import 'package:get/get.dart';

class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
        'fr_FR': {
          'settings': 'Paramètres',
          'language': 'Langue de l\'application',
          'welcome': 'Bienvenue',
          'home': 'Accueil',
          'leaderboard': 'Classement',
          'challenges': 'Défis',
          'profile': 'Profil',
          'login': 'Se connecter',
          'signup': 'S\'inscrire',
          'username': 'Pseudo',
          'email': 'Adresse e-mail',
          'password': 'Mot de passe',
        },
        'en_US': {
          'settings': 'Settings',
          'language': 'App Language',
          'welcome': 'Welcome',
          'home': 'Home',
          'leaderboard': 'Leaderboard',
          'challenges': 'Challenges',
          'profile': 'Profile',
          'login': 'Sign in',
          'signup': 'Sign up',
          'username': 'Username',
          'email': 'Email address',
          'password': 'Password',
        }
      };
}
