const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { onSchedule } = require('firebase-functions/v2/scheduler');
admin.initializeApp();

// CLÉ SECRÈTE STRIPE (Récupération sécurisée via Secret Manager / Config Firebase / Environment Variables)
const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
if (!stripeSecretKey) {
    console.warn("⚠️ [ATTENTION] La clé secrète Stripe n'est pas configurée (process.env.STRIPE_SECRET_KEY).");
}
const stripe = stripeSecretKey ? require('stripe')(stripeSecretKey) : null;

// --- CONFIGURATION DES PRIX ---
// ID du prix "Compteur" (Commission variable) - Celui que vous aviez déjà
const METER_PRICE_ID = 'price_1Sf3OjJmX9VkIHA6i6tCmgeT';

// ID du prix "Visibilité Or" (Abonnement fixe 5€/mois)
// 1. Allez sur Stripe Dashboard > Produits > Ajouter un produit
// 2. Nom: "Option Visibilité Or", Prix: 5.00 EUR, Récurrent (Mensuel)
// 3. Copiez l'ID du prix (commence par price_...) et collez-le ci-dessous :
const GOLD_PRICE_ID = 'price_1SgZkvJmX9VkIHA6tTa42iTY';


// --- FONCTION 1 : CRÉATION DU MAGASIN ---
exports.createStripeShop = functions.https.onCall(async (data, context) => {
    console.log("🚀 [START] createStripeShop appelée !");

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Utilisateur non authentifié.');
    }

    if (!stripe) {
        throw new functions.https.HttpsError('failed-precondition', 'Le service Stripe n\'est pas configuré sur le serveur.');
    }

    const paymentMethodId = data.paymentMethodId;
    const email = data.email || context.auth.token.email;
    const name = data.name;
    // Récupération de l'option envoyée par Flutter
    const isVisibilityBoostEnabled = (data.is_visibility_boost_enabled === true || data.isVisibilityBoostEnabled === true);

    console.log(`📦 Données : Nom=${name}, Email=${email}, OptionOr=${isVisibilityBoostEnabled}`);

    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        throw new functions.https.HttpsError('invalid-argument', 'Adresse email invalide.');
    }

    if (!paymentMethodId) {
        throw new functions.https.HttpsError('invalid-argument', 'Moyen de paiement manquant.');
    }

    try {
        // 1. Création du Customer Stripe
        const customer = await stripe.customers.create({
            payment_method: paymentMethodId,
            email: email,
            name: name,
            invoice_settings: { default_payment_method: paymentMethodId },
        });

        // 2. Préparation des éléments de l'abonnement
        const itemsToSubscribe = [
            { price: METER_PRICE_ID } // Le compteur de base (obligatoire)
        ];

        // Si l'option Or est activée et que l'ID est configuré, on ajoute les 5€
        if (isVisibilityBoostEnabled && GOLD_PRICE_ID && GOLD_PRICE_ID.startsWith('price_')) {
            console.log("🌟 Option Visibilité Or activée : Ajout du prix fixe.");
            itemsToSubscribe.push({ price: GOLD_PRICE_ID });
        }

        // 3. Création de l'abonnement
        const subscription = await stripe.subscriptions.create({
            customer: customer.id,
            items: itemsToSubscribe,
        });

        console.log(`✅ Abonnement réussi : ${subscription.id}`);

        // On doit retrouver l'ID du "compteur" parmi les items pour pouvoir reporter l'usage plus tard.
        // On cherche l'item qui correspond au METER_PRICE_ID
        const meterItem = subscription.items.data.find(item => item.price.id === METER_PRICE_ID);

        // Sécurité : si on ne le trouve pas (cas rare), on prend le premier
        const itemId = meterItem ? meterItem.id : subscription.items.data[0].id;

        // Sauvegarde de l'ID d'abonnement côté serveur dans Firestore
        await admin.firestore().collection('users').doc(context.auth.uid).set({
            stripe_customer_id: customer.id,
            stripe_subscription_id: subscription.id,
            stripe_subscription_item_id: itemId,
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        return {
            customerId: customer.id,
            subscriptionId: subscription.id,
            subscriptionItemId: itemId
        };

    } catch (error) {
        console.error("❌ ERREUR CRITIQUE STRIPE :", error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// --- FONCTION 2 : DÉCLARATION DE COMMISSION (USAGE) ---
exports.reportCommission = functions.https.onCall(async (data, context) => {
    console.log("🚀 [START] reportCommission appelée");

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Utilisateur non authentifié.');
    }

    if (!stripe) {
        throw new functions.https.HttpsError('failed-precondition', 'Le service Stripe n\'est pas configuré sur le serveur.');
    }

    const subscriptionItemId = data.subscriptionItemId;
    const amountInCents = data.amountInCents;

    if (!subscriptionItemId || !amountInCents) {
        throw new functions.https.HttpsError('invalid-argument', 'Données manquantes.');
    }

    const quantity = parseInt(amountInCents);
    if (isNaN(quantity) || quantity <= 0 || quantity > 10000000) {
        throw new functions.https.HttpsError('invalid-argument', 'Montant de commission invalide.');
    }

    const userId = context.auth.uid;
    const userDoc = await admin.firestore().collection('users').doc(userId).get();
    const userData = userDoc.exists ? userDoc.data() : null;

    if (userData?.stripe_subscription_item_id && userData.stripe_subscription_item_id !== subscriptionItemId) {
        throw new functions.https.HttpsError('permission-denied', 'Cet abonnement ne vous appartient pas.');
    }

    try {
        await stripe.subscriptionItems.createUsageRecord(
            subscriptionItemId,
            {
                quantity: quantity,
                action: 'increment'
            }
        );
        console.log(`✅ Usage ajouté (+${quantity}) sur l'item ${subscriptionItemId}`);
        return { success: true };
    } catch (error) {
        console.error("❌ Erreur reportCommission :", error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// ════════════════════════════════════════════════════════════════════════════
// 🛡️ SECURE OCR - FONCTION 3 : DOCUMENT AI (Serveur sécurisé)
// ════════════════════════════════════════════════════════════════════════════
// Cette Cloud Function traite les images OCR en toute SÉCURITÉ :
// - Les clés API restent invisibles (stockées en tant que secret Google)
// - Aucune clé n'est exposée au client Flutter
// - Protège contre la surfacturation malveillante
// ════════════════════════════════════════════════════════════════════════════

const { DocumentProcessorServiceClient } = require('@google-cloud/documentai').v1;

// Configuration Document AI (sécurisée côté serveur)
const PROJECT_ID = '1087731109113';
const PROCESSOR_ID = 'bf5524b33f20120c';
const LOCATION = 'eu'; // Region: EU

async function verifyReceiptWithGeminiServer(extractedText, storeName) {
    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) {
        console.warn("⚠️ GEMINI_API_KEY serveur absente. Reçu refusé par précaution.");
        return { valid: false, reason: 'Clé d\'analyse IA non configurée sur le serveur.' };
    }

    try {
        const prompt = `Tu es un expert en vérification de tickets de caisse pour une application de cashback.
Voici le texte d'un ticket de caisse scanné dans le magasin "${storeName || 'Commerce'}":
---
${extractedText}
---
Vérifie les points suivants :
1. Le ticket appartient-il bien à l'enseigne "${storeName || 'Commerce'}" ?
2. Le ticket semble-t-il authentique ? N'y a-t-il pas de traces de retouches numériques, d'incohérences de police, ou de montages grossiers ?

Réponds EXCLUSIVEMENT sous la forme d'un objet JSON valide sans balises de code Markdown :
{"valid": true, "reason": ""} ou {"valid": false, "reason": "Motif explicatif"}`;

        const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;
        const response = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                contents: [{ parts: [{ text: prompt }] }]
            })
        });

        if (!response.ok) {
            console.error(`❌ Erreur HTTP Gemini API: ${response.status}`);
            return { valid: false, reason: 'Le service d\'analyse du reçu est indisponible.' };
        }

        const data = await response.json();
        const responseText = data?.candidates?.[0]?.content?.parts?.[0]?.text || '';
        const cleanedText = responseText.replace(/```(?:json)?/g, '').trim();
        let decoded;
        try {
            decoded = JSON.parse(cleanedText);
        } catch (jsonErr) {
            console.error("❌ Échec du parsing JSON Gemini:", cleanedText, jsonErr.message);
            return { valid: false, reason: "Erreur de format de la réponse IA." };
        }

        return {
            valid: decoded.valid === true,
            reason: decoded.reason || (decoded.valid ? '' : 'Ticket jugé non valide.')
        };
    } catch (err) {
        console.error("❌ Erreur validation Gemini serveur:", err.message);
        return { valid: false, reason: 'Erreur d\'analyse du ticket par le serveur.' };
    }
}

exports.processReceiptOCR = functions.https.onCall(async (data, context) => {
    console.log("🛡️ [SECURE] processReceiptOCR appelée via Cloud Function");

    // Vérification authentification Firebase
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const imageBase64 = data.imageBase64;
    const mimeType = data.mimeType || 'image/jpeg';
    const storeName = data.storeName || '';

    if (!imageBase64) {
        throw new functions.https.HttpsError('invalid-argument', 'Image base64 manquante');
    }

    // Protection anti-DoS/Surcharge : max 7MB de chaîne base64 (~5MB image binaire)
    if (imageBase64.length > 7 * 1024 * 1024) {
        throw new functions.https.HttpsError('invalid-argument', 'Image trop volumineuse (maximum 5 Mo autorisés).');
    }

    const userId = context.auth.uid;
    const userRef = admin.firestore().collection('users').doc(userId);
    const userDoc = await userRef.get();
    const lastOcrTime = userDoc.data()?.last_ocr_timestamp;
    const now = Date.now();

    if (lastOcrTime && (now - lastOcrTime.toMillis()) < 30000) {
        const remainingSec = Math.ceil((30000 - (now - lastOcrTime.toMillis())) / 1000);
        throw new functions.https.HttpsError('resource-exhausted', `Veuillez patienter ${remainingSec}s avant de scanner un autre reçu.`);
    }

    try {
        console.log(`📸 Traitement de l'image OCR (${imageBase64.length} bytes) pour l'enseigne "${storeName}"`);

        // Initialiser le client Document AI
        const client = new DocumentProcessorServiceClient({
            projectId: PROJECT_ID,
        });

        // Construire le chemin du processeur
        const name = client.processorPath(PROJECT_ID, LOCATION, PROCESSOR_ID);

        // Préparer le document
        const request = {
            name: name,
            rawDocument: {
                content: Buffer.from(imageBase64, 'base64'),
                mimeType: mimeType,
            },
        };

        // Appeler Document AI (serveur sécurisé)
        console.log(`🔐 Appel Document AI (Project: ${PROJECT_ID}, Processor: ${PROCESSOR_ID})`);
        const [result] = await client.processDocument(request);

        // Extraire le texte reconnu
        const document = result.document;
        const extractedText = document.text || '';

        console.log(`✅ OCR réussi: ${extractedText.length} caractères reconnus`);

        // Mettre à jour l'horodatage du dernier OCR
        await userRef.update({
            last_ocr_timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        // Analyse IA Gemini côté serveur (sans exposer de clé API au client)
        const geminiCheck = await verifyReceiptWithGeminiServer(extractedText, storeName);

        return {
            success: true,
            text: extractedText,
            valid: geminiCheck.valid,
            reason: geminiCheck.reason,
            confidence: document?.documentLayout?.blocks?.[0]?.confidence || 0.9,
        };

    } catch (error) {
        console.error("❌ Erreur Document AI / Gemini Server:", error.message);

        throw new functions.https.HttpsError(
            'internal',
            'Erreur serveur OCR/Gemini. Veuillez réessayer.'
        );
    }
});

// ════════════════════════════════════════════════════════════════════════════
// 🛡️ ARCHITECTURE SÉCURISÉE (SERVER-AUTHORITATIVE FUNCTIONS)
// ════════════════════════════════════════════════════════════════════════════

// --- FONCTION 4 : VALIDATION SERVEUR DES TRAJETS & ATTRIBUTION DES LAMES ---
exports.validateTrip = functions.https.onCall(async (data, context) => {
    console.log("🚀 [START] validateTrip appelée");

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const userId = context.auth.uid;
    const amountToAdd = Math.round(data.amountToAdd || 0);
    const source = data.source || 'Trajet';
    const isSpecialBonus = data.isSpecialBonus === true ||
        source.toLowerCase().includes('bonus') ||
        source.toLowerCase().includes('défi') ||
        source.toLowerCase().includes('defi') ||
        source.toLowerCase().includes('super');

    if (amountToAdd <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Montant de Lames invalide.');
    }

    // Protection anti-triche 1 : Plafond max absolu de Lames par trajet / action
    const maxCeiling = isSpecialBonus ? 5000 : 1500;

    if (amountToAdd > maxCeiling) {
        console.warn(`⚠️ [ANTI-TRICHE] Tentative d'attribution suspecte (${amountToAdd} Lames, max: ${maxCeiling}) par ${userId} (source: ${source})`);
        throw new functions.https.HttpsError('permission-denied', `Montant de Lames dépassant le plafond maximal autorisé (${maxCeiling}).`);
    }

    // Protection anti-triche 2 : Validation Physique Serveur (Vitesse & Ratio Distance/Lames)
    const distanceMeters = Number(data.distanceMeters || 0);
    const durationSeconds = Number(data.durationSeconds || 0);
    const travelMode = data.travelMode || 'walking';

    if (!isSpecialBonus && distanceMeters <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Distance de trajet invalide.');
    }

    if (distanceMeters > 0 && durationSeconds > 0 && !isSpecialBonus) {
        const speedKmh = (distanceMeters / 1000) / (durationSeconds / 3600);
        const maxPhysicalSpeed = travelMode === 'bicycling' ? 70.0 : (travelMode === 'transit' ? 140.0 : 35.0);

        if (speedKmh > maxPhysicalSpeed) {
            console.warn(`⚠️ [ANTI-TRICHE SERVEUR] Vitesse physiquement impossible: ${speedKmh.toFixed(1)} km/h en ${travelMode} par ${userId}`);
            throw new functions.https.HttpsError('permission-denied', `Vitesse physiquement impossible détectée (${speedKmh.toFixed(1)} km/h). Trajet rejeté.`);
        }

        // Vérification logique : maximum 150 Lames par km réellement parcouru (+ marge fixe pour bonus)
        const maxAllowedForDistance = Math.ceil((distanceMeters / 1000) * 150) + 50;
        if (amountToAdd > maxAllowedForDistance) {
            console.warn(`⚠️ [ANTI-TRICHE SERVEUR] Incohérence Lames/Distance: ${amountToAdd} Lames demandées pour ${(distanceMeters / 1000).toFixed(2)}km par ${userId}`);
            throw new functions.https.HttpsError('permission-denied', `Montant de Lames incohérent avec la distance parcourue.`);
        }
    }

    const userRef = admin.firestore().collection('users').doc(userId);

    try {
        await admin.firestore().runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Profil utilisateur introuvable.');
            }

            // Rate Limiter anti-spam : Cooldown de 10 minutes SEULEMENT pour les validations de trajet
            const isTripSource = source.toLowerCase().startsWith('trajet') || source === 'Trajet';

            if (isTripSource) {
                const lastTripTime = userDoc.data().last_trip_timestamp;
                const now = admin.firestore.Timestamp.now();

                if (lastTripTime) {
                    const elapsedMs = now.toMillis() - lastTripTime.toMillis();
                    if (elapsedMs < 10 * 60 * 1000) {
                        const remainingSec = Math.ceil((10 * 60 * 1000 - elapsedMs) / 1000);
                        throw new functions.https.HttpsError('resource-exhausted', `Vous allez trop vite ! Veuillez attendre ${remainingSec}s avant de valider un autre trajet.`);
                    }

                    // Anti-triche horloge : la durée du trajet ne peut pas dépasser le temps réel écoulé depuis la dernière validation (+ 120s tolérance)
                    const elapsedSec = elapsedMs / 1000;
                    if (durationSeconds > elapsedSec + 120) {
                        console.warn(`⚠️ [ANTI-TRICHE SERVEUR] Durée déclarée (${durationSeconds}s) supérieure au temps réel écoulé (${elapsedSec.toFixed(0)}s) pour ${userId}`);
                        throw new functions.https.HttpsError('permission-denied', `Durée de trajet incohérente avec le temps écoulé réel.`);
                    }
                }
            }

            const currentLame = userDoc.data().lame_points || 0;
            const currentTotalEarned = userDoc.data().total_lame_earned || 0;

            const updateData = {
                lame_points: currentLame + amountToAdd,
                total_lame_earned: currentTotalEarned + amountToAdd,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            };

            if (isTripSource) {
                updateData.last_trip_timestamp = admin.firestore.FieldValue.serverTimestamp();
            }

            transaction.update(userRef, updateData);

            const historyRef = userRef.collection('lame_history').doc();
            transaction.set(historyRef, {
                amount: amountToAdd,
                source: source,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });
        });

        console.log(`✅ [VALIDATION SERVEUR] ${amountToAdd} Lames créditées pour ${userId} (${source})`);
        return { success: true, amountAdded: amountToAdd };

    } catch (error) {
        console.error("❌ Erreur validateTrip :", error);
        if (error instanceof functions.https.HttpsError) throw error;
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// --- FONCTION 5 : ACHAT DE RÉCOMPENSE / BOUTIQUE SERVEUR ---
exports.purchaseShopItem = functions.https.onCall(async (data, context) => {
    console.log("🚀 [START] purchaseShopItem appelée");

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Non authentifié');
    }

    const userId = context.auth.uid;
    const itemId = data.itemId;
    const itemTitle = data.itemTitle || 'Achat Boutique';

    const userRef = admin.firestore().collection('users').doc(userId);

    try {
        const result = await admin.firestore().runTransaction(async (transaction) => {
            // 1. Le SERVEUR détermine et vérifie le prix réel de l'objet
            let actualCost = 0;
            if (!itemId) {
                throw new functions.https.HttpsError('invalid-argument', 'Identifiant de l\'objet (itemId) requis.');
            }

            const itemRef = admin.firestore().collection('shop_items').doc(itemId);
            const itemDoc = await transaction.get(itemRef);
            if (itemDoc.exists) {
                actualCost = Math.round(itemDoc.data().cost_lame || itemDoc.data().costLame || itemDoc.data().cost || 0);
            } else {
                const rewardRef = admin.firestore().collection('rewards').doc(itemId);
                const rewardDoc = await transaction.get(rewardRef);
                if (rewardDoc.exists) {
                    actualCost = Math.round(rewardDoc.data().cost_lame || rewardDoc.data().costLame || rewardDoc.data().cost || 0);
                } else {
                    throw new functions.https.HttpsError('not-found', 'Objet de boutique introuvable dans le catalogue.');
                }
            }

            if (data.cost && Math.round(data.cost) !== actualCost) {
                console.warn(`⚠️ [ALERTE SÉCURITÉ] Coût client (${data.cost}) ≠ coût serveur (${actualCost}) pour ${itemId} par ${userId}`);
            }

            if (actualCost <= 0) {
                throw new functions.https.HttpsError('invalid-argument', 'Prix de l\'objet invalide.');
            }

            // 2. Le SERVEUR vérifie l'utilisateur
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Profil utilisateur introuvable.');
            }

            const currentBalance = userDoc.data().lame_points || 0;
            if (currentBalance < actualCost) {
                throw new functions.https.HttpsError('failed-precondition', 'Solde de Lames insuffisant.');
            }

            const newBalance = currentBalance - actualCost;

            // 3. Application de l'achat
            transaction.update(userRef, {
                lame_points: newBalance,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });

            // Enregistrement de l'offre réclamée côté serveur (anti-triche)
            const claimedRef = admin.firestore().collection('user_claimed_offers').doc();
            transaction.set(claimedRef, {
                user_id: userId,
                user_email_contact: context.auth.token.email || 'inconnu',
                reward_id: itemId,
                details: { claimed_for_lame: actualCost, offer_title: itemTitle },
                claimed_at: admin.firestore.FieldValue.serverTimestamp(),
                status: 'approved'
            });

            const historyRef = userRef.collection('lame_history').doc();
            transaction.set(historyRef, {
                amount: -actualCost,
                source: `Achat: ${itemTitle}`,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });

            return { newBalance, actualCost };
        });

        console.log(`✅ [ACHAT SERVEUR] -${result.actualCost} Lames pour ${userId} (${itemTitle}). Nouveau solde: ${result.newBalance}`);
        return { success: true, newBalance: result.newBalance, costDeducted: result.actualCost };

    } catch (error) {
        console.error("❌ Erreur purchaseShopItem :", error);
        if (error instanceof functions.https.HttpsError) throw error;
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// --- FONCTION 6 : RÉCOMPENSE QUOTIDIENNE DE CONNEXION SERVEUR ---
exports.claimDailyReward = functions.https.onCall(async (data, context) => {
    console.log("🚀 [START] claimDailyReward appelée");

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const userId = context.auth.uid;
    const userRef = admin.firestore().collection('users').doc(userId);

    try {
        const result = await admin.firestore().runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Profil utilisateur introuvable.');
            }

            const userData = userDoc.data();
            const now = new Date();
            const todayStr = now.toISOString().split('T')[0];

            const lastLoginDate = userData.last_login_date ? userData.last_login_date.toDate() : null;
            const lastLoginStr = lastLoginDate ? lastLoginDate.toISOString().split('T')[0] : null;

            if (lastLoginStr === todayStr) {
                return { updated: false, message: "Récompense déjà récupérée aujourd'hui." };
            }

            let consecutiveLogins = userData.consecutive_logins || 0;
            if (lastLoginStr) {
                const lastDate = new Date(lastLoginStr);
                const todayDate = new Date(todayStr);
                const diffTime = Math.abs(todayDate - lastDate);
                const diffDays = Math.ceil(diffTime / (1000 * 60 * 60 * 24));
                if (diffDays === 1) {
                    consecutiveLogins += 1;
                } else if (diffDays > 1) {
                    consecutiveLogins = 1;
                }
            } else {
                consecutiveLogins = 1;
            }

            const paliersActuels = Math.floor(consecutiveLogins / 5);
            const bonusSerie = Math.min(paliersActuels * 0.1, 0.5);
            const newNextLevelBoost = 1.0 + bonusSerie;

            const currentLame = userData.lame_points || 0;
            const currentTotalEarned = userData.total_lame_earned || 0;

            // Ajout de +1 Lame et historique
            transaction.update(userRef, {
                consecutive_logins: consecutiveLogins,
                last_login_date: admin.firestore.FieldValue.serverTimestamp(),
                next_level_boost: newNextLevelBoost,
                lame_points: currentLame + 1,
                total_lame_earned: currentTotalEarned + 1,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });

            const historyRef = userRef.collection('lame_history').doc();
            transaction.set(historyRef, {
                amount: 1,
                source: 'Récompense quotidienne',
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });

            return { updated: true, consecutiveLogins, nextLevelBoost: newNextLevelBoost, newBalance: currentLame + 1, newTotalEarned: currentTotalEarned + 1 };
        });

        return { success: true, ...result };

    } catch (error) {
        console.error("❌ Erreur claimDailyReward :", error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// --- FONCTION 7 : ACHAT DE TICKETS DE LOTERIE (RAFFLE) SERVEUR ---
exports.purchaseRaffleTicket = functions.https.onCall(async (data, context) => {
    console.log("🚀 [START] purchaseRaffleTicket appelée");

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const userId = context.auth.uid;
    const contestId = data.contestId;
    const ticketCount = Math.round(data.ticketCount || 0);

    if (!contestId || ticketCount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Paramètres d\'achat de ticket invalides.');
    }

    const userRef = admin.firestore().collection('users').doc(userId);
    const userStatsRef = admin.firestore().collection('user_stats').doc(userId);
    const contestRef = admin.firestore().collection('contests').doc(contestId);

    try {
        const result = await admin.firestore().runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Profil utilisateur introuvable.');
            }

            let contestDoc = await transaction.get(contestRef);
            let contestData = contestDoc.exists ? contestDoc.data() : null;

            if (!contestDoc.exists) {
                const rewardRef = admin.firestore().collection('rewards').doc(contestId);
                const rewardDoc = await transaction.get(rewardRef);
                if (rewardDoc.exists) {
                    contestDoc = rewardDoc;
                    contestData = rewardDoc.data();
                } else {
                    throw new functions.https.HttpsError('not-found', 'Concours ou loterie introuvable.');
                }
            }

            if (contestData.status && contestData.status !== 'open') {
                throw new functions.https.HttpsError('failed-precondition', 'Le concours n\'est pas ouvert.');
            }

            const rawEndDate = contestData.end_date || contestData.endDate || contestData.details_json?.end_date;
            const endDate = rawEndDate ? (rawEndDate.toDate ? rawEndDate.toDate() : new Date(rawEndDate)) : null;
            if (endDate && new Date() > endDate) {
                throw new functions.https.HttpsError('failed-precondition', 'Ce concours est terminé.');
            }

            const ticketCostLame = Math.round(
                contestData?.details_json?.ticket_cost_eco ||
                contestData?.detailsJson?.ticket_cost_eco ||
                contestData?.eco_cost ||
                contestData?.ecoCost ||
                contestData?.cost_lame ||
                contestData?.costLame ||
                10
            );

            const totalCost = ticketCount * ticketCostLame;

            const currentLame = userDoc.data().lame_points || 0;
            if (currentLame < totalCost) {
                throw new functions.https.HttpsError('failed-precondition', `Fonds insuffisants (${currentLame} Lames disponibles, ${totalCost} requises).`);
            }

            const newBalance = currentLame - totalCost;

            // Déduction des lames (uniquement du solde disponible lame_points)
            transaction.update(userRef, {
                lame_points: newBalance,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });

            // Mise à jour de user_stats avec le total des Lames dépensées
            transaction.set(userStatsRef, {
                total_lames_spent: admin.firestore.FieldValue.increment(totalCost),
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

            // Incrémenter les tickets du concours
            const currentTickets = contestData.total_tickets_sold || 0;
            transaction.update(contestRef, {
                total_tickets_sold: currentTickets + ticketCount,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });

            // Ajouter la participation
            const entryRef = admin.firestore().collection('contest_entries').doc();
            transaction.set(entryRef, {
                contest_id: contestId,
                user_id: userId,
                entry_type: 'raffle_ticket',
                submission_data: {
                    ticket_count: ticketCount,
                    cost_per_ticket_eco: ticketCostLame
                },
                created_at: admin.firestore.FieldValue.serverTimestamp()
            });

            // Historique Lames
            const historyRef = userRef.collection('lame_history').doc();
            transaction.set(historyRef, {
                amount: -totalCost,
                source: `Achat Loterie (${ticketCount} ticket${ticketCount > 1 ? 's' : ''})`,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });

            return { newBalance, totalCost, ticketCount };
        });

        console.log(`✅ [RAFFLE SERVEUR] ${ticketCount} tickets achetés pour ${userId} (-${result.totalCost} Lames). Solde: ${result.newBalance}`);
        return { success: true, ...result };

    } catch (error) {
        console.error("❌ Erreur purchaseRaffleTicket :", error);
        if (error instanceof functions.https.HttpsError) throw error;
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// --- FONCTION 8 : ENCHÈRES SÉCURISÉES SERVEUR ---
exports.placeBid = functions.https.onCall(async (data, context) => {
    console.log("🚀 [START] placeBid appelée");

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const userId = context.auth.uid;
    const contestId = data.contestId;
    const bidAmount = parseFloat(data.bidAmount);

    if (!contestId || isNaN(bidAmount) || bidAmount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Paramètres d\'enchère invalides.');
    }

    const userRef = admin.firestore().collection('users').doc(userId);
    const contestRef = admin.firestore().collection('contests').doc(contestId);

    try {
        const result = await admin.firestore().runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Profil utilisateur introuvable.');
            }

            let contestDoc = await transaction.get(contestRef);
            if (!contestDoc.exists) {
                const rewardRef = admin.firestore().collection('rewards').doc(contestId);
                const rewardDoc = await transaction.get(rewardRef);
                if (rewardDoc.exists) {
                    contestDoc = rewardDoc;
                } else {
                    throw new functions.https.HttpsError('not-found', 'Enchère introuvable.');
                }
            }

            const contestData = contestDoc.data();
            const currentHighestBid = parseFloat(contestData.current_highest_bid || contestData.currentHighestBid || 0);
            const minBid = parseFloat(contestData.min_bid || contestData.minBid || 10);

            if (contestData.status && contestData.status !== 'open') {
                throw new functions.https.HttpsError('failed-precondition', 'L\'enchère n\'est pas ouverte.');
            }

            const rawEndDate = contestData.end_date || contestData.endDate || contestData.details_json?.end_date;
            const endDate = rawEndDate ? (rawEndDate.toDate ? rawEndDate.toDate() : new Date(rawEndDate)) : null;
            if (endDate && new Date() > endDate) {
                throw new functions.https.HttpsError('failed-precondition', 'Cette enchère est terminée.');
            }

            const minNextBid = currentHighestBid > 0 ? currentHighestBid + 1.0 : minBid;
            if (bidAmount < minNextBid) {
                throw new functions.https.HttpsError('failed-precondition', `L'enchère doit être d'au moins ${minNextBid} Lames.`);
            }

            const oldBidderId = contestData.highest_bidder_user_id || contestData.highestBidderUserId;

            let amountToDeduct = bidAmount;
            if (oldBidderId && oldBidderId === userId) {
                // L'utilisateur se surenchérit lui-même : on ne déduit que la différence
                amountToDeduct = bidAmount - currentHighestBid;
            }

            const userLame = userDoc.data().lame_points || 0;
            if (userLame < amountToDeduct) {
                throw new functions.https.HttpsError('failed-precondition', `Solde de Lames insuffisant (${userLame} disponibles, ${amountToDeduct} requises pour cette surenchère).`);
            }

            // Rembourser l'ancien enchérisseur s'il s'agit d'une autre personne
            if (oldBidderId && oldBidderId !== userId) {
                const oldBidderRef = admin.firestore().collection('users').doc(oldBidderId);
                transaction.update(oldBidderRef, {
                    lame_points: admin.firestore.FieldValue.increment(currentHighestBid),
                    updated_at: admin.firestore.FieldValue.serverTimestamp()
                });

                const refundHistoryRef = oldBidderRef.collection('lame_history').doc();
                transaction.set(refundHistoryRef, {
                    amount: currentHighestBid,
                    source: `Remboursement Enchère (Surenchéri)`,
                    timestamp: admin.firestore.FieldValue.serverTimestamp()
                });
            }

            // Débiter le nouvel enchérisseur (ou ajuster en cas d'auto-surenchère) avec FieldValue.increment
            const newBalance = userLame - amountToDeduct;
            transaction.update(userRef, {
                lame_points: admin.firestore.FieldValue.increment(-amountToDeduct),
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });

            // Mettre à jour le document de l'enchère
            transaction.update(contestDoc.ref, {
                current_highest_bid: bidAmount,
                highest_bidder_user_id: userId,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });

            // Ajouter l'entrée dans contest_entries
            const entryRef = admin.firestore().collection('contest_entries').doc();
            transaction.set(entryRef, {
                contest_id: contestId,
                user_id: userId,
                entry_type: 'bid',
                submission_data: { bid_amount: bidAmount },
                created_at: admin.firestore.FieldValue.serverTimestamp()
            });

            // Historique Lames
            const historyRef = userRef.collection('lame_history').doc();
            transaction.set(historyRef, {
                amount: -amountToDeduct,
                source: `Enchère: ${contestData.product_name || contestData.title || contestId}`,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });

            return { newBalance, bidAmount };
        });

        console.log(`✅ [ENCHÈRE SERVEUR] Enchère de ${bidAmount} Lames placée pour ${userId} sur ${contestId}. Nouveau solde: ${result.newBalance}`);
        return { success: true, ...result };

    } catch (error) {
        console.error("❌ Erreur placeBid :", error);
        if (error instanceof functions.https.HttpsError) throw error;
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// ════════════════════════════════════════════════════════════════════════════
// --- FONCTION 8 : OPTIMISATION CLASSEMENT (SCHEDULED 1H -> 1 READ FIRESTORE) ---
// ════════════════════════════════════════════════════════════════════════════
exports.updateDailyLeaderboard = onSchedule('every 1 hours', async (event) => {
    console.log("🚀 [SCHEDULED] Agrégation du Top 100 dans leaderboards/daily_top");

    try {
        const snapshot = await admin.firestore()
            .collection('users')
            .orderBy('total_lame_earned', 'desc')
            .limit(100)
            .get();

        const entries = snapshot.docs.map((doc, index) => {
            const data = doc.data();
            return {
                rank: index + 1,
                id: doc.id,
                username: data.username || 'EcoNavigo',
                total_lame_earned: data.total_lame_earned || 0,
                lame_points: data.lame_points || 0,
                current_level: data.current_level || 1,
                country: data.country || 'Monde',
                unlocked_badges: data.unlocked_badges || [],
                friend_ids: data.friend_ids || []
            };
        });

        await admin.firestore().collection('leaderboards').doc('daily_top').set({
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
            entries: entries,
            count: entries.length
        });

        console.log(`✅ [LEADERBOARD] ${entries.length} utilisateurs agrégés dans leaderboards/daily_top (1 seule lecture Firestore pour les clients)`);
        return null;
    } catch (error) {
        console.error("❌ Erreur mise à jour classement:", error);
        return null;
    }
});

// ════════════════════════════════════════════════════════════════════════════
// --- FONCTION 9 : SUPPRESSION DU COMPTE & DONNÉES (RGPD ARTICLE 17 & APP STORE) ---
// ════════════════════════════════════════════════════════════════════════════
exports.deleteUserAccount = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const userId = context.auth.uid;
    console.log(`⚠️ [RGPD] Suppression définitive du compte et des données pour ${userId}`);

    try {
        const userRef = admin.firestore().collection('users').doc(userId);

        // 1. Supprimer l'historique des lames
        const historyDocs = await userRef.collection('lame_history').get();
        const batch = admin.firestore().batch();
        historyDocs.forEach(doc => batch.delete(doc.ref));
        await batch.commit();

        // 2. Supprimer les offres réclamées de l'utilisateur
        const claims = await admin.firestore().collection('user_claimed_offers').where('user_id', '==', userId).get();
        const claimsBatch = admin.firestore().batch();
        claims.forEach(doc => claimsBatch.delete(doc.ref));
        await claimsBatch.commit();

        // 3. Supprimer le document profil utilisateur
        await userRef.delete();

        // 4. Supprimer le compte Firebase Auth
        await admin.auth().deleteUser(userId);

        console.log(`✅ [RGPD] Compte et données de ${userId} définitivement supprimés.`);
        return { success: true };
    } catch (error) {
        console.error("❌ Erreur suppression de compte:", error);
        if (error instanceof functions.https.HttpsError) throw error;
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// ===========================================================================
// 🛡️ NOUVEAU : ANTI-TRICHE POUR LES PUBS, BOOSTS ET DONS
// ===========================================================================

// --- 1. Regarder une pub générale (Ad Points) ---
exports.addAdPoint = functions.https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Non autorisé');
    
    const userRef = admin.firestore().collection('users').doc(context.auth.uid);
    
    return admin.firestore().runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const currentPoints = userDoc.data().ad_points || 0;
        
        if (currentPoints >= 50) {
            throw new functions.https.HttpsError('resource-exhausted', 'Max Ad Points atteints.');
        }
        
        const newPoints = currentPoints + 1;
        transaction.update(userRef, {
            ad_points: newPoints,
            last_ad_point_decay_time: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
        
        return { newAdPoints: newPoints };
    });
});

// --- 2. Regarder une pub pour un magasin (Boost Cashback) ---
exports.addStoreBoost = functions.https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Non autorisé');
    
    const storeId = data.storeId;
    if (!storeId) throw new functions.https.HttpsError('invalid-argument', 'Store ID manquant');

    const userRef = admin.firestore().collection('users').doc(context.auth.uid);
    const storeRef = admin.firestore().collection('stores').doc(storeId);

    return admin.firestore().runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const storeDoc = await transaction.get(storeRef);

        const isVip = userDoc.data().is_vip === true;
        const storeHasBoost = storeDoc.exists && storeDoc.data().is_premium_ad_boost_enabled === true;
        const cashbackRate = storeDoc.exists ? (storeDoc.data().cashback_rate || 0.05) : 0.05;

        const effectivelySuperPremium = isVip && storeHasBoost;
        const effectivelyPremium = isVip || storeHasBoost;

        const storeBoosts = userDoc.data().store_boosts || {};
        const currentBoost = storeBoosts[storeId]?.amount || 0.0;

        let gain = 0.01;
        if (currentBoost >= 1.0) {
            gain = effectivelySuperPremium ? 0.8 : (effectivelyPremium ? 0.4 : 0.2);
        } else {
            gain = effectivelySuperPremium ? 0.04 : (effectivelyPremium ? 0.02 : 0.01);
        }

        let maxCap = Math.max(cashbackRate * 100.0, 1.0);
        let newAmount = Math.min(currentBoost + gain, maxCap);

        transaction.set(userRef, {
            store_boosts: { 
                [storeId]: { 
                    amount: newAmount, 
                    last_update: admin.firestore.FieldValue.serverTimestamp() 
                } 
            }
        }, { merge: true });

        return { 
            newAmount: newAmount, 
            gain: gain,
            maxReached: newAmount === maxCap, 
            effectivelySuperPremium: effectivelySuperPremium 
        };
    });
});

// --- 3. Dépenser des lames (Dons, Arbres, Virements) ---
exports.processDonation = functions.https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Non autorisé');
    
    const { amount, offerId, offerTitle, email, isInstantApproval } = data;
    
    const userId = context.auth.uid;
    const userRef = admin.firestore().collection('users').doc(userId);
    const claimedRef = admin.firestore().collection('user_claimed_offers').doc();

    return admin.firestore().runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Profil utilisateur introuvable.');
        }

        let cost = parseFloat(amount);

        if (offerId) {
            const rewardRef = admin.firestore().collection('rewards').doc(offerId);
            const rewardDoc = await transaction.get(rewardRef);
            if (rewardDoc.exists) {
                const rData = rewardDoc.data();
                const fetchedCost = rData.eco_cost ?? rData.ecoCost ?? rData.cost_lame ?? rData.costLame ?? rData.cost;
                if (fetchedCost !== undefined && fetchedCost !== null && !isNaN(parseFloat(fetchedCost))) {
                    cost = parseFloat(fetchedCost);
                }

                // Si c'est une campagne solidaires (avec details_json), enregistrer le don sur la campagne
                if (rData.details_json) {
                    const currentDetails = rData.details_json || {};
                    const currentAmt = Number(currentDetails.current_amount_eco || 0);
                    const currentDonors = Number(currentDetails.current_donors || 0);
                    currentDetails.current_amount_eco = currentAmt + cost;
                    currentDetails.current_donors = currentDonors + 1;

                    transaction.update(rewardRef, {
                        details_json: currentDetails,
                        updated_at: admin.firestore.FieldValue.serverTimestamp()
                    });
                }
            }
        }

        if (isNaN(cost) || cost <= 0) {
            throw new functions.https.HttpsError('invalid-argument', 'Montant invalide. Triche détectée.');
        }

        const currentLame = userDoc.data().lame_points || 0;

        if (currentLame < cost) {
            throw new functions.https.HttpsError('failed-precondition', 'Fonds insuffisants.');
        }

        // Déduction des points
        transaction.update(userRef, { 
            lame_points: admin.firestore.FieldValue.increment(-cost),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });

        // Enregistrement de la demande
        transaction.set(claimedRef, {
            user_id: userId,
            user_email_contact: email || 'inconnu',
            reward_id: offerId || 'donation',
            details: { claimed_for_lame: cost, offer_title: offerTitle || 'Offre / Don' },
            claimed_at: admin.firestore.FieldValue.serverTimestamp(),
            status: isInstantApproval ? 'approved' : 'pending',
        });
        
        // Historique
        const historyRef = userRef.collection('lame_history').doc();
        transaction.set(historyRef, {
            amount: -cost,
            source: `Dépense : ${offerTitle || 'Offre'}`,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        return { success: true, newBalance: currentLame - cost };
    });
});

// --- 4. Valider un Ticket de Caisse et Calculer le Cashback ---
exports.claimCashback = functions.https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Non autorisé');

    const { storeId, amountSpent, rawText } = data;
    let amount = parseFloat(amountSpent);

    if (!storeId || isNaN(amount) || amount <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Données de ticket invalides.');
    }

    // Plafond de sécurité anti-triche : max 100€ par ticket
    if (amount > 100.0) {
        amount = 100.0;
    }

    const userId = context.auth.uid;
    const userRef = admin.firestore().collection('users').doc(userId);
    const storeRef = admin.firestore().collection('stores').doc(storeId);

    return admin.firestore().runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const storeDoc = await transaction.get(storeRef);

        if (!userDoc.exists || !storeDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Utilisateur ou magasin introuvable.');
        }

        const userData = userDoc.data();
        const storeData = storeDoc.data();

        // 1. Calcul des taux (Le serveur récupère les vraies données)
        let baseRate = (storeData.cashback_rate || 0.05) * 100.0;
        if (storeData.is_visibility_boost_enabled) baseRate += 1.0;

        const storeBoosts = userData.store_boosts || {};
        const boostAddon = storeBoosts[storeId]?.amount || 0.0;

        // 2. Calcul de la fidélité
        let loyaltyDiscount = 0.0;
        let loyaltyTierLabel = "";
        const loyaltyProgress = userData.loyalty_progress || {};
        const storeProgress = loyaltyProgress[storeId] || { visits: 0, spend: 0 };
        
        const rules = storeData.loyalty_rules || [];
        for (const rule of rules) {
            const reached = rule.type === 'visit' ? storeProgress.visits >= rule.threshold : storeProgress.spend >= rule.threshold;
            if (reached && rule.rewardPercent > loyaltyDiscount) {
                loyaltyDiscount = rule.rewardPercent;
                loyaltyTierLabel = rule.type === 'visit' ? `Palier ${rule.threshold} visites` : `Palier ${rule.threshold}€`;
            }
        }

        const totalRate = baseRate + boostAddon + loyaltyDiscount;
        const cashbackAmount = amount * (totalRate / 100.0);

        // 3. Calcul du Bonus de Lames en fonction du Niveau
        const totalLameEarned = userData.total_lame_earned || 0;
        let currentLevel = 1;
        let lameNeeded = 500;
        let totalForLevel = 0;
        while (totalLameEarned >= totalForLevel + lameNeeded && currentLevel < 50) {
            totalForLevel += lameNeeded;
            currentLevel++;
            lameNeeded *= 2;
        }
        const levelMultiplier = 1.0 + (currentLevel * 0.01);
        const lameBonus = Math.round((cashbackAmount * 10) * levelMultiplier);

        // --- 4. ÉCRITURES SÉCURISÉES ---
        
        // Mise à jour de l'utilisateur
        transaction.update(userRef, {
            lame_points: admin.firestore.FieldValue.increment(lameBonus),
            total_lame_earned: admin.firestore.FieldValue.increment(lameBonus),
            [`loyalty_progress.${storeId}.visits`]: admin.firestore.FieldValue.increment(1),
            [`loyalty_progress.${storeId}.spend`]: admin.firestore.FieldValue.increment(amount)
        });

        // Historique des Lames
        if (lameBonus > 0) {
            const historyRef = userRef.collection('lame_history').doc();
            transaction.set(historyRef, {
                amount: lameBonus,
                source: `Cashback ${storeData.name || 'Magasin'}`,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });
        }

        // Historique du Cashback
        const cbHistoryRef = userRef.collection('cashback_history').doc();
        transaction.set(cbHistoryRef, {
            store_id: storeId,
            store_name: storeData.name || 'Magasin',
            amount_spent: amount,
            cashback_amount: cashbackAmount,
            cashback_rate_applied: totalRate,
            lame_points_earned: lameBonus,
            loyalty_tier_applied: loyaltyTierLabel || null,
            receipt_text_raw: rawText || '',
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        // Transaction Commerçant & Stats
        const storeTxRef = storeRef.collection('store_transactions').doc();
        transaction.set(storeTxRef, {
            user_id: userId,
            username: userData.username || 'Anonyme',
            amount_spent: amount,
            cashback_given: cashbackAmount,
            rate_applied: totalRate,
            loyalty_tier: loyaltyTierLabel || null,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        transaction.update(storeRef, {
            totalAmountSpentByUser: admin.firestore.FieldValue.increment(amount),
            totalCashbackGiven: admin.firestore.FieldValue.increment(cashbackAmount)
        });

        return { cashbackAmount, lameBonus, totalRate };
    });
});