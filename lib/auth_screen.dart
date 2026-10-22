import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'constants.dart';
import 'main.dart' show MainScreenController, resetAppControllers;
import 'l10n/l10n_helper.dart';
import 'ip_geo_service.dart';

class AuthController extends GetxController {
  final RxBool isLoadingOnboarding = true.obs;
  final RxBool hasSeenOnboarding = false.obs;
  final RxInt currentPage = 0.obs;

  final RxBool isLoadingAuth = false.obs;
  final RxBool isLogin = true.obs;
  final RxBool acceptTerms = false.obs;

  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  PageController? _pageController;
  PageController get pageController => _pageController ??= PageController();

  List<Map<String, String>> getSlides(BuildContext context) {
    final l10n = context.tr;
    return [
      {
        "title": l10n.onboardingTitle1,
        "description": l10n.onboardingDesc1,
        "icon": "directions_walk"
      },
      {
        "title": l10n.onboardingTitle2,
        "description": l10n.onboardingDesc2,
        "icon": "receipt_long"
      },
      {
        "title": l10n.onboardingTitle3,
        "description": l10n.onboardingDesc3,
        "icon": "eco"
      },
    ];
  }

  @override
  void onInit() {
    super.onInit();
    checkOnboarding();
  }

  @override
  void onClose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    _pageController?.dispose();
    _pageController = null;
    super.onClose();
  }

  Future<void> checkOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 1. Gérer l'Onboarding
      hasSeenOnboarding.value = prefs.getBool('has_seen_onboarding') ?? false;

      // 2. Gérer la langue via IP avec un timeout strict pour ne JAMAIS bloquer
      String? savedLang = prefs.getString('app_language');
      if (savedLang != null) {
        Get.updateLocale(Locale(savedLang));
      } else {
        try {
          final data = await IpGeoService.getGeoData()
              .timeout(const Duration(seconds: 2));
          if (data != null) {
            String countryCode =
                (data['country_code'] ?? data['countryCode'] ?? 'FR')
                    .toString()
                    .toUpperCase();
            String detectedLang = IpGeoService.resolveLanguage(countryCode);
            Get.updateLocale(Locale(detectedLang));
            prefs.setString('app_language', detectedLang);
          }
        } catch (e) {
          debugPrint("⚠️ Timeout ou erreur IpGeoService (fallback 'fr') : $e");
          Get.updateLocale(const Locale('fr'));
        }
      }
    } catch (e) {
      debugPrint("⚠️ Erreur SharedPreferences dans checkOnboarding : $e");
    } finally {
      // Quoi qu'il arrive, on arrête le loader !
      isLoadingOnboarding.value = false;
    }
  }

  Future<void> completeOnboarding() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_onboarding', true);
    } catch (e) {
      debugPrint("⚠️ Impossible d'écrire has_seen_onboarding dans SharedPreferences : $e");
    } finally {
      // Déclenche le passage à l'écran suivant QUOI QU'IL ARRIVE
      hasSeenOnboarding.value = true;
    }
  }

  void toggleAuthMode() {
    isLogin.value = !isLogin.value;
  }

  Future<void> submitAuth(BuildContext context) async {
    final l10n = context.tr;
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final username = usernameController.text.trim();

    if (!isLogin.value && username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.enterUsername)),
      );
      return;
    }

    if (!isLogin.value && !acceptTerms.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.mustAcceptTerms),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.fillEmailAndPassword)),
      );
      return;
    }

    final emailRegex = RegExp(
        r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+$");
    if (!emailRegex.hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Format d'adresse e-mail invalide."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validation du pseudo à l'inscription (3 à 20 caractères, alphanumérique et underscores)
    if (!isLogin.value) {
      if (username.length < 3 || username.length > 20) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Le pseudo doit contenir entre 3 et 20 caractères."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      final usernameRegex = RegExp(r'^[a-zA-Z0-9_]+$');
      if (!usernameRegex.hasMatch(username)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "Le pseudo ne peut contenir que des lettres, chiffres et tirets bas (_)."),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    // Validation mot de passe (8+ caractères avec lettres et chiffres à l'inscription)
    if (!isLogin.value) {
      final bool hasMinLength = password.length >= 8;
      final bool hasLetter = RegExp(r'[A-Za-z]').hasMatch(password);
      final bool hasDigit = RegExp(r'[0-9]').hasMatch(password);
      if (!hasMinLength || !hasLetter || !hasDigit) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.passwordMinLength),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    } else {
      if (password.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.passwordMinLength)),
        );
        return;
      }
    }

    isLoadingAuth.value = true;

    try {
      if (isLogin.value) {
        // CONNEXION
        final userCred =
            await fb_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        if (userCred.user != null) {
          try {
            await Purchases.logIn(userCred.user!.uid);
          } catch (e) {
            debugPrint("Erreur RevenueCat logIn : $e");
          }
          emailController.clear();
          passwordController.clear();
          usernameController.clear();
        }
      } else {
        // INSCRIPTION
        fb_auth.UserCredential userCred =
            await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        final user = userCred.user;
        if (user == null) {
          throw fb_auth.FirebaseAuthException(
            code: 'user-not-found',
            message: 'Impossible de créer le compte utilisateur.',
          );
        }
        final uid = user.uid;

        // 1. Initialisation directe du profil utilisateur dans Firestore
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'username': username,
          'email': email,
          'lame_points': 0,
          'total_lame_earned': 0,
          'is_vip': false,
          'consecutive_logins': 1,
          'current_level': 1,
          'next_level_boost': 1.0,
          'total_distance_km': 0.0,
          'total_trips_count': 0,
          'total_calories_burned': 0,
          'country': "Monde",
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        await FirebaseFirestore.instance
            .collection('public_profiles')
            .doc(uid)
            .set({
          'id': uid,
          'username': username,
          'current_level': 1,
          'country': "Monde",
          'total_lame_earned': 0,
          'total_distance_km': 0.0,
          'total_trips_count': 0,
          'unlocked_badges': [],
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // 2. Mise à jour du DisplayName
        try {
          await user.updateDisplayName(username);
        } catch (_) {}

        // 3. Appel de réservation serveur du pseudo en non-bloquant
        try {
          final callable =
              FirebaseFunctions.instance.httpsCallable('claimInitialUsername');
          await callable.call({'username': username});
        } catch (claimErr) {
          debugPrint("⚠️ Note réservation pseudo: $claimErr");
        }

        try {
          await Purchases.logIn(uid);
        } catch (e) {
          debugPrint("Erreur RevenueCat logIn : $e");
        }

        // 4. Détection de pays en tâche de fond
        IpGeoService.getCountryName().then((detectedCountry) {
          final batch = FirebaseFirestore.instance.batch();
          batch.set(
              FirebaseFirestore.instance.collection('users').doc(uid),
              {'country': detectedCountry},
              SetOptions(merge: true));
          batch.set(
              FirebaseFirestore.instance.collection('public_profiles').doc(uid),
              {'country': detectedCountry},
              SetOptions(merge: true));
          batch.commit().catchError((e) {
            debugPrint("Erreur commit pays : $e");
          });
        }).catchError((_) {});

        try {
          await user.sendEmailVerification();
        } catch (_) {}

        emailController.clear();
        passwordController.clear();
        usernameController.clear();

        // Affichage notification sécurisé sans context potentiellement démonté
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (Get.overlayContext != null) {
            Get.snackbar(
              "Compte créé !",
              "Bienvenue sur EcoNav. Vérifiez votre boîte e-mail pour confirmer votre compte.",
              backgroundColor: Colors.green,
              colorText: Colors.white,
              duration: const Duration(seconds: 4),
            );
          }
        });
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      final l10n = currentL10n;
      String errorMessage = l10n.authError;
      if (e.code == 'weak-password') {
        errorMessage = l10n.weakPassword;
      } else if (e.code == 'email-already-in-use') {
        errorMessage = l10n.emailAlreadyInUse;
      } else if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        errorMessage = l10n.wrongCredentials;
      } else if (e.code == 'invalid-email') {
        errorMessage = l10n.invalidEmail;
      } else {
        errorMessage = e.message ?? errorMessage;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Get.overlayContext != null) {
          Get.snackbar(l10n.error, errorMessage,
              backgroundColor: Colors.red, colorText: Colors.white);
        }
      });
    } catch (e) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (Get.overlayContext != null) {
          Get.snackbar("Erreur", '$e',
              backgroundColor: Colors.red, colorText: Colors.white);
        }
      });
    } finally {
      isLoadingAuth.value = false;
    }
  }

  Future<void> sendPasswordReset(BuildContext context) async {
    final l10n = context.tr;
    final email = emailController.text.trim();
    if (email.isEmpty) {
      Get.snackbar(
        l10n.emailRequired,
        l10n.enterEmailForReset,
        backgroundColor: Colors.orange,
        colorText: Colors.white,
      );
      return;
    }

    try {
      await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (context.mounted) {
        Get.snackbar(
          l10n.emailSent,
          'Si un compte est associé à $email, un e-mail de réinitialisation a été envoyé.',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      // Protection anti-énumération de comptes (Item 138)
      if (e.code == 'user-not-found') {
        Get.snackbar(
          l10n.emailSent,
          'Si un compte est associé à $email, un e-mail de réinitialisation a été envoyé.',
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );
        return;
      }
      String msg = l10n.authError;
      if (e.code == 'invalid-email') {
        msg = l10n.invalidEmail;
      } else {
        msg = e.message ?? msg;
      }
      Get.snackbar(l10n.error, msg,
          backgroundColor: Colors.red, colorText: Colors.white);
    } catch (e) {
      Get.snackbar(l10n.error, '$e',
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }
}

class OnboardingGuard extends StatelessWidget {
  const OnboardingGuard({super.key});

  @override
  Widget build(BuildContext context) {
    final authController = Get.isRegistered<AuthController>()
        ? Get.find<AuthController>()
        : Get.put(AuthController());

    return Obx(() {
      if (authController.isLoadingOnboarding.value) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: primaryGreen)),
        );
      }

      if (!authController.hasSeenOnboarding.value) {
        return OnboardingScreen(
            onFinish: () => authController.completeOnboarding());
      }

      return StreamBuilder<fb_auth.User?>(
        stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body:
                  Center(child: CircularProgressIndicator(color: primaryGreen)),
            );
          }
          if (snapshot.hasData && snapshot.data != null) {
            return MainScreenController();
          }
          // L'utilisateur est déconnecté : réinitialise les contrôleurs pour éviter les résidus
          resetAppControllers();
          return const AuthScreen();
        },
      );
    });
  }
}

class OnboardingScreen extends StatelessWidget {
  final VoidCallback onFinish;

  const OnboardingScreen({super.key, required this.onFinish});

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'directions_walk':
        return Icons.directions_walk;
      case 'receipt_long':
        return Icons.receipt_long;
      case 'emoji_events':
        return Icons.emoji_events;
      case 'eco':
        return Icons.eco;
      default:
        return Icons.star;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authController = Get.find<AuthController>();
    final l10n = context.tr;
    final slides = authController.getSlides(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: authController.pageController,
                onPageChanged: (index) {
                  authController.currentPage.value = index;
                },
                itemCount: slides.length,
                itemBuilder: (context, index) {
                  final slide = slides[index];
                  return Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(30),
                          decoration: BoxDecoration(
                            color: primaryGreen.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _getIconData(slide["icon"]!),
                            size: 100,
                            color: primaryGreen,
                          ),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          slide["title"]!,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: textDark,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          slide["description"]!,
                          style: const TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Obx(() => Row(
                        children: List.generate(
                          slides.length,
                          (index) => Container(
                            margin: const EdgeInsets.only(right: 5),
                            height: 10,
                            width: authController.currentPage.value == index
                                ? 25
                                : 10,
                            decoration: BoxDecoration(
                              color: authController.currentPage.value == index
                                  ? primaryGreen
                                  : Colors.grey[300],
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      )),
                  Obx(() => ElevatedButton(
                        onPressed: () {
                          if (authController.currentPage.value ==
                              slides.length - 1) {
                            onFinish();
                          } else {
                            authController.pageController.nextPage(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeIn,
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 30, vertical: 12),
                        ),
                        child: Text(
                          authController.currentPage.value ==
                                  slides.length - 1
                              ? l10n.getStarted
                              : l10n.next,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      )),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authController = Get.find<AuthController>();
    final l10n = context.tr;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primaryGreen, Colors.green[900]!],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Icon(Icons.eco, size: 60, color: Colors.white),
              const SizedBox(height: 10),
              const Text(
                "EcoNav",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 20),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(40)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Obx(() => Text(
                          authController.isLogin.value
                              ? l10n.welcomeBack
                              : l10n.createAccount,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: textDark,
                          ),
                          textAlign: TextAlign.center,
                        )),
                    const SizedBox(height: 30),

                    // CHAMP PSEUDO (Seulement pour l'inscription)
                    Obx(() {
                      if (authController.isLogin.value) {
                        return const SizedBox.shrink();
                      }
                      return Column(
                        children: [
                          TextField(
                            controller: authController.usernameController,
                            autofillHints: const [AutofillHints.username],
                            decoration: InputDecoration(
                              labelText: l10n.username,
                              prefixIcon:
                                  const Icon(Icons.person, color: primaryGreen),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: Colors.grey[100],
                            ),
                          ),
                          const SizedBox(height: 15),
                        ],
                      );
                    }),

                    // CHAMP EMAIL
                    TextField(
                      controller: authController.emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(
                        labelText: l10n.email,
                        prefixIcon:
                            const Icon(Icons.email, color: primaryGreen),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    ),
                    const SizedBox(height: 15),

                    // CHAMP MOT DE PASSE
                    TextField(
                      controller: authController.passwordController,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.password],
                      decoration: InputDecoration(
                        labelText: l10n.password,
                        prefixIcon: const Icon(Icons.lock, color: primaryGreen),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    ),
                    // LIEN MOT DE PASSE OUBLIÉ (affiché uniquement en mode connexion)
                    Obx(() {
                      if (!authController.isLogin.value) {
                        return const SizedBox.shrink();
                      }
                      return Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            final resetEmailController = TextEditingController(
                              text: authController.emailController.text.trim(),
                            );

                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Mot de passe oublié"),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "Saisissez votre e-mail pour recevoir un lien de réinitialisation :",
                                      style: TextStyle(fontSize: 14),
                                    ),
                                    const SizedBox(height: 12),
                                    TextField(
                                      controller: resetEmailController,
                                      keyboardType: TextInputType.emailAddress,
                                      decoration: const InputDecoration(
                                        labelText: "Adresse e-mail",
                                        border: OutlineInputBorder(),
                                      ),
                                    ),
                                  ],
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx),
                                    child: const Text("Annuler"),
                                  ),
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: primaryGreen),
                                    onPressed: () async {
                                      final email =
                                          resetEmailController.text.trim();
                                      if (email.isEmpty) return;

                                      Navigator.pop(ctx);
                                      authController.emailController.text =
                                          email;
                                      await authController
                                          .sendPasswordReset(context);
                                    },
                                    child: const Text("Envoyer le lien"),
                                  ),
                                ],
                              ),
                            );
                          },
                          child: Text(
                            l10n.forgotPassword,
                            style: const TextStyle(
                              color: primaryGreen,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      );
                    }),
                    // CHAMP CONDITIONS LÉGALES (Uniquement affiché lors de l'inscription)
                    Obx(() {
                      if (authController.isLogin.value) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 15.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Checkbox(
                              value: authController.acceptTerms.value,
                              activeColor: primaryGreen,
                              onChanged: (val) => authController
                                  .acceptTerms.value = val ?? false,
                            ),
                            Expanded(
                              child: Wrap(
                                children: [
                                  Text(l10n.acceptTermsPrefix,
                                      style: const TextStyle(
                                          fontSize: 12, color: textDark)),
                                  GestureDetector(
                                    onTap: () => launchUrl(
                                      Uri.parse(
                                          'https://walkmoney-1cdad.web.app/cgu'),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                    child: Text(
                                      l10n.cguAndEula,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: primaryGreen,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline),
                                    ),
                                  ),
                                  Text(l10n.andThe,
                                      style: const TextStyle(
                                          fontSize: 12, color: textDark)),
                                  GestureDetector(
                                    onTap: () => launchUrl(
                                      Uri.parse(
                                          'https://walkmoney-1cdad.web.app/privacy'),
                                      mode: LaunchMode.externalApplication,
                                    ),
                                    child: Text(
                                      l10n.privacyPolicy,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: primaryGreen,
                                          fontWeight: FontWeight.bold,
                                          decoration: TextDecoration.underline),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    // BOUTON DE VALIDATION
                    Obx(() {
                      if (authController.isLoadingAuth.value) {
                        return const Center(
                            child:
                                CircularProgressIndicator(color: primaryGreen));
                      }
                      return ElevatedButton(
                        onPressed: () => authController.submitAuth(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryGreen,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15),
                          ),
                          elevation: 2,
                        ),
                        child: Text(
                          authController.isLogin.value
                              ? l10n.login
                              : l10n.signup,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      );
                    }),
                    const SizedBox(height: 15),

                    // BOUTON BASCULE LOGIN / SIGNUP
                    Obx(() => TextButton(
                          onPressed: () => authController.toggleAuthMode(),
                          child: Text(
                            authController.isLogin.value
                                ? l10n.noAccountYet
                                : l10n.alreadyHaveAccount,
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        )),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  ),
);
  }
}
