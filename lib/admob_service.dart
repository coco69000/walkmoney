import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class AdMobService {
  static RewardedAd? _rewardedAd;
  static bool _isAdLoading = false;

  /// ID de bloc d'annonces récompensées (Rewarded)
  static String get rewardedAdUnitId {
    if (kDebugMode) {
      // Identifiants de test officiels Google AdMob
      return Platform.isAndroid
          ? 'ca-app-pub-3940256099942544/5224354917'
          : 'ca-app-pub-3940256099942544/1712485313';
    }
    // En production, lecture depuis le .env
    return Platform.isAndroid
        ? (dotenv.env['ADMOB_REWARDED_ANDROID'] ?? '')
        : (dotenv.env['ADMOB_REWARDED_IOS'] ?? '');
  }

  /// Initialisation du SDK
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
    loadRewardedAd(); // Pré-charge la première publicité
  }

  /// Pré-chargement en mémoire
  static void loadRewardedAd() {
    if (_isAdLoading || _rewardedAd != null) return;
    _isAdLoading = true;

    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedAd = ad;
          _isAdLoading = false;
          debugPrint('✅ AdMob: Rewarded Ad chargée avec succès.');
        },
        onAdFailedToLoad: (error) {
          _rewardedAd = null;
          _isAdLoading = false;
          debugPrint('❌ AdMob: Échec chargement pub: $error');
        },
      ),
    );
  }

  /// Affiche la pub et exécute onUserEarnedReward si la pub a été visionnée jusqu'au bout
  static void showRewardedAd({
    required Function(RewardItem reward) onUserEarnedReward,
    VoidCallback? onAdFailedToShow,
  }) {
    if (_rewardedAd == null) {
      debugPrint('⚠️ AdMob: Aucune pub disponible. Tentative de rechargement...');
      loadRewardedAd();
      if (onAdFailedToShow != null) onAdFailedToShow();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd(); // Recharger immédiatement pour la prochaine fois
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('❌ AdMob: Échec affichage pub: $error');
        ad.dispose();
        _rewardedAd = null;
        loadRewardedAd();
        if (onAdFailedToShow != null) onAdFailedToShow();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (adWithoutView, reward) {
        onUserEarnedReward(reward);
      },
    );
  }
}
