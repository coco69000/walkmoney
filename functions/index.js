const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

// VOTRE CLÉ SECRÈTE STRIPE
const stripe = require('stripe')('sk_test_51Sf3KIJmX9VkIHA6L11Lo7xx2g1FB8pUqBni2eBmhzLJctwvhlkKMbTWaGvYspNkD6vnE3tS3C4MjoAGl1F68kiY00yUNPNOQe');

// --- CONFIGURATION DES PRIX ---
// ID du prix "Compteur" (Commission variable) - Celui que vous aviez déjà
const METER_PRICE_ID = 'price_1Sf3OjJmX9VkIHA6i6tCmgeT';

// ID du prix "Visibilité Or" (Abonnement fixe 5€/mois)
// 1. Allez sur Stripe Dashboard > Produits > Ajouter un produit
// 2. Nom: "Option Visibilité Or", Prix: 5.00 EUR, Récurrent (Mensuel)
// 3. Copiez l'ID du prix (commence par price_...) et collez-le ci-dessous :
const GOLD_PRICE_ID = 'price_1SgZkvJmX9VkIHA6tTa42iTY';


// --- FONCTION 1 : CRÉATION DU MAGASIN ---
exports.createStripeShop = functions.https.onCall(async (dataOrRequest, context) => {
    console.log("🚀 [START] createStripeShop appelée !");

    // Extraction universelle des données
    const data = dataOrRequest.data || dataOrRequest;

    const paymentMethodId = data.paymentMethodId;
    const email = data.email;
    const name = data.name;
    // Récupération de l'option envoyée par Flutter
    const isVisibilityBoostEnabled = (data.is_visibility_boost_enabled === true || data.isVisibilityBoostEnabled === true);

    console.log(`📦 Données : Nom=${name}, Email=${email}, OptionOr=${isVisibilityBoostEnabled}`);

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
exports.reportCommission = functions.https.onCall(async (dataOrRequest, context) => {
    console.log("🚀 [START] reportCommission appelée");

    const data = dataOrRequest.data || dataOrRequest;

    const subscriptionItemId = data.subscriptionItemId;
    const amountInCents = data.amountInCents;

    if (!subscriptionItemId || !amountInCents) {
        throw new functions.https.HttpsError('invalid-argument', 'Données manquantes.');
    }

    try {
        // C'est ici que l'erreur se produisait avant.
        // "subscriptionItems" est correctement écrit avec un I majuscule.
        await stripe.subscriptionItems.createUsageRecord(
            subscriptionItemId,
            {
                quantity: parseInt(amountInCents),
                action: 'increment'
            }
        );
        console.log(`✅ Usage ajouté (+${amountInCents}) sur l'item ${subscriptionItemId}`);
        return { success: true };
    } catch (error) {
        console.error("❌ Erreur reportCommission :", error);
        throw new functions.https.HttpsError('internal', error.message);
    }
});