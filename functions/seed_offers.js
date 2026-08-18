/**
 * 🚀 SCRIPT D'INJECTION AUTOMATIQUE DE DONNÉES (Shop Items & Rewards)
 * Projet: walkmoney-1cdad
 * 
 * Exécution:
 *   cd functions
 *   node seed_offers.js
 */

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// Initialisation intelligente : vérifie si serviceAccountKey.json existe dans le dossier
const keyPath = path.join(__dirname, 'serviceAccountKey.json');

if (!admin.apps.length) {
    if (fs.existsSync(keyPath)) {
        console.log("🔑 Clé de compte de service détectée (serviceAccountKey.json)");
        const serviceAccount = require(keyPath);
        admin.initializeApp({
            credential: admin.credential.cert(serviceAccount)
        });
    } else {
        admin.initializeApp({
            projectId: 'walkmoney-1cdad'
        });
    }
}

const db = admin.firestore();

// 🛒 CATALOGUE DES ARTICLES DE BOUTIQUE (shop_items)
const shopItems = [
    {
        name: "Multiplicateur de Lames x1.5 (24h)",
        cost_lame: 300,
        type: "Boost",
        icon: "bolt",
        description: "Multiplie vos gains de Lames par 1.5 sur tous vos trajets pendant 24h."
    },
    {
        name: "Multiplicateur de Lames x2.0 (24h)",
        cost_lame: 600,
        type: "Boost",
        icon: "flash_on",
        description: "Double tous vos gains de Lames pendant 24 heures !"
    },
    {
        name: "Badge Exclusif Éco-Guerrier",
        cost_lame: 1000,
        type: "Badge",
        icon: "military_tech",
        description: "Débloque le badge spécial Éco-Guerrier affiché sur votre profil."
    },
    {
        name: "Pass Premium VIP (7 Jours)",
        cost_lame: 2500,
        type: "VIP",
        icon: "workspace_premium",
        description: "Profitez de tous les avantages VIP pendant 7 jours complets."
    },
    {
        name: "Pack Rechargement 500 Lames",
        cost_lame: 400,
        type: "Reward",
        icon: "stars",
        description: "Bonus de 500 Lames crédité instantanément."
    }
];

// 🎁 CATALOGUE DES OFFRES DE RÉCOMPENSES (rewards)
const rewardOffers = [
    {
        title: "Bon de réduction 5€ Biocoop",
        description: "Valable dès 25€ d'achat dans tous les magasins Biocoop participants.",
        brand_name: "Biocoop",
        offer_type: "promoCode",
        eco_cost: 1500,
        is_active: true,
        sort_order: 1,
        details_json: {
            code: "BIOCOOP-ECO5",
            terms: "Un seul code par passage en caisse. Expire sous 30 jours."
        }
    },
    {
        title: "Carte Cadeau 10€ Decathlon",
        description: "E-carte cadeau valable sur tout le site decathlon.fr ou en magasin.",
        brand_name: "Decathlon",
        offer_type: "freeOffer",
        eco_cost: 3000,
        is_active: true,
        sort_order: 2,
        details_json: {
            code: "DECATH-10EUR-7892",
            link: "https://www.decathlon.fr"
        }
    },
    {
        title: "Don 5€ - Plantation de 2 arbres",
        description: "Financez directement la plantation de 2 arbres en forêt française avec Reforest'Action.",
        brand_name: "Reforest'Action",
        offer_type: "campaignDonation",
        eco_cost: 1000,
        is_active: true,
        sort_order: 3,
        details_json: {
            partner: "Reforest'Action",
            impact: "2 arbres plantés"
        }
    },
    {
        title: "15% de réduction Nature & Découvertes",
        description: "Remise immédiate en caisse sur vos achats hors promotions.",
        brand_name: "Nature & Découvertes",
        offer_type: "promoCode",
        eco_cost: 2000,
        is_active: true,
        sort_order: 4,
        details_json: {
            code: "NATURE-ECO15"
        }
    },
    {
        title: "Tirage au sort : VTT Électrique",
        description: "Achetez des tickets de tombola et tentez de remporter ce VTT Électrique !",
        brand_name: "Grand Tirage EcoNav",
        offer_type: "contest",
        eco_cost: 500,
        is_active: true,
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
        title: "Tirage au sort : Console PS5 Slim",
        description: "Tirage au sort exclusif pour gagner une console PS5 Slim 1To !",
        brand_name: "Grand Tirage EcoNav",
        offer_type: "contest",
        eco_cost: 200,
        is_active: true,
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
        title: "Enchère : Apple Watch Series 9",
        description: "Misez vos Lames et remportez la montre connectée Apple Watch Series 9 !",
        brand_name: "Enchères Exclusives",
        offer_type: "contest",
        eco_cost: 100,
        is_active: true,
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

async function seedDatabase() {
    console.log("🌱 [START] Démarrage de l'injection des offres et articles...");

    try {
        // 1. Injection dans `shop_items`
        console.log("\n🛒 Injection dans la collection 'shop_items'...");
        for (const item of shopItems) {
            const docRef = db.collection('shop_items').doc();
            await docRef.set({
                ...item,
                created_at: admin.firestore.FieldValue.serverTimestamp(),
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });
            console.log(`  ✅ Article ajouté : "${item.name}" (ID: ${docRef.id})`);
        }

        // 2. Injection dans `rewards`
        console.log("\n🎁 Injection dans la collection 'rewards'...");
        for (const offer of rewardOffers) {
            const docRef = db.collection('rewards').doc();
            await docRef.set({
                ...offer,
                created_at: admin.firestore.FieldValue.serverTimestamp(),
                updated_at: admin.firestore.FieldValue.serverTimestamp()
            });
            console.log(`  ✅ Offre ajoutée : "${offer.title}" (ID: ${docRef.id})`);
        }

        // 3. Injection dans `contests` et `contest_state` pour les enchères
        console.log("\n🏆 Injection des détails de l'enchère dans 'contests' & 'contest_state'...");
        const auctionContestId = "CONTEST_AUCTION_AW9";
        
        await db.collection('contests').doc(auctionContestId).set({
            product_name: "Apple Watch Series 9",
            product_image_url: "https://i.imgur.com/gO0A3vT.png",
            description: "Misez vos Lames et remportez la montre connectée Apple Watch Series 9 !",
            min_bid: 100,
            current_highest_bid: 1250,
            is_active: true,
            end_date: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
            created_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        await db.collection('contest_state').doc(auctionContestId).set({
            current_highest_bid: 1250,
            highest_bid: 1250,
            highest_bidder_user_id: null,
            total_bids: 5,
            updated_at: admin.firestore.FieldValue.serverTimestamp()
        }, { merge: true });

        console.log(`  ✅ Enchère initialisée dans 'contests' & 'contest_state' (ID: ${auctionContestId})`);

        console.log("\n✨ [SUCCESS] Injection terminée avec succès ! Vos articles, offres et enchères sont en ligne.");
        process.exit(0);
    } catch (error) {
        console.error("\n❌ [ERROR] Échec lors de l'injection :", error.message);
        console.error("💡 Assurez-vous d'être connecté via 'gcloud auth application-default login' ou d'avoir configuré GOOGLE_APPLICATION_CREDENTIALS.");
        process.exit(1);
    }
}

seedDatabase();
