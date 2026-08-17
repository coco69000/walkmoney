const functions = require('firebase-functions');
const admin = require('firebase-admin');
const crypto = require('crypto');
const { onSchedule } = require('firebase-functions/v2/scheduler');
admin.initializeApp();

// Helper : Vérification Firebase App Check
const verifyAppCheck = (context) => {
    if (!context.app && process.env.FUNCTIONS_EMULATOR !== 'true') {
        throw new functions.https.HttpsError(
            'failed-precondition',
            'L\'appel doit provenir d\'une application officielle authentifiée (App Check).'
        );
    }
};

// Helper : Calcul du Niveau Serveur et Promotion VIP automatique (Niveau 30+)
function checkAndApplyVipStatus(totalLameEarned, updateObject) {
    let currentLevel = 1;
    let lameNeeded = 500;
    let totalForLevel = 0;
    while (totalLameEarned >= totalForLevel + lameNeeded && currentLevel < 50) {
        totalForLevel += lameNeeded;
        currentLevel++;
        lameNeeded *= 2;
    }
    if (currentLevel >= 30) {
        updateObject.is_vip = true;
    }
    return currentLevel;
}

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
    verifyAppCheck(context);
    console.log("🚀 [START] createStripeShop appelée !");

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Utilisateur non authentifié.');
    }

    if (!stripe) {
        throw new functions.https.HttpsError('failed-precondition', 'Le service Stripe n\'est pas configuré sur le serveur.');
    }

    const userId = context.auth.uid;
    const userRef = admin.firestore().collection('users').doc(userId);
    const userDoc = await userRef.get();
    if (userDoc.exists && userDoc.data()?.stripe_subscription_id) {
        throw new functions.https.HttpsError('already-exists', 'Vous possédez déjà un abonnement magasin actif.');
    }

    const paymentMethodId = data.paymentMethodId;
    const email = context.auth.token ? context.auth.token.email : null;
    const name = data.name;
    // Récupération de l'option envoyée par Flutter
    const isVisibilityBoostEnabled = (data.is_visibility_boost_enabled === true || data.isVisibilityBoostEnabled === true);

    console.log(`📦 Données : Nom=${name}, Email=${email}, OptionOr=${isVisibilityBoostEnabled}`);

    if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
        throw new functions.https.HttpsError('failed-precondition', 'Aucune adresse e-mail valide associée à ce compte Firebase Token.');
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

        // Optimisation : enregistrer également l'item ID sur les magasins du propriétaire pour accélérer le cashback
        const ownerStores = await admin.firestore().collection('stores').where('owner_id', '==', context.auth.uid).get();
        if (!ownerStores.empty) {
            const batch = admin.firestore().batch();
            ownerStores.docs.forEach(doc => {
                batch.update(doc.ref, {
                    stripe_subscription_id: subscription.id,
                    stripe_subscription_item_id: itemId,
                    updated_at: admin.firestore.FieldValue.serverTimestamp()
                });
            });
            await batch.commit();
        }

        return {
            customerId: customer.id,
            subscriptionId: subscription.id
        };
    } catch (error) {
        console.error("❌ ERREUR CRITIQUE STRIPE :", error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// (Note: La déclaration de commission Stripe est gérée automatiquement de façon sécurisée à la fin de claimCashback)

// ════════════════════════════════════════════════════════════════════════════
// 🛡️ SECURE OCR - NVIDIA NIM (Llama 3.2 Vision)
// ════════════════════════════════════════════════════════════════════════════
// Remplace Document AI + Gemini par NVIDIA NIM (OCR + Analyse en une requête)
// ════════════════════════════════════════════════════════════════════════════

const NVIDIA_API_KEY = (functions.config().nvidia && functions.config().nvidia.api_key) || process.env.NVIDIA_API_KEY || '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';
const NVIDIA_API_URL = 'https://integrate.api.nvidia.com/v1/chat/completions';

async function analyzeReceiptWithNvidia(base64Image, mimeType, storeName) {
    if (!NVIDIA_API_KEY) {
        console.warn("⚠️ NVIDIA_API_KEY absente. Reçu refusé par précaution.");
        return { valid: false, reason: 'Clé API NVIDIA non configurée.', extractedText: '', amount: null };
    }

    const safeStoreName = (storeName || 'Commerce').replace(/[^a-zA-Z0-9\s\-\.\'\&]/g, '').trim().substring(0, 50) || 'Commerce';

    const prompt = `Tu es un expert en vérification de tickets de caisse pour une application de cashback.
Analyse cette image de ticket de caisse qui devrait provenir du magasin "${safeStoreName}".

Tu dois :
1. Extraire tout le texte visible du ticket (OCR)
2. Vérifier si le ticket semble authentique (pas de montage, pas de retouche)
3. Vérifier si le nom du magasin sur le ticket correspond à "${safeStoreName}"
4. Extraire le montant total TTC/NET du ticket
5. Extraire la date et l'heure du ticket

Réponds EXCLUSIVEMENT avec un objet JSON valide (sans balises markdown) :
{
  "valid": true/false,
  "reason": "explication si invalide, sinon vide",
  "extractedText": "tout le texte du ticket",
  "storeNameFound": "nom du magasin trouvé sur le ticket",
  "amount": nombre_decimal_ou_null,
  "date": "JJ/MM/AAAA HH:MM ou null",
  "isReceipt": true/false (est-ce bien un ticket de caisse ?)
}`;

    try {
        const response = await fetch(NVIDIA_API_URL, {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${NVIDIA_API_KEY}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                model: 'meta/llama-3.2-11b-vision-instruct',
                messages: [
                    {
                        role: 'user',
                        content: [
                            { type: 'text', text: prompt },
                            {
                                type: 'image_url',
                                image_url: {
                                    url: `data:${mimeType};base64,${base64Image}`
                                }
                            }
                        ]
                    }
                ],
                max_tokens: 1024,
                temperature: 0.1
            })
        });

        if (!response.ok) {
            console.error(`❌ Erreur NVIDIA API: ${response.status}`);
            const errorText = await response.text();
            console.error('Détails:', errorText);
            return { valid: false, reason: 'Service d\'analyse indisponible.', extractedText: '', amount: null };
        }

        const data = await response.json();
        const responseText = data?.choices?.[0]?.message?.content || '';

        // Nettoyer la réponse (enlever les balises markdown si présentes)
        const cleanedText = responseText
            .replace(/```json\s*/g, '')
            .replace(/```\s*/g, '')
            .trim();

        let parsed;
        try {
            parsed = JSON.parse(cleanedText);
        } catch (jsonErr) {
            console.error("❌ Échec parsing JSON NVIDIA:", cleanedText);
            // Essayer d'extraire un JSON partiel
            const jsonMatch = cleanedText.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
                try {
                    parsed = JSON.parse(jsonMatch[0]);
                } catch (e) {
                    return { valid: false, reason: 'Format de réponse invalide.', extractedText: '', amount: null };
                }
            } else {
                return { valid: false, reason: 'Réponse non structurée.', extractedText: cleanedText, amount: null };
            }
        }

        return {
            valid: parsed.valid === true && parsed.isReceipt === true,
            reason: parsed.reason || '',
            extractedText: parsed.extractedText || '',
            storeNameFound: parsed.storeNameFound || '',
            amount: parsed.amount || null,
            date: parsed.date || null
        };

    } catch (err) {
        console.error("❌ Erreur NVIDIA NIM:", err.message);
        return { valid: false, reason: 'Erreur de connexion au service d\'analyse.', extractedText: '', amount: null };
    }
}

exports.processReceiptOCR = functions.runWith({ memory: '1GB', timeoutSeconds: 120 }).https.onCall(async (data, context) => {
    verifyAppCheck(context);
    console.log("🛡️ [SECURE] processReceiptOCR via NVIDIA NIM");

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const imageBase64 = data.imageBase64;
    const mimeType = data.mimeType || 'image/jpeg';
    const rawStoreName = data.storeName || '';
    const safeStoreName = rawStoreName.replace(/[^a-zA-Z0-9\s\-\.\'\&]/g, '').trim().substring(0, 50) || 'Commerce';

    if (!imageBase64) {
        throw new functions.https.HttpsError('invalid-argument', 'Image base64 manquante');
    }

    if (imageBase64.length > 7 * 1024 * 1024) {
        throw new functions.https.HttpsError('invalid-argument', 'Image trop volumineuse (maximum 5 Mo).');
    }

    const userId = context.auth.uid;
    const statsRef = admin.firestore().collection('user_stats').doc(userId);
    const now = Date.now();

    // Anti-spam : 30 secondes entre chaque scan
    await admin.firestore().runTransaction(async (transaction) => {
        const statsDoc = await transaction.get(statsRef);
        const statsData = statsDoc.exists ? statsDoc.data() : {};
        const lastOcrTime = statsData.last_ocr_timestamp;

        if (lastOcrTime && (now - lastOcrTime.toMillis()) < 30000) {
            const remainingSec = Math.ceil((30000 - (now - lastOcrTime.toMillis())) / 1000);
            throw new functions.https.HttpsError('resource-exhausted', `Patientez ${remainingSec}s avant un nouveau scan.`);
        }

        transaction.set(statsRef, {
            last_ocr_timestamp: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });
    });

    try {
        console.log(`📸 Analyse NVIDIA NIM pour "${safeStoreName}"`);

        // Appel à NVIDIA NIM (OCR + Analyse en une requête)
        const analysis = await analyzeReceiptWithNvidia(imageBase64, mimeType, safeStoreName);

        console.log(`✅ Analyse terminée. Valid: ${analysis.valid}, Montant: ${analysis.amount}`);

        // Création du jeton de validation si valide
        let receiptToken = null;
        if (analysis.valid) {
            receiptToken = crypto.randomBytes(16).toString('hex');
            const expiresAt = admin.firestore.Timestamp.fromDate(new Date(Date.now() + 5 * 60 * 1000));

            await admin.firestore().collection('ocr_validations').doc(receiptToken).set({
                user_id: userId,
                store_name: safeStoreName,
                extracted_text: analysis.extractedText,
                extracted_amount: analysis.amount,
                extracted_date: analysis.date,
                store_name_found: analysis.storeNameFound,
                created_at: admin.firestore.FieldValue.serverTimestamp(),
                expires_at: expiresAt,
                used: false
            });
            console.log(`🔑 Jeton généré : ${receiptToken}`);
        }

        return {
            success: true,
            receiptToken: receiptToken,
            text: analysis.extractedText,
            valid: analysis.valid,
            reason: analysis.reason,
            amount: analysis.amount,
            date: analysis.date,
            storeNameFound: analysis.storeNameFound,
            confidence: 0.95
        };

    } catch (error) {
        console.error("❌ Erreur NVIDIA NIM:", error.message);
        throw new functions.https.HttpsError('internal', 'Erreur d\'analyse. Veuillez réessayer.');
    }
});

// ════════════════════════════════════════════════════════════════════════════
// 🛡️ ARCHITECTURE SÉCURISÉE (SERVER-AUTHORITATIVE FUNCTIONS)
// ════════════════════════════════════════════════════════════════════════════

// --- FONCTION 4 : VALIDATION SERVEUR DES TRAJETS & ATTRIBUTION DES LAMES (ENRICHI) ---
exports.validateTrip = functions.https.onCall(async (data, context) => {
    verifyAppCheck(context);
    console.log("🚀 [START] validateTrip appelée");

    // VÉRIFICATION D'AUTHENTIFICATION RENFORCÉE
    if (!context.auth || !context.auth.uid) {
        console.warn("⚠️ [AUTH] Requête rejetée : context.auth est null. Le client n'a pas envoyé de token valide (token expiré ou utilisateur déconnecté).");
        throw new functions.https.HttpsError('unauthenticated', 'Session expirée. Veuillez vous reconnecter dans l\'application.');
    }

    const userId = context.auth.uid;
    const source = data.source || 'Trajet';
    const challengeId = data.challengeId || null;
    const tripId = data.tripId || null; // 🆕 L'ID du document trip_logs

    // 🚨 FIX 1 : tripId est STRICTEMENT OBLIGATOIRE pour les trajets normaux (hors défis)
    if (!challengeId && !tripId) {
        throw new functions.https.HttpsError('invalid-argument', 'ID de trajet manquant (tripId obligatoire).');
    }

    const travelMode = data.travelMode || 'walking';
    const cheatDetected = data.cheatDetected || false;
    const cheatReason = data.cheatReason || null;
    const startLocation = data.startLocation || null;
    const endLocation = data.endLocation || null;

    // Validation des défis globales
    let isVerifiedChallenge = false;
    let challengeReward = 0;
    if (challengeId) {
        const challengeDoc = await admin.firestore().collection('challenges').doc(challengeId).get();
        if (challengeDoc.exists && challengeDoc.data().active !== false) {
            isVerifiedChallenge = true;
            const cData = challengeDoc.data();
            challengeReward = Math.round(cData.reward_lame ?? cData.reward ?? 0);
            if (challengeReward <= 0) {
                throw new functions.https.HttpsError('invalid-argument', 'Récompense du défi non valide.');
            }
        } else {
            throw new functions.https.HttpsError('not-found', 'Défi ou bonus introuvable ou expiré.');
        }
    }

    // Pour un défi, la récompense est strictement imposée par le serveur depuis Firestore (ignore le client)
    const amountToAdd = isVerifiedChallenge ? challengeReward : Math.round(data.amountToAdd || 0);

    if (amountToAdd <= 0) {
        throw new functions.https.HttpsError('invalid-argument', 'Montant de Lames invalide.');
    }

    // 🛡️ ANTI-TRICHE 1 : Si le client a déjà détecté une triche, on rejette immédiatement
    if (cheatDetected && !isVerifiedChallenge) {
        console.warn(`⚠️ [ANTI-TRICHE CLIENT] Trajet rejeté (${cheatReason}) par ${userId}`);
        throw new functions.https.HttpsError('permission-denied', `Trajet invalide : ${cheatReason}`);
    }

    // Anti-triche 2 : Plafond max absolu de Lames par trajet / action (1500 pour trajets, 5000 pour défis vérifiés DB)
    const maxCeiling = isVerifiedChallenge ? 5000 : 1500;
    if (amountToAdd > maxCeiling) {
        console.warn(`⚠️ [ANTI-TRICHE] Tentative d'attribution suspecte (${amountToAdd} Lames, max: ${maxCeiling}) par ${userId} (source: ${source})`);
        throw new functions.https.HttpsError('permission-denied', `Montant de Lames dépassant le plafond maximal autorisé (${maxCeiling}).`);
    }

    const userRef = admin.firestore().collection('users').doc(userId);
    const statsRef = admin.firestore().collection('user_stats').doc(userId);

    try {
        await admin.firestore().runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            const statsDoc = await transaction.get(statsRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Profil utilisateur introuvable.');
            }
            const statsData = statsDoc.exists ? statsDoc.data() : {};

            let dbDistanceMeters = Number(data.distanceMeters || 0);
            let dbDurationSeconds = Number(data.durationSeconds || 0);

            // 🚨 FIX 1 & 3 : VÉRIFICATION SERVEUR DES DONNÉES EN BD (trip_logs)
            if (tripId && !isVerifiedChallenge) {
                const tripRef = userRef.collection('trip_logs').doc(tripId);
                const tripDoc = await transaction.get(tripRef);
                if (!tripDoc.exists) {
                    throw new functions.https.HttpsError('not-found', 'Journal de trajet introuvable en base de données.');
                }

                const tripLogData = tripDoc.data();
                if (tripLogData.cheat_detected === true) {
                    throw new functions.https.HttpsError('permission-denied', 'Trajet marqué comme triché par le système.');
                }
                if (tripLogData.validation_status === 'validated') {
                    throw new functions.https.HttpsError('already-exists', 'Ce trajet a déjà été validé.');
                }

                // Récupération stricte depuis la BD pour les calculs anti-triche
                dbDistanceMeters = Number(tripLogData.actual_distance_meters ?? dbDistanceMeters);
                dbDurationSeconds = Number(tripLogData.actual_duration_seconds ?? dbDurationSeconds);

                if (dbDistanceMeters <= 0) {
                    throw new functions.https.HttpsError('invalid-argument', 'Distance de trajet enregistrée en BD invalide.');
                }

                // Validation Physique Serveur
                if (dbDurationSeconds > 0) {
                    const speedKmh = (dbDistanceMeters / 1000) / (dbDurationSeconds / 3600);
                    const maxPhysicalSpeed = travelMode === 'bicycling' ? 70.0 : (travelMode === 'transit' ? 140.0 : 35.0);

                    if (speedKmh > maxPhysicalSpeed) {
                        console.warn(`⚠️ [ANTI-TRICHE SERVEUR] Vitesse physiquement impossible: ${speedKmh.toFixed(1)} km/h en ${travelMode} par ${userId}`);
                        throw new functions.https.HttpsError('permission-denied', `Vitesse physiquement impossible détectée (${speedKmh.toFixed(1)} km/h). Trajet rejeté.`);
                    }
                }

                const maxAllowedForDistance = Math.ceil((dbDistanceMeters / 1000) * 150) + 50;
                if (amountToAdd > maxAllowedForDistance) {
                    console.warn(`⚠️ [ANTI-TRICHE SERVEUR] Incohérence Lames/Distance: ${amountToAdd} Lames demandées pour ${(dbDistanceMeters / 1000).toFixed(2)}km par ${userId}`);
                    throw new functions.https.HttpsError('permission-denied', `Montant de Lames incohérent avec la distance parcourue.`);
                }
            }

            // 🚨 FIX 3 : VÉRIFICATION QUE L'UTILISATEUR A BIEN COMMENCÉ LE DÉFI DANS user_challenges
            if (isVerifiedChallenge && challengeId) {
                const userChallengeRef = admin.firestore().collection('user_challenges').doc(`${userId}_${challengeId}`);
                const userChallengeDoc = await transaction.get(userChallengeRef);
                if (!userChallengeDoc.exists || (userChallengeDoc.data().status !== 'inProgress' && userChallengeDoc.data().completed !== true)) {
                    throw new functions.https.HttpsError('permission-denied', 'Défi non commencé ou invalide dans vos défis.');
                }
                if (userChallengeDoc.data().completed === true) {
                    throw new functions.https.HttpsError('already-exists', 'Ce défi a déjà été validé et récompensé.');
                }
                transaction.set(userChallengeRef, {
                    user_id: userId,
                    challenge_id: challengeId,
                    completed: true,
                    status: 'completed',
                    completed_at: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });
            }

            // Cooldown de 10 minutes SEULEMENT pour les validations de trajet ou de visite
            const sourceLower = source.toLowerCase();
            const isTripSource = !isVerifiedChallenge && (sourceLower.startsWith('trajet') || sourceLower.startsWith('visite'));

            if (isTripSource) {
                const lastTripTime = statsData.last_trip_timestamp;
                const now = admin.firestore.Timestamp.now();

                if (lastTripTime) {
                    const elapsedMs = now.toMillis() - lastTripTime.toMillis();
                    if (elapsedMs < 10 * 60 * 1000) {
                        const remainingSec = Math.ceil((10 * 60 * 1000 - elapsedMs) / 1000);
                        throw new functions.https.HttpsError('resource-exhausted', `Vous allez trop vite ! Veuillez attendre ${remainingSec}s avant de valider un autre trajet.`);
                    }

                    const elapsedSec = elapsedMs / 1000;
                    if (dbDurationSeconds > elapsedSec + 120) {
                        console.warn(`⚠️ [ANTI-TRICHE SERVEUR] Durée déclarée (${dbDurationSeconds}s) supérieure au temps réel écoulé (${elapsedSec.toFixed(0)}s) pour ${userId}`);
                        throw new functions.https.HttpsError('permission-denied', `Durée de trajet incohérente avec le temps écoulé réel.`);
                    }
                }
            }

            const currentLame = userDoc.data().lame_points || 0;
            const currentTotalEarned = userDoc.data().total_lame_earned || 0;
            const newTotalEarned = currentTotalEarned + amountToAdd;

            const updateData = {
                lame_points: currentLame + amountToAdd,
                total_lame_earned: newTotalEarned,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            };

            // Promotion automatique statut VIP si Niveau 30+
            checkAndApplyVipStatus(newTotalEarned, updateData);

            transaction.update(userRef, updateData);

            if (isTripSource) {
                transaction.set(statsRef, {
                    last_trip_timestamp: admin.firestore.FieldValue.serverTimestamp(),
                    updated_at: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });
            }

            // 🆕 MISE À JOUR DU TRIP_LOG POUR LE LIER AUX LAMES
            if (tripId && !isVerifiedChallenge) {
                const tripRef = userRef.collection('trip_logs').doc(tripId);
                transaction.update(tripRef, {
                    lames_earned: amountToAdd,
                    validation_status: 'validated',
                    validated_at: admin.firestore.FieldValue.serverTimestamp()
                });
            }

            // 🆕 HISTORIQUE ENRICHI AVEC METADATA
            const historyRef = userRef.collection('lame_history').doc();
            const historyData = {
                amount: amountToAdd,
                source: source,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                type: isVerifiedChallenge ? 'challenge' : 'trip',
                metadata: {}
            };

            if (isVerifiedChallenge) {
                historyData.metadata = { challenge_id: challengeId, challenge_reward: challengeReward };
            } else {
                const computedAvgSpeedKmh = dbDurationSeconds > 0 ? parseFloat(((dbDistanceMeters / 1000) / (dbDurationSeconds / 3600)).toFixed(2)) : 0;
                historyData.metadata = {
                    trip_id: tripId,
                    travel_mode: travelMode,
                    distance_meters: dbDistanceMeters,
                    duration_seconds: dbDurationSeconds,
                    avg_speed_kmh: computedAvgSpeedKmh,
                    start_location: startLocation,
                    end_location: endLocation,
                    cheat_detected: cheatDetected,
                    cheat_reason: cheatReason
                };
            }
            transaction.set(historyRef, historyData);
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
    verifyAppCheck(context);
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
                actualCost = Math.round(itemDoc.data().cost_lame || itemDoc.data().cost || 0);
            } else {
                const rewardRef = admin.firestore().collection('rewards').doc(itemId);
                const rewardDoc = await transaction.get(rewardRef);
                if (rewardDoc.exists) {
                    actualCost = Math.round(rewardDoc.data().cost_lame || rewardDoc.data().cost || 0);
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
    verifyAppCheck(context);
    console.log("🚀 [START] claimDailyReward appelée");

    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const userId = context.auth.uid;
    const userRef = admin.firestore().collection('users').doc(userId);
    const statsRef = admin.firestore().collection('user_stats').doc(userId);

    try {
        const result = await admin.firestore().runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            const statsDoc = await transaction.get(statsRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Profil utilisateur introuvable.');
            }

            const userData = userDoc.data();
            const statsData = statsDoc.exists ? statsDoc.data() : {};
            const lastLoginTimestamp = statsData.last_login_date;
            const now = admin.firestore.Timestamp.now();

            let consecutiveLogins = statsData.consecutive_logins ?? 0;

            if (lastLoginTimestamp) {
                const elapsedMs = now.toMillis() - lastLoginTimestamp.toMillis();
                // Cooldown de 24h (86 400 000 ms)
                if (elapsedMs < 86400000) {
                    const remainingHours = Math.ceil((86400000 - elapsedMs) / 3600000);
                    return { updated: false, message: `Récompense déjà récupérée. Revenez dans ${remainingHours}h.` };
                }

                // Si entre 24h et 48h (172 800 000 ms), la série s'incrémente. Si > 48h, réinitialisation à 1.
                if (elapsedMs <= 172800000) {
                    consecutiveLogins += 1;
                } else {
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
            const newTotalEarned = currentTotalEarned + 1;

            const userUpdate = {
                lame_points: currentLame + 1,
                total_lame_earned: newTotalEarned,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            };

            // Promotion automatique statut VIP si Niveau 30+
            checkAndApplyVipStatus(newTotalEarned, userUpdate);

            // Mise à jour du Portefeuille (users)
            transaction.update(userRef, userUpdate);

            // Mise à jour des Stats/Cooldowns (user_stats)
            transaction.set(statsRef, {
                consecutive_logins: consecutiveLogins,
                last_login_date: admin.firestore.FieldValue.serverTimestamp(),
                next_level_boost: newNextLevelBoost,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

            const historyRef = userRef.collection('lame_history').doc();
            transaction.set(historyRef, {
                amount: 1,
                source: 'Récompense quotidienne',
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                type: 'daily_reward',
                metadata: {
                    consecutive_logins: consecutiveLogins,
                    streak_multiplier: newNextLevelBoost
                }
            });

            return { updated: true, consecutiveLogins, nextLevelBoost: newNextLevelBoost, newBalance: currentLame + 1, newTotalEarned: newTotalEarned };
        });

        return { success: true, ...result };

    } catch (error) {
        console.error("❌ Erreur claimDailyReward :", error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});

// --- FONCTION 7 : ACHAT DE TICKETS DE LOTERIE (RAFFLE) SERVEUR ---
exports.purchaseRaffleTicket = functions.https.onCall(async (data, context) => {
    verifyAppCheck(context);
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
    const rewardRef = admin.firestore().collection('rewards').doc(contestId);
    const contestStateRef = admin.firestore().collection('contest_state').doc(contestId);

    try {
        const result = await admin.firestore().runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Profil utilisateur introuvable.');
            }

            let contestDoc = await transaction.get(rewardRef);
            let contestData = contestDoc.exists ? contestDoc.data() : null;

            if (!contestDoc.exists) {
                const contestRef = admin.firestore().collection('contests').doc(contestId);
                const legacyDoc = await transaction.get(contestRef);
                if (legacyDoc.exists) {
                    contestDoc = legacyDoc;
                    contestData = legacyDoc.data();
                } else {
                    throw new functions.https.HttpsError('not-found', 'Concours ou loterie introuvable.');
                }
            }

            const contestStateDoc = await transaction.get(contestStateRef);
            const contestStateData = contestStateDoc.exists ? contestStateDoc.data() : {};

            if (contestData.status && contestData.status !== 'open') {
                throw new functions.https.HttpsError('failed-precondition', 'Le concours n\'est pas ouvert.');
            }

            const rawEndDate = contestData.end_date || contestData.details_json?.end_date;
            const endDate = rawEndDate ? (rawEndDate.toDate ? rawEndDate.toDate() : new Date(rawEndDate)) : null;
            if (endDate && new Date() > endDate) {
                throw new functions.https.HttpsError('failed-precondition', 'Ce concours est terminé.');
            }

            const ticketCostLame = Math.round(
                contestData?.details_json?.ticket_cost_eco ||
                contestData?.eco_cost ||
                contestData?.cost_lame ||
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

            // Incrémenter les tickets du concours dans contest_state (séparation dynamique)
            const currentTickets = contestStateData.total_tickets_sold || contestData.total_tickets_sold || 0;
            transaction.set(contestStateRef, {
                total_tickets_sold: currentTickets + ticketCount,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

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
    verifyAppCheck(context);
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
    const userStatsRef = admin.firestore().collection('user_stats').doc(userId);
    const rewardRef = admin.firestore().collection('rewards').doc(contestId);
    const contestStateRef = admin.firestore().collection('contest_state').doc(contestId);

    try {
        const result = await admin.firestore().runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Profil utilisateur introuvable.');
            }

            const userStatsDoc = await transaction.get(userStatsRef);
            const userStatsData = userStatsDoc.exists ? userStatsDoc.data() : {};
            const lastBidTime = userStatsData.last_bid_timestamp;
            const now = admin.firestore.Timestamp.now();

            // Anti-Spam / Anti-Contention : Cooldown de 3 secondes par utilisateur sur les enchères
            if (lastBidTime) {
                const elapsedMs = now.toMillis() - lastBidTime.toMillis();
                if (elapsedMs < 3000) {
                    const remainingSec = ((3000 - elapsedMs) / 1000).toFixed(1);
                    throw new functions.https.HttpsError('resource-exhausted', `Veuillez patienter ${remainingSec}s entre chaque enchère.`);
                }
            }

            let contestDoc = await transaction.get(rewardRef);
            if (!contestDoc.exists) {
                const contestRef = admin.firestore().collection('contests').doc(contestId);
                const legacyDoc = await transaction.get(contestRef);
                if (legacyDoc.exists) {
                    contestDoc = legacyDoc;
                } else {
                    throw new functions.https.HttpsError('not-found', 'Enchère introuvable.');
                }
            }

            const contestStateDoc = await transaction.get(contestStateRef);
            const contestStateData = contestStateDoc.exists ? contestStateDoc.data() : {};
            const contestData = contestDoc.data();

            const currentHighestBid = parseFloat(
                contestStateData.highest_bid ?? contestStateData.current_highest_bid ?? contestData.current_highest_bid ?? 0
            );
            const minBid = parseFloat(contestData.min_bid || 10);

            if (contestData.status && contestData.status !== 'open') {
                throw new functions.https.HttpsError('failed-precondition', 'L\'enchère n\'est pas ouverte.');
            }

            const rawEndDate = contestData.end_date || contestData.details_json?.end_date;
            const endDate = rawEndDate ? (rawEndDate.toDate ? rawEndDate.toDate() : new Date(rawEndDate)) : null;
            if (endDate && new Date() > endDate) {
                throw new functions.https.HttpsError('failed-precondition', 'Cette enchère est terminée.');
            }

            const minNextBid = currentHighestBid > 0 ? currentHighestBid + 1.0 : minBid;
            if (bidAmount < minNextBid) {
                throw new functions.https.HttpsError('failed-precondition', `L'enchère doit être d'au moins ${minNextBid} Lames.`);
            }

            const oldBidderId = contestStateData.highest_bidder_user_id || contestData.highest_bidder_user_id;

            let amountToDeduct = bidAmount;
            if (oldBidderId && oldBidderId === userId) {
                // L'utilisateur se surenchérit lui-même : on ne déduit que la différence
                amountToDeduct = bidAmount - currentHighestBid;
            }

            const userLame = userDoc.data().lame_points || 0;
            if (userLame < amountToDeduct) {
                throw new functions.https.HttpsError('failed-precondition', `Solde de Lames insuffisant (${userLame} disponibles, ${amountToDeduct} requises pour cette surenchère).`);
            }

            // Lire l'ancien enchérisseur si nécessaire (toutes les lectures doivent précéder les écritures dans une transaction)
            let oldBidderDoc = null;
            let oldBidderRef = null;
            if (oldBidderId && oldBidderId !== userId) {
                oldBidderRef = admin.firestore().collection('users').doc(oldBidderId);
                oldBidderDoc = await transaction.get(oldBidderRef);
            }

            // Rembourser l'ancien enchérisseur uniquement s'il existe toujours
            if (oldBidderId && oldBidderId !== userId && oldBidderRef) {
                if (oldBidderDoc && oldBidderDoc.exists) {
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
                } else {
                    console.warn(`⚠️ Ancien enchérisseur ${oldBidderId} introuvable (compte supprimé). Remboursement annulé.`);
                }
            }

            // Débiter le nouvel enchérisseur (ou ajuster en cas d'auto-surenchère) avec FieldValue.increment
            const newBalance = userLame - amountToDeduct;
            transaction.update(userRef, {
                lame_points: admin.firestore.FieldValue.increment(-amountToDeduct),
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });

            // Mettre à jour le document de l'état de l'enchère (séparé pour éviter la contention)
            transaction.set(contestStateRef, {
                highest_bid: bidAmount,
                current_highest_bid: bidAmount,
                highest_bidder_user_id: userId,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

            // Enregistrer l'horodatage de la dernière enchère de l'utilisateur pour le cooldown anti-spam
            transaction.set(userStatsRef, {
                last_bid_timestamp: admin.firestore.FieldValue.serverTimestamp(),
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

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
// Helper pour découper un tableau d'éléments en sous-tableaux de taille max (ex: 400 pour les batches Firestore)
const chunkArray = (arr, size) => arr.reduce((acc, _, i) => {
    if (i % size === 0) acc.push(arr.slice(i, i + size));
    return acc;
}, []);

exports.deleteUserAccount = functions.https.onCall(async (data, context) => {
    verifyAppCheck(context);
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const userId = context.auth.uid;
    console.log(`⚠️ [RGPD] Suppression définitive du compte et des données pour ${userId}`);

    try {
        const userRef = admin.firestore().collection('users').doc(userId);

        // Helper pour exécuter la suppression par lot de 400 documents max (pour respecter la limite stricte de 500 par batch)
        const deleteQueryDocsChunked = async (querySnapshot) => {
            if (querySnapshot.empty) return;
            const chunks = chunkArray(querySnapshot.docs, 400);
            for (const chunk of chunks) {
                const batch = admin.firestore().batch();
                chunk.forEach(doc => batch.delete(doc.ref));
                await batch.commit();
            }
        };

        // 1. Supprimer l'historique des lames, trajets et cashback (sous-collections)
        const historyDocs = await userRef.collection('lame_history').get();
        await deleteQueryDocsChunked(historyDocs);

        const tripDocs = await userRef.collection('trip_logs').get();
        await deleteQueryDocsChunked(tripDocs);

        // 🚨 FIX 6 : Supprimer la sous-collection cashback_history sous users/{userId}
        const cbSubDocs = await userRef.collection('cashback_history').get();
        await deleteQueryDocsChunked(cbSubDocs);

        // 2. Supprimer toutes les données liées dans les collections principales (découpé par batch de 400 max)
        const collectionsToDelete = ['user_claimed_offers', 'user_challenges', 'contest_entries', 'cashback_claims'];
        for (const col of collectionsToDelete) {
            const snapshot = await admin.firestore().collection(col).where('user_id', '==', userId).get();
            await deleteQueryDocsChunked(snapshot);
        }

        // 3. Anonymiser les transactions magasins (store_transactions) et les magasins créés par l'utilisateur
        const storeTxDocs = await admin.firestore().collectionGroup('store_transactions').where('user_id', '==', userId).get();
        if (!storeTxDocs.empty) {
            const chunks = chunkArray(storeTxDocs.docs, 400);
            for (const chunk of chunks) {
                const txBatch = admin.firestore().batch();
                chunk.forEach(doc => txBatch.update(doc.ref, {
                    user_id: 'deleted_user',
                    username: 'Utilisateur supprimé',
                    anonymized: true
                }));
                await txBatch.commit();
            }
        }

        const storesSnapshot = await admin.firestore().collection('stores').where('owner_id', '==', userId).get();
        if (!storesSnapshot.empty) {
            const chunks = chunkArray(storesSnapshot.docs, 400);
            for (const chunk of chunks) {
                const storeBatch = admin.firestore().batch();
                chunk.forEach(doc => storeBatch.update(doc.ref, {
                    owner_id: 'deleted_user',
                    owner_anonymized: true,
                    updated_at: admin.firestore.FieldValue.serverTimestamp()
                }));
                await storeBatch.commit();
            }
        }

        // 4. Supprimer le document profil utilisateur et le document user_stats
        await userRef.delete();
        await admin.firestore().collection('user_stats').doc(userId).delete();

        // 5. Supprimer le compte Firebase Auth (avec capture d'erreur si déjà supprimé)
        try {
            await admin.auth().deleteUser(userId);
        } catch (authErr) {
            console.warn(`⚠️ Compte Auth pour ${userId} introuvable ou déjà supprimé:`, authErr.message);
        }

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
    verifyAppCheck(context);
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Non autorisé');

    const userId = context.auth.uid;
    const userRef = admin.firestore().collection('users').doc(userId);
    const statsRef = admin.firestore().collection('user_stats').doc(userId);

    return admin.firestore().runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const statsDoc = await transaction.get(statsRef);
        if (!userDoc.exists) throw new functions.https.HttpsError('not-found', 'Profil introuvable.');

        const statsData = statsDoc.exists ? statsDoc.data() : {};
        const userData = userDoc.data();
        const lastAdTime = statsData.last_ad_point_timestamp;
        const now = admin.firestore.Timestamp.now();
        if (lastAdTime) {
            const elapsedMs = now.toMillis() - lastAdTime.toMillis();
            if (elapsedMs < 30000) {
                const remainingSec = Math.ceil((30000 - elapsedMs) / 1000);
                throw new functions.https.HttpsError('resource-exhausted', `Veuillez patienter ${remainingSec}s avant de regarder une autre publicité.`);
            }
        }

        const currentPoints = statsData.ad_points ?? 0;

        if (currentPoints >= 50) {
            throw new functions.https.HttpsError('resource-exhausted', 'Max Ad Points atteints.');
        }

        const newPoints = currentPoints + 1;
        transaction.set(statsRef, {
            ad_points: newPoints,
            last_ad_point_timestamp: admin.firestore.FieldValue.serverTimestamp(),
            last_ad_point_decay_time: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        return { newAdPoints: newPoints };
    });
});

// --- 2. Regarder une pub pour un magasin (Boost Cashback) ---
exports.addStoreBoost = functions.https.onCall(async (data, context) => {
    verifyAppCheck(context);
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Non autorisé');

    const storeId = data.storeId;
    if (!storeId) throw new functions.https.HttpsError('invalid-argument', 'Store ID manquant');

    const userId = context.auth.uid;
    const userRef = admin.firestore().collection('users').doc(userId);
    const statsRef = admin.firestore().collection('user_stats').doc(userId);
    const storeRef = admin.firestore().collection('stores').doc(storeId);

    return admin.firestore().runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const statsDoc = await transaction.get(statsRef);
        const storeDoc = await transaction.get(storeRef);

        if (!userDoc.exists) throw new functions.https.HttpsError('not-found', 'Profil introuvable.');

        const userData = userDoc.data();
        const statsData = statsDoc.exists ? statsDoc.data() : {};

        const lastBoostTime = statsData.last_store_boost_timestamp;
        const now = admin.firestore.Timestamp.now();
        if (lastBoostTime) {
            const elapsedMs = now.toMillis() - lastBoostTime.toMillis();
            if (elapsedMs < 30000) {
                const remainingSec = Math.ceil((30000 - elapsedMs) / 1000);
                throw new functions.https.HttpsError('resource-exhausted', `Veuillez patienter ${remainingSec}s entre deux boosts de magasin.`);
            }
        }

        // 🚨 FIX 4 : Protection anti-bot : limite quotidienne de 10 boosts par jour et par magasin
        const todayStr = new Date().toISOString().split('T')[0];
        const boostDailyKey = `boosts_${storeId}_${todayStr}`;
        const dailyBoosts = statsData[boostDailyKey] || 0;

        if (dailyBoosts >= 10) {
            throw new functions.https.HttpsError('resource-exhausted', 'Limite quotidienne de boosts atteinte pour ce magasin (10 max par jour).');
        }

        const isVip = userData.is_vip === true;
        const storeHasBoost = storeDoc.exists && storeDoc.data().is_premium_ad_boost_enabled === true;
        const cashbackRate = storeDoc.exists ? (storeDoc.data().cashback_rate || 0.05) : 0.05;

        const effectivelySuperPremium = isVip && storeHasBoost;
        const effectivelyPremium = isVip || storeHasBoost;

        const storeBoosts = statsData.store_boosts || {};
        const currentBoost = storeBoosts[storeId]?.amount || 0.0;

        let gain = 0.01;
        if (currentBoost >= 1.0) {
            gain = effectivelySuperPremium ? 0.8 : (effectivelyPremium ? 0.4 : 0.2);
        } else {
            gain = effectivelySuperPremium ? 0.04 : (effectivelyPremium ? 0.02 : 0.01);
        }

        let maxCap = Math.max(cashbackRate * 100.0, 1.0);
        let newAmount = Math.min(currentBoost + gain, maxCap);

        // Nettoyage de la map des boosts : si le boost tombe à 0 ou en cas d'expiration, on supprime la clé
        const storeBoostsUpdate = {};
        if (newAmount <= 0) {
            storeBoostsUpdate[`store_boosts.${storeId}`] = admin.firestore.FieldValue.delete();
        } else {
            storeBoostsUpdate[`store_boosts.${storeId}`] = {
                amount: newAmount,
                last_update: admin.firestore.FieldValue.serverTimestamp()
            };
        }

        transaction.set(statsRef, {
            last_store_boost_timestamp: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
            [boostDailyKey]: dailyBoosts + 1,
            ...storeBoostsUpdate
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
    verifyAppCheck(context);
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

        let cost = 0;

        if (offerId) {
            const rewardRef = admin.firestore().collection('rewards').doc(offerId);
            const rewardDoc = await transaction.get(rewardRef);
            if (!rewardDoc.exists) {
                throw new functions.https.HttpsError('not-found', 'Offre introuvable dans le catalogue.');
            }
            const rData = rewardDoc.data();
            const fetchedCost = rData.eco_cost ?? rData.cost_lame ?? rData.cost;
            if (fetchedCost !== undefined && fetchedCost !== null && !isNaN(parseFloat(fetchedCost))) {
                cost = parseFloat(fetchedCost);
            } else {
                throw new functions.https.HttpsError('invalid-argument', 'Coût de l\'offre invalide.');
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
        } else {
            // 🚨 FIX 5 : Don libre sans offerId -> contrôle strict des limites (100 min, 5000 max)
            const rawCost = parseFloat(amount);
            if (isNaN(rawCost) || rawCost < 100 || rawCost > 5000) {
                throw new functions.https.HttpsError('invalid-argument', 'Montant de don libre invalide (minimum 100, maximum 5000 Lames).');
            }
            cost = rawCost;
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

// Helper : Calcul de la décroissance temporelle (Decay) des boosts de magasin
function calculateDecayedBoost(initialAmount, lastUpdateTimestamp, isVip) {
    if (!initialAmount || initialAmount <= 0 || !lastUpdateTimestamp) return 0.0;

    let lastUpdateMs = 0;
    if (typeof lastUpdateTimestamp.toMillis === 'function') {
        lastUpdateMs = lastUpdateTimestamp.toMillis();
    } else if (lastUpdateTimestamp._seconds) {
        lastUpdateMs = lastUpdateTimestamp._seconds * 1000;
    } else if (lastUpdateTimestamp.toDate) {
        lastUpdateMs = lastUpdateTimestamp.toDate().getTime();
    } else {
        lastUpdateMs = new Date(lastUpdateTimestamp).getTime();
    }

    const elapsedSeconds = Math.floor((Date.now() - lastUpdateMs) / 1000);
    if (isNaN(elapsedSeconds) || elapsedSeconds <= 0) return Number(initialAmount);

    let simulatedAmount = Number(initialAmount);
    let secondsSimulated = 0;

    while (simulatedAmount > 0) {
        let stepMinutes, lossAmount;
        if (simulatedAmount >= 1.0) {
            stepMinutes = isVip ? 10 : 5;
            lossAmount = isVip ? 0.05 : 0.10;
        } else if (simulatedAmount >= 0.60) {
            stepMinutes = 5;
            lossAmount = 0.60;
        } else if (simulatedAmount >= 0.50) {
            stepMinutes = 10;
            lossAmount = 0.50;
        } else if (simulatedAmount >= 0.40) {
            stepMinutes = 15;
            lossAmount = 0.40;
        } else if (simulatedAmount >= 0.30) {
            stepMinutes = 20;
            lossAmount = 0.30;
        } else if (simulatedAmount >= 0.20) {
            stepMinutes = 25;
            lossAmount = 0.20;
        } else if (simulatedAmount >= 0.10) {
            stepMinutes = 30;
            lossAmount = 0.10;
        } else {
            stepMinutes = 60;
            lossAmount = 0.01;
        }

        const stepSeconds = stepMinutes * 60;
        if (secondsSimulated + stepSeconds <= elapsedSeconds) {
            simulatedAmount -= lossAmount;
            secondsSimulated += stepSeconds;
        } else {
            break;
        }
    }

    return Math.max(0.0, Math.round(simulatedAmount * 1000) / 1000);
}

// --- 4. Valider un Ticket de Caisse et Calculer le Cashback ---
exports.claimCashback = functions.https.onCall(async (data, context) => {
    verifyAppCheck(context);
    if (!context.auth) throw new functions.https.HttpsError('unauthenticated', 'Non autorisé');

    const { storeId, receiptToken, rawText } = data;
    const userId = context.auth.uid;

    if (!storeId) {
        throw new functions.https.HttpsError('invalid-argument', 'Store ID manquant.');
    }

    // 🚨 FIX 2 : Exiger le jeton de validation OCR éphémère émis par Document AI / Gemini
    if (!receiptToken) {
        throw new functions.https.HttpsError('invalid-argument', 'Jeton de validation OCR manquant. Veuillez d\'abord scanner votre reçu.');
    }

    const userRef = admin.firestore().collection('users').doc(userId);
    const statsRef = admin.firestore().collection('user_stats').doc(userId);
    const storeRef = admin.firestore().collection('stores').doc(storeId);
    const ocrRef = admin.firestore().collection('ocr_validations').doc(receiptToken);

    let stripeSubscriptionItemId = null;
    let commissionCentsToReport = 0;

    const transactionResult = await admin.firestore().runTransaction(async (transaction) => {
        // 🚨 FIX 2 : Vérification atomique du jeton OCR
        const ocrDoc = await transaction.get(ocrRef);
        if (!ocrDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Jeton de validation du reçu introuvable ou expiré.');
        }
        const ocrData = ocrDoc.data();

        if (ocrData.user_id !== userId) {
            throw new functions.https.HttpsError('permission-denied', 'Ce jeton de validation ne correspond pas à votre compte.');
        }

        if (ocrData.used === true) {
            throw new functions.https.HttpsError('already-exists', 'Ce reçu a déjà été réclamé.');
        }

        if (ocrData.expires_at && ocrData.expires_at.toMillis() < Date.now()) {
            throw new functions.https.HttpsError('deadline-exceeded', 'Le jeton de validation du reçu a expiré (limite de 5 minutes).');
        }

        const validText = (ocrData.extracted_text || rawText || '').trim();

        // 🚨 FIX 8 : Extraction sécurisée et robuste du montant certifié par l'OCR
        let extractedAmount = null;
        if (validText) {
            const matches = validText.match(/(?:total|net|montant|paye|cb|carte|eur|€)[^\d]*(\d+[\.,]\d{2})/gi);
            if (matches && matches.length > 0) {
                for (let i = matches.length - 1; i >= 0; i--) {
                    const numMatch = matches[i].match(/(\d+[\.,]\d{2})/);
                    if (numMatch) {
                        const parsedVal = parseFloat(numMatch[1].replace(',', '.'));
                        if (parsedVal > 0.50 && parsedVal <= 500.0) {
                            extractedAmount = parsedVal;
                            break;
                        }
                    }
                }
            }
        }

        if (!extractedAmount || extractedAmount <= 0) {
            throw new functions.https.HttpsError('invalid-argument', 'Impossible de vérifier le montant total sur le ticket certifié.');
        }
        let amount = Math.min(extractedAmount, 100.0); // Plafond anti-triche 100€

        // 🚨 FIX 8 : Empreinte anti-rejeu basée sur le jeton certifié et le montant
        const receiptHash = crypto.createHash('sha256').update(`${userId}_${storeId}_${amount}_${receiptToken}`).digest('hex');
        const claimRef = admin.firestore().collection('cashback_claims').doc(receiptHash);
        const claimDoc = await transaction.get(claimRef);
        if (claimDoc.exists) {
            throw new functions.https.HttpsError('already-exists', 'Ce ticket de caisse a déjà été scanné et validé.');
        }

        const userDoc = await transaction.get(userRef);
        const statsDoc = await transaction.get(statsRef);
        const storeDoc = await transaction.get(storeRef);

        if (!userDoc.exists || !storeDoc.exists) {
            throw new functions.https.HttpsError('not-found', 'Utilisateur ou magasin introuvable.');
        }

        const userData = userDoc.data();
        const statsData = statsDoc.exists ? statsDoc.data() : {};
        const storeData = storeDoc.data();

        // Récupérer l'ID d'abonnement Stripe du commerçant
        stripeSubscriptionItemId = storeData.stripe_subscription_item_id || null;
        if (!stripeSubscriptionItemId && storeData.owner_id) {
            const ownerDoc = await transaction.get(admin.firestore().collection('users').doc(storeData.owner_id));
            if (ownerDoc.exists) {
                stripeSubscriptionItemId = ownerDoc.data().stripe_subscription_item_id || null;
                if (stripeSubscriptionItemId) {
                    transaction.update(storeRef, { stripe_subscription_item_id: stripeSubscriptionItemId });
                }
            }
        }

        // 1. Calcul des taux (Le serveur récupère les vraies données)
        let baseRate = (storeData.cashback_rate || 0.05) * 100.0;
        if (storeData.is_visibility_boost_enabled) baseRate += 1.0;

        // 🚨 FIX 4 : Calcul Serveur de la Décroissance Temporelle (Decay) du Boost
        const storeBoosts = statsData.store_boosts || {};
        const boostEntry = storeBoosts[storeId];
        let boostAddon = 0.0;
        if (boostEntry && boostEntry.amount && boostEntry.last_update) {
            boostAddon = calculateDecayedBoost(boostEntry.amount, boostEntry.last_update, userData.is_vip === true);
        }

        // 2. Calcul de la fidélité depuis user_stats
        let loyaltyDiscount = 0.0;
        let loyaltyTierLabel = "";
        const loyaltyProgress = statsData.loyalty_progress || {};
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
        commissionCentsToReport = Math.round(cashbackAmount * 100);

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
        const newTotalLameEarned = totalLameEarned + lameBonus;

        // --- 4. ÉCRITURES SÉCURISÉES ---

        // 🚨 FIX 2 : Marquer le jeton OCR comme consommé
        transaction.update(ocrRef, {
            used: true,
            claimed_at: admin.firestore.FieldValue.serverTimestamp()
        });

        // Enregistrer la réclamation pour éviter le rejeu
        transaction.set(claimRef, {
            user_id: userId,
            store_id: storeId,
            amount_spent: amount,
            receipt_token: receiptToken,
            claimed_at: admin.firestore.FieldValue.serverTimestamp()
        });

        // Mise à jour du profil (users)
        const userUpdate = {
            lame_points: admin.firestore.FieldValue.increment(lameBonus),
            total_lame_earned: admin.firestore.FieldValue.increment(lameBonus)
        };
        checkAndApplyVipStatus(newTotalLameEarned, userUpdate);
        transaction.update(userRef, userUpdate);

        // Mise à jour de la progression de fidélité (user_stats)
        const newVisits = (storeProgress.visits || 0) + 1;
        const newSpend = (storeProgress.spend || 0) + amount;
        transaction.set(statsRef, {
            [`loyalty_progress.${storeId}`]: {
                visits: newVisits,
                spend: newSpend
            },
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        // Historique des Lames (ENRICHI)
        if (lameBonus > 0) {
            const historyRef = userRef.collection('lame_history').doc();
            transaction.set(historyRef, {
                amount: lameBonus,
                source: `Cashback ${storeData.name || 'Magasin'}`,
                timestamp: admin.firestore.FieldValue.serverTimestamp(),
                type: 'cashback',
                metadata: {
                    store_id: storeId,
                    store_name: storeData.name || 'Magasin',
                    amount_spent_euro: amount,
                    cashback_earned_euro: cashbackAmount,
                    receipt_hash: receiptHash,
                    loyalty_tier: loyaltyTierLabel || null
                }
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
            receipt_text_raw: validText,
            receipt_hash: receiptHash,
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

    // 5. Reporting automatique de la commission Stripe côté serveur (sécurisé)
    if (stripe && stripeSubscriptionItemId && commissionCentsToReport > 0) {
        try {
            await stripe.subscriptionItems.createUsageRecord(
                stripeSubscriptionItemId,
                {
                    quantity: commissionCentsToReport,
                    action: 'increment'
                }
            );
            console.log(`✅ Commission Stripe reportée automatiquement (+${commissionCentsToReport} cents) pour le magasin ${storeId}`);
        } catch (stripeErr) {
            console.error("⚠️ Échec du reporting Stripe automatique :", stripeErr.message);
        }
    }

    return transactionResult;
});

// ════════════════════════════════════════════════════════════════════════════
// 🗑️ NETTOYAGE AUTOMATIQUE PLANIFIÉ (TTL 90 JOURS)
// ════════════════════════════════════════════════════════════════════════════
exports.cleanupOldLogs = onSchedule('every 24 hours', async (event) => {
    console.log("🚀 [SCHEDULED] Démarrage du nettoyage automatique des logs (TTL 90 jours)");
    const cutoff = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 90 * 24 * 60 * 60 * 1000));

    // Mapper le bon champ de date pour chaque collection
    const collectionsConfig = [
        { name: 'lame_history', dateField: 'timestamp' },
        { name: 'cashback_history', dateField: 'timestamp' },
        { name: 'trip_logs', dateField: 'started_at' },
        { name: 'contest_entries', dateField: 'created_at' }
    ];

    let totalDeleted = 0;
    for (const config of collectionsConfig) {
        let hasMore = true;
        while (hasMore) {
            try {
                const snap = await admin.firestore().collectionGroup(config.name)
                    .where(config.dateField, '<', cutoff)
                    .limit(400)
                    .get();

                if (snap.empty) {
                    hasMore = false;
                    break;
                }

                const batch = admin.firestore().batch();
                snap.docs.forEach(doc => batch.delete(doc.ref));
                await batch.commit();
                totalDeleted += snap.size;

                if (snap.size < 400) {
                    hasMore = false;
                }
            } catch (err) {
                console.error(`⚠️ Erreur nettoyage collectionGroup '${config.name}':`, err.message);
                hasMore = false;
            }
        }
    }
    console.log(`✅ [CLEANUP] Nettoyage terminé. ${totalDeleted} documents anciens supprimés.`);
    return null;
});