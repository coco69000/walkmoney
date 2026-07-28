import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'main.dart'; // Pour accéder à primaryGreen, textDark, MainScreenController etc.

class AuthController extends GetxController {
  final RxBool isLoadingOnboarding = true.obs;
  final RxBool hasSeenOnboarding = false.obs;
  final RxInt currentPage = 0.obs;

  final RxBool isLoadingAuth = false.obs;
  final RxBool isLogin = true.obs;

  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final PageController pageController = PageController();

  final List<Map<String, String>> slides = const [
    {
      "title": "Marchez, Roulez, Gagnez",
      "description": "Utilisez des modes de transport doux et cumulez des Lames pour chaque kilomètre parcouru.",
      "icon": "directions_walk"
    },
    {
      "title": "Défis & Cashbacks",
      "description": "Rendez-vous dans nos magasins partenaires, validez vos achats et gagnez du cashback.",
      "icon": "receipt_long"
    },
    {
      "title": "Protégez la planète",
      "description": "Plantez des arbres, faites des dons ou récupérez des cartes cadeaux avec vos gains.",
      "icon": "eco"
    },
  ];

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
    pageController.dispose();
    super.onClose();
  }

  Future<void> checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Gérer l'Onboarding
    hasSeenOnboarding.value = prefs.getBool('has_seen_onboarding') ?? false;

    // 2. Gérer la langue via IP (uniquement si aucune langue n'est sauvegardée)
    String? savedLang = prefs.getString('app_language');
    if (savedLang != null) {
      Get.updateLocale(Locale(savedLang));
    } else {
      try {
        final response = await http.get(Uri.parse('http://ip-api.com/json'));
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          String countryCode = data['countryCode'] ?? 'FR';
          if (['FR', 'BE', 'CH', 'CA', 'LU'].contains(countryCode)) {
            Get.updateLocale(const Locale('fr', 'FR'));
            prefs.setString('app_language', 'fr');
          } else {
            Get.updateLocale(const Locale('en', 'US'));
            prefs.setString('app_language', 'en');
          }
        }
      } catch (e) {
        Get.updateLocale(const Locale('fr', 'FR'));
      }
    }

    isLoadingOnboarding.value = false;
  }

  Future<void> completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_onboarding', true);
    hasSeenOnboarding.value = true;
  }

  void toggleAuthMode() {
    isLogin.value = !isLogin.value;
  }

  Future<void> submitAuth(BuildContext context) async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final username = usernameController.text.trim();

    if (!isLogin.value && username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer un pseudo.')),
      );
      return;
    }

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez remplir l\'e-mail et le mot de passe.')),
      );
      return;
    }

    if (password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le mot de passe doit contenir au moins 6 caractères.')),
      );
      return;
    }

    isLoadingAuth.value = true;

    try {
      if (isLogin.value) {
        // CONNEXION
        await fb_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        // INSCRIPTION
        fb_auth.UserCredential userCred =
            await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Mettre à jour le displayName Firebase
        await userCred.user!.updateDisplayName(username);

        // Détection de l'IP pour le pays
        String detectedCountry = "Monde";
        try {
          final response = await http.get(Uri.parse('http://ip-api.com/json'));
          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            detectedCountry = data['country'] ?? "Monde";
          }
        } catch (e) {
          debugPrint("Erreur détection IP pays : $e");
        }

        // Création du document utilisateur dans Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userCred.user!.uid)
            .set({
          'username': username,
          'email': email,
          'lame_points': 0,
          'total_lame_earned': 0,
          'is_vip': false,
          'consecutive_logins': 0,
          'current_level': 1,
          'next_level_boost': 1.0,
          'total_distance_km': 0.0,
          'total_trips_count': 0,
          'total_calories_burned': 0,
          'country': detectedCountry,
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Inscription réussie !')),
          );
        }
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      String errorMessage = "Erreur d'authentification.";
      if (e.code == 'weak-password') {
        errorMessage = 'Le mot de passe fourni est trop faible.';
      } else if (e.code == 'email-already-in-use') {
        errorMessage = 'Un compte existe déjà pour cet e-mail.';
      } else if (e.code == 'user-not-found' ||
          e.code == 'wrong-password' ||
          e.code == 'invalid-credential') {
        errorMessage = 'Identifiants incorrects.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'L\'adresse e-mail n\'est pas valide.';
      } else {
        errorMessage = e.message ?? errorMessage;
      }
      if (context.mounted) {
        Get.snackbar('Erreur', errorMessage,
            backgroundColor: Colors.red, colorText: Colors.white);
      }
    } catch (e) {
      if (context.mounted) {
        Get.snackbar('Erreur', 'Une erreur est survenue: $e',
            backgroundColor: Colors.red, colorText: Colors.white);
      }
    } finally {
      isLoadingAuth.value = false;
    }
  }
}

class OnboardingGuard extends StatelessWidget {
  const OnboardingGuard({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authController = Get.put(AuthController());

    return Obx(() {
      if (authController.isLoadingOnboarding.value) {
        return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: primaryGreen)),
        );
      }

      if (!authController.hasSeenOnboarding.value) {
        return OnboardingScreen(onFinish: () => authController.completeOnboarding());
      }

      return StreamBuilder<fb_auth.User?>(
        stream: fb_auth.FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator(color: primaryGreen)),
            );
          }
          if (snapshot.hasData && snapshot.data != null) {
            return MainScreenController();
          }
          return const AuthScreen();
        },
      );
    });
  }
}

class OnboardingScreen extends StatelessWidget {
  final VoidCallback onFinish;

  const OnboardingScreen({Key? key, required this.onFinish}) : super(key: key);

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
                itemCount: authController.slides.length,
                itemBuilder: (context, index) {
                  final slide = authController.slides[index];
                  return Padding(
                    padding: const EdgeInsets.all(40.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(30),
                          decoration: BoxDecoration(
                            color: primaryGreen.withOpacity(0.1),
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
                          authController.slides.length,
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
                              authController.slides.length - 1) {
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
                                  authController.slides.length - 1
                              ? "Commencer"
                              : "Suivant",
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
  const AuthScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final authController = Get.find<AuthController>();

    return Scaffold(
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
              const Spacer(),
              const Icon(Icons.eco, size: 80, color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                "EcoNav",
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(30),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(40)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Obx(() => Text(
                          authController.isLogin.value
                              ? "Bon retour !"
                              : "Créer un compte",
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
                            decoration: InputDecoration(
                              labelText: 'Pseudo',
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
                      decoration: InputDecoration(
                        labelText: 'Email',
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
                      decoration: InputDecoration(
                        labelText: 'Mot de passe',
                        prefixIcon: const Icon(Icons.lock, color: primaryGreen),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Colors.grey[100],
                      ),
                    ),
                    const SizedBox(height: 25),

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
                              ? "Se connecter"
                              : "S'inscrire",
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
                                ? "Pas encore de compte ? S'inscrire"
                                : "Déjà un compte ? Se connecter",
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
