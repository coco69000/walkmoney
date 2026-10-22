const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const nodemailer = require('nodemailer');
const admin = require('firebase-admin');
const crypto = require('crypto');
admin.initializeApp();

// Helper : Vérification Firebase App Check tolérante en dev
const verifyAppCheck = (request) => {
    // Si App Check n'est pas encore configuré avec le debug token dans la console, ne pas bloquer les utilisateurs
    if (!request?.app && process.env.FUNCTIONS_EMULATOR !== 'true' && process.env.ENFORCE_APP_CHECK === 'true') {
        throw new HttpsError(
            'failed-precondition',
            'L\'appel doit provenir d\'une application officielle authentifiée (App Check).'
        );
    }
};

// 🔒 Helper : Vérification des droits Administrateur
const verifyAdmin = (context) => {
    if (!context.auth) {
        throw new HttpsError('unauthenticated', 'Utilisateur non authentifié.');
    }
    if (!context.auth.token || context.auth.token.admin !== true) {
        throw new HttpsError('permission-denied', 'Droits d\'administrateur requis pour réaliser cette action.');
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
    if (updateObject && typeof updateObject === 'object') {
        updateObject.current_level = currentLevel;
        if (currentLevel >= 30) {
            updateObject.is_vip = true;
        }
    }
    return currentLevel;
}

// Helper d'échappement HTML pour prévenir toute injection dans les e-mails transactionnels
const esc = (s) => String(s || '').replace(/[&<>"']/g, c => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;'
}[c]));

// Protection anti-abus / fermes de comptes (Item 137)
const verifyEmailVerified = (context) => {
    if (!context.auth) {
        throw new HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }
    if (process.env.FUNCTIONS_EMULATOR === 'true' || process.env.FIREBASE_AUTH_EMULATOR_HOST) return;
    if (!context.auth.token || !context.auth.token.email_verified) {
        throw new HttpsError('failed-precondition', 'Veuillez vérifier votre adresse e-mail avant de réclamer des gains ou des récompenses.');
    }
};

// ════════════════════════════════════════════════════════════════════════════
// 🔔 GESTIONNAIRE DE NOTIFICATIONS (PUSH FCM + IN-APP)
// ════════════════════════════════════════════════════════════════════════════
async function sendNotification(userId, title, body, data = {}) {
    if (!userId) return;
    try {
        // 1. Enregistrement dans la boîte de notifications Firestore de l'utilisateur (In-App)
        await admin.firestore().collection('users').doc(userId).collection('notifications').add({
            title: title,
            body: body,
            data: data,
            read: false,
            created_at: admin.firestore.FieldValue.serverTimestamp()
        });

        // 2. Envoi Push Notification FCM si l'utilisateur possède un jeton
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        if (userDoc.exists) {
            const userData = userDoc.data() || {};
            const fcmToken = userData.fcm_token || userData.fcmToken;
            if (fcmToken) {
                const messagePayload = {
                    token: fcmToken,
                    notification: {
                        title: title,
                        body: body,
                    },
                    data: Object.fromEntries(
                        Object.entries(data).map(([k, v]) => [k, String(v ?? '')])
                    )
                };
                await admin.messaging().send(messagePayload);
                console.log(`📲 [NOTIF] Notification Push envoyée avec succès à ${userId} ("${title}")`);
            }
        }
    } catch (err) {
        console.warn(`⚠️ [NOTIF] Échec envoi notification pour ${userId}:`, err.message);
    }
}

// ════════════════════════════════════════════════════════════════════════════
// 🛡️ SECURE OCR - NVIDIA NIM (Llama 3.2 Vision)
// ════════════════════════════════════════════════════════════════════════════
// Remplace Document AI + Gemini par NVIDIA NIM (OCR + Analyse en une requête)
// ════════════════════════════════════════════════════════════════════════════

const NVIDIA_API_KEY = process.env.NVIDIA_API_KEY;
const NVIDIA_API_URL = 'https://integrate.api.nvidia.com/v1/chat/completions';

async function analyzeReceiptWithNvidia(base64Image, mimeType, storeName) {
    if (!NVIDIA_API_KEY) {
        console.warn("⚠️ NVIDIA_API_KEY absente. Reçu refusé par précaution.");
        return { valid: false, reason: 'Clé API NVIDIA non configurée sur le serveur.', extractedText: '', amount: null, storeNameFound: '' };
    }

    // Nettoyer le nom du magasin pour le prompt
    const safeStoreName = (storeName || 'Commerce').replace(/[^a-zA-Z0-9\s\-\.\'\&]/g, '').trim().substring(0, 50) || 'Commerce';

    const prompt = `Tu es un expert strict en vérification de tickets de caisse et en détection de fraude pour une application de cashback. Ton but est de valider l'authenticité du ticket et d'exclure toute tentative de falsification ou de triche.

Analyse l'image fournie qui est censée être un ticket de caisse du magasin : "${safeStoreName}".

ÉVALUATION STRICTE ET DÉTECTION DE TRICHE :
1. DÉTECTION DE TRICHE ET FALSIFICATION :
   - Inspecte minutieusement le document pour détecter toute altération : ratures, texte barré, annotations manuelles au stylo ou au feutre remplaçant du texte imprimé, collage ou photomontage.
   - Si le nom du magasin imprimé à l'origine semble avoir été rayé, masqué ou modifié manuellement (par ex. pour écrire ou faire croire qu'il s'agit de "${safeStoreName}"), marque IMMÉDIATEMENT le ticket comme INVALIDE (valid: false) avec une explication claire.
   - Rejette immédiatement les faux tickets, les notes manuscrites, les captures d'écran d'applications ou d'autres écrans de téléphone, et les images tronquées ne montrant pas un vrai ticket.

2. CORRESPONDANCE DU MAGASIN :
   - Identifie le nom officiel de l'enseigne imprimé sur le ticket ("storeNameFound").
   - Il doit correspondre clairement à "${safeStoreName}". Si le ticket provient d'une autre enseigne (ex: ticket Carrefour pour une visite Auchan), c'est un REJET IMMÉDIAT (valid: false).

3. MONTANT TOTAL TTC :
   - Extrais le montant total payé TTC (Total, Net à payer, Total TTC). Ce montant doit être supérieur à 0 et clairement imprimé sur le reçu (pas ajouté à la main).

4. DATE DU TICKET :
   - Une date de transaction doit être visible sur le ticket.

Tu dois répondre EXCLUSIVEMENT avec un objet JSON valide (aucun texte avant ou après, aucune balise markdown comme \`\`\`json).

Format de réponse JSON strict :
{
  "valid": true ou false,
  "reason": "Si valid est false, explique PRÉCISÉMENT et en une phrase claire pourquoi (ex: 'Le nom du magasin semble avoir été raturé ou modifié manuellement', 'Le ticket provient de X au lieu de Y', 'Montant total introuvable ou illisible'). Si valid est true, mets 'OK'.",
  "extractedText": "Le texte brut extrait du ticket (concentre-toi sur l'en-tête avec le nom du magasin et le pied de page avec le total)",
  "storeNameFound": "Le nom exact du magasin tel qu'il apparaît sur le ticket (ou 'Inconnu')",
  "amount": nombre_decimal (ex: 15.50) ou null si introuvable,
  "date": "Date trouvée au format JJ/MM/AAAA ou null",
  "isReceipt": true ou false
}

Règles absolues :
- Si le ticket semble falsifié, altéré ou si le magasin ne correspond pas, valid DOIT être false et reason DOIT le mentionner explicitement.
- Ne sois pas indulgent. En cas de doute sur l'authenticité ou le magasin, rejette (valid: false).
- Ne génère AUCUN texte en dehors du JSON.`;

    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 60000);

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
                temperature: 0.0 // Température à 0 pour une réponse déterministe et stricte
            }),
            signal: controller.signal
        });

        if (!response.ok) {
            console.error(`❌ Erreur NVIDIA API: ${response.status}`);
            return { valid: false, reason: 'Service d\'analyse indisponible ou erreur serveur.', extractedText: '', amount: null, storeNameFound: '' };
        }

        const data = await response.json();
        const responseText = data?.choices?.[0]?.message?.content || '';

        // --- PARSING JSON ROBUSTE ---
        // 1. Enlever les balises markdown ```json ... ``` si l'IA en ajoute quand même
        let cleanedText = responseText.trim().replace(/^```json\s*/i, '').replace(/```\s*$/i, '');

        // 2. Extraire uniquement le bloc JSON si du texte parasite existe avant/après
        const firstBrace = cleanedText.indexOf('{');
        const lastBrace = cleanedText.lastIndexOf('}');

        if (firstBrace !== -1 && lastBrace !== -1 && lastBrace > firstBrace) {
            cleanedText = cleanedText.substring(firstBrace, lastBrace + 1);
        }

        let parsed;
        try {
            parsed = JSON.parse(cleanedText);
        } catch (jsonErr) {
            console.error("❌ Échec parsing JSON NVIDIA. Réponse brute:", cleanedText);
            return {
                valid: false,
                reason: 'Erreur de format de la réponse de l\'IA. Veuillez réessayer avec une image plus nette.',
                extractedText: '',
                amount: null,
                storeNameFound: ''
            };
        }

        // Validation stricte des champs
        const isValid = (parsed.valid === true && parsed.isReceipt === true);
        const reason = (parsed.reason && parsed.reason.trim().length > 0)
            ? parsed.reason
            : (isValid ? 'OK' : 'Le ticket ne respecte pas les critères de validation (magasin, authenticité ou montant).');

        return {
            valid: isValid,
            reason: reason,
            extractedText: parsed.extractedText || '',
            storeNameFound: parsed.storeNameFound || 'Inconnu',
            amount: typeof parsed.amount === 'number' ? parsed.amount : null,
            date: parsed.date || null
        };

    } catch (err) {
        if (err.name === 'AbortError') {
            console.error("⏱️ Timeout requête NVIDIA NIM (60s)");
            return { valid: false, reason: 'Délai d\'attente dépassé lors de l\'analyse du ticket. Veuillez réessayer.', extractedText: '', amount: null, storeNameFound: '' };
        }
        console.error("❌ Erreur critique NVIDIA NIM:", err.message);
        return { valid: false, reason: 'Erreur de connexion au service d\'analyse.', extractedText: '', amount: null, storeNameFound: '' };
    } finally {
        clearTimeout(timeoutId);
    }
}

exports.processReceiptOCR = onCall({ memory: '1GiB', timeoutSeconds: 120 }, async (request) => {
    const data = request.data;
    const context = request;
    verifyAppCheck(context);
    console.log("🛡️ [SECURE] processReceiptOCR via NVIDIA NIM");

    if (!context.auth) {
        throw new HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const imageBase64 = data.imageBase64;
    const mimeType = data.mimeType || 'image/jpeg';
    const rawStoreName = data.storeName || '';
    const safeStoreName = rawStoreName.replace(/[^a-zA-Z0-9\s\-\.\'\&]/g, '').trim().substring(0, 50) || 'Commerce';

    if (!imageBase64) {
        throw new HttpsError('invalid-argument', 'Image base64 manquante');
    }

    if (imageBase64.length > 7 * 1024 * 1024) {
        throw new HttpsError('invalid-argument', 'Image trop volumineuse (maximum 5 Mo).');
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
            throw new HttpsError('resource-exhausted', `Patientez ${remainingSec}s avant un nouveau scan.`);
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
        throw new HttpsError('internal', 'Erreur d\'analyse. Veuillez réessayer.');
    }
});

// ════════════════════════════════════════════════════════════════════════════
// 🛡️ ARCHITECTURE SÉCURISÉE (SERVER-AUTHORITATIVE FUNCTIONS)
// ════════════════════════════════════════════════════════════════════════════

// --- FONCTION 4 : VALIDATION SERVEUR DES TRAJETS & ATTRIBUTION DES LAMES (ENRICHI) ---
exports.validateTrip = onCall(async (request) => {
    const data = request.data;
    const context = request;
    verifyAppCheck(context);
    console.log("🚀 [START] validateTrip appelée");

    // VÉRIFICATION D'AUTHENTIFICATION RENFORCÉE & EMAIL VÉRIFIÉ (Item 137)
    if (!context.auth || !context.auth.uid) {
        console.warn("⚠️ [AUTH] Requête rejetée : context.auth est null. Le client n'a pas envoyé de token valide (token expiré ou utilisateur déconnecté).");
        throw new HttpsError('unauthenticated', 'Session expirée. Veuillez vous reconnecter dans l\'application.');
    }
    verifyEmailVerified(context);

    const userId = context.auth.uid;
    const source = data.source || 'Trajet';
    const challengeId = data.challengeId || null;
    const tripId = data.tripId || null; // 🆕 L'ID du document trip_logs

    // 🚨 FIX SÉCURITÉ : Pas de passe-droit client pour des bonus arbitraires via le nom de la source
    // Les bonus d'envergure (ex: Super Défi 5000 Lames) doivent être validés par claimSuperChallengeBonus

    // tripId ou données GPS obligatoires pour les trajets normaux (hors défis vérifiés)
    if (!challengeId && !tripId) {
        if (!data.distanceMeters || !data.durationSeconds) {
            throw new HttpsError('invalid-argument', 'ID de trajet manquant ET données GPS incomplètes.');
        }
        console.warn(`⚠️ Validation de trajet sans tripId explicite pour ${userId}, fallback sur données GPS.`);
    }

    const rawMode = (data.travelMode || 'walking').toString().toLowerCase();
    const travelMode = rawMode.includes('transit') ? 'transit' : (rawMode.includes('bicycling') || rawMode.includes('bike') ? 'bicycling' : 'walking');
    const cheatDetected = data.cheatDetected || false;
    const cheatReason = data.cheatReason || null;
    const startLocation = data.startLocation || null;
    const endLocation = data.endLocation || null;

    // Validation des défis
    let isVerifiedChallenge = false;
    let challengeReward = 0;
    if (challengeId) {
        if (challengeId.startsWith('poi_')) {
            // Défi local POI : vérification impérative de la position GPS utilisateur par rapport au lieu
            const userLoc = data.userLocation || data.endLocation;
            const poiLoc = data.poiLocation;
            if (!userLoc || !poiLoc || userLoc.latitude === undefined || poiLoc.latitude === undefined) {
                throw new HttpsError('invalid-argument', 'Coordonnées GPS utilisateur et POI obligatoires pour valider un défi de lieu.');
            }

            // Calcul distance Haversine
            const lat1 = Number(userLoc.latitude);
            const lon1 = Number(userLoc.longitude);
            const lat2 = Number(poiLoc.latitude);
            const lon2 = Number(poiLoc.longitude);
            const R = 6371e3; // mètres
            const φ1 = lat1 * Math.PI / 180;
            const φ2 = lat2 * Math.PI / 180;
            const Δφ = (lat2 - lat1) * Math.PI / 180;
            const Δλ = (lon2 - lon1) * Math.PI / 180;
            const a = Math.sin(Δφ / 2) * Math.sin(Δφ / 2) +
                Math.cos(φ1) * Math.cos(φ2) *
                Math.sin(Δλ / 2) * Math.sin(Δλ / 2);
            const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
            const distM = R * c;

            if (distM > 150.0) {
                console.warn(`⚠️ [ANTI-TRICHE POI] Utilisateur ${userId} trop éloigné du POI (${distM.toFixed(1)}m > 150m)`);
                throw new HttpsError('permission-denied', `Vous êtes trop éloigné du lieu du défi (${Math.round(distM)}m). Rapprochez-vous pour valider.`);
            }

            challengeReward = Math.min(Math.round(data.amountToAdd || 0), 300);
            isVerifiedChallenge = true;
        } else {
            const challengeDoc = await admin.firestore().collection('challenges').doc(challengeId).get();
            if (challengeDoc.exists && challengeDoc.data().active !== false) {
                isVerifiedChallenge = true;
                const cData = challengeDoc.data();
                challengeReward = Math.round(cData.reward_lame ?? cData.reward ?? 0);
                if (challengeReward <= 0) {
                    throw new HttpsError('invalid-argument', 'Récompense du défi non valide.');
                }
            } else {
                throw new HttpsError('not-found', 'Défi introuvable ou expiré.');
            }
        }
    }

    // Plafonnement du montant
    let amountToAdd = Math.round(data.amountToAdd || 0);
    if (isVerifiedChallenge) {
        if (challengeId && challengeId.startsWith('poi_')) {
            if (amountToAdd <= 0) {
                throw new HttpsError('invalid-argument', 'Montant de Lames pour le défi POI invalide.');
            }
            if (amountToAdd > 500) {
                console.warn(`⚠️ [ANTI-TRICHE SERVEUR] Récompense défi POI anormalement élevée (${amountToAdd}) par ${userId}`);
                throw new HttpsError('permission-denied', 'Montant de récompense défi POI trop élevé (maximum 500 Lames autorisées).');
            }
        } else {
            if (amountToAdd > challengeReward) {
                if (amountToAdd > challengeReward * 3.0) {
                    console.warn(`⚠️ [ANTI-TRICHE SERVEUR] Récompense de défi anormalement élevée (${amountToAdd} > ${challengeReward * 3.0}) par ${userId}`);
                    throw new HttpsError('permission-denied', 'Récompense de défi anormalement élevée (triche détectée).');
                }
            } else {
                amountToAdd = challengeReward; // Sécurité : on ne peut pas recevoir moins que la base
            }
        }
    }

    if (amountToAdd <= 0) {
        throw new HttpsError('invalid-argument', 'Montant de Lames invalide.');
    }

    // 🛡️ ANTI-TRICHE 1 : Si le client a déjà détecté une triche, on rejette immédiatement
    if (cheatDetected && !isVerifiedChallenge) {
        console.warn(`⚠️ [ANTI-TRICHE CLIENT] Trajet rejeté (${cheatReason}) par ${userId}`);
        throw new HttpsError('permission-denied', `Trajet invalide : ${cheatReason}`);
    }

    // Anti-triche 2 : Plafond max absolu de Lames par trajet (1500 pour trajets, 3000 pour défis vérifiés)
    const maxCeiling = isVerifiedChallenge ? 3000 : 1500;
    if (amountToAdd > maxCeiling) {
        console.warn(`⚠️ [ANTI-TRICHE] Tentative d'attribution suspecte (${amountToAdd} Lames, max: ${maxCeiling}) par ${userId} (source: ${source})`);
        throw new HttpsError('permission-denied', `Montant de Lames dépassant le plafond maximal autorisé (${maxCeiling}).`);
    }

    const userRef = admin.firestore().collection('users').doc(userId);
    const statsRef = admin.firestore().collection('user_stats').doc(userId);

    try {
        await admin.firestore().runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            const statsDoc = await transaction.get(statsRef);
            if (!userDoc.exists) {
                throw new HttpsError('not-found', 'Profil utilisateur introuvable.');
            }
            const statsData = statsDoc.exists ? statsDoc.data() : {};

            let dbDistanceMeters = Number(data.distanceMeters || 0);
            let dbDurationSeconds = Number(data.durationSeconds || 0);

            // 🚨 FIX 1 & 3 : VÉRIFICATION SERVEUR DES DONNÉES EN BD (trip_logs)
            let tripLogData = null;
            if (tripId && !isVerifiedChallenge) {
                const tripRef = userRef.collection('trip_logs').doc(tripId);
                const tripDoc = await transaction.get(tripRef);
                if (!tripDoc.exists) {
                    throw new HttpsError('not-found', 'Journal de trajet introuvable en base de données.');
                }

                tripLogData = tripDoc.data();
                if (tripLogData.cheat_detected === true) {
                    throw new HttpsError('permission-denied', 'Trajet marqué comme triché par le système.');
                }
                if (tripLogData.validation_status === 'validated') {
                    throw new HttpsError('already-exists', 'Ce trajet a déjà été validé.');
                }

                // Récupération stricte depuis la BD pour les calculs anti-triche
                dbDistanceMeters = Number(tripLogData.actual_distance_meters ?? dbDistanceMeters);
                dbDurationSeconds = Number(tripLogData.actual_duration_seconds ?? dbDurationSeconds);
            }

            // Validation physique et cohérence pour tout trajet classique (avec ou sans tripId)
            if (!isVerifiedChallenge) {
                if (dbDistanceMeters <= 0) {
                    throw new HttpsError('invalid-argument', 'Distance de trajet invalide.');
                }

                // Validation Physique Serveur
                if (dbDurationSeconds > 0) {
                    const speedKmh = (dbDistanceMeters / 1000) / (dbDurationSeconds / 3600);
                    const maxPhysicalSpeed = travelMode === 'bicycling' ? 70.0 : (travelMode === 'transit' ? 140.0 : 35.0);

                    if (speedKmh > maxPhysicalSpeed) {
                        console.warn(`⚠️ [ANTI-TRICHE SERVEUR] Vitesse physiquement impossible: ${speedKmh.toFixed(1)} km/h en ${travelMode} par ${userId}`);
                        throw new HttpsError('permission-denied', `Vitesse physiquement impossible détectée (${speedKmh.toFixed(1)} km/h). Trajet rejeté.`);
                    }
                }

                const baseMaxAllowed = Math.ceil((dbDistanceMeters / 1000) * 150) + 50;
                // On multiplie par 3.0 pour laisser une marge confortable aux multiplicateurs légitimes cumulés
                const maxAllowedForDistance = Math.ceil(baseMaxAllowed * 3.0);

                if (amountToAdd > maxAllowedForDistance) {
                    console.warn(`⚠️ [ANTI-TRICHE SERVEUR] Incohérence Lames/Distance: ${amountToAdd} Lames demandées pour ${(dbDistanceMeters / 1000).toFixed(2)}km par ${userId}`);
                    throw new HttpsError('permission-denied', `Montant de Lames incohérent avec la distance parcourue.`);
                }
            }

            // 🚨 FIX 3 : VÉRIFICATION QUE L'UTILISATEUR A BIEN COMMENCÉ LE DÉFI DANS user_challenges
            if (isVerifiedChallenge && challengeId) {
                const userChallengeRef = admin.firestore().collection('user_challenges').doc(`${userId}_${challengeId}`);
                const userChallengeDoc = await transaction.get(userChallengeRef);
                const validStatuses = ['inProgress', 'completedPendingReward', 'rewardClaimed'];

                if (challengeId.startsWith('poi_')) {
                    if (!userChallengeDoc.exists) {
                        throw new HttpsError('permission-denied', 'Défi POI non commencé ou introuvable dans vos défis.');
                    }
                    if (userChallengeDoc.data().reward_already_credited === true || userChallengeDoc.data().completed === true) {
                        throw new HttpsError('already-exists', 'Ce défi a déjà été validé et récompensé.');
                    }
                    transaction.set(userChallengeRef, {
                        user_id: userId,
                        challenge_id: challengeId,
                        reward_already_credited: true,
                        status: 'rewardClaimed',
                        completed_at: admin.firestore.FieldValue.serverTimestamp()
                    }, { merge: true });
                } else {
                    if (!userChallengeDoc.exists || !validStatuses.includes(userChallengeDoc.data().status)) {
                        throw new HttpsError('permission-denied', 'Défi non commencé ou invalide dans vos défis.');
                    }
                    if (userChallengeDoc.data().reward_already_credited === true || userChallengeDoc.data().completed === true) {
                        throw new HttpsError('already-exists', 'Ce défi a déjà été validé et récompensé.');
                    }
                    transaction.set(userChallengeRef, {
                        user_id: userId,
                        challenge_id: challengeId,
                        reward_already_credited: true,
                        status: 'rewardClaimed',
                        completed_at: admin.firestore.FieldValue.serverTimestamp()
                    }, { merge: true });
                }
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
                        throw new HttpsError('resource-exhausted', `Vous allez trop vite ! Veuillez attendre ${remainingSec}s avant de valider un autre trajet.`);
                    }
                }

                // Vérification de la cohérence de durée par rapport au début réel du trajet (si disponible dans trip_logs)
                if (tripLogData && tripLogData.started_at) {
                    const startedMs = typeof tripLogData.started_at.toMillis === 'function'
                        ? tripLogData.started_at.toMillis()
                        : new Date(tripLogData.started_at).getTime();
                    const tripElapsedSec = (now.toMillis() - startedMs) / 1000;
                    if (tripElapsedSec > 0 && dbDurationSeconds > tripElapsedSec + 180) {
                        console.warn(`⚠️ [ANTI-TRICHE SERVEUR] Durée déclarée (${dbDurationSeconds}s) supérieure au temps réel du trajet (${tripElapsedSec.toFixed(0)}s) pour ${userId}`);
                        throw new HttpsError('permission-denied', `Durée de trajet incohérente avec le temps réel écoulé.`);
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

            // Mise à jour sécurisée des statistiques côté serveur pour tout trajet réel
            if (isTripSource && dbDistanceMeters > 0) {
                const addedKm = dbDistanceMeters / 1000.0;
                let addedCals = 0;
                if (travelMode === 'bicycling') {
                    addedCals = Math.round(addedKm * 30);
                } else if (travelMode === 'walking') {
                    addedCals = Math.round(addedKm * 60);
                } // 0 calorie pour transit / bus
                updateData.total_distance_km = admin.firestore.FieldValue.increment(addedKm);
                updateData.total_trips_count = admin.firestore.FieldValue.increment(1);
                updateData.total_calories_burned = admin.firestore.FieldValue.increment(addedCals);
            }

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
        if (error instanceof HttpsError) throw error;
        throw new HttpsError('internal', error.message);
    }
});

// --- FONCTION 5 : ACHAT DE RÉCOMPENSE / BOUTIQUE SERVEUR ---
exports.purchaseShopItem = onCall(async (request) => {
    const data = request.data;
    const context = request;
    verifyAppCheck(context);
    console.log("🚀 [START] purchaseShopItem appelée");

    if (!context.auth) {
        throw new HttpsError('unauthenticated', 'Non authentifié');
    }
    verifyEmailVerified(context);

    const userId = context.auth.uid;
    const itemId = data.itemId;
    const itemTitle = data.itemTitle || 'Achat Boutique';

    const userRef = admin.firestore().collection('users').doc(userId);

    try {
        const result = await admin.firestore().runTransaction(async (transaction) => {
            // 1. Le SERVEUR détermine et vérifie le prix réel de l'objet
            let actualCost = 0;
            if (!itemId) {
                throw new HttpsError('invalid-argument', 'Identifiant de l\'objet (itemId) requis.');
            }

            const itemRef = admin.firestore().collection('shop_items').doc(itemId);
            let actualTitle = 'Achat Boutique';
            let itemType = 'Divers';

            const itemDoc = await transaction.get(itemRef);
            if (itemDoc.exists) {
                const iData = itemDoc.data();
                actualCost = Math.round(iData.cost_lame || iData.cost || 0);
                actualTitle = iData.name || actualTitle;
                itemType = iData.type || itemType;
            } else {
                const rewardRef = admin.firestore().collection('rewards').doc(itemId);
                const rewardDoc = await transaction.get(rewardRef);
                if (rewardDoc.exists) {
                    const rData = rewardDoc.data();
                    actualCost = Math.round(rData.cost_lame || rData.cost || 0);
                    actualTitle = rData.title || actualTitle;
                    itemType = rData.type || itemType;
                } else {
                    throw new HttpsError('not-found', 'Objet de boutique introuvable dans le catalogue.');
                }
            }

            if (data.cost && Math.round(data.cost) !== actualCost) {
                console.warn(`⚠️ [ALERTE SÉCURITÉ] Coût client (${data.cost}) ≠ coût serveur (${actualCost}) pour ${itemId} par ${userId}`);
            }

            if (actualCost <= 0) {
                throw new HttpsError('invalid-argument', 'Prix de l\'objet invalide.');
            }

            // 2. Le SERVEUR vérifie l'utilisateur
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new HttpsError('not-found', 'Profil utilisateur introuvable.');
            }

            const currentBalance = userDoc.data().lame_points || 0;
            if (currentBalance < actualCost) {
                throw new HttpsError('failed-precondition', 'Solde de Lames insuffisant.');
            }

            const newBalance = currentBalance - actualCost;

            // 3. Application de l'achat et de l'effet concret
            const userUpdate = {
                lame_points: newBalance,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            };
            const publicProfileUpdate = {
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            };

            // Application des effets selon le type
            if (itemType === 'Boost' || (itemId && itemId.startsWith('boost_'))) {
                const multiplier = itemId.includes('2_0') ? 2.0 : 1.5;
                userUpdate.active_boost_multiplier = multiplier;
                userUpdate.active_boost_expires_at = admin.firestore.Timestamp.fromMillis(Date.now() + 24 * 3600 * 1000);
            } else if (itemType === 'Badge' || (itemId && itemId.startsWith('badge_'))) {
                const badgeKey = itemId.replace('badge_', '') || 'eco_warrior';
                userUpdate.unlocked_badges = admin.firestore.FieldValue.arrayUnion(badgeKey);
                publicProfileUpdate.unlocked_badges = admin.firestore.FieldValue.arrayUnion(badgeKey);
            } else if (itemType === 'VIP' || (itemId && itemId.startsWith('vip_'))) {
                userUpdate.is_vip = true;
                userUpdate.vip_expires_at = admin.firestore.Timestamp.fromMillis(Date.now() + 7 * 24 * 3600 * 1000);
                publicProfileUpdate.is_vip = true;
            }

            transaction.update(userRef, userUpdate);
            const publicProfileRef = admin.firestore().collection('public_profiles').doc(userId);
            transaction.set(publicProfileRef, publicProfileUpdate, { merge: true });

            // Enregistrement de l'offre réclamée côté serveur (anti-triche)
            const claimedRef = admin.firestore().collection('user_claimed_offers').doc();
            transaction.set(claimedRef, {
                user_id: userId,
                user_email_contact: context.auth.token.email || 'inconnu',
                reward_id: itemId,
                details: { claimed_for_lame: actualCost, offer_title: actualTitle },
                claimed_at: admin.firestore.FieldValue.serverTimestamp(),
                status: 'approved'
            });

            const historyRef = userRef.collection('lame_history').doc();
            transaction.set(historyRef, {
                amount: -actualCost,
                source: `Achat: ${actualTitle}`,
                timestamp: admin.firestore.FieldValue.serverTimestamp()
            });

            return { newBalance, actualCost, actualTitle };
        });

        console.log(`✅ [ACHAT SERVEUR] -${result.actualCost} Lames pour ${userId} (${result.actualTitle}). Nouveau solde: ${result.newBalance}`);

        // Notification email transactionnelle
        try {
            const userEmail = context.auth?.token?.email;
            if (userEmail) {
                const safeTitle = esc(result.actualTitle);
                await admin.firestore().collection('mail').add({
                    to: userEmail,
                    message: {
                        subject: 'Confirmation de votre récompense EcoNav',
                        html: `<p>Bonjour,</p><p>Votre commande pour <strong>${safeTitle}</strong> (-${result.actualCost} Lames) a bien été enregistrée et activée sur votre compte.</p><p>Merci pour votre engagement écologique !</p>`
                    },
                    created_at: admin.firestore.FieldValue.serverTimestamp()
                });
            }
        } catch (mailErr) {
            console.warn("⚠️ Impossible d'enfiler l'email d'achat :", mailErr.message);
        }

        return { success: true, newBalance: result.newBalance, costDeducted: result.actualCost };

    } catch (error) {
        console.error("❌ Erreur purchaseShopItem :", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError('internal', error.message);
    }
});

// --- FONCTION 6 : RÉCOMPENSE QUOTIDIENNE DE CONNEXION SERVEUR ---
exports.claimDailyReward = onCall(async (request) => {
    const data = request.data;
    const context = request;
    verifyAppCheck(context);
    console.log("🚀 [START] claimDailyReward appelée");

    if (!context.auth) {
        throw new HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }
    verifyEmailVerified(context);

    const userId = context.auth.uid;
    const userRef = admin.firestore().collection('users').doc(userId);
    const statsRef = admin.firestore().collection('user_stats').doc(userId);

    try {
        const result = await admin.firestore().runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            const statsDoc = await transaction.get(statsRef);
            if (!userDoc.exists) {
                throw new HttpsError('not-found', 'Profil utilisateur introuvable.');
            }

            const userData = userDoc.data();
            const statsData = statsDoc.exists ? statsDoc.data() : {};
            const lastLoginTimestamp = statsData.last_login_date || userData.last_login_date;

            const now = new Date();
            // Normalisation à minuit UTC pour comparaison de jours calendaires stricts
            const todayUtc = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());

            let consecutiveLogins = statsData.consecutive_logins || userData.consecutive_logins || 0;
            let updated = false;

            if (lastLoginTimestamp) {
                const lastDate = lastLoginTimestamp.toDate();
                const lastUtc = Date.UTC(lastDate.getUTCFullYear(), lastDate.getUTCMonth(), lastDate.getUTCDate());
                const diffDays = Math.floor((todayUtc - lastUtc) / (1000 * 60 * 60 * 24));

                if (diffDays === 0) {
                    // Déjà connecté aujourd'hui
                    return {
                        updated: false,
                        consecutiveLogins: consecutiveLogins,
                        nextLevelBoost: statsData.next_level_boost || 1.0,
                        message: "Récompense déjà validée pour aujourd'hui."
                    };
                } else if (diffDays === 1) {
                    // Connexion le lendemain : série continue
                    consecutiveLogins += 1;
                    updated = true;
                } else {
                    // Plus d'un jour d'absence : série réinitialisée à 1
                    consecutiveLogins = 1;
                    updated = true;
                }
            } else {
                // Première connexion
                consecutiveLogins = 1;
                updated = true;
            }

            // Calcul du multiplicateur de série (palier tous les 5 jours, max +50%)
            const paliersActuels = Math.floor(consecutiveLogins / 5);
            const bonusSerie = Math.min(paliersActuels * 0.1, 0.5);
            const newNextLevelBoost = 1.0 + bonusSerie;

            const currentLame = userData.lame_points || 0;
            const currentTotalEarned = userData.total_lame_earned || 0;
            const newTotalEarned = currentTotalEarned + 1;

            const userUpdate = {
                lame_points: currentLame + 1,
                total_lame_earned: newTotalEarned,
                consecutive_logins: consecutiveLogins,
                last_login_date: admin.firestore.FieldValue.serverTimestamp(),
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            };

            checkAndApplyVipStatus(newTotalEarned, userUpdate);

            // Mise à jour users & user_stats synchronisée
            transaction.update(userRef, userUpdate);
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

            return {
                updated: true,
                consecutiveLogins,
                nextLevelBoost: newNextLevelBoost,
                newBalance: currentLame + 1,
                newTotalEarned: newTotalEarned
            };
        });

        return { success: true, ...result };

    } catch (error) {
        if (error instanceof HttpsError) throw error;
        console.error("❌ Erreur claimDailyReward :", error);
        throw new HttpsError('internal', error.message);
    }
});

// --- FONCTION 7 : ACHAT DE TICKETS DE LOTERIE (RAFFLE) SERVEUR ---
exports.purchaseRaffleTicket = onCall(async (request) => {
    const data = request.data;
    const context = request;
    verifyAppCheck(context);
    console.log("🚀 [START] purchaseRaffleTicket appelée");

    if (!context.auth) {
        throw new HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const userId = context.auth.uid;
    const contestId = data.contestId;
    const ticketCount = Math.round(data.ticketCount || 0);

    if (!contestId || ticketCount <= 0 || ticketCount > 1000) {
        throw new HttpsError('invalid-argument', 'Nombre de tickets invalide (1 à 1000 max par achat).');
    }

    const userRef = admin.firestore().collection('users').doc(userId);
    const userStatsRef = admin.firestore().collection('user_stats').doc(userId);
    const rewardRef = admin.firestore().collection('rewards').doc(contestId);
    const contestStateRef = admin.firestore().collection('contest_state').doc(contestId);

    try {
        const result = await admin.firestore().runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new HttpsError('not-found', 'Profil utilisateur introuvable.');
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
                    throw new HttpsError('not-found', 'Concours ou loterie introuvable.');
                }
            }

            const contestStateDoc = await transaction.get(contestStateRef);
            const contestStateData = contestStateDoc.exists ? contestStateDoc.data() : {};

            if (contestData.status && contestData.status !== 'open') {
                throw new HttpsError('failed-precondition', 'Le concours n\'est pas ouvert.');
            }

            const rawEndDate = contestData.end_date || contestData.details_json?.end_date;
            let endDate = null;
            if (rawEndDate) {
                endDate = typeof rawEndDate.toDate === 'function' ? rawEndDate.toDate() : new Date(rawEndDate);
                if (isNaN(endDate.getTime())) endDate = null;
            }
            if (endDate && Date.now() > endDate.getTime()) {
                throw new HttpsError('failed-precondition', 'Ce concours est terminé.');
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
                throw new HttpsError('failed-precondition', `Fonds insuffisants (${currentLame} Lames disponibles, ${totalCost} requises).`);
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

            // Incrémenter les tickets du concours dans contest_state ET dans rewards/contests
            const currentTickets = contestStateData.total_tickets_sold ?? contestData?.details_json?.total_tickets_sold ?? contestData?.total_tickets_sold ?? 0;
            const newTotalTickets = currentTickets + ticketCount;

            transaction.set(contestStateRef, {
                total_tickets_sold: newTotalTickets,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });

            if (contestDoc.ref) {
                const currentDetails = contestData.details_json || {};
                transaction.set(contestDoc.ref, {
                    total_tickets_sold: newTotalTickets,
                    details_json: {
                        ...currentDetails,
                        total_tickets_sold: newTotalTickets
                    },
                    updated_at: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });
            }

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
        if (error instanceof HttpsError) throw error;
        throw new HttpsError('internal', error.message);
    }
});

// --- FONCTION 8 : ENCHÈRES SÉCURISÉES SERVEUR ---
exports.placeBid = onCall(async (request) => {
    const data = request.data;
    const context = request;
    verifyAppCheck(context);
    console.log("🚀 [START] placeBid appelée");

    if (!context.auth) {
        throw new HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const userId = context.auth.uid;
    const contestId = data.contestId;
    const bidAmount = parseFloat(data.bidAmount);

    if (!contestId || isNaN(bidAmount) || bidAmount <= 0) {
        throw new HttpsError('invalid-argument', 'Paramètres d\'enchère invalides.');
    }

    const userRef = admin.firestore().collection('users').doc(userId);
    const userStatsRef = admin.firestore().collection('user_stats').doc(userId);
    const rewardRef = admin.firestore().collection('rewards').doc(contestId);
    const contestStateRef = admin.firestore().collection('contest_state').doc(contestId);

    try {
        const result = await admin.firestore().runTransaction(async (transaction) => {
            const userDoc = await transaction.get(userRef);
            if (!userDoc.exists) {
                throw new HttpsError('not-found', 'Profil utilisateur introuvable.');
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
                    throw new HttpsError('resource-exhausted', `Veuillez patienter ${remainingSec}s entre chaque enchère.`);
                }
            }

            let contestDoc = await transaction.get(rewardRef);
            if (!contestDoc.exists) {
                const contestRef = admin.firestore().collection('contests').doc(contestId);
                const legacyDoc = await transaction.get(contestRef);
                if (legacyDoc.exists) {
                    contestDoc = legacyDoc;
                } else {
                    throw new HttpsError('not-found', 'Enchère introuvable.');
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
                throw new HttpsError('failed-precondition', 'L\'enchère n\'est pas ouverte.');
            }

            const rawEndDate = contestData.end_date || contestData.details_json?.end_date;
            let endDate = null;
            if (rawEndDate) {
                endDate = typeof rawEndDate.toDate === 'function' ? rawEndDate.toDate() : new Date(rawEndDate);
                if (isNaN(endDate.getTime())) endDate = null;
            }
            if (endDate && Date.now() > endDate.getTime()) {
                throw new HttpsError('failed-precondition', 'Cette enchère est terminée.');
            }

            const minNextBid = currentHighestBid > 0 ? Math.ceil(currentHighestBid) + 1.0 : minBid;
            if (bidAmount < minNextBid) {
                throw new HttpsError('failed-precondition', `L'enchère doit être d'au moins ${minNextBid} Lames.`);
            }

            const oldBidderId = contestStateData.highest_bidder_user_id || contestData.highest_bidder_user_id;

            let amountToDeduct = bidAmount;
            if (oldBidderId && oldBidderId === userId) {
                // L'utilisateur se surenchérit lui-même : on ne déduit que la différence
                amountToDeduct = bidAmount - currentHighestBid;
            }

            const userLame = userDoc.data().lame_points || 0;
            if (userLame < amountToDeduct) {
                throw new HttpsError('failed-precondition', `Solde de Lames insuffisant (${userLame} disponibles, ${amountToDeduct} requises pour cette surenchère).`);
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
        if (error instanceof HttpsError) throw error;
        throw new HttpsError('internal', error.message);
    }
});

// ════════════════════════════════════════════════════════════════════════════
// --- FONCTION 8 : OPTIMISATION CLASSEMENT (SCHEDULED 1H -> 1 READ FIRESTORE) ---
// ════════════════════════════════════════════════════════════════════════════
exports.updateDailyLeaderboard = onSchedule('every 1 hours', async (event) => {
    console.log("🚀 [SCHEDULED] Agrégation du Top 100 dans leaderboards/daily_top");

    try {
        const snapshot = await admin.firestore()
            .collection('public_profiles')
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
                unlocked_badges: data.unlocked_badges || []
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

exports.deleteUserAccount = onCall({ timeoutSeconds: 300, memory: '512MiB' }, async (request) => {
    const data = request.data;
    const context = request;
    verifyAppCheck(context);
    if (!context.auth) {
        throw new HttpsError('unauthenticated', 'Utilisateur non authentifié');
    }

    const userId = context.auth.uid;
    console.log(`⚠️ [RGPD] Suppression définitive du compte et des données pour ${userId}`);

    // Protection Item 143: Exiger un login récent (< 15 minutes)
    const authTime = context.auth.token?.auth_time;
    const currentTimeSec = Math.floor(Date.now() / 1000);
    if (authTime && (currentTimeSec - authTime) > 900) {
        throw new HttpsError('unauthenticated', 'Par mesure de sécurité, veuillez vous reconnecter avant de supprimer définitivement votre compte.');
    }

    let userEmail = context.auth.token?.email;
    if (!userEmail) {
        try {
            const uRec = await admin.auth().getUser(userId);
            userEmail = uRec.email;
        } catch (_) { }
    }

    try {
        const userRef = admin.firestore().collection('users').doc(userId);

        // Helper pour exécuter la suppression par lot de 400 documents max (limite 500 max par batch)
        const deleteQueryDocsChunked = async (querySnapshot) => {
            if (querySnapshot.empty) return;
            const chunks = chunkArray(querySnapshot.docs, 400);
            for (const chunk of chunks) {
                const batch = admin.firestore().batch();
                chunk.forEach(doc => batch.delete(doc.ref));
                await batch.commit();
            }
        };

        // 1. Annulation des abonnements Stripe (Item 142)
        if (stripe) {
            try {
                const userDocSnap = await userRef.get();
                const customerId = userDocSnap.data()?.stripe_customer_id;
                if (customerId) {
                    const subs = await stripe.subscriptions.list({ customer: customerId, status: 'active' });
                    for (const sub of subs.data) {
                        await stripe.subscriptions.cancel(sub.id);
                        console.log(`[RGPD] Abonnement Stripe ${sub.id} annulé pour ${userId}`);
                    }
                }
            } catch (stripeErr) {
                console.warn(`⚠️ Erreur annulation abonnements Stripe pour ${userId}:`, stripeErr.message);
            }
        }

        // 2. Supprimer l'historique des lames, trajets et cashback (sous-collections)
        const historyDocs = await userRef.collection('lame_history').get();
        await deleteQueryDocsChunked(historyDocs);

        const tripDocs = await userRef.collection('trip_logs').get();
        await deleteQueryDocsChunked(tripDocs);

        const cbSubDocs = await userRef.collection('cashback_history').get();
        await deleteQueryDocsChunked(cbSubDocs);

        // 3. Supprimer toutes les données liées dans les collections principales (Item 142)
        const collectionsToDelete = [
            'user_claimed_offers',
            'user_challenges',
            'contest_entries',
            'cashback_claims',
            'ocr_validations',
            'campaign_donations'
        ];
        for (const col of collectionsToDelete) {
            const snapshot = await admin.firestore().collection(col).where('user_id', '==', userId).get();
            await deleteQueryDocsChunked(snapshot);
        }

        // 4. Supprimer les e-mails de la collection mail (Item 142)
        if (userEmail) {
            const mailToDocs = await admin.firestore().collection('mail').where('to', '==', userEmail).get();
            await deleteQueryDocsChunked(mailToDocs);

            const claimedContactDocs = await admin.firestore().collection('user_claimed_offers').where('user_email_contact', '==', userEmail).get();
            await deleteQueryDocsChunked(claimedContactDocs);
        }
        const mailUserDocs = await admin.firestore().collection('mail').where('user_id', '==', userId).get();
        await deleteQueryDocsChunked(mailUserDocs);

        // 5. Supprimer la réservation de pseudo dans /usernames (Item 142)
        const usernameDocs = await admin.firestore().collection('usernames').where('uid', '==', userId).get();
        await deleteQueryDocsChunked(usernameDocs);

        // 6. Anonymiser les enchères (auctions) et tickets de tombola (raffle_tickets) (Item 142)
        const auctionsSnap = await admin.firestore().collection('auctions').where('highest_bidder', '==', userId).get();
        if (!auctionsSnap.empty) {
            for (const doc of auctionsSnap.docs) {
                await doc.ref.update({
                    highest_bidder: 'deleted_user',
                    highest_bidder_name: 'Utilisateur supprimé'
                });
            }
        }

        const rafflesSnap = await admin.firestore().collection('raffle_tickets').where('user_id', '==', userId).get();
        if (!rafflesSnap.empty) {
            const chunks = chunkArray(rafflesSnap.docs, 400);
            for (const chunk of chunks) {
                const b = admin.firestore().batch();
                chunk.forEach(doc => b.update(doc.ref, {
                    user_id: 'deleted_user',
                    username: 'Utilisateur supprimé'
                }));
                await b.commit();
            }
        }

        // 7. Supprimer les fichiers Cloud Storage associés (preuves de défis, tickets) (Item 142)
        try {
            const bucket = admin.storage().bucket();
            await bucket.deleteFiles({ prefix: `challenge_proofs/${userId}/`, force: true });
            await bucket.deleteFiles({ prefix: `receipts/${userId}/`, force: true });
        } catch (storageErr) {
            console.warn(`⚠️ Erreur suppression Storage pour ${userId}:`, storageErr.message);
        }

        // 8. Anonymiser les transactions magasins et les magasins créés par l'utilisateur
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

        // 9. Supprimer le document profil utilisateur, user_stats et public_profiles (Item 142)
        await userRef.delete();
        await admin.firestore().collection('user_stats').doc(userId).delete();
        await admin.firestore().collection('public_profiles').doc(userId).delete();

        // 10. Supprimer le compte Firebase Auth (avec capture d'erreur si déjà supprimé)
        try {
            await admin.auth().deleteUser(userId);
        } catch (authErr) {
            console.warn(`⚠️ Compte Auth pour ${userId} introuvable ou déjà supprimé:`, authErr.message);
        }

        console.log(`✅ [RGPD] Compte et données de ${userId} définitivement supprimés.`);
        return { success: true };
    } catch (error) {
        console.error("❌ Erreur suppression de compte:", error);
        if (error instanceof HttpsError) throw error;
        throw new HttpsError('internal', error.message);
    }
});

// ===========================================================================
// 🛡️ NOUVEAU : ANTI-TRICHE POUR LES PUBS, BOOSTS ET DONS
// ===========================================================================

// --- 1. Regarder une pub générale (Ad Points) ---
exports.addAdPoint = onCall(async (request) => {
    const data = request.data;
    const context = request;
    verifyAppCheck(context);
    if (!context.auth) throw new HttpsError('unauthenticated', 'Non autorisé');
    verifyEmailVerified(context);

    const userId = context.auth.uid;
    const userRef = admin.firestore().collection('users').doc(userId);
    const statsRef = admin.firestore().collection('user_stats').doc(userId);

    return admin.firestore().runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const statsDoc = await transaction.get(statsRef);
        if (!userDoc.exists) throw new HttpsError('not-found', 'Profil introuvable.');

        const statsData = statsDoc.exists ? statsDoc.data() : {};
        const userData = userDoc.data();
        const lastAdTime = statsData.last_ad_point_timestamp;
        const now = admin.firestore.Timestamp.now();
        if (lastAdTime) {
            const elapsedMs = now.toMillis() - lastAdTime.toMillis();
            if (elapsedMs < 30000) {
                const remainingSec = Math.ceil((30000 - elapsedMs) / 1000);
                throw new HttpsError('resource-exhausted', `Veuillez patienter ${remainingSec}s avant de regarder une autre publicité.`);
            }
        }

        const currentPoints = statsData.ad_points ?? 0;

        if (currentPoints >= 50) {
            throw new HttpsError('resource-exhausted', 'Max Ad Points atteints.');
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
exports.addStoreBoost = onCall(async (request) => {
    const data = request.data;
    const context = request;
    verifyAppCheck(context);
    if (!context.auth) throw new HttpsError('unauthenticated', 'Non autorisé');

    const storeId = data.storeId;
    if (!storeId) throw new HttpsError('invalid-argument', 'Store ID manquant');

    const userId = context.auth.uid;
    const userRef = admin.firestore().collection('users').doc(userId);
    const statsRef = admin.firestore().collection('user_stats').doc(userId);
    const storeRef = admin.firestore().collection('stores').doc(storeId);

    return admin.firestore().runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const statsDoc = await transaction.get(statsRef);
        const storeDoc = await transaction.get(storeRef);

        if (!userDoc.exists) throw new HttpsError('not-found', 'Profil introuvable.');

        const userData = userDoc.data();
        const statsData = statsDoc.exists ? statsDoc.data() : {};

        const lastBoostTime = statsData.last_store_boost_timestamp;
        const now = admin.firestore.Timestamp.now();
        if (lastBoostTime) {
            const elapsedMs = now.toMillis() - lastBoostTime.toMillis();
            if (elapsedMs < 30000) {
                const remainingSec = Math.ceil((30000 - elapsedMs) / 1000);
                throw new HttpsError('resource-exhausted', `Veuillez patienter ${remainingSec}s entre deux boosts de magasin.`);
            }
        }

        // 🚨 FIX 4 : Protection anti-bot : limite quotidienne de 10 boosts par jour et par magasin
        const todayStr = new Date().toISOString().split('T')[0];
        const boostDailyKey = `boosts_${storeId}_${todayStr}`;
        const dailyBoosts = statsData[boostDailyKey] || 0;

        if (dailyBoosts >= 10) {
            throw new HttpsError('resource-exhausted', 'Limite quotidienne de boosts atteinte pour ce magasin (10 max par jour).');
        }

        const isVip = userData.is_vip === true;
        const storeHasBoost = storeDoc.exists && storeDoc.data().is_premium_ad_boost_enabled === true;
        const cashbackRate = storeDoc.exists ? (storeDoc.data().cashback_rate || 0.05) : 0.05;

        const effectivelySuperPremium = isVip && storeHasBoost;
        const effectivelyPremium = isVip || storeHasBoost;

        const storeBoosts = statsData.store_boosts || {};
        const boostEntry = storeBoosts[storeId];
        let currentBoost = boostEntry?.amount || 0.0;
        if (currentBoost > 0 && boostEntry?.last_update) {
            currentBoost = calculateDecayedBoost(currentBoost, boostEntry.last_update, isVip);
        }

        let gain = 0.01;
        if (currentBoost >= 1.0) {
            gain = effectivelySuperPremium ? 0.8 : (effectivelyPremium ? 0.4 : 0.2);
        } else {
            gain = effectivelySuperPremium ? 0.04 : (effectivelyPremium ? 0.02 : 0.01);
        }

        let maxCap = Math.max(cashbackRate * 100.0, 1.0);
        let newAmount = Math.min(currentBoost + gain, maxCap);

        // Nettoyage et mise à jour de la map des boosts imbriquée
        const currentStoreBoosts = statsData.store_boosts || {};
        const updatedStoreBoosts = { ...currentStoreBoosts };
        if (newAmount <= 0) {
            delete updatedStoreBoosts[storeId];
        } else {
            updatedStoreBoosts[storeId] = {
                amount: newAmount,
                last_update: admin.firestore.FieldValue.serverTimestamp()
            };
        }

        transaction.set(statsRef, {
            last_store_boost_timestamp: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
            [boostDailyKey]: dailyBoosts + 1,
            store_boosts: updatedStoreBoosts
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
exports.processDonation = onCall(async (request) => {
    const data = request.data;
    const context = request;
    verifyAppCheck(context);
    if (!context.auth) throw new HttpsError('unauthenticated', 'Non autorisé');

    // NOUVEAU : Récupération du flag d'anonymat
    const { amount, offerId, offerTitle, email, isInstantApproval, isAnonymous } = data;
    const userId = context.auth.uid;
    const userRef = admin.firestore().collection('users').doc(userId);
    const claimedRef = admin.firestore().collection('user_claimed_offers').doc();

    return admin.firestore().runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        if (!userDoc.exists) {
            throw new HttpsError('not-found', 'Profil utilisateur introuvable.');
        }

        let cost = 0;
        let isCampaign = false;

        const isSpecialDonation = offerId === 'plant_tree_action' || (typeof offerId === 'string' && offerId.startsWith('sdg_donation_'));

        if (offerId && !isSpecialDonation) {
            const rewardRef = admin.firestore().collection('rewards').doc(offerId);
            const rewardDoc = await transaction.get(rewardRef);
            if (!rewardDoc.exists) {
                throw new HttpsError('not-found', 'Offre introuvable dans le catalogue.');
            }
            const rData = rewardDoc.data();

            if (rData.is_active === false) {
                throw new HttpsError('failed-precondition', 'Cette offre n\'est plus disponible.');
            }
            if (rData.expiry_date) {
                const expMillis = typeof rData.expiry_date.toMillis === 'function'
                    ? rData.expiry_date.toMillis()
                    : new Date(rData.expiry_date).getTime();
                if (!isNaN(expMillis) && expMillis < Date.now()) {
                    throw new HttpsError('failed-precondition', 'Cette offre a expiré.');
                }
            }
            if (rData.stock !== undefined && rData.stock !== null && rData.stock <= 0) {
                throw new HttpsError('failed-precondition', 'Cette offre est épuisée (stock insuffisant).');
            }

            const fetchedCost = rData.eco_cost ?? rData.cost_lame ?? rData.cost;
            if (rData.details_json || rData.type === 'campaignDonation' || rData.type === 'campaign') {
                const userAmount = parseFloat(amount);
                const minCost = (fetchedCost !== undefined && !isNaN(parseFloat(fetchedCost)) && parseFloat(fetchedCost) > 0)
                    ? parseFloat(fetchedCost)
                    : 10;
                if (!isNaN(userAmount) && userAmount >= minCost) {
                    cost = userAmount;
                } else if (fetchedCost !== undefined && !isNaN(parseFloat(fetchedCost)) && parseFloat(fetchedCost) > 0) {
                    cost = parseFloat(fetchedCost);
                } else {
                    cost = 10;
                }
            } else if (fetchedCost !== undefined && fetchedCost !== null && !isNaN(parseFloat(fetchedCost))) {
                cost = parseFloat(fetchedCost);
                if (cost < 0) {
                    throw new HttpsError('invalid-argument', 'Coût de l\'offre invalide.');
                }
            } else {
                throw new HttpsError('invalid-argument', 'Coût de l\'offre invalide.');
            }

            // Décrémenter le stock si applicable
            if (rData.stock !== undefined && rData.stock !== null && rData.stock > 0) {
                transaction.update(rewardRef, {
                    stock: admin.firestore.FieldValue.increment(-1),
                    updated_at: admin.firestore.FieldValue.serverTimestamp()
                });
            }

            // Si c'est une campagne solidaire, on met à jour les détails de la campagne
            if (rData.details_json) {
                isCampaign = true;
                const currentDetails = rData.details_json || {};
                const currentAmt = Number(currentDetails.current_amount_eco || 0);
                const currentDonors = Number(currentDetails.current_donors || 0);

                currentDetails.current_amount_eco = currentAmt + cost;
                currentDetails.current_donors = currentDonors + 1;

                transaction.update(rewardRef, {
                    details_json: currentDetails,
                    updated_at: admin.firestore.FieldValue.serverTimestamp()
                });

                // Enregistrer le don dans la collection campaign_donations pour le classement
                const donationRef = admin.firestore().collection('campaign_donations').doc();
                const userData = userDoc.data();
                transaction.set(donationRef, {
                    campaign_id: offerId,
                    user_id: isAnonymous ? 'anonymous' : userId,
                    username: isAnonymous ? 'Anonyme' : (userData.username || 'Utilisateur'),
                    amount_eco: cost,
                    created_at: admin.firestore.FieldValue.serverTimestamp(),
                });
            }
        } else {
            const rawCost = parseFloat(amount);
            if (isNaN(rawCost) || rawCost <= 0) {
                throw new HttpsError('invalid-argument', 'Montant de don invalide.');
            }
            if (offerId === 'plant_tree_action' && rawCost < 1000) {
                throw new HttpsError('invalid-argument', 'Planter un arbre nécessite au moins 1000 Lames.');
            }
            if (!offerId && (rawCost < 100 || rawCost > 5000)) {
                throw new HttpsError('invalid-argument', 'Montant de don libre invalide (minimum 100, maximum 5000 Lames).');
            }
            cost = rawCost;
        }

        const currentLame = userDoc.data().lame_points || 0;
        if (currentLame < cost) {
            throw new HttpsError('failed-precondition', 'Fonds insuffisants.');
        }

        transaction.update(userRef, {
            lame_points: admin.firestore.FieldValue.increment(-cost),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });

        const safeOfferTitle = offerTitle || 'Offre / Don';

        transaction.set(claimedRef, {
            user_id: userId,
            user_email_contact: context.auth.token.email || 'inconnu',
            reward_id: offerId || 'donation',
            is_anonymous: isAnonymous || false,
            details: { claimed_for_lame: cost, offer_title: safeOfferTitle },
            claimed_at: admin.firestore.FieldValue.serverTimestamp(),
            status: isInstantApproval ? 'approved' : 'pending',
        });

        const historyRef = userRef.collection('lame_history').doc();
        transaction.set(historyRef, {
            amount: -cost,
            source: `Dépense : ${safeOfferTitle}`,
            timestamp: admin.firestore.FieldValue.serverTimestamp()
        });

        const donationResult = { success: true, newBalance: currentLame - cost };

        // Notification email transactionnelle pour le don (destinée UNIQUEMENT à l'email certifié du token)
        try {
            const userEmail = context.auth?.token?.email;
            if (userEmail) {
                const safeHtmlTitle = esc(safeOfferTitle);
                await admin.firestore().collection('mail').add({
                    to: userEmail,
                    message: {
                        subject: 'Merci pour votre don EcoNav ! 🌱',
                        html: `<p>Bonjour,</p><p>Nous confirmons la prise en compte de votre contribution de <strong>${cost} Lames</strong> pour : <strong>${safeHtmlTitle}</strong>.</p><p>Merci d'agir pour un avenir durable !</p>`
                    },
                    created_at: admin.firestore.FieldValue.serverTimestamp()
                });
            }
        } catch (mailErr) {
            console.warn("⚠️ Impossible d'enfiler l'email de don :", mailErr.message);
        }

        return donationResult;
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
            lossAmount = 0.06;
        } else if (simulatedAmount >= 0.50) {
            stepMinutes = 10;
            lossAmount = 0.05;
        } else if (simulatedAmount >= 0.40) {
            stepMinutes = 15;
            lossAmount = 0.04;
        } else if (simulatedAmount >= 0.30) {
            stepMinutes = 20;
            lossAmount = 0.03;
        } else if (simulatedAmount >= 0.20) {
            stepMinutes = 25;
            lossAmount = 0.02;
        } else if (simulatedAmount >= 0.10) {
            stepMinutes = 30;
            lossAmount = 0.01;
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
exports.claimCashback = onCall(async (request) => {
    const data = request.data;
    const context = request;
    verifyAppCheck(context);
    if (!context.auth) throw new HttpsError('unauthenticated', 'Non autorisé');
    verifyEmailVerified(context);

    const { storeId, receiptToken, rawText } = data;
    const userId = context.auth.uid;

    if (!storeId) {
        throw new HttpsError('invalid-argument', 'Store ID manquant.');
    }

    // 🚨 FIX 2 : Exiger le jeton de validation OCR éphémère émis par Document AI / Gemini
    if (!receiptToken) {
        throw new HttpsError('invalid-argument', 'Jeton de validation OCR manquant. Veuillez d\'abord scanner votre reçu.');
    }

    const userRef = admin.firestore().collection('users').doc(userId);
    const statsRef = admin.firestore().collection('user_stats').doc(userId);
    const storeRef = admin.firestore().collection('stores').doc(storeId);
    const ocrRef = admin.firestore().collection('ocr_validations').doc(receiptToken);

    const transactionResult = await admin.firestore().runTransaction(async (transaction) => {
        // 🚨 FIX 2 : Vérification atomique du jeton OCR
        const ocrDoc = await transaction.get(ocrRef);
        if (!ocrDoc.exists) {
            throw new HttpsError('not-found', 'Jeton de validation du reçu introuvable ou expiré.');
        }
        const ocrData = ocrDoc.data();

        if (ocrData.user_id !== userId) {
            throw new HttpsError('permission-denied', 'Ce jeton de validation ne correspond pas à votre compte.');
        }

        if (ocrData.used === true) {
            throw new HttpsError('already-exists', 'Ce reçu a déjà été réclamé.');
        }

        if (ocrData.expires_at && ocrData.expires_at.toMillis() < Date.now()) {
            throw new HttpsError('deadline-exceeded', 'Le jeton de validation du reçu a expiré (limite de 5 minutes).');
        }

        const validText = (ocrData.extracted_text || rawText || '').trim();

        // 🚨 FIX 8 : Utilisation prioritaire du montant certifié par l'IA/OCR
        let rawAmount = Number(ocrData.extracted_amount);
        if (!rawAmount || isNaN(rawAmount) || rawAmount <= 0 || rawAmount > 500.0) {
            // Fallback éventuel par regex si extracted_amount n'était pas renseigné
            if (validText) {
                const matches = validText.match(/(?:total|net|montant|paye|cb|carte|eur|€)[^\d]*(\d+[\.,]\d{2})/gi);
                if (matches && matches.length > 0) {
                    for (let i = matches.length - 1; i >= 0; i--) {
                        const numMatch = matches[i].match(/(\d+[\.,]\d{2})/);
                        if (numMatch) {
                            const parsedVal = parseFloat(numMatch[1].replace(',', '.'));
                            if (parsedVal > 0.50 && parsedVal <= 500.0) {
                                rawAmount = parsedVal;
                                break;
                            }
                        }
                    }
                }
            }
        }

        if (!rawAmount || isNaN(rawAmount) || rawAmount <= 0) {
            throw new HttpsError('invalid-argument', 'Montant total invalide ou introuvable sur le ticket certifié.');
        }

        const isCapped = rawAmount > 100.0;
        const amount = Math.min(rawAmount, 100.0); // Plafond anti-triche 100€

        // Empreinte anti-rejeu déterministe et robuste
        const cleanDate = (ocrData.extracted_date || '').toString().trim();
        const receiptNumber = (ocrData.extracted_receipt_number || ocrData.receipt_number || '').toString().trim();
        const receiptHash = crypto.createHash('sha256')
            .update(`${storeId}_${amount.toFixed(2)}_${cleanDate || 'nodate'}_${receiptNumber || receiptToken}`)
            .digest('hex');

        // TOUTES LES LECTURES DE LA TRANSACTION SONT EFFECTUÉES EN PREMIER
        const claimRef = admin.firestore().collection('cashback_claims').doc(receiptHash);
        const claimDoc = await transaction.get(claimRef);
        if (claimDoc.exists) {
            throw new HttpsError('already-exists', 'Ce ticket de caisse a déjà été scanné et validé.');
        }

        const userDoc = await transaction.get(userRef);
        const statsDoc = await transaction.get(statsRef);
        const storeDoc = await transaction.get(storeRef);

        if (!userDoc.exists || !storeDoc.exists) {
            throw new HttpsError('not-found', 'Utilisateur ou magasin introuvable.');
        }

        const userData = userDoc.data();
        const statsData = statsDoc.exists ? statsDoc.data() : {};
        const storeData = storeDoc.data();

        // Sécurité anti-fraude : Le commerçant ne peut pas réclamer de cashback dans sa propre boutique
        if (storeData.owner_id === userId || storeData.user_id === userId) {
            throw new HttpsError('permission-denied', 'Vous ne pouvez pas réclamer de cashback dans votre propre magasin.');
        }

        let storeUpdates = {};

        // 1. Calcul des taux (Le serveur récupère les vraies données)
        let baseRate = (storeData.cashback_rate || 0.05) * 100.0;
        if (storeData.is_visibility_boost_enabled) baseRate += 1.0;

        // Calcul Serveur de la Décroissance Temporelle (Decay) du Boost
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

        // --- 4. TOUTES LES ÉCRITURES SÉCURISÉES DE LA TRANSACTION ---

        if (Object.keys(storeUpdates).length > 0) {
            transaction.update(storeRef, storeUpdates);
        }

        // Marquer le jeton OCR comme consommé
        transaction.update(ocrRef, {
            used: true,
            claimed_at: admin.firestore.FieldValue.serverTimestamp()
        });

        // Enregistrer la réclamation pour éviter le rejeu
        transaction.set(claimRef, {
            user_id: userId,
            store_id: storeId,
            amount_spent: amount,
            raw_amount: rawAmount,
            is_capped: isCapped,
            receipt_token: receiptToken,
            claimed_at: admin.firestore.FieldValue.serverTimestamp()
        });

        // Mise à jour du profil utilisateur (users)
        const userUpdate = {
            lame_points: admin.firestore.FieldValue.increment(lameBonus),
            total_lame_earned: admin.firestore.FieldValue.increment(lameBonus)
        };
        checkAndApplyVipStatus(newTotalLameEarned, userUpdate);
        transaction.update(userRef, userUpdate);

        // Synchronisation du profil public pour le classement
        const publicProfileRef = admin.firestore().collection('public_profiles').doc(userId);
        transaction.set(publicProfileRef, {
            total_lame_earned: newTotalLameEarned,
            current_level: currentLevel,
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        // Mise à jour de la progression de fidélité (user_stats) sans écraser les autres magasins
        const newVisits = (storeProgress.visits || 0) + 1;
        const newSpend = (storeProgress.spend || 0) + amount;
        if (statsDoc.exists) {
            transaction.update(statsRef, {
                [`loyalty_progress.${storeId}`]: {
                    visits: newVisits,
                    spend: newSpend
                },
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });
        } else {
            transaction.set(statsRef, {
                loyalty_progress: {
                    [storeId]: {
                        visits: newVisits,
                        spend: newSpend
                    }
                },
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });
        }

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

        return { cashbackAmount, lameBonus, totalRate, is_capped: isCapped, rawAmount, amount, storeName: storeData.name || 'Magasin' };
    });

    // 5. Notification Push & In-App automatique
    await sendNotification(
        userId,
        "Cashback validé ! 💰",
        `+${transactionResult.cashbackAmount.toFixed(2)}€ et +${transactionResult.lameBonus} Lames crédités pour votre achat chez ${transactionResult.storeName}.`,
        { type: 'cashback', store_id: storeId, cashback_amount: String(transactionResult.cashbackAmount) }
    );

    // 6. Notification email transactionnelle automatique (mail/{mailId})
    try {
        const userEmail = context.auth?.token?.email;
        if (userEmail && transactionResult?.cashbackAmount) {
            await admin.firestore().collection('mail').add({
                to: userEmail,
                message: {
                    subject: 'Cashback validé sur votre achat EcoNav !',
                    html: `<p>Bonjour,</p><p>Votre ticket de caisse a été validé avec succès.</p><p>Cashback obtenu : <strong>${transactionResult.cashbackAmount.toFixed(2)}€</strong> (+${transactionResult.lameBonus} Lames bonus).</p>${transactionResult.is_capped ? '<p><em>Note : Le montant pris en compte pour le cashback est plafonné à 100,00 € par ticket conformément à nos conditions générales.</em></p>' : ''}<p>Bravo pour votre démarche éco-responsable !</p>`
                },
                created_at: admin.firestore.FieldValue.serverTimestamp()
            });
        }
    } catch (mailErr) {
        console.warn("⚠️ Impossible d'enfiler l'email de cashback :", mailErr.message);
    }

    return transactionResult;
});

// ════════════════════════════════════════════════════════════════════════════
// 🗑️ NETTOYAGE AUTOMATIQUE PLANIFIÉ (TTL 90 JOURS)
// ════════════════════════════════════════════════════════════════════════════
exports.cleanupOldLogs = onSchedule('every 24 hours', async (event) => {
    console.log("🚀 [SCHEDULED] Démarrage du nettoyage automatique des logs (TTL 90 jours)");
    const cutoff = admin.firestore.Timestamp.fromDate(new Date(Date.now() - 90 * 24 * 60 * 60 * 1000));

    // Nettoyage limité strictement aux logs éphémères opérationnels (préservation comptable et légale de lame_history et cashback_history)
    const collectionsConfig = [
        { name: 'trip_logs', dateField: 'started_at' },
        { name: 'contest_entries', dateField: 'created_at' },
        { name: 'ocr_validations', dateField: 'created_at' }
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

// ════════════════════════════════════════════════════════════════════════════
// 🛒 FONCTION 1 : CRÉER UN ARTICLE DE BOUTIQUE (Shop Item) - ADMIN ONLY
// ════════════════════════════════════════════════════════════════════════════
exports.createShopItem = onCall(async (request) => {
    const data = request.data;
    const context = request;

    verifyAdmin(context);

    const { name, cost_lame, type, icon } = data;

    // Validation des données
    if (!name || typeof cost_lame !== 'number' || cost_lame <= 0 || !type || !icon) {
        throw new HttpsError('invalid-argument', 'Données invalides. Champs requis : name, cost_lame (nombre > 0), type, icon.');
    }

    try {
        const newItemRef = admin.firestore().collection('shop_items').doc();
        const newItemData = {
            name: name,
            cost_lame: cost_lame,
            type: type, // ex: 'Boost', 'Badge', 'Cashback'
            icon: icon, // ex: 'card_giftcard', 'account_balance_wallet'
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        };

        await newItemRef.set(newItemData);

        console.log(`✅ Article de boutique créé avec succès : ${newItemRef.id}`);
        return {
            success: true,
            itemId: newItemRef.id,
            message: 'Article ajouté à la boutique avec succès.'
        };
    } catch (error) {
        console.error("❌ Erreur lors de la création de l'article :", error);
        throw new HttpsError('internal', 'Erreur interne lors de la création de l\'article.');
    }
});

// ════════════════════════════════════════════════════════════════════════════
// 🎁 FONCTION 2 : CRÉER UNE OFFRE DE RÉCOMPENSE (Reward Offer) - ADMIN ONLY
// ════════════════════════════════════════════════════════════════════════════
exports.createRewardOffer = onCall(async (request) => {
    const data = request.data;
    const context = request;

    verifyAdmin(context);

    const {
        title,
        description,
        offer_type,
        eco_cost,
        brand_name,
        is_active = true,
        details_json = {},
        sort_order = 0
    } = data;

    // Validation des données
    if (!title || !offer_type || typeof eco_cost !== 'number' || eco_cost < 0) {
        throw new HttpsError('invalid-argument', 'Données invalides. Champs requis : title, offer_type, eco_cost (nombre >= 0).');
    }

    try {
        const newOfferRef = admin.firestore().collection('rewards').doc();
        const newOfferData = {
            title: title,
            description: description || '',
            offer_type: offer_type, // ex: 'freeOffer', 'promoCode', 'transfer', 'contest', 'campaignDonation'
            eco_cost: eco_cost,
            brand_name: brand_name || 'EcoNav',
            is_active: is_active,
            details_json: details_json, // Pour stocker des infos supplémentaires (ex: code promo, lien, etc.)
            sort_order: sort_order,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        };

        await newOfferRef.set(newOfferData);

        console.log(`✅ Offre de récompense créée avec succès : ${newOfferRef.id}`);
        return {
            success: true,
            offerId: newOfferRef.id,
            message: 'Offre ajoutée au catalogue de récompenses avec succès.'
        };
    } catch (error) {
        console.error("❌ Erreur lors de la création de l'offre :", error);
        throw new HttpsError('internal', 'Erreur interne lors de la création de l\'offre.');
    }
});

// ════════════════════════════════════════════════════════════════════════════
// 🌱 FONCTION AUTOMATIQUE D'INITIALISATION DE CATALOGUE (SEED)
// ════════════════════════════════════════════════════════════════════════════
exports.seedInitialOffers = onCall(async (request) => {
    const context = request;
    verifyAdmin(context);

    const shopItems = [
        {
            id: "boost_mult_1_5",
            name: "Multiplicateur de Lames x1.5 (24h)",
            cost_lame: 300,
            type: "Boost",
            icon: "bolt",
            description: "Multiplie vos gains de Lames par 1.5 sur tous vos trajets pendant 24h."
        },
        {
            id: "boost_mult_2_0",
            name: "Multiplicateur de Lames x2.0 (24h)",
            cost_lame: 600,
            type: "Boost",
            icon: "flash_on",
            description: "Double tous vos gains de Lames pendant 24h."
        },
        {
            id: "badge_eco_warrior",
            name: "Badge Exclusif Éco-Guerrier",
            cost_lame: 1000,
            type: "Badge",
            icon: "military_tech",
            description: "Débloque le badge spécial Éco-Guerrier sur votre profil."
        },
        {
            id: "vip_pass_7d",
            name: "Pass Premium VIP (7 Jours)",
            cost_lame: 2500,
            type: "VIP",
            icon: "workspace_premium",
            description: "Profitez de tous les avantages VIP pendant 7 jours."
        },
        {
            id: "title_eco_ambassador",
            name: "Titre de Profil Éco-Ambassadeur",
            cost_lame: 500,
            type: "Badge",
            icon: "stars",
            description: "Affichez fièrement le titre honorifique Éco-Ambassadeur sur votre profil public."
        }
    ];

    const rewardOffers = [
        {
            id: "offer_promo_biocoop_5eur",
            title: "Bon de réduction 5€ Biocoop",
            description: "Valable dès 25€ d'achat dans tous les magasins Biocoop.",
            brand_name: "Biocoop",
            offer_type: "promoCode",
            eco_cost: 1500,
            is_active: true,
            sort_order: 1,
            details_json: { code: "BIOCOOP-ECO5" }
        },
        {
            id: "offer_decathlon_10eur",
            title: "Carte Cadeau 10€ Decathlon",
            description: "E-carte cadeau valable sur tout le site decathlon.fr ou en magasin.",
            brand_name: "Decathlon",
            offer_type: "freeOffer",
            eco_cost: 3000,
            is_active: true,
            sort_order: 2,
            details_json: { code: "DECATH-10EUR-7892" }
        },
        {
            id: "offer_reforestaction_2trees",
            title: "Don 5€ - Plantation de 2 arbres",
            description: "Financez la plantation de 2 arbres en forêt française avec Reforest'Action.",
            brand_name: "Reforest'Action",
            offer_type: "campaignDonation",
            eco_cost: 1000,
            is_active: true,
            sort_order: 3,
            details_json: { partner: "Reforest'Action" }
        },
        {
            id: "offer_promo_nature_decouvertes",
            title: "15% de réduction Nature & Découvertes",
            description: "Remise immédiate en caisse sur vos achats hors promotions.",
            brand_name: "Nature & Découvertes",
            offer_type: "promoCode",
            eco_cost: 2000,
            is_active: true,
            sort_order: 4,
            details_json: { code: "NATURE-ECO15" }
        },
        {
            id: "raffle_vtt_electrique",
            title: "Tirage au sort : VTT Électrique",
            description: "Achetez des tickets de tombola et tentez de remporter ce VTT Électrique !",
            brand_name: "Grand Tirage EcoNav",
            offer_type: "raffle",
            eco_cost: 500,
            is_active: true,
            status: "open",
            sort_order: 5,
            details_json: {
                type: "raffle",
                product_name: "VTT Électrique Performance",
                product_image_url: "https://i.imgur.com/gO0A3vT.png",
                ticket_cost_eco: 500,
                total_tickets_sold: 120,
                end_date: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
            }
        },
        {
            id: "raffle_ps5_slim",
            title: "Tirage au sort : Console PS5 Slim",
            description: "Tirage au sort exclusif pour gagner une console PS5 Slim 1To !",
            brand_name: "Grand Tirage EcoNav",
            offer_type: "raffle",
            eco_cost: 200,
            is_active: true,
            status: "open",
            sort_order: 6,
            details_json: {
                type: "raffle",
                product_name: "Console PS5 Slim 1To",
                product_image_url: "https://i.imgur.com/gO0A3vT.png",
                ticket_cost_eco: 200,
                total_tickets_sold: 450,
                end_date: new Date(Date.now() + 15 * 24 * 60 * 60 * 1000).toISOString()
            }
        },
        {
            id: "CONTEST_AUCTION_AW9",
            title: "Enchère : Apple Watch Series 9",
            description: "Misez vos Lames et remportez la montre connectée Apple Watch Series 9 !",
            brand_name: "Enchères Exclusives",
            offer_type: "auction",
            eco_cost: 100,
            is_active: true,
            status: "open",
            sort_order: 7,
            details_json: {
                type: "auction",
                product_name: "Apple Watch Series 9",
                product_image_url: "https://i.imgur.com/gO0A3vT.png",
                min_bid: 100,
                current_highest_bid: 1250,
                end_date: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
                contest_id_ref: "CONTEST_AUCTION_AW9"
            }
        }
    ];

    try {
        const batch = admin.firestore().batch();

        // Insertion idempotente avec IDs déterministes
        for (const item of shopItems) {
            const ref = admin.firestore().collection('shop_items').doc(item.id);
            batch.set(ref, {
                ...item,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
        }

        for (const offer of rewardOffers) {
            const ref = admin.firestore().collection('rewards').doc(offer.id);
            batch.set(ref, {
                ...offer,
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
        }

        // Enregistrer l'enchère dans `contests` et `contest_state`
        const auctionRef = admin.firestore().collection('contests').doc("CONTEST_AUCTION_AW9");
        batch.set(auctionRef, {
            product_name: "Apple Watch Series 9",
            product_image_url: "https://i.imgur.com/gO0A3vT.png",
            description: "Misez vos Lames et remportez la montre connectée Apple Watch Series 9 !",
            min_bid: 100,
            current_highest_bid: 1250,
            is_active: true,
            status: "open",
            end_date: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
            created_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        const auctionStateRef = admin.firestore().collection('contest_state').doc("CONTEST_AUCTION_AW9");
        batch.set(auctionStateRef, {
            current_highest_bid: 1250,
            highest_bid: 1250,
            highest_bidder_user_id: null,
            total_bids: 5,
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        await batch.commit();
        console.log("✅ Catalogue initial généré avec succès !");
        return { success: true, message: "Catalogue initial d'offres, d'articles et d'enchères généré avec succès !" };
    } catch (error) {
        console.error("❌ Erreur lors de la génération du catalogue :", error);
        throw new HttpsError('internal', 'Erreur lors de la création du catalogue initial.');
    }
});

// ════════════════════════════════════════════════════════════════════════════
// 📧 ENVOI AUTOMATIQUE D'EMAIL (Remplacement direct de l'extension Firestore)
// ════════════════════════════════════════════════════════════════════════════
exports.onMailDocumentCreated = onDocumentCreated("mail/{mailId}", async (event) => {
    const snap = event.data;
    if (!snap) return;

    const emailData = snap.data();

    // Vérifie si l'email a déjà été envoyé pour éviter les doublons
    if (emailData.delivery && emailData.delivery.state === "SUCCESS") {
        return;
    }

    const emailUser = process.env.EMAIL_USER || process.env.SMTP_USER || "contact@walkmoney.com";
    const emailPass = process.env.EMAIL_PASS || process.env.SMTP_PASS || "";

    // 💡 Déplacé ici pour ne PAS ralentir l'initialisation de Firebase
    const transporter = nodemailer.createTransport({
        service: process.env.SMTP_SERVICE || "gmail",
        host: process.env.SMTP_HOST || undefined,
        port: process.env.SMTP_PORT ? parseInt(process.env.SMTP_PORT, 10) : undefined,
        secure: process.env.SMTP_SECURE === "true",
        auth: {
            user: emailUser,
            pass: emailPass,
        },
    });

    const mailOptions = {
        from: emailData.from || `"WalkMoney" <${emailUser}>`,
        to: emailData.to,
        subject: emailData.message?.subject || emailData.subject || "Nouvelle notification WalkMoney",
        text: emailData.message?.text || emailData.text || "",
        html: emailData.message?.html || emailData.html || "",
    };

    try {
        const info = await transporter.sendMail(mailOptions);
        console.log(`✅ Email envoyé avec succès (ID: ${event.params.mailId}) : ${info.messageId}`);

        // Met à jour le statut dans Firestore exactement comme le faisait l'extension
        await snap.ref.update({
            delivery: {
                state: "SUCCESS",
                startTime: admin.firestore.FieldValue.serverTimestamp(),
                endTime: admin.firestore.FieldValue.serverTimestamp(),
                info: { messageId: info.messageId }
            }
        });
    } catch (error) {
        console.error(`❌ Échec de l'envoi de l'email (ID: ${event.params.mailId}) :`, error);

        await snap.ref.update({
            delivery: {
                state: "ERROR",
                error: error.message,
                endTime: admin.firestore.FieldValue.serverTimestamp()
            }
        });
    }
});

// ============================================================================
// 💳 WEBHOOK REVENUECAT (Google Play In-App Billing)
// ============================================================================
exports.revenueCatWebhook = onRequest(async (req, res) => {
    // Clé d'autorisation configurée dans le tableau de bord RevenueCat
    const authHeader = req.headers.authorization;
    if (!process.env.REVENUECAT_WEBHOOK_AUTH || authHeader !== process.env.REVENUECAT_WEBHOOK_AUTH) {
        console.error("❌ Accès webhook RevenueCat non autorisé.");
        return res.status(401).send("Non autorisé");
    }

    const event = req.body?.event;
    if (!event) {
        return res.status(400).send("Données manquantes");
    }

    const userId = event.app_user_id; // L'UID Firebase transmis lors de Purchases.logIn()
    const type = event.type;

    console.log(`📢 Webhook RevenueCat pour l'utilisateur ${userId} : ${type}`);

    if (!userId) {
        return res.status(400).send("app_user_id manquant");
    }

    const userRef = admin.firestore().collection("users").doc(userId);

    try {
        switch (type) {
            case "INITIAL_PURCHASE":
            case "RENEWAL":
            case "UNCANCELLATION":
                // Activer le statut VIP
                await userRef.set({
                    is_vip: true,
                    revenuecat_active: true,
                    updated_at: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });
                console.log(`✅ VIP activé pour ${userId}`);
                break;

            case "CANCELLATION":
            case "EXPIRATION":
            case "BILLING_ISSUE": {
                // Vérifier si l'utilisateur est VIP par niveau 30+ ou abonnement Stripe actif
                const userDoc = await userRef.get();
                const userData = userDoc.exists ? userDoc.data() : {};
                const isLevelVip = (userData.current_level || 0) >= 30;
                const hasStripeVip = userData.stripe_subscription_status === 'active';
                const keepVip = isLevelVip || hasStripeVip;

                await userRef.set({
                    is_vip: keepVip,
                    revenuecat_active: false,
                    updated_at: admin.firestore.FieldValue.serverTimestamp()
                }, { merge: true });
                console.log(`🛑 Traitement fin droits RevenueCat pour ${userId} (VIP conservé: ${keepVip})`);
                break;
            }

            default:
                break;
        }

        res.status(200).send({ received: true });
    } catch (error) {
        console.error("❌ Erreur traitement Webhook RevenueCat :", error);
        res.status(500).send("Erreur serveur");
    }
});

/**
 * Envoie une demande d'ami sécurisée côté serveur
 */
exports.sendFriendRequest = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Utilisateur non authentifié.');
    }
    const currentUserId = request.auth.uid;
    const { friendId } = request.data || {};

    if (!friendId || typeof friendId !== 'string') {
        throw new HttpsError('invalid-argument', 'Identifiant ami manquant ou invalide.');
    }

    if (friendId === currentUserId) {
        throw new HttpsError('invalid-argument', 'Vous ne pouvez pas vous ajouter vous-même en ami.');
    }

    const db = admin.firestore();
    const friendRef = db.collection('users').doc(friendId);
    const currentUserRef = db.collection('users').doc(currentUserId);

    await db.runTransaction(async (t) => {
        const friendDoc = await t.get(friendRef);
        if (!friendDoc.exists) {
            throw new HttpsError('not-found', 'Utilisateur cible introuvable.');
        }

        const friendData = friendDoc.data() || {};
        const received = friendData.friend_requests_received || [];
        const existingFriends = friendData.friend_ids || [];

        if (existingFriends.includes(currentUserId)) {
            throw new HttpsError('already-exists', 'Vous êtes déjà amis.');
        }

        if (!received.includes(currentUserId)) {
            t.update(friendRef, {
                friend_requests_received: admin.firestore.FieldValue.arrayUnion(currentUserId),
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });
        }

        t.update(currentUserRef, {
            friend_requests_sent: admin.firestore.FieldValue.arrayUnion(friendId),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
    });

    try {
        const senderDoc = await currentUserRef.get();
        const senderName = senderDoc.exists ? (senderDoc.data()?.username || 'Un utilisateur') : 'Un utilisateur';
        await sendNotification(
            friendId,
            "Nouvelle demande d'ami 👥",
            `${senderName} souhaite devenir votre ami sur EcoNav.`,
            { type: 'friend_request', sender_id: currentUserId }
        );
    } catch (_) { }

    return { success: true };
});

// ============================================================================
// 👑 RÉSILIATION DU STATUT VIP PAR L'UTILISATEUR (Sécurisé côté serveur)
// ============================================================================
exports.cancelVipSubscription = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Authentification requise.');
    }
    const uid = request.auth.uid;
    const userRef = admin.firestore().collection('users').doc(uid);
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
        throw new HttpsError('not-found', 'Utilisateur introuvable.');
    }

    const userData = userDoc.data();
    const isLevelVip = (userData.current_level || 0) >= 30;
    if (isLevelVip) {
        return { success: true, message: "Abonnement révoqué, statut VIP conservé grâce à votre niveau 30+ !" };
    }

    await userRef.update({
        is_vip: false,
        revenuecat_active: false,
        updated_at: admin.firestore.FieldValue.serverTimestamp()
    });

    console.log(`👑 Statut VIP révoqué avec succès par le serveur pour ${uid}`);
    return { success: true };
});

// ============================================================================
// 🗺️ PROXY SÉCURISÉ GOOGLE DIRECTIONS (Protection de la clé API)
// ============================================================================
exports.getDirectionsProxy = onCall(async (request) => {
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Authentification requise pour calculer un itinéraire.');
    }
    const { origin, destination, mode, arrivalTime, departureTime } = request.data || {};
    if (!origin || !destination) {
        throw new HttpsError('invalid-argument', 'Origine et destination requises.');
    }

    const apiKey = process.env.GOOGLE_MAPS_SERVER_API_KEY || process.env.GOOGLE_MAPS_API_KEY;
    if (!apiKey) {
        throw new HttpsError('failed-precondition', 'Clé API Google Directions non configurée sur le serveur.');
    }

    try {
        const params = new URLSearchParams({
            origin: String(origin),
            destination: String(destination),
            mode: mode || 'walking',
            language: 'fr',
            key: apiKey,
        });

        if (arrivalTime) params.append('arrival_time', String(arrivalTime));
        if (departureTime) params.append('departure_time', String(departureTime));

        const response = await fetch(`https://maps.googleapis.com/maps/api/directions/json?${params.toString()}`);
        if (!response.ok) {
            throw new HttpsError('internal', `Erreur HTTP Google API: ${response.status}`);
        }
        const data = await response.json();
        return data;
    } catch (err) {
        console.error('Erreur proxy Directions:', err);
        throw new HttpsError('internal', 'Impossible de récupérer les directions via le serveur.');
    }
});

// ============================================================================
// 🏆 CLÔTURE AUTOMATIQUE DES ENCHÈRES ET TIRAGE DES LOTERIES (Item 48, 49)
// ============================================================================
exports.closeExpiredAuctionsAndRaffles = onSchedule('every 15 minutes', async (event) => {
    console.log("🚀 [SCHEDULED] Vérification des enchères et loteries expirées...");

    try {
        // 1. Clôture des enchères (rewards et contests de type 'auction')
        const openAuctions = await admin.firestore().collection('rewards')
            .where('status', '==', 'open')
            .get();

        for (const doc of openAuctions.docs) {
            const data = doc.data();
            const isAuction = data.offer_type === 'auction' || data.type === 'auction' || data.details_json?.type === 'auction';
            if (!isAuction) continue;

            const rawEndDate = data.end_date || data.details_json?.end_date;
            let isExpired = false;
            if (rawEndDate) {
                const endMillis = typeof rawEndDate.toMillis === 'function' ? rawEndDate.toMillis() : new Date(rawEndDate).getTime();
                if (!isNaN(endMillis) && endMillis <= Date.now()) {
                    isExpired = true;
                }
            }

            if (isExpired) {
                const contestStateRef = admin.firestore().collection('contest_state').doc(doc.id);
                const stateDoc = await contestStateRef.get();
                const stateData = stateDoc.exists ? stateDoc.data() : {};
                const winnerId = stateData.highest_bidder_user_id || data.highest_bidder_user_id;
                const winningBid = stateData.highest_bid || data.current_highest_bid || 0;

                await doc.ref.update({
                    status: 'completed',
                    winner_user_id: winnerId || null,
                    winning_bid: winningBid,
                    closed_at: admin.firestore.FieldValue.serverTimestamp()
                });

                if (winnerId) {
                    await admin.firestore().collection('user_claimed_offers').add({
                        user_id: winnerId,
                        reward_id: doc.id,
                        details: { offer_title: data.title || data.product_name || 'Enchère EcoNav', winning_bid: winningBid },
                        claimed_at: admin.firestore.FieldValue.serverTimestamp(),
                        status: 'approved'
                    });

                    // Email de confirmation au gagnant
                    const winnerDoc = await admin.firestore().collection('users').doc(winnerId).get();
                    const winnerEmail = winnerDoc.exists ? winnerDoc.data()?.email : null;
                    if (winnerEmail) {
                        const safeTitle = esc(data.title || data.product_name || 'Enchère');
                        await admin.firestore().collection('mail').add({
                            to: winnerEmail,
                            message: {
                                subject: '🏆 Félicitations, vous avez remporté l\'enchère EcoNav !',
                                html: `<p>Félicitations ! Vous avez remporté l'enchère pour <strong>${safeTitle}</strong> avec une mise de <strong>${winningBid} Lames</strong>.</p>`
                            },
                            created_at: admin.firestore.FieldValue.serverTimestamp()
                        });
                    }

                    await sendNotification(
                        winnerId,
                        "🏆 Enchère remportée !",
                        `Félicitations ! Vous avez remporté l'enchère pour : ${data.title || data.product_name || 'Enchère'} avec ${winningBid} Lames.`,
                        { type: 'auction_won', reward_id: doc.id }
                    );
                }
                console.log(`✅ Enchère ${doc.id} clôturée avec succès. Gagnant : ${winnerId}`);
            }
        }

        // 2. Tirage au sort des loteries (raffles)
        const openRaffles = await admin.firestore().collection('rewards')
            .where('status', '==', 'open')
            .get();

        for (const doc of openRaffles.docs) {
            const data = doc.data();
            const isRaffle = data.offer_type === 'raffle' || data.type === 'raffle' || data.details_json?.type === 'raffle';
            if (!isRaffle) continue;

            const rawEndDate = data.end_date || data.details_json?.end_date;
            let isExpired = false;
            if (rawEndDate) {
                const endMillis = typeof rawEndDate.toMillis === 'function' ? rawEndDate.toMillis() : new Date(rawEndDate).getTime();
                if (!isNaN(endMillis) && endMillis <= Date.now()) {
                    isExpired = true;
                }
            }

            if (isExpired) {
                const entriesSnap = await admin.firestore().collection('contest_entries')
                    .where('contest_id', '==', doc.id)
                    .get();

                let winnerId = null;
                if (!entriesSnap.empty) {
                    const crypto = require('crypto');
                    const randomIndex = crypto.randomInt(0, entriesSnap.docs.length);
                    winnerId = entriesSnap.docs[randomIndex].data().user_id;
                }

                await doc.ref.update({
                    status: 'completed',
                    winner_user_id: winnerId || null,
                    closed_at: admin.firestore.FieldValue.serverTimestamp()
                });

                if (winnerId) {
                    await admin.firestore().collection('user_claimed_offers').add({
                        user_id: winnerId,
                        reward_id: doc.id,
                        details: { offer_title: data.title || 'Loterie EcoNav' },
                        claimed_at: admin.firestore.FieldValue.serverTimestamp(),
                        status: 'approved'
                    });

                    const winnerDoc = await admin.firestore().collection('users').doc(winnerId).get();
                    const winnerEmail = winnerDoc.exists ? winnerDoc.data()?.email : null;
                    if (winnerEmail) {
                        const safeTitle = esc(data.title || 'Loterie EcoNav');
                        await admin.firestore().collection('mail').add({
                            to: winnerEmail,
                            message: {
                                subject: '🎉 Félicitations, vous avez gagné le tirage au sort EcoNav !',
                                html: `<p>Félicitations ! Vous avez été tiré(e) au sort pour le lot : <strong>${safeTitle}</strong>.</p>`
                            },
                            created_at: admin.firestore.FieldValue.serverTimestamp()
                        });
                    }

                    await sendNotification(
                        winnerId,
                        "🎉 Tirage au sort gagnant !",
                        `Félicitations ! Vous avez été tiré(e) au sort pour le lot : ${data.title || 'Loterie EcoNav'} !`,
                        { type: 'raffle_won', reward_id: doc.id }
                    );
                }
                console.log(`✅ Loterie ${doc.id} tirée au sort. Gagnant : ${winnerId}`);
            }
        }
    } catch (e) {
        console.error("❌ Erreur closeExpiredAuctionsAndRaffles :", e);
    }
    return null;
});

// ============================================================================
// 👥 GESTION SÉCURISÉE DES AMIS (Item 61)
// ============================================================================
exports.acceptFriendRequest = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Non authentifié.');
    const currentUserId = request.auth.uid;
    const { friendId } = request.data || {};
    if (!friendId) throw new HttpsError('invalid-argument', 'Identifiant ami manquant.');

    const db = admin.firestore();
    const currentUserRef = db.collection('users').doc(currentUserId);
    const friendRef = db.collection('users').doc(friendId);

    await db.runTransaction(async (t) => {
        const userDoc = await t.get(currentUserRef);
        const friendDoc = await t.get(friendRef);
        if (!userDoc.exists || !friendDoc.exists) throw new HttpsError('not-found', 'Profil introuvable.');

        t.update(currentUserRef, {
            friend_requests_received: admin.firestore.FieldValue.arrayRemove(friendId),
            friend_ids: admin.firestore.FieldValue.arrayUnion(friendId),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
        t.update(friendRef, {
            friend_requests_sent: admin.firestore.FieldValue.arrayRemove(currentUserId),
            friend_ids: admin.firestore.FieldValue.arrayUnion(currentUserId),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
    });

    try {
        const receiverDoc = await currentUserRef.get();
        const receiverName = receiverDoc.exists ? (receiverDoc.data()?.username || 'Votre ami') : 'Votre ami';
        await sendNotification(
            friendId,
            "Demande d'ami acceptée 🎉",
            `${receiverName} a accepté votre demande d'ami sur EcoNav !`,
            { type: 'friend_accepted', friend_id: currentUserId }
        );
    } catch (_) { }

    return { success: true };
});

exports.rejectFriendRequest = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Non authentifié.');
    const currentUserId = request.auth.uid;
    const { friendId } = request.data || {};
    if (!friendId) throw new HttpsError('invalid-argument', 'Identifiant ami manquant.');

    const db = admin.firestore();
    const currentUserRef = db.collection('users').doc(currentUserId);
    const friendRef = db.collection('users').doc(friendId);

    await db.runTransaction(async (t) => {
        t.update(currentUserRef, {
            friend_requests_received: admin.firestore.FieldValue.arrayRemove(friendId),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
        t.update(friendRef, {
            friend_requests_sent: admin.firestore.FieldValue.arrayRemove(currentUserId),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
    });
    return { success: true };
});

exports.removeFriend = onCall(async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Non authentifié.');
    const currentUserId = request.auth.uid;
    const { friendId } = request.data || {};
    if (!friendId) throw new HttpsError('invalid-argument', 'Identifiant ami manquant.');

    const db = admin.firestore();
    const currentUserRef = db.collection('users').doc(currentUserId);
    const friendRef = db.collection('users').doc(friendId);

    await db.runTransaction(async (t) => {
        t.update(currentUserRef, {
            friend_ids: admin.firestore.FieldValue.arrayRemove(friendId),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
        t.update(friendRef, {
            friend_ids: admin.firestore.FieldValue.arrayRemove(currentUserId),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });
    });
    return { success: true };
});

/**
 * Attribution sécurisée du Super Défi (5000 Lames)
 * Vérifie côté serveur que tous les défis du cycle de 14 jours sont validés et non rejoués.
 */
exports.claimSuperChallengeBonus = onCall({ enforceAppCheck: false }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Authentification requise.');
    verifyEmailVerified(request);
    const userId = request.auth.uid;
    const SUPER_BONUS = 5000;
    const db = admin.firestore();
    const userRef = db.collection('users').doc(userId);
    const statsRef = db.collection('user_stats').doc(userId);

    return await db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const statsDoc = await transaction.get(statsRef);

        if (!userDoc.exists) {
            throw new HttpsError('not-found', 'Profil utilisateur introuvable.');
        }

        const statsData = statsDoc.exists ? statsDoc.data() : {};
        if (statsData.super_challenge_bonus_claimed === true) {
            throw new HttpsError('failed-precondition', 'Le Super Défi a déjà été réclamé pour ce cycle de 14 jours.');
        }

        // Vérification des user_challenges
        const challengesSnap = await db.collection('user_challenges')
            .where('user_id', '==', userId)
            .get();

        if (challengesSnap.empty) {
            throw new HttpsError('failed-precondition', 'Aucun défi trouvé dans votre progression.');
        }

        let totalChallenges = 0;
        let completedChallenges = 0;
        challengesSnap.forEach(doc => {
            const data = doc.data();
            // Ignorer l'éventuel objet bonus dans la collection
            if (data.title && data.title.includes('BONUS')) return;
            totalChallenges++;
            if (data.status === 'rewardClaimed' || data.status === 'completed' || (data.current_step >= (data.total_steps || 1))) {
                completedChallenges++;
            }
        });

        if (totalChallenges < 3 || completedChallenges < totalChallenges) {
            throw new HttpsError('permission-denied', `Tous les défis du cycle ne sont pas encore complétés (${completedChallenges}/${totalChallenges}).`);
        }

        // Crédit atomique des 5000 Lames
        transaction.update(userRef, {
            lame_points: admin.firestore.FieldValue.increment(SUPER_BONUS),
            total_lame_earned: admin.firestore.FieldValue.increment(SUPER_BONUS),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        });

        transaction.set(statsRef, {
            super_challenge_bonus_claimed: true,
            super_challenge_claimed_at: admin.firestore.FieldValue.serverTimestamp(),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        // Mise à jour profil public
        const pubRef = db.collection('public_profiles').doc(userId);
        transaction.set(pubRef, {
            total_lame_earned: admin.firestore.FieldValue.increment(SUPER_BONUS),
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        // Historique
        const historyRef = db.collection('users').doc(userId).collection('lame_history').doc();
        transaction.set(historyRef, {
            points: SUPER_BONUS,
            source: 'Super Défi - Bonus Final',
            created_at: admin.firestore.FieldValue.serverTimestamp()
        });

        return { success: true, bonus_amount: SUPER_BONUS };
    });
});

/**
 * Actualisation du cycle de défis de 14 jours contrôlée côté serveur
 */
exports.refreshChallengesCycle = onCall({ enforceAppCheck: false }, async (request) => {
    if (!request.auth) throw new HttpsError('unauthenticated', 'Authentification requise.');
    const userId = request.auth.uid;
    const db = admin.firestore();
    const statsRef = db.collection('user_stats').doc(userId);
    const statsDoc = await statsRef.get();
    const statsData = statsDoc.exists ? statsDoc.data() : {};

    const lastRefresh = statsData.last_challenges_refresh ? statsData.last_challenges_refresh.toDate() : null;
    const now = new Date();
    const CYCLE_DURATION_MS = 14 * 24 * 60 * 60 * 1000;

    if (lastRefresh && (now.getTime() - lastRefresh.getTime() < CYCLE_DURATION_MS - 60000)) {
        const remainingHours = Math.ceil((CYCLE_DURATION_MS - (now.getTime() - lastRefresh.getTime())) / (3600 * 1000));
        throw new HttpsError('failed-precondition', `Le cycle de 14 jours est toujours actif (reste environ ${remainingHours}h).`);
    }

    await statsRef.set({
        last_challenges_refresh: admin.firestore.FieldValue.serverTimestamp(),
        super_challenge_bonus_claimed: false,
        updated_at: admin.firestore.FieldValue.serverTimestamp()
    }, { merge: true });

    return { refreshed: true, timestamp: now.toISOString() };
});

// ════════════════════════════════════════════════════════════════════════════
// 🔒 VÉRIFICATION & RÉSERVATION PSEUDO À L'INSCRIPTION (Serveur Atomique)
// ════════════════════════════════════════════════════════════════════════════
exports.claimInitialUsername = onCall(async (request) => {
    try {
        verifyAppCheck(request);
    } catch (_) {
        console.warn("⚠️ App Check non validé pour claimInitialUsername (mode permissif)");
    }
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Utilisateur non authentifié.');
    }

    const userId = request.auth.uid;
    const rawUsername = (request.data?.username || '').trim();

    // Validation du format du pseudo
    if (rawUsername.length < 3 || rawUsername.length > 20) {
        throw new HttpsError('invalid-argument', 'Le pseudo doit comporter entre 3 et 20 caractères.');
    }
    const usernameRegex = /^[a-zA-Z0-9_]+$/;
    if (!usernameRegex.test(rawUsername)) {
        throw new HttpsError('invalid-argument', 'Le pseudo ne peut contenir que des lettres, chiffres et tirets bas (_).');
    }

    const cleanUsername = rawUsername.toLowerCase();
    const db = admin.firestore();

    return await db.runTransaction(async (transaction) => {
        const usernameRef = db.collection('usernames').doc(cleanUsername);
        const usernameDoc = await transaction.get(usernameRef);

        // VÉRIFICATION SERVEUR ATOMIQUE
        if (usernameDoc.exists && usernameDoc.data().uid !== userId) {
            throw new HttpsError('already-exists', 'Ce pseudo est déjà pris. Veuillez en choisir un autre.');
        }

        // Réservation du pseudo
        transaction.set(usernameRef, {
            uid: userId,
            username: rawUsername,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        // Mise à jour du profil utilisateur
        const userRef = db.collection('users').doc(userId);
        transaction.set(userRef, {
            username: rawUsername,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        const publicProfileRef = db.collection('public_profiles').doc(userId);
        transaction.set(publicProfileRef, {
            username: rawUsername,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        return { success: true, username: rawUsername };
    });
});

// ════════════════════════════════════════════════════════════════════════════
// 🔒 MODIFICATION DU PSEUDO (Serveur Atomique avec Libération de l'Ancien)
// ════════════════════════════════════════════════════════════════════════════
exports.updateUsername = onCall(async (request) => {
    verifyAppCheck(request);
    if (!request.auth) {
        throw new HttpsError('unauthenticated', 'Utilisateur non authentifié.');
    }

    const userId = request.auth.uid;
    const newUsername = (request.data?.newUsername || '').trim();

    if (newUsername.length < 3 || newUsername.length > 20) {
        throw new HttpsError('invalid-argument', 'Le pseudo doit comporter entre 3 et 20 caractères.');
    }
    const usernameRegex = /^[a-zA-Z0-9_]+$/;
    if (!usernameRegex.test(newUsername)) {
        throw new HttpsError('invalid-argument', 'Le pseudo ne peut contenir que des lettres, chiffres et tirets bas (_).');
    }

    const cleanNew = newUsername.toLowerCase();
    const db = admin.firestore();

    return await db.runTransaction(async (transaction) => {
        const userRef = db.collection('users').doc(userId);
        const userDoc = await transaction.get(userRef);

        if (!userDoc.exists) {
            throw new HttpsError('not-found', 'Profil utilisateur introuvable.');
        }

        const oldUsername = (userDoc.data().username || '').trim();
        const cleanOld = oldUsername.toLowerCase();

        if (cleanNew === cleanOld) {
            return { success: true, message: 'Le pseudo est identique.' };
        }

        // Vérification de la disponibilité du nouveau pseudo
        const newUsernameRef = db.collection('usernames').doc(cleanNew);
        const newUsernameDoc = await transaction.get(newUsernameRef);

        if (newUsernameDoc.exists && newUsernameDoc.data().uid !== userId) {
            throw new HttpsError('already-exists', 'Ce pseudo est déjà pris. Veuillez en choisir un autre.');
        }

        // 1. Libérer l'ancien pseudo s'il existait
        if (cleanOld) {
            const oldUsernameRef = db.collection('usernames').doc(cleanOld);
            transaction.delete(oldUsernameRef);
        }

        // 2. Bloquer le nouveau pseudo
        transaction.set(newUsernameRef, {
            uid: userId,
            username: newUsername,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        // 3. Mettre à jour `users` et `public_profiles`
        transaction.update(userRef, {
            username: newUsername,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
        });

        const publicProfileRef = db.collection('public_profiles').doc(userId);
        transaction.set(publicProfileRef, {
            username: newUsername,
            updated_at: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });

        return { success: true, newUsername: newUsername };
    });
});