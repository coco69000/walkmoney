import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Service centralisé de géolocalisation IP avec double niveau de cache
/// (mémoire vive + SharedPreferences pendant 7 jours) pour ne jamais
/// dépasser le quota gratuit d'ipapi.co (1 000 requêtes / mois).
class IpGeoService {
  static Map<String, dynamic>? _memoryCache;
  static Future<Map<String, dynamic>?>? _pendingRequest;

  static const String _prefKeyData = 'cached_ip_geo_data';
  static const String _prefKeyTime = 'cached_ip_geo_timestamp';
  static const int _cacheDurationMs = 7 * 24 * 3600 * 1000; // 7 jours

  /// Récupère les données de géolocalisation IP en priorité depuis le cache.
  static Future<Map<String, dynamic>?> getGeoData() async {
    // 1. Cache mémoire vive (instantané)
    if (_memoryCache != null) {
      return _memoryCache;
    }

    // 2. Mutualisation des requêtes concurrentes au démarrage
    if (_pendingRequest != null) {
      return _pendingRequest;
    }

    _pendingRequest = _fetchAndCache();
    final result = await _pendingRequest;
    _pendingRequest = null;
    return result;
  }

  static Future<Map<String, dynamic>?> _fetchAndCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedJson = prefs.getString(_prefKeyData);
      final int cachedTime = prefs.getInt(_prefKeyTime) ?? 0;
      final int now = DateTime.now().millisecondsSinceEpoch;

      // Utiliser le cache disque s'il a moins de 7 jours
      if (cachedJson != null && (now - cachedTime) < _cacheDurationMs) {
        try {
          final Map<String, dynamic> parsed =
              json.decode(cachedJson) as Map<String, dynamic>;
          _memoryCache = parsed;
          return parsed;
        } catch (_) {}
      }

      // Requête HTTP unique
      final response = await http
          .get(Uri.parse('https://ipapi.co/json/'))
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data =
            json.decode(response.body) as Map<String, dynamic>;
        _memoryCache = data;
        await prefs.setString(_prefKeyData, json.encode(data));
        await prefs.setInt(_prefKeyTime, now);
        return data;
      } else {
        debugPrint(
            "⚠️ ipapi.co réponse ${response.statusCode}: ${response.body}");
      }
    } catch (e) {
      debugPrint("⚠️ Erreur IpGeoService: $e");
    }

    // Repli vers le dernier cache disponible même si expiré
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cachedJson = prefs.getString(_prefKeyData);
      if (cachedJson != null) {
        final Map<String, dynamic> parsed =
            json.decode(cachedJson) as Map<String, dynamic>;
        _memoryCache = parsed;
        return parsed;
      }
    } catch (_) {}

    return null;
  }

  /// Récupère le nom du pays détecté (ex: "France"), avec repli.
  static Future<String> getCountryName({String fallback = "Monde"}) async {
    final geo = await getGeoData();
    if (geo != null) {
      final name = geo['country_name'] ?? geo['country'];
      if (name != null && name.toString().trim().isNotEmpty) {
        return name.toString().trim();
      }
    }
    return fallback;
  }

  /// Récupère le code pays à 2 lettres (ex: "FR"), avec repli.
  static Future<String> getCountryCode({String fallback = "FR"}) async {
    final geo = await getGeoData();
    if (geo != null) {
      final code = geo['country_code'] ?? geo['country'];
      if (code != null && code.toString().trim().isNotEmpty) {
        return code.toString().trim().toUpperCase();
      }
    }
    return fallback;
  }

  /// Déduit le code de langue supporté (sur les 18 langues de l'application)
  /// à partir du code pays ISO-3166-1 alpha-2.
  static String resolveLanguage(String? countryCode) {
    if (countryCode == null) return 'fr';
    final code = countryCode.toUpperCase();
    if (['FR', 'BE', 'LU', 'MC', 'SN', 'CI', 'CM'].contains(code)) {
      return 'fr';
    } else if (['US', 'GB', 'CA', 'AU', 'NZ', 'IE', 'ZA'].contains(code)) {
      return 'en';
    } else if (['ES', 'MX', 'AR', 'CO', 'CL', 'PE', 'VE', 'EC', 'GT', 'CU', 'BO', 'DO', 'HN', 'PY', 'SV', 'NI', 'CR', 'PA', 'UY'].contains(code)) {
      return 'es';
    } else if (['DE', 'AT'].contains(code)) {
      return 'de';
    } else if (['IT', 'SM', 'VA'].contains(code)) {
      return 'it';
    } else if (['PT', 'BR'].contains(code)) {
      return 'pt';
    } else if (['NL'].contains(code)) {
      return 'nl';
    } else if (['PL'].contains(code)) {
      return 'pl';
    } else if (['UA'].contains(code)) {
      return 'uk';
    } else if (['SE'].contains(code)) {
      return 'sv';
    } else if (['DK'].contains(code)) {
      return 'da';
    } else if (['NO'].contains(code)) {
      return 'no';
    } else if (['FI'].contains(code)) {
      return 'fi';
    } else if (['GR', 'CY'].contains(code)) {
      return 'el';
    } else if (['RO', 'MD'].contains(code)) {
      return 'ro';
    } else if (['CZ', 'SK'].contains(code)) {
      return 'cs';
    } else if (['HU'].contains(code)) {
      return 'hu';
    } else if (['TR'].contains(code)) {
      return 'tr';
    } else if (code == 'CH') {
      return 'fr';
    }
    return 'en';
  }
}
