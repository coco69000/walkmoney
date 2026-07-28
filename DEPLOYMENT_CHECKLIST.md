# ✅ Checklist Déploiement Sécurisé OCR

## Phase 1: Préparation Local (Dev Machine)

- [ ] **Supprimer `.env` ancien**
  ```bash
  git rm .env  # ou supprimer manuellement
  ```
  Vérifie qu'il n'y a PLUS de `GOOGLE_CLOUD_API_KEY`

- [ ] **Tester le build local**
  ```bash
  flutter clean
  flutter pub get
  flutter analyze
  flutter build apk --debug
  ```
  ✅ Doit compiler sans erreurs

- [ ] **Vérifier les logs locaux**
  ```
  [OCR] Appel Cloud Function
  [OCR] Fallback ML Kit [OK]
  ```

---

## Phase 2: Configuration Google Cloud

- [ ] **Créer Service Account**
  1. Aller à: https://console.cloud.google.com/iam-admin/serviceaccounts
  2. Créer account: `firebase-functions-ocr`
  3. Ajouter permission: `Document AI API User`
  4. Créer clé JSON
  5. ⚠️ Ne PAS committer la clé JSON

- [ ] **Configurer Document AI API**
  1. Aller à: https://console.cloud.google.com/apis/library/documentai.googleapis.com
  2. Cliquer "Enable"
  3. Attendre l'activation

- [ ] **Vérifier Processor Document AI**
  ```
  Project ID: 1087731109113
  Processor ID: bf5524b33f20120c
  Region: eu (Europe)
  ```

---

## Phase 3: Déployer Cloud Functions

- [ ] **Mettre à jour dependencies**
  ```bash
  cd functions/
  npm install
  ```
  Vérifie que `@google-cloud/documentai` est installé

- [ ] **Déployer la fonction**
  ```bash
  # Assurez-vous d'être loggé
  firebase login
  
  # Déployer uniquement la nouvelle fonction
  firebase deploy --only functions:processReceiptOCR
  ```

- [ ] **Vérifier la fonction est active**
  ```bash
  firebase functions:list
  ```
  Output doit montrer:
  ```
  ✔ processReceiptOCR - httpCallable
  ```

- [ ] **Vérifier les logs du déploiement**
  ```bash
  firebase functions:log
  ```

---

## Phase 4: Tests Sécurité

- [ ] **Test 1: Appel sans authentification**
  ```javascript
  // Depuis Console Firebase
  const callable = firebase.functions().httpsCallable('processReceiptOCR');
  
  // ❌ Doit retourner erreur
  try {
    await callable({ imageBase64: 'test' });
  } catch (e) {
    console.assert(e.code === 'unauthenticated');
  }
  ```

- [ ] **Test 2: Appel avec authentification**
  ```javascript
  // Après firebase.auth().signIn(...)
  const callable = firebase.functions().httpsCallable('processReceiptOCR');
  
  // ✅ Doit fonctionner
  const result = await callable({ imageBase64: 'test' });
  ```

- [ ] **Test 3: Scanner réel depuis Flutter**
  ```dart
  // Ouvrir l'app
  // Aller à un magasin
  // Cliquer "Scanner ticket"
  // Prendre une photo
  
  // Vérifier les logs flutter:
  // ✅ [OCR] Appel Cloud Function
  // ✅ [OCR] Texte reconnu: XXX caractères
  ```

- [ ] **Test 4: Vérifier pas d'appels directs Document AI**
  ```bash
  # Depuis Burp Suite / Fiddler
  # Intercepter trafic réseau
  
  # ❌ NE PAS voir:
  # - documentai.googleapis.com
  # - eu-documentai.googleapis.com
  
  # ✅ Voir UNIQUEMENT:
  # - firebasefunctions.googleapis.com
  ```

---

## Phase 5: Monitoring Production

- [ ] **Configurer alertes Google Cloud**
  1. Aller à: https://console.cloud.google.com/monitoring/alerting
  2. Créer alerte: "Document AI Quota exceeded"
  3. Email: ops@yourcompany.com

- [ ] **Vérifier les quotas**
  1. Google Cloud Console → Document AI → Quotas
  2. Configurer limite: 100,000 pages/mois (par exemple)
  3. Activer alertes à 80%, 100%

- [ ] **Vérifier les logs Firebase**
  ```bash
  firebase functions:log --limit 50
  ```
  Doit montrer:
  ```
  ✅ OCR réussi: XXX caractères
  ✅ Authentification: user@email.com
  ❌ Erreurs Document AI: [AUCUNE]
  ```

- [ ] **Configurer billing alerts**
  1. Google Cloud Console → Billing
  2. Budget Alerts: $500/mois (par exemple)
  3. Notification: Slack/Email

---

## Phase 6: Documentation & Archive

- [ ] **Documenter Architecture**
  - [x] SECURE_OCR_ARCHITECTURE.md ✅
  - [x] IMPLEMENTATION_NOTES.md (mis à jour)

- [ ] **Archiver les credentials**
  ```
  ❌ NE PAS stocker en Git
  ✅ Stocker dans Google Secret Manager
  
  gcloud secrets create document-ai-key \
    --data-file=/path/to/service-account.json
  ```

- [ ] **Commiter les changements**
  ```bash
  git add lib/main.dart
  git add functions/index.js
  git add functions/package.json
  git add SECURE_OCR_ARCHITECTURE.md
  git add IMPLEMENTATION_NOTES.md
  git commit -m "🛡️ Security Fix: Move OCR to secure Cloud Function backend"
  git push origin main
  ```

- [ ] **Nettoyer le repo**
  ```bash
  # Supprimer anciennes docs dangereuses
  rm DOCUMENT_AI_CONFIG.md
  git add -u
  git commit -m "Remove insecure configuration docs"
  ```

---

## Phase 7: Communication Équipe

- [ ] **Informer l'équipe**
  ```markdown
  📢 ARCHITECTURE CHANGE - OCR Security Update
  
  ❌ DEPRECATED:
  - Direct API calls from Flutter
  - .env API keys
  - Unprotected Document AI access
  
  ✅ NEW:
  - Secure Cloud Function backend
  - Firebase authentication required
  - Service Account credentials (invisible)
  - Protected quotas & monitoring
  
  🛡️ Impact: Better security, no API key exposure
  ```

- [ ] **Mettre à jour docs interne**
  - Ajouter SECURE_OCR_ARCHITECTURE.md aux docs de l'équipe
  - Documenter les credentials dans Secret Manager
  - Ajouter procédure backup/restore

---

## Phase 8: Rollback (Si nécessaire)

Si vous devez revenir en arrière:

```bash
# Désactiver la Cloud Function
firebase deploy --only functions: (l'oublier)

# Ou la supprimer
firebase functions:delete processReceiptOCR

# Revenir au fallback ML Kit
# (L'app continuera de fonctionner avec ML Kit local)
```

---

## 🔍 Troubleshooting

| Problème | Cause | Solution |
|----------|-------|----------|
| "Cloud Function not found" | Pas déployée | `firebase deploy --only functions:processReceiptOCR` |
| "Permission denied" | Service Account manquant permission | Ajouter "Document AI API User" |
| "Image too large" | Base64 > 100MB | Compresser l'image avant l'encoder |
| "Timeout" | Document AI lent | Augmenter timeout à 60s |
| "Unauthenticated" | Firebase auth non fait | Vérifier `context.auth` existe |

---

## ✨ Vérification Finale

Avant de considérer comme "LIVE":

```bash
# 1. Vérifier la compilation
flutter build apk --release
✅ Success

# 2. Vérifier le test scanning
[Lancer l'app et scanner un ticket]
✅ Texte reconnu correctement

# 3. Vérifier les logs
firebase functions:log | grep "processReceiptOCR"
✅ Appels enregistrés

# 4. Vérifier la sécurité
[Décompiler APK et chercher clé API]
✅ Aucune clé trouvée

# 5. Vérifier le coût
[Google Cloud Console → Billing]
✅ Coût < $50/mois
```

---

## 📞 Support

Si vous avez des problèmes:

1. Vérifier les logs: `firebase functions:log`
2. Vérifier les secrets: `gcloud secrets list`
3. Vérifier quotas: Google Cloud Console → Document AI
4. Vérifier perms: Google Cloud IAM Roles

---

**Status**: 🛡️ Sécurisé  
**Dernière mise à jour**: March 15, 2026  
**Approuvé**: ✅ Production Ready
