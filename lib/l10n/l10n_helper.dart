import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'app_localizations.dart';
import 'app_localizations_en.dart';

export 'app_localizations.dart';

/// Extension for convenient access to translations from any BuildContext
extension LocalizedContext on BuildContext {
  AppLocalizations get tr => AppLocalizations.of(this) ?? AppLocalizationsEn();
}

/// Global helper for accessing translations even outside of a BuildContext (controllers, snackbars, etc.)
AppLocalizations get currentL10n {
  try {
    if (Get.context != null) {
      final l10n = AppLocalizations.of(Get.context!);
      if (l10n != null) return l10n;
    }
  } catch (_) {}
  return AppLocalizationsEn();
}
