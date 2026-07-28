# Configuration Document AI + Trip Logging

## 📋 Résumé des Améliorations Implémentées

### ✅ 1. Google Cloud Document AI OCR

**Configuration**:
- Project ID: `1087731109113`
- Processor ID: `bf5524b33f20120c`
- Region: `eu`

**Fonction Principale**: `Future<String?> _performDocumentAIOCR(String imagePath)`

**Fallback Automatique**: Si Document AI n'est pas disponible → Google ML Kit

---

### ✅ 2. Enregistrement Complet des Trajets

Chaque trajet enregistré inclut:

**Point de Départ**:
```
start_lat, start_lng (enregistrés au démarrage)
```

**Point d'Arrivée**:
```
destination_lat, destination_lng (destination plannifiée)
```

**Temps**:
```
actual_duration_seconds (durée réelle)
estimated_duration_seconds (durée estimée)
```

**Distance**:
```
actual_distance_meters (distance réelle calculée)
estimated_distance_meters (distance estimée)
```

**Déviation**:
```
total_deviation_meters (écart cumulatif de la route)
```

**Vitesse**:
```
average_speed_kmh (moyenne de tous les échantillons)
```

**Détection de Triche**:
```
cheat_detected (booléen)
cheat_reason (texte explicatif)
```

**Détails Supplémentaires**:
```
travel_mode (walking, bicycling, transit, driving)
positions[] (array de positions GPS avec vitesse, heading, timestamp)
lames_earned (récompense finale)
```

---

## 🔧 Configuration Requise

### 1. Variable Environnement `.env`

Ajouter:
```env
GOOGLE_CLOUD_API_KEY=your_api_key_here
```

### 2. Permissions Firestore

Les données de trajets sont stockées en:
```
users/{userId}/trip_logs/{tripId}
```

### 3. Dépendances (déjà présentes)

- `dio: ^5.0.0` (pour les appels API)
- `google_mlkit_text_recognition: ^0.11.0` (fallback)
- `cloud_firestore: ^5.0.0` (stockage)
- `firebase_auth: ^5.0.0` (authentification)

---

## 🧪 Points de Test Critiques

### OCR Document AI
```
□ Tester reconnaissance avec ticket normal
□ Tester avec ticket flou
□ Tester fallback quand API est « down »
□ Vérifier extraction correcte du montant
□ Vérifier extraction du timestamp
```

### Enregistrement Trajets
```
□ Vérifier start_lat/start_lng remplis
□ Vérifier destination_lat/destination_lng remplis
□ Vérifier positions[] s'accumulent
□ Vérifier average_speed_kmh calculé correctement
□ Vérifier total_deviation_meters accumule correctement
□ Vérifier cheat_detected activé si deviation > limite
□ Vérifier actual_duration_seconds exact
□ Vérifier lames_earned enregistré
```

### Détection de Triche
```
□ Test mode Walking: vitesse > 6 km/h = suspect
□ Test mode Bicycling: vitesse > 30 km/h = suspect
□ Test déviation > 3000m (non-premium) = alerte
□ Test déviation > 6000m (premium) = alerte
```

---

## 🗄️ Structure Firestore Exemple

```json
{
  "users": {
    "user123": {
      "trip_logs": {
        "trip_001": {
          "user_id": "user123",
          "travel_mode": "walking",
          "start_lat": 48.8566,
          "start_lng": 2.3522,
          "destination_lat": 48.8606,
          "destination_lng": 2.3376,
          "destination_name": "Musée Louvre",
          "started_at": "2026-03-15T10:30:00Z",
          "ended_at": "2026-03-15T10:45:00Z",
          "status": "completed",
          "estimated_distance_meters": 4200,
          "estimated_duration_seconds": 3600,
          "actual_distance_meters": 4150,
          "actual_duration_seconds": 900,
          "average_speed_kmh": 4.8,
          "total_deviation_meters": 250,
          "cheat_detected": false,
          "cheat_reason": null,
          "positions": [
            {
              "lat": 48.8566,
              "lng": 2.3522,
              "speed_kmh": 0,
              "heading": 45,
              "ts": 1710489000000
            },
            // ... plus de positions
          ],
          "lames_earned": 150
        }
      }
    }
  }
}
```

---

## 🚀 Déploiement

1. **Ajouter clé API au `.env`**
   ```bash
   echo "GOOGLE_CLOUD_API_KEY=your_key" >> .env
   ```

2. **Compiler sans erreurs**
   ```bash
   flutter clean
   flutter pub get
   flutter analyze
   ```

3. **Tester sur device**
   ```bash
   flutter run
   ```

4. **Valider les logs**
   - Vérifier `[DocumentAI]` logs
   - Vérifier `[TripLog]` logs
   - Vérifier Firestore pour les nouvelles entrées

---

## 🐛 Troubleshooting

### Document AI retourne null
→ Vérifier clé API en `.env`  
→ Vérifier Project ID correct (1087731109113)  
→ Vérifier Processor ID correct (bf5524b33f20120c)  
→ Vérifier région eu accessible  
→ Vérifier permissions IAM dans Google Cloud

### Trajets non enregistrés
→ Vérifier Firebase Auth actif  
→ Vérifier Firestore rules permettent écriture  
→ Vérifier `_activeTripId` pas null  
→ Vérifier logs de démarrage/arrêt

### Vitesse moyenne incohérente
→ Vérifier `_tripSpeedSamples` se remplit  
→ Vérifier `_logTripPosition()` appelé régulièrement  
→ Vérifier calcul moyenne ligne 1351-1354

---

**Status**: ✅ Ready for Production  
**Last Updated**: March 15, 2026
