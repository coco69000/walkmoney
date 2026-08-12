import 'dart:math' as gmaps_utils show Point;
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, kDebugMode; // Pour détecter si on est sur le Web / debug
import 'package:flutter/services.dart'; // Pour MethodChannel
import 'dart:io'; // Pour Platform
import 'package:google_maps_utils/google_maps_utils.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:math';
// MODIFIÉ: Alias pour éviter les conflits de noms.
import 'package:google_maps_utils/google_maps_utils.dart' as gmaps_utils
    show Point, PolyUtils;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'
    hide Priority; // <--- AJOUT POUR LE TICKER VSYNC
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_html/flutter_html.dart' as html;
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
import 'app_translations.dart';
import 'package:google_directions_api/google_directions_api.dart';
import 'package:http/http.dart' as http;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:maps_toolkit/maps_toolkit.dart' as toolkit;
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'firebase_options.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:latlong2/latlong.dart' as latlong;
// --- CONSTANTES MISES À JOUR ---
import 'package:shared_preferences/shared_preferences.dart';
// --- SERVICE OSRM (NOUVEAU) ---
// --- SERVICES ---
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // IMPORTANT POUR LA NOTIF
import 'package:safe_device/safe_device.dart'; // <--- AJOUTER CET IMPORT
import 'package:google_generative_ai/google_generative_ai.dart';
import 'auth_screen.dart';

class OsrmService {
  final Dio _dio = Dio();

  // AJOUT: On ajoute un paramètre optionnel "bearing"
  Future<Map<String, dynamic>?> getRoute(LatLng start, LatLng end, String mode,
      {double? bearing}) async {
    String baseUrl;
    String urlProfile = 'driving';

    if (mode == Constants.modeCycling) {
      baseUrl = "https://routing.openstreetmap.de/routed-bike";
    } else if (mode == Constants.modeWalking) {
      baseUrl = "https://routing.openstreetmap.de/routed-foot";
    } else {
      baseUrl = "https://router.project-osrm.org";
    }

    // OSRM format de base
    String url =
        "$baseUrl/route/v1/$urlProfile/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson&steps=true";

    // AJOUT: Si on a un cap (bearing), on force OSRM à partir dans cette direction (tolérance de 45 degrés)
    // Le ";" vide à la fin signifie qu'on n'impose pas de direction d'arrivée.
    if (bearing != null && bearing >= 0) {
      url += "&bearings=${bearing.round()},45;";
    }

    try {
      var response = await _dio.get(url);

      if (response.statusCode == 200 &&
          response.data['routes'] != null &&
          response.data['routes'].isNotEmpty) {
        return response.data['routes'][0];
      }
    } catch (e) {
      debugPrint("Erreur OSRM ($mode): $e");
    }
    return null;
  }
}

class PhotonService {
  final Dio _dio = Dio();
  static const String _userAgent = 'WalkMoneyApp/1.0 (contact@walkmoney.com)';

  Future<List<dynamic>> searchPlace(String query) async {
    final String url =
        "https://photon.komoot.io/api/?q=${Uri.encodeQueryComponent(query)}&limit=10";
    try {
      var response = await _dio.get(url,
          options: Options(headers: {'User-Agent': _userAgent}));
      if (response.statusCode == 200 && response.data['features'] != null) {
        return (response.data['features'] as List).map((f) {
          final props = f['properties'] ?? {};
          final coords = f['geometry']?['coordinates'] ?? [0.0, 0.0];
          String name = props['name'] ?? '';
          String city =
              props['city'] ?? props['town'] ?? props['village'] ?? '';
          String display = name.isNotEmpty
              ? (city.isNotEmpty ? '$name, $city' : name)
              : city;

          return {
            'display_name': display.isEmpty ? 'Lieu inconnu' : display,
            'lat': coords.length >= 2 ? coords[1].toString() : '0',
            'lon': coords.length >= 2 ? coords[0].toString() : '0',
          };
        }).toList();
      }
    } catch (e) {
      debugPrint("Erreur Photon search: $e");
    }
    return [];
  }

  Future<Map<String, dynamic>?> reverseGeocode(double lat, double lon) async {
    final String url = "https://photon.komoot.io/reverse?lon=$lon&lat=$lat";
    try {
      var response = await _dio.get(url,
          options: Options(headers: {'User-Agent': _userAgent}));
      if (response.statusCode == 200 &&
          response.data['features'] != null &&
          (response.data['features'] as List).isNotEmpty) {
        return {'address': response.data['features'][0]['properties']};
      }
    } catch (e) {
      debugPrint("Erreur Photon reverse: $e");
    }
    return null;
  }

  Future<Map<String, dynamic>?> geocode(String query) async {
    final results = await searchPlace(query);
    if (results.isNotEmpty) {
      return Map<String, dynamic>.from(results.first);
    }
    return null;
  }
}

// Représente le point le plus proche sur l'itinéraire calculé, et la distance à ce point.
class _RouteSnapResult {
  final LatLng point;
  final double distance;

  _RouteSnapResult(this.point, this.distance);
}

class MyVehicle {
  final String? name;
  final String? type;
  final String? icon;

  MyVehicle({this.name, this.type, this.icon});
}

class MyLine {
  final String? name;
  final String? shortName;
  final MyVehicle? vehicle;

  MyLine({this.name, this.shortName, this.vehicle});
}

class MyStop {
  final String? name;
  final LatLng? location;

  MyStop({this.name, this.location});
}

class MyTransitDetails {
  final MyStop? arrivalStop;
  final MyStop? departureStop;
  final MyLine? line;
  final String? headsign;
  final int? numStops;

  MyTransitDetails({
    this.arrivalStop,
    this.departureStop,
    this.line,
    this.headsign,
    this.numStops,
  });
}

class DirectionModelDistance {
  double? lat;
  double? lng;

  DirectionModelDistance({this.lat, this.lng});

  DirectionModelDistance.fromJson(Map<String, dynamic> json) {
    lat = json['lat']?.toDouble();
    lng = json['lng']?.toDouble();
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['lat'] = lat;
    data['lng'] = lng;
    return data;
  }
}

// Find this class in your main.dart
class DirectionModel {
  String? instructions;
  DirectionModelDistance? distance;

  DirectionModel({this.instructions, this.distance});

  DirectionModel.fromJson(Map<String, dynamic> json) {
// 1. Handle Instructions (OSRM puts instructions in 'maneuver', Google in 'html_instructions')
// We try to grab the best available string.
    if (json['maneuver'] != null && json['maneuver']['type'] != null) {
// OSRM logic: usually combination of type and modifier
      instructions =
          "${json['maneuver']['type']} ${json['maneuver']['modifier'] ?? ''}";
    } else {
// Google / Fallback logic
      instructions =
          json['html_instructions'] ?? json['instructions']?.toString();
    }

// 2. FIX THE CRASH HERE
// Check if 'distance' is actually a Map before trying to parse it as an object.
    if (json['distance'] != null && json['distance'] is Map<String, dynamic>) {
      distance = DirectionModelDistance.fromJson(json['distance']);
    } else {
// If it's a double (OSRM) or null, we assume no complex object exists
      distance = null;
    }
  }

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    data['instructions'] = instructions;
    if (distance != null) {
      data['distance'] = distance!.toJson();
    }
    return data;
  }
}

class Constants {
// Images
  static const driverCarImage = 'assets/images/car.png';
  static const mapIcon = 'assets/images/map_icon.png';
  static const locateMeIcon = 'assets/images/locate_me.png';

// États de la map
  static const idle = "idle";
  static const route = "route";
  static const onDestination = "on destination";

// Style MapLibre (OpenFreeMap)
  static const mapStyle = 'https://tiles.openfreemap.org/styles/liberty';

// Modes de transport
  static const modeDriving = 'driving';
  static const modeCycling = 'cycling';
  static const modeWalking = 'walking';
  static const modeTransit = 'transit';

// Directions (pour l'affichage des instructions)
  static const north = 'north';
  static const east = 'east';
  static const south = 'south';
  static const west = 'west';
  static const northEast = 'northeast';
  static const northWest = 'northwest';
  static const southEast = 'southeast';
  static const southWest = 'southwest';
  static const straight = 'straight';
  static const right = 'right';
  static const left = 'left';
}

enum CheatModeStatus {
  none,
  exceededSpeedWarning,
  exceededSpeedCheating,
}

class SpeedController extends GetxController {
  final RxDouble currentSpeed = 0.0.obs;

// Gestion de la triche (gardé de votre ancien code pour compatibilité)
  final Rx<CheatModeStatus> cheatStatus = CheatModeStatus.none.obs;
  final RxString cheatWarningMessage = ''.obs;

// Variables pour le calcul précis de la vitesse
  Position? _lastPosition;
  DateTime? _lastPositionTime;
  TravelMode _currentExpectedTravelMode = TravelMode.driving;

  // NOUVEAU: Timer pour forcer à zéro
  Timer? _stopTimer;

// Méthode manquante qui causait l'erreur
  void setExpectedTravelMode(dynamic mode) {
// Conversion dynamique si besoin
    if (mode is TravelMode) {
      _currentExpectedTravelMode = mode;
    } else if (mode == Constants.modeWalking) {
      _currentExpectedTravelMode = TravelMode.walking;
    } else if (mode == Constants.modeCycling) {
      _currentExpectedTravelMode = TravelMode.bicycling;
    } else {
      _currentExpectedTravelMode = TravelMode.driving;
    }
// Reset logique triche si nécessaire
    cheatStatus.value = CheatModeStatus.none;
    cheatWarningMessage.value = '';
  }

  void updateSpeed(Position position) {
    // Annuler le timer précédent
    _stopTimer?.cancel();

    double speedInMs = 0.0;

// 1. Priorité à la vitesse native du GPS (Doppler)
    if (position.speed > 0 && position.speed != 1.0) {
      speedInMs = position.speed;
    }
// 2. Fallback : Calcul manuel
    else if (_lastPosition != null && _lastPositionTime != null) {
      double distanceMeters = Geolocator.distanceBetween(
          _lastPosition!.latitude,
          _lastPosition!.longitude,
          position.latitude,
          position.longitude);
      int timeDiffSeconds =
          DateTime.now().difference(_lastPositionTime!).inSeconds;
      if (timeDiffSeconds > 0) {
        speedInMs = distanceMeters / timeDiffSeconds;
      }
    }

    _lastPosition = position;
    _lastPositionTime = DateTime.now();

    double speedInKmH = speedInMs * 3.6;
// Lissage à l'arrêt
    if (speedInKmH < 2.0) speedInKmH = 0.0;

    currentSpeed.value = speedInKmH;

    // NOUVEAU: Si aucune position n'arrive dans les 3 prochaines secondes, on force à 0
    _stopTimer = Timer(const Duration(seconds: 3), () {
      currentSpeed.value = 0.0;
    });
  }

  @override
  void onClose() {
    _stopTimer?.cancel();
    super.onClose();
  }
}

class HomeController extends GetxController with GetTickerProviderStateMixin {
  late MapLibreMapController mapController;
  final Completer<void> _mapReadyCompleter = Completer<void>();
  final Completer<void> _styleReadyCompleter = Completer<void>();
  final OsrmService _osrmService = OsrmService();
  StreamSubscription<Position>? _idlePositionStream;

  // --- VARIABLES UI & NAVIGATION ---
  var destination = "".obs;
  var distanceLeft = "".obs;
  var timeLeft = "".obs;
  var mapStatus = Constants.idle.obs;
  var gettingRoute = false.obs;

  var currentTravelMode = Rx<dynamic>(Constants.modeDriving);

  var isNavigatingToStore = false.obs;
  var validationCountdown = Rx<Duration?>(null);
  var showTransitOptions = false.obs;
  var transitRouteOptions = [].obs;
  var activeRouteEstimatedGain = 0.obs;
  var activeRouteRawDistanceMeters = 0.0.obs;
  var activeRouteRawDurationSeconds = 0.0.obs;
  var elevationGain = 0.0.obs;
  var arrived = false.obs;

  // Caméra et Animation
  var isNavigationCameraLocked = true.obs;
  var isAnimating = false.obs;

  // Données Route
  List<LatLng> polylineCoordinates = <LatLng>[].obs;

  List<LatLng> get polyline => polylineCoordinates;
  LatLng destinationCoordinates = const LatLng(0, 0);

  // Animation Fluide
  AnimationController? _movementController;
  double _lastBearing = 0;
  LatLng? _currentAnimatedPos;

  // 🚀 VARIABLES FILTRE PRÉDICTIF 🚀
  final KinematicFilter kinematicFilter = KinematicFilter();
  Ticker? _navigationTicker; // <--- REMPLACE Timer? _fluidTimer

  // ── VARIABLE POUR AFFICHER/MASQUER LES POINTS (AJOUT) ──
  var showDiagnosticPoints = true.obs;

  void toggleDiagnosticPoints() {
    showDiagnosticPoints.value = !showDiagnosticPoints.value;
    if (!showDiagnosticPoints.value) {
      _clearDiagnosticMarkers();
    } else {
      _updateDiagnosticMarkers();
    }
  }

  // IDs MapLibre
  static const String driverSourceId = "driver-source";
  static const String driverLayerId = "driver-layer";

  // Route Principale (Solide - Bus/Voiture)
  static const String routeSourceId = "route-source";
  static const String routeLayerId = "route-layer";

  // Route Marche (Pointillés - Rejoindre l'arrêt)
  static const String walkingRouteSourceId = "walking-route-source";
  static const String walkingRouteLayerId = "walking-route-layer";

  static const String destSourceId = "dest-source";
  static const String destLayerId = "dest-layer";

// NOUVEAU : IDs pour le rayon de l'arrêt de bus
  static const String radiusSourceId = "radius-source";
  static const String radiusLayerId = "radius-layer";

  // IDs pour le diagnostic kinématique (A, B, C, Raw)
  static const String diagPointASourceId = "diag-point-a-source";
  static const String diagPointALayerId = "diag-point-a-layer";
  static const String diagPointBSourceId = "diag-point-b-source";
  static const String diagPointBLayerId = "diag-point-b-layer";
  static const String diagPointCSourceId = "diag-point-c-source";
  static const String diagPointCLayerId = "diag-point-c-layer";
  static const String diagRawSourceId = "diag-raw-source";
  static const String diagRawLayerId = "diag-raw-layer";
  CameraPosition initialCameraPosition = const CameraPosition(
    target: LatLng(48.8566, 2.3522),
    zoom: 14.0,
  );

  void onMapCreated(MapLibreMapController controller) {
    mapController = controller;
    if (!_mapReadyCompleter.isCompleted) _mapReadyCompleter.complete();
  }

  // Méthode sécurisée pour définir les sources GeoJSON avec gestion des erreurs
  Future<void> _setSafeGeoJsonSource(
      String sourceId, Map<String, dynamic> geoJsonData) async {
    try {
      if (!_styleReadyCompleter.isCompleted) {
        debugPrint("⚠️ Style map pas encore prêt pour source: $sourceId");
        return;
      }
      await mapController.setGeoJsonSource(sourceId, geoJsonData);
    } on MissingPluginException catch (e) {
      debugPrint("❌ Plugin MapLibre manquant pour $sourceId: $e");
      // L'app continuera malgré l'absence du plugin
    } on FlutterError catch (e) {
      if (e.message?.contains("Overlay") == true) {
        debugPrint(
            "⚠️ Overlay non disponible lors de la mise à jour de $sourceId (ignoré)");
      } else {
        debugPrint("❌ Erreur Flutter pour $sourceId: $e");
      }
    } catch (e) {
      debugPrint("❌ Erreur inattendue setGeoJsonSource($sourceId): $e");
    }
  }
// Dans HomeController

  Future<void> defineHomeAddress(String address, LatLng coordinates) async {
    try {
      String userId = FirebaseAuth.instance.currentUser!.uid;

      // 1. Sauvegarde Firebase (Cloud) avec timestamp de modification
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'home_address_string': address,
        'home_address_coordinates': {
          'latitude': coordinates.latitude,
          'longitude': coordinates.longitude
        },
        'last_address_update_time':
            FieldValue.serverTimestamp(), // Restriction 1 fois/an
        'updated_at': FieldValue.serverTimestamp(),
      });

      // 2. Sauvegarde Locale pour le Background Service (CRUCIAL)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('user_home_lat', coordinates.latitude);
      await prefs.setDouble('user_home_lng', coordinates.longitude);

      // Mettre à jour le profil localement si nécessaire
      Get.snackbar("Succès", "Domicile défini !",
          backgroundColor: Colors.green, colorText: Colors.white);
    } catch (e) {
      Get.snackbar("Erreur", "Impossible de sauvegarder le domicile: $e",
          backgroundColor: Colors.red, colorText: Colors.white);
    }
  }

  void onUserInteraction() {
    // Si on est en mode navigation, on désactive le verrouillage caméra
    if (mapStatus.value == Constants.onDestination) {
      if (isNavigationCameraLocked.value) {
        isNavigationCameraLocked.value = false;
        // Petit feedback haptique ou visuel optionnel ici
        debugPrint("Navigation: Caméra déverrouillée manuellement");
      }
    }
  }

  Future<void> _fetchElevationGain(List<LatLng> points) async {
    if (points.isEmpty) return;

    try {
      // Échantillonnage agressif de la route (10 points pour ne pas dépasser les limites d'URL)
      int sampleSize = 10;
      List<LatLng> sampledPoints = [];

      if (points.length <= sampleSize) {
        sampledPoints = points;
      } else {
        int step = (points.length / sampleSize).ceil();
        for (int i = 0; i < points.length; i += step) {
          sampledPoints.add(points[i]);
        }
        if (sampledPoints.last != points.last) {
          sampledPoints.add(points.last);
        }
      }

      // Open-Meteo attend des latitudes et longitudes séparées par des virgules
      String lats =
          sampledPoints.map((p) => p.latitude.toStringAsFixed(5)).join(",");
      String lons =
          sampledPoints.map((p) => p.longitude.toStringAsFixed(5)).join(",");

      // Utilisation de l'API publique Open-Meteo (Gratuite, sans clé API)
      String url =
          "https://api.open-meteo.com/v1/elevation?latitude=$lats&longitude=$lons";

      var response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        if (data['elevation'] != null) {
          List<dynamic> elevations = data['elevation'];
          double totalAscent = 0.0;

          // Calcul du dénivelé positif cumulé
          for (int i = 0; i < elevations.length - 1; i++) {
            if (elevations[i] == null || elevations[i + 1] == null) continue;

            double elev1 = (elevations[i] as num).toDouble();
            double elev2 = (elevations[i + 1] as num).toDouble();

            double diff = elev2 - elev1;
            if (diff > 0) {
              totalAscent += diff;
            }
          }

          elevationGain.value = totalAscent;
          debugPrint(
              "Dénivelé Open-Meteo calculé : ${totalAscent.toStringAsFixed(1)} m");
        }
      } else {
        debugPrint("Erreur Open-Meteo Elevation: ${response.body}");
      }
    } catch (e) {
      debugPrint("Exception calcul dénivelé Open-Meteo: $e");
    }
  }

// --- NOUVELLE MÉTHODE : Mise à jour en temps réel ---
  void updateRemainingDistanceAndTime(LatLng currentPos) {
    if (polylineCoordinates.isEmpty) return;

    int closestIndex = 0;
    double minDistance = double.infinity;

    // 1. Trouver le point le plus proche sur l'itinéraire
    for (int i = 0; i < polylineCoordinates.length; i++) {
      double dist = Geolocator.distanceBetween(
          currentPos.latitude,
          currentPos.longitude,
          polylineCoordinates[i].latitude,
          polylineCoordinates[i].longitude);
      if (dist < minDistance) {
        minDistance = dist;
        closestIndex = i;
      }
    }

    // 2. Additionner la distance de tous les points restants jusqu'à l'arrivée
    double remainingDistanceMeters = 0;
    for (int i = closestIndex; i < polylineCoordinates.length - 1; i++) {
      remainingDistanceMeters += Geolocator.distanceBetween(
          polylineCoordinates[i].latitude,
          polylineCoordinates[i].longitude,
          polylineCoordinates[i + 1].latitude,
          polylineCoordinates[i + 1].longitude);
    }

    // 3. Mettre à jour le texte de la distance (en m ou km)
    if (remainingDistanceMeters >= 1000) {
      distanceLeft.value =
          "${(remainingDistanceMeters / 1000).toStringAsFixed(1)} km";
    } else {
      distanceLeft.value = "${remainingDistanceMeters.round()} m";
    }

    // 4. Estimer le temps restant selon le mode de transport
    double speedKmh = 5.0; // Marche par défaut
    String modeStr = currentTravelMode.value.toString().toLowerCase();

    if (modeStr.contains('driving'))
      speedKmh = 40.0;
    else if (modeStr.contains('bicycling') || modeStr.contains('cycling'))
      speedKmh = 15.0;
    else if (modeStr.contains('transit'))
      speedKmh = 30.0; // Vitesse moyenne bus/métro

    double speedMps = speedKmh / 3.6;
    double remainingSeconds = remainingDistanceMeters / speedMps;

    // 5. Mettre à jour le texte du temps
    int mins = (remainingSeconds / 60).round();
    int hours = mins ~/ 60;
    timeLeft.value = hours > 0 ? "${hours}h ${mins % 60}min" : "$mins min";
  }

  void onStyleLoaded() async {
    try {
      await _addImageFromAsset("car_icon", Constants.driverCarImage);
      await _addImageFromAsset("marker_icon", "assets/images/marker.png");

      // Sources
      try {
        await mapController.addSource(
            driverSourceId,
            const GeojsonSourceProperties(
                data: {"type": "FeatureCollection", "features": []}));
      } catch (e) {
        debugPrint("⚠️ Source $driverSourceId: $e");
      }

      try {
        await mapController.addSource(
            routeSourceId,
            const GeojsonSourceProperties(
                data: {"type": "FeatureCollection", "features": []}));
      } catch (e) {
        debugPrint("⚠️ Source $routeSourceId: $e");
      }

      try {
        await mapController.addSource(
            walkingRouteSourceId,
            const GeojsonSourceProperties(
                data: {"type": "FeatureCollection", "features": []}));
      } catch (e) {
        debugPrint("⚠️ Source $walkingRouteSourceId: $e");
      }

      try {
        await mapController.addSource(
            destSourceId,
            const GeojsonSourceProperties(
                data: {"type": "FeatureCollection", "features": []}));
      } catch (e) {
        debugPrint("⚠️ Source $destSourceId: $e");
      }

      // AJOUT SOURCE RAYON
      try {
        await mapController.addSource(
            radiusSourceId,
            const GeojsonSourceProperties(
                data: {"type": "FeatureCollection", "features": []}));
      } catch (e) {
        debugPrint("⚠️ Source $radiusSourceId: $e");
      }

      // Layer Route Bus (Ligne pleine)
      try {
        await mapController.addLayer(
            routeSourceId,
            routeLayerId,
            const LineLayerProperties(
                lineColor: ['get', 'color'],
                lineWidth: 6.0,
                lineOpacity: 0.9,
                lineCap: "round",
                lineJoin: "round"));
      } catch (e) {
        debugPrint("⚠️ Layer $routeLayerId: $e");
      }

      // CORRECTION LAYER MARCHE (Pointillés Orange bien visibles)
      try {
        await mapController.addLayer(
            walkingRouteSourceId,
            walkingRouteLayerId,
            const LineLayerProperties(
                lineColor: "#FF9800", // Orange
                lineWidth: 5.0,
                lineOpacity: 1.0,
                lineDasharray: [2, 2] // Pointillés nets
                ));
      } catch (e) {
        debugPrint("⚠️ Layer $walkingRouteLayerId: $e");
      }

      // AJOUT LAYER RAYON (Cercle Rouge semi-transparent)
      try {
        await mapController.addLayer(
            radiusSourceId,
            radiusLayerId,
            const FillLayerProperties(
                fillColor: "#FF0000",
                fillOpacity: 0.25, // Transparence pour voir la carte dessous
                fillOutlineColor: "#FF0000"));
      } catch (e) {
        debugPrint("⚠️ Layer $radiusLayerId: $e");
      }

      // Layers Icones
      try {
        await mapController.addLayer(
            destSourceId,
            destLayerId,
            const SymbolLayerProperties(
                iconImage: "marker_icon",
                iconSize: 1.0,
                iconAnchor: "bottom",
                iconAllowOverlap: true));
      } catch (e) {
        debugPrint("⚠️ Layer $destLayerId: $e");
      }

      try {
        await mapController.addLayer(
            driverSourceId,
            driverLayerId,
            const SymbolLayerProperties(
                iconImage: "car_icon",
                iconSize: 0.5,
                iconRotate: ['get', 'bearing'],
                iconRotationAlignment: 'map',
                iconPitchAlignment: 'map',
                iconAllowOverlap: true,
                iconIgnorePlacement: true));
      } catch (e) {
        debugPrint("⚠️ Layer $driverLayerId: $e");
      }

      // ── POINTS DE DIAGNOSTIC ──
      // Point A (ROUGE - position GPS précédente)
      try {
        await mapController.addSource(
            diagPointASourceId,
            const GeojsonSourceProperties(
                data: {"type": "FeatureCollection", "features": []}));
        await mapController.addLayer(
            diagPointASourceId,
            diagPointALayerId,
            const CircleLayerProperties(
              circleColor: "#FF0000",
              circleRadius: 7.0,
              circleStrokeWidth: 2.0,
              circleStrokeColor: "#FFFFFF",
              circleOpacity: 0.9,
            ));
      } catch (e) {
        debugPrint("⚠️ Diag Point A: $e");
      }

      // Point B (BLEU - position lissée/snappée actuelle)
      try {
        await mapController.addSource(
            diagPointBSourceId,
            const GeojsonSourceProperties(
                data: {"type": "FeatureCollection", "features": []}));
        await mapController.addLayer(
            diagPointBSourceId,
            diagPointBLayerId,
            const CircleLayerProperties(
              circleColor: "#2196F3",
              circleRadius: 7.0,
              circleStrokeWidth: 2.0,
              circleStrokeColor: "#FFFFFF",
              circleOpacity: 0.9,
            ));
      } catch (e) {
        debugPrint("⚠️ Diag Point B: $e");
      }

      // Point C (VERT - position future prédite)
      try {
        await mapController.addSource(
            diagPointCSourceId,
            const GeojsonSourceProperties(
                data: {"type": "FeatureCollection", "features": []}));
        await mapController.addLayer(
            diagPointCSourceId,
            diagPointCLayerId,
            const CircleLayerProperties(
              circleColor: "#4CAF50",
              circleRadius: 7.0,
              circleStrokeWidth: 2.0,
              circleStrokeColor: "#FFFFFF",
              circleOpacity: 0.9,
            ));
      } catch (e) {
        debugPrint("⚠️ Diag Point C: $e");
      }

      // Position GPS brute (JAUNE)
      try {
        await mapController.addSource(
            diagRawSourceId,
            const GeojsonSourceProperties(
                data: {"type": "FeatureCollection", "features": []}));
        await mapController.addLayer(
            diagRawSourceId,
            diagRawLayerId,
            const CircleLayerProperties(
              circleColor: "#FFEB3B",
              circleRadius: 6.0,
              circleStrokeWidth: 2.0,
              circleStrokeColor: "#000000",
              circleOpacity: 0.85,
            ));
      } catch (e) {
        debugPrint("⚠️ Diag Raw: $e");
      }

      startIdleTracking();
      _checkPermissionsAndInitLocation();
      if (!_styleReadyCompleter.isCompleted) _styleReadyCompleter.complete();
    } catch (e) {
      debugPrint("❌ Erreur onStyleLoaded: $e");
      if (!_styleReadyCompleter.isCompleted)
        _styleReadyCompleter.complete(); // Complète même en erreur
    }
  }

  void _safeSnackbar(
    String title,
    String message, {
    Color? backgroundColor,
    Color? colorText,
    Duration duration = const Duration(seconds: 3),
    SnackPosition snackPosition = SnackPosition.BOTTOM,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        if (Get.overlayContext != null) {
          Get.snackbar(
            title,
            message,
            backgroundColor: backgroundColor,
            colorText: colorText,
            duration: duration,
            snackPosition: snackPosition,
          );
        } else {
          debugPrint(
              '⚠️ Snackbar skipped (no overlay context) : $title - $message');
        }
      } catch (e, st) {
        debugPrint('⚠️ Snackbar error: $e\n$st');
      }
    });
  }

  void selectAndDrawTransitRoute(int index) async {
    if (index >= transitRouteOptions.length) return;

    gettingRoute.value = true;
    polylineCoordinates.clear();

    try {
      final Map<String, dynamic> route =
          Map<String, dynamic>.from(transitRouteOptions[index]);
      if (route['legs'] == null || (route['legs'] as List).isEmpty) {
        gettingRoute.value = false;
        return;
      }
      final Map<String, dynamic> leg =
          Map<String, dynamic>.from(route['legs'][0]);
      final List<dynamic> steps = leg['steps'] as List<dynamic>;

      LatLng? firstTransitStopLocation;
      DateTime? transitDepartureTime;
      bool transitStopFound = false;

      List<Map<String, dynamic>> busStops = [];
      String? lastTransitLine;

      List<dynamic> solidFeatures = [];
      List<dynamic> dottedFeatures = [];

      for (int stepIndex = 0; stepIndex < steps.length; stepIndex++) {
        var step = steps[stepIndex] as Map<String, dynamic>;

        List<List<double>> stepCoords = [];

        // CORRECTION 1: Sécurité sur la présence de la polyline
        if (step['polyline'] != null && step['polyline']['points'] != null) {
          String encodedPoly = step['polyline']['points'];
          List<gmaps_utils.Point> points =
              gmaps_utils.PolyUtils.decode(encodedPoly);

          if (points.isNotEmpty) {
            stepCoords =
                points.map((p) => [p.y.toDouble(), p.x.toDouble()]).toList();
            for (var p in points) {
              polylineCoordinates.add(LatLng(p.x.toDouble(), p.y.toDouble()));
            }
          }
        }

        // CORRECTION 2: Fallback si pas de polyline (ex: correspondance immédiate)
        if (stepCoords.isEmpty &&
            step['start_location'] != null &&
            step['end_location'] != null) {
          double sLat = (step['start_location']['lat'] as num).toDouble();
          double sLng = (step['start_location']['lng'] as num).toDouble();
          double eLat = (step['end_location']['lat'] as num).toDouble();
          double eLng = (step['end_location']['lng'] as num).toDouble();
          stepCoords = [
            [sLng, sLat],
            [eLng, eLat]
          ];
          polylineCoordinates.add(LatLng(sLat, sLng));
          polylineCoordinates.add(LatLng(eLat, eLng));
        }

        // Si l'étape n'a vraiment aucune coordonnée, on passe à la suivante
        if (stepCoords.isEmpty) continue;

        String mode = step['travel_mode'] ?? 'WALKING';

        if (mode == 'WALKING') {
          dottedFeatures.add({
            "type": "Feature",
            "geometry": {"type": "LineString", "coordinates": stepCoords},
            "properties": <String, dynamic>{}
          });
        } else if (mode == 'TRANSIT') {
          if (!transitStopFound) {
            double lat = (step['start_location']['lat'] as num).toDouble();
            double lng = (step['start_location']['lng'] as num).toDouble();
            firstTransitStopLocation = LatLng(lat, lng);

            if (step['transit_details'] != null &&
                step['transit_details']['departure_time'] != null) {
              var val = step['transit_details']['departure_time']['value'];
              if (val != null) {
                transitDepartureTime = DateTime.fromMillisecondsSinceEpoch(
                    (val as num).toInt() * 1000);
              }
            }
            transitStopFound = true;

            _safeSnackbar(
              "🚌 Embarquement",
              "Arrêt de bus atteint. En attente du départ...",
              backgroundColor: Colors.blue.shade700,
              duration: const Duration(seconds: 3),
              snackPosition: SnackPosition.BOTTOM,
            );

            if (Get.isRegistered<NavigationController>()) {
              Get.find<NavigationController>().currentInstructionText.value =
                  "🚌 Arrêt de bus atteint. En attente du départ...";
            }
          }

          String? currentLine =
              step['transit_details']?['line']?['short_name'] as String?;

          if (currentLine != null &&
              lastTransitLine != null &&
              lastTransitLine != currentLine) {
            double lat = (step['start_location']['lat'] as num).toDouble();
            double lng = (step['start_location']['lng'] as num).toDouble();
            busStops.add({
              'location': LatLng(lat, lng),
              'type': 'correspondence',
              'line': currentLine,
            });

            _safeSnackbar(
              "🔄 Correspondance",
              "Ligne $currentLine. Changez de bus ici.",
              backgroundColor: Colors.orange.shade700,
              duration: const Duration(seconds: 4),
              snackPosition: SnackPosition.BOTTOM,
            );

            if (Get.isRegistered<NavigationController>()) {
              Get.find<NavigationController>().currentInstructionText.value =
                  "🔄 Correspondance: Prenez la ligne $currentLine ici.";
            }
          }
          lastTransitLine = currentLine;

          if (stepIndex == 0 ||
              (stepIndex > 0 &&
                  steps[stepIndex - 1]['travel_mode'] != 'TRANSIT')) {
            double lat = (step['start_location']['lat'] as num).toDouble();
            double lng = (step['start_location']['lng'] as num).toDouble();
            busStops.add({
              'location': LatLng(lat, lng),
              'type': 'departure',
              'line': currentLine,
            });
          }

          if (stepIndex == steps.length - 1 ||
              (stepIndex < steps.length - 1 &&
                  steps[stepIndex + 1]['travel_mode'] != 'TRANSIT')) {
            double lat = (step['end_location']['lat'] as num).toDouble();
            double lng = (step['end_location']['lng'] as num).toDouble();
            busStops.add({
              'location': LatLng(lat, lng),
              'type': 'arrival',
              'line': currentLine,
            });

            _safeSnackbar(
              "🚌 Descente",
              "Arrêt atteint. Descendez du bus ici.",
              backgroundColor: Colors.green.shade700,
              duration: const Duration(seconds: 3),
              snackPosition: SnackPosition.BOTTOM,
            );
          }

          String segmentColor = "#3d5afe";
          if (step['transit_details']?['line']?['color'] != null) {
            segmentColor = step['transit_details']['line']['color'] as String;
            if (!segmentColor.startsWith('#')) {
              segmentColor = "#$segmentColor";
            }
          }

          solidFeatures.add({
            "type": "Feature",
            "geometry": {"type": "LineString", "coordinates": stepCoords},
            "properties": {"color": segmentColor}
          });
        }
      }

      await _setSafeGeoJsonSource(routeSourceId,
          {"type": "FeatureCollection", "features": solidFeatures});

      await _setSafeGeoJsonSource(walkingRouteSourceId,
          {"type": "FeatureCollection", "features": dottedFeatures});

      List<dynamic> allRadiusFeatures = [];

      for (var stop in busStops) {
        if (stop['type'] != 'departure') {
          final circleCoords =
              _getCircleCoordinates(stop['location'] as LatLng, 10);
          allRadiusFeatures.add({
            "type": "Feature",
            "geometry": {
              "type": "Polygon",
              "coordinates": [circleCoords]
            },
            "properties": <String, dynamic>{}
          });
        }
      }

      if (firstTransitStopLocation != null) {
        final firstCircleCoords =
            _getCircleCoordinates(firstTransitStopLocation, 10);
        allRadiusFeatures.add({
          "type": "Feature",
          "geometry": {
            "type": "Polygon",
            "coordinates": [firstCircleCoords]
          },
          "properties": <String, dynamic>{}
        });
      }

      await _setSafeGeoJsonSource(radiusSourceId,
          {"type": "FeatureCollection", "features": allRadiusFeatures});

      distanceLeft.value = leg['distance']['text'] as String;
      timeLeft.value = leg['duration']['text'] as String;

      // CORRECTION 3: Enregistrer les distances brutes qui étaient oubliées pour le transit
      if (leg['distance'] != null && leg['distance']['value'] != null) {
        activeRouteRawDistanceMeters.value =
            (leg['distance']['value'] as num).toDouble();
      }
      if (leg['duration'] != null && leg['duration']['value'] != null) {
        activeRouteRawDurationSeconds.value =
            (leg['duration']['value'] as num).toDouble();
      }

      mapStatus.value = Constants.route;
      showTransitOptions.value = false;

      if (dottedFeatures.isNotEmpty) {
        final firstCoord =
            dottedFeatures[0]['geometry']['coordinates'][0] as List;
        moveMapCamera(
          LatLng((firstCoord[1] as num).toDouble(),
              (firstCoord[0] as num).toDouble()),
          zoom: 17,
        );
      } else if (solidFeatures.isNotEmpty) {
        final firstCoord =
            solidFeatures[0]['geometry']['coordinates'][0] as List;
        moveMapCamera(
          LatLng((firstCoord[1] as num).toDouble(),
              (firstCoord[0] as num).toDouble()),
          zoom: 16,
        );
      }

      if (Get.isRegistered<NavigationController>()) {
        final nav = Get.find<NavigationController>();
        nav.setRouteInstructions(steps);
        if (transitStopFound && firstTransitStopLocation != null) {
          nav.setTargetTransitStop(
              firstTransitStopLocation, transitDepartureTime);
        } else {
          nav.clearTargetTransitStop();
        }
      }
    } catch (e, st) {
      debugPrint("Erreur dessin route transit: $e\n$st");
    } finally {
      gettingRoute.value = false;
    }
  }

  List<List<double>> _getCircleCoordinates(LatLng center, double radiusMeters) {
    int points = 64;
    List<List<double>> coordinates = [];
    double km = radiusMeters / 1000.0;

    double lat = center.latitude * (math.pi / 180);
    double lng = center.longitude * (math.pi / 180);
    double d_rad = km / 6378.137;

    for (int i = 0; i < points; i++) {
      double theta = (math.pi * 2 * i) / points;
      double lat_rad = math.asin(math.sin(lat) * math.cos(d_rad) +
          math.cos(lat) * math.sin(d_rad) * math.cos(theta));
      double lng_rad = lng +
          math.atan2(math.sin(theta) * math.sin(d_rad) * math.cos(lat),
              math.cos(d_rad) - math.sin(lat) * math.sin(lat_rad));
      coordinates.add([lng_rad * (180 / math.pi), lat_rad * (180 / math.pi)]);
    }
    coordinates.add(coordinates[0]); // Fermer la boucle
    return coordinates;
  }

  // (Optionnel) Vous pouvez garder l'ancienne fonction drawCircleOnMap pour les défis "Rester sur place"
  Future<void> drawCircleOnMap(LatLng center, double radiusMeters) async {
    if (!_styleReadyCompleter.isCompleted) return;
    final coordinates = _getCircleCoordinates(center, radiusMeters);

    final feature = <String, dynamic>{
      "type": "FeatureCollection",
      "features": [
        <String, dynamic>{
          "type": "Feature",
          "geometry": <String, dynamic>{
            "type": "Polygon",
            "coordinates": [coordinates]
          },
          "properties": <String, dynamic>{}
        }
      ]
    };

    await _setSafeGeoJsonSource(radiusSourceId, feature);
  }

  // --- LOGIQUE ANIMATION FLUIDE ---
  void moveDriverFluidly(
      LatLng from, LatLng to, double targetBearing, Duration duration) {
    _movementController?.dispose();
    _movementController = AnimationController(duration: duration, vsync: this);

    double startBearing = _lastBearing;
    double diff = targetBearing - startBearing;
    if (diff > 180) targetBearing -= 360;
    if (diff < -180) targetBearing += 360;

    Animation<double> anim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _movementController!, curve: Curves.linear));

    anim.addListener(() {
      double v = anim.value;
      double lat = v * to.latitude + (1 - v) * from.latitude;
      double lng = v * to.longitude + (1 - v) * from.longitude;
      double bearing = startBearing + v * (targetBearing - startBearing);

      _currentAnimatedPos = LatLng(lat, lng);
      _lastBearing = bearing;

      _updateDriverMarker(LatLng(lat, lng), bearing);

      if (isNavigationCameraLocked.value && !isAnimating.value) {
        mapController.moveCamera(CameraUpdate.newCameraPosition(CameraPosition(
            target: LatLng(lat, lng), zoom: 18.0, bearing: bearing, tilt: 50)));
      }
    });
    _movementController!.forward();
  }

  // 🚀 LANCE LA BOUCLE D'ANIMATION (Synchronisée avec l'écran via VSync)
  void startFluidNavigation() {
    _navigationTicker?.dispose();

    _navigationTicker = createTicker((Duration elapsed) {
      if (mapStatus.value != Constants.onDestination) {
        _navigationTicker?.stop();
        return;
      }

      // 1. Le filtre devine l'avancée de la voiture (inclut Mode Tunnel & Buffer adaptatif)
      LatLng? predictedPos =
          kinematicFilter.predictNextPosition(polylineCoordinates);

      if (predictedPos != null && kinematicFilter.lastRealPos != null) {
        // 🔋 ECONOMIE D'ÉNERGIE : Si le véhicule est à l'arrêt, on ne recalcule pas le rendu
        if (kinematicFilter.calculatedSpeedMps < 0.1 &&
            _currentAnimatedPos != null) {
          double drift = Geolocator.distanceBetween(
              predictedPos.latitude,
              predictedPos.longitude,
              _currentAnimatedPos!.latitude,
              _currentAnimatedPos!.longitude);
          if (drift < 0.5)
            return; // On saute la frame, on ne consomme pas de CPU
        }

        // 2. MAGIE DES VIRAGES : Aimant intelligent avec pénalité d'angle progressive
        LatLng snappedPos =
            snapToRoute(predictedPos, kinematicFilter.lastRealPos!.heading);

        // 🚀 2.5 CORRECTION ANTI-RETARD, FREINAGE ET RATTRAPAGE
        final lastGps = kinematicFilter.lastRealPos;
        if (lastGps != null) {
          final now = DateTime.now();

          // Calcul de la latence exacte en millisecondes
          int latencyMs = now.difference(lastGps.timestamp).inMilliseconds;

          // Mise à jour de l'UI de diagnostic
          if (Get.isRegistered<NavigationController>()) {
            Get.find<NavigationController>().gpsLatencyMs.value = latencyMs;
          }

          // Borne de sécurité (entre 0.0s et 1.0s max)
          double exactLatencySeconds = (latencyMs / 1000.0).clamp(0.0, 1.0);
          double currentSpeedMps = kinematicFilter.calculatedSpeedMps;

          if (_currentAnimatedPos != null) {
            // Calcul de la distance entre la flèche animée et la vraie position GPS
            double driftDistance = Geolocator.distanceBetween(
                _currentAnimatedPos!.latitude,
                _currentAnimatedPos!.longitude,
                lastGps.latitude,
                lastGps.longitude);

            final snappedGpsPos = snapToRoute(
                LatLng(lastGps.latitude, lastGps.longitude), lastGps.heading);

            // RÈGLE 3 : Rupture (Snap)
            if (driftDistance > 20.0) {
              snappedPos = snappedGpsPos;
            }
            // RÈGLE 1 & 2 : Freinage proportionnel, correction avant/arrière et rattrapage adaptatif
            else if (driftDistance > 2.0) {
              final previousSpeedMps = kinematicFilter.previousCalculatedSpeedMps;
              final brakingRatio = previousSpeedMps > 0.4
                  ? ((previousSpeedMps - currentSpeedMps) / previousSpeedMps)
                      .clamp(0.0, 1.0)
                  : (currentSpeedMps < 0.5 ? 1.0 : 0.0);

              final signedDrift = _signedDistanceAlongHeadingMeters(
                  from: snappedGpsPos,
                  to: _currentAnimatedPos!,
                  headingDegrees: lastGps.heading);
              final arrowAhead = signedDrift > 0;

              double correctionFactor = arrowAhead
                  ? (0.18 + (brakingRatio * 0.62))
                  : (0.10 + (brakingRatio * 0.35));

              if (currentSpeedMps < 0.8) {
                correctionFactor += 0.12;
              }

              double estimatedCatchSeconds = driftDistance /
                  math.max(currentSpeedMps * math.max(correctionFactor, 0.15), 0.5);

              if (estimatedCatchSeconds > 4.0 || driftDistance > 12.0) {
                correctionFactor = math.max(correctionFactor, 0.60);
              }

              correctionFactor = correctionFactor.clamp(0.10, 0.85);

              if (estimatedCatchSeconds > 8.0 || driftDistance > 18.0) {
                snappedPos = snappedGpsPos;
              } else {
                LatLng correctedPos = LatLng(
                  _currentAnimatedPos!.latitude +
                      (snappedGpsPos.latitude - _currentAnimatedPos!.latitude) *
                          correctionFactor,
                  _currentAnimatedPos!.longitude +
                      (snappedGpsPos.longitude - _currentAnimatedPos!.longitude) *
                          correctionFactor,
                );
                snappedPos = snapToRoute(correctedPos, lastGps.heading);

                if (!arrowAhead &&
                    currentSpeedMps > 1.0 &&
                    exactLatencySeconds > 0.02) {
                  double latencyScale = (1.0 - (brakingRatio * 0.5)).clamp(0.4, 1.0);
                  double advanceMeters =
                      (currentSpeedMps * latencyScale) * exactLatencySeconds;
                  double headingRad = lastGps.heading * (math.pi / 180.0);

                  double deltaLat =
                      (advanceMeters * math.cos(headingRad)) / 111111.0;
                  double deltaLng = (advanceMeters * math.sin(headingRad)) /
                      (111111.0 *
                          math.cos(snappedPos.latitude * (math.pi / 180.0)));

                  snappedPos = LatLng(
                      snappedPos.latitude + deltaLat,
                      snappedPos.longitude + deltaLng);
                }
              }
            }
            // Cas nominal : compensation simple de latence
            else if (currentSpeedMps > 1.0 && exactLatencySeconds > 0.02) {
              double advanceMeters = currentSpeedMps * exactLatencySeconds;
              double headingRad = lastGps.heading * (math.pi / 180.0);

              double deltaLat = (advanceMeters * math.cos(headingRad)) / 111111.0;
              double deltaLng = (advanceMeters * math.sin(headingRad)) /
                  (111111.0 * math.cos(snappedPos.latitude * (math.pi / 180.0)));

              snappedPos = LatLng(
                  snappedPos.latitude + deltaLat, snappedPos.longitude + deltaLng);
            }
          } else {
            // Fallback de sécurité si _currentAnimatedPos n'est pas encore initialisé
            if (currentSpeedMps > 1.0 && exactLatencySeconds > 0.02) {
              double advanceMeters = currentSpeedMps * exactLatencySeconds;
              double headingRad = lastGps.heading * (math.pi / 180.0);

              double deltaLat = (advanceMeters * math.cos(headingRad)) / 111111.0;
              double deltaLng = (advanceMeters * math.sin(headingRad)) /
                  (111111.0 * math.cos(snappedPos.latitude * (math.pi / 180.0)));

              snappedPos = LatLng(
                  snappedPos.latitude + deltaLat, snappedPos.longitude + deltaLng);
            }
          }
        }

        // 🔄 3. LISSAGE ANGULAIRE (Rotation Fluide de la Caméra)
        double targetBearing = kinematicFilter.lastRealPos!.heading;
        double diff = targetBearing - _lastBearing;
        if (diff > 180) diff -= 360;
        if (diff < -180) diff += 360;
        _lastBearing += diff * 0.05;
        if (_lastBearing < 0) _lastBearing += 360;
        if (_lastBearing >= 360) _lastBearing -= 360;

        // 4. Mise à jour de l'UI à l'écran (avec l'angle lissé)
        _updateDriverMarker(snappedPos, _lastBearing);
        _updateDiagnosticMarkers(); // ✅ Redessiner les points de diagnostic à chaque frame

        // 5. On enregistre pour le recentrage
        _currentAnimatedPos = snappedPos;

        // 6. On fait avancer la caméra de façon ultra-fluide (60/120 FPS)
        if (isNavigationCameraLocked.value && !isAnimating.value) {
          mapController.moveCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                  target: snappedPos,
                  zoom: 18.0,
                  bearing: _lastBearing,
                  tilt: 50)));
        }
      }
    });

    _navigationTicker!.start();
  }

  void stopFluidNavigation() {
    _navigationTicker?.stop();
    _navigationTicker?.dispose();
    _navigationTicker = null;
    kinematicFilter.reset();
    _clearDiagnosticMarkers(); // 🔍 Effacer les points de diagnostic
  }

  Future<void> _updateDriverMarker(LatLng position, double heading) async {
    final feature = {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [position.longitude, position.latitude]
          },
          "properties": {"bearing": heading}
        }
      ]
    };
    await _setSafeGeoJsonSource(driverSourceId, feature);
  }

  /// Met à jour les 4 points de diagnostic kinématique sur la carte
  Future<void> _updateDiagnosticMarkers() async {
    // Si l'affichage est désactivé, on ne dessine rien !
    if (!showDiagnosticPoints.value) return;

    final kf = kinematicFilter;

    // Point A - ROUGE
    if (kf.pointA != null) {
      await _setSafeGeoJsonSource(diagPointASourceId, {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "Point",
              "coordinates": [kf.pointA!.longitude, kf.pointA!.latitude]
            },
            "properties": {}
          }
        ]
      });
    }

    // Point B - BLEU
    if (kf.pointB != null) {
      await _setSafeGeoJsonSource(diagPointBSourceId, {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "Point",
              "coordinates": [kf.pointB!.longitude, kf.pointB!.latitude]
            },
            "properties": {}
          }
        ]
      });
    }

    // Point C - VERT
    if (kf.pointC != null) {
      await _setSafeGeoJsonSource(diagPointCSourceId, {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "Point",
              "coordinates": [kf.pointC!.longitude, kf.pointC!.latitude]
            },
            "properties": {}
          }
        ]
      });
    }

    // Position GPS brute - JAUNE
    if (kf.rawGpsPos != null) {
      await _setSafeGeoJsonSource(diagRawSourceId, {
        "type": "FeatureCollection",
        "features": [
          {
            "type": "Feature",
            "geometry": {
              "type": "Point",
              "coordinates": [kf.rawGpsPos!.longitude, kf.rawGpsPos!.latitude]
            },
            "properties": {}
          }
        ]
      });
    }
  }

  /// Efface tous les points de diagnostic
  Future<void> _clearDiagnosticMarkers() async {
    final empty = {"type": "FeatureCollection", "features": []};
    await _setSafeGeoJsonSource(diagPointASourceId, empty);
    await _setSafeGeoJsonSource(diagPointBSourceId, empty);
    await _setSafeGeoJsonSource(diagPointCSourceId, empty);
    await _setSafeGeoJsonSource(diagRawSourceId, empty);
  }

  // --- LOGIQUE SNAPPING ET PROJECTION EXACTE ---

  _RouteSnapResult _getNearestRoutePoint(LatLng gpsPos, [double? headingGps]) {
    if (polylineCoordinates.isEmpty) return _RouteSnapResult(gpsPos, 0.0);

    LatLng closest = polylineCoordinates.first;
    double minDist = double.infinity;

    // Optimisation : Fenêtre de recherche basée sur l'index de route connu (anti-sauts sur voies parallèles)
    int startIndex = 0;
    int endIndex = polylineCoordinates.length - 1;
    if (kinematicFilter.lastRouteIndex != -1) {
      startIndex = kinematicFilter.lastRouteIndex;
      endIndex = math.min(startIndex + 5, polylineCoordinates.length - 1);
    }

    int bestIndex = startIndex;

    for (int i = startIndex; i < endIndex; i++) {
      LatLng p1 = polylineCoordinates[i];
      LatLng p2 = polylineCoordinates[i + 1];
      LatLng proj = _projectCorrected(gpsPos, p1, p2);

      double d = Geolocator.distanceBetween(
          gpsPos.latitude, gpsPos.longitude, proj.latitude, proj.longitude);

      // Pénalité Continue d'Angle (Empêche l'aimant de coller sur des routes perpendiculaires)
      if (headingGps != null) {
        double segmentBearing = Geolocator.bearingBetween(
            p1.latitude, p1.longitude, p2.latitude, p2.longitude);
        if (segmentBearing < 0) segmentBearing += 360;

        double diff = (segmentBearing - headingGps).abs();
        if (diff > 180) diff = 360 - diff;

        // Courbe Cosinus fluide pour la pénalité (0m si aligné, 100m si contre-sens)
        double diffRad = diff * (math.pi / 180.0);
        double penalty = 100.0 * ((1.0 - math.cos(diffRad)) / 2.0);
        d += penalty;
      }

      if (d < minDist) {
        minDist = d;
        closest = proj;
        bestIndex = i;
      }
    }

    kinematicFilter.lastRouteIndex = bestIndex;

    // Distance pure sans pénalité pour les calculs de déviation réels
    double pureDist = Geolocator.distanceBetween(
        gpsPos.latitude, gpsPos.longitude, closest.latitude, closest.longitude);

    return _RouteSnapResult(closest, pureDist);
  }

  LatLng snapToRoute(LatLng gpsPos, [double? headingGps]) {
    final snap = _getNearestRoutePoint(gpsPos, headingGps);
    return snap.distance < 45.0 ? snap.point : gpsPos; // Seuil de snap à 45m
  }

  double _signedDistanceAlongHeadingMeters({
    required LatLng from,
    required LatLng to,
    required double headingDegrees,
  }) {
    final midLatRad = ((from.latitude + to.latitude) / 2.0) * (math.pi / 180.0);
    final metersPerDegreeLat = 111111.0;
    final metersPerDegreeLng = 111111.0 * math.cos(midLatRad);

    final dx = (to.longitude - from.longitude) * metersPerDegreeLng;
    final dy = (to.latitude - from.latitude) * metersPerDegreeLat;

    final headingRad = headingDegrees * (math.pi / 180.0);
    final forwardX = math.sin(headingRad);
    final forwardY = math.cos(headingRad);

    return (dx * forwardX) + (dy * forwardY);
  }

  // Projection Orthogonale Corrigée (Prend en compte la courbure de la Terre)
  LatLng _projectCorrected(LatLng p, LatLng a, LatLng b) {
    double latRad = (a.latitude + b.latitude) / 2.0 * (math.pi / 180.0);
    double cosLat = math.cos(latRad);

    double ax = a.longitude * cosLat;
    double ay = a.latitude;
    double bx = b.longitude * cosLat;
    double by = b.latitude;
    double px = p.longitude * cosLat;
    double py = p.latitude;

    double l2 =
        math.pow(bx - ax, 2).toDouble() + math.pow(by - ay, 2).toDouble();
    if (l2 == 0.0) return a;

    double t = ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / l2;

    // Force strictement le point projeté à rester sur le segment (Anti-retours en arrière)
    t = math.max(0.0, math.min(1.0, t));

    return LatLng(
      a.latitude + t * (b.latitude - a.latitude),
      a.longitude + t * (b.longitude - a.longitude),
    );
  }

  // --- GESTION ANTI-SPAM DES PERMISSIONS GPS ---
  Future<Position>? _pendingLocationFuture;

  Future<Position> getMyCurrentLocation() {
    // Si une requête GPS est déjà en cours, on retourne la même (évite le spam des 13 fenêtres)
    if (_pendingLocationFuture != null) return _pendingLocationFuture!;

    _pendingLocationFuture = _fetchLocationSafely().whenComplete(() {
      _pendingLocationFuture = null; // Libère le verrou une fois terminé
    });

    return _pendingLocationFuture!;
  }

  Future<Position> _fetchLocationSafely() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return Future.error('Les services de localisation sont désactivés.');
    }

    // On VÉRIFIE la permission avant de la demander
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // Si refusé, on demande (une seule fenêtre apparaîtra grâce au verrou)
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return Future.error('Permission GPS refusée');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return Future.error('Permission GPS refusée de façon permanente');
    }

    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  void setDestination(String name, LatLng coords,
      {dynamic mode, bool isStore = false}) async {
    destination.value = name;
    destinationCoordinates = coords;
    if (mode != null) currentTravelMode.value = mode;
    isNavigatingToStore.value = isStore;
    mapStatus.value = Constants.route;
    arrived.value = false;

    await addDestinationMarker(coords);
    await drawRoute(coords);
  }

  void setTravelMode(dynamic mode) {
    currentTravelMode.value = mode;
    if (mapStatus.value == Constants.route && destination.value.isNotEmpty) {
      drawRoute(destinationCoordinates);
    }
  }

  Future<void> drawRoute(LatLng dest,
      {LatLng? origin,
      DateTime? departureTime,
      DateTime? arrivalTime,
      double? currentBearing}) async {
    // <-- 1. ON AJOUTE LE PARAMÈTRE ICI

    // Attendre que le style soit chargé (sources disponibles) avant d'utiliser mapController
    await _styleReadyCompleter.future;
    // 1. Initialisation et Nettoyage
    gettingRoute.value = true;
    polylineCoordinates.clear();
    transitRouteOptions.clear();
    showTransitOptions.value = false;

    // On remet le dénivelé à 0 avant le nouveau calcul
    elevationGain.value = 0.0;

    // Nettoyage visuel des anciennes routes sur la carte
    await _setSafeGeoJsonSource(
        routeSourceId, {"type": "FeatureCollection", "features": []});
    await _setSafeGeoJsonSource(
        walkingRouteSourceId, {"type": "FeatureCollection", "features": []});

    try {
      // 2. Détermination du point de départ
      LatLng start;
      if (origin != null) {
        start = origin;
      } else {
        Position pos = await Geolocator.getCurrentPosition();
        start = LatLng(pos.latitude, pos.longitude);
      }

      String currentModeStr = currentTravelMode.value.toString();

      // ---------------------------------------------------------
      // CAS A : TRANSPORT EN COMMUN (Via Google Directions API)
      // ---------------------------------------------------------
      if (currentModeStr.contains('transit') ||
          currentTravelMode.value == TravelMode.transit) {
        String originStr = "${start.latitude},${start.longitude}";
        String destStr = "${dest.latitude},${dest.longitude}";

        // Gestion des horaires : s'assurer que c'est >= maintenant
        String timeParam = "";
        if (departureTime != null) {
          DateTime actualDeparture = departureTime.isBefore(DateTime.now())
              ? DateTime.now()
              : departureTime;
          timeParam =
              "&departure_time=${(actualDeparture.millisecondsSinceEpoch / 1000).round()}";
        } else if (arrivalTime != null) {
          timeParam =
              "&arrival_time=${(arrivalTime.millisecondsSinceEpoch / 1000).round()}";
        }

        String apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";

        // 🔍 LOGS PRÉCIS : Avant la requête
        debugPrint("========== DÉBUT REQUÊTE GOOGLE TRANSIT ==========");
        debugPrint("📍 Origine : $originStr");
        debugPrint("📍 Destination : $destStr");
        debugPrint(
            "🕒 Paramètre temps : ${timeParam.isEmpty ? 'Aucun (Maintenant par défaut)' : timeParam}");
        debugPrint(
            "🔑 Clé API chargée : ${apiKey.isNotEmpty ? 'OUI (Commence par ${apiKey.substring(0, 4)}...)' : 'NON (Chaîne vide)'}");

        String url =
            "https://maps.googleapis.com/maps/api/directions/json?units=metric&origin=$originStr&destination=$destStr&mode=transit$timeParam&alternatives=true&language=fr&key=$apiKey";

        try {
          var response = await Dio().get(url);
          var data = response.data;

          // 🔍 LOGS PRÉCIS : Réponse de l'API
          debugPrint("🌐 Statut HTTP : ${response.statusCode}");
          debugPrint("📝 Statut API Google : ${data['status']}");

          if (data['status'] == 'OK' &&
              data['routes'] != null &&
              (data['routes'] as List).isNotEmpty) {
            List<dynamic> routes = data['routes'];
            debugPrint(
                "✅ Succès : ${routes.length} itinéraire(s) de bus/métro trouvé(s).");

            transitRouteOptions.assignAll(routes);
            showTransitOptions.value = true;

            debugPrint("========== FIN REQUÊTE GOOGLE TRANSIT ==========");
            return;
          } else {
            // 🔍 LOGS PRÉCIS : Si Google ne renvoie pas 'OK'
            debugPrint("⚠️ L'API a répondu mais a refusé ou n'a rien trouvé.");
            debugPrint(
                "❌ Message d'erreur détaillé : ${data['error_message'] ?? 'Aucun message d\'erreur fourni par Google.'}");

            _safeSnackbar(
              "Transports",
              "Aucun itinéraire trouvé (Statut: ${data['status']})",
              backgroundColor: Colors.orange.shade700,
            );
            gettingRoute.value = false;
            debugPrint(
                "========== FIN REQUÊTE GOOGLE TRANSIT (ÉCHEC API) ==========");
            return; // On empêche OSRM de prendre le relais !
          }
        } on DioException catch (e) {
          // 🔍 LOGS PRÉCIS : Si la requête réseau plante (pas d'internet, timeout...)
          debugPrint("❌ Erreur Réseau (DioException) : ${e.message}");
          if (e.response != null) {
            debugPrint("❌ Données d'erreur HTTP : ${e.response?.data}");
          }
        } catch (e) {
          // 🔍 LOGS PRÉCIS : Si le code plante (erreur de parsing JSON, etc.)
          debugPrint("❌ Erreur Inattendue Google Transit : $e");
        }

        gettingRoute.value = false;
        debugPrint(
            "========== FIN REQUÊTE GOOGLE TRANSIT (AVEC EXCEPTION) ==========");
        return; // On empêche OSRM de prendre le relais
      }

      // ---------------------------------------------------------
      // CAS B : MARCHE / VÉLO / VOITURE (Via OSRM)
      // ---------------------------------------------------------

      // Définition du mode pour OSRM
      String osrmMode = 'driving'; // Par défaut
      if (currentModeStr.contains('cycling') ||
          currentTravelMode.value == TravelMode.bicycling) {
        osrmMode = Constants.modeCycling;
      } else if (currentModeStr.contains('walking') ||
          currentTravelMode.value == TravelMode.walking) {
        osrmMode = Constants.modeWalking;
      }

      // ---> 2. C'EST ICI QU'ON APPELLE LE SERVICE OSRM AVEC LE BEARING <---
      var routeData = await _osrmService.getRoute(start, dest, osrmMode,
          bearing: currentBearing);

      if (routeData != null &&
          routeData['distance'] != null &&
          routeData['duration'] != null &&
          routeData['geometry'] != null) {
        // Mise à jour des données brutes (Dist/Temps) en toute sécurité
        activeRouteRawDistanceMeters.value =
            (routeData['distance'] as num).toDouble();
        activeRouteRawDurationSeconds.value =
            (routeData['duration'] as num).toDouble();

        // Mise à jour de l'affichage UI
        if (activeRouteRawDistanceMeters.value >= 1000) {
          distanceLeft.value =
              "${(activeRouteRawDistanceMeters.value / 1000).toStringAsFixed(1)} km";
        } else {
          distanceLeft.value =
              "${activeRouteRawDistanceMeters.value.round()} m";
        }

        int mins = (activeRouteRawDurationSeconds.value / 60).round();
        int hours = mins ~/ 60;
        timeLeft.value = hours > 0 ? "${hours}h ${mins % 60}min" : "$mins min";

        // Traitement de la géométrie (Polyline)
        List coords = routeData['geometry']['coordinates'];
        for (var c in coords) {
          // OSRM renvoie [long, lat], on stocke LatLng(lat, long)
          polylineCoordinates.add(LatLng(c[1], c[0]));
        }

        // Dessin sur la carte (Source GeoJSON)
        final feature = {
          "type": "FeatureCollection",
          "features": [
            {
              "type": "Feature",
              "geometry": {"type": "LineString", "coordinates": coords}
            }
          ]
        };
        await _setSafeGeoJsonSource(routeSourceId, feature);

        // -----------------------------------------------------
        // CALCUL DU DÉNIVELÉ (OPEN-METEO API)
        // -----------------------------------------------------
        // On appelle la fonction dédiée avec les points de la route trouvée
        if (polylineCoordinates.isNotEmpty) {
          _fetchElevationGain(polylineCoordinates);
        }

        // Mise à jour des instructions textuelles (NavigationController)
        if (Get.isRegistered<NavigationController>()) {
          Get.find<NavigationController>()
              .setRouteInstructions(routeData['legs'][0]['steps']);
        }
      }
    } catch (e) {
      debugPrint("Erreur globale drawRoute: $e");
    } finally {
      gettingRoute.value = false;
    }
  }

  Future<void> addDestinationMarker(LatLng point) async {
    await _styleReadyCompleter.future;
    final feature = {
      "type": "FeatureCollection",
      "features": [
        {
          "type": "Feature",
          "geometry": {
            "type": "Point",
            "coordinates": [point.longitude, point.latitude]
          }
        }
      ]
    };
    await _setSafeGeoJsonSource(destSourceId, feature);
  }

  Future<void> moveMapCamera(LatLng target,
      {double zoom = 15.0, double bearing = 0.0, double tilt = 0.0}) async {
    if (!_styleReadyCompleter.isCompleted) return;
    try {
      await mapController
          .animateCamera(CameraUpdate.newCameraPosition(CameraPosition(
        target: target,
        zoom: zoom,
        bearing: bearing,
        tilt: tilt,
      )));
    } catch (e) {}
  }

  Future<void> getTotalDistanceAndTime(LatLng dest) async {}

  void clearDestination() async {
    mapStatus.value = Constants.idle;
    isNavigationCameraLocked.value = true;
    destination.value = "";
    arrived.value = false;
    polylineCoordinates.clear();
    transitRouteOptions.clear();

    if (!_styleReadyCompleter.isCompleted) return;
    await _setSafeGeoJsonSource(
        routeSourceId, {"type": "FeatureCollection", "features": []});
    await _setSafeGeoJsonSource(
        walkingRouteSourceId, {"type": "FeatureCollection", "features": []});
    await _setSafeGeoJsonSource(
        destSourceId, {"type": "FeatureCollection", "features": []});

    stopFluidNavigation();
    _movementController?.stop();
    recenterMap();
    startIdleTracking();
  }

  void startIdleTracking() async {
    await _idlePositionStream?.cancel();
    const settings =
        LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0);
    _idlePositionStream =
        Geolocator.getPositionStream(locationSettings: settings)
            .listen((Position position) {
      if (mapStatus.value == Constants.onDestination) return;
      _updateDriverMarker(
          LatLng(position.latitude, position.longitude), position.heading);
    });
  }

  void stopIdleTracking() => _idlePositionStream?.cancel();

  Future<void> recenterMap() async {
    try {
      if (mapStatus.value == Constants.onDestination) {
        // CAS NAVIGATION : On reverrouille la caméra sur le conducteur
        isNavigationCameraLocked.value = true;

        // On force un mouvement immédiat vers la dernière position connue ou animée
        if (_currentAnimatedPos != null) {
          await mapController.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                  target: _currentAnimatedPos!,
                  zoom: 18.0,
                  bearing: _lastBearing,
                  tilt: 50)));
        } else {
          // Fallback si pas d'animation fluide en cours
          Position pos = await Geolocator.getCurrentPosition();
          await mapController.animateCamera(CameraUpdate.newCameraPosition(
              CameraPosition(
                  target: LatLng(pos.latitude, pos.longitude),
                  zoom: 18.0,
                  bearing: pos.heading,
                  tilt: 50)));
        }
      } else {
        // CAS IDLE / ROUTE : On centre simplement sur la position utilisateur
        Position pos = await Geolocator.getCurrentPosition();
        await moveMapCamera(LatLng(pos.latitude, pos.longitude));
      }
    } catch (e) {
      debugPrint("Erreur lors du recentrage: $e");
    }
  }

  Future<void> _addImageFromAsset(String name, String assetName) async {
    try {
      final ByteData bytes = await rootBundle.load(assetName);
      final Uint8List list = bytes.buffer.asUint8List();
      await mapController.addImage(name, list);
    } catch (_) {}
  }

  Future<void> _checkPermissionsAndInitLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    // --- AJOUT SÉCURITÉ MOCK LOCATION ---
    const bool securityEnabled = false;

    if (securityEnabled) {
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        bool isMockLocation = await SafeDevice.isMockLocation;
        if (isMockLocation) {
          Get.offAll(() => const SecurityBlockedScreen(
              reason: "Position fictive (Fake GPS) détectée."));
          return;
        }
      }
    }
    // ------------------------------------
    recenterMap();
  }
}

class NavigationController extends GetxController {
  final HomeController homeController = Get.find();
  final SpeedController speedController = Get.find();
  var isStayTimerActive = false.obs;
  var staySecondsRemaining = 0.obs;
  var isUserInStayZone = false.obs;
  Challenge? stayChallenge;
  StreamSubscription<Position>? independentStayStream;
  Timer? independentStayTimer;
  StreamSubscription<Position>? positionStream;

  // ── VARIABLES DIAGNOSTIC (AJOUT) ──
  var timeBetweenGpsMs = 0.obs; // Temps écoulé depuis le dernier point GPS
  var gpsProcessingMs = 0.obs; // Temps que met le code à s'exécuter
  var gpsLatencyMs = 0.obs; // 🚀 NOUVEAU : Latence exacte entre le fix GPS et l'écran
  DateTime? _lastGpsReceiveTime;

// ── VARIABLES DÉVIATION DE ROUTE ──────────────────────────────────────────
  double _cumulatedDeviationMeters = 0.0;
  LatLng? _lastOnRoutePosition;
  DateTime? _lastOnRouteTime;
  bool _isDeviationDialogOpen = false;
  DateTime? _lastAutoRecalculateTime;
  UserProfile? _activeUserProfile;

  // NOUVEAU : Verrou de sécurité pour limiter le recalcul à 1 seule fois
  bool _hasUsedManualRecalculate = false;
  var isCameraLocked = true.obs;
  var isOnBus = false.obs;
  var transitLegs = [].obs;
  var currentLegIndex = 0.obs;
  var directions = [].obs;

  var currentInstructionText = "".obs;

  dynamic activeChallenge;
  String? activeWorkCommuteType;
  Function()? onStoreDestinationReached;
  Function(dynamic)? _onChallengeReached;
  Function(String)? _onWorkReached;
  Function(int)? onNormalDestinationReached;

  // Variables spécifiques Arrêt de Bus
  LatLng? _targetBusStopLocation;
  DateTime? _targetBusStopSchedule;
  DateTime? _busStopArrivalTime; // Ajout pour la détection d'arrêt de bus
  bool _hasReachedBusStop = false;

  // Variables lissage mouvement
  DateTime? _lastPositionTime;
  LatLng? _lastSnappedPos;
  double _avgInterval = 1000;

  // Transit monitoring (avertissements de déviation)
  TransitMonitor? _transitMonitor;
  DateTime? _transitOffRouteSince;
  bool _transitOffRouteLongWarning = false;

  // --- VARIABLES POUR LA DÉTECTION DE MODE ET VITESSE (ANTI-TRICHE) ---
  // Historique pour calcul de moyenne et variance
  final List<double> _speedHistory = [];
  final List<double> _recentWalkingSpeeds = [];
  DateTime? _startTime;

  // Gestion de la tolérance (Burst)
  DateTime? _highSpeedBurstStartTime;
  static const Duration _maxBurstDuration = Duration(seconds: 15);

  // Indicateur pour ne pas spammer les popups
  bool _isSwitchingModeDialogTrace = false;

  // ── HISTORIQUE VITESSE POUR DÉTECTION MODE VOITURE ─────────────────────
  final List<double> _highSpeedSamples = [];
  DateTime? _highSpeedWindowStart;

  // ── FLAGS POPUPS (éviter doublons) ───────────────────────────────────────
  bool _isScheduleDialogOpen = false;
  int _currentStepIndex =
      0; // Index séquentiel pour les instructions de navigation

  // ══════════════════════════════════════════════════════════════════════════
  // 📊 FIREBASE TRIP LOGGING + NOTIFICATIONS
  // ══════════════════════════════════════════════════════════════════════════
  String? _activeTripId;
  DateTime? _tripStartTime;
  final List<Map<String, dynamic>> _tripPositionBuffer = [];
  int _positionSampleCount = 0;
  static const int _positionSampleInterval = 5;
  double _totalDeviationMeters = 0.0; // Track cumulative deviations during trip
  final List<double> _tripSpeedSamples =
      []; // Store speed samples for calculating average
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();
// ── AJOUT : MISE À JOUR DES STATS ET DISTRIBUTION DES BADGES ──
  Future<void> _updateStatsAndCheckBadges(double distanceMeters) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .get();
      if (!doc.exists) return;

      final data = doc.data()!;
      double currentDist =
          (data['total_distance_km'] as num?)?.toDouble() ?? 0.0;
      int currentTrips = (data['total_trips_count'] as num?)?.toInt() ?? 0;
      int currentCals = (data['total_calories_burned'] as num?)?.toInt() ?? 0;
      List<String> unlocked =
          (data['unlocked_badges'] as List<dynamic>?)?.cast<String>() ?? [];
      List<String> friends =
          (data['friend_ids'] as List<dynamic>?)?.cast<String>() ?? [];
      bool isVip = data['is_vip'] ?? false;

      // 1. Incrémenter les statistiques
      double addedKm = distanceMeters / 1000.0;
      currentDist += addedKm;
      currentTrips += 1;
      int addedCals =
          (addedKm * 50).round(); // Moyenne de 50 calories brûlées par km
      currentCals += addedCals;

      // 2. Vérifier si de nouveaux badges sont débloqués
      List<String> newBadges = [];

      if (currentDist >= 1.0 && !unlocked.contains('first_km'))
        newBadges.add('first_km');
      if (currentDist >= 10.0 && !unlocked.contains('endurance_10km'))
        newBadges.add('endurance_10km');
      if (currentDist >= 42.0 && !unlocked.contains('marathon'))
        newBadges.add('marathon');
      if (currentDist >= 100.0 && !unlocked.contains('hundred_km'))
        newBadges.add('hundred_km');

      if (currentTrips >= 50 && !unlocked.contains('fifty_trips'))
        newBadges.add('fifty_trips');
      if (currentTrips >= 100 && !unlocked.contains('hundred_trips'))
        newBadges.add('hundred_trips');

      if (currentCals >= 1000 && !unlocked.contains('burn_thousand_calories'))
        newBadges.add('burn_thousand_calories');

      if (friends.length >= 10 && !unlocked.contains('social_butterfly'))
        newBadges.add('social_butterfly');
      if (isVip && !unlocked.contains('vip_member'))
        newBadges.add('vip_member');

      // 3. Sauvegarder dans Firestore et alerter l'utilisateur
      if (newBadges.isNotEmpty) {
        unlocked.addAll(newBadges);
        for (var b in newBadges) {
          // Notification en haut de l'écran pour féliciter !
          Get.snackbar(
            "Nouveau Badge ! 🏅",
            "Vous avez débloqué un nouvel accomplissement, vérifiez votre profil !",
            backgroundColor: Colors.amber,
            colorText: Colors.black,
            duration: const Duration(seconds: 4),
          );
        }
      }

      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'total_distance_km': currentDist,
        'total_trips_count': currentTrips,
        'total_calories_burned': currentCals,
        'unlocked_badges': unlocked,
      });
    } catch (e) {
      print("Erreur mise à jour stats et badges: $e");
    }
  }

  void stopIndependentStayTimer() {
    isStayTimerActive.value = false;
    independentStayTimer?.cancel();
    independentStayStream?.cancel();
    stayChallenge = null;
  }

  Future<void> _initNotifications() async {
    try {
      const InitializationSettings settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _notificationsPlugin.initialize(settings);
    } catch (_) {}
  }

  Future<void> _showNotification(String title, String body,
      {int id = 0}) async {
    try {
      await _notificationsPlugin.show(
          id,
          title,
          body,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'walkmoney_nav_channel',
              'Navigation WalkMoney',
              channelDescription: 'Notifications de navigation',
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ));
    } catch (_) {}
  }

  Future<void> _startTripLog() async {
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;
      final mode = homeController.currentTravelMode.value;
      final modeStr = mode == TravelMode.walking
          ? 'walking'
          : mode == TravelMode.bicycling
              ? 'bicycling'
              : mode == TravelMode.transit
                  ? 'transit'
                  : 'driving';
      _tripStartTime = DateTime.now();
      _tripPositionBuffer.clear();
      _tripSpeedSamples.clear();
      _totalDeviationMeters = 0.0;
      _positionSampleCount = 0;
      final userPos = await homeController.getMyCurrentLocation();
      final docRef = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('trip_logs')
          .add({
        'user_id': userId,
        'travel_mode': modeStr,
        'start_lat': userPos.latitude,
        'start_lng': userPos.longitude,
        'destination_name': homeController.destination.value,
        'destination_lat': homeController.destinationCoordinates.latitude,
        'destination_lng': homeController.destinationCoordinates.longitude,
        'started_at': FieldValue.serverTimestamp(),
        'ended_at': null,
        'status': 'in_progress',
        'estimated_distance_meters':
            homeController.activeRouteRawDistanceMeters.value,
        'estimated_duration_seconds':
            homeController.activeRouteRawDurationSeconds.value,
        'actual_duration_seconds': null,
        'actual_distance_meters': null,
        'average_speed_kmh': null,
        'total_deviation_meters': 0.0,
        'cheat_detected': false,
        'cheat_reason': null,
        'positions': [],
        'lames_earned': 0,
      });
      _activeTripId = docRef.id;
    } catch (e) {
      debugPrint('[TripLog] Erreur démarrage: $e');
    }
  }

  Future<void> _logTripPosition(
      LatLng pos, double speedKmh, double heading) async {
    _positionSampleCount++;
    if (_positionSampleCount % _positionSampleInterval != 0 ||
        _activeTripId == null) return;
    _tripSpeedSamples.add(speedKmh);
    _tripPositionBuffer.add({
      'lat': pos.latitude,
      'lng': pos.longitude,
      'speed_kmh': speedKmh,
      'heading': heading,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    if (_tripPositionBuffer.length >= 10) await _flushTripPositions();
  }

  Future<void> _flushTripPositions() async {
    if (_activeTripId == null || _tripPositionBuffer.isEmpty) return;
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;
      final buf = List<Map<String, dynamic>>.from(_tripPositionBuffer);
      _tripPositionBuffer.clear();
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('trip_logs')
          .doc(_activeTripId)
          .update({'positions': FieldValue.arrayUnion(buf)});
    } catch (e) {
      debugPrint('[TripLog] Erreur flush: $e');
    }
  }

  Future<void> _endTripLog({
    required String status,
    String? cheatReason,
    double? finalDistanceMeters,
    int? lamesEarned,
  }) async {
    if (_activeTripId == null) return;
    final tripId = _activeTripId!;
    _activeTripId = null;
    try {
      await _flushTripPositions();
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;
      final actualDuration = _tripStartTime != null
          ? DateTime.now().difference(_tripStartTime!).inSeconds
          : null;
      _tripStartTime = null;

      // Calculate average speed from all samples
      double averageSpeedKmh = 0.0;
      if (_tripSpeedSamples.isNotEmpty) {
        averageSpeedKmh = _tripSpeedSamples.reduce((a, b) => a + b) /
            _tripSpeedSamples.length;
      }
      _tripSpeedSamples.clear();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('trip_logs')
          .doc(tripId)
          .update({
        'ended_at': FieldValue.serverTimestamp(),
        'status': status,
        'cheat_detected': cheatReason != null,
        'cheat_reason': cheatReason,
        'actual_duration_seconds': actualDuration,
        'actual_distance_meters': finalDistanceMeters,
        'average_speed_kmh': averageSpeedKmh,
        'total_deviation_meters': _totalDeviationMeters,
        'lames_earned': lamesEarned ?? 0,
      });
      await FirebaseFirestore.instance.collection('user_activity_logs').add({
        'user_id': userId,
        'type': 'trip_$status',
        'trip_id': tripId,
        'travel_mode': homeController.currentTravelMode.value.toString(),
        'destination': homeController.destination.value,
        'timestamp': FieldValue.serverTimestamp(),
        'cheat_reason': cheatReason,
        'lames_earned': lamesEarned ?? 0,
      });
    } catch (e) {
      debugPrint('[TripLog] Erreur fin: $e');
    }
  }

  void setRouteInstructions(List steps) {
    directions.assignAll(steps);
    _currentStepIndex = 0;
    if (steps.isNotEmpty) {
      final firstStep = steps[0];

      // Essayer différents formats selon la source (OSRM, Google Transit, Google Directions)
      if (firstStep['maneuver'] != null) {
        // Format OSRM
        final maneuver = firstStep['maneuver'];
        if (maneuver is Map) {
          currentInstructionText.value = _translateManeuver(
            maneuver['type']?.toString() ?? '',
            maneuver['modifier']?.toString() ?? '',
          );
        }
      } else if (firstStep['instruction'] != null) {
        // Format OSRM alternatif ou autres services
        currentInstructionText.value = firstStep['instruction'].toString();
      } else if (firstStep['html_instructions'] != null) {
        // Format Google Directions / Transit
        currentInstructionText.value =
            _cleanHtml(firstStep['html_instructions'].toString());
      } else if (firstStep['instructions'] != null) {
        // Format fallback
        currentInstructionText.value = firstStep['instructions'].toString();
      } else if (firstStep['name'] != null) {
        // Format OSRM avec juste le nom de la route
        currentInstructionText.value =
            "Continuer sur ${firstStep['name'].toString()}";
      } else {
        // Dernier recours: afficher quelque chose
        debugPrint("⚠️ Format d'instruction non reconnu: ${firstStep.keys}");
        currentInstructionText.value = "Navigation en cours...";
      }
    }
  }

  String _cleanHtml(String htmlString) {
    return htmlString.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  void setOnStoreDestinationReachedCallback(Function() cb) =>
      onStoreDestinationReached = cb;
  void setOnChallengeDestinationReachedCallback(Function(dynamic) cb) =>
      _onChallengeReached = cb;
  void setOnWorkDestinationReachedCallback(Function(String) cb) =>
      _onWorkReached = cb;
  void setOnNormalDestinationReachedCallback(Function(int) cb) =>
      onNormalDestinationReached = cb;

  /// Transmettre le profil utilisateur pour la tolérance déviation (3km standard / 6km premium)
  void setActiveUserProfile(UserProfile? profile) =>
      _activeUserProfile = profile;

  void setTargetTransitStop(LatLng location, DateTime? schedule) {
    _targetBusStopLocation = location;
    _targetBusStopSchedule = schedule;
    _hasReachedBusStop = false;
  }

  void clearTargetTransitStop() {
    _targetBusStopLocation = null;
    _targetBusStopSchedule = null;
    _hasReachedBusStop = false;
  }

  // Getters publics pour accéder aux états du transit (à partir des widgets)
  LatLng? get targetBusStopLocation => _targetBusStopLocation;
  DateTime? get targetBusStopSchedule => _targetBusStopSchedule;
  bool get hasReachedBusStop => _hasReachedBusStop;
  double get cumulatedDeviationMeters => _cumulatedDeviationMeters;

  void startNavigation() {
    navigateToDestination();
  }

  void navigateToDestination({bool validateWalkingLegs = false}) async {
    if (homeController.polylineCoordinates.isEmpty) return;

    // --- 1. SAUVEGARDE DES DONNÉES POUR L'ARRIÈRE-PLAN ---
    double currentElevFactor = _getElevationSpeedFactor();
    bool isPremium = _activeUserProfile?.isVip ?? false;
    double deviationLimit = isPremium ? 6000.0 : 3000.0;

    String bgModeStr =
        homeController.currentTravelMode.value.toString().toLowerCase();

    // On sérialise la polyline pour que le background puisse vérifier la déviation
    List<Map<String, double>> serializedPolyline = homeController
        .polylineCoordinates
        .map((p) => {'lat': p.latitude, 'lng': p.longitude})
        .toList();

    await SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('bg_is_navigating', true);
      prefs.setString('bg_travel_mode', bgModeStr);
      prefs.setDouble('bg_elevation_factor', currentElevFactor);
      prefs.setDouble('bg_max_deviation', deviationLimit);
      prefs.setString('bg_route_polyline', jsonEncode(serializedPolyline));
    });
    // ----------------------------------------------------

    FlutterBackgroundService().invoke("stop_background_trip", {
      'travel_mode': bgModeStr,
    });
    print("📡 Envoi signal: stop_background_trip avec paramètres avancés");

    // Dessiner le cercle rouge si c'est un défi "Rester sur place"
    if (activeChallenge != null &&
        (activeChallenge!.stayDurationSeconds ?? 0) > 0) {
      if (activeChallenge!.latitude != null &&
          activeChallenge!.longitude != null) {
        homeController.drawCircleOnMap(
            LatLng(activeChallenge!.latitude!, activeChallenge!.longitude!),
            10.0);
      }
    }

    // Initialisation du trajet
    _startTime = DateTime.now();
    _speedHistory.clear();
    _recentWalkingSpeeds.clear();
    _highSpeedSamples.clear();
    _highSpeedWindowStart = null;
    _highSpeedBurstStartTime = null;
    _cumulatedDeviationMeters = 0.0;
    _lastOnRoutePosition = null;
    _lastOnRouteTime = DateTime.now();
    _isDeviationDialogOpen = false;
    _isScheduleDialogOpen = false;
    _currentStepIndex = 0;

    // NOUVEAU: Verrou de la chance unique pour le recalcul
    _hasUsedManualRecalculate = false;

    // Pour s'assurer qu'une instruction s'affiche immédiatement en navigation
    currentInstructionText.value = "Navigation en cours...";

    homeController.stopIdleTracking();
    homeController.mapStatus.value = Constants.onDestination;
    homeController.isNavigationCameraLocked.value = true;
    isCameraLocked.value = true;

    // Initialisation du monitor transit (pour détecter déviation en bus)
    if (homeController.currentTravelMode.value == TravelMode.transit) {
      _transitMonitor = TransitMonitor(
        onWarning: (msg) {
          // Première alerte dès la déviation détectée
          homeController._safeSnackbar("⚠️ Déviation Transports", msg,
              backgroundColor: Colors.orange.shade700);
          _transitOffRouteSince ??= DateTime.now();
          _transitOffRouteLongWarning = false;
        },
        onBackOnRoute: () {
          // Remise sur la route
          _transitOffRouteSince = null;
          _transitOffRouteLongWarning = false;
          homeController._safeSnackbar("✅ Retour sur l'itinéraire",
              "Vous êtes de nouveau sur le trajet du bus.",
              backgroundColor: Colors.green.shade700);
        },
      );
    } else {
      _transitMonitor = null;
      _transitOffRouteSince = null;
      _transitOffRouteLongWarning = false;
    }

    // ─── LOG DU MODE DE TRANSPORT CHOISI ───
    String modeStr = "à pied 🚶";
    MaterialColor modeColor = Colors.green;
    String currentModeString =
        homeController.currentTravelMode.value.toString().toLowerCase();

    if (currentModeString.contains('bicycl')) {
      modeStr = "à vélo 🚲";
      modeColor = Colors.blue;
    } else if (currentModeString.contains('transit')) {
      modeStr = "en transports 🚌";
      modeColor = Colors.orange;
    }

    homeController._safeSnackbar(
      "Navigation démarrée",
      "Trajet $modeStr",
      backgroundColor: modeColor.shade700,
      colorText: Colors.white,
      duration: const Duration(seconds: 4),
      snackPosition: SnackPosition.BOTTOM,
    );
    // ───────────────────────────────────────

    // Sauvegarde état navigation
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(
          'active_nav_destination', homeController.destination.value);
      prefs.setDouble(
          'active_nav_lat', homeController.destinationCoordinates.latitude);
      prefs.setDouble(
          'active_nav_lng', homeController.destinationCoordinates.longitude);
      prefs.setString(
          'active_nav_mode', homeController.currentTravelMode.value.toString());
      prefs.setBool('active_nav_running', true);
    });

    _initNotifications().then((_) {
      _startTripLog();
      _showNotification(
        '🚀 Navigation démarrée',
        'Vers : ${homeController.destination.value}',
        id: 1,
      );
    });

    // 🚀 Lancer l'animation prédictive
    homeController.startFluidNavigation();

    // 🔋 RÉGLAGES GPS TEMPS RÉEL (Idéal pour la navigation, comme Google Maps/Waze)
    // On met distanceFilter à 0 pour recevoir des updates même à l'arrêt.
    LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter:
                0, // 0 = Désactivé, on se base uniquement sur le temps
            intervalDuration:
                const Duration(seconds: 1), // 1 update par seconde !
          )
        : AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0, // 0 = Désactivé
            activityType: ActivityType.automotiveNavigation,
          );

    positionStream = Geolocator.getPositionStream(locationSettings: settings)
        .listen((Position position) {
      // ⏱️ 1. DÉBUT DU CHRONO : Réception du GPS
      final receiveTime = DateTime.now();
      if (_lastGpsReceiveTime != null) {
        timeBetweenGpsMs.value =
            receiveTime.difference(_lastGpsReceiveTime!).inMilliseconds;
      }
      _lastGpsReceiveTime = receiveTime;

      // 🚀 2. DONNER LA VRAIE POSITION AU FILTRE !
      homeController.kinematicFilter.updateRealPosition(position);

      // 🔍 3. MISE À JOUR DES POINTS DE DIAGNOSTIC
      homeController._updateDiagnosticMarkers();

      // ─── GARDE-FOU: Ne pas exécuter si on cherche déjà une route ───
      if (homeController.gettingRoute.value) return;

      final now = DateTime.now();
      speedController.updateSpeed(position);

      LatLng rawPos = LatLng(position.latitude, position.longitude);
      // CORRIGÉ : On utilise la vitesse lissée du SpeedController
      double currentSpeedKmh = speedController.currentSpeed.value;
      if (currentSpeedKmh < 0) currentSpeedKmh = 0;

      // CORRIGÉ : On enregistre la vitesse pour le récapitulatif final (tous les modes)
      _speedHistory.add(currentSpeedKmh);

      if (homeController.currentTravelMode.value != TravelMode.transit &&
          !_isSwitchingModeDialogTrace) {
        bool stopNow = _analyzeSpeedCompliance(currentSpeedKmh);
        if (stopNow) return;
      }

      final snapResult =
          homeController._getNearestRoutePoint(rawPos, position.heading);
      LatLng snappedPos =
          snapResult.distance < 30.0 ? snapResult.point : rawPos;
      double distanceDeviation = snapResult.distance;

      // Initialiser _lastOnRoutePosition au premier point GPS si pas encore init
      if (_lastOnRoutePosition == null) {
        _lastOnRoutePosition = snappedPos;
        _lastOnRouteTime = DateTime.now();
        debugPrint(
            "✅ Déviation: Point de référence initialisé à ${snappedPos.latitude}, ${snappedPos.longitude}");
      }

      var mode = homeController.currentTravelMode.value;
      bool isWalkOrBike =
          mode == TravelMode.walking || mode == TravelMode.bicycling;

      if (isWalkOrBike && !_isDeviationDialogOpen) {
        if (distanceDeviation > 30.0) {
          LatLng referencePoint = _lastOnRoutePosition ?? snappedPos;
          double distSinceLastOnRoute = Geolocator.distanceBetween(
            rawPos.latitude,
            rawPos.longitude,
            referencePoint.latitude,
            referencePoint.longitude,
          );
          if (distSinceLastOnRoute > _cumulatedDeviationMeters) {
            _cumulatedDeviationMeters = distSinceLastOnRoute;
          }
        } else {
          _lastOnRoutePosition = snappedPos;
          _lastOnRouteTime = DateTime.now();
          _cumulatedDeviationMeters = 0.0;
        }

        // RÈGLE DE LA MORT SUBITE
        if (_hasUsedManualRecalculate && _cumulatedDeviationMeters > 50.0) {
          print("🚨 DEUXIÈME DÉVIATION DÉTECTÉE (> 50m). ARRÊT IMMÉDIAT.");
          _triggerDeviationFailure();
          return;
        }

        bool isPremium = _activeUserProfile?.isVip ?? false;
        double deviationLimitMeters = isPremium ? 6000.0 : 3000.0;
        double autoRecalculateLimitMeters = isWalkOrBike ? 50.0 : 100.0;

        if (_cumulatedDeviationMeters >= autoRecalculateLimitMeters &&
            !_isDeviationDialogOpen &&
            !_hasUsedManualRecalculate) {
          bool canAutoRecalculate = _lastAutoRecalculateTime == null ||
              DateTime.now().difference(_lastAutoRecalculateTime!).inSeconds >=
                  10;

          if (canAutoRecalculate) {
            print(
                "🚨 DÉVIATION MAJEURE DÉTECTÉE : ${(_cumulatedDeviationMeters / 1000).toStringAsFixed(2)}km - RECALCUL AUTOMATIQUE");
            _isDeviationDialogOpen = true;
            _recalculateToLastOnRoutePoint(rawPos).then((_) {
              _isDeviationDialogOpen = false;
            }).catchError((e) {
              debugPrint("❌ Erreur recalcul déviation: $e");
              _isDeviationDialogOpen = false;
            });
            return;
          }
        }

        if (_cumulatedDeviationMeters >= deviationLimitMeters &&
            !_hasUsedManualRecalculate) {
          _showDeviationPopup(
              _cumulatedDeviationMeters, deviationLimitMeters, rawPos);
          return;
        }
      }

      homeController.updateRemainingDistanceAndTime(snappedPos);
      _updateInstruction(rawPos);
      _logTripPosition(rawPos, currentSpeedKmh, position.heading);

      if (_targetBusStopLocation != null) {
        double distanceToStop = Geolocator.distanceBetween(
            rawPos.latitude,
            rawPos.longitude,
            _targetBusStopLocation!.latitude,
            _targetBusStopLocation!.longitude);

        // Détection d'arrêt de bus
        if (distanceToStop <= 15.0 && !_hasReachedBusStop) {
          _hasReachedBusStop = true;
          isOnBus.value = false;
          _busStopArrivalTime = DateTime.now();
          currentInstructionText.value =
              "🚌 Arrêt de bus atteint. En attente du départ...";
          homeController._safeSnackbar(
            "🚌 Arrêt de bus atteint",
            "Restez près du point d'arrêt pour monter à bord.",
            backgroundColor: Colors.blue.shade700,
            duration: const Duration(seconds: 4),
          );
        }

        // Détection du départ du bus
        if (_hasReachedBusStop &&
            !isOnBus.value &&
            distanceToStop > 30.0 &&
            currentSpeedKmh > 8.0) {
          isOnBus.value = true;
          _hasReachedBusStop = false;
          _busStopArrivalTime = null;
          _targetBusStopLocation = null;
          currentInstructionText.value = "🚌 Bus parti. Bon voyage !";
          homeController._safeSnackbar(
            "🚌 Bus parti",
            "Le bus est en mouvement. Profitez du trajet.",
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
          );
        }

        // Arrivée à un arrêt (si déjà dans le bus)
        if (isOnBus.value && distanceToStop <= 15.0 && currentSpeedKmh < 5.0) {
          isOnBus.value = false;
          _busStopArrivalTime = DateTime.now();
          currentInstructionText.value =
              "🚌 Bus à l'arrêt. Préparez-vous à descendre.";
          homeController._safeSnackbar(
            "🚌 Arrivée",
            "Le bus est à l'arrêt. Préparez-vous à descendre.",
            backgroundColor: Colors.blue.shade700,
            duration: const Duration(seconds: 4),
          );
        }

        // --- CORRECTION LOGIQUE RETARD BUS ---
        if (_busStopArrivalTime != null &&
            _hasReachedBusStop &&
            distanceToStop <= 15.0) {
          bool isDelayed = false;

          if (_targetBusStopSchedule != null) {
            // Le bus est en retard SI on a dépassé l'heure prévue de plus de 5 minutes
            isDelayed =
                DateTime.now().difference(_targetBusStopSchedule!).inSeconds >
                    300;
          } else {
            // Fallback: 15 minutes d'attente minimum avant de le considérer en retard
            isDelayed =
                DateTime.now().difference(_busStopArrivalTime!).inSeconds > 900;
          }

          if (isDelayed) {
            _showCriticalModal(
              'Retard de bus détecté',
              '⏳ Le bus semble bloqué ou en retard. Vérifiez le planning ou choisissez un autre itinéraire.',
            );
            _busStopArrivalTime = null; // Ne pas spammer l'utilisateur
          }
        }
        // --------------------------------------

        // Détection d'écart du tracé (transit)
        if (_transitMonitor != null &&
            homeController.polylineCoordinates.isNotEmpty) {
          bool isOnRoute = _transitMonitor!
              .checkPosition(rawPos, homeController.polylineCoordinates);

          if (!isOnRoute && _transitOffRouteSince != null) {
            final offRouteDuration =
                DateTime.now().difference(_transitOffRouteSince!);

            if (offRouteDuration.inSeconds > 60) {
              print(
                  "🚨 TRICHE TRANSIT : Hors du tracé depuis plus de 60s. ARRÊT IMMÉDIAT.");
              _triggerCheatDetection("Vous avez quitté le trajet du bus.");
              return;
            }

            if (offRouteDuration.inSeconds > 30 &&
                !_transitOffRouteLongWarning) {
              _transitOffRouteLongWarning = true;
              homeController._safeSnackbar(
                "⚠️ Hors itinéraire",
                "Vous avez quitté le trajet du bus. Retournez-y vite !",
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 5),
              );
            }
          }
        }

        // Gestion du pop-up horaire du bus (retard / avance)
        if (distanceToStop <= 10.0 &&
            !_isScheduleDialogOpen &&
            !_hasReachedBusStop) {
          _checkBusStopArrivalLogic();
        }
      }

      _lastPositionTime = now;
      _lastSnappedPos = snappedPos;
      _checkRouteLogic(rawPos, snappedPos);

      // ⏱️ 4. FIN DU CHRONO : Temps de traitement du code
      final finishTime = DateTime.now();
      gpsProcessingMs.value = finishTime.difference(receiveTime).inMilliseconds;
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 🧠 SYSTÈME ANTI-TRICHE INTELLIGENT — VITESSE + DÉNIVELÉ + MODE
  // ══════════════════════════════════════════════════════════════════════════

  /// Retourne le facteur de tolérance vitesse selon le dénivelé de l'itinéraire.
  /// En descente significative, un vélo peut aller très vite (>50km/h) — on augmente la tolérance.
  /// En montée significative, la vitesse moyenne baisse — on réduit le seuil de suspicion.
  double _getElevationSpeedFactor() {
    double elevM = homeController.elevationGain.value;
    double routeKm =
        (homeController.activeRouteRawDistanceMeters.value / 1000.0)
            .clamp(0.1, 100.0);
    double gradientPercent =
        (elevM / (routeKm * 10.0)).clamp(0.0, 20.0); // % moyen

    // Forte montée (>8%) → vitesse max réduite de 20% (cycliste lent)
    // Forte descente (stockée comme élévation négative potentielle non calculée)
    // On applique une tolérance accrue pour les fortes pentes
    if (gradientPercent > 8.0) return 0.85; // Moins tolérant car montée lente
    if (gradientPercent > 5.0) return 0.92;
    if (gradientPercent > 2.0) return 1.05; // Légère descente possible
    return 1.0; // Plat
  }

  bool _analyzeSpeedCompliance(double speedKmh) {
    _speedHistory.add(speedKmh);
    var mode = homeController.currentTravelMode.value;

    // ---------- DÉTECTION
    // ── Seuils de base ──────────────────────────────────────────────────────
    double maxSpeedWalk = 10.0; // Max marche rapide / jogging
    double maxSpeedBike = 55.0; // Max vélo (descente)
    double carSuspectThreshold = 70.0; // Au-dessus → voiture certaine

    double elevFactor = _getElevationSpeedFactor();

    if (mode == TravelMode.transit) {
      // En transit, on ne veut pas déclencher le système anti-triche pour la vitesse normale,
      // mais on peut détecter des valeurs absurdes (GPS erratique ou simulation).
      if (speedKmh > 150.0) {
        _triggerCarDetected();
        return true;
      }
      return false;
    }

    if (mode == TravelMode.walking) {
      maxSpeedWalk *= elevFactor;

      // ── FENÊTRE VÉLO (12–35 km/h maintenu > 15s) ─────────────────────────
      if (speedKmh > 12.0) {
        if (_highSpeedBurstStartTime == null)
          _highSpeedBurstStartTime = DateTime.now();
        Duration burst = DateTime.now().difference(_highSpeedBurstStartTime!);
        if (burst > const Duration(seconds: 15)) {
          return _handleSpeedViolation(speedKmh, mode);
        }
      } else {
        _highSpeedBurstStartTime = null;
      }

      // ── DÉTECTION VOITURE (>60 km/h) ─────────────────────────────────────
      if (speedKmh > carSuspectThreshold) {
        _collectHighSpeedSample(speedKmh);
        if (_isCarSpeedConfirmed()) {
          _triggerCarDetected();
          return true;
        }
      }

      // ── ANALYSE VARIANCE (comportement robotique) ────────────────────────
      if (speedKmh > 3.0) {
        _recentWalkingSpeeds.add(speedKmh);
        if (_recentWalkingSpeeds.length > 20) _recentWalkingSpeeds.removeAt(0);
        if (_recentWalkingSpeeds.length >= 15) {
          double variance = _calculateVariance(_recentWalkingSpeeds);
          // Variance < 0.2 sur 15 mesures = vitesse trop constante (voiture à faible vitesse)
          double avgSpeed = _recentWalkingSpeeds.reduce((a, b) => a + b) /
              _recentWalkingSpeeds.length;
          if (variance < 0.2 && avgSpeed > 7.0) {
            _handleSpeedViolation(avgSpeed, mode);
          }
        }
      }
    } else if (mode == TravelMode.bicycling) {
      double effectiveMax = maxSpeedBike * elevFactor;

      if (speedKmh > effectiveMax) {
        if (_highSpeedBurstStartTime == null)
          _highSpeedBurstStartTime = DateTime.now();
        Duration burst = DateTime.now().difference(_highSpeedBurstStartTime!);
        // Tolérance plus longue en descente (dénivelé élevé)
        Duration toleranceDuration = elevFactor < 0.95
            ? const Duration(
                seconds: 30) // Montée = moins de tolérance sur dépassement
            : const Duration(seconds: 20);
        if (burst > toleranceDuration) {
          return _handleSpeedViolation(speedKmh, mode);
        }
      } else {
        _highSpeedBurstStartTime = null;
      }

      // Détection voiture sur vélo (>80 km/h maintenu)
      if (speedKmh > 80.0) {
        _collectHighSpeedSample(speedKmh);
        if (_isCarSpeedConfirmed()) {
          _triggerCarDetected();
          return true;
        }
      }
    }

    return false;
  }

  void _triggerDeviationFailure() {
    // On ferme les éventuelles popups existantes
    _closeGetDialog();

    // ── Firebase log : on annule et on signale la raison ──────────────────
    if (_activeTripId != null) {
      _endTripLog(
        status: 'cancelled',
        cheatReason: 'second_deviation_exceeded',
        finalDistanceMeters: homeController.activeRouteRawDistanceMeters.value,
      );
    }

    stopNavigation();

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.cancel_outlined, color: Colors.red, size: 28),
          SizedBox(width: 10),
          Text("Trajet annulé", style: TextStyle(color: Colors.red)),
        ]),
        content: const Text(
          "Vous avez quitté l'itinéraire de secours de plus de 50 mètres.\n\n"
          "Pour des raisons d'équité vis-à-vis des autres utilisateurs, votre trajet a été définitivement annulé.",
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => _closeGetDialog(),
            child: const Text("Compris", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  void _collectHighSpeedSample(double speed) {
    final now = DateTime.now();
    if (_highSpeedWindowStart == null ||
        now.difference(_highSpeedWindowStart!).inSeconds > 10) {
      _highSpeedSamples.clear();
      _highSpeedWindowStart = now;
    }
    _highSpeedSamples.add(speed);
  }

  /// Voiture confirmée si ≥ 5 mesures au-dessus du seuil dans les 10 dernières secondes
  bool _isCarSpeedConfirmed() => _highSpeedSamples.length >= 5;

  bool _handleSpeedViolation(double speed, dynamic currentMode) {
    if (currentMode == TravelMode.transit) return false;

    // ── CAS : Mode Marche, vitesse vélo (12–60 km/h) → proposer switch vélo ─
    if (currentMode == TravelMode.walking && speed > 12 && speed <= 60) {
      _showModeChangePopup(
        title: "Vitesse élevée détectée 🚲",
        content:
            "Vous roulez à ${speed.toStringAsFixed(0)} km/h. Basculer en mode VÉLO ?",
        newMode: TravelMode.bicycling,
        newIcon: Icons.directions_bike,
      );
      return false;
    }

    // ── CAS : Mode Vélo, vitesse voiture (>70 km/h maintenu) → triche ────────
    if (currentMode == TravelMode.bicycling && speed > 70) {
      _triggerCarDetected();
      return true;
    }

    // ── CAS : Vitesse absolument impossible pour vélo (>80 km/h) ─────────────
    if (speed > 80) {
      _triggerCarDetected();
      return true;
    }

    return false;
  }

  /// Déclenche l'annulation pour utilisation de voiture (triche grave)
  void _triggerCarDetected() {
    // Guard anti-doublon
    if (Get.isDialogOpen ?? false) return;

    // ── Firebase log de triche + notification ─────────────────────────────
    _endTripLog(
        status: 'cheat_detected', cheatReason: 'vehicle_speed_violation');
    _showNotification(
      '⚠️ Triche détectée',
      'Vitesse de véhicule motorisé détectée. Trajet annulé.',
      id: 2,
    );
    // ──────────────────────────────────────────────────────────────────────

    stopNavigation();
    speedController.cheatStatus.value = CheatModeStatus.exceededSpeedCheating;
    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.directions_car, color: Colors.red, size: 28),
          SizedBox(width: 10),
          Text("Trajet annulé", style: TextStyle(color: Colors.red)),
        ]),
        content: const Text(
          "Une vitesse compatible avec un véhicule motorisé a été détectée.\n\n"
          "Le trajet a été annulé. Seuls la marche et le vélo sont autorisés pour gagner des Lames.",
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => _closeGetDialog(),
            child: const Text("Compris", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // 📍 SYSTÈME DE DÉVIATION DE ROUTE
  // ══════════════════════════════════════════════════════════════════════════

  void _showDeviationPopup(
      double deviationMeters, double limitMeters, LatLng currentPos) {
    if (_isDeviationDialogOpen) return;
    _isDeviationDialogOpen = true;

    bool isPremium = _activeUserProfile?.isVip ?? false;
    double deviationKm = (deviationMeters / 1000.0);

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.orange, size: 28),
          const SizedBox(width: 10),
          Expanded(
              child: Text(
            "Déviation détectée",
            style: const TextStyle(fontWeight: FontWeight.bold),
          )),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Déviation : ${deviationKm.toStringAsFixed(2)} km",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                        "Limite autorisée : ${(limitMeters / 1000).toStringAsFixed(0)} km${isPremium ? ' (Premium)' : ''}",
                        style:
                            const TextStyle(fontSize: 13, color: Colors.grey)),
                  ]),
            ),
            const SizedBox(height: 12),
            const Text(
              "Vous vous êtes trop éloigné de l'itinéraire prévu.\n"
              "Que souhaitez-vous faire ?",
              style: TextStyle(fontSize: 14),
            ),
            if (!isPremium) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber),
                ),
                child: const Row(children: [
                  Icon(Icons.star, color: Colors.amber, size: 16),
                  SizedBox(width: 6),
                  Expanded(
                      child: Text(
                    "Premium : tolérance de 6 km",
                    style: TextStyle(fontSize: 12, color: Colors.amber),
                  )),
                ]),
              ),
            ],
          ],
        ),
        actions: [
          // ANNULER LE TRAJET
          TextButton.icon(
            icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
            label: const Text("Annuler le trajet",
                style: TextStyle(color: Colors.red)),
            onPressed: () {
              _isDeviationDialogOpen = false;
              _closeGetDialog();
              stopNavigation();
              Future.delayed(const Duration(milliseconds: 150), () {
                Get.snackbar("Trajet annulé", "Votre trajet a été annulé.",
                    backgroundColor: Colors.red, colorText: Colors.white);
              });
            },
          ),
          // DEMI-TOUR → recalculer vers le dernier point sur l'itinéraire
          ElevatedButton.icon(
            icon: const Icon(Icons.u_turn_left),
            label: const Text("Faire demi-tour"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              _closeGetDialog();

              // NOUVEAU : On grille la chance unique
              _hasUsedManualRecalculate = true;

              _recalculateToLastOnRoutePoint(currentPos).then((_) {
                _isDeviationDialogOpen = false;
                // Petit bonus UX : prévenir l'utilisateur de la sanction
                Get.snackbar(
                  "Dernière chance ⚠️",
                  "Restez sur ce tracé. Toute sortie de plus de 50m annulera le trajet.",
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                  duration: const Duration(seconds: 5),
                );
              }).catchError((e) {
                debugPrint("❌ Erreur recalcul (demi-tour): $e");
                _isDeviationDialogOpen = false;
              });
            },
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  void _showStayChallengeNotification(String title, String message) {
    homeController._safeSnackbar(
      title,
      message,
      backgroundColor: Colors.blueGrey.shade900.withOpacity(0.9),
      colorText: Colors.white,
      duration: const Duration(seconds: 2),
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  void _showStayChallengeCompletionDialog() {
    if (Get.isDialogOpen ?? false) return;

    Get.dialog(
      AlertDialog(
        title: const Text('Défi terminé'),
        content: const Text(
            '🎉 Félicitations ! Vous avez validé votre défi de zone. Bravo !'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('OK'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  void _showCriticalModal(String title, String message) {
    if (Get.isDialogOpen ?? false) return;

    Get.dialog(
      AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => _closeGetDialog(),
            child: const Text('OK'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  /// Recalcule l'itinéraire depuis la position actuelle vers la destination finale
  /// Recalcule l'itinéraire depuis la position actuelle vers la destination finale
  Future<void> _recalculateToLastOnRoutePoint(LatLng currentPos) async {
    final destination = homeController.destinationCoordinates;
    _currentStepIndex = 0;
    _lastAutoRecalculateTime = DateTime.now();
    homeController.polylineCoordinates.clear();
    directions.clear();

    // CORRECTION : On demande instantanément la dernière direction (heading) au GPS
    double bearing = 0.0;
    try {
      Position? lastPos = await Geolocator.getLastKnownPosition();
      bearing = lastPos?.heading ?? 0.0;
    } catch (_) {}

    // Appeler drawRoute et attendre sa complétude
    await homeController.drawRoute(
      destination,
      origin: currentPos,
      currentBearing: bearing, // <-- ON PASSE LA DIRECTION ICI
    );

    // CORRECTION: Réinitialiser les variables APRÈS que drawRoute ait terminé
    // Réinitialiser à null - sera défini au premier point GPS du nouveau trajet
    _cumulatedDeviationMeters = 0.0;
    _lastOnRoutePosition = null;
    _lastOnRouteTime = DateTime.now();

    Get.snackbar(
      "Itinéraire recalculé",
      "Nouvelle trajectoire trouvée.",
      backgroundColor: Colors.green,
      colorText: Colors.white,
      duration: const Duration(seconds: 3),
      icon: const Icon(Icons.u_turn_left, color: Colors.white),
    );
  }

  // Calcul mathématique de la variance
  double _calculateVariance(List<double> values) {
    if (values.isEmpty) return 0.0;
    double mean = values.reduce((a, b) => a + b) / values.length;
    double variance =
        values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) /
            values.length;
    return variance;
  }

  void _showModeChangePopup(
      {required String title,
      required String content,
      required TravelMode newMode,
      required IconData newIcon}) {
    // Guard anti-doublon
    if (_isSwitchingModeDialogTrace) return;
    _isSwitchingModeDialogTrace = true;
    _highSpeedBurstStartTime = null;

    Get.dialog(
      AlertDialog(
        title: Row(children: [
          Icon(Icons.speed, color: Colors.orange),
          SizedBox(width: 10),
          Expanded(child: Text(title, style: TextStyle(fontSize: 18)))
        ]),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () {
              _isSwitchingModeDialogTrace = false;
              _closeGetDialog();
              _triggerCheatDetection("Mode inadapté à la vitesse.");
            },
            child: const Text("Non, arrêter"),
          ),
          ElevatedButton.icon(
            icon: Icon(newIcon, size: 16),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              homeController.currentTravelMode.value = newMode;
              speedController.setExpectedTravelMode(newMode);
              _speedHistory.clear();
              _highSpeedBurstStartTime = null;
              _isSwitchingModeDialogTrace = false;
              _closeGetDialog();
              Future.delayed(const Duration(milliseconds: 150), () {
                Get.snackbar("Mode changé", "Calculs ajustés pour ce mode.",
                    backgroundColor: Colors.green,
                    colorText: Colors.white,
                    duration: const Duration(seconds: 3));
              });
            },
            label: const Text("Oui, changer"),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  void _updateInstruction(LatLng userPos) {
    if (directions.isEmpty) return;

    // ─ DÉTERMINER LE TYPE D'ITINÉRAIRE (OSRM vs Google) ──────────────
    final firstStep = directions.isNotEmpty ? directions.first : null;
    bool isOsrmRoute = firstStep != null &&
        (firstStep.containsKey('maneuver') ||
            firstStep.containsKey('instruction'));

    // ──────────────────────────────────────────────────────────────────
    // CAS GOOGLE DIRECTIONS / TRANSIT (avec end_location, start_location)
    // ──────────────────────────────────────────────────────────────────
    if (!isOsrmRoute) {
      // ── 1. Trouver l'étape la plus proche DEVANT nous ──────────────
      int bestStep = _currentStepIndex;
      double bestDist = double.maxFinite;

      for (int i = _currentStepIndex; i < directions.length; i++) {
        final step = directions[i];
        final endLoc = step['end_location'];
        if (endLoc == null) continue;

        double endLat = (endLoc['lat'] as num?)?.toDouble() ?? 0.0;
        double endLng = (endLoc['lng'] as num?)?.toDouble() ?? 0.0;

        double distToEnd = Geolocator.distanceBetween(
            userPos.latitude, userPos.longitude, endLat, endLng);

        if (distToEnd < bestDist) {
          bestDist = distToEnd;
          bestStep = i;
        }
      }

      if (bestDist < 40.0 && bestStep + 1 < directions.length) {
        bestStep++;
      }

      // ── 3. Snackbars de transition lors du changement d'étape ───────
      if (bestStep != _currentStepIndex) {
        final oldStep = directions[_currentStepIndex];
        final newStep = directions[bestStep];

        final String oldMode = (oldStep['travel_mode'] ?? '') as String;
        final String newMode = (newStep['travel_mode'] ?? '') as String;

        if (newMode == 'TRANSIT') {
          final String line =
              (newStep['transit_details']?['line']?['short_name'] ?? '')
                  as String;
          final String depStop =
              (newStep['transit_details']?['departure_stop']?['name'] ?? '')
                  as String;

          Get.snackbar(
            oldMode == 'TRANSIT' ? "🔄 Correspondance" : "🚌 Embarquement",
            depStop.isNotEmpty
                ? "Prenez la ligne $line à $depStop."
                : "Prenez la ligne $line.",
            backgroundColor: oldMode == 'TRANSIT'
                ? Colors.orange.shade700
                : Colors.blue.shade700,
            colorText: Colors.white,
            duration: const Duration(seconds: 4),
            snackPosition: SnackPosition.BOTTOM,
          );

          // -----------------------------------------------------------------
          // 🔴 FIX CRUCIAL : MISE À JOUR DE L'ARRÊT POUR LA CORRESPONDANCE
          // -----------------------------------------------------------------
          double nextLat = (newStep['start_location']['lat'] as num).toDouble();
          double nextLng = (newStep['start_location']['lng'] as num).toDouble();

          DateTime? nextDepartureTime;
          if (newStep['transit_details']?['departure_time']?['value'] != null) {
            int val =
                (newStep['transit_details']['departure_time']['value'] as num)
                    .toInt();
            nextDepartureTime = DateTime.fromMillisecondsSinceEpoch(val * 1000);
          }

          // On met à jour le traceur de bus pour le nouveau départ !
          setTargetTransitStop(LatLng(nextLat, nextLng), nextDepartureTime);
          // -----------------------------------------------------------------
        } else if (oldMode == 'TRANSIT' && newMode == 'WALKING') {
          final String arrStop =
              (oldStep['transit_details']?['arrival_stop']?['name'] ?? '')
                  as String;
          Get.snackbar(
            "🚶 Descente",
            arrStop.isNotEmpty
                ? "Descendez à $arrStop. Continuez à pied."
                : "Vous êtes arrivé(e) à votre arrêt. Continuez à pied.",
            backgroundColor: Colors.green.shade700,
            colorText: Colors.white,
            duration: const Duration(seconds: 4),
            snackPosition: SnackPosition.BOTTOM,
          );
        }

        _currentStepIndex = bestStep;
      }

      // ── 4. Construction du texte d'instruction ─────────────────────
      final step = directions[_currentStepIndex];
      final String mode = (step['travel_mode'] ?? '') as String;
      String instruction = "";

      double startLat =
          (step['start_location']?['lat'] as num?)?.toDouble() ?? 0.0;
      double startLng =
          (step['start_location']?['lng'] as num?)?.toDouble() ?? 0.0;
      double distToStart = Geolocator.distanceBetween(
          userPos.latitude, userPos.longitude, startLat, startLng);

      double endLat = (step['end_location']?['lat'] as num?)?.toDouble() ?? 0.0;
      double endLng = (step['end_location']?['lng'] as num?)?.toDouble() ?? 0.0;
      double distToEnd = Geolocator.distanceBetween(
          userPos.latitude, userPos.longitude, endLat, endLng);

      if (mode == 'TRANSIT') {
        final details = step['transit_details'];
        final String line = (details?['line']?['short_name'] ?? '') as String;
        final String headsign = (details?['headsign'] ?? 'Terminus') as String;
        final String arrStop =
            (details?['arrival_stop']?['name'] ?? '') as String;
        final String depStop =
            (details?['departure_stop']?['name'] ?? '') as String;
        final int? numStops = details?['num_stops'] as int?;

        if (distToStart < 80.0 && distToEnd > 200.0) {
          // À l'arrêt en attente du bus
          if (_targetBusStopSchedule != null) {
            String timeStr =
                DateFormat('HH:mm').format(_targetBusStopSchedule!);
            Duration diff = DateTime.now().difference(_targetBusStopSchedule!);
            int diffMin = diff.inMinutes;

            if (diffMin < -5) {
              instruction =
                  "⏳ À l'arrêt $depStop - Bus en avance (prévu à $timeStr)";
            } else if (diffMin >= -5 && diffMin <= 5) {
              instruction =
                  "🚏 À l'arrêt $depStop - Bus à l'heure (prévu à $timeStr)";
            } else if (diffMin > 5 && diffMin <= 15) {
              instruction =
                  "⏱️ À l'arrêt $depStop - Bus légèrement en retard (prévu à $timeStr)";
            } else {
              instruction =
                  "🚨 À l'arrêt $depStop - Bus très en retard! (prévu à $timeStr)";
            }
          } else {
            instruction = "🚏 À l'arrêt $depStop (Ligne $line) - En attente";
          }
        } else if (distToEnd < 100.0) {
          instruction =
              "🛑 Arrivée imminente à $arrStop (Ligne $line). Préparez-vous à descendre !";
        } else {
          final String stopsInfo =
              numStops != null ? " · $numStops arrêt(s)" : "";
          instruction = "🚌 Ligne $line → $arrStop (Dir. $headsign$stopsInfo)";
        }
      } else {
        // WALKING, DRIVING, BICYCLING (Google)
        if (step['html_instructions'] != null) {
          instruction = _cleanHtml(step['html_instructions'].toString());
        } else if (step['instructions'] != null) {
          instruction = step['instructions'].toString();
        }

        // Si la prochaine étape est un embarquement bus → information contextuelle
        if (_currentStepIndex + 1 < directions.length) {
          final nextStep = directions[_currentStepIndex + 1];
          if (nextStep['travel_mode'] == 'TRANSIT') {
            final String nextLine =
                (nextStep['transit_details']?['line']?['short_name'] ?? '')
                    as String;
            final String nextStop =
                (nextStep['transit_details']?['departure_stop']?['name'] ?? '')
                    as String;
            if (nextStop.isNotEmpty) {
              instruction =
                  "🚶 Rejoignez l'arrêt $nextStop (Ligne $nextLine) · ${distToEnd.round()} m";
            } else if (instruction.isNotEmpty && distToEnd > 15) {
              instruction += " (${distToEnd.round()} m)";
            }
          } else if (instruction.isNotEmpty && distToEnd > 15) {
            instruction += " (${distToEnd.round()} m)";
          }
        } else if (instruction.isNotEmpty && distToEnd > 15) {
          instruction += " (${distToEnd.round()} m)";
        }
      }

      if (kDebugMode) {
        debugPrint("[Nav] Instruction (#$_currentStepIndex): $instruction");
      }
      currentInstructionText.value = instruction;
    }
    // ──────────────────────────────────────────────────────────────────
    // CAS OSRM (avec maneuver, name, instruction) - CORRIGÉ
    // ──────────────────────────────────────────────────────────────────
    else {
      // 1. Trouver l'étape la plus proche de notre position actuelle
      int bestStep = _currentStepIndex;
      double bestDist = double.maxFinite;

      for (int i = _currentStepIndex; i < directions.length; i++) {
        final s = directions[i];
        double mLat = 0.0;
        double mLng = 0.0;

        // OSRM stocke les coordonnées dans ['maneuver']['location'] -> [lng, lat]
        if (s['maneuver'] != null && s['maneuver']['location'] != null) {
          final loc = s['maneuver']['location'];
          if (loc is List && loc.length >= 2) {
            mLng = (loc[0] as num).toDouble();
            mLat = (loc[1] as num).toDouble();
          }
        }

        // Si l'étape possède des coordonnées valides
        if (mLat != 0.0 && mLng != 0.0) {
          double d = Geolocator.distanceBetween(
              userPos.latitude, userPos.longitude, mLat, mLng);
          if (d < bestDist) {
            bestDist = d;
            bestStep = i;
          }
        }
      }

      // 2. Si on s'approche à moins de 40m de la manœuvre actuelle, on passe à la suivante
      if (bestDist < 40.0 && bestStep + 1 < directions.length) {
        bestStep++;
      }

      _currentStepIndex = bestStep;

      // 3. Construction du texte d'instruction
      final step = directions[_currentStepIndex];
      String instruction = "";

      if (step['instruction'] != null) {
        instruction = step['instruction'].toString();
      } else if (step['maneuver'] != null && step['maneuver'] is Map) {
        final maneuver = step['maneuver'];
        String type = maneuver['type']?.toString() ?? '';
        String modifier = maneuver['modifier']?.toString() ?? '';

        instruction = _translateManeuver(type, modifier);

        // Ajout du nom de la rue s'il existe et n'est pas vide
        if (step['name'] != null && step['name'].toString().trim().isNotEmpty) {
          instruction += " sur ${step['name'].toString()}";
        }
      } else if (step['name'] != null) {
        instruction = "Continuer sur ${step['name'].toString()}";
      }

      currentInstructionText.value =
          instruction.isNotEmpty ? instruction : "Navigation en cours...";
    }
  }

  /// Traduit un type de manœuvre OSRM en texte lisible
  String _translateManeuver(String type, String modifier) {
    switch (type) {
      case 'turn':
        switch (modifier) {
          case 'left':
            return 'Tourner à gauche';
          case 'right':
            return 'Tourner à droite';
          case 'slight left':
            return 'Légèrement à gauche';
          case 'slight right':
            return 'Légèrement à droite';
          case 'sharp left':
            return 'Virage serré à gauche';
          case 'sharp right':
            return 'Virage serré à droite';
          case 'uturn':
            return 'Faire demi-tour';
          default:
            return 'Tourner';
        }
      case 'depart':
        return modifier.isNotEmpty
            ? 'Partir vers ${modifier == "left" ? "la gauche" : modifier == "right" ? "la droite" : modifier}'
            : 'Départ';
      case 'arrive':
        return 'Vous êtes arrivé(e)';
      case 'merge':
        return 'Continuer tout droit';
      case 'on ramp':
        return 'Prendre la bretelle';
      case 'off ramp':
        return 'Sortir';
      case 'fork':
        return modifier.contains('left')
            ? 'Rester à gauche'
            : 'Rester à droite';
      case 'end of road':
        return modifier.contains('left')
            ? 'Tourner à gauche en fin de route'
            : 'Tourner à droite en fin de route';
      case 'roundabout':
        return 'Prendre le rond-point';
      case 'rotary':
        return 'Prendre le rond-point';
      case 'continue':
        return 'Continuer tout droit';
      default:
        return type.isNotEmpty ? type : 'Continuer';
    }
  }

  void _checkBusStopArrivalLogic() {
    _hasReachedBusStop = true;
    if (_targetBusStopSchedule == null) {
      Get.snackbar("À l'arrêt 🚏", "En attente du bus...",
          backgroundColor: Colors.blue, colorText: Colors.white);
      return;
    }

    DateTime now = DateTime.now();
    Duration diff = now.difference(_targetBusStopSchedule!);
    int diffMinutes = diff.inMinutes;

    // --- LOGIQUE DE TOLÉRANCE INTELLIGENTE (Statut réel affiché) ---
    bool isVip = _activeUserProfile?.isVip ?? false;

    if (diffMinutes < -5) {
      // En avance
      Get.snackbar(
        "En avance ! ⏳",
        "Votre bus est prévu dans ${diffMinutes.abs()} min. Détendez-vous !",
        backgroundColor: Colors.blue.shade600,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
      currentInstructionText.value =
          "Attente du bus prévu à ${DateFormat('HH:mm').format(_targetBusStopSchedule!)}";
    } else if (diffMinutes <= 5) {
      // À l'heure ou très léger retard (<= 5 min)
      Get.snackbar(
        "À l'arrêt 🚏",
        "Le bus ne devrait pas tarder.",
        backgroundColor: Colors.green.shade600,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
      currentInstructionText.value =
          "Attente du bus prévu à ${DateFormat('HH:mm').format(_targetBusStopSchedule!)}";
    } else if (diffMinutes <= 15) {
      // Retard modéré
      Get.snackbar(
        "Retard modéré",
        "Le bus est retardé d'environ $diffMinutes min.${isVip ? " (Validé avec tolérance VIP)" : ""}",
        backgroundColor: Colors.orange.shade600,
        colorText: Colors.white,
        duration: const Duration(seconds: 4),
      );
      currentInstructionText.value = "Bus retardé d'environ $diffMinutes min.";
    } else if (diffMinutes <= 30) {
      // Retard important
      Get.snackbar(
        "Retard important",
        "Le bus a ${diffMinutes} min de retard.${isVip ? " (Validé avec tolérance VIP)" : ""}",
        backgroundColor: Colors.orange.shade700,
        colorText: Colors.white,
        duration: const Duration(seconds: 5),
      );
      currentInstructionText.value = "Bus en retard (~$diffMinutes min).";
    } else if (diffMinutes <= 45) {
      // Très important
      Get.snackbar(
        "Gros retard",
        "Le bus a plus de ${diffMinutes} min de retard. Il peut être plus rentable d'en prendre un autre.",
        backgroundColor: Colors.red.shade600,
        colorText: Colors.white,
        duration: const Duration(seconds: 6),
      );
      currentInstructionText.value = "Gros retard du bus (~$diffMinutes min).";
    } else {
      // Retard extrême ou absence de service
      _showNewSchedulePopup();
    }
  }

  void _closeGetDialog() {
    if (Get.isSnackbarOpen) {
      Get.closeCurrentSnackbar();
    }
    if (Get.isDialogOpen ?? false) {
      Get.back();
    }
  }

  void _showNewSchedulePopup() {
    // Guard anti-doublon : évite que le stream GPS rouvre le popup
    if (_isScheduleDialogOpen) return;
    _isScheduleDialogOpen = true;

    DateTime baseTime = _targetBusStopSchedule ?? DateTime.now();
    DateTime next1 = baseTime.add(const Duration(minutes: 15));
    DateTime next2 = baseTime.add(const Duration(minutes: 30));

    Get.dialog(
      AlertDialog(
        title: Row(children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 10),
          Text("Horaire Manqué")
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Vous êtes hors de la tolérance de 10 min."),
            const SizedBox(height: 15),
            const Text("Prochains passages estimés :",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.directions_bus, color: Colors.blue),
              title: Text(DateFormat('HH:mm').format(next1)),
              subtitle: const Text("Ligne actuelle"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () => _updateScheduleAndResume(next1),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.directions_bus, color: Colors.grey),
              title: Text(DateFormat('HH:mm').format(next2)),
              subtitle: const Text("Alternative"),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14),
              onTap: () => _updateScheduleAndResume(next2),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => _updateScheduleAndResume(next1),
            child: const Text("OK, j'attends ici"),
          ),
          TextButton(
            onPressed: () {
              _isScheduleDialogOpen = false;
              _closeGetDialog();
              stopNavigation();
            },
            child: const Text("Arrêter GPS"),
          ),
          TextButton(
            onPressed: () {
              _isScheduleDialogOpen = false;
              _closeGetDialog();
              stopNavigation();
              homeController.clearDestination();
            },
            child: const Text("Changer dest."),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  void _updateScheduleAndResume(DateTime newTime) {
    _isScheduleDialogOpen = false;
    _closeGetDialog();
    _targetBusStopSchedule = newTime;

    // CRITIQUE : L'utilisateur EST à l'arrêt. On ne veut plus relancer la détection d'arrivée.
    _hasReachedBusStop = true;

    // On met à jour les logs de navigation directement
    currentInstructionText.value =
        "Attente du bus jusqu'à ${DateFormat('HH:mm').format(newTime)}";

    Future.delayed(const Duration(milliseconds: 150), () {
      Get.snackbar(
        "Nouvel horaire",
        "Attente jusqu'à ${DateFormat('HH:mm').format(newTime)}",
        backgroundColor: Colors.blueAccent,
        colorText: Colors.white,
        duration: const Duration(seconds: 3),
      );
    });
  }

  void _triggerCheatDetection(String reason) {
    stopNavigation();
    speedController.cheatStatus.value = CheatModeStatus.exceededSpeedCheating;
    Get.snackbar("Navigation Interrompue", "Anomalie détectée : $reason",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5));
  }

  void _checkRouteLogic(LatLng raw, LatLng snapped) {
    double distDest = Geolocator.distanceBetween(
        raw.latitude,
        raw.longitude,
        homeController.destinationCoordinates.latitude,
        homeController.destinationCoordinates.longitude);

    if (distDest < 40 && !homeController.arrived.value) {
      homeController.arrived.value = true;
      _finishTripWithRecap();
    }
  }

  void _showArrivalRecapPopup(Duration duration, double avgSpeed,
      {bool isChallenge = false}) {
    String modeStr =
        homeController.currentTravelMode.value == TravelMode.walking
            ? "Marche 🚶"
            : "Vélo 🚲";
    if (homeController.currentTravelMode.value == TravelMode.transit)
      modeStr = "Transport 🚌";

    // ── Popup DÉFI : pas de lames pour le trajet ──────────────────────────
    if (isChallenge) {
      final challenge = activeChallenge;
      final bool isLastStep = challenge == null ||
          (challenge.currentStep + 1) >=
              (challenge.visitCount ?? challenge.totalSteps ?? 1);

      showDialog(
        context: Get.context!,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: const [
              Icon(Icons.emoji_events, size: 50, color: Colors.purple),
              SizedBox(height: 10),
              Text("Destination atteinte !",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Divider(),
              _buildRecapRow("Mode", modeStr),
              _buildRecapRow("Temps",
                  "${duration.inMinutes} min ${duration.inSeconds % 60} s"),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.purple.withOpacity(0.4))),
                child: Column(children: [
                  Text(
                    isLastStep ? "🎉 Défi complété !" : "✅ Étape accomplie !",
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isLastStep
                        ? "Récupérez votre récompense dans l'onglet Mes Défis."
                        : "Continuez votre défi dans l'onglet Mes Défis.",
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
              const SizedBox(height: 10),
              const Text(
                "Étape validée !\nRécupérez votre récompense de défi finale dans l'onglet Mes Défis.",
                style: TextStyle(
                    fontSize: 12,
                    color: primaryGreen,
                    fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              onPressed: () {
                Navigator.pop(ctx);
                // On ne veut pas créditer de lames automatiquement ici (défi déjà traité)
                _distributeRewardsAndCallbacks(forceChallenge: true);
              },
              child: const Text("Voir mes Défis",
                  style: TextStyle(fontSize: 15, color: Colors.white)),
            ),
          ],
        ),
      );
      return;
    }

    // ── Popup TRAJET NORMAL ────────────────────────────────────────────────
    int lamesGagnees = homeController.activeRouteEstimatedGain.value;

    showDialog(
      context: Get.context!,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: const [
            Icon(Icons.emoji_events, size: 50, color: Colors.amber),
            SizedBox(height: 10),
            Text("Trajet Terminé !",
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            _buildRecapRow("Mode validé", modeStr),
            _buildRecapRow("Temps total",
                "${duration.inMinutes} min ${duration.inSeconds % 60} s"),
            _buildRecapRow(
                "Vitesse Moy.", "${avgSpeed.toStringAsFixed(1)} km/h"),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.green)),
              child: Column(
                children: [
                  const Text("Gain Total",
                      style: TextStyle(
                          color: Colors.green, fontWeight: FontWeight.bold)),
                  Text("+$lamesGagnees Lames",
                      style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.green)),
                ],
              ),
            )
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            onPressed: () {
              Navigator.pop(ctx);
              _distributeRewardsAndCallbacks();
            },
            child: const Text("Récupérer mes Lames",
                style: TextStyle(
                    fontSize: 16,
                    color: Colors.white,
                    fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _buildRecapRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }

  void stopNavigation({bool keepChallengeCallbacks = false}) {
    positionStream?.cancel();
    _lastGpsReceiveTime = null;
    homeController.stopFluidNavigation();
    _lastPositionTime = null;
    _lastSnappedPos = null;
    _transitOffRouteSince = null;
    _transitOffRouteLongWarning = false;

    // CORRECTION : Ne pas écraser le défi si on demande de le garder pour la popup/minuteur
    if (!keepChallengeCallbacks) {
      activeChallenge = null;
    }

    // ── Firebase : log annulation si trajet en cours ─────────────────────
    if (_activeTripId != null) {
      _endTripLog(
        status: 'cancelled',
        finalDistanceMeters: homeController.activeRouteRawDistanceMeters.value,
      );
    }
    // ──────────────────────────────────────────────────────────────────────

    // ── Effacer l'état de navigation sauvegardé ──────────────────────────
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('active_nav_running');
    });

    homeController.clearDestination();
    isCameraLocked.value = true;
    isOnBus.value = false;
    _transitMonitor = null;
    speedController.cheatStatus.value = CheatModeStatus.none;
    _speedHistory.clear();
    _recentWalkingSpeeds.clear();
    _highSpeedBurstStartTime = null;
    _isSwitchingModeDialogTrace = false;
    _isDeviationDialogOpen = false;
    _isScheduleDialogOpen = false;
    _currentStepIndex = 0;
    _cumulatedDeviationMeters = 0.0;
    FlutterBackgroundService().invoke("resume_background_tracking");
    print("📡 Envoi signal: resume_background_tracking");
  }

  void _finishTripWithRecap() {
    Duration duration = DateTime.now().difference(_startTime ?? DateTime.now());
    double avgSpeed = 0.0;
    if (_speedHistory.isNotEmpty)
      avgSpeed = _speedHistory.reduce((a, b) => a + b) / _speedHistory.length;

    var mode = homeController.currentTravelMode.value;
    double maxAvgAllowed = mode == TravelMode.walking
        ? 12.0
        : (mode == TravelMode.bicycling
            ? 38.0 / _getElevationSpeedFactor()
            : 1000.0);

    if (avgSpeed > maxAvgAllowed && mode != TravelMode.transit) {
      _triggerCarDetected();
      return;
    }

    final bool isChallengeTrip = activeChallenge != null;
    int lamesGagnees = homeController.activeRouteEstimatedGain.value;

    _endTripLog(
        status: 'completed',
        finalDistanceMeters: homeController.activeRouteRawDistanceMeters.value,
        lamesEarned: lamesGagnees);
    _updateStatsAndCheckBadges(
        homeController.activeRouteRawDistanceMeters.value);

    // --- NOUVELLE LOGIQUE MINUTEUR ---
    if (isChallengeTrip &&
        activeChallenge != null &&
        (activeChallenge!.stayDurationSeconds ?? 0) > 0) {
      _showNotification(
          '📍 Zone atteinte', 'Restez dans la zone pour valider le défi !',
          id: 3);
      startIndependentStayTimer(activeChallenge!);
      stopNavigation(
          keepChallengeCallbacks:
              true); // On garde le callback pour la fin du timer !
    } else {
      _showNotification('🏁 Arrivée !', 'Trajet terminé !', id: 3);
      stopNavigation(
          keepChallengeCallbacks:
              isChallengeTrip); // On garde le callback pour la popup !
      _showArrivalRecapPopup(duration, avgSpeed, isChallenge: isChallengeTrip);
    }
  }

  void startIndependentStayTimer(Challenge challenge) {
    stayChallenge = challenge;
    staySecondsRemaining.value = challenge.stayDurationSeconds ?? 180;
    isStayTimerActive.value = true;
    isUserInStayZone.value = true; // On suppose qu'il y est en arrivant

    _showStayChallengeNotification('Défi de zone démarré',
        'Restez dans la zone pendant ${staySecondsRemaining.value} secondes pour valider.');

    // Dessine le cercle
    homeController.drawCircleOnMap(
        LatLng(challenge.latitude!, challenge.longitude!), 10.0);

    independentStayStream?.cancel();
    independentStayTimer?.cancel();

    // Flux GPS indépendant (tourne même si on coupe la navigation)
    independentStayStream = Geolocator.getPositionStream(
            locationSettings: LocationSettings(
                accuracy: LocationAccuracy.bestForNavigation,
                distanceFilter: LOCATION_DISTANCE_FILTER_METERS.toInt()))
        .listen((pos) {
      double dist = Geolocator.distanceBetween(pos.latitude, pos.longitude,
          challenge.latitude!, challenge.longitude!);
      bool wasInZone = isUserInStayZone.value;
      bool isNowInZone = dist <= STAY_ZONE_TOLERANCE_METERS;
      isUserInStayZone.value = isNowInZone;

      if (isNowInZone && !wasInZone) {
        _showStayChallengeNotification('Restez sur place',
            'Vous êtes revenu dans la zone. Continuez le défi.');
      } else if (!isNowInZone && wasInZone) {
        _showStayChallengeNotification('⚠️ Hors zone',
            'Vous avez quitté la zone. Revenez pour continuer le défi.');
      }

      if (isUserInStayZone.value) {
        staySecondsRemaining.value--;
        if (staySecondsRemaining.value % 10 == 0) {
          _showStayChallengeNotification(
              'Défi en cours', 'Temps restant ${staySecondsRemaining.value}s.');
        }

        if (staySecondsRemaining.value <= 0) {
          independentStayTimer?.cancel();
          independentStayStream?.cancel();
          isStayTimerActive.value = false;

          // CORRECTION : Défi complété !
          _onChallengeReached?.call(challenge);
          activeChallenge = null;

          _showStayChallengeCompletionDialog();
          Get.snackbar(
            "✅ Étape validée !",
            "Temps sur place validé.",
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: const Duration(seconds: 5),
          );
        }
      }
    });
  }

  void _distributeRewardsAndCallbacks({bool forceChallenge = false}) {
    final bool isChallenge = activeChallenge != null || forceChallenge;

    if (onStoreDestinationReached != null) {
      onStoreDestinationReached!();
    } else if (activeChallenge != null && _onChallengeReached != null) {
      // CORRECTION : On exécute le callback pour les défis toujours, y compris après le popup.
      // Ceci garantit que le statut passe de inProgress à completedPendingReward dans l'onglet Défis.
      _onChallengeReached!(activeChallenge!);
    } else if (activeWorkCommuteType != null && _onWorkReached != null) {
      _onWorkReached!(activeWorkCommuteType!);
    } else if (!forceChallenge) {
      // CORRECTION : On donne le gain de trajet seulement si ce n'est pas un défi
      int gain = homeController.activeRouteEstimatedGain.value;
      if (onNormalDestinationReached != null) {
        onNormalDestinationReached!(gain);
      }
    }

    // Nettoyage final
    activeChallenge = null;

    homeController.clearDestination();
    speedController.cheatStatus.value = CheatModeStatus.none;

    SharedPreferences.getInstance().then((prefs) {
      prefs.remove('active_nav_running');
    });

    // Seuls les trajets classiques (hors défis) déclenchent le popup "Lames ajoutées"
    if (!isChallenge) {
      Future.delayed(const Duration(milliseconds: 150), () {
        Get.snackbar("Félicitations 🎉", "Lames ajoutées !",
            backgroundColor: Colors.green,
            colorText: Colors.white,
            duration: const Duration(seconds: 3));
      });
    }
  }
}

class TransitLeg {
  final String instructions;
  final TravelMode? travelMode;
  final LatLng startLocation;
  final LatLng endLocation;
  final String distance;
  final String duration;
  final List<LatLng> polylinePoints;

  final MyTransitDetails? transitDetails;

  TransitLeg({
    required this.instructions,
    this.travelMode,
    required this.startLocation,
    required this.endLocation,
    required this.distance,
    required this.duration,
    required this.polylinePoints,
    this.transitDetails,
  });

  bool get isWalking => travelMode == TravelMode.walking;
  bool get isTransit => travelMode == TravelMode.transit;
}

// MODIFIÉ: Logique de surveillance des transports en commun
enum TransitIssue { none, offRoute }

class TransitMonitor {
  final Function(String) onWarning;
  final Function()? onBackOnRoute;
  TransitIssue _lastWarningSent = TransitIssue.none;

  TransitMonitor({required this.onWarning, this.onBackOnRoute});

  /// Vérifie si l'utilisateur est sur le tracé.
  /// Retourne `true` si sur la route, `false` si dévié.
  bool checkPosition(LatLng userPosition, List<LatLng> routePolyline) {
    bool isOnRoute = gmaps_utils.PolyUtils.isLocationOnEdgeTolerance(
        gmaps_utils.Point(userPosition.latitude, userPosition.longitude),
        routePolyline
            .map((p) => gmaps_utils.Point(p.latitude, p.longitude))
            .toList(),
        false,
        30.0 // Tolérance de 30 mètres
        );

    if (!isOnRoute) {
      if (_lastWarningSent != TransitIssue.offRoute) {
        onWarning(
            "Attention, vous semblez avoir dévié de l'itinéraire du transport en commun.");
        _lastWarningSent = TransitIssue.offRoute;
      }
    } else {
      if (_lastWarningSent == TransitIssue.offRoute) {
        _lastWarningSent = TransitIssue.none;
        onBackOnRoute?.call();
      }
    }

    return isOnRoute;
  }

  void reset() {
    _lastWarningSent = TransitIssue.none;
  }

  void dispose() {
    // Pas de timer à annuler dans cette version
  }
}

// NOUVEAU: Enum pour gérer les phases de validation d'une étape en transport en commun
enum TransitLegPhase { BeforeBoarding, Onboard }

class SpeedometerDisplay extends StatelessWidget {
  final SpeedController speedController = Get.find();
  final HomeController homeController = Get.find();
  final NavigationController navigationController = Get.find();

  SpeedometerDisplay({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (homeController.mapStatus.value != Constants.onDestination) {
        return const SizedBox.shrink();
      }

      final speed = speedController.currentSpeed.value;
      final cheatStatus = speedController.cheatStatus.value;
      final cheatMessage = speedController.cheatWarningMessage.value;
      final gpsIntervalMs = navigationController.timeBetweenGpsMs.value;
      final gpsProcessingMs = navigationController.gpsProcessingMs.value;
      final gpsLatencyMs = navigationController.gpsLatencyMs.value; // 🚀 NOUVEAU

      Color displayColor = Colors.black;
      if (cheatStatus == CheatModeStatus.exceededSpeedWarning)
        displayColor = Colors.orange;
      if (cheatStatus == CheatModeStatus.exceededSpeedCheating)
        displayColor = Colors.red;

      // Couleur du GPS selon la qualité du signal
      Color gpsColor = Colors.greenAccent;
      if (gpsIntervalMs > 2000)
        gpsColor = Colors.redAccent;
      else if (gpsIntervalMs > 1200) gpsColor = Colors.orangeAccent;

      return Positioned(
        top: MediaQuery.of(context).padding.top + 120,
        left: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── VITESSE ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                border: Border.all(
                  color: displayColor == Colors.black
                      ? Colors.transparent
                      : displayColor,
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    speed.toStringAsFixed(0),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: displayColor,
                      height: 1.0,
                    ),
                  ),
                  const Text('km/h',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey)),
                ],
              ),
            ),
            if (cheatMessage.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 5),
                padding: const EdgeInsets.all(5),
                color: displayColor,
                child: Text(cheatMessage,
                    style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
            const SizedBox(height: 8),
            // ── TEMPS GPS EN MILLISECONDES ──
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.withOpacity(0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "⏱️ GPS CAPTATION",
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Intervalle entre 2 points GPS
                  Row(
                    children: [
                      Icon(Icons.gps_fixed, color: gpsColor, size: 14),
                      const SizedBox(width: 6),
                      Text(
                        "Intervalle: ",
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        "${gpsIntervalMs} ms",
                        style: TextStyle(
                          color: gpsColor,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // NOUVEAU: Latence exacte du fix GPS
                  Row(
                    children: [
                      Icon(Icons.timer, color: Colors.cyanAccent, size: 14),
                      const SizedBox(width: 6),
                      Text("Latence: ",
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 11)),
                      Text(
                        "${gpsLatencyMs} ms",
                        style: TextStyle(
                          color: Colors.cyanAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Temps de traitement
                  Row(
                    children: [
                      Icon(Icons.memory,
                          color: gpsProcessingMs > 50
                              ? Colors.orangeAccent
                              : Colors.greenAccent,
                          size: 14),
                      const SizedBox(width: 6),
                      Text(
                        "Traitement: ",
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        "${gpsProcessingMs} ms",
                        style: TextStyle(
                          color: gpsProcessingMs > 50
                              ? Colors.orangeAccent
                              : Colors.greenAccent,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Fréquence théorique vs réelle
                  Text(
                    "Théorique: 1000 ms | Réel: ${gpsIntervalMs} ms",
                    style: TextStyle(
                      color: gpsIntervalMs <= 1100
                          ? Colors.greenAccent
                          : Colors.orangeAccent,
                      fontSize: 9,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }
}

class DebugOverlayWidget extends StatelessWidget {
  const DebugOverlayWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final nav = Get.find<NavigationController>();
    final home = Get.find<HomeController>();

    return Obx(() {
      if (home.mapStatus.value != Constants.onDestination) {
        return const SizedBox.shrink();
      }

      final pingMs = nav.timeBetweenGpsMs.value;
      final procMs = nav.gpsProcessingMs.value;
      final isVisible = home.showDiagnosticPoints.value;

      // Calcul de la précision
      String precisionLabel;
      Color precisionColor;
      if (pingMs <= 1050) {
        precisionLabel = "EXCELLENT";
        precisionColor = Colors.greenAccent;
      } else if (pingMs <= 1500) {
        precisionLabel = "BON";
        precisionColor = Colors.lightGreenAccent;
      } else if (pingMs <= 2500) {
        precisionLabel = "MOYEN";
        precisionColor = Colors.orangeAccent;
      } else {
        precisionLabel = "FAIBLE";
        precisionColor = Colors.redAccent;
      }

      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.85),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withOpacity(0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.gps_fixed, color: Colors.white, size: 14),
                const SizedBox(width: 6),
                const Text(
                  "GPS DIAGNOSTIC",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Intervalle précis en ms
            Text(
              "📡 Intervalle GPS : ${pingMs} ms",
              style: TextStyle(
                color: precisionColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 2),
            // Temps de traitement
            Text(
              "⚙️ Traitement : ${procMs} ms",
              style: TextStyle(
                color: procMs > 50 ? Colors.orangeAccent : Colors.greenAccent,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 2),
            // Qualité du signal
            Text(
              "📶 Qualité : $precisionLabel",
              style: TextStyle(
                color: precisionColor,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            // Écart par rapport à la théorie
            Text(
              "📐 Écart théorie : ${pingMs - 1000} ms",
              style: TextStyle(
                color: (pingMs - 1000).abs() > 200
                    ? Colors.orangeAccent
                    : Colors.greenAccent,
                fontSize: 9,
                fontStyle: FontStyle.italic,
              ),
            ),
            const Divider(color: Colors.white24, height: 10),
            // Toggle points diagnostic
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isVisible ? "Points: VISIBLES" : "Points: MASQUÉS",
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => home.toggleDiagnosticPoints(),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isVisible ? Colors.blueAccent : Colors.grey[700],
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Icon(
                      isVisible ? Icons.visibility : Icons.visibility_off,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    });
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final home = Get.put(HomeController());
    Get.put(NavigationController());
    Get.put(SpeedController());

    final double screenHeight = MediaQuery.of(context).size.height;

// C'est cette valeur qui détermine à quel point la flèche est basse.
// 0.60 signifie que le bas de la map est remonté de 60% de la hauteur de l'écran.
// Donc le centre de la map descend.
    final double mapOffset = screenHeight * 0.90;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
// --- CARTE DYNAMIQUE ---
          Obx(() {
            bool isNavigating = home.mapStatus.value == Constants.onDestination;

// Si on navigue, on applique l'offset négatif pour descendre la flèche
            double currentBottom = isNavigating ? -mapOffset : 0;

            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: currentBottom, // <-- C'est ici que la flèche descend

// Listener pour détecter si l'utilisateur touche la carte
              child: Listener(
                onPointerDown: (_) {
                  home.onUserInteraction(); // Déverrouille la caméra si on touche
                },
                child: MapLibreMap(
                  styleString: Constants.mapStyle,
                  initialCameraPosition: home.initialCameraPosition,
                  onMapCreated: home.onMapCreated,
                  onStyleLoadedCallback: home.onStyleLoaded,
                  myLocationEnabled: false, // On utilise notre propre icône
                  attributionButtonPosition: AttributionButtonPosition.topRight,
                ),
              ),
            );
          }),

// --- UI : Recherche & Instructions ---
          Obx(() {
            // Affiche les instructions dès que la navigation est active (route calculée ou navigation en cours)
            if (home.mapStatus.value != Constants.idle) {
              return Positioned(
                top: 50,
                left: 15,
                right: 15,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    InstructionHeader(),
                    TransitStatusWidget(),
                  ],
                ),
              );
            } else {
              // Recherche : afficher la barre de recherche
              return Positioned(
                top: 60,
                left: 15,
                right: 15,
                child: PhotonSearchBar(onSelected: home.setDestination),
              );
            }
          }),

// --- UI : Compteur de Vitesse ---
          SpeedometerDisplay(),

// --- UI : Bouton Recentrer ---
          Obx(() {
// Affiche le bouton recentrer si on n'est pas en nav, OU si on est en nav mais déverrouillé
            bool showRecenter =
                home.mapStatus.value != Constants.onDestination ||
                    (home.mapStatus.value == Constants.onDestination &&
                        !home.isNavigationCameraLocked.value);

            if (!showRecenter) return const SizedBox.shrink();

            return Positioned(
              right: 20,
// On remonte le bouton si le panneau du bas est visible
              bottom: home.mapStatus.value != Constants.idle ? 250 : 40,
              child: FloatingActionButton(
                heroTag: "recenter",
                backgroundColor: Colors.white,
                child: Icon(Icons.my_location,
                    color: (home.mapStatus.value == Constants.onDestination)
                        ? Colors.orange
                        : Colors.blueAccent),
                onPressed: () => home.recenterMap(),
              ),
            );
          }),

// --- UI : Panneau du bas (Distance/Temps) ---
          Obx(() => home.mapStatus.value != Constants.idle &&
                  home.mapStatus.value != Constants.onDestination
              ? Positioned(
                  bottom: 0, left: 0, right: 0, child: const BottomPanel())
              : Container()),

          // ── BOUTON STOP + TOGGLE POINTS GPS (pendant navigation) ──
          Obx(() {
            if (home.mapStatus.value != Constants.onDestination) {
              return const SizedBox.shrink();
            }
            final showPoints = home.showDiagnosticPoints.value;
            return Positioned(
              bottom: 80,
              left: 20,
              right: 20,
              child: Row(
                children: [
                  // ── BOUTON TOGGLE POINTS GPS ──
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: showPoints
                            ? Colors.blue.shade700
                            : Colors.grey.shade700,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14, horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                      icon: Icon(
                        showPoints ? Icons.visibility : Icons.visibility_off,
                        color: Colors.white,
                        size: 20,
                      ),
                      label: Text(
                        showPoints ? "Points GPS" : "Points masqués",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: () {
                        home.toggleDiagnosticPoints();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  // ── BOUTON STOP NAVIGATION ──
                  Expanded(
                    flex: 3,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 4,
                      ),
                      child: const Text(
                        "STOP NAVIGATION",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      onPressed: () =>
                          Get.find<NavigationController>().stopNavigation(),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class DirectionsStatusBar extends StatelessWidget {
  final Future<void> Function()? onValidatePurchase;

  const DirectionsStatusBar({Key? key, this.onValidatePurchase})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    HomeController homeController = Get.find();

    return Obx(() {
      // 1. On l'affiche UNIQUEMENT si l'utilisateur est arrivé (arrived.value = true)
      // Cela laisse la place libre pour ton InstructionHeader pendant le trajet !
      bool shouldShow =
          homeController.mapStatus.value == Constants.onDestination &&
              homeController.arrived.value;

      if (!shouldShow) return const SizedBox.shrink();

      Widget content;

      // 2. Logique d'arrivée conservée intacte pour la validation des achats
      if (homeController.isNavigatingToStore.value) {
        content = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "Vous êtes arrivé(e) au magasin !",
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onValidatePurchase,
              icon: const Icon(Icons.receipt_long_rounded),
              label: const Text("Valider un Achat"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFB300), // accentGold
                foregroundColor: const Color(0xFF212121), // textDark
              ),
            ),
          ],
        );
      } else if (homeController.validationCountdown.value != null) {
        Duration countdown = homeController.validationCountdown.value!;
        String twoDigits(int n) => n.toString().padLeft(2, '0');
        final minutes = twoDigits(countdown.inMinutes.remainder(60));
        final seconds = twoDigits(countdown.inSeconds.remainder(60));
        content = Text(
          "Validation dans : $minutes:$seconds",
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
        );
      } else {
        content = const Text(
          "Vous êtes arrivé(e) !",
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 20, color: Colors.white, fontWeight: FontWeight.bold),
        );
      }

      return SizedBox(
        width: MediaQuery.of(context).size.width,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 350),
            padding: const EdgeInsets.all(10),
            width: double.infinity,
            decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    spreadRadius: 1,
                    blurRadius: 7,
                    offset: const Offset(0, 1),
                  ),
                ]),
            child: Center(child: content),
          ),
        ),
      );
    });
  }
}

class BottomBar extends StatelessWidget {
  const BottomBar({super.key});

// Dans la classe BottomBar
  @override
  Widget build(BuildContext context) {
    HomeController homeController = Get.find();
    NavigationController navigationController = Get.find();

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      width: MediaQuery.of(context).size.width,
      child: Obx(() {
        bool isTransitRouteSelected =
            homeController.currentTravelMode.value == TravelMode.transit &&
                !homeController.showTransitOptions.value &&
                homeController.mapStatus.value == Constants.route;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
// Section Gauche : Distance et temps (Empêche l'étirement excessif)
            Flexible(
              flex: 2,
              child: Row(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      homeController.distanceLeft.value,
                      style: TextStyle(
                          color: Colors.green[900],
                          fontWeight: FontWeight.bold,
                          fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      "(${homeController.timeLeft.value})",
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

// Section Droite : Boutons d'action
            Flexible(
              flex: 3,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (homeController.mapStatus.value == Constants.onDestination)
// Bouton Arrêter pendant la navigation
                    ElevatedButton(
                      onPressed: () => navigationController.stopNavigation(),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 16)),
                      child: const Text("Arrêter",
                          style: TextStyle(color: Colors.white)),
                    )
                  else if (isTransitRouteSelected)
// Bouton spécifique pour le Transit
                    ElevatedButton(
                      onPressed: () =>
                          navigationController.navigateToDestination(),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          padding: const EdgeInsets.symmetric(horizontal: 16)),
                      child: const Text("Partir",
                          style: TextStyle(color: Colors.white)),
                    )
                  else
// Boutons Annuler / Commencer pour Marche et Vélo
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => homeController.clearDestination(),
                          child: const Text("Annuler",
                              style: TextStyle(color: Colors.grey)),
                        ),
                        const SizedBox(width: 5),
                        ElevatedButton(
                          onPressed: () => navigationController
                              .navigateToDestination(validateWalkingLegs: true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                          ),
                          child: const Text("Démarrer",
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      }),
    );
  }
}

// --- WIDGETS MANQUANTS ---

class PhotonSearchBar extends StatefulWidget {
  final Function(String name, LatLng coords) onSelected;
  const PhotonSearchBar({super.key, required this.onSelected});
  @override
  State<PhotonSearchBar> createState() => _PhotonSearchBarState();
}

class _PhotonSearchBarState extends State<PhotonSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final PhotonService _service = PhotonService();
  List<dynamic> _results = [];
  bool _isLoading = false;

  void _search() async {
    if (_controller.text.length < 3) return;
    setState(() => _isLoading = true);
    FocusManager.instance.primaryFocus?.unfocus();

    var res = await _service.searchPlace(_controller.text);
    if (mounted) {
      setState(() {
        _results = res;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(blurRadius: 5, color: Colors.black26)
              ]),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: "Rechercher une destination...",
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(15),
              suffixIcon: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(
                      icon: const Icon(Icons.search), onPressed: _search),
            ),
            onSubmitted: (_) => _search(),
          ),
        ),
        if (_results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 5),
            constraints: const BoxConstraints(maxHeight: 250),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [
                  BoxShadow(blurRadius: 5, color: Colors.black12)
                ]),
            child: Material(
              color: Colors.transparent,
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (ctx, i) => const Divider(height: 1),
                itemBuilder: (ctx, i) {
                  var p = _results[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined,
                        color: Colors.blue),
                    title: Text(p['display_name'].split(",")[0],
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(p['display_name'],
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      double lat = double.parse(p['lat']);
                      double lon = double.parse(p['lon']);
                      widget.onSelected(
                          p['display_name'].split(",")[0], LatLng(lat, lon));
                      setState(() {
                        _results = [];
                        _controller.clear();
                      });
                      FocusManager.instance.primaryFocus?.unfocus();
                    },
                  );
                },
              ),
            ),
          )
      ],
    );
  }
}

class InstructionHeader extends GetView<NavigationController> {
  const InstructionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      String text = controller.currentInstructionText.value;
      if (text.trim().isEmpty) {
        text = "Navigation en cours...";
      }

      // Récupérer le mode actuel pour afficher l'icône appropriée
      final mode = controller.homeController.currentTravelMode.value;
      IconData modeIcon = Icons.directions_walk;
      Color bgColor = Colors.green[800]!;

      if (mode == TravelMode.bicycling || mode == Constants.modeCycling) {
        modeIcon = Icons.directions_bike;
      } else if (mode == TravelMode.transit || mode == Constants.modeTransit) {
        modeIcon = Icons.directions_bus;
        // Changer couleur en fonction du contexte
        if (text.contains("retard")) {
          bgColor = Colors.red[700]!;
        } else if (text.contains("avance")) {
          bgColor = Colors.blue[700]!;
        } else if (text.contains("l'heure")) {
          bgColor = Colors.green[700]!;
        }
      }

      String modeLabel = "Mode";
      if (mode == TravelMode.walking) modeLabel = "Marche";
      if (mode == TravelMode.bicycling) modeLabel = "Vélo";
      if (mode == TravelMode.transit) modeLabel = "Transports";

      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(modeIcon, color: Colors.white, size: 30),
                const SizedBox(width: 15),
                Expanded(
                    child: Text(
                  text,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                )),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "Mode : $modeLabel",
              style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    });
  }
}

/// Widget d'affichage des informations de transit (arrêt, bus, déviation)
class TransitStatusWidget extends GetView<NavigationController> {
  const TransitStatusWidget({super.key});

  String _getTimeStatus(DateTime scheduleTime) {
    DateTime now = DateTime.now();
    Duration diff = now.difference(scheduleTime);
    int diffMinutes = diff.inMinutes;

    if (diffMinutes < -5) {
      // En avance
      return "en avance de ${diffMinutes.abs()} min ⏳";
    } else if (diffMinutes >= -5 && diffMinutes <= 5) {
      // À l'heure
      return "à l'heure 🎯";
    } else if (diffMinutes > 5 && diffMinutes <= 15) {
      // Légèrement en retard
      return "en retard de $diffMinutes min ⏱️";
    } else {
      // Très en retard
      return "très en retard ($diffMinutes min) 🚨";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final mode = controller.homeController.currentTravelMode.value;

      // N'afficher ce widget que pour le transit
      if (mode != TravelMode.transit && mode != Constants.modeTransit) {
        return Container();
      }

      final isInBus = controller.isOnBus.value;
      final isAtStop = controller.targetBusStopLocation != null &&
          controller.hasReachedBusStop;
      final hasDeviation = controller.cumulatedDeviationMeters > 0;
      final scheduleTime = controller.targetBusStopSchedule;

      String statusText = "";
      Color statusColor = Colors.blue.shade700;
      IconData statusIcon = Icons.info;

      // Déterminer l'état à afficher
      if (hasDeviation && controller.cumulatedDeviationMeters > 3000) {
        // Déviation détectée
        statusText =
            "⚠️ Déviation détectée (${(controller.cumulatedDeviationMeters / 1000).toStringAsFixed(1)} km)";
        statusColor = Colors.red.shade700;
        statusIcon = Icons.warning;
      } else if (isInBus) {
        // Dans le bus
        statusText = "🚌 Vous êtes dans le bus";
        statusColor = Colors.blue.shade700;
        statusIcon = Icons.directions_bus;
      } else if (isAtStop && scheduleTime != null) {
        // À l'arrêt, en attente du bus avec info d'horaire
        String timeStatus = _getTimeStatus(scheduleTime);
        String timeStr = DateFormat('HH:mm').format(scheduleTime);

        Duration diff = DateTime.now().difference(scheduleTime);
        if (diff.inMinutes < -5) {
          statusText = "⏳ En attente - Bus prévu à $timeStr (en avance)";
          statusColor = Colors.blue.shade700;
          statusIcon = Icons.schedule;
        } else if (diff.inMinutes >= -5 && diff.inMinutes <= 15) {
          statusText = "🎯 À l'arrêt - Bus prévu à $timeStr ($timeStatus)";
          statusColor = Colors.green.shade700;
          statusIcon = Icons.done;
        } else {
          statusText = "🚨 Bus en retard - Prévu à $timeStr ($timeStatus)";
          statusColor = Colors.red.shade700;
          statusIcon = Icons.warning;
        }
      } else if (isAtStop) {
        // À l'arrêt sans horaire
        statusText = "🚏 À l'arrêt - En attente du bus...";
        statusColor = Colors.amber.shade700;
        statusIcon = Icons.location_on;
      } else if (controller.targetBusStopLocation != null &&
          !controller.hasReachedBusStop) {
        // En route vers l'arrêt
        statusText = "🚏 En route vers l'arrêt";
        statusColor = Colors.amber.shade700;
        statusIcon = Icons.location_on;
      }

      // Ne rien afficher si pas d'état particulier
      if (statusText.isEmpty) return Container();

      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: statusColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)]),
        child: Row(
          children: [
            Icon(statusIcon, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                statusText,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    });
  }
}

class TravelModeSelector extends StatelessWidget {
  final HomeController controller;
  const TravelModeSelector({super.key, required this.controller});

  Widget _buildModeBtn(String mode, IconData icon, String label) {
    return Obx(() {
// Comparaison String vs Enum gérée ici
      bool isSelected = controller.currentTravelMode.value.toString() == mode ||
          controller.currentTravelMode.value == mode;

      return GestureDetector(
        onTap: () => controller.setTravelMode(
            mode), // setTravelMode manque, on l'utilise pour trigger la maj
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
              color: isSelected ? Colors.blueAccent : Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: isSelected ? Colors.blue : Colors.transparent)),
          child: Row(
            children: [
              Icon(icon,
                  color: isSelected ? Colors.white : Colors.black54, size: 20),
              const SizedBox(width: 8),
              Text(label,
                  style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildModeBtn(Constants.modeDriving, Icons.directions_car, "Voiture"),
          const SizedBox(width: 10),
          _buildModeBtn(Constants.modeCycling, Icons.directions_bike, "Vélo"),
          const SizedBox(width: 10),
          _buildModeBtn(Constants.modeWalking, Icons.directions_walk, "À pied"),
        ],
      ),
    );
  }
}

class BottomPanel extends GetView<HomeController> {
  const BottomPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final nav = Get.find<NavigationController>();
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
                color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))
          ]),
      padding: const EdgeInsets.fromLTRB(25, 15, 25, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 15),
          Obx(() => controller.mapStatus.value == Constants.route
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: TravelModeSelector(controller: controller),
                )
              : Container()),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Obx(() => Text(controller.timeLeft.value,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87))),
                    Obx(() => Text(controller.distanceLeft.value,
                        style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 16,
                            fontWeight: FontWeight.w500))),
                    const SizedBox(height: 6),
                    Obx(() => Text(
                          nav.currentInstructionText.value.isNotEmpty
                              ? nav.currentInstructionText.value
                              : "Navigation en cours...",
                          style: const TextStyle(
                              color: Colors.black54, fontSize: 13),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => controller.mapStatus.value == Constants.route
                    ? nav.startNavigation()
                    : nav.stopNavigation(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: controller.mapStatus.value == Constants.route
                      ? Colors.blueAccent
                      : Colors.redAccent,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                icon: Icon(
                    controller.mapStatus.value == Constants.route
                        ? Icons.navigation
                        : Icons.stop,
                    color: Colors.white),
                label: Obx(() => Text(
                    controller.mapStatus.value == Constants.route
                        ? "DÉMARRER"
                        : "STOP",
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16))),
              )
            ],
          ),
        ],
      ),
    );
  }
}

class MapPage extends StatelessWidget {
  final Future<void> Function(EcoStore store)? onValidatePurchase;
  const MapPage({super.key, this.onValidatePurchase});

  @override
  Widget build(BuildContext context) {
    final home = Get.find<HomeController>();

    return Stack(
      children: [
// --- CARTE DYNAMIQUE ---
// CORRECTION : Suppression de l'Obx ici car MapLibreMap n'écoute pas de variable réactive directement
        Positioned.fill(
          child: Listener(
            onPointerDown: (_) {
              home.onUserInteraction();
            },
            child: MapLibreMap(
              styleString: Constants.mapStyle,
              initialCameraPosition: home.initialCameraPosition,
              onMapCreated: home.onMapCreated,
              onStyleLoadedCallback: home.onStyleLoaded,
              myLocationEnabled: false,
              attributionButtonPosition: AttributionButtonPosition.topRight,
            ),
          ),
        ),

// --- BOUTON RECENTRER ---
        Obx(() {
// On cache le bouton si la caméra est verrouillée en mode navigation
          bool isNavLocked = home.mapStatus.value == Constants.onDestination &&
              home.isNavigationCameraLocked.value;

          if (isNavLocked) return const SizedBox.shrink();

          return Positioned(
            right: 20,
// Remonte le bouton si on est en navigation (pour ne pas être caché par le panneau)
            bottom: home.mapStatus.value == Constants.onDestination ? 200 : 250,
            child: FloatingActionButton(
              heroTag: "recenter_map_page",
              backgroundColor: Colors.white,
              child: Icon(Icons.my_location, color: Colors.blueAccent),
              onPressed: () => home.recenterMap(),
            ),
          );
        }),
      ],
    );
  }
}

final fb_auth.FirebaseAuth _firebaseAuth = fb_auth.FirebaseAuth.instance;
final FirebaseFirestore _firestore = FirebaseFirestore.instance;
final FirebaseStorage _firebaseStorage = FirebaseStorage.instance;
const double LOGIN_STREAK_BONUS_PER_PALIER = 0.10;
const int LOGIN_STREAK_DAYS_PER_PALIER = 5;
const double MAX_LOGIN_STREAK_BONUS_TOTAL = 0.50;

// CONSTANTES MÉTIER
const double STAY_ZONE_TOLERANCE_METERS = 15.0;
const double LOCATION_DISTANCE_FILTER_METERS = 2.0;
const double MAX_WALK_SPEED_KMH = 12.0;
const double MAX_BIKE_SPEED_KMH = 55.0;
const double MAX_CAR_SUSPECT_SPEED_KMH = 70.0;
const double MAX_VEHICLE_SPEED_VIOLATION_KMH = 80.0;
const double WARNING_SPEED_THRESHOLD_KMH = 60.0;

const Color primaryGreen = Color(0xFF388E3C);
const Color lightGreen = Color(0xFFA5D6A7);
const Color defisScreenBackground = Color(0xFFF5F5F5);
const Color defisCardBackground = Color(0xFFE6F5E6);
const Color defisProgressFilled = Color(0xFF4CAF50);
const Color defisProgressEmpty = Color(0xFFD0D0D0);
const Color defisPrimaryButton = Color(0xFF4CAF50);
const Color defisSecondaryButton = Color(0xFFE0E0E0);
const Color defisSecondaryButtonText = Color(0xFF757575);
const Color accentGold = Color(0xFFFFB300);
const Color backgroundGrey = Color(0xFFF5F5F5);
const Color cardWhite = Color(0xFFFFFFFF);
const Color textDark = Color(0xFF212121);
const Color textGrey = Color(0xFF757575);

enum ChallengeStatus {
  notStarted,
  inProgress,
  storeSelectionNeeded,
  proofSubmissionNeeded,
  completedPendingReward,
  rewardClaimed,
  expired
}

enum TravelType { walk, bike, transit }

enum ChallengeType {
  visitMultiple,
  purchaseScanProof,
  partnerStoreVisit,
  localPoiVisit
}

class UserProfile {
  final String id;
  final int lamePoints;
  final bool isVip;
  final int consecutiveLogins;
  final String username;
  final int currentLevel;
  final double nextLevelBoost;

  // 📊 Statistiques utilisateur
  final double totalDistanceKm;
  final int totalTripsCount;
  final int totalCaloriesBurned;
  final List<String> unlockedBadges; // IDs des badges déverrouillés

  // 👥 Système d'amis
  final List<String> friendIds; // IDs des amis confirmés
  final List<String> friendRequestsSent; // Demandes d'ami envoyées
  final List<String> friendRequestsReceived; // Demandes d'ami reçues

  final Timestamp? updatedAt;
  final String? homeAddressString;
  final latlong.LatLng? homeAddressCoordinates;
  final String? workAddressString;
  final latlong.LatLng? workAddressCoordinates;
  final Timestamp? lastAddressUpdateTime;
  final List<int> workDays;
  final int currentWorkCommuteStreak;
  final Timestamp? lastWorkCommuteTimestamp;
  final String? lastCommuteType;
  final int adPoints;
  final Timestamp? adBoostEndTime;
  final Timestamp? lastAdPointDecayTime;
  final Timestamp? lastLoginDate;
  final Timestamp? lastDailyRewardCollectedDate;
  final String? country; // NOUVEAU: Champ pour le pays de l'utilisateur
  final double currentCashbackBoost; // Le montant ajouté (ex: 0.15)
  final Timestamp? lastBoostUpdate; // Date du dernier calcul de perte
  final Map<String, dynamic>
      loyaltyProgress; // { "store_id": { "visits": 3, "spend": 45.0 } }
  final Map<String, dynamic>
      storeBoosts; // Nouveau champ : {'storeId': {'amount': 0.5, 'last_update': ...}}
  final List<String> favoriteStores; // Liste des magasins favoris
  final List<Map<String, dynamic>> favoriteRoutes; // Liste des trajets favoris
  final int?
      totalLameEarned; // Total cumulé de Lame Points gagnés (pour les niveaux)

  final Timestamp? lastWorkArrivalTimestamp;
  final int monthlyWorkAbsenceAllowance;
  final Timestamp? lastMonthlyAllowanceReset;

  UserProfile({
    required this.id,
    required this.lamePoints,
    required this.isVip,
    required this.consecutiveLogins,
    required this.username,
    required this.currentLevel,
    required this.nextLevelBoost,
    this.totalDistanceKm = 0.0,
    this.totalTripsCount = 0,
    this.totalCaloriesBurned = 0,
    this.unlockedBadges = const [],
    this.friendIds = const [],
    this.friendRequestsSent = const [],
    this.friendRequestsReceived = const [],
    this.updatedAt,
    this.homeAddressString,
    this.homeAddressCoordinates,
    this.workAddressString,
    this.workAddressCoordinates,
    this.lastAddressUpdateTime,
    this.workDays = const [],
    this.currentWorkCommuteStreak = 0,
    this.lastWorkCommuteTimestamp,
    this.lastCommuteType,
    this.adPoints = 0,
    this.storeBoosts = const {},
    this.adBoostEndTime,
    this.lastAdPointDecayTime,
    this.lastLoginDate,
    this.lastDailyRewardCollectedDate,
    this.country, // NOUVEAU
    this.currentCashbackBoost = 0.0,
    this.lastBoostUpdate,
    this.loyaltyProgress = const {},
    this.favoriteStores = const [],
    this.favoriteRoutes = const [],
    this.totalLameEarned,
    this.lastWorkArrivalTimestamp,
    this.monthlyWorkAbsenceAllowance = 3,
    this.lastMonthlyAllowanceReset,
  });

  static int _parseFirestoreInt(
      dynamic value, int defaultValue, String fieldName) {
    if (value is int) {
      return value;
    } else if (value is num) {
      return value.toInt();
    } else if (value != null) {
      print(
          'WARNING (UserProfile.fromFirestore): Field "$fieldName" expected an int but got ${value.runtimeType}: $value. Using default value $defaultValue.');
    }
    return defaultValue;
  }

  static double _parseFirestoreDouble(
      dynamic value, double defaultValue, String fieldName) {
    if (value is double) {
      return value;
    } else if (value is num) {
      return value.toDouble();
    } else if (value != null) {
      print(
          'WARNING (UserProfile.fromFirestore): Field "$fieldName" expected a double but got ${value.runtimeType}: $value. Using default value $defaultValue.');
    }
    return defaultValue;
  }

  static bool _parseFirestoreBool(
      dynamic value, bool defaultValue, String fieldName) {
    if (value is bool) {
      return value;
    } else if (value != null) {
      print(
          'WARNING (UserProfile.fromFirestore): Field "$fieldName" expected a bool but got ${value.runtimeType}: $value. Using default value $defaultValue.');
    }
    return defaultValue;
  }

  static List<int> _parseFirestoreIntList(dynamic value, String fieldName) {
    if (value is List) {
      List<int> result = [];
      for (var item in value) {
        if (item is int) {
          result.add(item);
        } else if (item is num) {
          result.add(item.toInt());
        } else if (item != null) {
          print(
              'WARNING (UserProfile.fromFirestore): Field "$fieldName" list contained non-numeric item ${item.runtimeType}: $item. Skipping.');
        }
      }
      return result;
    }
    return [];
  }

  factory UserProfile.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      throw Exception(
          "User profile data is null for snapshot ID: ${snapshot.id}");
    }

    latlong.LatLng? parseCoordinates(dynamic coordsData) {
      if (coordsData is Map<String, dynamic> &&
          coordsData['latitude'] is num &&
          coordsData['longitude'] is num) {
        return latlong.LatLng((coordsData['latitude'] as num).toDouble(),
            (coordsData['longitude'] as num).toDouble());
      } else if (coordsData is GeoPoint) {
        return latlong.LatLng(coordsData.latitude, coordsData.longitude);
      } else if (coordsData != null) {
        print(
            'WARNING (UserProfile.fromFirestore): Field for coordinates had malformed data: $coordsData.');
      }
      return null;
    }

    return UserProfile(
      id: snapshot.id,
      storeBoosts: data?['store_boosts'] ?? {}, // Récupération de la map

      lamePoints: _parseFirestoreInt(data['lame_points'], 0, 'lame_points'),
      isVip: _parseFirestoreBool(data['is_vip'], false, 'is_vip'),
      currentCashbackBoost:
          (data['current_cashback_boost'] as num?)?.toDouble() ?? 0.0,
      lastBoostUpdate: data['last_boost_update'],
      loyaltyProgress: data['loyalty_progress'] ?? {},

      // 📊 Statistiques
      totalDistanceKm: (data['total_distance_km'] as num?)?.toDouble() ?? 0.0,
      totalTripsCount:
          _parseFirestoreInt(data['total_trips_count'], 0, 'total_trips_count'),
      totalCaloriesBurned: _parseFirestoreInt(
          data['total_calories_burned'], 0, 'total_calories_burned'),
      unlockedBadges:
          (data['unlocked_badges'] as List<dynamic>?)?.cast<String>() ?? [],

      // 👥 Amis
      friendIds: (data['friend_ids'] as List<dynamic>?)?.cast<String>() ?? [],
      friendRequestsSent:
          (data['friend_requests_sent'] as List<dynamic>?)?.cast<String>() ??
              [],
      friendRequestsReceived:
          (data['friend_requests_received'] as List<dynamic>?)
                  ?.cast<String>() ??
              [],

      consecutiveLogins: _parseFirestoreInt(
          data['consecutive_logins'], 0, 'consecutive_logins'),
      username: data['username'] as String? ?? 'Utilisateur Anonyme',
      currentLevel:
          _parseFirestoreInt(data['current_level'], 1, 'current_level'),
      nextLevelBoost: _parseFirestoreDouble(
          data['next_level_boost'], 1.0, 'next_level_boost'),
      updatedAt: data['updated_at'] as Timestamp?,
      homeAddressString: data['home_address_string'] as String?,
      homeAddressCoordinates:
          parseCoordinates(data['home_address_coordinates']),
      workAddressString: data['work_address_string'] as String?,
      workAddressCoordinates:
          parseCoordinates(data['work_address_coordinates']),
      lastAddressUpdateTime: data['last_address_update_time'] as Timestamp?,
      workDays: _parseFirestoreIntList(data['work_days'], 'work_days'),
      currentWorkCommuteStreak: _parseFirestoreInt(
          data['current_work_commute_streak'],
          0,
          'current_work_commute_streak'),
      lastWorkCommuteTimestamp:
          data['last_work_commute_timestamp'] as Timestamp?,
      lastCommuteType: data['last_commute_type'] as String?,
      adPoints: _parseFirestoreInt(data['ad_points'], 0, 'ad_points'),
      adBoostEndTime: data['ad_boost_end_time'] as Timestamp?,
      lastAdPointDecayTime: data['last_ad_point_decay_time'] as Timestamp?,
      lastLoginDate: data['last_login_date'] as Timestamp?,
      lastDailyRewardCollectedDate:
          data['last_daily_reward_collected_date'] as Timestamp?,
      country: data['country'] as String?, // NOUVEAU
      favoriteStores:
          (data['favorite_stores'] as List<dynamic>?)?.cast<String>() ?? [],
      favoriteRoutes: (data['favorite_routes'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [],
      totalLameEarned:
          _parseFirestoreInt(data['total_lame_earned'], 0, 'total_lame_earned'),
      lastWorkArrivalTimestamp:
          data['last_work_arrival_timestamp'] as Timestamp?,
      monthlyWorkAbsenceAllowance: _parseFirestoreInt(
          data['monthly_work_absence_allowance'],
          3,
          'monthly_work_absence_allowance'),
      lastMonthlyAllowanceReset:
          data['last_monthly_allowance_reset'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lame_points': lamePoints,
      'is_vip': isVip,
      'consecutive_logins': consecutiveLogins,
      'username': username,
      'current_level': currentLevel,
      'next_level_boost': nextLevelBoost,
      'updated_at': updatedAt ?? FieldValue.serverTimestamp(),

      // 📊 Statistiques
      'total_distance_km': totalDistanceKm,
      'total_trips_count': totalTripsCount,
      'total_calories_burned': totalCaloriesBurned,
      'unlocked_badges': unlockedBadges,

      // 👥 Amis
      'friend_ids': friendIds,
      'friend_requests_sent': friendRequestsSent,
      'friend_requests_received': friendRequestsReceived,

      'home_address_string': homeAddressString,
      'home_address_coordinates': homeAddressCoordinates != null
          ? GeoPoint(homeAddressCoordinates!.latitude,
              homeAddressCoordinates!.longitude)
          : null,
      'work_address_string': workAddressString,
      'work_address_coordinates': workAddressCoordinates != null
          ? GeoPoint(workAddressCoordinates!.latitude,
              workAddressCoordinates!.longitude)
          : null,
      'last_address_update_time': lastAddressUpdateTime,
      'work_days': workDays,
      'current_work_commute_streak': currentWorkCommuteStreak,
      'last_work_commute_timestamp': lastWorkCommuteTimestamp,
      'last_commute_type': lastCommuteType,
      'ad_points': adPoints,
      'ad_boost_end_time': adBoostEndTime,
      'last_ad_point_decay_time': lastAdPointDecayTime,
      'last_login_date': lastLoginDate,
      'last_daily_reward_collected_date': lastDailyRewardCollectedDate,
      'country': country, // NOUVEAU
      'favorite_stores': favoriteStores,
      'favorite_routes': favoriteRoutes,
      'total_lame_earned': totalLameEarned ?? 0,
      'last_work_arrival_timestamp': lastWorkArrivalTimestamp,
      'monthly_work_absence_allowance': monthlyWorkAbsenceAllowance,
      'last_monthly_allowance_reset': lastMonthlyAllowanceReset,
    };
  }

  UserProfile copyWith({
    String? id,
    int? lamePoints,
    bool? isVip,
    int? consecutiveLogins,
    String? username,
    int? currentLevel,
    double? nextLevelBoost,
    double? totalDistanceKm,
    int? totalTripsCount,
    int? totalCaloriesBurned,
    List<String>? unlockedBadges,
    List<String>? friendIds,
    List<String>? friendRequestsSent,
    List<String>? friendRequestsReceived,
    Timestamp? updatedAt,
    ValueGetter<String?>? homeAddressString,
    ValueGetter<latlong.LatLng?>? homeAddressCoordinates,
    ValueGetter<String?>? workAddressString,
    ValueGetter<latlong.LatLng?>? workAddressCoordinates,
    ValueGetter<Timestamp?>? lastAddressUpdateTime,
    List<int>? workDays,
    int? currentWorkCommuteStreak,
    ValueGetter<Timestamp?>? lastWorkCommuteTimestamp,
    ValueGetter<String?>? lastCommuteType,
    int? adPoints,
    ValueGetter<Timestamp?>? adBoostEndTime,
    ValueGetter<Timestamp?>? lastAdPointDecayTime,
    ValueGetter<Timestamp?>? lastLoginDate,
    ValueGetter<Timestamp?>? lastDailyRewardCollectedDate,
    String? country, // NOUVEAU
    List<String>? favoriteStores,
    List<Map<String, dynamic>>? favoriteRoutes,
    int? totalLameEarned,
    ValueGetter<Timestamp?>? lastWorkArrivalTimestamp,
    int? monthlyWorkAbsenceAllowance,
    ValueGetter<Timestamp?>? lastMonthlyAllowanceReset,
  }) {
    return UserProfile(
      id: id ?? this.id,
      lamePoints: lamePoints ?? this.lamePoints,
      isVip: isVip ?? this.isVip,
      totalDistanceKm: totalDistanceKm ?? this.totalDistanceKm,
      totalTripsCount: totalTripsCount ?? this.totalTripsCount,
      totalCaloriesBurned: totalCaloriesBurned ?? this.totalCaloriesBurned,
      unlockedBadges: unlockedBadges ?? this.unlockedBadges,
      friendIds: friendIds ?? this.friendIds,
      friendRequestsSent: friendRequestsSent ?? this.friendRequestsSent,
      friendRequestsReceived:
          friendRequestsReceived ?? this.friendRequestsReceived,

      consecutiveLogins: consecutiveLogins ?? this.consecutiveLogins,
      username: username ?? this.username,
      currentLevel: currentLevel ?? this.currentLevel,
      nextLevelBoost: nextLevelBoost ?? this.nextLevelBoost,
      updatedAt: updatedAt ?? this.updatedAt,
      homeAddressString: homeAddressString != null
          ? homeAddressString()
          : this.homeAddressString,
      homeAddressCoordinates: homeAddressCoordinates != null
          ? homeAddressCoordinates()
          : this.homeAddressCoordinates,
      workAddressString: workAddressString != null
          ? workAddressString()
          : this.workAddressString,
      workAddressCoordinates: workAddressCoordinates != null
          ? workAddressCoordinates()
          : this.workAddressCoordinates,
      lastAddressUpdateTime: lastAddressUpdateTime != null
          ? lastAddressUpdateTime()
          : this.lastAddressUpdateTime,
      workDays: workDays ?? this.workDays,
      currentWorkCommuteStreak:
          currentWorkCommuteStreak ?? this.currentWorkCommuteStreak,
      lastWorkCommuteTimestamp: lastWorkCommuteTimestamp != null
          ? lastWorkCommuteTimestamp()
          : this.lastWorkCommuteTimestamp,
      lastCommuteType:
          lastCommuteType != null ? lastCommuteType() : this.lastCommuteType,
      adPoints: adPoints ?? this.adPoints,
      adBoostEndTime:
          adBoostEndTime != null ? adBoostEndTime() : this.adBoostEndTime,
      lastAdPointDecayTime: lastAdPointDecayTime != null
          ? lastAdPointDecayTime()
          : this.lastAdPointDecayTime,
      lastLoginDate:
          lastLoginDate != null ? lastLoginDate() : this.lastLoginDate,
      lastDailyRewardCollectedDate: lastDailyRewardCollectedDate != null
          ? lastDailyRewardCollectedDate()
          : this.lastDailyRewardCollectedDate,
      country: country ?? this.country, // NOUVEAU
      favoriteStores: favoriteStores ?? this.favoriteStores,
      favoriteRoutes: favoriteRoutes ?? this.favoriteRoutes,
      totalLameEarned: totalLameEarned ?? this.totalLameEarned,
      lastWorkArrivalTimestamp: lastWorkArrivalTimestamp != null
          ? lastWorkArrivalTimestamp()
          : this.lastWorkArrivalTimestamp,
      monthlyWorkAbsenceAllowance:
          monthlyWorkAbsenceAllowance ?? this.monthlyWorkAbsenceAllowance,
      lastMonthlyAllowanceReset: lastMonthlyAllowanceReset != null
          ? lastMonthlyAllowanceReset()
          : this.lastMonthlyAllowanceReset,
    );
  }

  bool get isAdBoostCurrentlyActive {
    if (adBoostEndTime == null) return false;
    return adBoostEndTime!.toDate().isAfter(DateTime.now());
  }
}

// 🏅 Définition des badges d'accomplissement
class Achievement {
  final String id;
  final String title;
  final String description;
  final String icon;
  final String requirement; // Texte du prérequis

  const Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    required this.requirement,
  });

  static const List<Achievement> all = [
    Achievement(
      id: 'first_km',
      title: 'Premier Kilomètre',
      description: 'Parcourir 1 km',
      icon: '🚶',
      requirement: '1 km parcouru',
    ),
    Achievement(
      id: 'endurance_10km',
      title: 'Endurance',
      description: 'Parcourir 10 km',
      icon: '⚡',
      requirement: '10 km parcourus',
    ),
    Achievement(
      id: 'marathon',
      title: 'Marathon',
      description: 'Parcourir 42 km',
      icon: '🏃',
      requirement: '42 km parcourus',
    ),
    Achievement(
      id: 'hundred_km',
      title: 'Centenaire',
      description: 'Parcourir 100 km',
      icon: '💯',
      requirement: '100 km parcourus',
    ),
    Achievement(
      id: 'fifty_trips',
      title: 'Explorateur',
      description: 'Effectuer 50 trajets',
      icon: '🗺️',
      requirement: '50 trajets complétés',
    ),
    Achievement(
      id: 'hundred_trips',
      title: 'Nomade',
      description: 'Effectuer 100 trajets',
      icon: '✈️',
      requirement: '100 trajets complétés',
    ),
    Achievement(
      id: 'burn_thousand_calories',
      title: 'Guerrier de Feu',
      description: 'Brûler 1000 calories',
      icon: '🔥',
      requirement: '1000 calories brûlées',
    ),
    Achievement(
      id: 'social_butterfly',
      title: 'Papillon Social',
      description: 'Ajouter 10 amis',
      icon: '🦋',
      requirement: '10 amis ajoutés',
    ),
    Achievement(
      id: 'level_master',
      title: 'Maître des Niveaux',
      description: 'Atteindre le niveau 50',
      icon: '👑',
      requirement: 'Niveau 50 atteint',
    ),
    Achievement(
      id: 'vip_member',
      title: 'Statut Premium',
      description: 'Devenir membre VIP',
      icon: '✨',
      requirement: 'Obtenir le statut VIP',
    ),
  ];

  static Achievement? getById(String id) {
    try {
      return all.firstWhere((a) => a.id == id);
    } catch (e) {
      return null;
    }
  }
}

class WeatherData {
  final double temperature;
  final int weatherCode;
  final double windSpeed;
  final int windDirection;
  final bool isDay;
  final double? maxTempToday;
  final double? minTempToday;
  final int? dailyWeatherCodeToday;
  final String cityOrRegion;

  WeatherData({
    required this.temperature,
    required this.weatherCode,
    required this.windSpeed,
    required this.windDirection,
    required this.isDay,
    this.maxTempToday,
    this.minTempToday,
    this.dailyWeatherCodeToday,
    this.cityOrRegion = "Météo actuelle",
  });

  factory WeatherData.fromJson(Map<String, dynamic> json,
      {String city = "Météo actuelle"}) {
    return WeatherData(
      temperature: (json['current_weather']['temperature'] as num).toDouble(),
      weatherCode: (json['current_weather']['weathercode'] as num).toInt(),
      windSpeed: (json['current_weather']['windspeed'] as num).toDouble(),
      windDirection: (json['current_weather']['winddirection'] as num).toInt(),
      isDay: (json['current_weather']['is_day'] as num).toInt() == 1,
      maxTempToday: json['daily'] != null &&
              json['daily']['temperature_2m_max'] != null &&
              json['daily']['temperature_2m_max'].isNotEmpty
          ? (json['daily']['temperature_2m_max'][0] as num).toDouble()
          : null,
      minTempToday: json['daily'] != null &&
              json['daily']['temperature_2m_min'] != null &&
              json['daily']['temperature_2m_min'].isNotEmpty
          ? (json['daily']['temperature_2m_min'][0] as num).toDouble()
          : null,
      dailyWeatherCodeToday: json['daily'] != null &&
              json['daily']['weathercode'] != null &&
              json['daily']['weathercode'].isNotEmpty
          ? (json['daily']['weathercode'][0] as num).toInt()
          : null,
      cityOrRegion: city,
    );
  }

  String toSummaryString() {
    return "$temperature°C à $cityOrRegion, ${getWeatherDescription()}";
  }

  IconData getWeatherIcon() {
    int codeToUse = dailyWeatherCodeToday ?? weatherCode;
    switch (codeToUse) {
      case 0:
        return Icons.wb_sunny_rounded;
      case 1:
        return isDay ? Icons.wb_cloudy_rounded : Icons.nightlight_round;
      case 2:
        return Icons.cloud_queue_rounded;
      case 3:
        return Icons.cloud_rounded;
      case 45:
      case 48:
        return Icons.foggy;
      case 51:
      case 53:
      case 55:
        return Icons.grain_rounded;
      case 56:
      case 57:
        return Icons.ac_unit_rounded;
      case 61:
        return Icons.water_drop_outlined;
      case 63:
        return Icons.water_drop_rounded;
      case 65:
        return Icons.umbrella_rounded;
      case 66:
      case 67:
        return Icons.ac_unit_rounded;
      case 71:
      case 73:
      case 75:
        return Icons.snowing;
      case 77:
        return Icons.grain_rounded;
      case 80:
      case 81:
      case 82:
        return Icons.shower;
      case 85:
      case 86:
        return Icons.snowing;
      case 95:
      case 96:
      case 99:
        return Icons.thunderstorm_rounded;
      default:
        return Icons.thermostat_rounded;
    }
  }

  String getWeatherDescription() {
    int codeToUse = dailyWeatherCodeToday ?? weatherCode;
    switch (codeToUse) {
      case 0:
        return "Ciel dégagé";
      case 1:
        return "Plutôt dégagé";
      case 2:
        return "Partiellement nuageux";
      case 3:
        return "Couvert";
      case 45:
        return "Brouillard";
      case 48:
        return "Brouillard givrant";
      case 51:
        return "Bruine légère";
      case 53:
        return "Bruine";
      case 55:
        return "Bruine forte";
      case 56:
        return "Bruine verglaçante légère";
      case 57:
        return "Bruine verglaçante";
      case 61:
        return "Pluie légère";
      case 63:
        return "Pluie";
      case 65:
        return "Pluie forte";
      case 66:
        return "Pluie verglaçante légère";
      case 67:
        return "Pluie verglaçante";
      case 71:
        return "Neige faible";
      case 73:
        return "Neige";
      case 75:
        return "Neige forte";
      case 77:
        return "Granules de neige";
      case 80:
        return "Averses légères";
      case 81:
        return "Averses";
      case 82:
        return "Averses fortes";
      case 85:
        return "Averses de neige légères";
      case 86:
        return "Averses de neige fortes";
      case 95:
        return "Orage";
      case 96:
        return "Orage et grêle légère";
      case 99:
        return "Orage et grêle forte";
      default:
        return "Conditions variables";
    }
  }
}

class LeaderboardEntry {
  final String id;
  String username;
  int lamePoints;
  int totalLameEarned;
  int rank;

  LeaderboardEntry(
      {required this.id,
      required this.username,
      required this.lamePoints,
      this.totalLameEarned = 0,
      required this.rank});

  /// Calcule le niveau utilisateur à partir du total cumulé de Lames gagnées
  int get userLevel {
    int currentLevel = 1;
    int lameNeeded = 500;
    int totalForLevel = 0;
    int total = totalLameEarned > 0 ? totalLameEarned : lamePoints;
    while (total >= totalForLevel + lameNeeded && currentLevel < 50) {
      totalForLevel += lameNeeded;
      currentLevel++;
      lameNeeded *= 2;
    }
    return currentLevel;
  }

  factory LeaderboardEntry.fromMap(Map<String, dynamic> data, int rank) {
    return LeaderboardEntry(
      id: data['id'] as String? ?? '',
      username: data['username'] as String? ?? 'Joueur Inconnu',
      lamePoints: (data['lame_points'] as num?)?.toInt() ?? 0,
      totalLameEarned: (data['total_lame_earned'] as num?)?.toInt() ?? 0,
      rank: (data['rank'] as num?)?.toInt() ?? rank,
    );
  }

  factory LeaderboardEntry.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> snapshot, int rank) {
    final data = snapshot.data();
    if (data == null) {
      throw Exception(
          "Leaderboard entry data is null for snapshot ID: ${snapshot.id}");
    }
    return LeaderboardEntry(
      id: snapshot.id,
      username: data['username'] as String? ?? 'Joueur Inconnu',
      lamePoints:
          UserProfile._parseFirestoreInt(data['lame_points'], 0, 'lame_points'),
      totalLameEarned: UserProfile._parseFirestoreInt(
          data['total_lame_earned'], 0, 'total_lame_earned'),
      rank: rank,
    );
  }
}

class Challenge {
  final String id;
  String title;
  String rewardText;
  int rewardLame;
  int totalDurationSeconds;
  Timestamp createdAt;

  String? userChallengeDocId;
  ChallengeStatus status;
  int currentStep;
  Timestamp? startedAtUser;

  String? selectedStore;
  String? proofImageIdentifier;
  String? ocrResultText;
  bool? isProofValid;
  final Timestamp? lastCompletedAt;

  final ChallengeType type;
  final int totalSteps;
  final List<String>? storeOptions;
  final double? latitude;
  final double? longitude;

  final String? partnerStoreId;
  final String? googlePlaceId;

  final int? visitCount;
  final int? stayDurationSeconds;

  Challenge({
    required this.id,
    required this.title,
    required this.rewardText,
    required this.rewardLame,
    required this.totalDurationSeconds,
    required this.createdAt,
    required this.type,
    required this.totalSteps,
    this.storeOptions,
    this.latitude,
    this.longitude,
    this.partnerStoreId,
    this.googlePlaceId,
    this.userChallengeDocId,
    this.status = ChallengeStatus.notStarted,
    this.currentStep = 0,
    this.startedAtUser,
    this.selectedStore,
    this.proofImageIdentifier,
    this.ocrResultText,
    this.isProofValid,
    this.lastCompletedAt,
    this.visitCount,
    this.stayDurationSeconds,
  });

  factory Challenge.fromMap(String id, Map<String, dynamic> data) {
    return Challenge(
      id: id,
      title: data['title'] as String? ?? 'Défi sans titre',
      rewardText: data['reward_text'] as String? ?? 'Récompense standard',
      rewardLame:
          UserProfile._parseFirestoreInt(data['reward_lame'], 0, 'reward_lame'),
      totalDurationSeconds: UserProfile._parseFirestoreInt(
          data['total_duration_seconds'], 0, 'total_duration_seconds'),
      createdAt: data['created_at'] as Timestamp? ?? Timestamp.now(),
      type: ChallengeType.values.firstWhere(
        (e) => e.toString() == 'ChallengeType.${data['type']}',
        orElse: () => ChallengeType.visitMultiple,
      ),
      totalSteps:
          UserProfile._parseFirestoreInt(data['total_steps'], 1, 'total_steps'),
      storeOptions: data['store_options'] != null
          ? List<String>.from(data['store_options'] as List)
          : null,
      latitude:
          UserProfile._parseFirestoreDouble(data['latitude'], 0.0, 'latitude'),
      longitude: UserProfile._parseFirestoreDouble(
          data['longitude'], 0.0, 'longitude'),
      partnerStoreId: data['partner_store_id'] as String?,
      googlePlaceId: data['google_place_id'] as String?,
      visitCount:
          UserProfile._parseFirestoreInt(data['visit_count'], 1, 'visit_count'),
      stayDurationSeconds: UserProfile._parseFirestoreInt(
          data['stay_duration_seconds'], 0, 'stay_duration_seconds'),
    );
  }

  factory Challenge.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>>? challengeSnapshot,
      {DocumentSnapshot<Map<String, dynamic>>? userChallengeSnapshot,
      Map<String, dynamic>? rawChallengeData}) {
    Map<String, dynamic>? challengeData;
    String challengeId;

    if (challengeSnapshot != null && challengeSnapshot.exists) {
      challengeData = challengeSnapshot.data();
      challengeId = challengeSnapshot.id;
    } else if (rawChallengeData != null) {
      challengeData = rawChallengeData;
      challengeId = rawChallengeData['id'] as String? ?? 'unknown_id';
    } else {
      throw Exception("Challenge data is null for snapshot or raw data.");
    }

    if (challengeData == null) {
      throw Exception("Challenge data is null for snapshot ID: $challengeId");
    }

    ChallengeStatus currentStatus = ChallengeStatus.notStarted;
    int currentStepVal = 0;
    int totalDuration = UserProfile._parseFirestoreInt(
        challengeData['total_duration_seconds'], 0, 'total_duration_seconds');
    Timestamp? userStartedAtTime;
    String? currentSelectedStore;
    String? currentProofImageIdentifier;
    String? currentUserChallengeDocId;
    String? currentOcrResultText;
    bool? currentIsProofValid;
    Timestamp? lastCompletedTimestamp;

    if (userChallengeSnapshot != null && userChallengeSnapshot.exists) {
      final userProgressData = userChallengeSnapshot.data();
      if (userProgressData != null) {
        currentUserChallengeDocId = userChallengeSnapshot.id;
        currentStatus = ChallengeStatus.values.firstWhere(
          (e) => e.toString().split('.').last == userProgressData['status'],
          orElse: () => ChallengeStatus.notStarted,
        );
        currentStepVal = UserProfile._parseFirestoreInt(
            userProgressData['current_step'], 0, 'current_step');
        userStartedAtTime = userProgressData['started_at'] as Timestamp?;
        currentSelectedStore = userProgressData['selected_store'] as String?;
        currentProofImageIdentifier =
            userProgressData['proof_image_identifier'] as String?;
        currentOcrResultText = userProgressData['ocr_result_text'] as String?;
        currentIsProofValid = userProgressData['is_proof_valid'] as bool?;
        lastCompletedTimestamp =
            userProgressData['last_completed_at'] as Timestamp?;
      }
    }

    return Challenge(
      id: challengeId,
      title: challengeData['title'] as String? ?? 'Défi sans titre',
      rewardText:
          challengeData['reward_text'] as String? ?? 'Récompense standard',
      rewardLame: UserProfile._parseFirestoreInt(
          challengeData['reward_lame'], 0, 'reward_lame'),
      totalDurationSeconds: totalDuration,
      createdAt: challengeData['created_at'] as Timestamp? ?? Timestamp.now(),
      type: ChallengeType.values.firstWhere(
        (e) => e.toString() == 'ChallengeType.${challengeData?['type']}',
        orElse: () => ChallengeType.visitMultiple,
      ),
      totalSteps: UserProfile._parseFirestoreInt(
          challengeData['total_steps'], 1, 'total_steps'),
      storeOptions: challengeData['store_options'] != null
          ? List<String>.from(challengeData['store_options'] as List)
          : null,
      latitude: UserProfile._parseFirestoreDouble(
          challengeData['latitude'], 0.0, 'latitude'),
      longitude: UserProfile._parseFirestoreDouble(
          challengeData['longitude'], 0.0, 'longitude'),
      partnerStoreId: challengeData['partner_store_id'] as String?,
      googlePlaceId: challengeData['google_place_id'] as String?,
      userChallengeDocId: currentUserChallengeDocId,
      status: currentStatus,
      currentStep: currentStepVal,
      startedAtUser: userStartedAtTime,
      selectedStore: currentSelectedStore,
      proofImageIdentifier: currentProofImageIdentifier,
      ocrResultText: currentOcrResultText,
      isProofValid: currentIsProofValid,
      visitCount: UserProfile._parseFirestoreInt(
          challengeData['visit_count'], 1, 'visit_count'),
      stayDurationSeconds: UserProfile._parseFirestoreInt(
          challengeData['stay_duration_seconds'], 0, 'stay_duration_seconds'),
      lastCompletedAt: lastCompletedTimestamp,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'reward_text': rewardText,
      'reward_lame': rewardLame,
      'total_duration_seconds': totalDurationSeconds,
      'created_at': createdAt,
      'type': type.toString().split('.').last,
      'total_steps': totalSteps,
      'store_options': storeOptions,
      'latitude': latitude,
      'longitude': longitude,
      'partner_store_id': partnerStoreId,
      'google_place_id': googlePlaceId,
      'visit_count': visitCount,
      'stay_duration_seconds': stayDurationSeconds,
    };
  }

  Challenge copyWith({
    String? id,
    String? title,
    String? rewardText,
    int? rewardLame,
    int? totalDurationSeconds,
    Timestamp? createdAt,
    ValueGetter<String?>? userChallengeDocId,
    ChallengeStatus? status,
    int? currentStep,
    ValueGetter<Timestamp?>? startedAtUser,
    ValueGetter<String?>? selectedStore,
    ValueGetter<String?>? proofImageIdentifier,
    ValueGetter<String?>? ocrResultText,
    ValueGetter<bool?>? isProofValid,
    ChallengeType? type,
    int? totalSteps,
    ValueGetter<List<String>?>? storeOptions,
    ValueGetter<double?>? latitude,
    ValueGetter<double?>? longitude,
    ValueGetter<String?>? partnerStoreId,
    ValueGetter<String?>? googlePlaceId,
    ValueGetter<Timestamp?>? lastCompletedAt,
    int? visitCount,
    int? stayDurationSeconds,
  }) {
    return Challenge(
      id: id ?? this.id,
      title: title ?? this.title,
      rewardText: rewardText ?? this.rewardText,
      rewardLame: rewardLame ?? this.rewardLame,
      totalDurationSeconds: totalDurationSeconds ?? this.totalDurationSeconds,
      createdAt: createdAt ?? this.createdAt,
      userChallengeDocId: userChallengeDocId != null
          ? userChallengeDocId()
          : this.userChallengeDocId,
      status: status ?? this.status,
      currentStep: currentStep ?? this.currentStep,
      startedAtUser:
          startedAtUser != null ? startedAtUser() : this.startedAtUser,
      selectedStore:
          selectedStore != null ? selectedStore() : this.selectedStore,
      proofImageIdentifier: proofImageIdentifier != null
          ? proofImageIdentifier()
          : this.proofImageIdentifier,
      ocrResultText:
          ocrResultText != null ? ocrResultText() : this.ocrResultText,
      isProofValid: isProofValid != null ? isProofValid() : this.isProofValid,
      type: type ?? this.type,
      totalSteps: totalSteps ?? this.totalSteps,
      storeOptions: storeOptions != null ? storeOptions() : this.storeOptions,
      latitude: latitude != null ? latitude() : this.latitude,
      longitude: longitude != null ? longitude() : this.longitude,
      partnerStoreId:
          partnerStoreId != null ? partnerStoreId() : this.partnerStoreId,
      googlePlaceId:
          googlePlaceId != null ? googlePlaceId() : this.googlePlaceId,
      lastCompletedAt:
          lastCompletedAt != null ? lastCompletedAt() : this.lastCompletedAt,
      visitCount: visitCount ?? this.visitCount,
      stayDurationSeconds: stayDurationSeconds != null
          ? stayDurationSeconds
          : this.stayDurationSeconds,
    );
  }

  Map<String, dynamic> toUserChallengeMap(String userId) {
    return {
      'user_id': userId,
      'challenge_id': id,
      'status': status.toString().split('.').last,
      'current_step': currentStep,
      'started_at': startedAtUser ?? FieldValue.serverTimestamp(),
      'selected_store': selectedStore,
      'proof_image_identifier': proofImageIdentifier,
      'ocr_result_text': ocrResultText,
      'is_proof_valid': isProofValid,
      'last_completed_at': (status == ChallengeStatus.completedPendingReward ||
              status == ChallengeStatus.rewardClaimed ||
              status == ChallengeStatus.expired)
          ? FieldValue.serverTimestamp()
          : null,
    };
  }

  String get dynamicChallengeDescription {
    switch (type) {
      case ChallengeType.visitMultiple:
        return "Rends-toi ${visitCount ?? totalSteps} fois à ce lieu.";
      case ChallengeType.localPoiVisit:
        String visitText = "";
        if (visitCount != null && visitCount! > 1) {
          visitText = "Rends-toi $visitCount fois ";
        } else {
          visitText = "Rends-toi ";
        }
        if (stayDurationSeconds != null && stayDurationSeconds! > 0) {
          final minutes = (stayDurationSeconds! / 60).round();
          visitText += "à ce lieu et restes-y $minutes minute(s).";
        } else {
          visitText += "à ce lieu.";
        }
        return visitText;
      case ChallengeType.purchaseScanProof:
        return "Rends-toi à un magasin ${storeOptions?.join(', ')} et scanne une preuve d'achat.";
      case ChallengeType.partnerStoreVisit:
        return "Rends-toi au magasin partenaire et scanne une preuve d'achat.";
      default:
        return rewardText;
    }
  }

  bool isBlockedForUser(Timestamp? lastCompletedAt) {
    if (lastCompletedAt == null) return false;
    final now = DateTime.now();
    final completedDate = lastCompletedAt.toDate();
    final sevenDaysLater = completedDate.add(const Duration(days: 7));
    return now.isBefore(sevenDaysLater);
  }
}

class EcoStore {
  final String id;
  final String name;
  final String address;
  final latlong.LatLng coordinates;
  final String description;
  final String category;

  // --- Options Commerciales ---
  final bool isCashbackEnabled; // Le socle
  final double cashbackRate; // Taux (ex: 0.05)

  final bool isVisibilityBoostEnabled; // Le Slider (Défis)
  final double lamePointMultiplier; // Valeur du slider (ex: 1.2)

  final bool
      isPremiumAdBoostEnabled; // Pub (Commission 40%) - Requiert Cashback
  final bool isGoldStoreEnabled; // Or (5€) - Requiert Cashback

  final double? minimumPurchase;
  final List<LoyaltyRule> loyaltyRules;
  final String? ownerId;

  // Facturation
  final double currentMonthDebt;
  final double totalAmountSpentByUser;
  final double totalCashbackGiven;

  EcoStore({
    required this.id,
    required this.name,
    required this.address,
    required this.coordinates,
    required this.description,
    this.category = 'Autre',
    this.isCashbackEnabled = true,
    required this.cashbackRate,
    this.isVisibilityBoostEnabled = false,
    this.lamePointMultiplier = 1.0,
    this.isPremiumAdBoostEnabled = false,
    this.isGoldStoreEnabled = false,
    this.minimumPurchase,
    this.loyaltyRules = const [],
    this.ownerId,
    this.currentMonthDebt = 0.0,
    this.totalAmountSpentByUser = 0.0,
    this.totalCashbackGiven = 0.0,
  });

  factory EcoStore.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) throw Exception("EcoStore data is null");

    latlong.LatLng coords;
    if (data['coordinates'] is GeoPoint) {
      final geoPoint = data['coordinates'] as GeoPoint;
      coords = latlong.LatLng(geoPoint.latitude, geoPoint.longitude);
    } else {
      coords = latlong.LatLng(
        (data['latitude'] as num?)?.toDouble() ?? 0.0,
        (data['longitude'] as num?)?.toDouble() ?? 0.0,
      );
    }

    List<LoyaltyRule> rules = [];
    if (data['loyalty_rules'] != null) {
      rules = (data['loyalty_rules'] as List)
          .map((x) => LoyaltyRule.fromMap(x))
          .toList();
    }

    return EcoStore(
      id: snapshot.id,
      name: data['name'] as String? ?? 'Magasin',
      address: data['address'] as String? ?? 'Adresse inconnue',
      coordinates: coords,
      description: data['description'] as String? ?? '',
      category: data['category'] as String? ?? 'Autre',

      // Lecture des options
      isCashbackEnabled: data['is_cashback_enabled'] as bool? ?? true,
      cashbackRate: UserProfile._parseFirestoreDouble(
          data['cashback_rate'], 0.05, 'cashback_rate'),

      isVisibilityBoostEnabled:
          data['is_visibility_boost_enabled'] as bool? ?? false,
      lamePointMultiplier:
          (data['lame_point_multiplier'] as num?)?.toDouble() ?? 1.0,

      isPremiumAdBoostEnabled:
          data['is_premium_ad_boost_enabled'] as bool? ?? false,
      isGoldStoreEnabled: data['is_gold_store_enabled'] as bool? ?? false,

      minimumPurchase: UserProfile._parseFirestoreDouble(
          data['minimum_purchase'], 0.0, 'minimum_purchase'),
      ownerId: data['owner_id'] as String?,
      currentMonthDebt: UserProfile._parseFirestoreDouble(
          data['current_month_debt'], 0.0, 'current_month_debt'),
      totalAmountSpentByUser: UserProfile._parseFirestoreDouble(
          data['totalAmountSpentByUser'], 0.0, 'totalAmountSpentByUser'),
      totalCashbackGiven: UserProfile._parseFirestoreDouble(
          data['totalCashbackGiven'], 0.0, 'totalCashbackGiven'),
      loyaltyRules: rules,
    );
  }
}

class LoyaltyRule {
  final String type;
  final double threshold;
  final double rewardPercent;
// Ces champs doivent exister :
  final double? minPurchaseAmount;
  final int? minStayDurationSeconds;

  LoyaltyRule({
    required this.type,
    required this.threshold,
    required this.rewardPercent,
    this.minPurchaseAmount, // Ici
    this.minStayDurationSeconds, // Et ici
  });

  Map<String, dynamic> toMap() =>
      {'type': type, 'threshold': threshold, 'rewardPercent': rewardPercent};

  factory LoyaltyRule.fromMap(Map<String, dynamic> map) {
    return LoyaltyRule(
      type: map['type'] ?? 'visit',
      threshold: (map['threshold'] as num).toDouble(),
      rewardPercent: (map['rewardPercent'] as num).toDouble(),
    );
  }
}

class ShopItem {
  final String id;
  String name;
  int costLame;
  String type;
  String iconName;

  ShopItem(
      {required this.id,
      required this.name,
      required this.costLame,
      required this.type,
      required this.iconName});

  factory ShopItem.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data();
    if (data == null) {
      throw Exception("Shop item data is null for snapshot ID: ${snapshot.id}");
    }
    return ShopItem(
        id: snapshot.id,
        name: data['name'] as String? ?? 'Objet Inconnu',
        costLame: UserProfile._parseFirestoreInt(
            data['cost_lame'], 9999, 'cost_lame'),
        type: data['type'] as String? ?? 'Divers',
        iconName: data['icon'] as String? ?? 'store');
  }
  IconData get icon {
    switch (iconName) {
      case 'card_giftcard':
        return Icons.card_giftcard_rounded;
      case 'account_balance_wallet':
        return Icons.account_balance_wallet_rounded;
      default:
        return Icons.store_rounded;
    }
  }
}

const bool ENABLE_SECURITY_CHECKS = false;

/// ================================================================
/// SERVICE DE FOND : Détection position domicile et Navigation
/// ================================================================
@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  const int HOME_RADIUS_METERS = 150;
  const int NAV_CHECK_INTERVAL_SECONDS = 5;
  const int HOME_CHECK_INTERVAL_SECONDS = 60;

  Timer? bgTimer;
  LatLng? _lastNavPosition;
  DateTime? _lastNavTime;

  // --- VARIABLES D'ÉTAT BACKGROUND (Pour l'anti-triche) ---
  List<double> bgRecentSpeeds = [];
  DateTime? bgTransitOffRouteSince;
  double bgCumulatedDeviationMeters = 0.0;
  Map<String, double>? bgLastOnRoutePosition;
  DateTime? bgHighSpeedBurstStartTime;
  // ---------------------------------------------------------

  // Fonction mathématique pour projeter un point sur un segment (Distance à la route)
  Map<String, double> _projectToSegment(
      double px, double py, double ax, double ay, double bx, double by) {
    double l2 = pow(ax - bx, 2).toDouble() + pow(ay - by, 2).toDouble();
    if (l2 == 0.0) return {'lat': ax, 'lng': ay};
    double t = ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / l2;
    t = max(0, min(1, t));
    return {'lat': ax + t * (bx - ax), 'lng': ay + t * (by - ay)};
  }

  // Notifier l'utilisateur pour le forcer à ouvrir l'appli (remplace la popup)
  Future<void> _showBackgroundWarning(String title, String body) async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'walkmoney_warning_channel',
      'Avertissements',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    await flutterLocalNotificationsPlugin.show(
        999, title, body, const NotificationDetails(android: androidDetails));
  }

  Future<void> _bgLog(String message,
      [Object? error, StackTrace? stack]) async {
    final log = '[BG] $message${error != null ? ' - erreur: $error' : ''}';
    print(log);
    if (stack != null) {
      print(stack);
    }
  }

  Future<void> _safeServiceInvoke(
      ServiceInstance service, String event, Map<String, dynamic> payload,
      {int maxRetry = 2}) async {
    for (int attempt = 1; attempt <= maxRetry; attempt++) {
      try {
        // Use dynamic dispatch to avoid static void return type checks.
        final dynamic invokeResult =
            (service as dynamic).invoke(event, payload);
        if (invokeResult is Future) {
          await invokeResult;
        }
        return;
      } catch (e, stack) {
        await _bgLog(
            'Echec d\'invoque service [$event] tentative $attempt/$maxRetry',
            e,
            stack);
        if (attempt == maxRetry) {
          await _bgLog('Echec définitif de $event,essai abandonné');
        } else {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
    }
  }

  Future<void> checkHomeDistance(
      SharedPreferences prefs, Position position) async {
    try {
      await prefs.reload();
      final double? homeLat = prefs.getDouble('user_home_lat');
      final double? homeLng = prefs.getDouble('user_home_lng');
      if (homeLat == null || homeLng == null) return;

      final hasPending =
          prefs.getStringList('pending_validation_store_ids')?.isNotEmpty ??
              false;
      if (!hasPending) return;

      double distToHome = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        homeLat,
        homeLng,
      );

      if (distToHome <= HOME_RADIUS_METERS) {
        final List<String> storeIds =
            prefs.getStringList('pending_validation_store_ids') ?? [];
        final String? storeTimestampsJson =
            prefs.getString('pending_validation_timestamps');
        Map<String, dynamic> timestamps = {};
        if (storeTimestampsJson != null) {
          try {
            timestamps =
                Map<String, dynamic>.from(jsonDecode(storeTimestampsJson));
          } catch (_) {}
        }

        final bool isPremium = prefs.getBool('user_is_premium') ?? false;
        final List<String> remainingIds = [];

        if (isPremium) {
          final now = DateTime.now();
          for (final id in storeIds) {
            final tsStr = timestamps[id] as String?;
            if (tsStr != null) {
              final ts = DateTime.tryParse(tsStr);
              if (ts != null && now.difference(ts).inHours < 24) {
                remainingIds.add(id);
              }
            }
          }
        }

        await prefs.setStringList('pending_validation_store_ids', remainingIds);
        if (remainingIds.isEmpty)
          await prefs.remove('pending_validation_timestamps');

        await _safeServiceInvoke(service, 'user_returned_home',
            {'cleared': true, 'remaining': remainingIds.length});
        await _bgLog('[BG] Retour domicile détecté – validations effacées');
      }
    } catch (e) {
      print('[BG] Erreur détection domicile: $e');
    }
  }

  Future<void> checkNavigationAndSecurity(
      SharedPreferences prefs, Position position) async {
    try {
      await prefs.reload();
      final bool isNavigating = prefs.getBool('bg_is_navigating') ?? false;
      final bool isAppInForeground =
          prefs.getBool('is_app_in_foreground') ?? false;

      if (!isNavigating) return;
      if (isAppInForeground) {
        // L'application gère déjà l'anti-triche et la navigation au premier plan.
        return;
      }

      // 1. Vérification faux GPS
      try {
        bool isMock = await SafeDevice.isMockLocation;
        if (isMock) {
          await _safeServiceInvoke(
              service, 'cheat_detected', {'reason': 'fake_gps'});
          return;
        }
      } catch (_) {}

      // Restituer l'état anti-triche depuis SharedPreferences (résistance au kill Android)
      bgCumulatedDeviationMeters = prefs.getDouble('bg_cumulated_deviation') ??
          bgCumulatedDeviationMeters;
      final savedSpeeds = prefs.getStringList('bg_recent_speeds');
      if (savedSpeeds != null &&
          savedSpeeds.isNotEmpty &&
          bgRecentSpeeds.isEmpty) {
        bgRecentSpeeds =
            savedSpeeds.map((s) => double.tryParse(s) ?? 0.0).toList();
      }

      final double speedKmh = position.speed * 3.6;
      final String modeStr = prefs.getString('bg_travel_mode') ?? 'walking';

      // --- CORRECTION 1 : Facteur de dénivelé intelligent ---
      final double elevFactor = prefs.getDouble('bg_elevation_factor') ?? 1.0;

      // --- CORRECTION 5 : Détection Robot (Variance de vitesse) ---
      if (speedKmh > 3.0 && modeStr == 'walking') {
        bgRecentSpeeds.add(speedKmh);
        if (bgRecentSpeeds.length > 20) bgRecentSpeeds.removeAt(0);
        await prefs.setStringList('bg_recent_speeds',
            bgRecentSpeeds.map((s) => s.toString()).toList());

        if (bgRecentSpeeds.length >= 15) {
          double mean =
              bgRecentSpeeds.reduce((a, b) => a + b) / bgRecentSpeeds.length;
          double variance = bgRecentSpeeds
                  .map((v) => pow(v - mean, 2))
                  .reduce((a, b) => a + b) /
              bgRecentSpeeds.length;

          if (variance < 0.2 && mean > 7.0) {
            await _safeServiceInvoke(
                service, 'cheat_detected', {'reason': 'robot_variance'});
            return;
          }
        }
      }

      // --- GESTION DE LA VITESSE (Limites ajustées par le dénivelé) ---
      if (modeStr != 'transit') {
        double maxSpeedWalk = MAX_WALK_SPEED_KMH * elevFactor;
        double maxSpeedBike = MAX_BIKE_SPEED_KMH * elevFactor;
        double carSuspectThreshold = MAX_CAR_SUSPECT_SPEED_KMH; // Insta-ban

        if (modeStr == 'walking') {
          if (speedKmh > carSuspectThreshold) {
            await _safeServiceInvoke(service, 'cheat_detected',
                {'reason': 'vehicle_speed_violation'});
            return;
          } else if (speedKmh > MAX_WALK_SPEED_KMH) {
            // CORRECTION 2 : Absence de Pop-up -> Notification + Pause
            if (speedKmh <= WARNING_SPEED_THRESHOLD_KMH) {
              _showBackgroundWarning("Vitesse élevée 🚲",
                  "Vous roulez vite ! Ouvrez l'application pour confirmer votre mode de transport.");
              return;
            }

            // Si > 60km/h pendant plus de 15s en marchant (Grosse triche)
            bgHighSpeedBurstStartTime ??= DateTime.now();
            if (DateTime.now()
                    .difference(bgHighSpeedBurstStartTime!)
                    .inSeconds >
                15) {
              await _safeServiceInvoke(service, 'cheat_detected',
                  {'reason': 'speed_violation_burst'});
              return;
            }
          } else {
            bgHighSpeedBurstStartTime = null;
          }
        } else if (modeStr.contains('bicycling')) {
          if (speedKmh > maxSpeedBike) {
            bgHighSpeedBurstStartTime ??= DateTime.now();
            int tolerance =
                elevFactor < 0.95 ? 30 : 20; // Plus tolérant en descente
            if (DateTime.now()
                    .difference(bgHighSpeedBurstStartTime!)
                    .inSeconds >
                tolerance) {
              if (speedKmh > MAX_VEHICLE_SPEED_VIOLATION_KMH) {
                await _safeServiceInvoke(service, 'cheat_detected',
                    {'reason': 'vehicle_speed_violation'});
              } else {
                _showBackgroundWarning("Vitesse excessive",
                    "Réduisez l'allure ou vérifiez votre mode de transport.");
                return; // Pause
              }
            }
          } else {
            bgHighSpeedBurstStartTime = null;
          }
        }
      }

      // --- CORRECTIONS 3 & 4 : DÉVIATION ET TRANSIT ---
      String? polyStr = prefs.getString('bg_route_polyline');
      if (polyStr != null && polyStr.isNotEmpty) {
        List<dynamic> decoded = jsonDecode(polyStr);
        double minDistToRoute = double.infinity;
        Map<String, double> closestPoint = {
          'lat': position.latitude,
          'lng': position.longitude
        };

        // Trouver le point le plus proche sur le tracé
        for (int i = 0; i < decoded.length - 1; i++) {
          var p1 = decoded[i];
          var p2 = decoded[i + 1];
          var proj = _projectToSegment(position.latitude, position.longitude,
              p1['lat'], p1['lng'], p2['lat'], p2['lng']);
          double d = Geolocator.distanceBetween(position.latitude,
              position.longitude, proj['lat']!, proj['lng']!);
          if (d < minDistToRoute) {
            minDistToRoute = d;
            closestPoint = proj;
          }
        }

        // CORRECTION 4 : Triche spécifique aux Transports en commun
        if (modeStr == 'transit') {
          if (minDistToRoute > 30.0) {
            bgTransitOffRouteSince ??= DateTime.now();
            if (DateTime.now().difference(bgTransitOffRouteSince!).inSeconds >
                60) {
              await _safeServiceInvoke(
                  service, 'cheat_detected', {'reason': 'transit_off_route'});
              return;
            }
          } else {
            bgTransitOffRouteSince = null;
          }
        }
        // CORRECTION 3 : Déviation Marche / Vélo
        else {
          double maxDevAllowed = prefs.getDouble('bg_max_deviation') ?? 3000.0;

          if (minDistToRoute > 30.0) {
            Map<String, double> refPoint =
                bgLastOnRoutePosition ?? closestPoint;
            double distSinceLastOnRoute = Geolocator.distanceBetween(
                position.latitude,
                position.longitude,
                refPoint['lat']!,
                refPoint['lng']!);

            if (distSinceLastOnRoute > bgCumulatedDeviationMeters) {
              bgCumulatedDeviationMeters = distSinceLastOnRoute;
              await prefs.setDouble(
                  'bg_cumulated_deviation', bgCumulatedDeviationMeters);
            }

            // Si on explose la limite globale, BAN.
            if (bgCumulatedDeviationMeters > maxDevAllowed) {
              await _safeServiceInvoke(service, 'cheat_detected',
                  {'reason': 'max_deviation_exceeded'});
              return;
            }
          } else {
            bgLastOnRoutePosition = closestPoint;
            bgCumulatedDeviationMeters = 0.0;
            await prefs.setDouble('bg_cumulated_deviation', 0.0);
          }
        }
      }

      // Envoi de la position propre au foreground
      await _safeServiceInvoke(service, 'bg_position_update', {
        'lat': position.latitude,
        'lng': position.longitude,
        'speed': speedKmh,
        'heading': position.heading,
        'timestamp': DateTime.now().toIso8601String(),
      });

      _lastNavPosition = LatLng(position.latitude, position.longitude);
      _lastNavTime = DateTime.now();
    } catch (e) {
      print('[BG] Erreur navigation: $e');
    }
  }

  StreamSubscription<Position>? iosKeepAliveStream;
  StreamSubscription<Position>? bgPositionStream;

  void startBackgroundTracking(bool isNavigating) {
    bgTimer?.cancel();
    bgPositionStream?.cancel();
    iosKeepAliveStream?.cancel();

    if (Platform.isIOS && isNavigating) {
      iosKeepAliveStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          distanceFilter: 10,
        ),
      ).listen((_) {});
    }

    final LocationSettings locationSettings;
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: isNavigating
            ? LocationAccuracy.bestForNavigation
            : LocationAccuracy.medium,
        distanceFilter: isNavigating
            ? 15
            : 20, // Réveil uniquement sur déplacement de 15-20m
        intervalDuration: Duration(seconds: isNavigating ? 5 : 30),
        forceLocationManager: false,
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: isNavigating
            ? LocationAccuracy.bestForNavigation
            : LocationAccuracy.medium,
        distanceFilter: isNavigating ? 15 : 20,
        pauseLocationUpdatesAutomatically: true,
        activityType: isNavigating ? ActivityType.fitness : ActivityType.other,
      );
    } else {
      locationSettings = LocationSettings(
        accuracy: isNavigating
            ? LocationAccuracy.bestForNavigation
            : LocationAccuracy.medium,
        distanceFilter: isNavigating ? 15 : 20,
      );
    }

    bgPositionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) async {
      final prefs = await SharedPreferences.getInstance();
      await checkHomeDistance(prefs, position);
      await checkNavigationAndSecurity(prefs, position);
    });
  }

  startBackgroundTracking(false);

  service.on('stop_background_trip').listen((event) async {
    startBackgroundTracking(true);

    bgRecentSpeeds.clear();
    bgTransitOffRouteSince = null;
    bgCumulatedDeviationMeters = 0.0;
    bgLastOnRoutePosition = null;
    bgHighSpeedBurstStartTime = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('bg_cumulated_deviation');
    await prefs.remove('bg_recent_speeds');

    print('[BG] Navigation démarrée (surveillance accrue)');
  });

  service.on('resume_background_tracking').listen((event) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_is_navigating', false);
    await prefs.remove('bg_cumulated_deviation');
    await prefs.remove('bg_recent_speeds');
    startBackgroundTracking(false);
    print('[BG] Navigation terminée → surveillance domicile économe');
  });
}

/// Initialise le service de fond
Future<void> _initBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel bgChannel = AndroidNotificationChannel(
    'walkmoney_bg_channel',
    'WalkMoney Arrière-plan',
    description: 'Détection de votre position pour les validations',
    importance: Importance.low,
  );

  const AndroidNotificationChannel warningChannel = AndroidNotificationChannel(
    'walkmoney_warning_channel',
    'Avertissements',
    description: 'Avertissements liés à votre vitesse ou position',
    importance: Importance.high,
  );

  const AndroidNotificationChannel navChannel = AndroidNotificationChannel(
    'walkmoney_nav_channel',
    'Navigation WalkMoney',
    description: 'Notifications de navigation',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    final androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImplementation?.createNotificationChannel(bgChannel);
    await androidImplementation?.createNotificationChannel(warningChannel);
    await androidImplementation?.createNotificationChannel(navChannel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundServiceStart,
      autoStart: true,
      isForegroundMode: true,
      notificationChannelId: 'walkmoney_bg_channel',
      initialNotificationTitle: 'WalkMoney',
      initialNotificationContent: 'Surveillance position active',
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: true,
      onForeground: onBackgroundServiceStart,
      onBackground: _onIosBackground,
    ),
  );

  await service.startService();
}

@pragma('vm:entry-point')
Future<bool> _onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  return true;
}

void main() async {
  // 1. Initialisation des bindings (Obligatoire avant tout appel natif)
  WidgetsFlutterBinding.ensureInitialized();

  // Désactiver le téléchargement runtime des polices Google Fonts (évite l'erreur AssetManifest.json)
  GoogleFonts.config.allowRuntimeFetching = true;

  // --- CORRECTION CRITIQUE : Charger le fichier .env ---
  try {
    await dotenv.load(fileName: ".env");
    debugPrint("✅ DotEnv chargé avec succès");
  } catch (e) {
    debugPrint(
        "⚠️ Erreur chargement .env (Vérifiez qu'il est dans les assets) : $e");
  }
  // ----------------------------------------------------

  // 2. Bloquer l'orientation portrait
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // 3. Initialiser Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("✅ Firebase initialisé");
  } catch (e) {
    debugPrint("❌ Erreur Firebase : $e");
  }

  // 4. Initialiser la locale (fr_FR)
  await initializeDateFormatting('fr_FR', null);

  // 5. Initialisation STRIPE
  try {
    String? stripeKey = dotenv.env['STRIPE_PUBLISHABLE_KEY'];
    if (stripeKey != null && stripeKey.isNotEmpty) {
      Stripe.publishableKey = stripeKey;
      await Stripe.instance.applySettings();
      debugPrint("✅ Stripe initialisé");
    } else {
      debugPrint(
          "⚠️ Clé STRIPE_PUBLISHABLE_KEY non configurée dans le fichier .env");
    }
  } catch (e) {
    debugPrint("❌ Erreur Stripe : $e");
  }

  // 6. Vérification Sécurité (Root / Jailbreak)
  // (Utilise votre constante globale définie plus haut)
  if (ENABLE_SECURITY_CHECKS) {
    try {
      bool isJailBroken = await SafeDevice.isJailBroken;
      if (isJailBroken) {
        runApp(const SecurityBlockedScreen(
            reason: "Appareil Rooté ou Jailbreaké détecté."));
        return; // On arrête l'app ici
      }
    } catch (e) {
      debugPrint("Erreur check sécurité (ignorée) : $e");
    }
  }

  // 7. Injection des dépendances GetX
  Get.put(HomeController());
  Get.put(SpeedController());
  Get.put(NavigationController());
  Get.put(UserStatsController());
  Get.put(LeaderboardController());
  Get.put(MainTabController());

  // 8. Démarrer le service de fond (détection domicile en arrière-plan)
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      await _initBackgroundService();
      debugPrint("✅ Service background initialisé");
    } catch (e) {
      debugPrint("⚠️ Service background non démarré: $e");
    }
  }

  // 9. Lancement de l'application
  runApp(EcoNavApp());
}

class EcoNavApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'EcoNav',
      translations: AppTranslations(),
      locale: Get.deviceLocale,
      fallbackLocale: const Locale('fr', 'FR'),
      theme: ThemeData(
        primaryColor: primaryGreen,
        scaffoldBackgroundColor: defisScreenBackground,
        canvasColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primaryGreen,
          primary: primaryGreen,
          secondary: accentGold,
          surface: cardWhite,
          background: defisScreenBackground,
          onPrimary: Colors.white,
          onSecondary: textDark,
          onSurface: textDark,
          onBackground: textDark,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: textDark,
          titleTextStyle: TextStyle(
              fontSize: 20, fontWeight: FontWeight.bold, color: textDark),
          centerTitle: true,
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
            selectedItemColor: primaryGreen,
            unselectedItemColor: textGrey,
            backgroundColor: cardWhite,
            elevation: 8,
            selectedLabelStyle: TextStyle(fontWeight: FontWeight.w600)),
        elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
                backgroundColor: defisPrimaryButton,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold))),
        outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
                foregroundColor: defisSecondaryButtonText,
                backgroundColor: defisSecondaryButton,
                side: BorderSide.none,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold))),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Colors.white,
          foregroundColor: primaryGreen,
          elevation: 4.0,
          shape: CircleBorder(),
        ),
        textTheme: TextTheme(
          headlineMedium: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 18, color: textDark),
          titleLarge: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 16, color: textDark),
          titleMedium: TextStyle(
              fontWeight: FontWeight.normal,
              fontSize: 13,
              color: Colors.grey[700]),
          bodyLarge: const TextStyle(
              fontSize: 14, color: textDark, fontWeight: FontWeight.bold),
          bodyMedium: const TextStyle(fontSize: 13, color: textGrey),
        ),
        useMaterial3: true,
      ),
      home: const OnboardingGuard(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MainTabController extends GetxController {
  final RxInt currentIndex = 0.obs;

  void changeTab(int index) {
    currentIndex.value = index;
  }
}

class LeaderboardController extends GetxController {
  final RxString selectedFilter = 'country'.obs;
  final RxString userCountry = 'Chargement...'.obs;
  final RxBool isLoadingCountry = true.obs;
  final RxList<String> friendIds = <String>[].obs;
  final RxBool isLoadingFriends = true.obs;

  @override
  void onInit() {
    super.onInit();
    fetchUserCountry();
    fetchFriendIds();
  }

  Future<void> fetchUserCountry() async {
    final userId = _firebaseAuth.currentUser?.uid;
    if (userId == null) {
      userCountry.value = 'Monde';
      selectedFilter.value = 'world';
      isLoadingCountry.value = false;
      return;
    }

    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists &&
          (userDoc.data() as Map<String, dynamic>).containsKey('country')) {
        final country = userDoc.get('country');
        if (country != null && country.isNotEmpty) {
          userCountry.value = country;
          isLoadingCountry.value = false;
          return;
        }
      }

      final response = await http.get(Uri.parse('http://ip-api.com/json'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final country = data['country'];
        if (country != null) {
          await _firestore
              .collection('users')
              .doc(userId)
              .update({'country': country});
          userCountry.value = country;
          isLoadingCountry.value = false;
        }
      } else {
        throw Exception('Failed to load country from IP');
      }
    } catch (e) {
      print("Erreur de détection du pays: $e");
      userCountry.value = 'Monde';
      selectedFilter.value = 'world';
      isLoadingCountry.value = false;
    }
  }

  Future<void> fetchFriendIds() async {
    final userId = _firebaseAuth.currentUser?.uid;
    if (userId == null) {
      friendIds.clear();
      isLoadingFriends.value = false;
      return;
    }

    try {
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists) {
        final ids =
            (userDoc.data()?['friend_ids'] as List<dynamic>?)?.cast<String>() ??
                [];
        friendIds.assignAll(ids);
        isLoadingFriends.value = false;
      }
    } catch (e) {
      print("Erreur chargement amis: $e");
      friendIds.clear();
      isLoadingFriends.value = false;
    }
  }
}

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(LeaderboardController());

    return Obx(() {
      Query<Map<String, dynamic>> query = _firestore
          .collection('users')
          .orderBy('total_lame_earned', descending: true)
          .limit(100);

      if (controller.selectedFilter.value == 'country' &&
          !controller.isLoadingCountry.value &&
          controller.userCountry.value != 'Monde') {
        query = query.where('country', isEqualTo: controller.userCountry.value);
      } else if (controller.selectedFilter.value == 'friends' &&
          !controller.isLoadingFriends.value) {
        if (controller.friendIds.isNotEmpty) {
          List<String> queryIds = List.from(controller.friendIds);
          final currentUserId = _firebaseAuth.currentUser?.uid;
          if (currentUserId != null && !queryIds.contains(currentUserId)) {
            queryIds.add(currentUserId);
          }
          query = query.where(FieldPath.documentId, whereIn: queryIds);
        }
      }

      return Scaffold(
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: CupertinoSlidingSegmentedControl<String>(
                groupValue: controller.selectedFilter.value,
                onValueChanged: (value) {
                  if (value != null) {
                    controller.selectedFilter.value = value;
                  }
                },
                children: {
                  'country': Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(controller.isLoadingCountry.value
                        ? 'Mon Pays'
                        : controller.userCountry.value),
                  ),
                  'world': const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Text('Monde'),
                  ),
                  'friends': Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text('Amis (${controller.friendIds.length})'),
                  ),
                },
              ),
            ),
            Expanded(
              child: (controller.selectedFilter.value == 'friends' &&
                      controller.friendIds.isEmpty)
                  ? Center(
                      child: Text("Vous n'avez pas encore d'amis.",
                          style: Theme.of(context).textTheme.bodyLarge))
                  : (controller.selectedFilter.value == 'world')
                      ? _buildAggregatedLeaderboard(context)
                      : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: query.snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                    ConnectionState.waiting ||
                                controller.isLoadingCountry.value ||
                                controller.isLoadingFriends.value) {
                              return const Center(
                                  child: CircularProgressIndicator(
                                      color: primaryGreen));
                            }
                            if (snapshot.hasError) {
                              return Center(
                                  child: Text('Erreur: ${snapshot.error}',
                                      style:
                                          const TextStyle(color: Colors.red)));
                            }
                            if (!snapshot.hasData ||
                                snapshot.data!.docs.isEmpty) {
                              return Center(
                                  child: Text(
                                      'Aucun joueur dans ce classement.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge));
                            }

                            final userDocs = snapshot.data!.docs;
                            final currentUserId =
                                _firebaseAuth.currentUser?.uid;

                            return ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 8.0),
                              itemCount: userDocs.length,
                              itemBuilder: (context, index) {
                                final entry = LeaderboardEntry.fromFirestore(
                                    userDocs[index], index + 1);
                                final isCurrentUser = entry.id == currentUserId;
                                final userProfile = UserProfile.fromFirestore(
                                    userDocs[index] as DocumentSnapshot<
                                        Map<String, dynamic>>);

                                return Card(
                                  elevation: isCurrentUser ? 4 : 2,
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  color: isCurrentUser
                                      ? lightGreen.withOpacity(0.7)
                                      : cardWhite,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                    side: isCurrentUser
                                        ? const BorderSide(
                                            color: primaryGreen, width: 1.5)
                                        : BorderSide.none,
                                  ),
                                  child: ListTile(
                                    onTap: () => _showUserProfileDialog(
                                        context, userProfile, entry),
                                    leading: CircleAvatar(
                                      radius: 20,
                                      backgroundColor: isCurrentUser
                                          ? accentGold
                                          : primaryGreen,
                                      child: Text(
                                        '${entry.rank}',
                                        style: TextStyle(
                                          color: isCurrentUser
                                              ? textDark
                                              : Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                    title: Text(
                                      entry.username,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: textDark,
                                      ),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              'Niv. ${entry.userLevel}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: accentGold,
                                                fontSize: 16,
                                              ),
                                            ),
                                            Text(
                                              '${entry.lamePoints} L',
                                              style: const TextStyle(
                                                color: textGrey,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(width: 6),
                                        const Icon(Icons.military_tech_rounded,
                                            color: accentGold, size: 22),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildAggregatedLeaderboard(BuildContext context) {
    final currentUserId = _firebaseAuth.currentUser?.uid;

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream:
          _firestore.collection('leaderboards').doc('daily_top').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: primaryGreen));
        }

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data();
          final List<dynamic> entriesList =
              data?['entries'] as List<dynamic>? ?? [];

          if (entriesList.isEmpty) {
            return Center(
                child: Text('Aucun joueur dans ce classement.',
                    style: Theme.of(context).textTheme.bodyLarge));
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            itemCount: entriesList.length,
            itemBuilder: (context, index) {
              final Map<String, dynamic> entryMap =
                  Map<String, dynamic>.from(entriesList[index]);
              final entry = LeaderboardEntry.fromMap(entryMap, index + 1);
              final isCurrentUser = entry.id == currentUserId;

              return Card(
                elevation: isCurrentUser ? 4 : 2,
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                color: isCurrentUser ? lightGreen.withOpacity(0.7) : cardWhite,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: isCurrentUser
                      ? const BorderSide(color: primaryGreen, width: 1.5)
                      : BorderSide.none,
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: isCurrentUser ? accentGold : primaryGreen,
                    child: Text(
                      '${entry.rank}',
                      style: TextStyle(
                        color: isCurrentUser ? textDark : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  title: Text(
                    entry.username,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: textDark,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'Niv. ${entry.userLevel}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: accentGold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${entry.lamePoints} L',
                            style: const TextStyle(
                              color: textGrey,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.military_tech_rounded,
                          color: accentGold, size: 22),
                    ],
                  ),
                ),
              );
            },
          );
        }

        return Center(
            child: Text('Aucun joueur dans ce classement.',
                style: Theme.of(context).textTheme.bodyLarge));
      },
    );
  }

  void _showLevelsRewardsDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text("Récompenses de Niveaux",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold, color: primaryGreen)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: 100,
                itemBuilder: (ctx, index) {
                  int level = index + 1;
                  double multiplier = 1.0 + (level * 0.01);
                  String rewardText =
                      "Multiplicateur de Lames : x${multiplier.toStringAsFixed(2)}";
                  bool isMax = level == 100;
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          isMax ? accentGold : primaryGreen.withOpacity(0.2),
                      child: Text('$level',
                          style: TextStyle(
                              color: isMax ? Colors.white : primaryGreen,
                              fontWeight: FontWeight.bold)),
                    ),
                    title: Text("Niveau $level",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isMax ? accentGold : textDark)),
                    subtitle: Text(
                        isMax
                            ? "$rewardText\n🌟 Abonnement Premium Gratuit Débloqué !"
                            : rewardText,
                        style:
                            TextStyle(color: isMax ? accentGold : Colors.grey)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUserProfileDialog(
      BuildContext context, UserProfile userProfile, LeaderboardEntry entry) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isOwnProfile = currentUserId == userProfile.id;
    final isFriend = userProfile.friendIds.contains(currentUserId);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setState) {
        final bool hasSentRequest =
            userProfile.friendRequestsReceived.contains(currentUserId);
        final bool hasReceivedRequest =
            userProfile.friendRequestsSent.contains(currentUserId);

        return Container(
          decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(25)),
              gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Colors.green.shade50])),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: primaryGreen,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(25)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.white,
                        radius: 30,
                        child: Text(
                            userProfile.username.isNotEmpty
                                ? userProfile.username[0].toUpperCase()
                                : 'U',
                            style: const TextStyle(
                                color: primaryGreen,
                                fontSize: 24,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(userProfile.username,
                                  style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                              const SizedBox(height: 5),
                              InkWell(
                                onTap: () => _showLevelsRewardsDialog(context),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('Niveau ${entry.userLevel}',
                                          style: const TextStyle(
                                              fontSize: 14,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 5),
                                      const Icon(Icons.info_outline,
                                          color: Colors.white, size: 16),
                                    ],
                                  ),
                                ),
                              )
                            ]),
                      ),
                    ],
                  ),
                ),
                // Stats
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildLeaderboardStatCard(
                              '📍',
                              '${userProfile.totalDistanceKm.toStringAsFixed(1)}',
                              'Dist.'),
                          _buildLeaderboardStatCard('🚗',
                              '${userProfile.totalTripsCount}', 'Trajets'),
                          _buildLeaderboardStatCard('🏅',
                              '${userProfile.unlockedBadges.length}', 'Badges'),
                        ],
                      ),
                      const SizedBox(height: 25),
                      if (userProfile.unlockedBadges.isNotEmpty) ...[
                        const Text('Badges débloqués',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: textDark)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: userProfile.unlockedBadges.map((badgeName) {
                            final achievement = Achievement.all.firstWhere(
                              (a) => a.id == badgeName,
                              orElse: () => Achievement.all.first,
                            );
                            return Tooltip(
                              message: achievement.requirement,
                              child: Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.amber.shade100,
                                    border: Border.all(
                                        color: Colors.amber.shade600, width: 2),
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 4,
                                          offset: const Offset(0, 2))
                                    ]),
                                child: Center(
                                    child: Text(achievement.icon,
                                        style: const TextStyle(fontSize: 24))),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 20),
                      // Actions
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Fermer',
                                style: TextStyle(color: Colors.grey))),
                        if (!isOwnProfile) ...[
                          const SizedBox(width: 10),
                          if (isFriend)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.shade100,
                                  foregroundColor: Colors.red,
                                  elevation: 0),
                              icon: const Icon(Icons.person_remove),
                              label: const Text('Retirer'),
                              onPressed: () async {
                                await _firestore
                                    .collection('users')
                                    .doc(currentUserId)
                                    .update({
                                  'friend_ids':
                                      FieldValue.arrayRemove([userProfile.id]),
                                });
                                await _firestore
                                    .collection('users')
                                    .doc(userProfile.id)
                                    .update({
                                  'friend_ids':
                                      FieldValue.arrayRemove([currentUserId!]),
                                });
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            '${userProfile.username} retiré'),
                                        backgroundColor: Colors.green));
                              },
                            )
                          else if (hasSentRequest)
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange.shade100,
                                  foregroundColor: Colors.orange,
                                  elevation: 0),
                              icon: const Icon(Icons.hourglass_top),
                              label: const Text('En attente'),
                              onPressed: () async {
                                await _firestore
                                    .collection('users')
                                    .doc(currentUserId)
                                    .update({
                                  'friend_requests_sent':
                                      FieldValue.arrayRemove([userProfile.id]),
                                });
                                await _firestore
                                    .collection('users')
                                    .doc(userProfile.id)
                                    .update({
                                  'friend_requests_received':
                                      FieldValue.arrayRemove([currentUserId!]),
                                });
                                setState(() {});
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('✅ Demande annulée'),
                                        backgroundColor: Colors.green));
                              },
                            )
                          else if (hasReceivedRequest)
                            Row(
                              children: [
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryGreen,
                                      foregroundColor: Colors.white,
                                      elevation: 0),
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: const Text('Accepter'),
                                  onPressed: () async {
                                    await _firestore
                                        .collection('users')
                                        .doc(currentUserId)
                                        .update({
                                      'friend_ids': FieldValue.arrayUnion(
                                          [userProfile.id]),
                                      'friend_requests_received':
                                          FieldValue.arrayRemove(
                                              [userProfile.id]),
                                    });
                                    await _firestore
                                        .collection('users')
                                        .doc(userProfile.id)
                                        .update({
                                      'friend_ids': FieldValue.arrayUnion(
                                          [currentUserId!]),
                                      'friend_requests_sent':
                                          FieldValue.arrayRemove(
                                              [currentUserId]),
                                    });
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                            content: Text(
                                                '${userProfile.username} ajouté'),
                                            backgroundColor: Colors.green));
                                  },
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade100,
                                      foregroundColor: Colors.red,
                                      elevation: 0),
                                  child: const Icon(Icons.close),
                                  onPressed: () async {
                                    await _firestore
                                        .collection('users')
                                        .doc(currentUserId)
                                        .update({
                                      'friend_requests_received':
                                          FieldValue.arrayRemove(
                                              [userProfile.id]),
                                    });
                                    await _firestore
                                        .collection('users')
                                        .doc(userProfile.id)
                                        .update({
                                      'friend_requests_sent':
                                          FieldValue.arrayRemove(
                                              [currentUserId!]),
                                    });
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content: Text('Demande refusée'),
                                            backgroundColor: Colors.green));
                                  },
                                ),
                              ],
                            )
                          else
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                  backgroundColor: primaryGreen,
                                  foregroundColor: Colors.white,
                                  elevation: 0),
                              icon: const Icon(Icons.person_add),
                              label: const Text('Ajouter'),
                              onPressed: () async {
                                await _firestore
                                    .collection('users')
                                    .doc(currentUserId)
                                    .update({
                                  'friend_requests_sent':
                                      FieldValue.arrayUnion([userProfile.id]),
                                });
                                await _firestore
                                    .collection('users')
                                    .doc(userProfile.id)
                                    .update({
                                  'friend_requests_received':
                                      FieldValue.arrayUnion([currentUserId!]),
                                });
                                setState(() {});
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('✅ Demande envoyée!'),
                                        backgroundColor: Colors.green));
                              },
                            ),
                        ],
                      ])
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // Ajoute ce petit widget juste en dessous pour gérer l'affichage sans crasher
  Widget _buildLeaderboardStatCard(String icon, String value, String label) {
    return Container(
      width: 70,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Column(
        children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildProfileStat(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class StoreTripData {
  final EcoStore store;
  final TravelType travelType;

  StoreTripData({required this.store, required this.travelType});
}

class ChallengeTripData {
  final Challenge challenge;
  final TravelType travelType;
  final int estimatedReward;

  ChallengeTripData(
      {required this.challenge,
      required this.travelType,
      required this.estimatedReward});
}

class MainScreenController extends StatefulWidget {
  @override
  _MainScreenControllerState createState() => _MainScreenControllerState();
}

class _MainScreenControllerState extends State<MainScreenController>
    with WidgetsBindingObserver {
  // <--- AJOUT CRUCIAL ICI
  int _currentIndex = 0;
  UserProfile? _userProfile;
  WeatherData? _currentWeatherData;
  List<EcoStore> _ecoStores = [];
  StoreTripData? _pendingStoreTripData;
  ChallengeTripData? _pendingChallengeTripData;

  /// Map storeId → DateTime du trajet terminé, en attente de validation ticket
  final Map<String, DateTime> _pendingValidations = {};
  late HomeController _homeController;
  late NavigationController _navigationController;
  late SpeedController _speedController;
  final TextEditingController _destinationController = TextEditingController();
  final TextEditingController _originController = TextEditingController();
  String? get _currentUserId => _firebaseAuth.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool('is_app_in_foreground', true));
    _homeController = Get.find<HomeController>();
    _navigationController = Get.find<NavigationController>();
    _speedController = Get.find<SpeedController>();

    if (_currentUserId != null) {
      _fetchInitialData();
      _fetchEcoStores();
    } else {
      print(
          "CRITICAL: MainScreenController initialized without a current user.");
    }
    _requestNotificationPermissions();
    _fetchWeather();

    // Charger les validations en attente depuis SharedPreferences (persistance entre sessions)
    _loadPendingValidations();

    // Écouter le service background pour le retour domicile
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      FlutterBackgroundService().on('user_returned_home').listen((event) {
        if (mounted) {
          setState(() {
            // Vider les validations non-premium (le service a déjà nettoyé les prefs)
            _pendingValidations.clear();
          });
          _savePendingValidations();
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _destinationController.dispose();
    _originController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setBool('is_app_in_foreground', true));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setBool('is_app_in_foreground', false));
    }
  }

  /// Charge les validations en attente depuis SharedPreferences
  Future<void> _loadPendingValidations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storeIds =
          prefs.getStringList('pending_validation_store_ids') ?? [];
      final tsJson = prefs.getString('pending_validation_timestamps');
      Map<String, dynamic> timestamps = {};
      if (tsJson != null) {
        try {
          timestamps = Map<String, dynamic>.from(jsonDecode(tsJson));
        } catch (_) {}
      }

      final bool isPremium = _userProfile?.isVip ?? false;
      final now = DateTime.now();
      final Map<String, DateTime> loaded = {};

      for (final id in storeIds) {
        final tsStr = timestamps[id] as String?;
        if (tsStr != null) {
          final ts = DateTime.tryParse(tsStr);
          if (ts != null) {
            // Premium : conserver si < 24h. Non-premium : conserver si déjà ajouté (retour domicile = vidage)
            if (isPremium && now.difference(ts).inHours < 24) {
              loaded[id] = ts;
            } else if (!isPremium) {
              loaded[id] = ts;
            }
          }
        }
      }
      if (mounted) setState(() => _pendingValidations.addAll(loaded));
    } catch (e) {
      print('Erreur chargement validations: $e');
    }
  }

  /// Sauvegarde les validations en attente dans SharedPreferences
  Future<void> _savePendingValidations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
          'pending_validation_store_ids', _pendingValidations.keys.toList());
      final timestamps =
          _pendingValidations.map((k, v) => MapEntry(k, v.toIso8601String()));
      await prefs.setString(
          'pending_validation_timestamps', jsonEncode(timestamps));
      await prefs.setBool('user_is_premium', _userProfile?.isVip ?? false);
    } catch (e) {
      print('Erreur sauvegarde validations: $e');
    }
  }

  Future<void> _requestNotificationPermissions() async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    if (Platform.isAndroid) {
      final androidImplementation =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      // Demande explicite
      await androidImplementation?.requestNotificationsPermission();
    }
  }

  void _handleStartChallengeTrip(
      Challenge challenge, TravelType travelType, int estimatedReward) {
    if (mounted) {
      setState(() {
        _pendingChallengeTripData = ChallengeTripData(
            challenge: challenge,
            travelType: travelType,
            estimatedReward: estimatedReward);
        _currentIndex = 0; // Basculer vers l'onglet Home (index 0)
      });
    }
  }

  // -----------------------------------------------------------
// MÉTHODE 2 : L'APPEL DE LA SYNCHRO (main.dart)
// Remplacez votre fonction existante par celle-ci
// -----------------------------------------------------------

  Future<void> _fetchUserProfileData() async {
    if (_currentUserId == null) return;
    try {
      final userDoc =
          await _firestore.collection('users').doc(_currentUserId).get();

      if (userDoc.exists) {
        UserProfile profile = UserProfile.fromFirestore(userDoc);
        // Gestion du login quotidien
        UserProfile updatedProfile = await _processDailyLogin(profile);
        // Appliquer la décroissance des Ad Points si nécessaire
        updatedProfile = await _applyAdPointDecayIfNeeded(updatedProfile);

        if (mounted) {
          setState(() => _userProfile = updatedProfile);
        }
      } else {
        // Création nouveau profil (code existant...)
        fb_auth.User? currentUserAuth = _firebaseAuth.currentUser;
        if (currentUserAuth != null) {
          UserProfile newProfile = UserProfile(
            id: _currentUserId!,
            username: currentUserAuth.displayName ?? 'EcoNavigo',
            lamePoints: 0,
            isVip: false,
            consecutiveLogins: 0,
            currentLevel: 1,
            nextLevelBoost: 1.0,
          );
          await _firestore
              .collection('users')
              .doc(_currentUserId)
              .set(newProfile.toMap());
          UserProfile finalProfile =
              await _processDailyLogin(newProfile, isNewUser: true);

          if (mounted) {
            setState(() => _userProfile = finalProfile);
          }
        }
      }
    } catch (e) {
      print("Error fetching user profile: $e");
    }
  }

  Future<void> _fetchEcoStores() async {
    try {
      final querySnapshot = await _firestore.collection('stores').get();
      if (mounted) {
        setState(() {
          _ecoStores = querySnapshot.docs
              .map((doc) => EcoStore.fromFirestore(doc))
              .toList();
          print("Fetched ${_ecoStores.length} eco-stores.");
        });
      }
    } catch (e) {
      print("Error fetching eco stores: $e");
    }
  }

  Future<void> _fetchWeather({latlong.LatLng? location}) async {
    final double lat = location?.latitude ?? 45.75;
    final double lon = location?.longitude ?? 4.85;
    final String cityNameForDisplay =
        location != null ? "Adresse définie" : "Lyon";

    if (lat.isNaN || lat.isInfinite || lon.isNaN || lon.isInfinite) {
      print(
          "ERREUR CRITIQUE: Coordonnées invalides (NaN/Infinity) passées à _fetchWeather. lat=$lat, lon=$lon");
      if (mounted) setState(() => _currentWeatherData = null);
      return;
    }

    final String apiUrl =
        "https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon&current_weather=true&daily=weathercode,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=1";
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted)
          setState(() => _currentWeatherData =
              WeatherData.fromJson(data, city: cityNameForDisplay));
      } else {
        print(
            "Erreur API Météo: ${response.statusCode}, Body: ${response.body}");
        if (mounted) setState(() => _currentWeatherData = null);
      }
    } catch (e) {
      print("Exception lors de l'appel fetchWeather: $e");
      if (mounted) setState(() => _currentWeatherData = null);
    }
  }

  Future<void> _fetchInitialData() async {
    await _fetchUserProfileData();
    if (_userProfile?.homeAddressCoordinates != null) {
      _fetchWeather(location: _userProfile!.homeAddressCoordinates!);
    } else {
      _fetchWeather();
    }
  }

  Future<UserProfile> _processDailyLogin(UserProfile profile,
      {bool isNewUser = false}) async {
    fb_auth.User? currentUserAuth = _firebaseAuth.currentUser;
    if (currentUserAuth == null) return profile;

    DateTime now = DateTime.now();
    UserProfile tempUpdatedProfile = profile;

    // Appeler la Cloud Function claimDailyReward (le serveur dicte les règles)
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('claimDailyReward');
      final result = await callable.call();
      final data = result.data != null
          ? Map<String, dynamic>.from(result.data as Map)
          : null;

      if (data != null && data['updated'] == true) {
        final int consecutiveLogins = data['consecutiveLogins'] ?? 1;
        final double nextLevelBoost =
            (data['nextLevelBoost'] as num?)?.toDouble() ?? 1.0;
        final int newBalance = data['newBalance'] ?? (profile.lamePoints + 1);
        final int newTotalEarned = (data['newTotalEarned'] as num?)?.toInt() ??
            ((profile.totalLameEarned ?? 0) + 1);

        tempUpdatedProfile = tempUpdatedProfile.copyWith(
          consecutiveLogins: consecutiveLogins,
          nextLevelBoost: nextLevelBoost,
          lamePoints: newBalance,
          totalLameEarned: newTotalEarned,
          lastLoginDate: () => Timestamp.fromDate(now),
        );

        print(
            "✅ Récompense quotidienne attribuée par le serveur (+1 Lame). Streak: $consecutiveLogins");
      }
    } catch (e) {
      print("❌ Erreur lors de l'appel à claimDailyReward: $e");
    }

    // Gestion du reset mensuel des absences au travail (inchangé)
    DateTime? lastResetDate = profile.lastMonthlyAllowanceReset?.toDate();
    if (lastResetDate == null ||
        lastResetDate.month != now.month ||
        lastResetDate.year != now.year) {
      try {
        await _firestore.collection('users').doc(profile.id).update({
          'monthly_work_absence_allowance': 3,
          'last_monthly_allowance_reset': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        });
        tempUpdatedProfile = tempUpdatedProfile.copyWith(
          monthlyWorkAbsenceAllowance: 3,
          lastMonthlyAllowanceReset: () => Timestamp.now(),
        );
      } catch (e) {
        print("Error updating monthly absence allowance: $e");
      }
    }

    return tempUpdatedProfile;
  }

  /// Applique la décroissance des Ad Points si la dernière mise à jour date de plus de 5h.
  /// Corrige le bug où les utilisateurs restent bloqués à 10 AD pendant 72h+.
  Future<UserProfile> _applyAdPointDecayIfNeeded(UserProfile profile) async {
    if (profile.adPoints <= 0 || _currentUserId == null) return profile;

    final DateTime now = DateTime.now();
    final Timestamp lastDecayTimestamp = profile.lastAdPointDecayTime ??
        Timestamp.fromDate(now.subtract(const Duration(hours: 6)));
    final DateTime lastDecay = lastDecayTimestamp.toDate();

    // Calculer combien de périodes de 5h se sont écoulées
    int hoursPassed = now.difference(lastDecay).inHours;
    int decayCycles = hoursPassed ~/ 5; // Nombre de périodes de 5h

    if (decayCycles <= 0)
      return profile; // Pas encore de décroissance nécessaire

    // Calculer la perte totale sur les cycles manqués
    int currentPoints = profile.adPoints;
    for (int i = 0; i < decayCycles; i++) {
      if (currentPoints <= 0) break;
      int loss;
      if (currentPoints < 10)
        loss = 1;
      else if (currentPoints < 20)
        loss = 2;
      else if (currentPoints < 30)
        loss = 3;
      else if (currentPoints < 40)
        loss = 4;
      else
        loss = 5;
      currentPoints = (currentPoints - loss).clamp(0, 50);
    }

    if (currentPoints == profile.adPoints) return profile; // Pas de changement

    try {
      await _firestore.collection('users').doc(_currentUserId).update({
        'ad_points': currentPoints,
        'last_ad_point_decay_time': FieldValue.serverTimestamp(),
        'updated_at': FieldValue.serverTimestamp(),
      });
      return profile.copyWith(
        adPoints: currentPoints,
        lastAdPointDecayTime: () => Timestamp.fromDate(now),
      );
    } catch (e) {
      print("Erreur application decay AD Points: $e");
      return profile;
    }
  }

// MODIFIÉ: Centralisation de l'ajout de points ET de l'historique
  void _addLame(
    int amountToAdd, {
    String? source,
    bool isSpecialBonus = false,
    double? distanceMeters,
    double? durationSeconds,
    String? travelMode,
  }) async {
    if (_userProfile == null || _currentUserId == null || amountToAdd <= 0)
      return;

    final sourceText = source ?? 'Inconnue';

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('validateTrip');
      final Map<String, dynamic> payload = {
        'amountToAdd': amountToAdd,
        'source': sourceText,
        'isSpecialBonus': isSpecialBonus || amountToAdd > 500,
      };

      if (distanceMeters != null) payload['distanceMeters'] = distanceMeters;
      if (durationSeconds != null) payload['durationSeconds'] = durationSeconds;
      if (travelMode != null) payload['travelMode'] = travelMode;

      await callable.call(payload);

      // Synchroniser le profil directement depuis Firestore (source de vérité)
      await _fetchUserProfileData();

      // Vérifier si l'utilisateur atteint le niveau 30 (Premium gratuit)
      final newTotalLame = _userProfile?.totalLameEarned ?? 0;
      final levelData = _calculateUserLevel(newTotalLame);
      final newLevel = (levelData['currentLevel'] as num?)?.toInt() ?? 1;

      if (newLevel >= 30 && !(_userProfile?.isVip ?? false)) {
        // Activer le Premium gratuit
        await _firestore.collection('users').doc(_currentUserId!).update({
          'is_vip': true,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  "🎉 Félicitations ! Vous avez débloqué le Premium gratuit (Niveau 30+) !"),
              backgroundColor: accentGold,
              duration: Duration(seconds: 5),
            ),
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("+$amountToAdd Lames ! (Source: $sourceText)"),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      print("Error updating Lame points and history: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur sauvegarde Lames: $e")));
      }
    }
  }

  Map<String, dynamic> _calculateUserLevel(int totalLame) {
    int currentLevel = 1;
    int lameNeeded = 500; // Pour le niveau 2
    int totalLameForCurrentLevel = 0;

    // Calculer le niveau actuel
    while (totalLame >= totalLameForCurrentLevel + lameNeeded &&
        currentLevel < 50) {
      totalLameForCurrentLevel += lameNeeded;
      currentLevel++;
      lameNeeded *= 2; // Double à chaque niveau
    }

    // Calculer les Lame nécessaires pour le niveau suivant
    int lameForNextLevel = totalLameForCurrentLevel + lameNeeded;

    // Calculer le progrès vers le niveau suivant
    double progressToNextLevel = 0.0;
    if (currentLevel < 50) {
      int lameInCurrentLevel = totalLame - totalLameForCurrentLevel;
      progressToNextLevel = lameInCurrentLevel / lameNeeded;
      progressToNextLevel = progressToNextLevel.clamp(0.0, 1.0);
    }

    return {
      'currentLevel': currentLevel,
      'lameForCurrentLevel': totalLameForCurrentLevel,
      'lameForNextLevel': lameForNextLevel,
      'progressToNextLevel': progressToNextLevel,
    };
  }

  void _openProfile() {
    if (_userProfile == null || !mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => ProfileBottomSheet(
          userProfile: _userProfile!,
          onOpenShop: _openShop,
          scrollController: scrollController, // Passe le contrôleur !
        ),
      ),
    );
  }

  void _showLameHistory() {
    if (_currentUserId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => LameHistorySheet(
          userId: _currentUserId!,
          scrollController: scrollController, // Passe le contrôleur !
        ),
      ),
    );
  }

  void _openShop() {
    if (_userProfile == null || !mounted) return;
    if (Navigator.canPop(context)) Navigator.pop(context);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RewardScreen(
          userProfile: _userProfile!,
          onPurchase: (int cost) async {
            await _handlePurchase(cost);
          },
        ),
      ),
    );
  }

  Future<void> _handlePurchase(int cost,
      {String? itemId, String? itemTitle}) async {
    if (_userProfile == null || _currentUserId == null || cost <= 0) return;

    UserProfile? oldProfileState = _userProfile;
    if (mounted) {
      setState(() {
        _userProfile =
            _userProfile!.copyWith(lamePoints: _userProfile!.lamePoints - cost);
      });
      print(
          "UI mise à jour localement (achat). Nouveaux points (estimés): ${_userProfile!.lamePoints}");
    }

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('purchaseShopItem');
      await callable.call({
        'itemId': itemId,
        'cost': cost,
        'itemTitle': itemTitle ?? 'Récompense Boutique',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Achat réussi ! -${cost} Lame Points."),
          backgroundColor: Colors.green,
        ));
      }
      await _fetchUserProfileData();
    } catch (e) {
      if (mounted && oldProfileState != null) {
        setState(() => _userProfile = oldProfileState);
      }
      print("Error processing shop purchase: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("Erreur lors de l'achat: $e"),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _updateUserChallengeProgress(
      Challenge challenge, int rewardAmount) async {
    if (_userProfile == null || _currentUserId == null) return;
    try {
      final userChallengeData = challenge.toUserChallengeMap(_currentUserId!);
      final userChallengeDocRef = _firestore
          .collection('user_challenges')
          .doc('${_currentUserId}_${challenge.id}');
      await userChallengeDocRef.set(userChallengeData, SetOptions(merge: true));

      if (challenge.status == ChallengeStatus.rewardClaimed) {
        _addLame(rewardAmount, source: "Défi: ${challenge.title}");
      }
      if (mounted) setState(() {});
    } catch (e) {
      print("Error updating user_challenge: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur sauvegarde défi: $e")));
      }
    }
  }

  void _handleStartStoreTrip(EcoStore store, TravelType travelType) {
    if (mounted) {
      setState(() {
        _pendingStoreTripData =
            StoreTripData(store: store, travelType: travelType);
        _currentIndex = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_userProfile == null) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator(color: primaryGreen)));
    }

    final List<String> screenTitles = [
      'EcoNav Home',
      'Classement',
      'Défis Proches',
      'Magasins'
    ];

    StoreTripData? tripDataForHomeScreen = _pendingStoreTripData;
    if (tripDataForHomeScreen != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _pendingStoreTripData = null;
          });
        }
      });
    }

// AJOUT: Bloc pour gérer les données du trajet défi
    ChallengeTripData? challengeTripDataForHomeScreen =
        _pendingChallengeTripData;
    if (challengeTripDataForHomeScreen != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _pendingChallengeTripData = null;
          });
        }
      });
    }

    return Scaffold(
      extendBodyBehindAppBar: _currentIndex == 0,
      appBar: _currentIndex == 0
          ? PreferredSize(preferredSize: Size.zero, child: Container())
          : AppBar(
              title: Text(screenTitles[_currentIndex]),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
// MODIFIÉ: Rendre le Chip cliquable pour voir l'historique
                  child: InkWell(
                    onTap: _showLameHistory,
                    borderRadius: BorderRadius.circular(20),
                    child: Chip(
                      avatar: const Icon(Icons.eco_rounded,
                          color: accentGold, size: 18),
                      label: Text("${_userProfile!.lamePoints} L",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, color: textDark)),
                      backgroundColor: cardWhite.withOpacity(0.9),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.account_circle_rounded,
                      color: primaryGreen),
                  tooltip: "Mon Profil",
                  onPressed: _openProfile,
                ),
                IconButton(
                  icon: const Icon(Icons.logout, color: textGrey),
                  tooltip: "Déconnexion",
                  onPressed: () async {
                    await _firebaseAuth.signOut();
                  },
                )
              ],
            ),
      body: IndexedStack(
        index: _currentIndex,
        children: [
          MainHomeScreen(
            key: ValueKey('home_screen_${_userProfile?.id}'),
            userProfile: _userProfile!,
            weatherData: _currentWeatherData,
            currentWeatherTextForHome:
                _currentWeatherData?.toSummaryString() ?? "Chargement météo...",
            addLamePoints: _addLame,
            onFetchWeatherWithLocation: (location) =>
                _fetchWeather(location: location),
            onProfileModified: _fetchUserProfileData,
            ecoStores: _ecoStores,
            onStartStoreTrip: _handleStartStoreTrip,
            pendingStoreTrip: tripDataForHomeScreen,
            pendingChallengeTrip: challengeTripDataForHomeScreen,
            onProfileButtonPressed: _openProfile,
            onShowLameHistory: _showLameHistory,
            onShowStoresTab: () => setState(() => _currentIndex = 3),
            onStoreTripCompleted: (storeId, completedAt) {
              if (mounted) {
                setState(() => _pendingValidations[storeId] = completedAt);
                _savePendingValidations();
              }
            },
            onUserReturnedHome: () {
              if (mounted) {
                setState(() => _pendingValidations.clear());
                _savePendingValidations();
              }
            },
          ),
          const LeaderboardScreen(),
          if (_currentUserId != null)
            DefisScreen(
              userProfile: _userProfile!,
              currentUserId: _currentUserId!,
              onUpdateUserChallenge: _updateUserChallengeProgress,
              onStartChallengeTrip:
                  _handleStartChallengeTrip, // MODIFIÉ: Passer la nouvelle fonction de rappel
              ecoStores: _ecoStores,
              homeController: _homeController,
              navigationController: _navigationController,
              weatherData: _currentWeatherData,
            )
          else
            const Center(
                child: Text("Utilisateur non connecté pour voir les défis.")),
          StoresScreen(
            ecoStores: _ecoStores,
            onStartTrip: _handleStartStoreTrip,
            userProfile: _userProfile!,
            onAddLame: _addLame,
            weatherData: _currentWeatherData,
            pendingValidations: _pendingValidations,
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          if (mounted) setState(() => _currentIndex = index);
          if (index == 0) {}
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.leaderboard_rounded), label: 'Classement'),
          BottomNavigationBarItem(
              icon: Icon(Icons.extension_rounded), label: 'Défis'),
          BottomNavigationBarItem(
              icon: Icon(Icons.storefront_rounded), label: 'Magasins'),
        ],
      ),
    );
  }
}

// NOUVEAU: Widget pour afficher l'historique des Lames
class LameHistorySheet extends StatelessWidget {
  final String userId;
  final ScrollController? scrollController;
  const LameHistorySheet(
      {Key? key, required this.userId, this.scrollController})
      : super(key: key);

  Future<List<DocumentSnapshot>> _fetchHistory() async {
    final snapshot = await _firestore
        .collection('users')
        .doc(userId)
        .collection('lame_history')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();
    return snapshot.docs;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // CORRIGÉ: Suppression de `height: MediaQuery...` qui bloquait le DraggableScrollableSheet
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        children: [
          Text("Historique des Lames",
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<DocumentSnapshot>>(
              future: _fetchHistory(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: primaryGreen));
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Erreur: ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(
                      child: Text("Aucun historique de gain pour le moment."));
                }

                final historyDocs = snapshot.data!;
                return ListView.separated(
                  controller:
                      scrollController, // CORRIGÉ: Lier la liste au contrôleur de glissement
                  itemCount: historyDocs.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final data =
                        historyDocs[index].data() as Map<String, dynamic>;
                    final amount = data['amount'] as int? ?? 0;
                    final source =
                        data['source'] as String? ?? 'Source inconnue';
                    final timestamp =
                        (data['timestamp'] as Timestamp?)?.toDate();

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            amount > 0 ? lightGreen : Colors.red.shade100,
                        child: Icon(
                          amount > 0 ? Icons.add : Icons.remove,
                          color: amount > 0 ? primaryGreen : Colors.red,
                        ),
                      ),
                      title: Text(source,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        timestamp != null
                            ? DateFormat('le dd/MM/yyyy à HH:mm', 'fr_FR')
                                .format(timestamp)
                            : 'Date inconnue',
                      ),
                      trailing: Text(
                        '${amount > 0 ? '+' : ''}$amount L',
                        style: TextStyle(
                          color:
                              amount > 0 ? primaryGreen : Colors.red.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          // Le bouton "Fermer" a été supprimé car on peut glisser vers le bas
        ],
      ),
    );
  }
}

class ChallengeTimerHeader extends StatefulWidget {
  final DateTime targetDate;
  final VoidCallback onTimerFinished;

  const ChallengeTimerHeader({
    Key? key,
    required this.targetDate,
    required this.onTimerFinished,
  }) : super(key: key);

  @override
  State<ChallengeTimerHeader> createState() => _ChallengeTimerHeaderState();
}

class _ChallengeTimerHeaderState extends State<ChallengeTimerHeader> {
  Timer? _timer;
  String _displayString = "--j --h --m --s";

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant ChallengeTimerHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetDate != widget.targetDate) {
      _startTimer();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    _updateTime(); // Mise à jour immédiate
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
  }

  void _updateTime() {
    final now = DateTime.now();
    final difference = widget.targetDate.difference(now);

    if (difference.isNegative) {
      _timer?.cancel();
      // On évite d'appeler le callback pendant la construction
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onTimerFinished();
      });
    } else {
      if (mounted) {
        setState(() {
          _displayString = _formatDuration(difference);
        });
      }
    }
  }

  String _formatDuration(Duration d) {
    int days = d.inDays;
    int hours = d.inHours.remainder(24);
    int minutes = d.inMinutes.remainder(60);
    int seconds = d.inSeconds.remainder(60);
    return "${days}j ${hours}h ${minutes}m ${seconds}s";
  }

  @override
  Widget build(BuildContext context) {
    // MODIFIÉ : On renvoie directement la ligne sans le fond coloré (géré par le parent)
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        const Icon(Icons.timer_outlined, color: accentGold, size: 22),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "PROCHAINS DÉFIS :",
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2),
            ),
            Text(
              _displayString,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class DefisScreen extends StatefulWidget {
  final Future<void> Function(Challenge challenge, int rewardAmount)
      onUpdateUserChallenge;
  final String currentUserId;
  final UserProfile userProfile;
  final List<EcoStore> ecoStores;
  final HomeController homeController;
  final NavigationController navigationController;
  final WeatherData? weatherData;
// AJOUT: Nouvelle propriété pour la fonction de rappel
  // AJOUT: Nouvelle propriété pour la fonction de rappel
  final Function(
          Challenge challenge, TravelType travelType, int estimatedReward)
      onStartChallengeTrip;

  const DefisScreen({
    Key? key,
    required this.currentUserId,
    required this.userProfile,
    required this.onUpdateUserChallenge,
    required this.onStartChallengeTrip, // AJOUT
    required this.ecoStores,
    required this.homeController,
    required this.navigationController,
    this.weatherData,
  }) : super(key: key);
  @override
  _DefisScreenState createState() => _DefisScreenState();
}

class _DefisScreenState extends State<DefisScreen> {
  List<Challenge> _localPoiChallenges = [];
  bool _isLoadingLocalPois = false;
  String? _localPoiError;
  latlong.LatLng? _lastKnownUserLocation;
  bool _isStayChallengeDialogOpen = false;
  DateTime? _busStopArrivalTime;

  // Localisation personnalisée pour les défis
  latlong.LatLng? _customChallengeLocation;
  String? _customLocationName;
  int _locationChangesUsed = 0;

// On garde juste la date cible, plus de timer ici
  DateTime? _nextRefreshDate;

  @override
  void initState() {
    super.initState();
    _loadLocationChangeState();
    _initChallengeCycle();
    _fetchLocalPoisAsChallenges();
    _updateUserLocationForSorting();

    // CORRECTION : Callback navigation (appelé quand le trajet est fini OU quand le timer est fini)
    widget.navigationController
        .setOnChallengeDestinationReachedCallback((completedChallenge) async {
      int nextStep = completedChallenge.currentStep + 1;
      int total =
          completedChallenge.visitCount ?? completedChallenge.totalSteps;

      ChallengeStatus nextStatus = nextStep >= total
          ? ChallengeStatus.completedPendingReward
          : ChallengeStatus.inProgress;

      _showSnackBar(
          "Défi \"${completedChallenge.title}\" : étape $nextStep/$total validée !",
          backgroundColor: primaryGreen);
      await _handleChallengeAction(completedChallenge, nextStatus,
          newStep: nextStep);
    });
  }

  @override
  void dispose() {
    widget.navigationController
        .setOnChallengeDestinationReachedCallback((_) {});
    super.dispose();
  }

// Initialise la date de fin du cycle actuel
  Future<void> _initChallengeCycle() async {
    final userDoc = await _firestore
        .collection('user_stats')
        .doc(widget.currentUserId)
        .get();
// Par défaut, une date passée pour forcer le refresh si pas de donnée
    DateTime lastRefresh = DateTime.now().subtract(const Duration(days: 30));

    if (userDoc.exists &&
        userDoc.data()!.containsKey('last_challenges_refresh')) {
      lastRefresh =
          (userDoc.data()!['last_challenges_refresh'] as Timestamp).toDate();
    }

    if (mounted) {
      setState(() {
        _nextRefreshDate = lastRefresh.add(const Duration(days: 14));
      });
    }
  }

// Cette fonction est appelée par le Widget Enfant quand le temps est écoulé
  // Cette fonction est appelée par le Widget Enfant quand le temps est écoulé
  Future<void> _triggerAutoRefresh() async {
    print("CYCLE TERMINÉ : ACTUALISATION AUTOMATIQUE");

    // 0. Réinitialiser la progression des défis POI locaux dans Firestore
    try {
      final snapshot = await _firestore
          .collection('user_challenges')
          .where('user_id', isEqualTo: widget.currentUserId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final batch = _firestore.batch();
        for (var doc in snapshot.docs) {
          if (doc.id.contains('poi_')) {
            batch.delete(doc.reference);
          }
        }
        await batch.commit();
        print(
            "Progression des défis POI réinitialisée (${snapshot.docs.length} docs)");
      }
    } catch (e) {
      print("Erreur réinitialisation défis POI: $e");
    }

    // 1. NOUVEAU : Récupérer la position GPS actuelle et le nom de la ville (avec sécurité try/catch)
    Position? pos;
    try {
      pos = await widget.homeController.getMyCurrentLocation();
    } catch (e) {
      print("⚠️ Erreur géolocalisation lors de l'actualisation auto: $e");
    }

    String newLocationName = "Ma position";
    _showStayChallengeNotification(
        "Défi de zone", "Début du défi. Restez dans la zone pour valider.");

    if (pos != null) {
      try {
        final nominatim =
            await PhotonService().reverseGeocode(pos.latitude, pos.longitude);
        if (nominatim != null && nominatim['address'] != null) {
          final address = Map<String, dynamic>.from(nominatim['address']);
          newLocationName = address['city'] ??
              address['town'] ??
              address['village'] ??
              address['municipality'] ??
              'Ma position';
        }
      } catch (e) {
        print("Erreur reverse geocoding OSM: $e");
      }
    }

    // 2. Mettre à jour la date en base
    final now = DateTime.now();
    await _firestore.collection('user_stats').doc(widget.currentUserId).set(
        {'last_challenges_refresh': FieldValue.serverTimestamp()},
        SetOptions(merge: true));

    // 3. Mettre à jour la date locale et la nouvelle Zone
    if (mounted) {
      setState(() {
        _nextRefreshDate = now.add(const Duration(days: 14));
        _locationChangesUsed = 0;
        if (pos != null) {
          _customChallengeLocation =
              latlong.LatLng(pos.latitude, pos.longitude);
          _customLocationName = newLocationName; // Affiche le nom de la ville !
        }
      });
    }

    // 4. Sauvegarder la nouvelle zone dans les SharedPreferences
    if (pos != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          'defi_location_changes_used_${widget.currentUserId}', 0);
      await prefs.setDouble(
          'defi_custom_lat_${widget.currentUserId}', pos.latitude);
      await prefs.setDouble(
          'defi_custom_lng_${widget.currentUserId}', pos.longitude);
      await prefs.setString(
          'defi_custom_name_${widget.currentUserId}', newLocationName);
    }

    // 5. Générer nouveaux défis autour de cette nouvelle position
    await _fetchLocalPoisAsChallenges(forceRefresh: true);
  }

  Widget _buildChallengeLocationStatus({required bool canChange}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: primaryGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryGreen.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Localisation actuelle",
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Row(children: [
            Icon(
              _customChallengeLocation != null
                  ? Icons.edit_location_alt
                  : Icons.my_location,
              size: 16,
              color: primaryGreen,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _customChallengeLocation != null
                    ? (_customLocationName ?? "Position personnalisée")
                    : "Ma position GPS",
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Future<void> _loadLocationChangeState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final int used =
          prefs.getInt('defi_location_changes_used_${widget.currentUserId}') ??
              0;
      final double? lat =
          prefs.getDouble('defi_custom_lat_${widget.currentUserId}');
      final double? lng =
          prefs.getDouble('defi_custom_lng_${widget.currentUserId}');
      final String? name =
          prefs.getString('defi_custom_name_${widget.currentUserId}');
      if (mounted) {
        setState(() {
          _locationChangesUsed = used;
          if (lat != null && lng != null) {
            _customChallengeLocation = latlong.LatLng(lat, lng);
            _customLocationName = name;
          }
        });
      }
    } catch (e) {
      debugPrint('Erreur chargement état localisation défis: $e');
    }
  }

  Future<void> _showChangeChallengeLocationDialog() async {
    final int maxChanges = widget.userProfile.isVip ? 10 : 1;
    final bool canChange = _locationChangesUsed < maxChanges;

    final TextEditingController locationCtrl = TextEditingController();
    latlong.LatLng? pickedLocation;
    String? pickedName;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDS) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.location_on, color: primaryGreen),
            SizedBox(width: 8),
            Text("Zone de défis"),
          ]),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section : localisation actuelle (refactorisée)
              _buildChallengeLocationStatus(canChange: canChange),
              const SizedBox(height: 14),
              // Compteur de changements
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Changements restants :",
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: canChange
                          ? primaryGreen.withOpacity(0.1)
                          : Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: canChange ? primaryGreen : Colors.orange),
                    ),
                    child: Text(
                      "${maxChanges - _locationChangesUsed}/$maxChanges",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: canChange ? primaryGreen : Colors.orange),
                    ),
                  ),
                ],
              ),
              if (!canChange) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.userProfile.isVip
                        ? "Limite de $maxChanges changements atteinte pour ce cycle."
                        : "Vous avez utilisé votre changement gratuit.\nPassez Premium pour 10 changements par cycle !",
                    style: const TextStyle(fontSize: 12, color: Colors.orange),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (canChange) ...[
                const SizedBox(height: 14),
                const Text("Nouvelle zone :",
                    style:
                        TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                TextField(
                  controller: locationCtrl,
                  decoration: InputDecoration(
                    hintText: "Ex: Paris, Lyon, 75001...",
                    prefixIcon: const Icon(Icons.search, color: primaryGreen),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: primaryGreen),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Fermer"),
            ),
            if (canChange)
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
                onPressed: () async {
                  final address = locationCtrl.text.trim();
                  if (address.isEmpty) return;
                  try {
                    final results = await PhotonService().searchPlace(address);
                    if (results.isNotEmpty) {
                      final first = results.first as Map<String, dynamic>;
                      final lat =
                          double.tryParse(first['lat']?.toString() ?? '0');
                      final lon =
                          double.tryParse(first['lon']?.toString() ?? '0');

                      if (lat != null && lon != null && lat != 0 && lon != 0) {
                        pickedLocation = latlong.LatLng(lat, lon);
                        pickedName = (first['display_name'] as String?)
                                ?.split(',')
                                .first ??
                            address;
                        if (ctx.mounted) Navigator.pop(ctx);
                      } else {
                        _showSnackBar("Adresse introuvable",
                            backgroundColor: Colors.red);
                      }
                    } else {
                      _showSnackBar("Adresse introuvable",
                          backgroundColor: Colors.red);
                    }
                  } catch (e) {
                    _showSnackBar("Erreur de géocodage: $e",
                        backgroundColor: Colors.red);
                  }
                },
                child: const Text("Confirmer"),
              ),
          ],
        ),
      ),
    );

    if (pickedLocation != null) {
      final newUsed = _locationChangesUsed + 1;
      setState(() {
        _customChallengeLocation = pickedLocation;
        _customLocationName = pickedName;
        _locationChangesUsed = newUsed;
      });
      final prefs = await SharedPreferences.getInstance();
      prefs.setInt(
          'defi_location_changes_used_${widget.currentUserId}', newUsed);
      prefs.setDouble(
          'defi_custom_lat_${widget.currentUserId}', pickedLocation!.latitude);
      prefs.setDouble(
          'defi_custom_lng_${widget.currentUserId}', pickedLocation!.longitude);
      if (pickedName != null)
        prefs.setString(
            'defi_custom_name_${widget.currentUserId}', pickedName!);
      await _fetchLocalPoisAsChallenges(forceRefresh: true);
      _showSnackBar(
          "Zone mise à jour : ${pickedName ?? 'nouvelle position'} ($newUsed/$maxChanges)",
          backgroundColor: primaryGreen);
    }
  }

  void _showSnackBar(String message,
      {Color backgroundColor = Colors.black87,
      Duration duration = const Duration(seconds: 3)}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
      ),
    );
  }

  void _showStayChallengeNotification(String title, String message) {
    if (!context.mounted) return;
    Get.snackbar(title, message,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.blueGrey.shade900.withOpacity(0.9),
        colorText: Colors.white,
        duration: const Duration(seconds: 2));
  }

  void _showStayChallengeCompletionDialog() {
    if (!context.mounted) return;
    if (_isStayChallengeDialogOpen) {
      Get.back();
      _isStayChallengeDialogOpen = false;
    }

    _isStayChallengeDialogOpen = true;
    Get.dialog(
      AlertDialog(
        title: const Text('Défi terminé'),
        content: const Text(
            '🎉 Félicitations ! Vous avez validé votre défi de zone. Bravo !'),
        actions: [
          TextButton(
            onPressed: () {
              _isStayChallengeDialogOpen = false;
              Get.back();
            },
            child: const Text('OK'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  void _showCriticalModal(String title, String message) {
    if (!context.mounted) return;
    Get.dialog(
      AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('OK'),
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

// --- CALCUL DYNAMIQUE DE RÉCOMPENSE ---
  Future<int> _calculateDynamicReward(
      Challenge challenge, TravelType travelType) async {
    double baseEffort = 10;

    if (challenge.latitude != null && challenge.longitude != null) {
      try {
        final userPos = await widget.homeController.getMyCurrentLocation();
        double rawMeters = toolkit.SphericalUtil.computeDistanceBetween(
                toolkit.LatLng(userPos.latitude, userPos.longitude),
                toolkit.LatLng(challenge.latitude!, challenge.longitude!))
            .toDouble();

        double distanceKm = (rawMeters / 1000.0) * 1.3;
        double speedKmh = travelType == TravelType.bike
            ? 15.0
            : (travelType == TravelType.transit ? 20.0 : 5.0);
        double durationMinutes = (distanceKm / speedKmh) * 60.0;

        // Estimation du dénivelé via Open-Meteo
        double elevationDiff = 0.0;
        if (travelType != TravelType.transit) {
          try {
            String elevUrl =
                "https://api.open-meteo.com/v1/elevation?latitude=${userPos.latitude},${challenge.latitude}&longitude=${userPos.longitude},${challenge.longitude}";
            var elevResp = await Dio().get(elevUrl);
            var elevData = elevResp.data;
            if (elevData['elevation'] != null &&
                (elevData['elevation'] as List).length >= 2) {
              double e1 = (elevData['elevation'][0] as num).toDouble();
              double e2 = (elevData['elevation'][1] as num).toDouble();
              if (e2 > e1) {
                elevationDiff = e2 - e1;
              } else {
                // Parfois le trajet monte et descend, on prend l'écart absolu minimum
                elevationDiff = (e1 - e2).abs() * 0.5;
              }
            }
          } catch (e) {
            print("Erreur dénivelé Open-Meteo defis : $e");
          }
        }

        if (travelType == TravelType.walk) {
          baseEffort = (distanceKm * 10.0) +
              (durationMinutes * 0.5) +
              (elevationDiff / 3.0);
        } else if (travelType == TravelType.bike) {
          baseEffort = (distanceKm * 6.0) +
              (durationMinutes * 0.2) +
              (elevationDiff / 5.0);
        } else if (travelType == TravelType.transit) {
          // Logique de base en cas d'échec API
          baseEffort = (distanceKm * 5.0 * 0.8) + (durationMinutes * 0.5 * 0.8);
        }
      } catch (e) {
        baseEffort = 10;
      }

      // --- NOUVEAU CALCUL TRANSIT VIA API ---
      if (travelType == TravelType.transit) {
        try {
          final userPos = await widget.homeController.getMyCurrentLocation();
          String originStr = "${userPos.latitude},${userPos.longitude}";
          String destStr = "${challenge.latitude},${challenge.longitude}";
          String apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";
          String url =
              "https://maps.googleapis.com/maps/api/directions/json?units=metric&origin=$originStr&destination=$destStr&mode=transit&alternatives=true&language=fr&key=$apiKey";

          var response = await Dio().get(url);
          var data = response.data;

          if (data['status'] == 'OK' &&
              data['routes'] != null &&
              (data['routes'] as List).isNotEmpty) {
            List<dynamic> routes = data['routes'];
            double totalTransitEffort = 0;
            int count = 0;
            for (var route in routes) {
              if (route['legs'] != null && route['legs'].isNotEmpty) {
                var leg = route['legs'][0];
                double durMin = 0.0;
                if (leg['duration'] != null &&
                    leg['duration']['value'] != null) {
                  durMin = (leg['duration']['value'] as num).toDouble() / 60.0;
                }
                int tCount = 0;
                final List<dynamic> steps =
                    leg['steps'] as List<dynamic>? ?? [];
                for (var stepData in steps) {
                  final step = stepData as Map<String, dynamic>;
                  if (step['travel_mode'] == 'TRANSIT') tCount++;
                }
                totalTransitEffort += (durMin * 0.5) + (tCount * 5.0);
                count++;
              }
            }
            if (count > 0) {
              baseEffort = totalTransitEffort / count;
            }
          }
        } catch (e) {
          print("Erreur transit API defi: $e");
        }
      }
    }

    double challengeMultiplier = 1.0 + (challenge.rewardLame / 100.0);
    double baseReward = baseEffort * challengeMultiplier;

    // ── Bonus temps sur place ──
    if (challenge.stayDurationSeconds != null &&
        challenge.stayDurationSeconds! > 0) {
      int stayMin = (challenge.stayDurationSeconds! / 60).round();
      baseReward += stayMin;
      if (stayMin > 3) baseReward += (stayMin - 3);
    }

    // ── Multi-visites ──
    int visitCount = challenge.visitCount ?? 1;
    if (visitCount > 1) {
      baseReward = baseReward * visitCount;
    }

    // --- MODIFIÉ : Ajout Boost Météo & Pub ---
    final weather = widget.weatherData;
    if (weather != null) {
      bool isBadWeather = weather.weatherCode >= 51 ||
          weather.weatherCode == 45 ||
          weather.weatherCode == 48;
      bool isExtremeTemp = weather.temperature < 2 || weather.temperature > 32;
      if (isBadWeather || isExtremeTemp || weather.windSpeed > 30) {
        baseReward *= 1.5;
      }
    }

    if (widget.userProfile.adPoints >= 10) {
      baseReward *= 1.2;
    }

    // ── Bonus VIP x1.15 ──
    if (widget.userProfile.isVip) {
      baseReward *= 1.15;
    }

    return baseReward
        .round()
        .clamp(challenge.rewardLame, 5000); // 5000 for Super Defi
  }

  Future<void> _fetchLocalPoisAsChallenges({bool forceRefresh = false}) async {
    if (_isLoadingLocalPois) return;
    if (!mounted) return;

    if (forceRefresh) {
      setState(() {
        _localPoiChallenges.clear();
      });
    }

    setState(() {
      _isLoadingLocalPois = true;
      _localPoiError = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = 'cached_poi_challenges_${widget.currentUserId}';

      // =====================================================================
      // 1. LECTURE DU CACHE (Si le timer n'a pas déclenché de rafraîchissement)
      // =====================================================================
      if (!forceRefresh) {
        final String? cachedData = prefs.getString(cacheKey);

        if (cachedData != null) {
          List<dynamic> decoded = json.decode(cachedData);

          List<Challenge> cachedChallenges = decoded.map((c) {
            // Reconversion de la date pour le factory fromMap (JSON ne gère pas les Timestamp natifs)
            if (c['created_at'] is int) {
              c['created_at'] =
                  Timestamp.fromMillisecondsSinceEpoch(c['created_at']);
            } else if (c['created_at'] is String) {
              c['created_at'] =
                  Timestamp.fromDate(DateTime.parse(c['created_at']));
            }
            return Challenge.fromMap(c['id'], c as Map<String, dynamic>);
          }).toList();

          // Synchronisation avec la progression actuelle dans Firestore pour mettre à jour l'UI
          final userChallengesSnapshot = await _firestore
              .collection('user_challenges')
              .where('user_id', isEqualTo: widget.currentUserId)
              .get();

          final Map<String, dynamic> existingUserChallengeData = {
            for (var doc in userChallengesSnapshot.docs) doc.id: doc.data()
          };

          for (int i = 0; i < cachedChallenges.length; i++) {
            String userChallengeFullId =
                '${widget.currentUserId}_${cachedChallenges[i].id}';

            if (existingUserChallengeData.containsKey(userChallengeFullId)) {
              var existingProgress =
                  existingUserChallengeData[userChallengeFullId];

              // Mise à jour des variables mutables de la classe Challenge
              cachedChallenges[i].status = ChallengeStatus.values.firstWhere(
                (e) =>
                    e.toString().split('.').last == existingProgress['status'],
                orElse: () => ChallengeStatus.notStarted,
              );
              cachedChallenges[i].currentStep =
                  existingProgress['current_step'] ?? 0;
              cachedChallenges[i].selectedStore =
                  existingProgress['selected_store'];
            }
          }

          if (mounted) {
            setState(() {
              _localPoiChallenges = cachedChallenges;
            });
          }

          return; // Fin de l'exécution anticipée, on utilise les données en cache !
        }
      }

      // =====================================================================
      // 2. GÉNÉRATION DE NOUVEAUX DÉFIS VIA GOOGLE PLACES API
      // =====================================================================
      Position position = await widget.homeController.getMyCurrentLocation();
      final double lat =
          _customChallengeLocation?.latitude ?? position.latitude;
      final double lng =
          _customChallengeLocation?.longitude ?? position.longitude;
      final String apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;

      final String types =
          'park|museum|tourist_attraction|church|library|stadium|university';
      final _random = Random();

      // Récupérer la progression existante au cas où on recroise un défi connu
      final userChallengesSnapshot = await _firestore
          .collection('user_challenges')
          .where('user_id', isEqualTo: widget.currentUserId)
          .get();

      final Map<String, dynamic> existingUserChallengeData = {
        for (var doc in userChallengesSnapshot.docs) doc.id: doc.data()
      };

      // Tranches de distance et objectifs
      List<Map<String, double>> buckets = [
        {'min': 100, 'max': 2000, 'count': 3},
        {'min': 2000, 'max': 5000, 'count': 3},
        {'min': 5000, 'max': 10000, 'count': 2},
        {'min': 10000, 'max': 20000, 'count': 2},
      ];

      List<Challenge> newLocalPoiChallenges = [];

      for (var bucket in buckets) {
        double minR = bucket['min']!;
        double maxR = bucket['max']!;
        int targetCount = bucket['count']!.toInt();
        int foundInBucket = 0;
        int searchRadius = maxR.toInt();

        bool bucketFilled = false;
        int attempts = 0;

        while (!bucketFilled && attempts < 3) {
          // CORRECTION: Utiliser nwr au lieu de node, et out center pour récupérer
          // un point central pour way/relation
          String overpassQuery = '''
  [out:json][timeout:25];
  (
    nwr["leisure"="park"](around:$searchRadius,$lat,$lng);
    nwr["tourism"="museum"](around:$searchRadius,$lat,$lng);
    nwr["tourism"="attraction"](around:$searchRadius,$lat,$lng);
    nwr["historic"="monument"](around:$searchRadius,$lat,$lng);
  );
  out center 15;
''';

          final overpassUrl =
              Uri.parse('https://overpass-api.de/api/interpreter');
          final response = await http.post(
            overpassUrl,
            body: {'data': overpassQuery},
            headers: {'User-Agent': 'WalkMoneyApp/1.0 (contact@walkmoney.com)'},
          ).timeout(const Duration(seconds: 15));

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            final List<dynamic> elements = data['elements'] ?? [];
            elements.shuffle(); // Aléatoire pour varier les défis

            for (var place in elements) {
              if (foundInBucket >= targetCount) break;

              // CORRECTION: Les way/relation fournissent le centre dans place['center']
              double? pLat =
                  (place['lat'] ?? place['center']?['lat'] as num?)?.toDouble();
              double? pLng =
                  (place['lon'] ?? place['center']?['lon'] as num?)?.toDouble();
              if (pLat == null || pLng == null) continue;

              double dist = toolkit.SphericalUtil.computeDistanceBetween(
                      toolkit.LatLng(lat, lng), toolkit.LatLng(pLat, pLng))
                  .toDouble();

              // Vérification de la tranche de distance
              if (dist >= (attempts == 0 ? minR : 0) && dist <= searchRadius) {
                String osmId = place['id']?.toString() ?? '';
                String name =
                    (place['tags'] != null ? place['tags']['name'] : null) ??
                        'Lieu Mystère';

                // On ignore les lieux sans nom
                if (name == 'Lieu Mystère') continue;

                // Vérification doublon
                if (newLocalPoiChallenges.any((c) => c.googlePlaceId == osmId))
                  continue;

                String challengeDocId = 'poi_$osmId';
                String userChallengeFullId =
                    '${widget.currentUserId}_$challengeDocId';

                Map<String, dynamic>? existingProgress;
                if (existingUserChallengeData
                    .containsKey(userChallengeFullId)) {
                  existingProgress =
                      existingUserChallengeData[userChallengeFullId];
                }

                int visitCount = 1;
                String desc = "Visitez ce lieu.";
                int? stayDurationSeconds;
                int defiType = _random.nextInt(100);
                int baseReward =
                    (1 + _random.nextInt(5)) * 10; // 10, 20, 30, 40 ou 50 Lames

                // 20% de multi-visites, 30% de temps sur place, 50% normal
                if (defiType < 20) {
                  visitCount = 2 + _random.nextInt(4); // 2 à 5 visites
                  desc = "Rends-toi $visitCount fois à ce lieu.";
                } else if (defiType < 50) {
                  int stayMinutes = 3 + _random.nextInt(8); // 3 à 10 min
                  stayDurationSeconds = stayMinutes * 60;
                  desc =
                      "Rends-toi à ce lieu et restes-y $stayMinutes minute(s) dans un rayon de 10m.";
                } else {
                  desc = "Rends-toi à ce lieu.";
                }

                newLocalPoiChallenges.add(Challenge(
                  id: challengeDocId,
                  title: "Exploration : $name",
                  rewardText: desc,
                  rewardLame: baseReward,
                  totalDurationSeconds: 1209600, // 14 jours
                  createdAt: Timestamp.now(),
                  type: ChallengeType.localPoiVisit,
                  totalSteps: visitCount,
                  latitude: pLat,
                  longitude: pLng,
                  googlePlaceId: osmId,
                  visitCount: visitCount,
                  stayDurationSeconds: stayDurationSeconds,
                  status: existingProgress != null
                      ? ChallengeStatus.values.firstWhere(
                          (e) =>
                              e.toString().split('.').last ==
                              existingProgress!['status'],
                          orElse: () => ChallengeStatus.notStarted)
                      : ChallengeStatus.notStarted,
                  currentStep: existingProgress != null
                      ? (existingProgress['current_step'] ?? 0)
                      : 0,
                ));

                foundInBucket++;
              }
            }
          }

          if (foundInBucket >= targetCount) {
            bucketFilled = true;
          } else {
            // Élargir le rayon si on n'a pas trouvé assez de lieux intéressants
            searchRadius += 5000;
            attempts++;
          }
        }
      }

      // =====================================================================
      // 3. SAUVEGARDE EN CACHE (SharedPreferences)
      // =====================================================================
      List<Map<String, dynamic>> toCache = newLocalPoiChallenges.map((c) {
        var map = c.toMap();
        // Conversion du Timestamp Firestore en entier (millisecondes) pour la sérialisation JSON
        map['created_at'] = c.createdAt.millisecondsSinceEpoch;
        return map;
      }).toList();

      await prefs.setString(cacheKey, json.encode(toCache));

      // Mise à jour de l'UI
      if (mounted) {
        setState(() {
          _localPoiChallenges = newLocalPoiChallenges;
        });
      }
    } catch (e) {
      print("Erreur POI: $e");
      if (mounted)
        setState(
            () => _localPoiError = "Impossible de charger les défis locaux.");
    } finally {
      if (mounted) setState(() => _isLoadingLocalPois = false);
    }
  }

  Future<void> _handleChallengeAction(
      Challenge challenge, ChallengeStatus newStatus,
      {int? newStep,
      String? selectedStore,
      String? proofIdentifier,
      String? ocrResultText,
      bool? isProofValid}) async {
    // ── Calcul de la récompense finale si on réclame ──────────────────────
    int finalReward = challenge.rewardLame;

    if (newStatus == ChallengeStatus.rewardClaimed) {
      double baseReward = challenge.rewardLame.toDouble();

      // 1. Multi-visites
      int visitCount = challenge.visitCount ?? 1;
      if (visitCount > 1) {
        baseReward = baseReward * 2 * visitCount;
      }

      // 2. Bonus temps sur place
      if (challenge.stayDurationSeconds != null &&
          challenge.stayDurationSeconds! > 0) {
        int stayMin = (challenge.stayDurationSeconds! / 60).round();
        baseReward += stayMin;
        if (stayMin > 3) baseReward += (stayMin - 3);
      }

      // 3. Bonus Météo
      final weather = widget.weatherData;
      if (weather != null) {
        bool isBadWeather = weather.weatherCode >= 51 ||
            weather.weatherCode == 45 ||
            weather.weatherCode == 48;
        bool isExtremeTemp =
            weather.temperature < 2 || weather.temperature > 32;
        if (isBadWeather || isExtremeTemp || weather.windSpeed > 30) {
          baseReward *= 1.5;
        }
      }

      // 4. Bonus Pubs (Ad Points)
      if (widget.userProfile.adPoints >= 10) {
        baseReward *= 1.2;
      }

      // 5. Bonus VIP
      if (widget.userProfile.isVip) {
        baseReward *= 1.15;
      }

      finalReward = baseReward.round();
    }

    final updatedChallenge = challenge.copyWith(
        status: newStatus,
        currentStep: newStep,
        selectedStore: () => selectedStore);

    await widget.onUpdateUserChallenge(updatedChallenge, finalReward);

    // Mettre à jour la liste locale pour bloquer instantanément le bouton !
    int idx = _localPoiChallenges.indexWhere((c) => c.id == challenge.id);
    if (idx != -1) {
      _localPoiChallenges[idx] = updatedChallenge;
    }

    // --- AJOUT: Bonus 5000 lames si tous les défis sont réclamés ---
    if (newStatus == ChallengeStatus.rewardClaimed) {
      if (_localPoiChallenges.every((c) =>
          (c.id == challenge.id &&
              newStatus == ChallengeStatus.rewardClaimed) ||
          c.status == ChallengeStatus.rewardClaimed)) {
        // Vérifier si le bonus a déjà été donné pour ce cycle
        final statsDoc = await _firestore
            .collection('user_stats')
            .doc(widget.currentUserId)
            .get();
        final lastBonusDate =
            statsDoc.data()?['last_all_challenges_bonus_date'] as Timestamp?;
        final lastRefreshDate =
            statsDoc.data()?['last_challenges_refresh'] as Timestamp?;

        bool alreadyGiven = false;
        if (lastBonusDate != null && lastRefreshDate != null) {
          alreadyGiven = lastBonusDate.millisecondsSinceEpoch >
              lastRefreshDate.millisecondsSinceEpoch;
        }

        if (!alreadyGiven) {
          await _firestore
              .collection('user_stats')
              .doc(widget.currentUserId)
              .set({
            'last_all_challenges_bonus_date': FieldValue.serverTimestamp()
          }, SetOptions(merge: true));

          await widget.onUpdateUserChallenge(
              challenge.copyWith(title: "BONUS FINAL : 10/10 Défis"), 5000);

          Future.delayed(const Duration(milliseconds: 500), () {
            _showSnackBar(
                "FÉLICITATIONS ! Vous avez complété tous les défis du cycle. Bonus de 5000 lames ajouté ! 🏆",
                backgroundColor: Colors.purple,
                duration: const Duration(seconds: 7));
          });
        }
      }
    }
    setState(() {});
  }

  Future<void> _updateUserLocationForSorting() async {
    try {
      Position position = await widget.homeController.getMyCurrentLocation();
      if (mounted) {
        setState(() {
          _lastKnownUserLocation =
              latlong.LatLng(position.latitude, position.longitude);
        });
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    final int maxChanges = widget.userProfile.isVip ? 10 : 1;
    return Scaffold(
      backgroundColor: defisScreenBackground,
      body: Column(
        children: [
          // --- HEADER UNIFIÉ : TIMER + BOUTON CHANGEMENT LOCALISATION ---
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blueGrey.shade900, Colors.blueGrey.shade700],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
              ],
            ),
            child: Row(
              children: [
                // 1. Zone du Timer
                Expanded(
                  flex: 5,
                  child: _nextRefreshDate != null
                      ? ChallengeTimerHeader(
                          targetDate: _nextRefreshDate!,
                          onTimerFinished: _triggerAutoRefresh,
                        )
                      : const SizedBox(
                          height: 40,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: CircularProgressIndicator(
                                color: accentGold, strokeWidth: 2),
                          ),
                        ),
                ),
                // 2. Bouton de zone (intégré dans la bande noire)
                Expanded(
                  flex: 4,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: _showChangeChallengeLocationDialog,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white
                              .withOpacity(0.12), // Fond semi-transparent
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _customChallengeLocation != null
                                ? accentGold.withOpacity(0.7)
                                : Colors.white.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _customChallengeLocation != null
                                  ? Icons.edit_location_alt
                                  : Icons.my_location,
                              size: 15,
                              color: _customChallengeLocation != null
                                  ? accentGold
                                  : Colors.white,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _customChallengeLocation != null &&
                                        _customLocationName != null
                                    ? _customLocationName! // Affiche l'adresse complète récupérée
                                    : "Autour de moi",
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _customChallengeLocation != null
                                      ? accentGold
                                      : Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines:
                                    1, // Coupe proprement si l'adresse est trop longue
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // --- BOUTON DEBUG : FORCER RAZ CACHE POI (14 jours possible) ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orangeAccent.withOpacity(0.95),
              ),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final cacheKey =
                    'cached_poi_challenges_${widget.currentUserId}';
                await prefs.remove(cacheKey);
                await _fetchLocalPoisAsChallenges(forceRefresh: true);
                _showSnackBar(
                    "Cache local POI supprimé. Régénération en cours.",
                    backgroundColor: Colors.green);
              },
              icon: const Icon(Icons.delete_forever),
              label: const Text('Forcer régénération défis locaux'),
            ),
          ),

          // --- LISTE DES DÉFIS ---
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // Flux des défis globaux (Firebase)
              stream: _firestore
                  .collection('challenges')
                  .orderBy('created_at', descending: true)
                  .snapshots(),
              builder: (context, challengeListSnapshot) {
                // Loader initial si on attend Firebase ET les POI locaux
                if (challengeListSnapshot.connectionState ==
                        ConnectionState.waiting &&
                    _localPoiChallenges.isEmpty) {
                  return const Center(
                      child: CircularProgressIndicator(color: primaryGreen));
                }

                final firebaseChallenges = challengeListSnapshot.data?.docs
                        .map((doc) => Challenge.fromFirestore(doc))
                        .toList() ??
                    [];

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    // Flux de la progression utilisateur
                    stream: _firestore
                        .collection('user_challenges')
                        .where('user_id', isEqualTo: widget.currentUserId)
                        .snapshots(),
                    builder: (context, userProgressSnapshot) {
                      // Création d'une Map pour accès rapide à la progression
                      final Map<String, DocumentSnapshot> userProgressMap = {};
                      if (userProgressSnapshot.hasData) {
                        for (var doc in userProgressSnapshot.data!.docs) {
                          userProgressMap[doc.id] = doc;
                        }
                      }

                      // --- 1. FUSION DES LISTES ---
                      List<Challenge> challengesToDisplay = [];

                      // A. Défis Firebase (Campagnes nationales / Partenaires)
                      for (var fc in firebaseChallenges) {
                        String uid = '${widget.currentUserId}_${fc.id}';
                        challengesToDisplay.add(Challenge.fromFirestore(null,
                            rawChallengeData: fc.toMap(),
                            userChallengeSnapshot: userProgressMap[uid]
                                as DocumentSnapshot<Map<String, dynamic>>?));
                      }

                      // B. Défis Locaux (Générés via Google Places)
                      challengesToDisplay.addAll(_localPoiChallenges);

                      // --- 2. TRI INTELLIGENT ---
                      if (challengesToDisplay.isNotEmpty) {
                        challengesToDisplay.sort((a, b) {
                          EcoStore? storeA;
                          EcoStore? storeB;
                          try {
                            if (a.partnerStoreId != null)
                              storeA = widget.ecoStores
                                  .firstWhere((s) => s.id == a.partnerStoreId);
                          } catch (_) {}
                          try {
                            if (b.partnerStoreId != null)
                              storeB = widget.ecoStores
                                  .firstWhere((s) => s.id == b.partnerStoreId);
                          } catch (_) {}

                          // CRITÈRE 1 PRIORITAIRE : Boost Visibilité Commerçant activé
                          bool boostedA =
                              storeA?.isVisibilityBoostEnabled ?? false;
                          bool boostedB =
                              storeB?.isVisibilityBoostEnabled ?? false;
                          if (boostedA != boostedB) return boostedB ? 1 : -1;

                          // CRITÈRE 2 : Multiplicateur lame
                          double multA = storeA?.lamePointMultiplier ?? 1.0;
                          double multB = storeB?.lamePointMultiplier ?? 1.0;
                          if (multB != multA) return multB.compareTo(multA);

                          // CRITÈRE 3 : Récompense totale
                          int totalRewardA = a.rewardLame * (a.visitCount ?? 1);
                          int totalRewardB = b.rewardLame * (b.visitCount ?? 1);
                          int rewardComparison =
                              totalRewardB.compareTo(totalRewardA);
                          if (rewardComparison != 0) return rewardComparison;

                          // CRITÈRE 4 : Proximité
                          if (_lastKnownUserLocation != null &&
                              a.latitude != null &&
                              b.latitude != null) {
                            final distA =
                                toolkit.SphericalUtil.computeDistanceBetween(
                                    toolkit.LatLng(
                                        _lastKnownUserLocation!.latitude,
                                        _lastKnownUserLocation!.longitude),
                                    toolkit.LatLng(a.latitude!, a.longitude!));
                            final distB =
                                toolkit.SphericalUtil.computeDistanceBetween(
                                    toolkit.LatLng(
                                        _lastKnownUserLocation!.latitude,
                                        _lastKnownUserLocation!.longitude),
                                    toolkit.LatLng(b.latitude!, b.longitude!));
                            return distA.compareTo(distB);
                          }
                          return 0;
                        });
                      }

                      // --- 3. GESTION LISTE VIDE ---
                      if (challengesToDisplay.isEmpty && _isLoadingLocalPois) {
                        return const Center(
                            child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: CircularProgressIndicator(color: primaryGreen),
                        ));
                      }

                      if (challengesToDisplay.isEmpty) {
                        return const Center(
                            child:
                                Text("Aucun défi disponible pour le moment."));
                      }

                      // --- 4. AFFICHAGE DE LA LISTE ---
                      bool hasSuperDefi = _localPoiChallenges.isNotEmpty;
                      int itemCount = challengesToDisplay.length +
                          (_isLoadingLocalPois ? 1 : 0) +
                          (hasSuperDefi ? 1 : 0);

                      return ListView.builder(
                        padding: const EdgeInsets.all(12.0),
                        itemCount: itemCount,
                        itemBuilder: (context, index) {
                          if (_isLoadingLocalPois && index == 0) {
                            return const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Center(
                                    child: LinearProgressIndicator(
                                        color: primaryGreen)));
                          }

                          int currentIndex =
                              index - (_isLoadingLocalPois ? 1 : 0);

                          if (hasSuperDefi && currentIndex == 0) {
                            int completedPoi = _localPoiChallenges
                                .where((c) =>
                                    c.status == ChallengeStatus.rewardClaimed)
                                .length;
                            int totalPoi = _localPoiChallenges.length;
                            double progress =
                                totalPoi > 0 ? (completedPoi / totalPoi) : 0;
                            return Card(
                              color: Colors.purple.shade50,
                              margin: const EdgeInsets.only(bottom: 16.0),
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12.0),
                                side: BorderSide(
                                    color: Colors.purple.shade300, width: 2.0),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.star_rounded,
                                            color: Colors.purple, size: 40),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              const Text("Super Défi",
                                                  style: TextStyle(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: Colors.purple)),
                                              Text(
                                                  "Finissez les 10 défis pour le bonus !",
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: Colors
                                                          .purple.shade800)),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 10, vertical: 8),
                                          decoration: BoxDecoration(
                                              color: Colors.purple,
                                              borderRadius:
                                                  BorderRadius.circular(20)),
                                          child: const Text("+5000 L",
                                              style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16)),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 10,
                                        backgroundColor: Colors.purple.shade100,
                                        color: Colors.purple,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                        "$completedPoi / $totalPoi étapes accomplies",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.purple.shade900)),
                                  ],
                                ),
                              ),
                            );
                          }

                          final finalIndex =
                              currentIndex - (hasSuperDefi ? 1 : 0);
                          if (finalIndex < 0 ||
                              finalIndex >= challengesToDisplay.length)
                            return const SizedBox.shrink();

                          final challenge = challengesToDisplay[finalIndex];

                          EcoStore? partnerStore;
                          if (challenge.partnerStoreId != null) {
                            try {
                              partnerStore = widget.ecoStores.firstWhere(
                                  (s) => s.id == challenge.partnerStoreId);
                            } catch (_) {}
                          }

                          return DefisCard(
                            challenge: challenge,
                            onAction: _handleChallengeAction,
                            onStartChallengeTrip: widget.onStartChallengeTrip,
                            currentUserId: widget.currentUserId,
                            associatedPartnerStore: partnerStore,
                            userLocation: () async {
                              try {
                                Position p = await widget.homeController
                                    .getMyCurrentLocation();
                                return latlong.LatLng(p.latitude, p.longitude);
                              } catch (e) {
                                return const latlong.LatLng(0, 0);
                              }
                            },
                            homeController: widget.homeController,
                            navigationController: widget.navigationController,
                            calculateDynamicReward: _calculateDynamicReward,
                            userProfile: widget.userProfile,
                            weatherData: widget.weatherData,
                          );
                        },
                      );
                    });
              },
            ),
          ),
        ],
      ),
    );
  }
}

// MODIFIÉ: Converti en StatefulWidget pour gérer la sélection du mode de transport
class DefisCard extends StatefulWidget {
  final Challenge challenge;
  final String currentUserId;
  final Function(Challenge, ChallengeStatus,
      {int? newStep,
      String? selectedStore,
      String? proofIdentifier,
      String? ocrResultText,
      bool? isProofValid}) onAction;
  final EcoStore? associatedPartnerStore;
  final Future<latlong.LatLng?> Function() userLocation;
  final HomeController homeController;
  final NavigationController navigationController;
  final Future<int> Function(Challenge, TravelType) calculateDynamicReward;
  final UserProfile userProfile;
  final WeatherData? weatherData;
  final Function(
          Challenge challenge, TravelType travelType, int estimatedReward)
      onStartChallengeTrip;

  const DefisCard({
    Key? key,
    required this.challenge,
    required this.onAction,
    required this.onStartChallengeTrip, // AJOUT
    required this.currentUserId,
    this.associatedPartnerStore,
    required this.userLocation,
    required this.homeController,
    required this.navigationController,
    required this.calculateDynamicReward,
    required this.userProfile,
    this.weatherData,
  }) : super(key: key);

  @override
  State<DefisCard> createState() => _DefisCardState();
}

class _DefisCardState extends State<DefisCard> {
  TravelType _selectedTravelType = TravelType.walk;
  bool _isUpdatingChallenge = false;

  // ── TIMER "RESTER SUR PLACE" ─────────────────────────────────────────────
  Timer? _stayTimer;
  int _staySecondsElapsed = 0;
  bool _isStayTimerRunning = false;
  bool _isInStayZone = false;
  StreamSubscription<Position>? _stayPositionStream;

  @override
  void initState() {
    super.initState();
    // Pour les défis "rester sur place", afficher immédiatement le cercle sur la carte
    final c = widget.challenge;
    if (c.latitude != null &&
        c.longitude != null &&
        c.stayDurationSeconds != null &&
        c.stayDurationSeconds! > 0 &&
        c.status != ChallengeStatus.notStarted &&
        c.status != ChallengeStatus.rewardClaimed &&
        c.status != ChallengeStatus.expired) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.homeController
            .drawCircleOnMap(LatLng(c.latitude!, c.longitude!), 10.0);
      });
    }
  }

  @override
  void dispose() {
    _stayTimer?.cancel();
    _stayPositionStream?.cancel();
    super.dispose();
  }

  /// Lance le suivi de position pour le défi "rester sur place"
  void _startStayTracking() {
    _stayPositionStream?.cancel();
    if (_isStayTimerRunning) return;
    if (widget.challenge.latitude != null &&
        widget.challenge.longitude != null) {
      widget.homeController.drawCircleOnMap(
          LatLng(widget.challenge.latitude!, widget.challenge.longitude!),
          10.0);
    }
    _stayPositionStream?.cancel();
    _stayPositionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 2,
      ),
    ).listen((pos) {
      if (!mounted) return;
      if (widget.challenge.latitude == null) return;

      double dist = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        widget.challenge.latitude!,
        widget.challenge.longitude!,
      );

      bool inZone = dist <= 10.0;
      if (inZone && !_isStayTimerRunning) {
        setState(() {
          _isInStayZone = true;
          _isStayTimerRunning = true;
        });
        _stayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) {
            t.cancel();
            return;
          }
          setState(() => _staySecondsElapsed++);

          // CORRECTION : Défi complété !
          if (_staySecondsElapsed >=
              (widget.challenge.stayDurationSeconds ?? 180)) {
            t.cancel();
            _stayPositionStream?.cancel();
            setState(() {
              _isStayTimerRunning = false;
            });

            int nextStep = widget.challenge.currentStep + 1;
            int total =
                widget.challenge.visitCount ?? widget.challenge.totalSteps;
            // CORRECTION : On vérifie si c'est la dernière étape pour changer le statut !
            ChallengeStatus nextStatus = nextStep >= total
                ? ChallengeStatus.completedPendingReward
                : ChallengeStatus.inProgress;
            widget.onAction(widget.challenge, nextStatus, newStep: nextStep);
          }
          ;
        });
      } else if (!inZone && _isStayTimerRunning) {
        setState(() {
          _isInStayZone = false;
        });
      }
    });
  }

  void _showSnackBar(BuildContext context, String message,
      {Color backgroundColor = Colors.black87,
      Duration duration = const Duration(seconds: 3)}) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
      ),
    );
  }

  void _showStoreSelectionDialog(BuildContext context) {
    List<String> storesToDisplay = widget.challenge.storeOptions ?? [];
    if (widget.challenge.type == ChallengeType.partnerStoreVisit &&
        widget.associatedPartnerStore != null) {
      storesToDisplay = [widget.associatedPartnerStore!.name];
    }

    if (storesToDisplay.isEmpty) {
      _showSnackBar(context, "Aucun magasin disponible pour ce défi.");
      return;
    }

    String? tempSelectedStore = widget.challenge.selectedStore;
    if (widget.challenge.type == ChallengeType.partnerStoreVisit &&
        widget.associatedPartnerStore != null) {
      tempSelectedStore = widget.associatedPartnerStore!.name;
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text("Sélectionner un magasin",
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontSize: 18)),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setStateDialog) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: storesToDisplay.map((store) {
                    return RadioListTile<String>(
                      title: Text(store, style: const TextStyle(fontSize: 14)),
                      value: store,
                      groupValue: tempSelectedStore,
                      onChanged: (String? value) {
                        setStateDialog(() => tempSelectedStore = value);
                      },
                      activeColor: defisPrimaryButton,
                      contentPadding: EdgeInsets.zero,
                    );
                  }).toList(),
                ),
              );
            },
          ),
          actions: <Widget>[
            TextButton(
              child: const Text("Annuler", style: TextStyle(color: textGrey)),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            ElevatedButton(
              child: const Text("Confirmer"),
              onPressed: tempSelectedStore == null
                  ? null
                  : () {
                      widget.onAction(widget.challenge,
                          ChallengeStatus.proofSubmissionNeeded,
                          selectedStore: tempSelectedStore);
                      Navigator.of(dialogContext).pop();
                    },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showProofSubmissionDialog(BuildContext context) async {}

  Future<Map<String, dynamic>> _processProofImage(File imageFile) async {
    return {};
  }

  Future<String> _uploadProofImage(File imageFile) async {
    try {
      final fileName =
          '${widget.currentUserId}_${widget.challenge.id}_${DateTime.now().millisecondsSinceEpoch}.${p.extension(imageFile.path)}';
      final ref = _firebaseStorage
          .ref('challenge_proofs/${widget.currentUserId}/$fileName');
      UploadTask uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask.whenComplete(() => null);
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print("Error uploading image to Firebase Storage: $e");
      rethrow;
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title.toUpperCase(),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.0)),
    );
  }

  Widget _buildDetailRowDialog(String label, String value,
      {bool isBold = false,
      Color? valueColor,
      IconData? icon,
      bool isBonus = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: textGrey, size: 20),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 14, color: textGrey)),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: isBonus ? Colors.green : (valueColor ?? textDark)),
          ),
        ],
      ),
    );
  }

  void _showGainDetailsDialog(BuildContext context) async {
    int estimatedTotal = await widget.calculateDynamicReward(
        widget.challenge, _selectedTravelType);

    double baseEffort = 10;
    double distKm = 0.0;
    double durMin = 0.0;
    double pointsDistance = 0.0;
    double pointsDuree = 0.0;
    double pointsDenivele = 0.0;
    double elevationDiff = 0.0;

    if (widget.challenge.latitude != null &&
        widget.challenge.longitude != null) {
      try {
        final userPos = await widget.homeController.getMyCurrentLocation();
        double rawMeters = toolkit.SphericalUtil.computeDistanceBetween(
                toolkit.LatLng(userPos.latitude, userPos.longitude),
                toolkit.LatLng(
                    widget.challenge.latitude!, widget.challenge.longitude!))
            .toDouble();

        distKm = (rawMeters / 1000.0) * 1.3;
        double speedKmh = _selectedTravelType == TravelType.bike
            ? 15.0
            : (_selectedTravelType == TravelType.transit ? 20.0 : 5.0);
        durMin = (distKm / speedKmh) * 60.0;

        if (_selectedTravelType != TravelType.transit) {
          try {
            String elevUrl =
                "https://api.open-meteo.com/v1/elevation?latitude=${userPos.latitude},${widget.challenge.latitude}&longitude=${userPos.longitude},${widget.challenge.longitude}";
            var elevResp = await Dio().get(elevUrl);
            var elevData = elevResp.data;
            if (elevData['elevation'] != null &&
                (elevData['elevation'] as List).length >= 2) {
              double e1 = (elevData['elevation'][0] as num).toDouble();
              double e2 = (elevData['elevation'][1] as num).toDouble();
              if (e2 > e1) {
                elevationDiff = e2 - e1;
              } else {
                elevationDiff = (e1 - e2).abs() * 0.5;
              }
            }
          } catch (e) {}
        }

        if (_selectedTravelType == TravelType.walk) {
          pointsDistance = distKm * 10.0;
          pointsDuree = durMin * 0.5;
          pointsDenivele = elevationDiff / 3.0;
        } else if (_selectedTravelType == TravelType.bike) {
          pointsDistance = distKm * 6.0;
          pointsDuree = durMin * 0.2;
          pointsDenivele = elevationDiff / 5.0;
        } else if (_selectedTravelType == TravelType.transit) {
          pointsDistance = distKm * 5.0 * 0.8;
          pointsDuree = durMin * 0.5 * 0.8;
        }
        baseEffort = pointsDistance + pointsDuree + pointsDenivele;
      } catch (e) {}
    }

    double challengeMultiplier = 1.0 + (widget.challenge.rewardLame / 100.0);
    double stayBonus = 0;
    if (widget.challenge.stayDurationSeconds != null &&
        widget.challenge.stayDurationSeconds! > 0) {
      int stayMin = (widget.challenge.stayDurationSeconds! / 60).round();
      stayBonus = stayMin.toDouble();
      if (stayMin > 3) stayBonus += (stayMin - 3);
    }
    int visitCount = widget.challenge.visitCount ?? 1;

    double weatherMultiplier = 1.0;
    final weather = widget.weatherData;
    if (weather != null) {
      bool isBadWeather = weather.weatherCode >= 51 ||
          weather.weatherCode == 45 ||
          weather.weatherCode == 48;
      bool isExtremeTemp = weather.temperature < 2 || weather.temperature > 32;
      if (isBadWeather || isExtremeTemp || weather.windSpeed > 30) {
        weatherMultiplier = 1.5;
      }
    }

    double adMultiplier = (widget.userProfile.adPoints >= 10) ? 1.2 : 1.0;
    double vipMultiplier = widget.userProfile.isVip ? 1.15 : 1.0;

    int finalTotal = estimatedTotal;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Center(
                child: Text("Détails de la Récompense",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.purple, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
              _buildSectionHeader("Effort Physique (Estimation)"),
              _buildDetailRowDialog(
                  "Distance estimée (${distKm.toStringAsFixed(1)} km) :",
                  "+${pointsDistance.round()} L",
                  valueColor: Colors.blueGrey),
              _buildDetailRowDialog(
                  "Durée estimée (${durMin.toStringAsFixed(0)} min) :",
                  "+${pointsDuree.round()} L",
                  valueColor: Colors.blueGrey),
              if (_selectedTravelType != TravelType.transit)
                _buildDetailRowDialog(
                    "Dénivelé estimé :", "+${pointsDenivele.round()} L",
                    valueColor: Colors.blueGrey),
              const Divider(),
              _buildDetailRowDialog(
                  "Sous-total Effort :", "${baseEffort.round()} Lames",
                  valueColor: Colors.purple, isBold: true),
              const SizedBox(height: 20),
              _buildSectionHeader("Bonus du Défi"),
              _buildDetailRowDialog(
                  "Multiplicateur Défi (${widget.challenge.rewardLame} Lames) :",
                  "x${challengeMultiplier.toStringAsFixed(2)}",
                  valueColor: Colors.orange,
                  isBold: true),
              if (stayBonus > 0) ...[
                _buildDetailRowDialog(
                    "Temps sur place (${(widget.challenge.stayDurationSeconds! / 60).round()} min) :",
                    "+${stayBonus.round()} L",
                    valueColor: Colors.teal),
              ],
              if (visitCount > 1)
                _buildDetailRowDialog(
                    "Multiplicateur Multi-visites (x$visitCount) :",
                    "x$visitCount",
                    valueColor: Colors.purple,
                    isBold: true),
              const Divider(height: 30),
              _buildSectionHeader("Autres Multiplicateurs"),
              _buildDetailRowDialog("Météo Difficile :",
                  weatherMultiplier > 1.0 ? "x1.5" : "Aucun",
                  valueColor:
                      weatherMultiplier > 1.0 ? Colors.green : Colors.grey,
                  icon: Icons.cloud),
              _buildDetailRowDialog(
                  "Boost Soutien :", adMultiplier > 1.0 ? "x1.2" : "Aucun",
                  valueColor: adMultiplier > 1.0 ? Colors.purple : Colors.grey,
                  icon: Icons.bolt),
              _buildDetailRowDialog("Bonus Premium VIP :",
                  vipMultiplier > 1.0 ? "x1.15" : "Aucun",
                  valueColor: vipMultiplier > 1.0 ? Colors.orange : Colors.grey,
                  icon: Icons.star),
              const Divider(height: 30),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(15)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("GAIN TOTAL ESTIMÉ",
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    Text("$finalTotal Lames",
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Colors.purple)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    List<Widget> buttons = [];

    ChallengeStatus displayStatus = widget.challenge.status;
    bool isOnCooldown = false;
    DateTime? cooldownEnd;

    // --- NOUVEAU : LOGIQUE DE BLOCAGE JUSQU'À MINUIT ---
    if (displayStatus == ChallengeStatus.rewardClaimed &&
        widget.challenge.lastCompletedAt != null) {
      final completedTime = widget.challenge.lastCompletedAt!.toDate();
      final now = DateTime.now();
      bool isCompletedToday = completedTime.year == now.year &&
          completedTime.month == now.month &&
          completedTime.day == now.day;

      if (isCompletedToday) {
        isOnCooldown = true;
        cooldownEnd = DateTime(now.year, now.month, now.day + 1);
      } else {
        displayStatus = ChallengeStatus.notStarted;
      }
    }

    bool isPartnerStoreChallenge =
        widget.challenge.type == ChallengeType.partnerStoreVisit &&
            widget.associatedPartnerStore != null;
    bool isLocalPoiChallenge =
        widget.challenge.type == ChallengeType.localPoiVisit;
    bool isGeolocatedChallenge = isLocalPoiChallenge || isPartnerStoreChallenge;

    bool isPurchaseChallenge =
        widget.challenge.type == ChallengeType.purchaseScanProof ||
            isPartnerStoreChallenge;

    if (isOnCooldown) {
      buttons.add(Expanded(
        child: ElevatedButton(
          onPressed: null,
          style: ElevatedButton.styleFrom(
            disabledBackgroundColor: Colors.grey[300],
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: CooldownTimerWidget(
            targetDate: cooldownEnd!,
            onTimerFinished: () {
              if (mounted) setState(() {});
            },
          ),
        ),
      ));
    } else if (displayStatus == ChallengeStatus.notStarted) {
      buttons.add(Expanded(
        child: ElevatedButton(
          onPressed: () async {
            if (isGeolocatedChallenge) {
              int reward = await widget.calculateDynamicReward(
                  widget.challenge, _selectedTravelType);
              widget.onStartChallengeTrip(
                  widget.challenge, _selectedTravelType, reward);
              // AJOUT CRUCIAL : On informe Firebase que le défi est commencé !
              widget.onAction(widget.challenge, ChallengeStatus.inProgress,
                  newStep: 0);
            } else if (isPurchaseChallenge) {
              _showStoreSelectionDialog(context);
            } else {
              widget.onAction(widget.challenge, ChallengeStatus.inProgress,
                  newStep: 0);
            }
          },
          child: const Text("Commencer le trajet"),
        ),
      ));
    } else if (displayStatus == ChallengeStatus.inProgress &&
        (widget.challenge.type == ChallengeType.visitMultiple ||
            widget.challenge.type == ChallengeType.localPoiVisit)) {
      bool isStayChallenge = (widget.challenge.stayDurationSeconds ?? 0) > 0;

      if (isStayChallenge) {
        // ── Défi "rester sur place" : afficher timer + bouton activer ──
        int totalSecs = widget.challenge.stayDurationSeconds ?? 180;
        int remaining = (totalSecs - _staySecondsElapsed).clamp(0, totalSecs);
        int remMin = remaining ~/ 60;
        int remSec = remaining % 60;

        if (!_isStayTimerRunning) {
          buttons.add(Expanded(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.my_location, size: 16),
              label: const Text("Je suis sur place"),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              onPressed: _startStayTracking,
            ),
          ));
        } else {
          buttons.add(Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: _isInStayZone
                    ? Colors.teal.withOpacity(0.1)
                    : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: _isInStayZone ? Colors.teal : Colors.orange),
              ),
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_isInStayZone ? Icons.location_on : Icons.location_off,
                    color: _isInStayZone ? Colors.teal : Colors.orange,
                    size: 16),
                const SizedBox(width: 6),
                Text(
                  _isInStayZone
                      ? "Sur place : $remMin:${remSec.toString().padLeft(2, '0')}"
                      : "Revenez dans la zone !",
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _isInStayZone ? Colors.teal : Colors.orange),
                ),
              ]),
            ),
          ));
        }
      } else {
        // ── Défi de navigation classique ──
        String buttonText;
        bool enableButton = true;
        Function()? action;

        bool isNavigationActiveForThisChallenge =
            widget.homeController.mapStatus.value == Constants.onDestination &&
                widget.navigationController.activeChallenge?.id ==
                    widget.challenge.id;

        if (isNavigationActiveForThisChallenge) {
          buttonText = "Navigation en cours...";
          enableButton = false;
        } else if (isLocalPoiChallenge || isPartnerStoreChallenge) {
          buttonText = "Reprendre la navigation";
          action = () async {
            int reward = await widget.calculateDynamicReward(
                widget.challenge, _selectedTravelType);
            widget.onStartChallengeTrip(
                widget.challenge, _selectedTravelType, reward);
          };
        } else {
          buttonText =
              "Valider Étape (${widget.challenge.currentStep}/${widget.challenge.visitCount ?? widget.challenge.totalSteps})";
          action = () {
            int nextStep = widget.challenge.currentStep + 1;
            widget.onAction(widget.challenge, ChallengeStatus.inProgress,
                newStep: nextStep);
          };
        }
        buttons.add(Expanded(
            child: ElevatedButton(
                onPressed: enableButton ? action : null,
                child: Text(buttonText))));
      }
    } else if (displayStatus == ChallengeStatus.storeSelectionNeeded ||
        (isPartnerStoreChallenge && widget.challenge.selectedStore == null)) {
      buttons.add(Expanded(
          child: ElevatedButton(
              onPressed: () => _showStoreSelectionDialog(context),
              child: const Text("Choisir magasin"))));
    } else if (displayStatus == ChallengeStatus.proofSubmissionNeeded) {
// Bouton géré ailleurs ou non nécessaire ici
    } else if (displayStatus == ChallengeStatus.completedPendingReward) {
      buttons.add(Expanded(
          child: ElevatedButton(
              onPressed: _isUpdatingChallenge
                  ? null
                  : () async {
                      setState(() => _isUpdatingChallenge = true);
                      try {
                        await widget.onAction(
                            widget.challenge, ChallengeStatus.rewardClaimed);
                      } finally {
                        if (mounted)
                          setState(() => _isUpdatingChallenge = false);
                      }
                    },
              child: _isUpdatingChallenge
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text("Récupérer récompense"))));
      if (widget.challenge.proofImageIdentifier != null &&
          widget.challenge.proofImageIdentifier!.startsWith('http')) {
        buttons.add(const SizedBox(width: 8));
        buttons.add(Expanded(
            child: OutlinedButton(
                onPressed: () async {
                  final uri =
                      Uri.tryParse(widget.challenge.proofImageIdentifier!);
                  if (uri != null && await canLaunchUrl(uri)) {
                    await launchUrl(uri);
                  } else {
                    _showSnackBar(context, 'Impossible d\'ouvrir l\'image.');
                  }
                },
                style: OutlinedButton.styleFrom(
                    backgroundColor: defisSecondaryButton.withOpacity(0.5)),
                child: const Text("Voir Preuve"))));
      }
    } else if (displayStatus == ChallengeStatus.rewardClaimed) {
      buttons.add(Expanded(
          child: ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
              child: const Text("Récompense obtenue"))));
    } else if (displayStatus == ChallengeStatus.expired) {
      buttons.add(Expanded(
          child: ElevatedButton(
              onPressed: null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[400],
                  foregroundColor: Colors.black54),
              child: const Text("Défi Expiré"))));
    }

    String statusText = "Non commencé";
    Color statusColor = textGrey;

    if (isOnCooldown) {
      statusText = "Défi accompli pour aujourd'hui";
      statusColor = Colors.orange;
    } else if (displayStatus == ChallengeStatus.inProgress) {
      statusText = "En cours";
      statusColor = Colors.blue;
    } else if (displayStatus == ChallengeStatus.storeSelectionNeeded) {
      statusText = "Sélection magasin nécessaire";
      statusColor = Colors.orange;
    } else if (displayStatus == ChallengeStatus.proofSubmissionNeeded) {
      statusText = "Preuve requise";
      statusColor = Colors.orange;
    } else if (displayStatus == ChallengeStatus.completedPendingReward) {
      statusText = "Récompense à récupérer !";
      statusColor = primaryGreen;
    } else if (displayStatus == ChallengeStatus.rewardClaimed) {
      statusText = "Récompense obtenue !";
      statusColor = Colors.green.shade700;
    } else if (displayStatus == ChallengeStatus.expired) {
      statusText = "Défi expiré.";
      statusColor = Colors.red.shade700;
    }

    return Card(
      color: defisCardBackground,
      margin: const EdgeInsets.only(bottom: 16.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
        // Bordure orange si boosté par commerçant
        side: (widget.associatedPartnerStore?.isVisibilityBoostEnabled ?? false)
            ? const BorderSide(color: Colors.orange, width: 2.0)
            : BorderSide.none,
      ),
      elevation:
          (widget.associatedPartnerStore?.isVisibilityBoostEnabled ?? false)
              ? 5
              : 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge "SPONSORISÉ" si boosté commerçant
            if (widget.associatedPartnerStore?.isVisibilityBoostEnabled ??
                false)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Colors.orange, Colors.deepOrange]),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star, color: Colors.white, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    "SPONSORISÉ · x${(widget.associatedPartnerStore?.lamePointMultiplier ?? 1.0).toStringAsFixed(1)} Lames",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold),
                  ),
                ]),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.challenge.title,
                          style: theme.textTheme.titleLarge),
                      if (isPartnerStoreChallenge &&
                          widget.associatedPartnerStore != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                              "${widget.associatedPartnerStore!.name} (${widget.associatedPartnerStore!.address})",
                              style: theme.textTheme.titleMedium?.copyWith(
                                  color: primaryGreen,
                                  fontWeight: FontWeight.bold)),
                        ),
                      if (isLocalPoiChallenge &&
                          widget.challenge.latitude != null &&
                          widget.challenge.longitude != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                              "Lieu : ${widget.challenge.latitude!.toStringAsFixed(3)}, ${widget.challenge.longitude!.toStringAsFixed(3)}",
                              style: theme.textTheme.titleMedium?.copyWith(
                                  color: primaryGreen,
                                  fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(height: 4),
                      Text(widget.challenge.dynamicChallengeDescription,
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 6),
                      // Tags de type de défi
                      Wrap(spacing: 6, children: [
                        if ((widget.challenge.visitCount ?? 1) > 1)
                          _buildDefiTag(
                            "× ${widget.challenge.visitCount} visites",
                            Colors.blue,
                            Icons.repeat,
                          ),
                        if ((widget.challenge.stayDurationSeconds ?? 0) > 0)
                          _buildDefiTag(
                            "${((widget.challenge.stayDurationSeconds ?? 0) / 60).round()} min sur place",
                            Colors.teal,
                            Icons.timer,
                          ),
                        if ((widget.challenge.visitCount ?? 1) > 1)
                          _buildDefiTag(
                            "Double Lames",
                            Colors.purple,
                            Icons.bolt,
                          ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FutureBuilder<int>(
                  future: widget.calculateDynamicReward(
                      widget.challenge, _selectedTravelType),
                  builder: (context, snapshot) {
                    String gainText = "-";
                    int? gainValue;
                    if (snapshot.connectionState == ConnectionState.done &&
                        snapshot.hasData) {
                      gainValue = snapshot.data;
                      gainText = gainValue.toString();
                    }

                    // Infos bonus pour l'affichage dans le cercle
                    int visitCount = widget.challenge.visitCount ?? 1;
                    bool isMultiVisit = visitCount > 1;
                    bool isStayChallenge =
                        (widget.challenge.stayDurationSeconds ?? 0) > 0;
                    bool isBoostedByStore = widget
                            .associatedPartnerStore?.isVisibilityBoostEnabled ??
                        false;
                    double storeMultiplier =
                        widget.associatedPartnerStore?.lamePointMultiplier ??
                            1.0;

                    // Texte avantage défi
                    String advantageText = "";
                    if (isMultiVisit && gainValue != null) {
                      advantageText = "x$visitCount visites";
                    } else if (isStayChallenge) {
                      int mins =
                          ((widget.challenge.stayDurationSeconds ?? 0) / 60)
                              .round();
                      advantageText = "+$mins min";
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Badge "Boosté Commerçant"
                        if (isBoostedByStore)
                          Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "⚡ x${storeMultiplier.toStringAsFixed(1)}",
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                        InkWell(
                          onTap: () => _showGainDetailsDialog(context),
                          borderRadius: BorderRadius.circular(30),
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isBoostedByStore
                                    ? Colors.orange.withOpacity(0.15)
                                    : lightGreen.withOpacity(0.5),
                                border: Border.all(
                                    color: isBoostedByStore
                                        ? Colors.orange
                                        : primaryGreen,
                                    width: isBoostedByStore ? 2.5 : 1.5)),
                            child: Center(
                              child: (snapshot.connectionState ==
                                      ConnectionState.waiting)
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: primaryGreen))
                                  : Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(gainText,
                                            style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: isBoostedByStore
                                                    ? Colors.orange.shade800
                                                    : textDark)),
                                        const Text("Lames",
                                            style: TextStyle(
                                                fontSize: 9, color: textGrey)),
                                        // Avantage défi (multi-visit ou stay)
                                        if (advantageText.isNotEmpty)
                                          Text(advantageText,
                                              style: TextStyle(
                                                  fontSize: 8,
                                                  fontWeight: FontWeight.bold,
                                                  color: isBoostedByStore
                                                      ? Colors.orange
                                                      : primaryGreen)),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                        // Bonus défi en bas du cercle
                        if (gainValue != null &&
                            gainValue > (widget.challenge.rewardLame))
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: primaryGreen.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                  color: primaryGreen.withOpacity(0.4)),
                            ),
                            child: Text(
                              "bonus +${gainValue - widget.challenge.rewardLame}L",
                              style: const TextStyle(
                                  fontSize: 8,
                                  color: primaryGreen,
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 10),
// NOUVEAU: Sélecteur de mode de transport pour les défis géolocalisés
            if (isGeolocatedChallenge &&
                displayStatus == ChallengeStatus.notStarted)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: SingleChildScrollView(
                  // Ajout pour éviter l'overflow
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildTravelTypeChip(
                          Icons.directions_walk, TravelType.walk, "Pied"),
                      const SizedBox(width: 8), // Espacement manuel si besoin
                      _buildTravelTypeChip(
                          Icons.directions_bike, TravelType.bike, "Vélo"),
                      const SizedBox(width: 8),
                      _buildTravelTypeChip(
                          Icons.directions_bus, TravelType.transit, "Transit"),
                    ],
                  ),
                ),
              ),
            Row(
              children: List.generate(
                  widget.challenge.type == ChallengeType.visitMultiple ||
                          widget.challenge.type == ChallengeType.localPoiVisit
                      ? (widget.challenge.visitCount ??
                          widget.challenge.totalSteps)
                      : 1, (index) {
                bool isFilled = index < widget.challenge.currentStep;
                if ((widget.challenge.type == ChallengeType.purchaseScanProof ||
                        isPartnerStoreChallenge) &&
                    widget.challenge.totalSteps == 1) {
                  if (displayStatus == ChallengeStatus.completedPendingReward ||
                      displayStatus == ChallengeStatus.rewardClaimed) {
                    isFilled = true;
                  } else if (displayStatus ==
                          ChallengeStatus.proofSubmissionNeeded &&
                      (widget.challenge.isProofValid ?? false)) {
                    isFilled = true;
                  } else {
                    isFilled = false;
                  }
                }

                return Expanded(
                  child: Container(
                    height: 10,
                    margin: EdgeInsets.only(
                        right: index <
                                (widget.challenge.type ==
                                                ChallengeType.visitMultiple ||
                                            widget.challenge.type ==
                                                ChallengeType.localPoiVisit
                                        ? (widget.challenge.visitCount ??
                                            widget.challenge.totalSteps)
                                        : 1) -
                                    1
                            ? 3
                            : 0),
                    decoration: BoxDecoration(
                      color:
                          isFilled ? defisProgressFilled : defisProgressEmpty,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 10),
            Text(statusText,
                style: theme.textTheme.bodyLarge
                    ?.copyWith(fontSize: 14, color: statusColor)),
            const SizedBox(height: 12),
            if (buttons.isNotEmpty)
              Row(
                children: buttons,
              )
          ],
        ),
      ),
    );
  }

  Widget _buildDefiTag(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.bold)),
      ]),
    );
  }

// NOUVEAU: Widget pour créer les chips de sélection de transport
  Widget _buildTravelTypeChip(IconData icon, TravelType type, String label) {
    bool isSelected = _selectedTravelType == type;
    return ChoiceChip(
      label: Text(label),
      avatar: Icon(icon, color: isSelected ? Colors.white : textGrey),
      selected: isSelected,
      onSelected: (bool selected) {
        if (selected) {
          setState(() {
            _selectedTravelType = type;
          });
        }
      },
      selectedColor: defisPrimaryButton,
      labelStyle: TextStyle(color: isSelected ? Colors.white : textDark),
      backgroundColor: defisSecondaryButton,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected ? defisPrimaryButton : Colors.grey.shade300,
        ),
      ),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  final UserProfile userProfile;
  final WeatherData? weatherData;
  final String currentWeatherTextForHome;
  final Function(int, {String? source}) addLamePoints;
  final Function(latlong.LatLng?) onFetchWeatherWithLocation;
  final Function() onProfileModified;
  final List<EcoStore> ecoStores;
  final Function(EcoStore, TravelType) onStartStoreTrip;
  final StoreTripData? pendingStoreTrip;
  final VoidCallback onProfileButtonPressed;
  final VoidCallback onShowLameHistory;
  final VoidCallback onShowStoresTab;
  final ChallengeTripData? pendingChallengeTrip;

  /// Callback quand un trajet vers un magasin est terminé (storeId, completedAt)
  final void Function(String storeId, DateTime completedAt)?
      onStoreTripCompleted;

  /// Callback quand l'utilisateur rentre à domicile (vider les validations en attente)
  final VoidCallback? onUserReturnedHome;
  const MainHomeScreen({
    Key? key,
    required this.userProfile,
    required this.weatherData,
    required this.currentWeatherTextForHome,
    required this.addLamePoints,
    required this.onFetchWeatherWithLocation,
    required this.onProfileModified,
    required this.ecoStores,
    required this.onStartStoreTrip,
    required this.onProfileButtonPressed,
    required this.onShowLameHistory,
    required this.onShowStoresTab,
    this.pendingStoreTrip,
    this.pendingChallengeTrip,
    this.onStoreTripCompleted,
    this.onUserReturnedHome,
  }) : super(key: key);

  @override
  _MainHomeScreenState createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  late HomeController homeController;
  late NavigationController navigationController;
  late SpeedController speedController;

  // --- Données UI & Suggestions ---
  List<EcoStore> _dailySuggestedStores = [];
  bool _isTransitOptionsExpanded = false; // Par défaut fermé pour le transit

  // --- Navigation & Recherche ---
  TravelType _selectedTravelType = TravelType.bike; // Mode par défaut
  List<Map<String, dynamic>> _placePredictions = [];
  final TextEditingController _destinationController = TextEditingController();

  // --- UI Heights ---
  final GlobalKey _upperControlsBarKey = GlobalKey();
  double _upperControlsBarHeight = 0.0;

  // --- Transit (Transport en commun) ---
  final TextEditingController _originController = TextEditingController();
  List<Map<String, dynamic>> _originPlacePredictions = [];
  LatLng? _originCoords;
  Timer? _originPlacePredictionDebounce;
  Timer? _destinationPlacePredictionDebounce;
  TransitTimeOption _transitTimeOption = TransitTimeOption.leaveNow;
  DateTime _selectedTransitTime = DateTime.now();
  bool _validateWalkingLegs = true;

  // --- Calculs Gains ---
  int _calculatedBaseGain = 0;
  Map<String, dynamic> _currentRouteData = {
    'duration': 'N/A',
    'distance': 'N/A',
  };

  // --- État Trajet Magasin ---
  EcoStore? _activeStoreTrip;
  int _activeStoreTripCashback = 0;

  // --- État Trajet Défi ---
  Challenge? _activeChallenge;
  int? _challengeEstimatedReward;
  final List<Worker> _workers = [];

  @override
  void initState() {
    super.initState();

    homeController = Get.find<HomeController>();
    navigationController = Get.find<NavigationController>();
    speedController = Get.find<SpeedController>();

    // Écouter les intents du widget Android
    _setupWidgetIntentListener();

    // Câbler le callback pour les trajets normaux (sans magasin/défi/travail)
    navigationController.setOnNormalDestinationReachedCallback((int gain) {
      widget.addLamePoints(gain, source: "Trajet");
    });

    // Listener d'arrivée générique (stocké pour libération dans dispose)
    _workers.add(ever(homeController.arrived, _handleArrival));

    // --- RECALCUL AUTOMATIQUE DES GAINS ---
    _workers.add(ever(homeController.activeRouteRawDistanceMeters,
        (_) => _updateGainAndRouteData()));
    _workers.add(ever(homeController.activeRouteRawDurationSeconds,
        (_) => _updateGainAndRouteData()));
    _workers.add(
        ever(homeController.elevationGain, (_) => _updateGainAndRouteData()));

    // Nettoyage quand on efface la destination
    _workers.add(ever(homeController.destination, (String dest) {
      if (dest.isEmpty && mounted) {
        _destinationController.clear();
        setState(() {
          _calculatedBaseGain = 0;
          _activeChallenge = null;
        });
      }
    }));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Calcul hauteur barre du haut pour padding
      if (_upperControlsBarKey.currentContext != null) {
        final RenderBox? renderBox = _upperControlsBarKey.currentContext!
            .findRenderObject() as RenderBox?;
        if (renderBox != null && mounted) {
          setState(() => _upperControlsBarHeight = renderBox.size.height);
        }
      }

      // Génération suggestions
      _generateDailyStoreSuggestions();

      SharedPreferences.getInstance().then((prefs) {
        prefs.remove('active_nav_running');
      });
      // Gestion des trajets en attente (venant d'autres onglets)
      if (widget.pendingStoreTrip != null) {
        _initiateStoreTrip(widget.pendingStoreTrip!);
      }
      if (widget.pendingChallengeTrip != null) {
        _initiateChallengeTrip(widget.pendingChallengeTrip!);
      }
    });
  }

  void _handleWidgetIntent(Map<dynamic, dynamic> data) {
    if (data['action'] == 'START_FAVORITE_ROUTE') {
      String routeName = data['route_name'] ?? '';
      String destination = data['route_destination'] ?? '';
      String travelModeStr = data['travel_mode'] ?? 'walk';

      double lat = (data['lat'] as num?)?.toDouble() ?? 0.0;
      double lng = (data['lng'] as num?)?.toDouble() ?? 0.0;

      // CORRECTION CRITIQUE : Si Android envoie NaN, on le transforme en 0.0
      // Ainsi, le code passera dans le bloc "else" et lancera la recherche d'adresse (_startFavoriteRoute)
      if (lat.isNaN) lat = 0.0;
      if (lng.isNaN) lng = 0.0;

      if (destination.isNotEmpty || routeName.isNotEmpty) {
        TravelType mode = _parseWidgetTravelType(travelModeStr);

        // Si on a des coordonnées valides
        if (lat != 0.0 && lng != 0.0) {
          final travelMode = mode == TravelType.walk
              ? TravelMode.walking
              : mode == TravelType.bike
                  ? TravelMode.bicycling
                  : TravelMode.transit;
          final destLabel = routeName.isNotEmpty ? routeName : destination;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _destinationController.text = destLabel;
              _selectedTravelType = mode;
            });
            homeController.setDestination(destLabel, LatLng(lat, lng),
                mode: travelMode);
            _startNavWhenRouteReady();
          });
        } else {
          // SI PAS DE COORDONNÉES, ON FAIT UNE RECHERCHE PAR LE NOM (Ce qui résout ton problème !)
          Map<String, dynamic>? route;
          for (var favoriteRoute in widget.userProfile.favoriteRoutes) {
            if (favoriteRoute['name'] == routeName ||
                favoriteRoute['destination'] == destination) {
              route = favoriteRoute;
              break;
            }
          }
          if (route != null) {
            _startFavoriteRoute(route, mode, autoStart: true);
          } else if (destination.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() {
                _destinationController.text = destination;
                _selectedTravelType = mode;
              });
              _calculateAndSetDestination().then((_) {
                _startNavWhenRouteReady();
              });
            });
          }
        }
      }
    }
  }

  // Modifiez la signature pour accepter autoStart
  void _startFavoriteRoute(Map<String, dynamic> route, TravelType selectedMode,
      {bool autoStart = false}) async {
    String destination = route['destination'] ?? '';

    if (destination.isEmpty) return;

    try {
      setState(() {
        _destinationController.text = destination;
        _selectedTravelType = selectedMode;
      });

      final place = await PhotonService().geocode(destination);
      if (place != null) {
        final lat = double.tryParse(place['lat']?.toString() ?? '0');
        final lon = double.tryParse(place['lon']?.toString() ?? '0');
        if (lat != null && lon != null && lat != 0 && lon != 0) {
          final LatLng coords = LatLng(lat, lon);

          final travelMode = selectedMode == TravelType.walk
              ? TravelMode.walking
              : selectedMode == TravelType.bike
                  ? TravelMode.bicycling
                  : TravelMode.transit;

          homeController.setDestination(destination, coords, mode: travelMode);

          if (autoStart) {
            _startNavWhenRouteReady();
          }
          return;
        }
      }
      _calculateAndSetDestination();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
    }
  }

  // --- NOUVELLE MÉTHODE : Attente intelligente de la fin du calcul d'itinéraire ---
  void _startNavWhenRouteReady() {
    // Si l'itinéraire est déjà calculé et prêt, on lance immédiatement
    if (!homeController.gettingRoute.value &&
        homeController.polylineCoordinates.isNotEmpty) {
      navigationController.navigateToDestination(
          validateWalkingLegs: _validateWalkingLegs);
      return;
    }

    // Sinon, on écoute la variable 'gettingRoute' de GetX
    Worker? worker;
    worker = ever(homeController.gettingRoute, (bool isGettingRoute) {
      // Dès que c'est fini (false)
      if (!isGettingRoute) {
        worker?.dispose(); // On détruit l'écouteur
        if (homeController.polylineCoordinates.isNotEmpty) {
          navigationController.navigateToDestination(
              validateWalkingLegs: _validateWalkingLegs);
        } else if (homeController.currentTravelMode.value ==
                TravelMode.transit &&
            homeController.transitRouteOptions.isNotEmpty) {
          homeController.showTransitOptions.value = true;
        } else {
          // L'API a échoué, on annule la restauration pour ne pas bloquer l'UI
          homeController.clearDestination();
          _showSnackBar("Impossible de restaurer l'itinéraire.",
              backgroundColor: Colors.red);
        }
      }
    });

    // Timeout de sécurité (10 secondes)
    Future.delayed(const Duration(seconds: 10), () {
      worker?.dispose();
      // Si au bout de 10s on n'est toujours pas en navigation, on reset
      if (homeController.mapStatus.value != Constants.onDestination) {
        if (homeController.currentTravelMode.value == TravelMode.transit &&
            homeController.transitRouteOptions.isNotEmpty) {
          homeController.showTransitOptions.value = true;
        } else {
          homeController.clearDestination();
          _showSnackBar("Délai expiré lors de la restauration de l'itinéraire.",
              backgroundColor: Colors.red);
        }
      }
    });
  }

  @override
  void didUpdateWidget(MainHomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Gestion des mises à jour venant du parent (ex: changement d'onglet vers Home avec un trajet)
    if (widget.pendingStoreTrip != null &&
        oldWidget.pendingStoreTrip != widget.pendingStoreTrip) {
      _initiateStoreTrip(widget.pendingStoreTrip!);
    }
    if (widget.pendingChallengeTrip != null &&
        oldWidget.pendingChallengeTrip != widget.pendingChallengeTrip) {
      _initiateChallengeTrip(widget.pendingChallengeTrip!);
    }
  }

  @override
  void dispose() {
    for (final worker in _workers) {
      worker.dispose();
    }
    _workers.clear();
    _originPlacePredictionDebounce?.cancel();
    _destinationPlacePredictionDebounce?.cancel();
    _destinationController.dispose();
    _originController.dispose();
    super.dispose();
  }

  // --- LOGIQUE METIER ---

  void _handleArrival(bool isArrived) {
    // Logique générique d'arrivée si nécessaire (ex: sons, vibrations)
    // La logique spécifique (Magasin/Défi) est gérée par les callbacks du NavigationController
  }

  void _generateDailyStoreSuggestions() async {
    if (widget.ecoStores.isEmpty) return;

    Position userPos = await homeController.getMyCurrentLocation();
    List<EcoStore> candidates = [];
    final random = Random();

    // 1. Filtrer les magasins dans un rayon max de 30km
    for (var store in widget.ecoStores) {
      double distKm = Geolocator.distanceBetween(
              userPos.latitude,
              userPos.longitude,
              store.coordinates.latitude,
              store.coordinates.longitude) /
          1000.0;

      if (distKm <= 30.0) {
        candidates.add(store);
      }
    }

    // 2. Calculer un score de "Poids"
    Map<EcoStore, double> storeWeights = {};

    for (var store in candidates) {
      double distKm = Geolocator.distanceBetween(
              userPos.latitude,
              userPos.longitude,
              store.coordinates.latitude,
              store.coordinates.longitude) /
          1000.0;

      double weight = 0;

      // Critère 1: Distance
      if (distKm <= 5)
        weight += 80;
      else if (distKm <= 10)
        weight += 50;
      else if (distKm <= 20)
        weight += 20;
      else
        weight += 10;

      // Critère 2: Magasin Or (Boost Visibilité)
      if (store.isVisibilityBoostEnabled) {
        weight *= 4.0;
      }

      // Facteur aléatoire
      weight += random.nextDouble() * 20;
      storeWeights[store] = weight;
    }

    // 3. Trier et garder les 3 premiers
    candidates.sort((a, b) => storeWeights[b]!.compareTo(storeWeights[a]!));

    if (mounted) {
      setState(() {
        _dailySuggestedStores = candidates.take(3).toList();
      });
    }
  }

  void _initiateStoreTrip(StoreTripData tripData) {
    if (!mounted) return;

    setState(() {
      _activeStoreTrip = tripData.store;
      _destinationController.text = tripData.store.name;
      _selectedTravelType = tripData.travelType;
    });

    navigationController.activeChallenge = null;
    navigationController.activeWorkCommuteType = null;

    // Callback récompense magasin : afficher popup avec bouton Valider ticket
    navigationController.setOnStoreDestinationReachedCallback(() {
      int finalPoints = homeController.activeRouteEstimatedGain.value;
      final store = tripData.store;
      final completedAt = DateTime.now();

      setState(() {
        _activeStoreTrip = null;
        _destinationController.clear();
      });

      // Notifier le parent qu'un trajet magasin est terminé (pour afficher Valider dans l'onglet Magasins)
      widget.onStoreTripCompleted?.call(store.id, completedAt);

      // Afficher la popup d'arrivée avec option de validation ticket
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Column(children: [
              Icon(Icons.storefront, size: 45, color: Color(0xFF388E3C)),
              SizedBox(height: 8),
              Text("Vous êtes arrivé(e) !",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.eco_rounded, color: Colors.green),
                      const SizedBox(width: 8),
                      Text("+$finalPoints Lames gagnées !",
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.green)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  "Vous êtes chez ${store.name}.\nSouhaitez-vous valider un achat et scanner votre ticket ?",
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.addLamePoints(finalPoints,
                      source: "Trajet vers ${store.name}");
                },
                child: const Text("Continuer sans valider"),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.receipt),
                label: const Text("Valider mon achat"),
                style: ElevatedButton.styleFrom(
                    backgroundColor: primaryGreen,
                    foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.addLamePoints(finalPoints,
                      source: "Trajet vers ${store.name}");
                  // Lancer le scan ticket directement depuis le contexte principal
                  _triggerStoreValidation(store);
                },
              ),
            ],
          ),
        );
      }
    });

    TravelMode apiTravelMode;
    switch (_selectedTravelType) {
      case TravelType.bike:
        apiTravelMode = TravelMode.bicycling;
        break;
      case TravelType.transit:
        apiTravelMode = TravelMode.transit;
        break;
      case TravelType.walk:
      default:
        apiTravelMode = TravelMode.walking;
        break;
    }

    homeController.setDestination(
        tripData.store.name,
        LatLng(tripData.store.coordinates.latitude,
            tripData.store.coordinates.longitude),
        mode: apiTravelMode,
        isStore: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted)
        _showSnackBar("Itinéraire vers ${tripData.store.name} calculé !",
            backgroundColor: primaryGreen);
    });
  }

  void _initiateChallengeTrip(ChallengeTripData tripData) {
    if (!mounted) return;

    final challenge = tripData.challenge;

    if (challenge.latitude == null || challenge.longitude == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted)
          _showSnackBar("Ce défi n'a pas de destination géographique valide.",
              backgroundColor: Colors.orange);
      });
      return;
    }

    LatLng destCoords = LatLng(challenge.latitude!, challenge.longitude!);
    String navTitle = challenge.title
        .replaceAll("Exploration : ", "")
        .replaceAll("Pause détente à : ", "");

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _destinationController.text = navTitle;
        _selectedTravelType = tripData.travelType;
        _activeChallenge = challenge; // Tracker le défi actif
        _challengeEstimatedReward = tripData.estimatedReward;
        _activeStoreTrip = null;
      });

      navigationController.activeChallenge = challenge;
      navigationController.onStoreDestinationReached = null;

      final travelMode = _selectedTravelType == TravelType.walk
          ? TravelMode.walking
          : _selectedTravelType == TravelType.bike
              ? TravelMode.bicycling
              : TravelMode.transit;

      homeController.setDestination(
        navTitle,
        destCoords,
        mode: travelMode,
        isStore: false,
      );
    });
  }

  Future<void> _calculateAndSetDestination() async {
    final destinationText = _destinationController.text.trim();
    if (destinationText.isEmpty) return;

    setState(() {
      _placePredictions = [];
    });

    FocusScope.of(context).unfocus();

    try {
      final place = await PhotonService().geocode(destinationText);
      if (place != null) {
        final lat = double.tryParse(place['lat']?.toString() ?? '0');
        final lon = double.tryParse(place['lon']?.toString() ?? '0');
        if (lat != null && lon != null && lat != 0 && lon != 0) {
          final LatLng coords = LatLng(lat, lon);

          final travelMode = _selectedTravelType == TravelType.walk
              ? TravelMode.walking
              : _selectedTravelType == TravelType.bike
                  ? TravelMode.bicycling
                  : TravelMode.transit;

          homeController.setDestination(destinationText, coords,
              mode: travelMode);
          return;
        }
      }
    } catch (e) {
      print("Erreur recherche : $e");
    }
    // Si Nominatim échoue, on laisse la logique existante pour ne pas bloquer.
  }

  // --- GESTION DES GAINS ---

  void _updateGainAndRouteData() {
    if (!mounted) return;

    if (_activeChallenge != null && _challengeEstimatedReward != null) {
      setState(() {
        _calculatedBaseGain = _challengeEstimatedReward!;
        _currentRouteData['distance'] = homeController.distanceLeft.value;
        _currentRouteData['duration'] = homeController.timeLeft.value;
      });
      homeController.activeRouteEstimatedGain.value =
          _challengeEstimatedReward!;
      return;
    }

    // Calcul base (Effort + Dénivelé Google)
    int base = _calculateBaseLameGain();

    // Calcul total (Multiplicateurs)
    int total = 0;

    setState(() {
      _calculatedBaseGain = base;
      _currentRouteData['distance'] = homeController.distanceLeft.value;
      _currentRouteData['duration'] = homeController.timeLeft.value;
    });

    total = _calculateTotalLameGain();

    if (total > 0) {
      homeController.activeRouteEstimatedGain.value = total;
    } else {
      if (homeController.activeRouteRawDistanceMeters.value > 0) {
        homeController.activeRouteEstimatedGain.value = 1;
      } else {
        homeController.activeRouteEstimatedGain.value = 0;
      }
    }
  }

  int _calculateBaseLameGain() {
    // Cas Transit (CORRIGÉ)
    if (homeController.currentTravelMode.value == TravelMode.transit ||
        _selectedTravelType == TravelType.transit) {
      if (homeController.transitRouteOptions.isEmpty) return 0;
      final route = homeController.transitRouteOptions.first;
      final leg = route['legs'][0];
      return _calculateGainForTransitOption(leg);
    }

    double meters = homeController.activeRouteRawDistanceMeters.value;
    double seconds = homeController.activeRouteRawDurationSeconds.value;
    double elevationMeters = homeController.elevationGain.value;

    if (meters <= 0 || seconds <= 0) return 0;

    double distanceKm = meters / 1000.0;
    double durationMinutes = seconds / 60.0;
    double score = 0.0;

    // --- MODIFIÉ : Formules physiques plus généreuses pour le dénivelé ---
    if (_selectedTravelType == TravelType.walk) {
      // Marche : 10 pts/km + 0.5 pts/min + 1 pt par 3m de dénivelé positif
      score = (distanceKm * 10.0) +
          (durationMinutes * 0.5) +
          (elevationMeters / 3.0);
    } else if (_selectedTravelType == TravelType.bike) {
      // Vélo : 6 pts/km + 0.2 pts/min + 1 pt par 5m de dénivelé positif
      score = (distanceKm * 6.0) +
          (durationMinutes * 0.2) +
          (elevationMeters / 5.0);
    }

    int finalScore = score.round();
    return (finalScore == 0 && meters > 100) ? 1 : finalScore;
  }

  int _calculateTotalLameGain() {
    double finalGainDouble = _calculatedBaseGain.toDouble();

    // 1. Météo
    if (_isWeatherBoostApplicable()) {
      finalGainDouble *= 1.5;
    }

    // 2. Série de Connexion
    if (widget.userProfile.nextLevelBoost > 1.0) {
      finalGainDouble *= widget.userProfile.nextLevelBoost;
    }

    // 3. Statut VIP
    if (widget.userProfile.isVip) {
      finalGainDouble *= 1.15;
    }

    // 4. Bonus de niveau (Multiplicateur : 1.01 à 2.00)
    final levelData =
        _calculateUserLevel(widget.userProfile.totalLameEarned ?? 0);
    final currentLevel = levelData['currentLevel'] as int;
    double levelMultiplier = 1.0 + (currentLevel * 0.01);
    finalGainDouble *= levelMultiplier;

    // 5. Multiplicateur Ad Points : x1.2 automatique dès 10 ADP
    if (widget.userProfile.adPoints >= 10) {
      finalGainDouble *= 1.2;
    }

    int finalGain = finalGainDouble.round();
    return (finalGain <= 0 && _calculatedBaseGain > 0) ? 1 : finalGain;
  }

  Map<String, dynamic> _calculateUserLevel(int totalLame) {
    int currentLevel = 1;
    int lameNeeded = 500; // Pour le niveau 2
    int totalLameForCurrentLevel = 0;

    // Calculer le niveau actuel
    while (totalLame >= totalLameForCurrentLevel + lameNeeded &&
        currentLevel < 50) {
      totalLameForCurrentLevel += lameNeeded;
      currentLevel++;
      lameNeeded *= 2; // Double à chaque niveau
    }

    // Calculer les Lame nécessaires pour le niveau suivant
    int lameForNextLevel = totalLameForCurrentLevel + lameNeeded;

    // Calculer le progrès vers le niveau suivant
    double progressToNextLevel = 0.0;
    if (currentLevel < 100) {
      int lameInCurrentLevel = totalLame - totalLameForCurrentLevel;
      progressToNextLevel = lameInCurrentLevel / lameNeeded;
      progressToNextLevel = progressToNextLevel.clamp(0.0, 1.0);
    }

    return {
      'currentLevel': currentLevel,
      'lameForCurrentLevel': totalLameForCurrentLevel,
      'lameForNextLevel': lameForNextLevel,
      'progressToNextLevel': progressToNextLevel,
    };
  }

  // --- TRANSIT UTILS ---

  int _calculateGainForTransitOption(dynamic legData,
      {bool isBaseOnly = false}) {
    if (legData == null || legData is! Map) return 0;
    final Map<String, dynamic> leg = Map<String, dynamic>.from(legData);

    if (leg['duration'] == null) return 0;

    try {
      double durationMinutes = 0.0;
      if (leg['duration']['value'] != null) {
        durationMinutes = (leg['duration']['value'] as num).toDouble() / 60.0;
      }

      int transitCount = 0;
      double pointsEcologiques = 0.0;
      const double FE_VOITURE_KM = 180.0;
      const double BUS_NB_PASSAGERS = 50.0;
      const double BUS_CONSO_KM = 900.0;
      const double BUS_CONSO_MINUTE = 15.0;
      const double FE_RAIL_KM = 6.0;
      const double CONVERSION_CO2_POINTS = 1.0 / 40.0;

      final List<dynamic> steps = leg['steps'] as List<dynamic>? ?? [];
      for (var stepData in steps) {
        final step = stepData as Map<String, dynamic>;

        double distanceKm = 0.0;
        if (step['distance'] != null && step['distance']['value'] != null) {
          distanceKm = (step['distance']['value'] as num).toDouble() / 1000.0;
        }
        double stepDurationMinutes = 0.0;
        if (step['duration'] != null && step['duration']['value'] != null) {
          stepDurationMinutes =
              (step['duration']['value'] as num).toDouble() / 60.0;
        }

        if (step['travel_mode'] == 'TRANSIT') {
          transitCount++;

          double co2EmisVoiture = distanceKm * FE_VOITURE_KM;
          double co2EmisUtilisateur = 0.0;
          String vehicleType =
              step['transit_details']?['line']?['vehicle']?['type'] ?? 'BUS';

          if (vehicleType == 'BUS' ||
              vehicleType == 'INTERCITY_BUS' ||
              vehicleType == 'TROLLEYBUS') {
            double emissionBusTotal = (distanceKm * BUS_CONSO_KM) +
                (stepDurationMinutes * BUS_CONSO_MINUTE);
            co2EmisUtilisateur = emissionBusTotal / BUS_NB_PASSAGERS;
          } else {
            co2EmisUtilisateur = distanceKm * FE_RAIL_KM;
          }

          double co2Economise = co2EmisVoiture - co2EmisUtilisateur;
          if (co2Economise > 0) {
            pointsEcologiques += (co2Economise * CONVERSION_CO2_POINTS);
          }
        } else if (step['travel_mode'] == 'WALKING') {
          double co2EmisVoiture = distanceKm * FE_VOITURE_KM;
          pointsEcologiques += (co2EmisVoiture * CONVERSION_CO2_POINTS);
        }
      }

      double baseEffort =
          (durationMinutes * 0.5) + (transitCount * 5.0) + pointsEcologiques;

      if (isBaseOnly) {
        return baseEffort.round();
      }

      double totalPoints = baseEffort;

      if (_isWeatherBoostApplicable()) totalPoints *= 1.5;
      if (widget.userProfile.nextLevelBoost > 1.0)
        totalPoints *= widget.userProfile.nextLevelBoost;
      if (widget.userProfile.isVip) totalPoints *= 1.15;
      if (widget.userProfile.adPoints >= 10) totalPoints *= 1.2;

      int finalGain = totalPoints.round();
      return (finalGain <= 0 && durationMinutes > 0) ? 1 : finalGain;
    } catch (e) {
      print("Erreur calcul gain transit: $e");
      return 0;
    }
  }

  Future<void> _getPlacePredictions(String input) async {
    _destinationPlacePredictionDebounce?.cancel();

    if (input.isEmpty || input.length < 3) {
      if (mounted) {
        setState(() {
          _placePredictions = [];
        });
      }
      return;
    }

    _destinationPlacePredictionDebounce =
        Timer(const Duration(milliseconds: 500), () async {
      try {
        double lat = 48.8566;
        double lon = 2.3522;
        try {
          final pos = await homeController.getMyCurrentLocation();
          lat = pos.latitude;
          lon = pos.longitude;
        } catch (_) {}

        final url = Uri.parse(
            'https://photon.komoot.io/api/?q=${Uri.encodeComponent(input)}&limit=5&lat=$lat&lon=$lon');

        final response = await http.get(url, headers: {
          'User-Agent': 'WalkMoneyApp/1.0 (contact@walkmoney.com)'
        });

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final features = data['features'] as List<dynamic>;

          if (mounted) {
            setState(() {
              _placePredictions = features.map<Map<String, dynamic>>((f) {
                final props = f['properties'] ?? {};
                final coords = f['geometry']?['coordinates'] ?? [0, 0];

                String name = (props['name'] as String?) ?? '';
                String city = (props['city'] as String?) ??
                    (props['town'] as String?) ??
                    (props['village'] as String?) ??
                    '';
                String street = (props['street'] as String?) ?? '';

                String display = name.isNotEmpty ? name : street;
                if (city.isNotEmpty && display.isNotEmpty) {
                  display += ', $city';
                } else if (city.isNotEmpty) {
                  display = city;
                }

                return {
                  'description': display.isNotEmpty ? display : 'Lieu inconnu',
                  'lat': coords.length >= 2 ? coords[1] : 0.0,
                  'lng': coords.length >= 2 ? coords[0] : 0.0,
                  'place_id': (props['osm_id']?.toString() ?? '')
                };
              }).toList(growable: false);
            });
          }
        }
      } catch (e) {
        debugPrint("Erreur Photon destination : $e");
      }
    });
  }

  Future<void> _selectPlace(Map<String, dynamic> prediction) async {
    final description = prediction['description'] as String? ?? '';
    final lat = double.tryParse(prediction['lat']?.toString() ?? '0') ?? 0;
    final lng = double.tryParse(prediction['lng']?.toString() ?? '0') ?? 0;

    if (lat == 0 || lng == 0) {
      _showSnackBar("Coordonnées invalides pour le lieu sélectionné.",
          backgroundColor: Colors.red);
      return;
    }

    setState(() {
      _placePredictions = [];
      _destinationController.text = description;
    });
    FocusScope.of(context).unfocus();

    final destinationCoords = LatLng(lat, lng);
    final destinationName = description;

    final travelMode = _selectedTravelType == TravelType.walk
        ? TravelMode.walking
        : _selectedTravelType == TravelType.bike
            ? TravelMode.bicycling
            : TravelMode.transit;

    homeController.destination.value = destinationName;
    homeController.destinationCoordinates = destinationCoords;
    homeController.currentTravelMode.value = travelMode;
    homeController.mapStatus.value = Constants.route;
    speedController.setExpectedTravelMode(travelMode);

    await homeController.addDestinationMarker(destinationCoords);

    if (travelMode != TravelMode.transit) {
      homeController.setDestination(destinationName, destinationCoords,
          mode: travelMode);
      _updateGainAndRouteData();
    }
    homeController.update();
  }

  // --- TRANSIT SEARCH UTILS ---

  Future<void> _getOriginPlacePredictions(String input) async {
    _originPlacePredictionDebounce?.cancel();

    if (input.isEmpty || input.length < 3) {
      if (mounted) {
        setState(() {
          _originPlacePredictions = [];
        });
      }
      return;
    }

    _originPlacePredictionDebounce =
        Timer(const Duration(milliseconds: 500), () async {
      try {
        double lat = 48.8566;
        double lon = 2.3522;
        try {
          final pos = await homeController.getMyCurrentLocation();
          lat = pos.latitude;
          lon = pos.longitude;
        } catch (_) {
          // fallback vers Paris si géo indisponible
        }

        final url = Uri.parse(
            'https://photon.komoot.io/api/?q=${Uri.encodeComponent(input)}&limit=5&lat=$lat&lon=$lon');

        final response = await http.get(url, headers: {
          'User-Agent': 'WalkMoneyApp/1.0 (contact@walkmoney.com)'
        });

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final features = data['features'] as List<dynamic>;

          if (mounted) {
            setState(() {
              _originPlacePredictions = features.map<Map<String, dynamic>>((f) {
                final props = f['properties'] ?? {};
                final coords = f['geometry']?['coordinates'] ?? [0, 0];

                String name = (props['name'] as String?) ?? '';
                String city = (props['city'] as String?) ??
                    (props['town'] as String?) ??
                    (props['village'] as String?) ??
                    '';
                String display = name.isNotEmpty ? '$name, $city' : city;

                return {
                  'description': display.isNotEmpty ? display : 'Lieu inconnu',
                  'lat': coords.length >= 2 ? coords[1] : 0.0,
                  'lng': coords.length >= 2 ? coords[0] : 0.0,
                  'place_id': (props['osm_id']?.toString() ?? '')
                };
              }).toList(growable: false);
            });
          }
        }
      } catch (e) {
        debugPrint("Erreur d'autocomplétion Photon: $e");
      }
    });
  }

  void _selectOriginPlace(Map<String, dynamic> prediction) {
    FocusScope.of(context).unfocus();
    setState(() {
      _originCoords =
          LatLng(prediction['lat'] as double, prediction['lng'] as double);
      _originController.text = prediction['description'] as String;
      _originPlacePredictions = [];
    });
  }

  Future<void> _pickTransitDateTime() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _selectedTransitTime,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null) return;

    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedTransitTime),
    );
    if (time == null) return;

    setState(() {
      _selectedTransitTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  void _searchTransitRoute() async {
    if (homeController.destinationCoordinates.latitude == 0 &&
        homeController.destinationCoordinates.longitude == 0) {
      _showSnackBar("Veuillez d'abord sélectionner une destination.",
          backgroundColor: Colors.orange);
      return;
    }

    DateTime? departureTime;
    DateTime? arrivalTime;

    if (_transitTimeOption == TransitTimeOption.departAt) {
      departureTime = _selectedTransitTime;
    } else if (_transitTimeOption == TransitTimeOption.arriveBy) {
      arrivalTime = _selectedTransitTime;
    }

    setState(() {
      homeController.transitRouteOptions.clear();
    });

    await homeController.drawRoute(
      homeController.destinationCoordinates,
      origin: _originCoords,
      departureTime: departureTime,
      arrivalTime: arrivalTime,
    );
  }

  // --- BOOST & ADS ---

  bool _isWeatherBoostApplicable() {
    if (widget.weatherData == null) return false;
    final weather = widget.weatherData!;
    bool isBadWeather = weather.weatherCode >= 51 ||
        weather.weatherCode == 45 ||
        weather.weatherCode == 48;
    bool isWindy = weather.windSpeed > 30;
    bool isExtremeTempCold = weather.temperature < 2;
    bool isExtremeTempeHot = weather.temperature > 32;
    return isBadWeather || isWindy || isExtremeTempCold || isExtremeTempeHot;
  }

  Future<void> _watchAd() async {
    if (!mounted) return;
    if (widget.userProfile.adPoints >= 50) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Vous avez atteint le maximum de 50 Ad Points!"),
          backgroundColor: Colors.orange));
      return;
    }

    int oldAdPoints = widget.userProfile.adPoints;
    int newAdPoints = (oldAdPoints + 1).clamp(0, 50);
    bool justUnlockedBoost = oldAdPoints < 10 && newAdPoints >= 10;

    try {
      await _firestore.collection('users').doc(widget.userProfile.id).update({
        'ad_points': newAdPoints,
        'last_ad_point_decay_time': FieldValue.serverTimestamp(),
      });
      widget.onProfileModified();
      if (mounted) {
        if (justUnlockedBoost) {
          // Notification spéciale quand on atteint 10 ADP
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(
              children: const [
                Icon(Icons.bolt_rounded, color: Colors.amber),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "🎉 10 Ad Points atteints ! Multiplicateur x1.2 activé sur tous vos trajets !",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: accentGold,
            duration: const Duration(seconds: 5),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "+1 AD Point ! Vous en avez $newAdPoints/50.${newAdPoints < 10 ? ' (${10 - newAdPoints} avant le multiplicateur x1.2)' : ' ⚡ x1.2 actif !'}"),
            backgroundColor: primaryGreen,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    }
  }

  // --- HELPERS UI ---

  /// Lance le flux de validation ticket pour un magasin (appelé depuis la popup d'arrivée)
  void _triggerStoreValidation(EcoStore store) {
    // Trouver la StoreCard associée et déclencher la validation
    // On ouvre une BottomSheet avec la StoreCard en mode "déjà arrivé"
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StoreCard(
        store: store,
        onStartTrip: (s, t) => Navigator.pop(ctx),
        userPositionForCalcul: () async {
          final pos = await homeController.getMyCurrentLocation();
          return latlong.LatLng(pos.latitude, pos.longitude);
        },
        userProfile: widget.userProfile,
        onAddLame: widget.addLamePoints,
        weatherData: widget.weatherData,
        showValidateOnOpen: true, // Mode validation directe
      ),
    );
  }

  void _showSnackBar(String message,
      {Color backgroundColor = Colors.black87,
      Duration duration = const Duration(seconds: 3)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).removeCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        duration: duration,
      ),
    );
  }

  String _getMultiplierText() {
    List<String> activeBoosts = [];
    if (_isWeatherBoostApplicable()) {
      activeBoosts.add("Météo x1.5");
    }
    if (widget.userProfile.nextLevelBoost > 1.0) {
      activeBoosts.add(
          "Global x${widget.userProfile.nextLevelBoost.toStringAsFixed(2)}");
    }
    if (widget.userProfile.isVip) activeBoosts.add("VIP x1.15");
    if (widget.userProfile.adPoints >= 10) activeBoosts.add("AD x1.2");
    if (activeBoosts.isEmpty) return "";
    return activeBoosts.join(" / ");
  }

  bool _canCollectTodayReward() {
    final profile = widget.userProfile;
    if (profile.lastLoginDate == null) return false;

    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime lastLoginDay = DateTime(
        profile.lastLoginDate!.toDate().year,
        profile.lastLoginDate!.toDate().month,
        profile.lastLoginDate!.toDate().day);

    if (!DateUtils.isSameDay(lastLoginDay, today)) return false;
    if (profile.lastDailyRewardCollectedDate == null) return true;

    DateTime lastCollectionDay = DateTime(
        profile.lastDailyRewardCollectedDate!.toDate().year,
        profile.lastDailyRewardCollectedDate!.toDate().month,
        profile.lastDailyRewardCollectedDate!.toDate().day);
    return lastCollectionDay.isBefore(today);
  }

  // --- POPUPS DETAILS ---

  void _showLameCalculationDetails(BuildContext context) {
    int totalFinalGain = homeController.activeRouteEstimatedGain.value;
    double distKm = homeController.activeRouteRawDistanceMeters.value / 1000.0;
    double durMin = homeController.activeRouteRawDurationSeconds.value / 60.0;
    double elevationMeters = homeController.elevationGain.value;

    String modeLabel = "Marche";
    IconData modeIcon = Icons.directions_walk;

    if (_selectedTravelType == TravelType.bike) {
      modeLabel = "Vélo";
      modeIcon = Icons.directions_bike;
    } else if (_selectedTravelType == TravelType.transit) {
      modeLabel = "Transport";
      modeIcon = Icons.directions_bus;
    }

    double pointsDistance = 0;
    double pointsDuree = 0;
    double pointsDenivele = 0;

    if (_selectedTravelType == TravelType.walk) {
      pointsDistance = distKm * 10.0;
      pointsDuree = durMin * 0.5;
      pointsDenivele = elevationMeters / 3.0; // MAJ ICI
    } else if (_selectedTravelType == TravelType.bike) {
      pointsDistance = distKm * 6.0;
      pointsDuree = durMin * 0.2;
      pointsDenivele = elevationMeters / 5.0; // MAJ ICI
    } else if (_selectedTravelType == TravelType.transit) {
      pointsDistance = distKm * 5.0 * 0.8;
      pointsDuree = durMin * 0.5 * 0.8;
    }

    int baseEffortTotal =
        (pointsDistance + pointsDuree + pointsDenivele).round();
    if (_selectedTravelType == TravelType.transit) {
      baseEffortTotal = _calculatedBaseGain;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2))),
                ),
                Center(
                  child: Text("Détails de la Récompense",
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(
                              color: primaryGreen,
                              fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
                _buildSectionHeader("Effort Physique"),
                _buildDetailRowDialog(
                    "Distance réelle (${distKm.toStringAsFixed(1)} km) :",
                    "+${pointsDistance.round()} L",
                    valueColor: Colors.blueGrey),
                _buildDetailRowDialog(
                    "Temps estimé (${durMin.toStringAsFixed(0)} min) :",
                    "+${pointsDuree.round()} L",
                    valueColor: Colors.blueGrey),
                _buildDetailRowDialog(
                    "Dénivelé positif :", "+${pointsDenivele.round()} L",
                    valueColor: Colors.blueGrey),
                const Divider(),
                _buildDetailRowDialog(
                    "Sous-total Effort :", "$baseEffortTotal Lames",
                    valueColor: primaryGreen, isBold: true),
                const SizedBox(height: 20),
                _buildSectionHeader("Vos Bonus Actifs (Multiplicateurs)"),
                _buildDetailRowDialog("Météo Difficile :",
                    _isWeatherBoostApplicable() ? "x1.5" : "Aucun",
                    valueColor: _isWeatherBoostApplicable()
                        ? Colors.green
                        : Colors.grey,
                    icon: Icons.cloud),
                _buildDetailRowDialog(
                    "Série Connexion :",
                    widget.userProfile.nextLevelBoost > 1.0
                        ? "x${widget.userProfile.nextLevelBoost.toStringAsFixed(2)}"
                        : "Aucun",
                    valueColor: widget.userProfile.nextLevelBoost > 1.0
                        ? Colors.orange
                        : Colors.grey,
                    icon: Icons.local_fire_department),
                _buildDetailRowDialog("Membre VIP :",
                    widget.userProfile.isVip ? "x1.15" : "Aucun",
                    valueColor:
                        widget.userProfile.isVip ? accentGold : Colors.grey,
                    icon: Icons.star),
                _buildDetailRowDialog("Boost Soutien :",
                    widget.userProfile.adPoints >= 10 ? "x1.2" : "Aucun",
                    valueColor: widget.userProfile.adPoints >= 10
                        ? Colors.purple
                        : Colors.grey,
                    icon: Icons.bolt),
                const Divider(height: 30),
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("GAIN TOTAL ESTIMÉ",
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      Text("+$totalFinalGain Lames",
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryGreen)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTransitLameCalculationDetails(
      BuildContext context, Map<String, dynamic> leg) {
    int baseEffortTotal = _calculateGainForTransitOption(leg, isBaseOnly: true);
    if (baseEffortTotal == 0) return;

    int totalFinalGain = _calculateGainForTransitOption(leg);

    double durationMinutes = 0.0;
    if (leg['duration'] != null && leg['duration']['value'] != null) {
      durationMinutes = (leg['duration']['value'] as num).toDouble() / 60.0;
    }

    int transitCount = 0;
    final List<dynamic> steps = leg['steps'] as List<dynamic>? ?? [];
    for (var stepData in steps) {
      final step = stepData as Map<String, dynamic>;
      if (step['travel_mode'] == 'TRANSIT') {
        transitCount++;
      }
    }

    double pointsDuree = durationMinutes * 0.5;
    double pointsTransit = transitCount * 5.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2))),
                    ),
                    Center(
                      child: Text("Détails de la Récompense",
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                  color: primaryGreen,
                                  fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 20),
                    _buildSectionHeader("Effort Transport"),
                    _buildDetailRowDialog(
                        "Temps estimé (${durationMinutes.toStringAsFixed(0)} min) :",
                        "+${pointsDuree.round()} L",
                        valueColor: Colors.blueGrey),
                    _buildDetailRowDialog("Correspondances ($transitCount) :",
                        "+${pointsTransit.round()} L",
                        valueColor: Colors.blueGrey,
                        icon: Icons.directions_bus),
                    const Divider(),
                    _buildDetailRowDialog(
                        "Sous-total Effort :", "$baseEffortTotal Lames",
                        valueColor: primaryGreen, isBold: true),
                    const SizedBox(height: 20),
                    _buildSectionHeader("Vos Bonus Actifs (Multiplicateurs)"),
                    _buildDetailRowDialog("Météo Difficile :",
                        _isWeatherBoostApplicable() ? "x1.5" : "Aucun",
                        valueColor: _isWeatherBoostApplicable()
                            ? Colors.green
                            : Colors.grey,
                        icon: Icons.cloud),
                    _buildDetailRowDialog(
                        "Série Connexion :",
                        widget.userProfile.nextLevelBoost > 1.0
                            ? "x${widget.userProfile.nextLevelBoost.toStringAsFixed(2)}"
                            : "Aucun",
                        valueColor: widget.userProfile.nextLevelBoost > 1.0
                            ? Colors.orange
                            : Colors.grey,
                        icon: Icons.local_fire_department),
                    _buildDetailRowDialog("Membre VIP :",
                        widget.userProfile.isVip ? "x1.15" : "Aucun",
                        valueColor:
                            widget.userProfile.isVip ? accentGold : Colors.grey,
                        icon: Icons.star),
                    _buildDetailRowDialog("Boost Soutien :",
                        widget.userProfile.adPoints >= 10 ? "x1.2" : "Aucun",
                        valueColor: widget.userProfile.adPoints >= 10
                            ? Colors.purple
                            : Colors.grey,
                        icon: Icons.bolt),
                    const Divider(height: 30),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                          color: primaryGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(15)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("GAIN TOTAL ESTIMÉ",
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87)),
                          Text("+$totalFinalGain Lames",
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: primaryGreen)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showAdPointsDetailsDialog(BuildContext context) {
    final profile = widget.userProfile;
    DateTime now = DateTime.now();

    int adPoints = profile.adPoints;
    int pointsLoss = _calculateAdPointLoss(adPoints);

    String nextDecayTime = "N/A";
    if (profile.adPoints > 0) {
      Timestamp lastDecayTime = profile.lastAdPointDecayTime ??
          Timestamp.fromDate(now.subtract(const Duration(hours: 5)));
      Duration timeSinceLastDecay = now.difference(lastDecayTime.toDate());
      Duration timeUntilNextDecay =
          const Duration(hours: 5) - timeSinceLastDecay;

      if (timeUntilNextDecay.isNegative) {
        nextDecayTime = "Perte dans les prochaines minutes";
      } else {
        nextDecayTime =
            "${timeUntilNextDecay.inHours}h ${timeUntilNextDecay.inMinutes.remainder(60)}m";
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (BuildContext sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Container(
              padding: EdgeInsets.fromLTRB(20, 0, 20,
                  MediaQuery.of(sheetContext).viewInsets.bottom + 20),
              child: SingleChildScrollView(
                controller: scrollController,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                          child: Text("📺 Vos Ad Points 📺",
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: primaryGreen))),
                      const SizedBox(height: 16),

                      // Indicateur multiplicateur
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: profile.adPoints >= 10
                              ? accentGold.withOpacity(0.15)
                              : Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: profile.adPoints >= 10
                                ? accentGold
                                : Colors.grey[300]!,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.bolt_rounded,
                              color: profile.adPoints >= 10
                                  ? accentGold
                                  : Colors.grey,
                              size: 28,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    profile.adPoints >= 10
                                        ? "Multiplicateur x1.2 ACTIF !"
                                        : "Multiplicateur x1.2 inactif",
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: profile.adPoints >= 10
                                          ? accentGold
                                          : Colors.grey,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (profile.adPoints < 10)
                                    Text(
                                      "Encore ${10 - profile.adPoints} ADP pour activer",
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.grey),
                                    )
                                  else
                                    const Text(
                                      "+20% sur tous vos gains de trajet",
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.grey),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (profile.adPoints < 10) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: profile.adPoints / 10.0,
                            minHeight: 6,
                            backgroundColor: Colors.grey[300],
                            valueColor:
                                const AlwaysStoppedAnimation<Color>(accentGold),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${profile.adPoints}/10 ADP",
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 12),
                      _buildDetailRowDialog(
                          "Ad Points actuels:", "${profile.adPoints}/50 ADP",
                          icon: Icons.slow_motion_video_rounded),
                      if (profile.adPoints > 0)
                        _buildDetailRowDialog(
                            "Prochaine perte (-$pointsLoss ADP):",
                            nextDecayTime,
                            icon: Icons.timer_outlined,
                            valueColor: Colors.orange[700]),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),
                      const Text("💡 Règles des Ad Points :",
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: textDark)),
                      const SizedBox(height: 8),
                      const Text("• Regardez une pub = +1 Ad Point (max 50)",
                          style: TextStyle(fontSize: 13, color: textGrey)),
                      const Text("• ≥ 10 ADP = multiplicateur x1.2 automatique",
                          style: TextStyle(
                              fontSize: 13,
                              color: accentGold,
                              fontWeight: FontWeight.w500)),
                      const SizedBox(height: 4),
                      const Text("• Perte toutes les 5h :",
                          style: TextStyle(
                              fontSize: 13,
                              color: textGrey,
                              fontWeight: FontWeight.bold)),
                      const Text("  - 0-9 : -1 pt   |   10-19 : -2 pts",
                          style: TextStyle(fontSize: 12, color: textGrey)),
                      const Text(
                          "  - 20-29 : -3 pts   |   30-39 : -4 pts   |   40+ : -5 pts",
                          style: TextStyle(fontSize: 12, color: textGrey)),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.slow_motion_video_rounded),
                          label: const Text("Regarder une Pub"),
                          onPressed: profile.adPoints < 50
                              ? () {
                                  Navigator.of(sheetContext).pop();
                                  _watchAd();
                                }
                              : null,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                          child: TextButton(
                              child: const Text("Fermer"),
                              onPressed: () =>
                                  Navigator.of(sheetContext).pop()))
                    ]),
              ),
            );
          },
        );
      },
    );
  }

  int _calculateAdPointLoss(int currentPoints) {
    if (currentPoints < 10) return 1;
    if (currentPoints < 20) return 2;
    if (currentPoints < 30) return 3;
    if (currentPoints < 40) return 4;
    return 5;
  }

  void _showLoginStreakDetailsDialog(BuildContext context) {
    final profile = widget.userProfile;

    // Calculs pour l'affichage (inchangés)
    int paliersActuels =
        (profile.consecutiveLogins / LOGIN_STREAK_DAYS_PER_PALIER).floor();
    double bonusSerieInclusDansNextLevelBoost =
        (paliersActuels * LOGIN_STREAK_BONUS_PER_PALIER)
            .clamp(0.0, MAX_LOGIN_STREAK_BONUS_TOTAL);
    int joursRestantsProchainPalier = 0;
    double progressionProchainPalier = 0.0;
    int prochainPalierEnJours = 0;
    double bonusDuProchainPalierReel = 0.0;
    bool maxBonusAtteintViaPaliers =
        bonusSerieInclusDansNextLevelBoost >= MAX_LOGIN_STREAK_BONUS_TOTAL &&
            MAX_LOGIN_STREAK_BONUS_TOTAL > 0;

    if (profile.consecutiveLogins == 0) {
      progressionProchainPalier = 0.0;
      joursRestantsProchainPalier = LOGIN_STREAK_DAYS_PER_PALIER;
      prochainPalierEnJours = LOGIN_STREAK_DAYS_PER_PALIER;
      bonusDuProchainPalierReel = LOGIN_STREAK_BONUS_PER_PALIER;
    } else if (!maxBonusAtteintViaPaliers) {
      int joursDepuisDernierPalierOuDebut =
          profile.consecutiveLogins % LOGIN_STREAK_DAYS_PER_PALIER;
      if (joursDepuisDernierPalierOuDebut == 0 &&
          profile.consecutiveLogins > 0) {
        progressionProchainPalier = 1.0;
        joursRestantsProchainPalier = LOGIN_STREAK_DAYS_PER_PALIER;
        prochainPalierEnJours =
            profile.consecutiveLogins + LOGIN_STREAK_DAYS_PER_PALIER;
      } else {
        progressionProchainPalier = joursDepuisDernierPalierOuDebut /
            LOGIN_STREAK_DAYS_PER_PALIER.toDouble();
        joursRestantsProchainPalier =
            LOGIN_STREAK_DAYS_PER_PALIER - joursDepuisDernierPalierOuDebut;
        prochainPalierEnJours =
            ((profile.consecutiveLogins / LOGIN_STREAK_DAYS_PER_PALIER)
                        .floor() +
                    1) *
                LOGIN_STREAK_DAYS_PER_PALIER;
      }
      bonusDuProchainPalierReel =
          ((prochainPalierEnJours / LOGIN_STREAK_DAYS_PER_PALIER).floor() *
                  LOGIN_STREAK_BONUS_PER_PALIER)
              .clamp(0.0, MAX_LOGIN_STREAK_BONUS_TOTAL);
    } else {
      progressionProchainPalier = 1.0;
      prochainPalierEnJours = profile.consecutiveLogins;
      joursRestantsProchainPalier = 0;
    }

    // Génération des widgets de paliers
    List<Widget> paliersWidgets = [];
    int maxPaliersPourAffichage = (MAX_LOGIN_STREAK_BONUS_TOTAL /
            (LOGIN_STREAK_BONUS_PER_PALIER > 0
                ? LOGIN_STREAK_BONUS_PER_PALIER
                : 1))
        .ceil();
    if (maxPaliersPourAffichage == 0 && MAX_LOGIN_STREAK_BONUS_TOTAL > 0)
      maxPaliersPourAffichage = 1;
    if (LOGIN_STREAK_DAYS_PER_PALIER == 0) maxPaliersPourAffichage = 1;

    for (int i = 1; i <= maxPaliersPourAffichage; i++) {
      if (LOGIN_STREAK_DAYS_PER_PALIER == 0 && i > 1) break;
      int joursPalier = i * LOGIN_STREAK_DAYS_PER_PALIER;
      double bonusPalierTotal = (i * LOGIN_STREAK_BONUS_PER_PALIER)
          .clamp(0.0, MAX_LOGIN_STREAK_BONUS_TOTAL);
      bool estAtteint = profile.consecutiveLogins >= joursPalier;
      bool estProchainNonAtteint = !maxBonusAtteintViaPaliers &&
          (prochainPalierEnJours == joursPalier &&
              profile.consecutiveLogins < joursPalier);

      paliersWidgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.0),
        child: Row(
          children: [
            Icon(
                estAtteint
                    ? Icons.check_circle_rounded
                    : (estProchainNonAtteint
                        ? Icons.flag_rounded
                        : Icons.radio_button_unchecked_rounded),
                color: estAtteint
                    ? primaryGreen
                    : (estProchainNonAtteint
                        ? accentGold
                        : textGrey.withOpacity(0.7)),
                size: 18),
            const SizedBox(width: 8),
            Text("$joursPalier jours : ",
                style: const TextStyle(
                    fontWeight: FontWeight.normal, fontSize: 13)),
            Text(
                "Multiplicateur Global +${bonusPalierTotal.toStringAsFixed(2)}",
                style: TextStyle(
                    color: estAtteint
                        ? primaryGreen
                        : (estProchainNonAtteint ? accentGold : textGrey),
                    fontWeight: estAtteint || estProchainNonAtteint
                        ? FontWeight.bold
                        : FontWeight.normal,
                    fontSize: 13)),
          ],
        ),
      ));
      if (bonusPalierTotal >= MAX_LOGIN_STREAK_BONUS_TOTAL &&
          MAX_LOGIN_STREAK_BONUS_TOTAL > 0) break;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white, // CORRIGÉ: Fond blanc pour voir la barre
      showDragHandle: true, // CORRIGÉ: Affichage de la petite barre
      builder: (BuildContext sheetContext) {
        bool _isClaimingReward = false;
        bool _hasClaimedLocally = false;

        // CORRIGÉ : Ajout du DraggableScrollableSheet pour lier le slide à la fermeture
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                bool canCollect = !_isClaimingReward &&
                    _canCollectTodayReward() &&
                    !_hasClaimedLocally;

                return Container(
                  padding: EdgeInsets.fromLTRB(20, 0, 20,
                      MediaQuery.of(sheetContext).viewInsets.bottom + 20),
                  child: SingleChildScrollView(
                    controller:
                        scrollController, // CORRIGÉ: Lier le scroll au glissement de la fenêtre
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                              child: Text("🔥 Votre Série de Connexion 🔥",
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                          color: Colors.orangeAccent[700]))),
                          const SizedBox(height: 16),
                          _buildDetailRowDialog("Série Actuelle:",
                              "${profile.consecutiveLogins} jours",
                              icon: Icons.calendar_today_rounded),
                          _buildDetailRowDialog(
                              "Multiplicateur Global Actuel (Série):",
                              "x${(profile.nextLevelBoost).toStringAsFixed(2)}",
                              icon: Icons.star_rate_rounded,
                              valueColor: primaryGreen),
                          const SizedBox(height: 12),
                          const Divider(),
                          const SizedBox(height: 12),
                          Text(
                              maxBonusAtteintViaPaliers &&
                                      profile.consecutiveLogins >=
                                          (maxPaliersPourAffichage *
                                              (LOGIN_STREAK_DAYS_PER_PALIER > 0
                                                  ? LOGIN_STREAK_DAYS_PER_PALIER
                                                  : 1)) &&
                                      LOGIN_STREAK_DAYS_PER_PALIER > 0
                                  ? "🎉 Bonus de série maximum atteint ! Maintenez votre série !"
                                  : (profile.consecutiveLogins == 0
                                      ? "Connectez-vous demain pour démarrer votre série !"
                                      : (joursRestantsProchainPalier > 0 &&
                                              LOGIN_STREAK_DAYS_PER_PALIER >
                                                  0 &&
                                              !maxBonusAtteintViaPaliers
                                          ? "Prochain palier dans $joursRestantsProchainPalier jour(s) :"
                                          : "Nouveau palier atteint ou série en cours !")),
                              style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: textDark)),
                          if (profile.consecutiveLogins > 0 &&
                              !maxBonusAtteintViaPaliers &&
                              LOGIN_STREAK_DAYS_PER_PALIER > 0) ...[
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: LinearProgressIndicator(
                                  value: progressionProchainPalier,
                                  backgroundColor:
                                      defisProgressEmpty.withOpacity(0.5),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                          accentGold),
                                  minHeight: 10),
                            ),
                            const SizedBox(height: 4),
                            if (joursRestantsProchainPalier > 0 &&
                                prochainPalierEnJours > 0)
                              Center(
                                  child: Text(
                                      "$prochainPalierEnJours jours > Multiplicateur Global x${(1.0 + bonusDuProchainPalierReel).toStringAsFixed(2)}",
                                      style: const TextStyle(
                                          fontSize: 12, color: textGrey))),
                          ],
                          const SizedBox(height: 16),
                          Text("Paliers de Multiplicateur Global (Série):",
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5),
                          ...paliersWidgets,
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            icon: Icon(canCollect
                                ? Icons.card_giftcard_rounded
                                : Icons.check_circle_outline_rounded),
                            label: Text(canCollect
                                ? "Récupérer Récompense du Jour (+1 Lame)"
                                : "Récompense du Jour Récupérée"),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 45),
                              backgroundColor:
                                  canCollect ? primaryGreen : Colors.grey[400],
                            ),
                            onPressed: canCollect
                                ? () async {
                                    setDialogState(() {
                                      _isClaimingReward = true;
                                      _hasClaimedLocally = true;
                                    });
                                    try {
                                      WriteBatch batch = _firestore.batch();
                                      DocumentReference userRef = _firestore
                                          .collection('users')
                                          .doc(widget.userProfile.id);
                                      batch.update(userRef, {
                                        'lame_points': FieldValue.increment(1),
                                        'total_lame_earned':
                                            FieldValue.increment(1),
                                        'last_daily_reward_collected_date':
                                            Timestamp.now(),
                                        'updated_at':
                                            FieldValue.serverTimestamp()
                                      });

                                      DocumentReference historyRef = userRef
                                          .collection('lame_history')
                                          .doc();
                                      batch.set(historyRef, {
                                        'amount': 1,
                                        'source': 'Récompense Quotidienne',
                                        'timestamp':
                                            FieldValue.serverTimestamp(),
                                      });

                                      await batch.commit();

                                      widget.onProfileModified();
                                      setDialogState(() {
                                        _isClaimingReward = false;
                                      });
                                      _showSnackBar(
                                          "Récompense récupérée (+1 Lame)!",
                                          backgroundColor: primaryGreen);
                                    } catch (e) {
                                      setDialogState(() {
                                        _isClaimingReward = false;
                                        _hasClaimedLocally = false;
                                      });
                                      _showSnackBar("Erreur: $e",
                                          backgroundColor: Colors.red);
                                    }
                                  }
                                : null,
                          ),
                          const SizedBox(height: 10),
                          Center(
                              child: TextButton(
                                  child: const Text("Fermer"),
                                  onPressed: () =>
                                      Navigator.of(sheetContext).pop()))
                        ]),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
  // --- WIDGET BUILDING ---

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(110.0),
        child: Obx(() {
          if (!mounted) return const SizedBox.shrink();
          return Visibility(
            visible: homeController.mapStatus.value != Constants.onDestination,
            child: _buildUpperControlsBar(),
          );
        }),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
              minWidth: constraints.maxWidth,
            ),
            child: IntrinsicHeight(
              child: Stack(
                children: [
                  // --- CARTE ---
                  Obx(() {
                    bool isNavigating = homeController.mapStatus.value ==
                        Constants.onDestination;
                    bool isShowingRoute =
                        homeController.mapStatus.value == Constants.route;
                    double offset = (isNavigating || isShowingRoute)
                        ? screenHeight * 0.35
                        : 0;

                    return Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      bottom: -offset,
                      child: SizedBox(
                        height: screenHeight + offset,
                        child: MapPage(
                          onValidatePurchase: (store) async {
                            showDialog(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text("Valider l'achat"),
                                content: Text(
                                    "Pour valider votre achat chez ${store.name}, veuillez aller dans l'onglet 'Magasins'."),
                                actions: [
                                  TextButton(
                                      child: const Text("OK"),
                                      onPressed: () => Navigator.of(ctx).pop())
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }),

                  // --- BOUTON LOCALISATION (IDLE) ---
                  Obx(() => Visibility(
                        visible:
                            homeController.mapStatus.value == Constants.idle,
                        child: Positioned(
                          bottom: 30,
                          right: 20,
                          child: FloatingActionButton(
                            heroTag: "btn_locate_me",
                            onPressed: () async {
                              try {
                                Position position =
                                    await homeController.getMyCurrentLocation();
                                await homeController.moveMapCamera(LatLng(
                                    position.latitude, position.longitude));
                              } catch (e) {
                                _showSnackBar(
                                    "Impossible d'obtenir votre position: $e",
                                    backgroundColor: Colors.red);
                              }
                            },
                            backgroundColor: Colors.white,
                            child:
                                Image.asset(Constants.locateMeIcon, scale: 4),
                          ),
                        ),
                      )),

                  // --- BOUTON RECENTRER (NAVIGATION) ---
                  Obx(() {
                    final isNavigating = homeController.mapStatus.value ==
                        Constants.onDestination;
                    final isCameraUnlocked =
                        !homeController.isNavigationCameraLocked.value;
                    return Visibility(
                      visible: isNavigating && isCameraUnlocked,
                      child: Positioned(
                        bottom: 100,
                        right: 20,
                        child: FloatingActionButton(
                          heroTag: "btn_recenter_nav",
                          tooltip: 'Recentrer la navigation',
                          backgroundColor: Colors.white,
                          child: const Icon(Icons.center_focus_strong,
                              color: Colors.blueAccent),
                          onPressed: () {
                            homeController.recenterMap();
                          },
                        ),
                      ),
                    );
                  }),

                  // --- UI OVERLAYS ---
                  SpeedometerDisplay(),

                  // --- INSTRUCTIONS NAVIGATION ---
                  Obx(() => Visibility(
                        visible: homeController.mapStatus.value ==
                            Constants.onDestination,
                        child: Positioned(
                          top: MediaQuery.of(context).padding.top + 10,
                          left: 15,
                          right: 15,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const InstructionHeader(), // C'est lui qui affichera la direction et la rue !
                              const TransitStatusWidget(),
                              const SizedBox(height: 8),
                              DirectionsStatusBar(onValidatePurchase: () async {
                                Get.snackbar("Action requise",
                                    "Veuillez retourner à l'onglet 'Magasins'.",
                                    snackPosition: SnackPosition.BOTTOM,
                                    backgroundColor: Colors.blueAccent,
                                    colorText: Colors.white);
                                navigationController.stopNavigation();
                              }),
                            ],
                          ),
                        ),
                      )),

                  // --- MINI-WIDGET MINUTEUR DÉFI ---
                  Obx(() {
                    if (!navigationController.isStayTimerActive.value)
                      return const SizedBox.shrink();

                    int mins =
                        navigationController.staySecondsRemaining.value ~/ 60;
                    int secs =
                        navigationController.staySecondsRemaining.value % 60;
                    bool inZone = navigationController.isUserInStayZone.value;

                    return Positioned(
                        top: _upperControlsBarHeight + 20,
                        left: 20,
                        right: 20,
                        child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                                color: inZone
                                    ? Colors.green.shade800
                                    : Colors.orange.shade800,
                                borderRadius: BorderRadius.circular(15),
                                boxShadow: const [
                                  BoxShadow(
                                      color: Colors.black26, blurRadius: 8)
                                ],
                                border: Border.all(
                                    color: Colors.white, width: 1.5)),
                            child: Row(children: [
                              Icon(inZone ? Icons.timer : Icons.location_off,
                                  color: Colors.white),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  inZone
                                      ? "Restez sur place : $mins:${secs.toString().padLeft(2, '0')}"
                                      : "⚠️ Revenez dans la zone !",
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white70, size: 20),
                                constraints: const BoxConstraints(),
                                padding: EdgeInsets.zero,
                                onPressed: () => navigationController
                                    .stopIndependentStayTimer(),
                              )
                            ])));
                  }),

                  // ── BOUTON STOP + TOGGLE POINTS GPS (pendant navigation) ──
                  Obx(() {
                    if (homeController.mapStatus.value !=
                        Constants.onDestination) {
                      return const SizedBox.shrink();
                    }
                    final showPoints =
                        homeController.showDiagnosticPoints.value;
                    return Positioned(
                      bottom: 80,
                      left: 20,
                      right: 20,
                      child: Row(
                        children: [
                          // ── BOUTON TOGGLE POINTS GPS ──
                          Expanded(
                            flex: 2,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: showPoints
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade700,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 14, horizontal: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 4,
                              ),
                              icon: Icon(
                                showPoints
                                    ? Icons.visibility
                                    : Icons.visibility_off,
                                color: Colors.white,
                                size: 20,
                              ),
                              label: Text(
                                showPoints ? "Points GPS" : "Points masqués",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () {
                                homeController.toggleDiagnosticPoints();
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          // ── BOUTON STOP NAVIGATION ──
                          Expanded(
                            flex: 3,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 4,
                              ),
                              child: const Text(
                                "STOP NAVIGATION",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              onPressed: () =>
                                  navigationController.stopNavigation(),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),

                  // --- BARRE DU BAS (Info Route) ---
                  Obx(() => Visibility(
                        visible:
                            homeController.mapStatus.value != Constants.idle,
                        child: const Positioned(
                            bottom: 0, left: 0, right: 0, child: BottomBar()),
                      )),

                  // --- SHEET PRINCIPAL ---
                  Obx(() => Visibility(
                        visible: homeController.mapStatus.value !=
                            Constants.onDestination,
                        child: Positioned.fill(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: _buildDraggableSheet(),
                          ),
                        ),
                      )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // --- WIDGET CONSTRUCTION ---

  Widget _buildUpperControlsBar() {
    return Material(
      key: _upperControlsBarKey,
      color: Theme.of(context).canvasColor,
      elevation: 2.0,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 5),
              _buildTopInfoChipsRow(),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopInfoChipsRow() {
    return Container(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          GestureDetector(
            onTap: widget.onShowLameHistory,
            child: _customChip(
              label: '${widget.userProfile.lamePoints} L',
              backgroundColor: const Color(0xFF8FBC8F),
              textColor: Colors.black,
              icon: Icons.eco_rounded,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: widget.onProfileButtonPressed,
            child: _customChip(
              label: 'niv ${widget.userProfile.currentLevel}',
              backgroundColor: Colors.white,
              textColor: Colors.black,
              trailing: CircleAvatar(
                radius: 10,
                backgroundColor: primaryGreen,
                child: Text(
                  widget.userProfile.username.isNotEmpty
                      ? widget.userProfile.username[0].toUpperCase()
                      : 'U',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _buildAdMinimalistIndicator(),
          const SizedBox(width: 8),
          _buildLoginStreakIndicator(),
        ],
      ),
    );
  }

  Widget _customChip(
      {required String label,
      required Color backgroundColor,
      required Color textColor,
      IconData? icon,
      Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: Chip(
        avatar: icon != null ? Icon(icon, color: textColor, size: 14) : null,
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: textColor, fontSize: 11)),
          if (trailing != null) ...[const SizedBox(width: 3), trailing],
        ]),
        backgroundColor: backgroundColor.withOpacity(0.9),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildDraggableSheet() {
    double initialSheetSize = 0.28;
    double minSheetSize = 0.28;
    double maxSheetSize = 0.90;

    if (homeController.destination.value.isNotEmpty) {
      minSheetSize = 0.40;
      initialSheetSize = 0.42;
    }

    return DraggableScrollableSheet(
      initialChildSize: initialSheetSize,
      minChildSize: minSheetSize,
      maxChildSize: maxSheetSize,
      snap: true,
      snapSizes: [minSheetSize, 0.5, 0.75, maxSheetSize],
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
            boxShadow: [
              BoxShadow(
                  blurRadius: 10.0,
                  color: Colors.black12,
                  offset: Offset(0, -2))
            ],
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            physics: const ClampingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height * minSheetSize,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.0, 20.0, 16.0,
                    MediaQuery.of(context).viewInsets.bottom + 16.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    // Contenu principal
                    ..._buildTrajetContentDraggablePart(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildTrajetContentDraggablePart() {
    return [
      Obx(() {
        bool hasDestination = homeController.destination.value.isNotEmpty;
        bool isTransit = _selectedTravelType == TravelType.transit;
        bool isSearching = homeController.gettingRoute.value;
        bool showRouteSummary =
            homeController.mapStatus.value == Constants.route &&
                !isSearching &&
                (!isTransit || !homeController.showTransitOptions.value);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchInputWithClear(),
            const SizedBox(height: 10),
            if (_placePredictions.isNotEmpty)
              _buildPredictionsList(
                  _placePredictions, (prediction) => _selectPlace(prediction))
            else ...[
              _buildTravelTypeToggle(),
              const Divider(height: 20),
              if (!hasDestination) ...[
                _buildWeatherSection(),
                const SizedBox(height: 10),
                _buildFavoriteRoutesSection(),
                const SizedBox(height: 10),
                _buildSuggestedStoresSection(),
              ] else if (showRouteSummary) ...[
                _buildRouteSummaryUI(),
                const SizedBox(height: 15),
                const Padding(
                  padding: EdgeInsets.only(left: 4.0, bottom: 4.0),
                  child: Text("Conditions sur le trajet :",
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          fontSize: 12)),
                ),
                _buildWeatherSection(),
              ] else if (isTransit &&
                  homeController.showTransitOptions.value) ...[
                _buildAdvancedTransitOptionsUI(),
                const SizedBox(height: 10),
                _buildWeatherSection(),
              ] else if (isSearching)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(
                            color: Color(0xFF388E3C))))
              else
                const SizedBox.shrink(),
            ],
          ],
        );
      }),
    ];
  }

  Widget _buildSearchInputWithClear() {
    return TextField(
      controller: _destinationController,
      onSubmitted: (value) {
        if (value.isNotEmpty) {
          _calculateAndSetDestination();
          FocusScope.of(context).unfocus();
        }
      },
      onChanged: (val) {
        if (val.length > 2) {
          _getPlacePredictions(val);
        } else {
          setState(() => _placePredictions = []);
        }
      },
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: "Où allez-vous ?",
        prefixIcon: const Icon(Icons.search, color: primaryGreen),
        suffixIcon: _destinationController.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.grey),
                onPressed: () {
                  setState(() {
                    _destinationController.clear();
                    _placePredictions = [];
                  });
                  homeController.clearDestination();
                },
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: Colors.grey[100],
      ),
    );
  }

  Widget _buildTravelTypeToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(
            child: _travelTypeIcon(Icons.directions_walk_rounded,
                TravelType.walk, _selectedTravelType == TravelType.walk),
          ),
          Container(
            width: 1.5,
            height: 25,
            color: Colors.grey[300],
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          Expanded(
            child: _travelTypeIcon(Icons.directions_bike_rounded,
                TravelType.bike, _selectedTravelType == TravelType.bike),
          ),
          Container(
            width: 1.5,
            height: 25,
            color: Colors.grey[300],
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          Expanded(
            child: _travelTypeIcon(Icons.directions_bus_rounded,
                TravelType.transit, _selectedTravelType == TravelType.transit),
          ),
        ],
      ),
    );
  }

  Widget _travelTypeIcon(IconData icon, TravelType type, bool isSelected) {
    return InkWell(
      onTap: () async {
        if (homeController.mapStatus.value == Constants.onDestination) return;
        if (_activeChallenge != null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text("Vous ne pouvez pas changer de mode pendant un défi.")));
          return;
        }
        if (_selectedTravelType == type) return;

        setState(() {
          _selectedTravelType = type;
        });

        TravelMode newTravelMode;
        switch (type) {
          case TravelType.walk:
            newTravelMode = TravelMode.walking;
            break;
          case TravelType.bike:
            newTravelMode = TravelMode.bicycling;
            break;
          case TravelType.transit:
            newTravelMode = TravelMode.transit;
            break;
          default:
            newTravelMode = TravelMode.walking;
        }

        homeController.currentTravelMode.value = newTravelMode;
        speedController.setExpectedTravelMode(newTravelMode);

        if (homeController.destination.value.isNotEmpty) {
          homeController.polyline.clear();
          homeController.polylineCoordinates.clear();
          homeController.gettingRoute.value = true;

          if (newTravelMode == TravelMode.transit) {
            homeController.showTransitOptions.value = true;
          } else {
            homeController.showTransitOptions.value = false;
          }

          await homeController.drawRoute(homeController.destinationCoordinates);
          _updateGainAndRouteData();
        }
      },
      borderRadius: BorderRadius.circular(25),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color:
              isSelected ? primaryGreen.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color:
                isSelected ? primaryGreen.withOpacity(0.3) : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                color: isSelected ? textDark : Colors.grey[500], size: 30),
            const SizedBox(height: 4),
            Text(
              type == TravelType.walk
                  ? "Pied"
                  : type == TravelType.bike
                      ? "Vélo"
                      : "Transit",
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? textDark : Colors.grey[500],
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestedStoresSection() {
    if (_dailySuggestedStores.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          child: Text("Suggestions du jour",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _dailySuggestedStores.length + 1,
            itemBuilder: (context, index) {
              if (index == _dailySuggestedStores.length) {
                return Container(
                  width: 100,
                  margin: const EdgeInsets.only(right: 10),
                  child: Card(
                    color: Colors.grey[100],
                    child: InkWell(
                      onTap: () {
                        widget.onShowStoresTab();
                      },
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.storefront, color: primaryGreen),
                            Text("Voir plus",
                                style: TextStyle(
                                    color: primaryGreen,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }

              final store = _dailySuggestedStores[index];
              bool isGold = store.isVisibilityBoostEnabled;

              return Container(
                width: 200,
                margin: const EdgeInsets.only(right: 10),
                child: Card(
                  elevation: isGold ? 4 : 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: isGold
                          ? const BorderSide(color: Colors.amber, width: 2)
                          : BorderSide.none),
                  child: InkWell(
                    onTap: () =>
                        widget.onStartStoreTrip(store, _selectedTravelType),
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                  child: Text(store.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis)),
                              if (isGold)
                                const Icon(Icons.star,
                                    color: Colors.amber, size: 16),
                            ],
                          ),
                          Text(store.address,
                              style: const TextStyle(
                                  fontSize: 10, color: Colors.grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const Spacer(),
                          Text("+${store.cashbackRate * 100}% Cashback",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isGold
                                      ? Colors.amber[800]
                                      : Colors.green)),
                          const SizedBox(height: 5),
                          SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          isGold ? Colors.amber : primaryGreen,
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero),
                                  onPressed: () => widget.onStartStoreTrip(
                                      store, _selectedTravelType),
                                  child: const Text("Y aller",
                                      style: TextStyle(fontSize: 12))))
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildRouteSummaryUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildRouteSummary(),
        _buildTravelModeDetails(),
        const SizedBox(height: 10),
        if (_selectedTravelType == TravelType.transit)
          Padding(
            padding: const EdgeInsets.only(bottom: 10.0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back, size: 18),
                label: const Text("Choisir un autre itinéraire"),
                onPressed: () {
                  homeController.showTransitOptions.value = true;
                },
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    side: BorderSide(color: Colors.grey[400]!),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
              ),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildGainCircle(),
            ElevatedButton(
              onPressed: () {
                navigationController.setActiveUserProfile(widget.userProfile);
                navigationController.navigateToDestination(
                    validateWalkingLegs: _validateWalkingLegs);
              },
              style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text("Commencer le trajet"),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteSummary() {
    return Obx(
        () => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(homeController.timeLeft.value,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(width: 8),
                Text("(${homeController.distanceLeft.value})",
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: Colors.grey[700])),
              ]),
              Text(
                homeController.destination.value.isNotEmpty
                    ? "Vers ${homeController.destination.value}"
                    : "Aucune destination",
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.grey[700]),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Divider(color: Colors.grey[300]),
              const SizedBox(height: 6)
            ]));
  }

  Widget _buildTravelModeDetails() {
    IconData icon;
    String text;
    switch (_selectedTravelType) {
      case TravelType.walk:
        icon = Icons.directions_walk_rounded;
        text = "À pied";
        break;
      case TravelType.bike:
        icon = Icons.directions_bike_rounded;
        text = "À vélo";
        break;
      case TravelType.transit:
        icon = Icons.directions_bus_rounded;
        text = "Transport en commun";
        break;
    }

    return Row(children: [
      Icon(icon, color: const Color(0xFF5DBB63), size: 22),
      const SizedBox(width: 6),
      Text(text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: const Color(0xFF5DBB63),
              fontWeight: FontWeight.bold,
              fontSize: 15)),
    ]);
  }

  Widget _buildGainCircle() {
    return Obx(() {
      int currentTotalGain = homeController.activeRouteEstimatedGain.value;

      // Si un défi est actif, afficher une bannière défi au lieu du cercle de gain
      if (_activeChallenge != null) {
        final c = _activeChallenge!;
        return InkWell(
          onTap: () => _showChallengeRewardInfo(c),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            constraints: const BoxConstraints(maxWidth: 150),
            decoration: BoxDecoration(
              color: Colors.purple.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purple.withOpacity(0.4)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.emoji_events, color: Colors.purple, size: 18),
                const SizedBox(height: 2),
                Text(
                  c.rewardText,
                  style: const TextStyle(
                      color: Colors.purple,
                      fontWeight: FontWeight.bold,
                      fontSize: 15),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 2),
                const Text(
                  "dans l'onglet Défis",
                  style: TextStyle(color: Colors.grey, fontSize: 9),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      String topText;
      String totalGainText;

      if (_activeStoreTrip != null) {
        topText = "GAIN TRAJET";
        totalGainText =
            currentTotalGain > 0 ? currentTotalGain.toString() : "-";
      } else {
        topText = "GAIN ESTIMÉ";
        totalGainText =
            currentTotalGain > 0 ? currentTotalGain.toString() : "-";
      }

      bool hasRoute = homeController.destination.value.isNotEmpty &&
          (homeController.polyline.isNotEmpty ||
              homeController.showTransitOptions.value);

      if (!hasRoute) {
        topText = "CALCULER TRAJET";
        totalGainText = "-";
      } else if (currentTotalGain == 0 && homeController.gettingRoute.value) {
        totalGainText = "...";
      }

      String multiplierText = _getMultiplierText();

      return InkWell(
        onTap: () {
          if (hasRoute && currentTotalGain > 0) {
            // CORRIGÉ : Redirection vers le bon popup détaillé pour le Transit
            if (_selectedTravelType == TravelType.transit &&
                homeController.transitRouteOptions.isNotEmpty) {
              _showTransitLameCalculationDetails(
                  context, homeController.transitRouteOptions.first['legs'][0]);
            } else {
              _showLameCalculationDetails(context);
            }
          } else if (hasRoute && currentTotalGain == 0) {
            _updateGainAndRouteData();
          }
        },
        borderRadius: BorderRadius.circular(45),
        child: Container(
          width: 90,
          height: 90,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accentGold.withOpacity(0.15),
              border: Border.all(color: accentGold, width: 1.5)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(topText,
                    style: const TextStyle(
                        color: accentGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 9),
                    textAlign: TextAlign.center,
                    maxLines: 1)),
            const SizedBox(height: 1),
            Text(totalGainText,
                style: const TextStyle(
                    color: textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 24)),
            const Text("Lames",
                style: TextStyle(color: Colors.grey, fontSize: 10)),
            if (multiplierText.isNotEmpty && currentTotalGain > 0)
              FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(multiplierText,
                      style: const TextStyle(
                          color: primaryGreen,
                          fontSize: 8,
                          fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                      maxLines: 1)),
          ]),
        ),
      );
    });
  }

  /// Extrait le nombre de lames depuis le texte de récompense d'un défi
  int _parseChallengeReward(String rewardText) {
    final match = RegExp(r'(\d+)').firstMatch(rewardText);
    if (match != null) return int.tryParse(match.group(1) ?? '') ?? 0;
    return 0;
  }

  // --- NOUVELLE MÉTHODE : Retourne le gain exact transmis depuis l'onglet Défis ---
  Future<int> _calculateChallengeDynamicReward(Challenge challenge) async {
    return _challengeEstimatedReward ?? challenge.rewardLame;
  }

  // --- MODIFIÉ : Affiche le gain calculé au-dessus de la phrase orange ---
  void _showChallengeRewardInfo(Challenge challenge) async {
    // 1. Calcul du vrai gain total
    int totalGain = await _calculateChallengeDynamicReward(challenge);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2))),
            ),
            const Icon(Icons.emoji_events, color: Colors.purple, size: 40),
            const SizedBox(height: 10),
            Text("Récompense du Défi",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.purple, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.purple.withOpacity(0.3))),
              child: Column(children: [
                Text(challenge.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.eco_rounded, color: Colors.purple, size: 28),
                  const SizedBox(width: 8),
                  Text(challenge.rewardText,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple)),
                ]),
              ]),
            ),

            // --- NOUVEAU BLOC : Affiche le total exact ---
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
              decoration: BoxDecoration(
                  color: primaryGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: primaryGreen)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: accentGold),
                  const SizedBox(width: 8),
                  Text("Gain Total Estimé : $totalGain Lames",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: primaryGreen)),
                ],
              ),
            ),

            const SizedBox(height: 15),
            const Text(
              "⚠️ Le gain de trajet classique n'est pas crédité pour les défis.\nSeule la récompense totale ci-dessus sera attribuée une fois le défi terminé.",
              style: TextStyle(fontSize: 12, color: Colors.orange),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(title.toUpperCase(),
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.0)),
    );
  }

  Widget _buildDetailRowDialog(String label, String value,
      {IconData? icon, Color? valueColor, bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, color: textGrey, size: 20),
            const SizedBox(width: 10)
          ],
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 14, color: textGrey))),
          const SizedBox(width: 10),
          Text(
            value,
            style: TextStyle(
                fontSize: 14,
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                color: valueColor ?? textDark),
            textAlign: TextAlign.end,
          ),
        ],
      ),
    );
  }

  Widget _buildPredictionsList(List<Map<String, dynamic>> predictions,
      void Function(Map<String, dynamic>) onSelect) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.3,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.zero,
        itemCount: predictions.length,
        itemBuilder: (context, index) {
          final prediction = predictions[index];
          return ListTile(
            leading: const Icon(Icons.location_on, color: textGrey),
            title: Text(prediction['description'] ?? ''),
            onTap: () {
              FocusScope.of(context).unfocus();
              onSelect(prediction);
            },
          );
        },
      ),
    );
  }

  Widget _buildAdvancedTransitOptionsUI() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.search),
                label: const Text("Voir les itinéraires"),
                onPressed: _searchTransitRoute,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 45),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: () {
                setState(() {
                  _isTransitOptionsExpanded = !_isTransitOptionsExpanded;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _isTransitOptionsExpanded
                            ? primaryGreen
                            : Colors.transparent)),
                child: Icon(
                  _isTransitOptionsExpanded ? Icons.tune : Icons.filter_list,
                  color:
                      _isTransitOptionsExpanded ? primaryGreen : Colors.black54,
                ),
              ),
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: SizedBox(
            height: _isTransitOptionsExpanded ? null : 0,
            child: Column(
              children: [
                const SizedBox(height: 15),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Options de trajet",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _originController,
                        decoration: InputDecoration(
                          hintText: "Départ : Ma position",
                          isDense: true,
                          prefixIcon: const Icon(Icons.my_location, size: 18),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8)),
                          fillColor: Colors.white,
                          filled: true,
                        ),
                        onChanged: _getOriginPlacePredictions,
                      ),
                      if (_originPlacePredictions.isNotEmpty)
                        _buildPredictionsList(
                            _originPlacePredictions, _selectOriginPlace),
                      const SizedBox(height: 10),
                      _buildTransitTimeOptions(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (homeController.showTransitOptions.value) _buildTransitOptionsList(),
      ],
    );
  }

  Widget _buildTransitTimeOptions() {
    return Column(
      children: [
        CupertinoSlidingSegmentedControl<TransitTimeOption>(
          groupValue: _transitTimeOption,
          onValueChanged: (value) {
            if (value != null) {
              setState(() => _transitTimeOption = value);
            }
          },
          children: const {
            TransitTimeOption.leaveNow: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text("Maintenant")),
            TransitTimeOption.departAt: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text("Partir à")),
            TransitTimeOption.arriveBy: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text("Arriver à")),
          },
        ),
        if (_transitTimeOption != TransitTimeOption.leaveNow)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: TextButton(
              onPressed: _pickTransitDateTime,
              child: Text(
                DateFormat('EEE d MMM, HH:mm', 'fr_FR')
                    .format(_selectedTransitTime),
                style: const TextStyle(fontSize: 16, color: primaryGreen),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTransitOptionsList() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Divider(height: 1, thickness: 1),
        const SizedBox(height: 15),
        if (_activeChallenge != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.purple.withOpacity(0.3))),
            child: Column(children: [
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.emoji_events, color: Colors.purple, size: 24),
                const SizedBox(width: 8),
                Text("Récompense du Défi",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.purple, fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 10),
              Text(_activeChallenge!.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.eco_rounded, color: Colors.purple, size: 28),
                const SizedBox(width: 8),
                Text(_activeChallenge!.rewardText,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.purple)),
              ]),
              const SizedBox(height: 15),
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                decoration: BoxDecoration(
                    color: primaryGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: primaryGreen)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, color: accentGold),
                    const SizedBox(width: 8),
                    Text(
                        "Gain Total Estimé : ${_challengeEstimatedReward ?? _activeChallenge!.rewardLame} Lames",
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: primaryGreen)),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              const Text(
                "⚠️ Le gain de trajet classique n'est pas crédité pour les défis.\nSeule la récompense totale ci-dessus sera attribuée une fois le défi terminé.",
                style: TextStyle(fontSize: 12, color: Colors.orange),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
          const SizedBox(height: 15),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Itinéraires disponibles",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: textDark,
                    ),
              ),
              Obx(() => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      "${homeController.transitRouteOptions.length} option${homeController.transitRouteOptions.length > 1 ? 's' : ''}",
                      style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.bold),
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Obx(() {
          if (homeController.transitRouteOptions.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 40.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.directions_bus_outlined,
                        size: 50, color: Colors.grey[300]),
                    const SizedBox(height: 10),
                    Text("Recherche d'itinéraires...",
                        style: TextStyle(color: Colors.grey[500])),
                  ],
                ),
              ),
            );
          }

          final int itemCount = homeController.transitRouteOptions.length;
          final double maxListHeight =
              MediaQuery.of(context).size.height * 0.34;

          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 20),
              itemCount: itemCount,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final route = homeController.transitRouteOptions[index];
                final leg = route['legs'][0];
                final duration = leg['duration']['text'];
                final arrivalTime = leg['arrival_time']?['text'] ?? "--:--";
                final departureTime = leg['departure_time']?['text'] ?? "--:--";
                final int estimatedGain = (_activeChallenge != null &&
                        _challengeEstimatedReward != null)
                    ? _challengeEstimatedReward!
                    : _calculateGainForTransitOption(leg);
                final bool isRecommended = index == 0;
                List<Widget> transportIcons =
                    _buildRouteStepsIcons(leg['steps']);

                return Card(
                  elevation: isRecommended ? 4 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color:
                            isRecommended ? primaryGreen : Colors.grey.shade200,
                        width: isRecommended ? 2 : 1),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      if (_activeChallenge != null) {
                        _showChallengeRewardInfo(_activeChallenge!);
                      } else {
                        _showTransitLameCalculationDetails(context, leg);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(duration,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: textDark)),
                                    const SizedBox(height: 4),
                                    Text("$departureTime → $arrivalTime",
                                        style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12)),
                                    const SizedBox(height: 8),
                                    Wrap(spacing: 5, children: transportIcons),
                                  ],
                                ),
                              ),
                              if (_activeChallenge == null)
                                _buildGainIndicator(estimatedGain),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: () {
                                homeController.activeRouteEstimatedGain.value =
                                    estimatedGain;
                                homeController.selectAndDrawTransitRoute(index);
                                FocusScope.of(context).unfocus();
                              },
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size.fromHeight(34),
                                backgroundColor: isRecommended
                                    ? primaryGreen
                                    : Colors.blueAccent,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text("Choisir cet itinéraire",
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }),
      ],
    );
  }

  Widget _buildGainIndicator(int gain) {
    return Container(
      width: 55,
      height: 55,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accentGold.withOpacity(0.1),
        border: Border.all(color: accentGold, width: 1.5),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            gain.toString(),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const Text("Lames", style: TextStyle(fontSize: 8, color: textGrey)),
        ],
      ),
    );
  }
// --- WIDGETS MANQUANTS (BOOSTS, METEO, SÉRIE) ---

  Widget _buildAdMinimalistIndicator() {
    final profile = widget.userProfile;
    final int decayAmount = _calculateAdPointDecay(profile.adPoints);
    String adPointsDecayTimeString = "- $decayAmount ADP toutes les 5h";

    if (profile.adPoints > 0 && profile.lastAdPointDecayTime != null) {
      DateTime now = DateTime.now();
      Timestamp lastDecayTime = profile.lastAdPointDecayTime!;
      Duration timeSinceLastDecay = now.difference(lastDecayTime.toDate());
      Duration timeUntilNextDecay =
          const Duration(hours: 5) - timeSinceLastDecay;
      if (timeUntilNextDecay.isNegative) {
        adPointsDecayTimeString = "-$decayAmount bientôt";
      } else {
        adPointsDecayTimeString =
            "-$decayAmount dans ${timeUntilNextDecay.inHours}h${timeUntilNextDecay.inMinutes.remainder(60)}m";
      }
    }

    return GestureDetector(
      onTap: () => _showAdPointsDetailsDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 2,
                offset: const Offset(0, 1))
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
                onTap: _watchAd,
                borderRadius: BorderRadius.circular(10),
                child: const Icon(Icons.slow_motion_video_rounded,
                    color: primaryGreen, size: 16)),
            const SizedBox(width: 3),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${profile.adPoints}/50 ADP",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: textDark,
                          fontSize: 9)),
                  if (adPointsDecayTimeString.isNotEmpty)
                    Text(
                      adPointsDecayTimeString,
                      style: TextStyle(fontSize: 6, color: Colors.orange[700]),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 3),
            if (profile.adPoints >= 10)
              const Tooltip(
                  message: "Multiplicateur x1.2 actif !",
                  child: Icon(Icons.bolt_rounded, color: accentGold, size: 14))
            else
              Tooltip(
                  message: "10 ADP pour activer x1.2",
                  child: Icon(Icons.offline_bolt_outlined,
                      color: textGrey.withOpacity(0.5), size: 14)),
          ],
        ),
      ),
    );
  }

  int _calculateAdPointDecay(int currentPoints) {
    if (currentPoints < 10) return 1;
    if (currentPoints < 20) return 2;
    if (currentPoints < 30) return 3;
    if (currentPoints < 40) return 4;
    return 5;
  }

  Widget _buildLoginStreakIndicator() {
    final profile = widget.userProfile;
    return GestureDetector(
      onTap: () => _showLoginStreakDetailsDialog(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 2,
                offset: const Offset(0, 1))
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department_rounded,
                color: Colors.orangeAccent, size: 14),
            const SizedBox(width: 4),
            Text("${profile.consecutiveLogins}",
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: textDark,
                    fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherSection() {
    final weather = widget.weatherData;
    if (weather == null) {
      return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
              color: cardWhite,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[200]!, width: 1),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 5,
                    offset: const Offset(0, 2))
              ]),
          child: Row(children: [
            Icon(Icons.thermostat_rounded, color: Colors.grey[400]),
            const SizedBox(width: 10),
            Expanded(
                child: Text(widget.currentWeatherTextForHome,
                    style: const TextStyle(color: textGrey)))
          ]));
    }

    bool weatherBoostIsActive = _isWeatherBoostApplicable();

    return Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: cardWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!, width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2))
            ]),
        child: Row(children: [
          Icon(weather.getWeatherIcon(), color: accentGold, size: 40),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    "${weather.temperature.toStringAsFixed(0)}°C à ${weather.cityOrRegion}",
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: textDark,
                        fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(weather.getWeatherDescription(),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: textGrey, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1),
                if (weather.minTempToday != null &&
                    weather.maxTempToday != null)
                  Text(
                      "Min ${weather.minTempToday?.toStringAsFixed(0)}° / Max ${weather.maxTempToday?.toStringAsFixed(0)}°",
                      style:
                          TextStyle(fontSize: 11, color: Colors.blueGrey[400]))
              ])),
          const SizedBox(width: 8),
          if (weatherBoostIsActive)
            const Tooltip(
              message: "Boost Météo (x1.5) actif !",
              child: Icon(Icons.shield_moon_rounded,
                  color: primaryGreen, size: 28),
            )
          else
            Tooltip(
              message: "Conditions météo normales",
              child: Icon(Icons.shield_outlined,
                  color: Colors.grey[400], size: 28),
            )
        ]));
  }

  Widget _buildFavoriteRoutesSection() {
    List<Map<String, dynamic>> favoriteRoutes =
        widget.userProfile.favoriteRoutes;

    if (favoriteRoutes.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: cardWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey[200]!, width: 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2))
            ]),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.favorite, color: Colors.red[400], size: 24),
                const SizedBox(width: 10),
                const Text(
                  "Trajets favoris",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: textDark,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _showAddFavoriteRouteDialog,
                  icon: const Icon(Icons.add, color: primaryGreen),
                  tooltip: "Ajouter un trajet favori",
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              "Aucun trajet favori ajouté. Appuyez sur + pour en créer un !",
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: cardWhite,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!, width: 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 5,
                offset: const Offset(0, 2))
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite, color: Colors.red[400], size: 24),
              const SizedBox(width: 10),
              const Text(
                "Trajets favoris",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _showAddFavoriteRouteDialog,
                icon: const Icon(Icons.add, color: primaryGreen),
                tooltip: "Ajouter un trajet favori",
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...favoriteRoutes
              .take(3)
              .map((route) => _buildFavoriteRouteCard(route))
              .toList(),
          if (favoriteRoutes.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Center(
                child: TextButton(
                  onPressed: _showAllFavoriteRoutes,
                  child: Text("Voir tous (${favoriteRoutes.length})"),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFavoriteRouteCard(Map<String, dynamic> route) {
    String name = route['name'] ?? 'Trajet sans nom';
    String destination = route['destination'] ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête avec nom et menu
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.my_location, size: 14, color: Colors.blue),
                        const SizedBox(width: 4),
                        Text(
                          'Position actuelle',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: Colors.red),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            destination,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    _showEditFavoriteRouteDialog(route);
                  } else if (value == 'delete') {
                    _deleteFavoriteRoute(route);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18),
                        SizedBox(width: 8),
                        Text('Modifier'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Supprimer'),
                      ],
                    ),
                  ),
                ],
                child:
                    const Icon(Icons.more_vert, size: 18, color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),
          // Modes de transport
          const Text(
            'Choisissez votre mode de transport :',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: textDark,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              // Mode Marche
              Expanded(
                child: InkWell(
                  onTap: () => _startFavoriteRoute(route, TravelType.walk),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.directions_walk,
                            color: Colors.blue, size: 24),
                        const SizedBox(height: 4),
                        const Text('Marche',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Mode Vélo
              Expanded(
                child: InkWell(
                  onTap: () => _startFavoriteRoute(route, TravelType.bike),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.directions_bike,
                            color: Colors.green, size: 24),
                        const SizedBox(height: 4),
                        const Text('Vélo',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Mode Transport
              Expanded(
                child: InkWell(
                  onTap: () => _startFavoriteRoute(route, TravelType.transit),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.directions_bus,
                            color: Colors.orange, size: 24),
                        const SizedBox(height: 4),
                        const Text('Transport',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<int> _calculateRouteReward(
      Map<String, dynamic> route, TravelType mode) async {
    try {
      // Obtenir les positions de départ et d'arrivée
      Position? startPosition;

      if (route['use_current_location'] == true) {
        startPosition = await homeController.getMyCurrentLocation();
      } else {
        // Pour l'instant, utiliser la position actuelle comme fallback
        // Dans une implémentation complète, on géocoderait l'adresse de départ
        startPosition = await homeController.getMyCurrentLocation();
      }

      String destination = route['destination'] ?? '';
      if (destination.isEmpty) return 0;

      // Estimer la distance (dans une vraie implémentation, on utiliserait un service de géocodage)
      // Pour l'instant, on utilise une estimation basée sur la destination
      double estimatedDistanceKm = 5.0; // Distance par défaut
      double durationMin = _estimateDuration(estimatedDistanceKm, mode);

      // Calculer les points selon le mode de transport
      double points = 0;

      switch (mode) {
        case TravelType.walk:
          points = estimatedDistanceKm * 10.0 + durationMin * 0.5;
          break;
        case TravelType.bike:
          points = estimatedDistanceKm * 6.0 + durationMin * 0.2;
          break;
        case TravelType.transit:
          points = estimatedDistanceKm * 5.0 * 0.8 + durationMin * 0.5 * 0.8;
          break;
      }

      return points.round();
    } catch (e) {
      print('Erreur lors du calcul des récompenses: $e');
      return 0;
    }
  }

  List<Widget> _buildRouteStepsIcons(List<dynamic> steps) {
    List<Widget> icons = [];
    for (var step in steps) {
      if (step['travel_mode'] == 'WALKING') {
        icons.add(
            const Icon(Icons.directions_walk, size: 16, color: Colors.grey));
      } else if (step['travel_mode'] == 'TRANSIT') {
        final vehicle = step['transit_details']?['line']?['vehicle']?['type'];
        IconData iconData = Icons.directions_bus;
        if (vehicle == 'SUBWAY') iconData = Icons.subway;
        if (vehicle == 'TRAM') iconData = Icons.tram;
        if (vehicle == 'RAIL') iconData = Icons.train;

        icons.add(Icon(iconData, size: 16, color: Colors.blueAccent));
        final shortName = step['transit_details']?['line']?['short_name'] ?? "";
        if (shortName.isNotEmpty) {
          icons.add(Text(shortName,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blueAccent)));
        }
      }
      if (steps.indexOf(step) != steps.length - 1) {
        icons
            .add(const Icon(Icons.chevron_right, size: 14, color: Colors.grey));
      }
    }
    return icons;
  }

  // === GESTION DES INTENTS DU WIDGET ===

  void _setupWidgetIntentListener() async {
    if (Platform.isAndroid) {
      const platform = MethodChannel('com.parrel.walkmoney/widget');

      // Vérifier s'il y a des données d'intent au démarrage
      try {
        final result = await platform.invokeMethod('getWidgetData');
        if (result != null) {
          _handleWidgetIntent(result);
        }
      } catch (e) {
        print('Erreur lors de la récupération des données du widget: $e');
      }
    }
  }

  TravelType _parseWidgetTravelType(String? mode) {
    switch (mode) {
      case 'bike':
        return TravelType.bike;
      case 'transit':
        return TravelType.transit;
      default:
        return TravelType.walk;
    }
  }

  // === GESTION DES TRAJETS FAVORIS ===

  void _showAddFavoriteRouteDialog() {
    String routeName = '';
    String destination = '';
    final nameController = TextEditingController();
    final destController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setDialogState) => AlertDialog(
          title: const Text('Ajouter un trajet favori'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nom du trajet',
                  hintText: 'Ex: Travail, Salle de sport...',
                ),
                onChanged: (value) {
                  setDialogState(() => routeName = value.trim());
                },
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.my_location, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Départ : Ma position actuelle',
                        style: TextStyle(
                            color: Colors.blue[800],
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: destController,
                decoration: const InputDecoration(
                  labelText: 'Destination',
                  hintText: 'Adresse de destination',
                  prefixIcon: Icon(Icons.location_on),
                ),
                onChanged: (value) {
                  setDialogState(() => destination = value.trim());
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: routeName.isNotEmpty && destination.isNotEmpty
                  ? () => _saveFavoriteRoute(routeName, '', destination, true)
                  : null,
              child: const Text('Ajouter'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditFavoriteRouteDialog(Map<String, dynamic> route) {
    String routeName = route['name'] ?? '';
    String destination = route['destination'] ?? '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Modifier le trajet favori'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: 'Nom du trajet'),
                controller: TextEditingController(text: routeName),
                onChanged: (value) => routeName = value,
              ),
              const SizedBox(height: 16),
              // Information sur le point de départ
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.my_location, color: Colors.blue, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Départ : Ma position actuelle',
                        style: TextStyle(
                          color: Colors.blue[800],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Destination',
                  prefixIcon: Icon(Icons.location_on),
                ),
                controller: TextEditingController(text: destination),
                onChanged: (value) => destination = value,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Annuler'),
            ),
            ElevatedButton(
              onPressed: routeName.isNotEmpty && destination.isNotEmpty
                  ? () => _updateFavoriteRoute(
                      route, routeName, '', destination, true)
                  : null,
              child: const Text('Modifier'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAllFavoriteRoutes() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Tous les trajets favoris',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _showAddFavoriteRouteDialog,
                  icon: const Icon(Icons.add, color: primaryGreen),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: widget.userProfile.favoriteRoutes.length,
                itemBuilder: (context, index) {
                  final route = widget.userProfile.favoriteRoutes[index];
                  return _buildFavoriteRouteCard(route);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveFavoriteRoute(String name, String startAddress,
      String destination, bool useCurrentLocation) async {
    Navigator.pop(context); // Fermer le dialog

    Map<String, dynamic> favoriteRoute = {
      'name': name,
      'start_address': startAddress,
      'destination': destination,
      'use_current_location': useCurrentLocation,
      'created_at': Timestamp.now().toDate().toIso8601String(),
    };

    List<Map<String, dynamic>> currentFavorites =
        List.from(widget.userProfile.favoriteRoutes);
    currentFavorites.add(favoriteRoute);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userProfile.id)
          .update({
        'favorite_routes': currentFavorites,
      });

      // Sauvegarder aussi dans SharedPreferences pour le widget Android
      await _saveRoutesToSharedPrefs(currentFavorites);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Trajet favori '$name' ajouté !"),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Actualiser le profil
      widget.onProfileModified();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de l'ajout: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updateFavoriteRoute(Map<String, dynamic> oldRoute, String name,
      String startAddress, String destination, bool useCurrentLocation) async {
    Navigator.pop(context); // Fermer le dialog

    Map<String, dynamic> updatedRoute = {
      'name': name,
      'start_address': startAddress,
      'destination': destination,
      'use_current_location': useCurrentLocation,
      'created_at':
          oldRoute['created_at'], // Garder la date de création originale
      'updated_at': Timestamp.now().toDate().toIso8601String(),
    };

    List<Map<String, dynamic>> currentFavorites =
        List.from(widget.userProfile.favoriteRoutes);
    int index = currentFavorites.indexOf(oldRoute);
    if (index != -1) {
      currentFavorites[index] = updatedRoute;
    }

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userProfile.id)
          .update({
        'favorite_routes': currentFavorites,
      });

      // Sauvegarder aussi dans SharedPreferences pour le widget Android
      await _saveRoutesToSharedPrefs(currentFavorites);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Trajet favori '$name' modifié !"),
            backgroundColor: Colors.green,
          ),
        );
      }

      // Actualiser le profil
      widget.onProfileModified();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de la modification: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteFavoriteRoute(Map<String, dynamic> route) async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le trajet favori'),
        content:
            Text("Êtes-vous sûr de vouloir supprimer '${route['name']}' ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    List<Map<String, dynamic>> currentFavorites =
        List.from(widget.userProfile.favoriteRoutes);
    currentFavorites.remove(route);

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userProfile.id)
          .update({
        'favorite_routes': currentFavorites,
      });

      // Sauvegarder aussi dans SharedPreferences pour le widget Android
      await _saveRoutesToSharedPrefs(currentFavorites);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Trajet favori '${route['name']}' supprimé"),
            backgroundColor: Colors.orange,
          ),
        );
      }

      // Actualiser le profil
      widget.onProfileModified();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erreur lors de la suppression: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getModeLabel(TravelType mode) {
    switch (mode) {
      case TravelType.walk:
        return 'Marche';
      case TravelType.bike:
        return 'Vélo';
      case TravelType.transit:
        return 'Transport';
      default:
        return 'Marche';
    }
  }

  Future<void> _saveRoutesToSharedPrefs(
      List<Map<String, dynamic>> routes) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final routesJson = jsonEncode(routes);
      await prefs.setString('favorite_routes', routesJson);

      // Notifier le widget Android de la mise à jour
      await _updateAndroidWidget();
    } catch (e) {
      print('Erreur lors de la sauvegarde des trajets favoris: $e');
    }
  }

  Future<void> _updateAndroidWidget() async {
    if (Platform.isAndroid) {
      try {
        // Utiliser la classe AppWidgetManager pour mettre à jour le widget
        const platform = MethodChannel('com.parrel.walkmoney/widget');
        await platform.invokeMethod('updateWidget');
      } catch (e) {
        print('Erreur lors de la mise à jour du widget: $e');
      }
    }
  }

  double _estimateDuration(double distanceKm, TravelType mode) {
    switch (mode) {
      case TravelType.walk:
        return distanceKm * 12; // 5 km/h
      case TravelType.bike:
        return distanceKm * 4; // 15 km/h
      case TravelType.transit:
        return distanceKm * 3; // 20 km/h en moyenne avec les arrêts
      default:
        return distanceKm * 12;
    }
  }
}

enum HomeScreenMode { trajet, trajetTravail }

enum TransitTimeOption { leaveNow, departAt, arriveBy }

enum StoreSortOption { proximity, profitability }

class StoresScreen extends StatefulWidget {
  final List<EcoStore> ecoStores;
  final Function(EcoStore, TravelType) onStartTrip;
  final UserProfile userProfile;
  final Function(int, {String? source}) onAddLame;
  final WeatherData? weatherData;

  /// Map storeId → DateTime du trajet terminé, en attente de validation ticket
  final Map<String, DateTime> pendingValidations;

  const StoresScreen({
    Key? key,
    required this.ecoStores,
    required this.onStartTrip,
    required this.userProfile,
    required this.onAddLame,
    this.weatherData,
    this.pendingValidations = const {},
  }) : super(key: key);

  @override
  _StoresScreenState createState() => _StoresScreenState();
}

class _StoresScreenState extends State<StoresScreen> {
  StoreSortOption _currentSort = StoreSortOption.proximity;
  bool _useRadius = true;
  double _radiusKm = 20.0;
  int _visibleCount = 10;
  List<EcoStore> _sortedStores = [];
  latlong.LatLng? _userPosition;
  bool _isLoadingLoc = true;
  bool _showOnlyFavorites = false;

  List<String> _selectedCategories = [];
  final List<String> _availableCategories = [
    'Alimentation',
    'Cosmétique',
    'Vêtement',
    'Grande surface'
  ];

  @override
  void initState() {
    super.initState();
    _initLocationAndData();
  }

  Future<void> _initLocationAndData() async {
    try {
      Position p = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium);
      _userPosition = latlong.LatLng(p.latitude, p.longitude);
    } catch (e) {
      print("Erreur localisation StoresScreen: $e");
      _userPosition = widget.userProfile.homeAddressCoordinates ??
          latlong.LatLng(45.75, 4.85);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLoc = false;
        });
        _applySortAndFilter();
      }
    }
  }

  void _applySortAndFilter() {
    if (_userPosition == null) return;

    List<EcoStore> tempStores = List.from(widget.ecoStores);
    Map<String, double> distances = {};
    for (var store in tempStores) {
      double distMeters = Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          store.coordinates.latitude,
          store.coordinates.longitude);
      distances[store.id] = distMeters / 1000.0;
    }

    if (_useRadius) {
      tempStores = tempStores.where((s) {
        double d = distances[s.id] ?? 9999.0;
        return d <= _radiusKm;
      }).toList();
    }

    if (_showOnlyFavorites) {
      tempStores = tempStores
          .where(
              (store) => widget.userProfile.favoriteStores.contains(store.id))
          .toList();
    }

    if (_selectedCategories.isNotEmpty) {
      tempStores = tempStores
          .where((s) => _selectedCategories.contains(s.category))
          .toList();
    }

    // TRI : On met d'abord les stores avec BOOST VISIBILITÉ (Payant) en premier
    tempStores.sort((a, b) {
      // 1. Priorité absolue au Multiplicateur (Boost Visibilité)
      // Celui qui paye pour 1.6x passe devant celui qui a 1.2x, qui passe devant 1.0x
      if (b.lamePointMultiplier.compareTo(a.lamePointMultiplier) != 0) {
        return b.lamePointMultiplier.compareTo(a.lamePointMultiplier);
      }

      // 2. Ensuite Tri Standard (Proximité ou Rentabilité)
      if (_currentSort == StoreSortOption.proximity) {
        double distA = distances[a.id] ?? 9999.0;
        double distB = distances[b.id] ?? 9999.0;
        return distA.compareTo(distB);
      } else {
        return b.cashbackRate.compareTo(a.cashbackRate);
      }
    });

    setState(() {
      _sortedStores = tempStores;
    });
  }

  void _loadMore() {
    setState(() => _visibleCount += 10);
  }

  void _showCategoryFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        List<String> tempSelected = List.from(_selectedCategories);
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text("Trier par catégorie"),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _availableCategories.map((cat) {
                    return CheckboxListTile(
                      title: Text(cat),
                      value: tempSelected.contains(cat),
                      activeColor: primaryGreen,
                      onChanged: (bool? value) {
                        setStateDialog(() {
                          if (value == true) {
                            tempSelected.add(cat);
                          } else {
                            tempSelected.remove(cat);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Annuler"),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _selectedCategories = tempSelected;
                    });
                    _applySortAndFilter();
                    Navigator.pop(context);
                  },
                  child: const Text("Appliquer"),
                )
              ],
            );
          },
        );
      },
    );
  }

  void _showRadiusFilterDialog() {
    showDialog(
        context: context,
        builder: (ctx) {
          double tempRadius = _radiusKm;
          bool tempUse = _useRadius;

          return StatefulBuilder(
            builder: (context, setStateDialog) {
              return AlertDialog(
                title: const Text("Filtrer par distance"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Checkbox(
                            value: tempUse,
                            activeColor: primaryGreen,
                            onChanged: (v) =>
                                setStateDialog(() => tempUse = v!)),
                        const Text("Limiter le rayon"),
                      ],
                    ),
                    if (tempUse) ...[
                      const SizedBox(height: 10),
                      Text("${tempRadius.round()} km",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: primaryGreen)),
                      Slider(
                        value: tempRadius,
                        min: 5,
                        max: 100,
                        divisions: 19,
                        activeColor: primaryGreen,
                        onChanged: (v) => setStateDialog(() => tempRadius = v),
                      ),
                    ]
                  ],
                ),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Annuler")),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _radiusKm = tempRadius;
                        _useRadius = tempUse;
                      });
                      _applySortAndFilter();
                      Navigator.pop(context);
                    },
                    child: const Text("Appliquer"),
                  )
                ],
              );
            },
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    final displayList = _sortedStores.take(_visibleCount).toList();
    final bool hasMore = _visibleCount < _sortedStores.length;

    return Scaffold(
      backgroundColor: defisScreenBackground,
      // MODIFIÉ: Suppression du FloatingActionButton ici
      body: Column(
        children: [
          // Barre de filtres (identique à avant)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    offset: const Offset(0, 2),
                    blurRadius: 5)
              ],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const Icon(Icons.tune, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(
                        _currentSort == StoreSortOption.proximity
                            ? Icons.near_me
                            : Icons.euro,
                        size: 16,
                        color: Colors.white),
                    label: Text(_currentSort == StoreSortOption.proximity
                        ? "Proximité"
                        : "Rentabilité"),
                    backgroundColor: primaryGreen,
                    labelStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold),
                    onPressed: () {
                      setState(() {
                        _currentSort = _currentSort == StoreSortOption.proximity
                            ? StoreSortOption.profitability
                            : StoreSortOption.proximity;
                        _applySortAndFilter();
                      });
                    },
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(Icons.radar,
                        size: 16, color: _useRadius ? Colors.white : textDark),
                    label: Text(_useRadius
                        ? "Rayon: ${_radiusKm.round()} km"
                        : "Monde entier"),
                    backgroundColor: _useRadius
                        ? primaryGreen.withOpacity(0.8)
                        : Colors.grey[200],
                    labelStyle: TextStyle(
                        color: _useRadius ? Colors.white : textDark,
                        fontSize: 13),
                    onPressed: _showRadiusFilterDialog,
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(Icons.category,
                        size: 16,
                        color: _selectedCategories.isNotEmpty
                            ? Colors.white
                            : textDark),
                    label: Text(_selectedCategories.isNotEmpty
                        ? "${_selectedCategories.length} Catégorie(s)"
                        : "Catégories"),
                    backgroundColor: _selectedCategories.isNotEmpty
                        ? primaryGreen.withOpacity(0.8)
                        : Colors.grey[200],
                    labelStyle: TextStyle(
                        color: _selectedCategories.isNotEmpty
                            ? Colors.white
                            : textDark,
                        fontSize: 13),
                    onPressed: _showCategoryFilterDialog,
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(Icons.favorite,
                        size: 16,
                        color: _showOnlyFavorites ? Colors.white : textDark),
                    label: Text(_showOnlyFavorites
                        ? "Favoris uniquement"
                        : "Tous les magasins"),
                    backgroundColor:
                        _showOnlyFavorites ? accentGold : Colors.grey[200],
                    labelStyle: TextStyle(
                        color: _showOnlyFavorites ? Colors.white : textDark,
                        fontSize: 13),
                    onPressed: () {
                      setState(() {
                        _showOnlyFavorites = !_showOnlyFavorites;
                      });
                      _applySortAndFilter();
                    },
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text("${_sortedStores.length} résultat(s)"),
                    backgroundColor: Colors.transparent,
                    shape: StadiumBorder(
                        side: BorderSide(color: Colors.grey.shade300)),
                    labelStyle:
                        const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoadingLoc
                ? const Center(
                    child: CircularProgressIndicator(color: primaryGreen))
                : _sortedStores.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                                _showOnlyFavorites
                                    ? Icons.favorite_border
                                    : Icons.location_off,
                                size: 50,
                                color: Colors.grey),
                            const SizedBox(height: 10),
                            Text(_showOnlyFavorites
                                ? "Aucun magasin favori trouvé."
                                : "Aucun magasin trouvé dans ce rayon."),
                            if (_useRadius && !_showOnlyFavorites)
                              TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _useRadius = false;
                                      _applySortAndFilter();
                                    });
                                  },
                                  child:
                                      const Text("Afficher tout sans limite")),
                            if (_showOnlyFavorites)
                              TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _showOnlyFavorites = false;
                                      _applySortAndFilter();
                                    });
                                  },
                                  child:
                                      const Text("Afficher tous les magasins"))
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () async => await _initLocationAndData(),
                        child: ListView.builder(
                          padding:
                              const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 80.0),
                          itemCount: displayList.length + 1,
                          itemBuilder: (context, index) {
                            if (index == displayList.length) {
                              if (hasMore) {
                                return Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 15),
                                  child: Center(
                                    child: OutlinedButton(
                                      onPressed: _loadMore,
                                      style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(20))),
                                      child: const Text(
                                          "Charger plus de magasins"),
                                    ),
                                  ),
                                );
                              } else {
                                return const SizedBox.shrink();
                              }
                            }
                            final store = displayList[index];
                            return StoreCard(
                              key: ValueKey(store.id),
                              store: store,
                              userPositionForCalcul: () async =>
                                  _userPosition ?? latlong.LatLng(0, 0),
                              onStartTrip: widget.onStartTrip,
                              userProfile: widget.userProfile,
                              onAddLame: widget.onAddLame,
                              weatherData: widget.weatherData,
                              tripCompletedAt:
                                  widget.pendingValidations[store.id],
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class StoreCard extends StatefulWidget {
  final Function(EcoStore, TravelType) onStartTrip;
  final EcoStore store;
  final Future<latlong.LatLng> Function() userPositionForCalcul;
  final UserProfile userProfile;
  final Function(int, {String? source}) onAddLame;
  final WeatherData? weatherData;

  /// Si true, ouvre directement le flux de validation ticket (mode "arrivé au magasin")
  final bool showValidateOnOpen;

  /// Date/heure à laquelle le trajet vers ce magasin s'est terminé (null = pas de trajet terminé)
  final DateTime? tripCompletedAt;

  const StoreCard({
    Key? key,
    required this.store,
    required this.onStartTrip,
    required this.userPositionForCalcul,
    required this.userProfile,
    required this.onAddLame,
    this.weatherData,
    this.showValidateOnOpen = false,
    this.tripCompletedAt,
  }) : super(key: key);

  @override
  _StoreCardState createState() => _StoreCardState();
}

class _StoreCardState extends State<StoreCard> {
  bool _isLoading = false;
  bool _isProcessingPurchase = false;
  String? _error;

  TravelType _selectedTravelType = TravelType.walk;
  String? _durationText;
  int? _totalLameGain;
  int? _effortBonus;
  double? _weatherMultiplier;
  bool _isFavorite = false;

// Gestion du Boost
  Timer? _refreshTimer;
  double _currentBoostVal = 0.0;
  String _boostStatusText = "";

// États locaux pour calcul immédiat
  double _localBoostAmount = 0.0;
  DateTime _localLastUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initBoostData();
    _isFavorite = widget.userProfile.favoriteStores.contains(widget.store.id);
    _calculateAllGains();

    // Si on est en mode "arrivé au magasin", déclencher la validation directement
    if (widget.showValidateOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onValidatePurchase();
      });
    }
  }

  void _initBoostData() {
// Récupérer les données spécifiques À CE MAGASIN
    final boostData = widget.userProfile.storeBoosts[widget.store.id] ?? {};
    _localBoostAmount = (boostData['amount'] as num?)?.toDouble() ?? 0.0;

    if (boostData['last_update'] != null) {
      _localLastUpdate = (boostData['last_update'] as Timestamp).toDate();
    } else {
      _localLastUpdate = DateTime.now();
    }
    _recalcBoostDisplay();
    _updateTimerState();
  }

  void _updateTimerState() {
    _refreshTimer?.cancel();
    _refreshTimer = null;

    // Lancer le timer de compte à rebours uniquement si un boost est actif
    if (_localBoostAmount > 0 && _currentBoostVal > 0) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          _refreshTimer = null;
          return;
        }
        _recalcBoostDisplay();
        if (_currentBoostVal <= 0) {
          timer.cancel();
          _refreshTimer = null;
        }
      });
    }
  }

  @override
  void didUpdateWidget(StoreCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile != widget.userProfile) {
      _initBoostData();
      _isFavorite = widget.userProfile.favoriteStores.contains(widget.store.id);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
    super.dispose();
  }

// ===========================================================================
// 🧠 LOGIQUE COMPLEXE DU BOOST (PERTE / DECAY)
// ===========================================================================

  void _recalcBoostDisplay() {
    final now = DateTime.now();
    final int secondsElapsed = now.difference(_localLastUpdate).inSeconds;

    double simulatedAmount = _localBoostAmount;
    int secondsSimulated = 0;
    String nextDropText = "";

// Max Boost = 2x Cashback Magasin (ex: 5% -> Max 10% -> donc boost max +5.0)
    double maxBoostAddon = widget.store.cashbackRate * 100.0;
    if (maxBoostAddon < 1.0) maxBoostAddon = 1.0; // Sécurité

    bool isSpecialMode = simulatedAmount >= 1.0;
    bool isPremium = widget.userProfile.isVip;

// Simulation de la perte temporelle
    while (true) {
      if (simulatedAmount <= 0) {
        simulatedAmount = 0;
        nextDropText = "Inactif";
        break;
      }

      final decayRule = _getBoostDecayRule(simulatedAmount, isPremium);
      int stepMinutes = decayRule['stepMinutes'] as int;
      double lossAmount = decayRule['lossAmount'] as double;

      int stepSeconds = stepMinutes * 60;

// Avance dans le temps
      if (secondsSimulated + stepSeconds <= secondsElapsed) {
        simulatedAmount -= lossAmount;
        secondsSimulated += stepSeconds;
// On continue la boucle avec la nouvelle valeur (qui changera peut-être de palier)
      } else {
// On est dans ce palier
        int secondsRemaining =
            stepSeconds - (secondsElapsed - secondsSimulated);
        String minStr = (secondsRemaining ~/ 60).toString().padLeft(2, '0');
        String secStr = (secondsRemaining % 60).toString().padLeft(2, '0');
        nextDropText = "-${lossAmount.toStringAsFixed(3)} dans $minStr:$secStr";
        break;
      }
    }

    setState(() {
      _currentBoostVal = simulatedAmount < 0 ? 0 : simulatedAmount;
      _boostStatusText = nextDropText;
    });
  }

  Map<String, dynamic> _getBoostDecayRule(double amount, bool isPremium) {
    // Le montant plus élevé doit déclencher une perte proportionnellement plus forte,
    // avec des paliers clairement définis et compréhensibles.
    int stepMinutes;
    double lossAmount;

    if (amount >= 1.0) {
      stepMinutes = isPremium ? 10 : 5;
      lossAmount = isPremium ? 0.05 : 0.10;
    } else if (amount >= 0.60) {
      stepMinutes = 5;
      lossAmount = 0.60;
    } else if (amount >= 0.50) {
      stepMinutes = 10;
      lossAmount = 0.50;
    } else if (amount >= 0.40) {
      stepMinutes = 15;
      lossAmount = 0.40;
    } else if (amount >= 0.30) {
      stepMinutes = 20;
      lossAmount = 0.30;
    } else if (amount >= 0.20) {
      stepMinutes = 25;
      lossAmount = 0.20;
    } else if (amount >= 0.10) {
      stepMinutes = 30;
      lossAmount = 0.10;
    } else {
      stepMinutes = 60;
      lossAmount = 0.01;
    }

    // Bonus Premium déjà intégré ci-dessus ; pas de règle inconsistante.
    return {
      'stepMinutes': stepMinutes,
      'lossAmount': lossAmount,
    };
  }

  Future<void> _toggleFavorite() async {
    try {
      bool isCurrentlyFavorite = _isFavorite;
      List<String> updatedFavorites =
          List.from(widget.userProfile.favoriteStores);

      if (isCurrentlyFavorite) {
        updatedFavorites.remove(widget.store.id);
      } else {
        updatedFavorites.add(widget.store.id);
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userProfile.id)
          .update({
        'favorite_stores': updatedFavorites,
      });

      if (mounted) {
        setState(() {
          _isFavorite = !isCurrentlyFavorite;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isCurrentlyFavorite
                ? "Retiré des favoris"
                : "Ajouté aux favoris"),
            backgroundColor: isCurrentlyFavorite ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Erreur lors de la mise à jour des favoris"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _watchAdForBoost() async {
// 1. Simulation Visionnage Pub (remplacer par AdMob si nécessaire)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator()),
    );
    await Future.delayed(const Duration(seconds: 2));
    if (Get.isDialogOpen ?? false)
      Get.back(); // Fermer loader de manière sécurisée

// 2. Calcul du Gain "Intelligent"
    bool userIsActuallyPremium = widget.userProfile.isVip;
    bool storeHasBoostEnabled = widget.store.isPremiumAdBoostEnabled;

// Logique demandée :
// - Si StoreBoost ON et User Standard -> User devient Premium pour ce store
// - Si StoreBoost ON et User Premium -> User devient Super Premium (x2)
// - Si StoreBoost OFF : User garde son statut normal

    bool effectivelyPremium = userIsActuallyPremium || storeHasBoostEnabled;
    bool effectivelySuperPremium =
        userIsActuallyPremium && storeHasBoostEnabled;

// Gain de base pour une pub standard
    double gain = 0.01;

// Application des multiplicateurs
    if (effectivelySuperPremium) {
      gain = 0.04; // Super Premium (Double du Premium standard 0.02)
    } else if (effectivelyPremium) {
      gain = 0.02; // Premium Standard (Double du standard 0.01)
    }

// Gestion du mode "Spécial" (si le boost est déjà > 1.0)
// Règle : Les gains explosent pour maintenir un haut niveau
    if (_currentBoostVal >= 1.0) {
      if (effectivelySuperPremium) {
        gain = 0.8; // Enorme boost
      } else if (effectivelyPremium) {
        gain = 0.4;
      } else {
        gain = 0.2;
      }
    }

    double newAmount = _currentBoostVal + gain;

// Max Cap (Double du cashback de base du store, min 1.0)
    double maxCap = widget.store.cashbackRate * 100.0;
    if (maxCap < 1.0) maxCap = 1.0;

    if (newAmount > maxCap) {
      newAmount = maxCap;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Maximum atteint ! Maintenez ce niveau.")));
    } else {
      String statusMsg = "";
      if (effectivelySuperPremium)
        statusMsg = " (SUPER PREMIUM !)";
      else if (storeHasBoostEnabled && !userIsActuallyPremium)
        statusMsg = " (Offert par le magasin)";

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text("Boost activé ! +${gain.toStringAsFixed(2)}%$statusMsg"),
          backgroundColor:
              effectivelySuperPremium ? Colors.amber[800] : Colors.green));
    }

// 3. Mise à jour Firestore (Map Specifique pour ce magasin)
    Map<String, dynamic> updateData = {
      'amount': newAmount,
      'last_update': FieldValue.serverTimestamp(),
    };

    try {
// On utilise set avec merge pour créer l'entrée si elle n'existe pas sans écraser le reste
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userProfile.id)
          .set({
        'store_boosts': {widget.store.id: updateData}
      }, SetOptions(merge: true));

// 4. Update Local Immédiat pour l'UI
      setState(() {
        _localBoostAmount = newAmount;
        _localLastUpdate = DateTime.now();
      });
      _recalcBoostDisplay(); // Met à jour le timer de perte
    } catch (e) {
      print("Erreur sauvegarde boost: $e");
    }
  }

// ===========================================================================
// 🗺️ CALCUL ITINÉRAIRE & UI
// ===========================================================================

  Future<void> _calculateAllGains() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _totalLameGain = null;
    });

    try {
      latlong.LatLng userPos = await widget.userPositionForCalcul();

      // Vérifier que la position est valide (non nulle)
      if (userPos.latitude == 0 && userPos.longitude == 0) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final directionsService = DirectionsService();

      TravelMode mode = TravelMode.walking;
      if (_selectedTravelType == TravelType.bike) mode = TravelMode.bicycling;
      if (_selectedTravelType == TravelType.transit) mode = TravelMode.transit;

      final request = DirectionsRequest(
        origin: "${userPos.latitude},${userPos.longitude}",
        destination:
            "${widget.store.coordinates.latitude},${widget.store.coordinates.longitude}",
        travelMode: mode,
      );

      // Utiliser null pour détecter si l'API répond vraiment
      double? durationMins;
      double? distKm;

      await directionsService.route(request,
          (DirectionsResult response, status) {
        if (status == DirectionsStatus.ok && response.routes!.isNotEmpty) {
          final leg = response.routes!.first.legs!.first;
          durationMins = (leg.duration!.value! / 60.0);
          distKm = (leg.distance!.value! / 1000.0);
        }
      });

      // Si l'API n'a pas répondu, on n'affiche pas de gain fictif
      if (durationMins == null || distKm == null) {
        setState(() {
          _isLoading = false;
        });
        return;
      }

// Calcul des Lames (Utilisation de doubles pour éviter le 0 intempestif)
      const double W_DIST = 5.0;
      const double W_DUREE = 0.5;

      double effort = (distKm! * W_DIST) + (durationMins! * W_DUREE);

      double mult = 1.0;
      if (_selectedTravelType == TravelType.bike) mult = 1.2;
      if (_selectedTravelType == TravelType.transit) mult = 0.8;

// Bonus de niveau, VIP, etc.
      if (widget.userProfile.nextLevelBoost > 1.0)
        effort *= widget.userProfile.nextLevelBoost;
      if (widget.userProfile.isVip) effort *= 1.15;
      if (widget.userProfile.adPoints >= 10) effort *= 1.2;

      _effortBonus = (effort * mult).round();
      double total = _effortBonus!.toDouble();

// Météo
      if (widget.weatherData != null) {
        bool isBad = widget.weatherData!.weatherCode >= 51 ||
            widget.weatherData!.temperature < 5;
        if (isBad) {
          _weatherMultiplier = 1.5;
          total *= 1.5;
        }
      }

      setState(() {
        _totalLameGain = total.round();
        if (_totalLameGain == 0 && distKm! > 0)
          _totalLameGain = 1; // Minimum 1 si trajet existe
        _durationText = "${durationMins!.round()} min";
        _isLoading = false;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = "Erreur GPS";
          _isLoading = false;
        });
    }
  }

  void _showTripDetails() {
    if (_totalLameGain == null) return;
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        showDragHandle: true,
        builder: (ctx) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Détail Gain Trajet",
                      style: Theme.of(context).textTheme.headlineSmall),
                  const Divider(),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Effort de base"),
                        Text("$_effortBonus L"),
                      ]),
                  if (_weatherMultiplier != null)
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Météo"),
                          Text("x$_weatherMultiplier",
                              style: const TextStyle(color: Colors.green)),
                        ]),
                  const Divider(),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("TOTAL",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text("$_totalLameGain L",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.amber)),
                      ]),
                  const SizedBox(height: 20),
                ],
              ),
            ));
  }

  void _showRulesDialog() {
    bool vip = widget.userProfile.isVip;
    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Info Boost"),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Statut: ${vip ? "PREMIUM" : "STANDARD"}",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: vip ? Colors.amber : Colors.grey)),
                    const SizedBox(height: 10),
                    const Text("Gain par pub :"),
                    Text(vip
                        ? "+0.02% (ou +0.4% si > 1%)"
                        : "+0.01% (ou +0.2% si > 1%)"),
                    const SizedBox(height: 10),
                    const Text("Paliers de perte (Decay) :"),
                    _ruleRow("< 0.10", "1h", "-0.01"),
                    _ruleRow("0.10", "30m", "-0.2"),
                    _ruleRow("0.20", "25m", "-0.2"),
                    _ruleRow(
                        "0.40", vip ? "15m" : "15m", vip ? "-0.2" : "-0.4"),
                    _ruleRow("0.60", vip ? "15m" : "5m", vip ? "-0.3" : "-0.6"),
                    _ruleRow("> 1.0", "5m", "Variable"),
                  ],
                ),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("OK"))
              ],
            ));
  }

  Widget _ruleRow(String range, String time, String loss) {
    return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(range), Text("$loss / $time")]);
  }

  @override
  Widget build(BuildContext context) {
// --- 1. CALCUL DE LA FIDÉLITÉ ---
    List<Widget> loyaltyWidgets = [];
    if (widget.store.loyaltyRules.isEmpty) {
      loyaltyWidgets.add(const Text("Aucun palier de fidélité configuré.",
          style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)));
    } else {
      Map<String, dynamic> storeProgress =
          widget.userProfile.loyaltyProgress[widget.store.id] ?? {};
      int visits = storeProgress['visits'] ?? 0;
      double spend = (storeProgress['spend'] as num?)?.toDouble() ?? 0.0;

      for (var rule in widget.store.loyaltyRules) {
        double progress = 0.0;
        String label = "";
        if (rule.type == 'visit') {
          progress = (visits / rule.threshold).clamp(0.0, 1.0);
          label = "${rule.threshold.toInt()} visites";
        } else {
          progress = (spend / rule.threshold).clamp(0.0, 1.0);
          label = "${rule.threshold}€ d'achats";
        }

        loyaltyWidgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Column(
            children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text("$label (-${rule.rewardPercent}%)",
                    style: const TextStyle(fontSize: 12)),
                Text("${(progress * 100).toInt()}%",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 11)),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                    progress >= 1 ? Colors.green : Colors.orange),
                minHeight: 6,
              )
            ],
          ),
        ));
      }
    }

// --- 2. LOGIQUE VISIBILITÉ & CALCUL DU TOTAL ---
    bool isGold = widget.store.isVisibilityBoostEnabled;

// Taux de base du magasin
    double baseRate = widget.store.cashbackRate * 100.0;

// Taux affiché de base (inclut le +1% si Gold)
    double displayRateBase = isGold ? baseRate + 1.0 : baseRate;

// --- CORRECTION : TOTAL = Base + Gold + Boost Actif ---
    double totalRateToDisplay = displayRateBase + _currentBoostVal;

    return Card(
// Changement de couleur de fond si Gold
      color: isGold ? const Color(0xFFFFF8E1) : Colors.white,
      margin: const EdgeInsets.only(bottom: 16.0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.0),
// Bordure dorée si Gold
        side: isGold
            ? const BorderSide(color: Colors.amber, width: 2.0)
            : BorderSide.none,
      ),
      elevation: isGold ? 6 : 3,
      child: Container(
// Dégradé subtil pour effet "Premium" si Gold
        decoration: isGold
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(12.0),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.white, Colors.amber.shade50, Colors.white],
                ),
              )
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
// --- HEADER MAGASIN ---
              Row(
                children: [
// Icône changeante
                  Icon(Icons.storefront,
                      color: isGold ? Colors.amber[800] : primaryGreen,
                      size: 30),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(
                          children: [
                            Flexible(
                                child: Text(widget.store.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18))),
// Badge Vérifié si Gold
                            if (isGold) ...[
                              const SizedBox(width: 5),
                              const Icon(Icons.verified,
                                  color: Colors.amber, size: 18),
                            ]
                          ],
                        ),
                        Text(widget.store.address,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text(
                            widget.store.description.isNotEmpty
                                ? widget.store.description
                                : 'Aucune description',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.black87,
                                fontSize: 12,
                                fontStyle: FontStyle.italic)),
                      ])),

// --- BLOC TAUX CASHBACK (CORRIGÉ) ---
                  InkWell(
                    onTap: _showTripDetails,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: isGold ? Colors.amber[100] : Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isGold ? Colors.amber[700]! : Colors.green),
                        boxShadow: isGold
                            ? [
                                BoxShadow(
                                    color: Colors.amber.withOpacity(0.3),
                                    blurRadius: 4)
                              ]
                            : null,
                      ),
                      child: Column(
                        children: [
// AFFICHE LE TOTAL (Base + Boost)
                          Text("${totalRateToDisplay.toStringAsFixed(1)}%",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: isGold
                                      ? Colors.black87
                                      : Colors.green[800])),
                          const Text("Cashback Total",
                              style: TextStyle(fontSize: 9)),

// Indication du boost si actif
                          if (_currentBoostVal > 0)
                            Text(
                                "(dont +${_currentBoostVal.toStringAsFixed(1)} boost)",
                                style: const TextStyle(
                                    fontSize: 8,
                                    color: Colors.purple,
                                    fontWeight: FontWeight.bold)),

                          if (isGold)
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4)),
                              child: const Text("+1% BONUS",
                                  style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Bouton Favori
                  IconButton(
                    onPressed: _toggleFavorite,
                    icon: Icon(
                      _isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: _isFavorite ? Colors.red : Colors.grey,
                    ),
                    tooltip: _isFavorite
                        ? "Retirer des favoris"
                        : "Ajouter aux favoris",
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(widget.store.description,
                  style: const TextStyle(fontSize: 13)),
              const Divider(),

// --- SECTION BOOST CASHBACK ---
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.purple.withOpacity(0.2))),
                child: Column(
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            const Icon(Icons.bolt, color: Colors.purple),
                            const SizedBox(width: 5),
                            const Text("Boost Cashback",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.purple)),
                            IconButton(
                                icon: const Icon(Icons.info_outline,
                                    size: 16, color: Colors.grey),
                                onPressed: _showRulesDialog)
                          ]),
// Affiche uniquement la valeur du boost ajouté
                          Text("+${_currentBoostVal.toStringAsFixed(2)}%",
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple))
                        ]),
                    if (_currentBoostVal > 0)
                      Align(
                          alignment: Alignment.centerRight,
                          child: Text(_boostStatusText,
                              style: TextStyle(
                                  color: Colors.red[800],
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold))),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _watchAdForBoost,
                        icon: const Icon(Icons.play_circle_fill),
                        label: const Text("Regarder une pub (+Boost)"),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple,
                            foregroundColor: Colors.white),
                      ),
                    )
                  ],
                ),
              ),
              if (widget.store.loyaltyRules.isNotEmpty) ...[
                const SizedBox(height: 15),

// --- SECTION FIDELITÉ ---
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.stars, color: Colors.amber[900], size: 18),
                        const SizedBox(width: 8),
                        Text("Votre Fidélité",
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.amber[900])),
                      ]),
                      const SizedBox(height: 8),
                      ...loyaltyWidgets
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 15),

// --- ACTIONS (Y ALLER + HISTORIQUE + VALIDER conditionnel) ---
              Builder(builder: (context) {
                // Calculer si le bouton Valider doit être affiché
                final completedAt = widget.tripCompletedAt;
                bool canValidate = false;
                String? validateExpiry;

                if (completedAt != null) {
                  final now = DateTime.now();
                  if (widget.userProfile.isVip) {
                    // Premium : 24h pour valider
                    canValidate = now.difference(completedAt).inHours < 24;
                    if (canValidate) {
                      final remaining =
                          24 - now.difference(completedAt).inHours;
                      validateExpiry = "Encore $remaining h (Premium)";
                    }
                  } else {
                    // Standard : fenêtre ouverte (à fermer via détection retour domicile)
                    canValidate = true;
                  }
                }

                return Column(
                  children: [
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => widget.onStartTrip(
                              widget.store, _selectedTravelType),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color:
                                    isGold ? Colors.amber[700]! : primaryGreen),
                            foregroundColor:
                                isGold ? Colors.amber[900]! : primaryGreen,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.near_me),
                              const SizedBox(width: 5),
                              Text(
                                  "Y aller ${_totalLameGain != null ? '($_totalLameGain L)' : ''}"),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon:
                            const Icon(Icons.receipt_long, color: Colors.teal),
                        tooltip: "Historique cashback",
                        onPressed: _showCashbackHistory,
                      ),
                      if (canValidate) ...[
                        const SizedBox(width: 4),
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.receipt),
                            label: const Text("Valider"),
                            onPressed: _onValidatePurchase,
                            style: ElevatedButton.styleFrom(
                                backgroundColor: primaryGreen,
                                foregroundColor: Colors.white),
                          ),
                        ),
                      ],
                    ]),
                    if (canValidate && validateExpiry != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(validateExpiry,
                            style: const TextStyle(
                                fontSize: 10,
                                color: Colors.orange,
                                fontStyle: FontStyle.italic)),
                      ),
                    if (canValidate && !widget.userProfile.isVip)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "Valider avant de rentrer chez vous",
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey[600],
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  // ===================================================================
  // 🧾 VALIDATION + SCAN TICKET + CASHBACK
  // ===================================================================

  void _onValidatePurchase() {
    final lameGain = _totalLameGain ?? 0;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Column(children: [
          Icon(Icons.emoji_events, size: 45, color: Colors.amber),
          SizedBox(height: 8),
          Text("Visite validée !",
              style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_fire_department, color: Colors.green),
                  const SizedBox(width: 8),
                  Text("+$lameGain Lames gagnées !",
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Voulez-vous scanner votre ticket de caisse pour obtenir du cashback ?",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onAddLame(lameGain, source: "Visite ${widget.store.name}");
            },
            child: const Text("Passer"),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text("Scanner le ticket"),
            style: ElevatedButton.styleFrom(
                backgroundColor: primaryGreen, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              widget.onAddLame(lameGain, source: "Visite ${widget.store.name}");
              _startReceiptScan();
            },
          ),
        ],
      ),
    );
  }

  void _startReceiptScan() async {
    final ImagePicker picker = ImagePicker();
    // Caméra uniquement (anti-triche)
    final XFile? photo = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (photo == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const AlertDialog(
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text("Analyse du ticket (serveur sécurisé)..."),
        ]),
      ),
    );

    try {
      final ocrResult = await _performSecureOCR(photo.path);
      final rawText = ocrResult['text'] as String? ?? '';
      final bool serverValid = ocrResult['serverValid'] == true;
      final String serverReason = ocrResult['serverReason'] as String? ?? '';

      if (rawText.isEmpty) {
        if (Get.isDialogOpen ?? false) Get.back();
        _showReceiptRejectedDialog(
            '❌ Erreur OCR: Impossible de lire le ticket. Veuillez réessayer.');
        return;
      }

      if (Get.isDialogOpen ?? false) Get.back();
      if (!mounted) return;

      // Vérification finale (règles serveur Gemini + validation locale de date/heure)
      final check =
          await _verifyReceiptWithGemini(rawText, serverValid, serverReason);

      if (!(check['valid'] as bool)) {
        _showReceiptRejectedDialog(check['reason'] as String);
        return;
      }

      final amount = _parseReceiptAmount(rawText);
      if (amount == null) {
        _showManualAmountEntry(rawText);
      } else {
        _showCashbackPopup(amount, rawText);
      }
    } catch (e) {
      if (Get.isDialogOpen ?? false) Get.back();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Erreur analyse: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _verifyReceiptWithGemini(
      String rawText, bool serverValid, String serverReason) async {
    if (!serverValid) {
      return {
        'valid': false,
        'reason':
            '❌ Refusé par l\'IA: ${serverReason.isNotEmpty ? serverReason : 'Ticket invalide ou falsifié.'}'
      };
    }
    // Effectuer la vérification locale de date et d'enseigne
    return _verifyReceiptValidity(rawText);
  }

  /// Secure OCR & Gemini AI via Firebase Cloud Function (Server-side)
  /// The Cloud Function handles Document AI & Gemini processing with server credentials
  Future<Map<String, dynamic>> _performSecureOCR(String imagePath) async {
    try {
      final File imageFile = File(imagePath);
      final bytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(bytes);

      // Call Firebase Cloud Function (secure, server-side processing)
      final HttpsCallable callable =
          FirebaseFunctions.instance.httpsCallable('processReceiptOCR');
      final response = await callable.call({
        'imageBase64': base64Image,
        'mimeType': 'image/jpeg',
        'storeName': widget.store.name,
      });

      if (response.data != null && response.data['text'] != null) {
        final extractedText = response.data['text'] as String;
        final bool serverValid = response.data['valid'] == true;
        final String serverReason = response.data['reason'] as String? ?? '';
        debugPrint(
            '[OCR & Gemini] Recognized text via Cloud Function: ${extractedText.length} chars (Valid: $serverValid)');
        return {
          'text': extractedText,
          'serverValid': serverValid,
          'serverReason': serverReason,
        };
      }

      final fallbackText = await _fallbackMLKitOCR(imagePath);
      return {
        'text': fallbackText,
        'serverValid': true,
        'serverReason': '',
      };
    } catch (e) {
      debugPrint(
          '[OCR] Cloud Function error: $e. Falling back to local ML Kit.');
      final fallbackText = await _fallbackMLKitOCR(imagePath);
      return {
        'text': fallbackText,
        'serverValid': true,
        'serverReason': '',
      };
    }
  }

  /// Fallback: Local Google ML Kit OCR (device-only, no external calls)
  Future<String?> _fallbackMLKitOCR(String imagePath) async {
    try {
      final inputImage = InputImage.fromFilePath(imagePath);
      final textRecognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognized =
          await textRecognizer.processImage(inputImage);
      await textRecognizer.close();
      debugPrint(
          '[MLKit] Local OCR completed: ${recognized.text.length} characters');
      return recognized.text;
    } catch (e) {
      debugPrint('[MLKit] Local OCR failed: $e');
      return null;
    }
  }

  Map<String, dynamic> _verifyReceiptValidity(String rawText) {
    final textLower = rawText.toLowerCase();
    final now = DateTime.now();

    // ── 1. Vérification du nom de l'enseigne ──────────────────────────────
    // On cherche au moins 1 mot significatif du nom ou de l'adresse dans le ticket
    bool storeFound = false;

    // Mots du nom du magasin (>3 lettres)
    final storeWords = widget.store.name
        .toLowerCase()
        .split(RegExp(r'[\s\-\./,]+'))
        .where((w) => w.length > 3)
        .toList();
    if (storeWords.any((w) => textLower.contains(w))) storeFound = true;

    // Mots de l'adresse (>4 lettres) — plan B
    if (!storeFound) {
      final addrWords = widget.store.address
          .toLowerCase()
          .split(RegExp(r'[\s\-\./,]+'))
          .where((w) => w.length > 4)
          .toList();
      if (addrWords.any((w) => textLower.contains(w))) storeFound = true;
    }

    if (!storeFound) {
      return {
        'valid': false,
        'reason':
            '❌ Ce ticket ne correspond pas au magasin "${widget.store.name}".\n\nAssurez-vous de scanner le ticket du bon magasin.'
      };
    }

    // ── 2. Extraction de la date et heure du ticket ───────────────────────
    // Pattern 1 : date complète  DD/MM/YYYY HH:MM  ou  DD/MM/YYYY HH:MM:SS
    final patternDateFull = RegExp(
        r'(\d{2})[/\-\.](\d{2})[/\-\.](\d{2,4})\s+(\d{1,2})[h:hH](\d{2})(?:[:\s](\d{2}))?');
    // Pattern 2 : heure seule  HH:MM  ou  HHhMM
    final patternTimeOnly = RegExp(r'\b(\d{1,2})[hH:](\d{2})(?::(\d{2}))?\b');

    DateTime? receiptDateTime;

    // Essai pattern date complète
    for (final m in patternDateFull.allMatches(rawText)) {
      try {
        int day = int.parse(m.group(1)!);
        int month = int.parse(m.group(2)!);
        int year = int.parse(m.group(3)!);
        int hour = int.parse(m.group(4)!);
        int minute = int.parse(m.group(5)!);
        if (year < 100) year += 2000;
        if (day >= 1 &&
            day <= 31 &&
            month >= 1 &&
            month <= 12 &&
            hour >= 0 &&
            hour < 24 &&
            minute >= 0 &&
            minute < 60) {
          final candidate = DateTime(year, month, day, hour, minute);
          // Prend la date la plus récente trouvée (évite dates de péremption etc.)
          if (receiptDateTime == null || candidate.isAfter(receiptDateTime)) {
            receiptDateTime = candidate;
          }
        }
      } catch (_) {}
    }

    // Essai pattern heure seule (si pas de date complète trouvée)
    if (receiptDateTime == null) {
      // Cherche toutes les heures et prend la dernière (souvent l'heure de passage)
      DateTime? lastTime;
      for (final m in patternTimeOnly.allMatches(rawText)) {
        try {
          int h = int.parse(m.group(1)!);
          int min = int.parse(m.group(2)!);
          if (h >= 0 && h < 24 && min >= 0 && min < 60) {
            // Ignore les heures qui ressemblent à des dates (ex: 20:02)
            final candidate = DateTime(now.year, now.month, now.day, h, min);
            // On ignore si ça ressemble à une date jj:mm (ex: 20/02 → 20h02 faux positif)
            if (h <= 23 && min <= 59) {
              if (lastTime == null ||
                  candidate.hour > lastTime.hour ||
                  (candidate.hour == lastTime.hour &&
                      candidate.minute > lastTime.minute)) {
                lastTime = candidate;
              }
            }
          }
        } catch (_) {}
      }
      if (lastTime != null) {
        receiptDateTime = lastTime;
        // Si l'heure ticket est dans le futur, c'est un ticket de la veille
        if (receiptDateTime!.isAfter(now)) {
          receiptDateTime = receiptDateTime!.subtract(const Duration(days: 1));
        }
      }
    }

    // ── 3. Vérification délai ≤ 2h ────────────────────────────────────────
    if (receiptDateTime != null) {
      final diff = now.difference(receiptDateTime!);
      if (diff.isNegative) {
        // Ticket dans le futur — probablement mauvaise date, on accepte avec bénéfice du doute
      } else if (diff.inMinutes > 120) {
        final ticketStr =
            '${receiptDateTime!.day.toString().padLeft(2, '0')}/${receiptDateTime!.month.toString().padLeft(2, '0')}/${receiptDateTime!.year} '
            '${receiptDateTime!.hour.toString().padLeft(2, '0')}:${receiptDateTime!.minute.toString().padLeft(2, '0')}';
        return {
          'valid': false,
          'reason':
              '⏱ Ce ticket date de plus de 2 heures.\n\nHeure sur le ticket : $ticketStr\nHeure actuelle : ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}\n\nSeuls les achats des 2 dernières heures sont acceptés.'
        };
      }
      // Entre 0 et 120 min → OK
    }
    // Si aucune heure trouvée → accepté (bénéfice du doute)

    return {'valid': true, 'reason': ''};
  }

  void _showReceiptRejectedDialog(String reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.error_outline, color: Colors.red),
          SizedBox(width: 8),
          Text("Ticket invalide"),
        ]),
        content: Text(reason),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("Fermer")),
          ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text("Réessayer"),
            onPressed: () {
              Navigator.pop(ctx);
              _startReceiptScan();
            },
          ),
        ],
      ),
    );
  }

  double? _parseReceiptAmount(String text) {
    final patterns = [
      RegExp(
          r'(?:TOTAL|TOTAL TTC|NET À PAYER|À PAYER|MONTANT|SOLDE)[^\d]*(\d+[,\.]\d{2})',
          caseSensitive: false),
      RegExp(r'(\d+[,\.]\d{2})\s*(?:EUR|€)', caseSensitive: false),
      RegExp(r'(?:EUR|€)\s*(\d+[,\.]\d{2})', caseSensitive: false),
    ];
    final candidates = <double>[];
    for (final p in patterns) {
      for (final m in p.allMatches(text)) {
        final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
        if (v != null && v > 0.5) candidates.add(v);
      }
    }
    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.compareTo(a));
    return candidates.first;
  }

  void _showManualAmountEntry(String rawText) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Montant non détecté"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text("Saisissez le montant total de l'achat :"),
          const SizedBox(height: 16),
          TextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: "Montant (€)",
              prefixIcon: Icon(Icons.euro),
              border: OutlineInputBorder(),
            ),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (v != null && v > 0) {
                Navigator.pop(ctx);
                _showCashbackPopup(v, rawText);
              }
            },
            child: const Text("Valider"),
          ),
        ],
      ),
    );
  }
// Add this method inside class _StoreCardState

  Map<String, dynamic> _calculateUserLevel(int totalLame) {
    int currentLevel = 1;
    int lameNeeded = 500; // Pour le niveau 2
    int totalLameForCurrentLevel = 0;

    // Calculer le niveau actuel
    while (totalLame >= totalLameForCurrentLevel + lameNeeded &&
        currentLevel < 50) {
      totalLameForCurrentLevel += lameNeeded;
      currentLevel++;
      lameNeeded *= 2; // Double à chaque niveau
    }

    // Calculer les Lame nécessaires pour le niveau suivant
    int lameForNextLevel = totalLameForCurrentLevel + lameNeeded;

    // Calculer le progrès vers le niveau suivant
    double progressToNextLevel = 0.0;
    if (currentLevel < 50) {
      int lameInCurrentLevel = totalLame - totalLameForCurrentLevel;
      progressToNextLevel = lameInCurrentLevel / lameNeeded;
      progressToNextLevel = progressToNextLevel.clamp(0.0, 1.0);
    }

    return {
      'currentLevel': currentLevel,
      'lameForCurrentLevel': totalLameForCurrentLevel,
      'lameForNextLevel': lameForNextLevel,
      'progressToNextLevel': progressToNextLevel,
    };
  }

  void _showCashbackPopup(double amountSpent, String rawText) {
    final store = widget.store;
    final profile = widget.userProfile;

    double baseRate = store.cashbackRate * 100.0;
    if (store.isVisibilityBoostEnabled) baseRate += 1.0;
    final boostAddon = _currentBoostVal;

    double loyaltyDiscount = 0.0;
    String loyaltyTierLabel = "";
    final progress = profile.loyaltyProgress[store.id] ?? {};
    final visits = progress['visits'] as int? ?? 0;
    final spend = (progress['spend'] as num?)?.toDouble() ?? 0.0;
    for (final rule in store.loyaltyRules) {
      final reached = rule.type == 'visit'
          ? visits >= rule.threshold
          : spend >= rule.threshold;
      if (reached && rule.rewardPercent > loyaltyDiscount) {
        loyaltyDiscount = rule.rewardPercent;
        loyaltyTierLabel = rule.type == 'visit'
            ? "Palier ${rule.threshold.toInt()} visites"
            : "Palier ${rule.threshold}€";
      }
    }

    final totalRate = baseRate + boostAddon + loyaltyDiscount;
    final cashbackAmount = amountSpent * (totalRate / 100.0);

    // NOUVEAU : Application du multiplicateur de niveau
    final levelData = _calculateUserLevel(profile.totalLameEarned ?? 0);
    final int currentLevel = (levelData['currentLevel'] as num?)?.toInt() ?? 1;
    final double levelMultiplier = 1.0 + (currentLevel * 0.01);
    final lameBonus = ((cashbackAmount * 10) * levelMultiplier).round();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(children: [
                  Icon(Icons.card_giftcard, color: Colors.green),
                  SizedBox(width: 8),
                  Text("Votre Cashback",
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 20),
                _cbRow(
                    "Montant dépensé", "${amountSpent.toStringAsFixed(2)} €"),
                const Divider(),
                _cbRow("Cashback de base",
                    "${(store.cashbackRate * 100).toStringAsFixed(1)}%"),
                if (store.isVisibilityBoostEnabled)
                  _cbRow("+1% Bonus Or", "+1.0%", color: Colors.amber[800]),
                if (boostAddon > 0)
                  _cbRow("Boost Pub", "+${boostAddon.toStringAsFixed(2)}%",
                      color: Colors.purple),
                if (loyaltyDiscount > 0)
                  _cbRow(loyaltyTierLabel,
                      "+${loyaltyDiscount.toStringAsFixed(1)}%",
                      color: Colors.orange),
                _cbRow("Taux total", "${totalRate.toStringAsFixed(2)}%",
                    bold: true, color: Colors.green),
                const Divider(),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Column(children: [
                    Text("${cashbackAmount.toStringAsFixed(2)} €",
                        style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.green)),
                    const Text("de cashback obtenu",
                        style: TextStyle(color: Colors.grey)),
                    if (lameBonus > 0) ...[
                      const SizedBox(height: 6),
                      Text("+$lameBonus Lames bonus",
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: accentGold)),
                    ],
                  ]),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check),
                    label:
                        const Text("Récupérer", style: TextStyle(fontSize: 16)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: primaryGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(15))),
                    onPressed: () {
                      Navigator.pop(ctx);
                      _saveCashback(amountSpent, cashbackAmount, lameBonus,
                          totalRate, rawText, loyaltyTierLabel);
                    },
                  ),
                )
              ]),
        ),
      ),
    );
  }

  Widget _cbRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(value,
            style: TextStyle(
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              color: color ?? Colors.black87,
              fontSize: bold ? 15 : 13,
            )),
      ]),
    );
  }

  Future<void> _saveCashback(
      double amountSpent,
      double cashbackAmount,
      int lameBonus,
      double rateApplied,
      String rawText,
      String loyaltyTier) async {
    try {
      final uid = widget.userProfile.id;
      final storeId = widget.store.id;
      final now = Timestamp.now();
      final batch = FirebaseFirestore.instance.batch();

      // 1. Historique cashback utilisateur
      batch.set(
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('cashback_history')
            .doc(),
        {
          'store_id': storeId,
          'store_name': widget.store.name,
          'amount_spent': amountSpent,
          'cashback_amount': cashbackAmount,
          'cashback_rate_applied': rateApplied,
          'lame_points_earned': lameBonus,
          'loyalty_tier_applied': loyaltyTier.isEmpty ? null : loyaltyTier,
          'receipt_text_raw': rawText,
          'timestamp': now,
        },
      );

      // 2. Transaction dans le magasin (espace commerçant)
      batch.set(
        FirebaseFirestore.instance
            .collection('stores')
            .doc(storeId)
            .collection('store_transactions')
            .doc(),
        {
          'user_id': uid,
          'username': widget.userProfile.username,
          'amount_spent': amountSpent,
          'cashback_given': cashbackAmount,
          'rate_applied': rateApplied,
          'loyalty_tier': loyaltyTier.isEmpty ? null : loyaltyTier,
          'timestamp': now,
        },
      );

      // 3. Stats globales magasin
      batch.update(
          FirebaseFirestore.instance.collection('stores').doc(storeId), {
        'totalAmountSpentByUser': FieldValue.increment(amountSpent),
        'totalCashbackGiven': FieldValue.increment(cashbackAmount),
      });

      // 4. Fidélité utilisateur
      batch.update(FirebaseFirestore.instance.collection('users').doc(uid), {
        'loyalty_progress.$storeId.visits': FieldValue.increment(1),
        'loyalty_progress.$storeId.spend': FieldValue.increment(amountSpent),
      });

      await batch.commit();

      if (lameBonus > 0)
        widget.onAddLame(lameBonus, source: "Cashback ${widget.store.name}");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              "✅ Cashback ${cashbackAmount.toStringAsFixed(2)}€ enregistré !${lameBonus > 0 ? ' +$lameBonus Lames' : ''}"),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCashbackHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _CashbackHistorySheet(
        userId: widget.userProfile.id,
        storeId: widget.store.id,
        storeName: widget.store.name,
      ),
    );
  }
}

// ===================================================================
// 📋 HISTORIQUE CASHBACK UTILISATEUR (Sheet)
// ===================================================================
class _CashbackHistorySheet extends StatelessWidget {
  final String userId;
  final String storeId;
  final String storeName;
  const _CashbackHistorySheet(
      {required this.userId, required this.storeId, required this.storeName});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.receipt_long, color: Colors.teal),
          const SizedBox(width: 8),
          Expanded(
              child: Text("Historique — $storeName",
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16))),
          IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context)),
        ]),
        const Divider(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .collection('cashback_history')
                .where('store_id', isEqualTo: storeId)
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData)
                return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(
                    child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 60, color: Colors.grey),
                    SizedBox(height: 12),
                    Text("Aucun cashback enregistré pour ce magasin.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey)),
                  ],
                ));
              }
              double totalSpent = 0, totalCashback = 0;
              for (final d in docs) {
                final m = d.data() as Map<String, dynamic>;
                totalSpent += (m['amount_spent'] as num?)?.toDouble() ?? 0;
                totalCashback +=
                    (m['cashback_amount'] as num?)?.toDouble() ?? 0;
              }
              return Column(children: [
                // Résumé
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.withOpacity(0.3)),
                  ),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _summaryChip("${totalSpent.toStringAsFixed(2)}€",
                            "Total dépensé", Colors.blue),
                        Container(
                            width: 1, height: 40, color: Colors.grey[300]),
                        _summaryChip("${totalCashback.toStringAsFixed(2)}€",
                            "Cashback total", Colors.green),
                        Container(
                            width: 1, height: 40, color: Colors.grey[300]),
                        _summaryChip(
                            "${docs.length}", "Visites", Colors.purple),
                      ]),
                ),
                Expanded(
                    child: ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final ts = (d['timestamp'] as Timestamp?)?.toDate();
                    final spent =
                        (d['amount_spent'] as num?)?.toDouble() ?? 0.0;
                    final cb =
                        (d['cashback_amount'] as num?)?.toDouble() ?? 0.0;
                    final rate =
                        (d['cashback_rate_applied'] as num?)?.toDouble() ?? 0.0;
                    final lames = d['lame_points_earned'] as int? ?? 0;
                    final tier = d['loyalty_tier_applied'] as String?;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.green.withOpacity(0.12),
                        child: Text("${cb.toStringAsFixed(1)}€",
                            style: const TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.bold)),
                      ),
                      title: Text(
                          "${spent.toStringAsFixed(2)}€ → ${cb.toStringAsFixed(2)}€ (${rate.toStringAsFixed(1)}%)"),
                      subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (lames > 0)
                              Text("+$lames Lames",
                                  style: const TextStyle(
                                      color: accentGold,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12)),
                            if (tier != null && tier.isNotEmpty)
                              Text(tier,
                                  style: const TextStyle(
                                      fontSize: 11, color: Colors.orange)),
                            if (ts != null)
                              Text(
                                "${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}/${ts.year}  ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}",
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey),
                              ),
                          ]),
                    );
                  },
                )),
              ]);
            },
          ),
        ),
      ]),
    );
  }

  Widget _summaryChip(String value, String label, Color color) {
    return Column(children: [
      Text(value,
          style: TextStyle(
              fontWeight: FontWeight.bold, fontSize: 17, color: color)),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }
}

class ShopScreen extends StatelessWidget {
  final UserProfile userProfile;

  final Function(int cost) onPurchase;

  ShopScreen({Key? key, required this.userProfile, required this.onPurchase})
      : super(key: key);

  // Dans la classe ShopScreen :

  Future<void> _buyItem(BuildContext context, ShopItem item) async {
    if (userProfile.lamePoints < item.costLame) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Pas assez de Lame Points!"),
          backgroundColor: Colors.red));
      return;
    }

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Confirmer l\'achat'),
        content: Text(
            'Voulez-vous acheter "${item.name}" pour ${item.costLame} Lame Points?'),
        actions: <Widget>[
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Acheter')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // 1. Enregistrement de l'offre réclamée (la déduction des Lames est gérée par le serveur via purchaseShopItem)
        WriteBatch batch = FirebaseFirestore.instance.batch();

        DocumentReference historyRef =
            FirebaseFirestore.instance.collection('user_claimed_offers').doc();
        batch.set(historyRef, {
          'user_id': userProfile.id,
          'reward_id': item.id,
          'details': {
            'offer_title': "Achat Boutique : ${item.name}",
            'claimed_for_lame': item.costLame.toDouble(),
          },
          'claimed_at': FieldValue.serverTimestamp(),
          'status':
              'approved', // Validé automatiquement car c'est un achat boutique
        });

        await batch.commit();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('${item.name} acheté!'),
              backgroundColor: Colors.green));
        }

        // Mise à jour UI locale
        onPurchase(item.costLame);

        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Erreur lors de l\'achat: $e'),
              backgroundColor: Colors.red));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Boutique EcoNav')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection('shop_items')
            .orderBy('cost_lame')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: primaryGreen));
          }
          if (snapshot.hasError)
            return Center(child: Text('Erreur: ${snapshot.error}'));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Boutique vide.'));
          }

          final items = snapshot.data!.docs
              .map((doc) => ShopItem.fromFirestore(doc))
              .toList();
          return GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.8),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final canAfford = userProfile.lamePoints >= item.costLame;
              return Card(
                elevation: 3,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: canAfford ? () => _buyItem(context, item) : null,
                  child: Opacity(
                    opacity: canAfford ? 1.0 : 0.6,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Icon(item.icon,
                              size: 40,
                              color: canAfford ? primaryGreen : textGrey),
                          Text(item.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)),
                          Text(item.type,
                              style: const TextStyle(
                                  fontSize: 12, color: textGrey)),
                          Chip(
                            label: Text('${item.costLame} L',
                                style: TextStyle(
                                    color: canAfford
                                        ? accentGold
                                        : Colors.red.shade700,
                                    fontWeight: FontWeight.bold)),
                            backgroundColor: canAfford
                                ? accentGold.withOpacity(0.2)
                                : Colors.red.withOpacity(0.1),
                            avatar: Icon(Icons.eco_rounded,
                                color: canAfford
                                    ? accentGold
                                    : Colors.red.shade700,
                                size: 16),
                          ),
                          if (!canAfford)
                            const Text("Fonds insuffisants",
                                style:
                                    TextStyle(color: Colors.red, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class ProfileBottomSheet extends StatelessWidget {
  final UserProfile userProfile;
  final VoidCallback onOpenShop;
  final ScrollController? scrollController; // CORRIGÉ

  const ProfileBottomSheet({
    Key? key,
    required this.userProfile,
    required this.onOpenShop,
    this.scrollController, // CORRIGÉ
  }) : super(key: key);

  // --- 1. FONCTION POUR ENVOYER LA NOTIFICATION ---
  // --- 1. FONCTION POUR ENVOYER LA NOTIFICATION (CORRIGÉE) ---
  Future<void> _sendHomeSavedNotification() async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    // DÉBUT CORRECTION : Ajout de 'icon' pour éviter le NullPointerException
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'econav_general', // ID du canal
      'EcoNav Général', // Nom du canal
      channelDescription: 'Notifications générales de l\'application',
      importance: Importance.max,
      priority: Priority.high,
      ticker: 'ticker',
      icon: '@mipmap/ic_launcher', // <--- LIGNE CRUCIALE AJOUTÉE
    );
    // FIN CORRECTION

    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);

    try {
      await flutterLocalNotificationsPlugin.show(
          999, // ID unique notif
          'Domicile Configuré ! 🏠',
          'Le suivi automatique est activé. Nous détecterons vos départs et retours.',
          platformChannelSpecifics);
    } catch (e) {
      print("Erreur affichage notification : $e");
    }
  }

  // --- 2. LOGIQUE SAUVEGARDE ADRESSE ---
  // --- 2. LOGIQUE SAUVEGARDE ADRESSE (avec restriction 1 fois/an) ---
  void _handleSetHomeAddress(BuildContext context) {
    final HomeController homeController = Get.find<HomeController>();

    // Vérifier la restriction 1 fois/an (sauf pour les utilisateurs Premium)
    if (!userProfile.isVip && userProfile.lastAddressUpdateTime != null) {
      final lastUpdate = userProfile.lastAddressUpdateTime!.toDate();
      final oneYearAgo = DateTime.now().subtract(const Duration(days: 365));
      if (lastUpdate.isAfter(oneYearAgo)) {
        final nextAllowedDate = lastUpdate.add(const Duration(days: 365));
        final daysRemaining = nextAllowedDate.difference(DateTime.now()).inDays;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.lock_clock, color: Colors.orange),
              SizedBox(width: 8),
              Text("Modification limitée"),
            ]),
            content: Text(
              "Vous avez déjà défini votre adresse de domicile récemment.\n\n"
              "La modification n'est possible qu'une fois par an.\n"
              "Prochaine modification disponible dans : $daysRemaining jours.\n\n"
              "Les membres Premium peuvent modifier sans restriction.",
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Compris")),
            ],
          ),
        );
        return;
      }
    }

    showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text("Adresse de Domicile"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "Cette adresse sert de point de référence pour démarrer et valider vos trajets automatiques.",
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                  if (!userProfile.isVip)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.4)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.info_outline,
                            color: Colors.orange, size: 16),
                        SizedBox(width: 6),
                        Expanded(
                            child: Text(
                                "Modifiable 1 fois par an (illimité avec Premium)",
                                style: TextStyle(
                                    fontSize: 11, color: Colors.orange))),
                      ]),
                    ),
                  const SizedBox(height: 16),

                  // OPTION A : POSITION ACTUELLE
                  ElevatedButton.icon(
                    icon: const Icon(Icons.my_location),
                    label: const Text("Utiliser ma position actuelle"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 45)),
                    onPressed: () async {
                      // CORRECTION : Utiliser Navigator pour fermer showDialog proprement
                      Navigator.of(ctx).pop();

                      // Loader
                      Get.dialog(
                          const Center(child: CircularProgressIndicator()),
                          barrierDismissible: false);

                      try {
                        Position p = await Geolocator.getCurrentPosition(
                            desiredAccuracy: LocationAccuracy.high);

                        // Sauvegarde dans le Controller
                        await homeController.defineHomeAddress(
                            "Position GPS actuelle",
                            LatLng(p.latitude, p.longitude));

                        // Ferme le loader (Get.back est ok ici car c'est un Get.dialog)
                        if (Get.isDialogOpen ?? false) Get.back();

                        // ENVOI NOTIFICATION IMMEDIATE
                        await _sendHomeSavedNotification();
                      } catch (e) {
                        // Ferme le loader en cas d'erreur
                        if (Get.isDialogOpen ?? false) Get.back();

                        Get.snackbar(
                            "Erreur", "Impossible de récupérer la position: $e",
                            backgroundColor: Colors.red,
                            colorText: Colors.white);
                      }
                    },
                  ),
                  const SizedBox(height: 10),

                  // OPTION B : RECHERCHE MANUELLE
                  OutlinedButton.icon(
                    icon: const Icon(Icons.search),
                    label: const Text("Rechercher une adresse"),
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 45)),
                    onPressed: () {
                      // CORRECTION : Fermer le dialogue proprement
                      Navigator.of(ctx).pop();

                      // Ouvre un BottomSheet avec la barre de recherche existante
                      Get.bottomSheet(Container(
                        color: Colors.white,
                        padding: const EdgeInsets.all(20),
                        height: 400,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Rechercher votre adresse",
                                style: GoogleFonts.poppins(
                                    fontWeight: FontWeight.bold, fontSize: 18)),
                            PhotonSearchBar(onSelected: (name, coords) async {
                              // Sauvegarde
                              await homeController.defineHomeAddress(
                                  name, coords);

                              // Ferme la recherche
                              if (Get.isBottomSheetOpen ?? false) Get.back();

                              // ENVOI NOTIFICATION IMMEDIATE
                              await _sendHomeSavedNotification();
                            }),
                          ],
                        ),
                      ));
                    },
                  )
                ],
              ),
            ));
  }

  // --- LOGIQUE VIP (EXISTANT) ---
  void _removeVipSubscription(BuildContext context) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text("Confirmer")
          ]),
          content: const Text(
              "Voulez-vous vraiment supprimer votre abonnement VIP ?"),
          actions: <Widget>[
            TextButton(
                child: const Text("Annuler"),
                onPressed: () => Navigator.of(dialogContext).pop(false)),
            ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("Supprimer VIP"),
                onPressed: () => Navigator.of(dialogContext).pop(true)),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userProfile.id)
            .update({
          'is_vip': false,
          'updated_at': FieldValue.serverTimestamp(),
        });
        Navigator.pop(context); // Ferme sheet
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Abonnement VIP supprimé"),
            backgroundColor: Colors.green));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _showPremiumDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.workspace_premium, color: Color(0xFFFFB300), size: 28),
            SizedBox(width: 8),
            Text("Abonnement Premium"),
          ]),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Débloquez tous les avantages exclusifs :",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _premiumBenefitRow(Icons.add_road, "Déviation tolérée : 6 km",
                    "Au lieu de 3 km en standard"),
                _premiumBenefitRow(Icons.bolt, "x2 Lames sur chaque trajet",
                    "Multipliez vos gains"),
                _premiumBenefitRow(Icons.percent, "+15% Cashback magasins",
                    "Plus de réductions"),
                _premiumBenefitRow(Icons.trending_up,
                    "Multiplicateur Ad Points", "Boostez votre progression"),
                _premiumBenefitRow(Icons.star, "Niveau max débloqué",
                    "Progressez sans limite"),
                _premiumBenefitRow(
                    Icons.cached, "Pub boost double", "Cashback boosté x2"),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB300).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFB300)),
                  ),
                  child: const Text(
                    "🏆 Niveau 30 : Premium OFFERT automatiquement !",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
                child: const Text("Fermer"),
                onPressed: () => Navigator.of(dialogContext).pop()),
            if (!userProfile.isVip)
              ElevatedButton.icon(
                icon: const Icon(Icons.workspace_premium, size: 16),
                label: const Text("Devenir Premium"),
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB300),
                    foregroundColor: Colors.black),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(userProfile.id)
                      .update({'is_vip': true});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("✅ Premium activé !"),
                        backgroundColor: Colors.green),
                  );
                },
              ),
          ],
        );
      },
    );
  }

  Widget _premiumBenefitRow(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, color: const Color(0xFFFFB300), size: 20),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ])),
      ]),
    );
  }

  // --- NOUVEAU : MENU DES PARAMÈTRES (Engrenage) ---
  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Paramètres",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.language, color: Colors.blue),
                title: Text("language".tr),
                trailing: DropdownButton<String>(
                  value: ['fr', 'en'].contains(Get.locale?.languageCode)
                      ? Get.locale?.languageCode
                      : 'fr',
                  underline: const SizedBox(),
                  icon: const Icon(Icons.arrow_drop_down, color: primaryGreen),
                  items: const [
                    DropdownMenuItem(value: 'fr', child: Text("Français")),
                    DropdownMenuItem(value: 'en', child: Text("English")),
                  ],
                  onChanged: (String? newLang) async {
                    if (newLang != null) {
                      Get.updateLocale(Locale(newLang));
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('app_language', newLang);
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_rounded, color: primaryGreen),
                title: Text(userProfile.homeAddressString != null &&
                        userProfile.homeAddressString!.isNotEmpty
                    ? 'Modifier mon domicile'
                    : 'Définir mon domicile'),
                subtitle: userProfile.homeAddressString != null
                    ? Text(
                        userProfile.homeAddressString!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      )
                    : null,
                onTap: () {
                  Navigator.pop(ctx);
                  _handleSetHomeAddress(context);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.privacy_tip_rounded, color: primaryGreen),
                title: const Text("Confidentialité & Données RGPD"),
                subtitle:
                    const Text("Gestion du consentement et de la vie privée"),
                onTap: () {
                  Navigator.pop(ctx);
                  _showGdprPrivacyDialog(context);
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.storefront_rounded, color: Colors.orange),
                title: const Text("Accès Espace Pro / Commerçant"),
                onTap: () async {
                  Navigator.pop(ctx);
                  final Uri url = Uri.parse(
                      'https://TON-SITE-WEB.com/pro/auth'); // A MODIFIER
                  if (!await launchUrl(url,
                      mode: LaunchMode.externalApplication)) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Impossible d'ouvrir la page web"),
                        backgroundColor: Colors.red));
                  }
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text("Supprimer mon compte et mes données",
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                    "Effacement définitif (RGPD Art. 17 / App Store)",
                    style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteAccountGdpr(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.grey),
                title: const Text("Se déconnecter",
                    style: TextStyle(color: Colors.grey)),
                onTap: () async {
                  Navigator.pop(ctx); // Ferme settings
                  Navigator.pop(context); // Ferme profil
                  await FirebaseAuth.instance.signOut();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGdprPrivacyDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.privacy_tip_rounded, color: primaryGreen),
          SizedBox(width: 8),
          Text("Confidentialité & RGPD"),
        ]),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Protection de vos Données Personnelles",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                "• Géolocalisation : Utilisée en arrière-plan uniquement pour mesurer vos trajets écologiques et valider vos récompenses.\n\n"
                "• Domicile : Votre adresse est chiffrée, protégée dans Firestore et accessible EXCLUSIVEMENT par vous-même.\n\n"
                "• Protection : Vos données personnelles ne sont JAMAIS revendues à des tiers.\n\n"
                "• Droit d'effacement : Conformément au RGPD (Art. 17), vous pouvez à tout moment supprimer définitivement l'ensemble de vos données.",
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen),
            onPressed: () => Navigator.pop(ctx),
            child: const Text("J'ai compris"),
          ),
        ],
      ),
    );
  }

  void _deleteAccountGdpr(BuildContext context) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.delete_forever, color: Colors.red),
          SizedBox(width: 8),
          Text("Suppression du compte"),
        ]),
        content: const Text(
          "Conformément au RGPD (Droit à l'effacement - Art. 17) et aux règles des stores Apple/Google :\n\n"
          "Cette action supprimera définitivement votre profil, vos Lames, votre historique de trajets, et votre compte de nos serveurs.\n\n"
          "Cette action est IRRÉVERSIBLE. Voulez-vous continuer ?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Supprimer mes données"),
          ),
        ],
      ),
    );

    if (confirm == true) {
      Get.dialog(
        const Center(child: CircularProgressIndicator(color: Colors.red)),
        barrierDismissible: false,
      );

      try {
        final callable =
            FirebaseFunctions.instance.httpsCallable('deleteUserAccount');
        await callable.call();

        if (Get.isDialogOpen ?? false) Get.back();

        Get.snackbar(
          "Compte supprimé",
          "Toutes vos données personnelles ont été définitivement effacées.",
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 5),
        );

        await FirebaseAuth.instance.signOut();
      } catch (e) {
        if (Get.isDialogOpen ?? false) Get.back();

        Get.snackbar(
          "Erreur",
          "Erreur lors de la suppression : $e",
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryGreen = Color(0xFF388E3C);
    const Color accentGold = Color(0xFFFFB300);
    const Color textGrey = Color(0xFF757575);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      // CORRIGÉ: Suppression de BoxConstraints(maxHeight) pour laisser le DraggableScrollableSheet gérer la taille
      child: SingleChildScrollView(
        controller: scrollController, // CORRIGÉ: Lier le scroll
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // --- NOUVEAU : BOUTON ENGRENAGE ---
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.settings, color: Colors.grey, size: 28),
                onPressed: () => _showSettingsSheet(context),
              ),
            ),

            // 1. AVATAR ET NOM
            CircleAvatar(
              radius: 40,
              backgroundColor: primaryGreen,
              child: Text(
                  userProfile.username.isNotEmpty
                      ? userProfile.username.substring(0, 1).toUpperCase()
                      : "U",
                  style: const TextStyle(fontSize: 30, color: Colors.white)),
            ),
            const SizedBox(height: 12),
            Text(userProfile.username,
                style: Theme.of(context).textTheme.headlineMedium),

            // 2. STATUT VIP
            if (userProfile.isVip)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: ElevatedButton.icon(
                  onPressed: () => _showVipDetailsDialog(context),
                  icon: const Icon(Icons.workspace_premium,
                      color: Colors.black87),
                  label: const Text("Membre VIP",
                      style: TextStyle(
                          color: Colors.black87, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentGold,
                    minimumSize: const Size(200, 45),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: OutlinedButton.icon(
                  onPressed: () => _showPremiumDialog(context),
                  icon: const Icon(Icons.workspace_premium_outlined,
                      color: accentGold),
                  label: const Text("Obtenir Premium",
                      style: TextStyle(color: accentGold)),
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: accentGold),
                      backgroundColor: accentGold.withOpacity(0.1)),
                ),
              ),

            const SizedBox(height: 15),
            const Divider(),

            // 📊 STATISTIQUES UTILISATEUR
            const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text('Statistiques',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            SizedBox(
              height: 110,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                _buildStatCard(
                    '📍',
                    '${userProfile.totalDistanceKm.toStringAsFixed(1)}',
                    'Distance'),
                _buildStatCard(
                    '🚗', '${userProfile.totalTripsCount}', 'Trajets'),
                _buildStatCard(
                    '🔥', '${userProfile.totalCaloriesBurned}', 'Calories'),
                _buildStatCard('👥', '${userProfile.friendIds.length}', 'Amis'),
              ]),
            ),

            // 🏅 BADGES D'ACCOMPLISSEMENT
            const SizedBox(height: 15),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Badges d\'accomplissement',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('${userProfile.unlockedBadges.length}/10',
                        style: const TextStyle(
                            color: accentGold, fontWeight: FontWeight.bold)),
                  ]),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final achievement in Achievement.all)
                  _buildBadge(achievement,
                      userProfile.unlockedBadges.contains(achievement.id)),
              ]),
            ),

            // 👥 GESTION DES AMIS
            const SizedBox(height: 15),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Ajouter'),
                  onPressed: () {
                    Navigator.pop(context);
                    _showAddFriendDialog(context);
                  },
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.people, size: 18),
                  label: Text('${userProfile.friendIds.length} Amis'),
                  onPressed: () => _showFriendsList(context, userProfile),
                ),
                if (userProfile.friendRequestsReceived.isNotEmpty)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.mail, size: 18),
                    label: Text(
                        '${userProfile.friendRequestsReceived.length} Demandes'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange),
                    onPressed: () {
                      Navigator.pop(context);
                      _showFriendRequestsDialog(context, userProfile);
                    },
                  ),
              ],
            ),

            const Divider(),

            // 3. SYSTÈME DE NIVEAUX
            _buildLevelProgressSection(userProfile, context),

            const Divider(),

            // 4. STATISTIQUES UTILISATEUR
            ListTile(
                leading: const Icon(Icons.eco_rounded, color: accentGold),
                title: Text('${userProfile.lamePoints} Lame Points')),
            ListTile(
                leading: const Icon(Icons.login_rounded, color: textGrey),
                title: Text(
                    '${userProfile.consecutiveLogins} jours de connexion')),

            const Divider(),

            // 5. BOUTIQUE
            const SizedBox(height: 10),
            ElevatedButton.icon(
                icon: const Icon(Icons.shopping_bag_outlined),
                label: const Text('Ouvrir la Boutique'),
                onPressed: onOpenShop,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 45))),

            const SizedBox(height: 20),
            // Les boutons Espace Pro, Domicile et Déconnexion ont été déplacés dans les paramètres !
          ],
        ),
      ),
    );
  }

  void _showVipDetailsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.workspace_premium, color: Color(0xFFFFB300), size: 28),
            SizedBox(width: 8),
            Text("Vos avantages VIP"),
          ]),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Vous profitez actuellement de :",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _premiumBenefitRow(Icons.add_road, "Déviation tolérée : 6 km",
                    "Au lieu de 3 km en standard"),
                _premiumBenefitRow(Icons.bolt, "x2 Lames sur chaque trajet",
                    "Multipliez vos gains"),
                _premiumBenefitRow(Icons.percent, "+15% Cashback magasins",
                    "Plus de réductions"),
                _premiumBenefitRow(Icons.trending_up,
                    "Multiplicateur Ad Points", "Boostez votre progression"),
                _premiumBenefitRow(Icons.star, "Niveau max débloqué",
                    "Progressez sans limite"),
                _premiumBenefitRow(
                    Icons.cached, "Pub boost double", "Cashback boosté x2"),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
                child:
                    const Text("Fermer", style: TextStyle(color: Colors.grey)),
                onPressed: () => Navigator.of(dialogContext).pop()),
            TextButton(
              child: const Text("Résilier VIP",
                  style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _removeVipSubscription(context);
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildStatCard(String icon, String value, String label) {
    return Container(
      width: 85,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!, width: 1),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(icon, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 6),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildBadge(Achievement achievement, bool unlocked) {
    return Tooltip(
      message: achievement.requirement,
      child: Container(
        width: 60,
        height: 60,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: unlocked ? Colors.amber[100] : Colors.grey[200],
          border: Border.all(
            color: unlocked ? Colors.amber : Colors.grey[400]!,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(achievement.icon, style: const TextStyle(fontSize: 24)),
            if (!unlocked) ...[
              const Text('?',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ]
          ],
        ),
      ),
    );
  }

  void _showFriendsList(BuildContext context, UserProfile userProfile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Amis (${userProfile.friendIds.length})'),
            IconButton(
              icon: const Icon(Icons.person_add, color: Colors.blue),
              tooltip: 'Ajouter un ami',
              onPressed: () {
                Navigator.pop(ctx);
                _showAddFriendDialog(context);
              },
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: userProfile.friendIds.isEmpty
              ? const Center(child: Text('Aucun ami pour le moment'))
              : FutureBuilder<List<UserProfile>>(
                  future: _fetchFriendProfiles(userProfile.friendIds),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(
                          child: Text('Impossible de charger les amis'));
                    }
                    return ListView(
                      children: snapshot.data!
                          .map((friend) => ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.grey[400],
                                  child: Text(friend.username.isNotEmpty
                                      ? friend.username[0].toUpperCase()
                                      : 'U'),
                                ),
                                title: Text(friend.username),
                                subtitle: Text('${friend.lamePoints} Lames'),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _showPublicProfile(context, friend);
                                },
                              ))
                          .toList(),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Fermer')),
        ],
      ),
    );
  }

  Future<List<UserProfile>> _fetchFriendProfiles(List<String> friendIds) async {
    try {
      final profiles = <UserProfile>[];
      for (final friendId in friendIds) {
        final doc = await _firestore.collection('users').doc(friendId).get();
        if (doc.exists) {
          profiles.add(UserProfile.fromFirestore(
              doc as DocumentSnapshot<Map<String, dynamic>>));
        }
      }
      return profiles;
    } catch (e) {
      debugPrint('Erreur chargement amis: $e');
      return [];
    }
  }

  void _showPublicProfile(BuildContext context, UserProfile userProfile) {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final isOwnProfile = currentUserId == userProfile.id;
    final isFriend = userProfile.friendIds.contains(currentUserId);

    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: Colors.blue,
                child: Text(
                    userProfile.username.isNotEmpty
                        ? userProfile.username[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(fontSize: 30, color: Colors.white)),
              ),
              const SizedBox(height: 12),
              Text(userProfile.username,
                  style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text('Niveau ${userProfile.currentLevel}',
                  style: const TextStyle(
                      color: Colors.blue, fontWeight: FontWeight.bold)),

              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width - 40),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildStatCard(
                            '📍',
                            '${userProfile.totalDistanceKm.toStringAsFixed(1)}',
                            'Distance'),
                        const SizedBox(width: 12),
                        _buildStatCard(
                            '🚗', '${userProfile.totalTripsCount}', 'Trajets'),
                        const SizedBox(width: 12),
                        _buildStatCard('🏅',
                            '${userProfile.unlockedBadges.length}', 'Badges'),
                      ]),
                ),
              ),

              // 🏆 Display unlocked badges
              if (userProfile.unlockedBadges.isNotEmpty)
                const SizedBox(height: 20),
              if (userProfile.unlockedBadges.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Badges débloqués',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: userProfile.unlockedBadges.map((badgeName) {
                        final achievement = Achievement.all.firstWhere(
                          (a) => a.id == badgeName,
                          orElse: () => Achievement.all.first,
                        );
                        return Tooltip(
                          message: achievement.requirement,
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.amber[100],
                              border: Border.all(color: Colors.amber, width: 2),
                            ),
                            child: Center(
                                child: Text(achievement.icon,
                                    style: const TextStyle(fontSize: 28))),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),

              const SizedBox(height: 20),
              if (!isOwnProfile) ...[
                if (!isFriend)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_add),
                    label: const Text('Ajouter en ami'),
                    onPressed: () {
                      _sendFriendRequest(userProfile.id, context);
                      Navigator.pop(ctx);
                    },
                  )
                else
                  ElevatedButton.icon(
                    icon: const Icon(Icons.person_remove),
                    label: const Text('Supprimer ami'),
                    style:
                        ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (dialogCtx) => AlertDialog(
                          title: const Text('Confirmer'),
                          content: Text(
                              'Supprimer ${userProfile.username} de vos amis ?'),
                          actions: [
                            TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogCtx, false),
                                child: const Text('Annuler')),
                            ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red),
                                onPressed: () => Navigator.pop(dialogCtx, true),
                                child: const Text('Supprimer')),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        final currentUserId =
                            FirebaseAuth.instance.currentUser?.uid;
                        if (currentUserId != null) {
                          await _firestore
                              .collection('users')
                              .doc(currentUserId)
                              .update({
                            'friend_ids':
                                FieldValue.arrayRemove([userProfile.id]),
                          });
                          await _firestore
                              .collection('users')
                              .doc(userProfile.id)
                              .update({
                            'friend_ids':
                                FieldValue.arrayRemove([currentUserId]),
                          });
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    '${userProfile.username} supprimé des amis'),
                                backgroundColor: Colors.green),
                          );
                        }
                      }
                    },
                  ),
              ],

              const SizedBox(height: 10),
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Fermer')),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendFriendRequest(String friendId, BuildContext context) async {
    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return;

      await _firestore.collection('users').doc(currentUserId).update({
        'friend_requests_sent': FieldValue.arrayUnion([friendId]),
      });

      await _firestore.collection('users').doc(friendId).update({
        'friend_requests_received': FieldValue.arrayUnion([currentUserId]),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ Demande d\'ami envoyée!'),
              backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      debugPrint('Erreur demande ami: $e');
    }
  }

  void _showAddFriendDialog(BuildContext parentContext) {
    // <-- 1. On renomme ici
    final TextEditingController usernameController = TextEditingController();
    String? errorMessage;
    bool isLoading = false;

    showDialog(
      context: parentContext,
      builder: (dialogCtx) => StatefulBuilder(
        // <-- 2. Et ici
        builder: (statefulCtx, setState) {
          // <-- 3. Et ici
          return AlertDialog(
            title: const Text('Ajouter un ami'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    hintText: 'Entrer le username',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(errorMessage!,
                      style: const TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold)),
                ]
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Annuler')),
              ElevatedButton(
                onPressed: isLoading
                    ? null
                    : () async {
                        if (usernameController.text.trim().isEmpty) {
                          setState(() => errorMessage = 'Entrez un username');
                          return;
                        }

                        setState(() {
                          isLoading = true;
                          errorMessage = null;
                        });

                        try {
                          final query = await _firestore
                              .collection('users')
                              .where('username',
                                  isEqualTo: usernameController.text.trim())
                              .limit(1)
                              .get();

                          if (query.docs.isEmpty) {
                            setState(() {
                              errorMessage = 'Utilisateur introuvable';
                              isLoading = false;
                            });
                            return;
                          }

                          final friend = UserProfile.fromFirestore(query.docs
                              .first as DocumentSnapshot<Map<String, dynamic>>);

                          // --- CORRECTION DU CRASH ICI ---
                          if (dialogCtx.mounted) {
                            if (Get.isDialogOpen ?? false)
                              Get.back(); // On ferme le popup de manière sécurisée
                            _showPublicProfile(parentContext,
                                friend); // On ouvre le profil avec le context parent !
                          }
                        } catch (e) {
                          setState(() {
                            errorMessage = 'Erreur: $e';
                            isLoading = false;
                          });
                        }
                      },
                child: isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Rechercher'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showFriendRequestsDialog(
      BuildContext context, UserProfile userProfile) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Demandes d\'amis'),
        content: SizedBox(
          width: double.maxFinite,
          child: userProfile.friendRequestsReceived.isEmpty
              ? const Text('Aucune demande en attente.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: userProfile.friendRequestsReceived.length,
                  itemBuilder: (context, index) {
                    final reqId = userProfile.friendRequestsReceived[index];
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('users')
                          .doc(reqId)
                          .get(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData)
                          return const ListTile(title: Text('Chargement...'));
                        final data =
                            snapshot.data!.data() as Map<String, dynamic>?;
                        if (data == null) return const SizedBox();
                        final name = data['username'] ?? 'Inconnu';

                        return ListTile(
                          title: Text(name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check,
                                    color: Colors.green),
                                onPressed: () async {
                                  // Accepter
                                  final currentUserId =
                                      FirebaseAuth.instance.currentUser?.uid;
                                  if (currentUserId == null) return;
                                  final batch =
                                      FirebaseFirestore.instance.batch();
                                  final currentUserRef = FirebaseFirestore
                                      .instance
                                      .collection('users')
                                      .doc(currentUserId);
                                  final friendRef = FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(reqId);

                                  batch.update(currentUserRef, {
                                    'friend_requests_received':
                                        FieldValue.arrayRemove([reqId]),
                                    'friend_ids': FieldValue.arrayUnion([reqId])
                                  });
                                  batch.update(friendRef, {
                                    'friend_requests_sent':
                                        FieldValue.arrayRemove([currentUserId]),
                                    'friend_ids':
                                        FieldValue.arrayUnion([currentUserId])
                                  });

                                  await batch.commit();
                                  if (context.mounted) Navigator.pop(ctx);
                                },
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.close, color: Colors.red),
                                onPressed: () async {
                                  // Refuser
                                  final currentUserId =
                                      FirebaseAuth.instance.currentUser?.uid;
                                  if (currentUserId == null) return;
                                  final batch =
                                      FirebaseFirestore.instance.batch();
                                  final currentUserRef = FirebaseFirestore
                                      .instance
                                      .collection('users')
                                      .doc(currentUserId);
                                  final friendRef = FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(reqId);

                                  batch.update(currentUserRef, {
                                    'friend_requests_received':
                                        FieldValue.arrayRemove([reqId]),
                                  });
                                  batch.update(friendRef, {
                                    'friend_requests_sent':
                                        FieldValue.arrayRemove([currentUserId]),
                                  });

                                  await batch.commit();
                                  if (context.mounted) Navigator.pop(ctx);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Fermer'))
        ],
      ),
    );
  }

  Widget _buildLevelProgressSection(
      UserProfile userProfile, BuildContext context) {
    final levelData = _calculateUserLevel(userProfile.totalLameEarned ?? 0);
    final currentLevel = levelData['currentLevel'];
    final lameForCurrentLevel = levelData['lameForCurrentLevel'];
    final lameForNextLevel = levelData['lameForNextLevel'];
    final progressToNextLevel = levelData['progressToNextLevel'];
    final isMaxLevel = currentLevel >= 50;

    // Vérifier si premium gratuit au niveau 30
    final shouldHaveFreePremium = currentLevel >= 30 && !userProfile.isVip;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryGreen.withOpacity(0.1),
            accentGold.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: primaryGreen.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête niveau
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: primaryGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Niveau $currentLevel',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const Spacer(),
              if (currentLevel >= 30)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentGold,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '👑 Premium',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Bonus actuel
          Row(
            children: [
              const Icon(Icons.add_circle, color: primaryGreen, size: 20),
              const SizedBox(width: 8),
              Text(
                '+$currentLevel Lame par trajet',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: primaryGreen,
                ),
              ),
            ],
          ),

          if (!isMaxLevel) ...[
            const SizedBox(height: 12),

            // Barre de progression
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${userProfile.totalLameEarned ?? 0}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  'Niveau ${currentLevel + 1}',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  '$lameForNextLevel',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progressToNextLevel,
                minHeight: 8,
                backgroundColor: Colors.grey[300],
                valueColor: AlwaysStoppedAnimation<Color>(
                  currentLevel >= 30 ? accentGold : primaryGreen,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Encore ${lameForNextLevel - (userProfile.totalLameEarned ?? 0)} Lame pour le niveau suivant',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ] else ...[
            const SizedBox(height: 8),
            const Text(
              '🌟 Niveau maximum atteint !',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: accentGold,
              ),
            ),
          ],

          // Notification premium gratuit
          if (shouldHaveFreePremium) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentGold.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: accentGold),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star, color: accentGold),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Félicitations ! Vous avez débloqué le Premium gratuit !',
                      style: TextStyle(
                        color: accentGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic> _calculateUserLevel(int totalLame) {
    int currentLevel = 1;
    int lameNeeded = 500; // Pour le niveau 2
    int totalLameForCurrentLevel = 0;

    // Calculer le niveau actuel
    while (totalLame >= totalLameForCurrentLevel + lameNeeded &&
        currentLevel < 50) {
      totalLameForCurrentLevel += lameNeeded;
      currentLevel++;
      lameNeeded *= 2; // Double à chaque niveau
    }

    // Calculer les Lame nécessaires pour le niveau suivant
    int lameForNextLevel = totalLameForCurrentLevel + lameNeeded;

    // Calculer le progrès vers le niveau suivant
    double progressToNextLevel = 0.0;
    if (currentLevel < 50) {
      int lameInCurrentLevel = totalLame - totalLameForCurrentLevel;
      progressToNextLevel = lameInCurrentLevel / lameNeeded;
      progressToNextLevel = progressToNextLevel.clamp(0.0, 1.0);
    }

    return {
      'currentLevel': currentLevel,
      'lameForCurrentLevel': totalLameForCurrentLevel,
      'lameForNextLevel': lameForNextLevel,
      'progressToNextLevel': progressToNextLevel,
    };
  }
}

class _PremiumBenefit extends StatelessWidget {
  final IconData icon;
  final String text;

  const _PremiumBenefit({Key? key, required this.icon, required this.text})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primaryGreen, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

enum OfferType {
  freeOffer,
  promoCode,
  transfer,
  contest,
  treePlanting,
  campaignDonation,
  sdgDonation,
  voucher,
  travelPoints,
  unknown,
}

class RewardOffer {
  final String id;
  final String title;
  final String description;
  final String? imageUrl;
  final OfferType offerType;
  final String? brandName;
  final int? ecoCost;
  final String? valueText;
  final DateTime createdAt;
  final DateTime? expiryDate;
  final bool isActive;
  final Map<String, dynamic>? detailsJson;
  final String? actionButtonText;
  final String? detailPageUrl;
  final int sortOrder;

  RewardOffer({
    required this.id,
    required this.title,
    required this.description,
    this.imageUrl,
    required this.offerType,
    this.brandName,
    this.ecoCost,
    this.valueText,
    required this.createdAt,
    this.expiryDate,
    this.isActive = true,
    this.detailsJson,
    this.actionButtonText,
    this.detailPageUrl,
    this.sortOrder = 0,
  });

  factory RewardOffer.fromFirestore(
      DocumentSnapshot<Map<String, dynamic>> doc) {
    final json = doc.data()!;
    return RewardOffer(
      id: doc.id,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      offerType: _parseOfferType(json['offer_type'] as String?),
      brandName: json['brand_name'] as String?,
      ecoCost: json['eco_cost'] as int?,
      valueText: json['value_text'] as String?,
      createdAt: (json['created_at'] as Timestamp).toDate(),
      expiryDate: (json['expiry_date'] as Timestamp?)?.toDate(),
      isActive: json['is_active'] as bool? ?? true,
      detailsJson: (json['details_json'] as Map<String, dynamic>?) ?? {},
      actionButtonText: json['action_button_text'] as String?,
      detailPageUrl: json['detail_page_url'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  static OfferType _parseOfferType(String? typeStr) {
    if (typeStr == null) return OfferType.unknown;
    switch (typeStr.toLowerCase()) {
      case 'freeoffer':
      case 'free_offer':
        return OfferType.freeOffer;
      case 'promocode':
      case 'promo_code':
        return OfferType.promoCode;
      case 'transfer':
        return OfferType.transfer;
      case 'contest':
        return OfferType.contest;
      case 'treeplanting':
      case 'tree_planting':
        return OfferType.treePlanting;
      case 'campaigndonation':
      case 'campaign_donation':
        return OfferType.campaignDonation;
      case 'voucher':
        return OfferType.voucher;
      case 'travelpoints':
      case 'travel_points':
        return OfferType.travelPoints;
      case 'sdgdonation':
      case 'sdg_donation':
        return OfferType.sdgDonation;
      default:
        print("Unknown offer type from DB: $typeStr");
        return OfferType.unknown;
    }
  }

  Widget getIconWidget({double size = 40, Color color = Colors.white}) {
    if (imageUrl == 'icon_megaphone_red' ||
        imageUrl == 'icon_megaphone_red_concours') {
      return Icon(Icons.campaign, size: size, color: color);
    }
    if (imageUrl == 'icon_paypal_logo_placeholder') {
      return Icon(Icons.paypal, size: size, color: color);
    }
    if (imageUrl == 'icon_1000_eco_green_circle') {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.green,
        child: Text("1k",
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.4)),
      );
    }

    if (imageUrl != null && imageUrl!.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (c, u) => SizedBox(
            width: size,
            height: size,
            child: Center(
                child: SizedBox(
                    width: size * 0.5,
                    height: size * 0.5,
                    child: CircularProgressIndicator(strokeWidth: 2)))),
        errorWidget: (c, u, e) =>
            Icon(Icons.broken_image, size: size, color: Colors.grey),
      );
    }

    IconData iconData;
    switch (offerType) {
      case OfferType.freeOffer:
      case OfferType.promoCode:
        iconData = Icons.campaign;
        break;
      case OfferType.transfer:
        iconData = Icons.paypal;
        break;
      case OfferType.contest:
        iconData = Icons.emoji_events;
        break;
      case OfferType.treePlanting:
        iconData = Icons.forest_outlined;
        break;
      case OfferType.campaignDonation:
        iconData = Icons.volunteer_activism;
        break;
      case OfferType.voucher:
        iconData = Icons.storefront;
        break;
      case OfferType.travelPoints:
        iconData = Icons.flight_takeoff;
        break;
      case OfferType.sdgDonation:
        iconData = Icons.public;
        break;
      default:
        iconData = Icons.card_giftcard;
    }
    return Icon(iconData, size: size, color: color);
  }
}

class RewardScreen extends StatefulWidget {
  final UserProfile userProfile;

  final Future<void> Function(int cost) onPurchase;

  const RewardScreen({
    super.key,
    required this.userProfile,
    required this.onPurchase,
  });

  @override
  State<RewardScreen> createState() => _RewardScreenState();
}

class _RewardScreenState extends State<RewardScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  List<RewardOffer> _allOffers = [];
  bool _isLoadingOffers = true;

  final firestore = FirebaseFirestore.instance;

  final List<Map<String, dynamic>> _sdgData = [
    {
      'id': 1,
      'name': 'ODD 1: Pas de pauvreté',
      'description': 'Éliminer la pauvreté.',
      'imageUrl': 'images/sdg/F-WEB-Goal-01.png'
    },
    {
      'id': 2,
      'name': 'ODD 2: Faim « zéro »',
      'description': 'Éliminer la faim.',
      'imageUrl': 'images/sdg/F-WEB-Goal-02.png'
    },
    {
      'id': 3,
      'name': 'ODD 3: Bonne santé et bien-être',
      'description': 'Bonne santé pour tous.',
      'imageUrl': 'images/sdg/F-WEB-Goal-03.png'
    },
    {
      'id': 4,
      'name': 'ODD 4: Éducation de qualité',
      'description': 'Éducation de qualité.',
      'imageUrl': 'images/sdg/F-WEB-Goal-04.png'
    },
    {
      'id': 5,
      'name': 'ODD 5: Égalité entre les sexes',
      'description': 'Égalité des sexes.',
      'imageUrl': 'images/sdg/F-WEB-Goal-05.png'
    },
    {
      'id': 6,
      'name': 'ODD 6: Eau propre et assainissement',
      'description': 'Eau propre.',
      'imageUrl': 'images/sdg/F-WEB-Goal-06.png'
    },
    {
      'id': 7,
      'name': 'ODD 7: Énergie propre',
      'description': 'Énergie propre.',
      'imageUrl': 'images/sdg/F-WEB-Goal-07.png'
    },
    {
      'id': 8,
      'name': 'ODD 8: Travail décent',
      'description': 'Travail décent.',
      'imageUrl': 'images/sdg/F-WEB-Goal-08.png'
    },
    {
      'id': 9,
      'name': 'ODD 9: Industrie, innovation',
      'description': 'Innovation.',
      'imageUrl': 'images/sdg/F-WEB-Goal-09.png'
    },
    {
      'id': 10,
      'name': 'ODD 10: Inégalités réduites',
      'description': 'Moins d\'inégalités.',
      'imageUrl': 'images/sdg/F-WEB-Goal-10.png'
    },
    {
      'id': 11,
      'name': 'ODD 11: Villes durables',
      'description': 'Villes durables.',
      'imageUrl': 'images/sdg/F-WEB-Goal-11.png'
    },
    {
      'id': 12,
      'name': 'ODD 12: Consommation responsable',
      'description': 'Consommation resp.',
      'imageUrl': 'images/sdg/F-WEB-Goal-12.png'
    },
    {
      'id': 13,
      'name': 'ODD 13: Lutte changements climatiques',
      'description': 'Action climat.',
      'imageUrl': 'images/sdg/F-WEB-Goal-13.png'
    },
    {
      'id': 14,
      'name': 'ODD 14: Vie aquatique',
      'description': 'Vie aquatique.',
      'imageUrl': 'images/sdg/F-WEB-Goal-14.png'
    },
    {
      'id': 15,
      'name': 'ODD 15: Vie terrestre',
      'description': 'Vie terrestre.',
      'imageUrl': 'images/sdg/F-WEB-Goal-15.png'
    },
    {
      'id': 16,
      'name': 'ODD 16: Paix, justice',
      'description': 'Paix et justice.',
      'imageUrl': 'images/sdg/F-WEB-Goal-16.png'
    },
    {
      'id': 17,
      'name': 'ODD 17: Partenariats',
      'description': 'Partenariats.',
      'imageUrl': 'images/sdg/F-WEB-Goal-17.png'
    },
  ];

  String _totalSdgCollectedDisplay = "5.65";

  bool _treePlantConfirming = false;
  Timer? _treePlantConfirmTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 0);
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    if (!mounted) return;
    await _loadUserStatsFromProvider();
    await _fetchOffersFromFirestore();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadUserStatsFromProvider() async {
    final userStatsProvider = Get.find<UserStatsController>();
    final currentUser = FirebaseAuth.instance.currentUser;
    if (userStatsProvider.userStats == null && currentUser != null) {
      final userId = currentUser.uid;
      try {
        final docSnapshot =
            await firestore.collection('user_stats').doc(userId).get();
        if (mounted) {
          UserStats loadedStats;
          if (docSnapshot.exists && docSnapshot.data() != null) {
            loadedStats = UserStats.fromJson(docSnapshot.data()!);
          } else {
            loadedStats = UserStats();
            await firestore
                .collection('user_stats')
                .doc(userId)
                .set(loadedStats.toJson());
          }
          userStatsProvider.setUserStats(loadedStats);
        }
      } catch (e) {
        print("Error loading user stats for RewardScreen init: $e");
        if (mounted) userStatsProvider.setUserStats(UserStats());
      }
    }
  }

  Future<void> _fetchOffersFromFirestore() async {
    if (!mounted) return;
    setState(() => _isLoadingOffers = true);
    try {
      final querySnapshot = await firestore
          .collection('rewards')
          .where('is_active', isEqualTo: true)
          .orderBy('sort_order', descending: false)
          .get();

      if (mounted) {
        _allOffers = querySnapshot.docs
            .map((doc) => RewardOffer.fromFirestore(doc))
            .toList();
        setState(() => _isLoadingOffers = false);
      }
    } catch (e) {
      print("Error fetching offers from Firestore: $e");
      if (mounted) {
        setState(() => _isLoadingOffers = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text("Erreur de chargement des offres: $e. Using fallback."),
            backgroundColor: Colors.red));
        _fetchOffersDummyData();
      }
    }
  }

  Future<void> _fetchOffersDummyData() async {
    await Future.delayed(const Duration(milliseconds: 100));
    DateTime now = DateTime.now();
    _allOffers = [
      RewardOffer(
          id: "free_offer_01",
          title: "Essai gratuit de 1 semaine",
          description: "Découvrez notre partenaire privilégié.",
          offerType: OfferType.freeOffer,
          brandName: "Marque Essai",
          ecoCost: 0,
          valueText: "1 semaine d'accès",
          imageUrl: "icon_megaphone_red",
          createdAt: now,
          sortOrder: 1,
          actionButtonText: "Commencer l'essai",
          detailPageUrl: "https://example.com/free-trial"),
      RewardOffer(
          id: "promo_code_01",
          title: "Code Promo -25%",
          description: "Obtenez un code promotionnel exclusif.",
          offerType: OfferType.promoCode,
          brandName: "Marque Promo",
          ecoCost: 0,
          valueText: "-25% sur tout",
          imageUrl: "icon_megaphone_red",
          detailsJson: {'code': 'TWINPLANET25'},
          createdAt: now,
          sortOrder: 2,
          actionButtonText: "Obtenir le code"),
      RewardOffer(
          id: "transfer_paypal_01",
          title: "\$5 via Paypal",
          description: "Échangez 5000 de vos éco.",
          offerType: OfferType.transfer,
          brandName: "Paypal",
          ecoCost: 5000,
          valueText: "\$5",
          imageUrl: "icon_paypal_logo_placeholder",
          createdAt: now,
          sortOrder: 3,
          actionButtonText: "Demander le virement"),
      RewardOffer(
          id: "contest_auction_ps5",
          title: "Enchère Pack PS5",
          description: "Misez vos éco pour gagner une PS5.",
          offerType: OfferType.contest,
          brandName: "Enchères Exclusives",
          valueText: "PS5 à gagner",
          imageUrl: "icon_megaphone_red_concours",
          detailsJson: {
            'type': 'auction',
            'product_name': 'Pack PS5',
            'product_image_url': 'https://i.imgur.com/gO0A3vT.png',
            'min_bid': 50.0,
            'current_highest_bid': 1500.0,
            'end_date': now.add(const Duration(days: 7)).toIso8601String(),
            'contest_id_ref': 'CONTEST_AUCTION_001'
          },
          createdAt: now,
          sortOrder: 4,
          ecoCost: 50),
      RewardOffer(
          id: "contest_raffle_ps5",
          title: "Super Tirage PS5",
          description: "Achetez des tickets pour gagner une PS5.",
          offerType: OfferType.contest,
          brandName: "Grand Tirage",
          valueText: "PS5 à gagner",
          imageUrl: "icon_megaphone_red_concours",
          detailsJson: {
            'type': 'raffle',
            'product_name': 'Pack PS5',
            'product_image_url': 'https://i.imgur.com/gO0A3vT.png',
            'ticket_cost_eco': 20,
            'total_tickets_sold': 350,
            'end_date': now.add(const Duration(days: 14)).toIso8601String()
          },
          createdAt: now,
          sortOrder: 5,
          ecoCost: 20),
      RewardOffer(
          id: "campaign_water_01",
          title: "L'oeuvre de l'eau enfants",
          description: "Contribuez à notre campagne pour l'eau potable.",
          offerType: OfferType.campaignDonation,
          brandName: "Accès à l'Eau",
          ecoCost: 50,
          valueText: "Contribuer",
          imageUrl: "https://i.imgur.com/zJ9Ae4Z.jpg",
          detailsJson: {
            'current_amount_eco': 58000,
            'target_amount_eco': 100000,
            'current_donors': 433,
            'campaign_id_ref': 'CAMP_WATER_001'
          },
          createdAt: now,
          sortOrder: 6),
      RewardOffer(
          id: "voucher_generic_01",
          title: "Bon d'achat de 5€",
          description: "Utilisez vos éco pour un bon d'achat.",
          offerType: OfferType.voucher,
          brandName: "Bons d'Achat Express",
          ecoCost: 5000,
          valueText: "Valeur 5€",
          imageUrl: "icon_megaphone_red",
          createdAt: now,
          sortOrder: 100),
      RewardOffer(
          id: "travel_points_01",
          title: "Points Voyage",
          description: "Cumulez des points voyage.",
          offerType: OfferType.travelPoints,
          brandName: "Voyages Malin",
          ecoCost: 1000,
          valueText: "100 points voyage",
          imageUrl: "icon_megaphone_red",
          createdAt: now,
          sortOrder: 101),
    ];
    if (mounted) setState(() => _isLoadingOffers = false);
  }

  Future<bool> _spendLamePoints(double amount, String offerIdContext,
      String offerTitleContext, String email,
      {bool isInstantApproval = false}) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    // 1. Vérifications de base
    if (currentUser == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Erreur: Utilisateur non connecté."),
            backgroundColor: Colors.red));
      return false;
    }

    if (widget.userProfile.lamePoints < amount) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Pas assez de Lame Points!"),
            backgroundColor: Colors.orange));
      return false;
    }

    final userRef = firestore.collection('users').doc(currentUser.uid);

    // Création d'une nouvelle référence pour l'historique des demandes
    final claimedOfferRef = firestore.collection('user_claimed_offers').doc();

    try {
      await firestore.runTransaction((transaction) async {
        // 2. Débiter les points de l'utilisateur
        transaction
            .update(userRef, {'lame_points': FieldValue.increment(-amount)});

        // 3. Enregistrer la demande dans l'historique avec le statut
        transaction.set(claimedOfferRef, {
          'user_id': currentUser.uid,
          'user_email_contact': email,
          'reward_id': offerIdContext,
          'details': {
            'claimed_for_lame': amount,
            'offer_title': offerTitleContext
          },
          'claimed_at': FieldValue.serverTimestamp(),

          // --- AJOUT CLÉ POUR LE SUIVI ---
          'status': isInstantApproval
              ? 'approved'
              : 'pending', // Dons = validé immédiatement, autres = en attente
          // -----------------------------

          // Champs pour l'envoi d'email (facultatif selon votre config backend)
          'to': 'corentinparrel2@gmail.com',
          'message': {
            'subject': 'Nouvelle demande de récompense EcoNav !',
            'text':
                'L\'utilisateur $email a réclamé la récompense "$offerTitleContext" pour $amount Lames. ID Utilisateur: ${currentUser.uid}',
            'html':
                '<h1>Nouvelle Récompense Réclamée</h1><p><b>Utilisateur:</b> $email</p><p><b>Récompense:</b> $offerTitleContext</p><p><b>Coût:</b> $amount Lames</p><p><b>ID User:</b> ${currentUser.uid}</p>',
          }
        });
      });

      // 4. Mettre à jour l'interface locale via le callback parent
      await widget.onPurchase(amount.toInt());
      return true;
    } catch (error) {
      print("Erreur de transaction Firestore: $error");
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur serveur: $error"),
            backgroundColor: Colors.red));
      return false;
    }
  }

  Future<void> _handleGenericLameSpend(
      double lameCost, String idContext, String titleContext,
      {String? successMessage,
      VoidCallback? onSuccess,
      bool isInstantApproval = false}) async {
    // 1. Retrieve the current user's email to satisfy the 4th argument
    final user = FirebaseAuth.instance.currentUser;
    final String userEmail = user?.email ?? "corentinparrel2@gmail.com";

    // 2. Pass 'userEmail' as the 4th argument
    bool success = await _spendLamePoints(
        lameCost, idContext, titleContext, userEmail,
        isInstantApproval: isInstantApproval);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(successMessage ??
              "Action réussie! ${lameCost.toStringAsFixed(1)} Lame Points dépensés."),
          backgroundColor: Colors.green));
      onSuccess?.call();
    }
  }

  void _plantTreeConfirmation() {
    if (_treePlantConfirming) {
      _treePlantConfirmTimer?.cancel();
      setState(() => _treePlantConfirming = false);
      _handleGenericLameSpend(1000.0, "plant_tree_action", "Planter un arbre",
          isInstantApproval: true,
          successMessage:
              "Félicitations! 1000.0 Lame Points dépensés pour planter un arbre.");
    } else {
      setState(() => _treePlantConfirming = true);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                "Appuyez à nouveau pour confirmer et planter l'arbre (1000.0 Lame Points)."),
            duration: Duration(seconds: 3)));
      _treePlantConfirmTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _treePlantConfirming = false);
      });
    }
  }

  void _showSdgDonationDialog(Map<String, dynamic> sdg) {
    final TextEditingController amountController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          if (sdg['imageUrl'] != null &&
              (sdg['imageUrl'] as String).startsWith('images/'))
            Image.asset(sdg['imageUrl'],
                width: 30,
                height: 30,
                errorBuilder: (c, u, e) =>
                    const Icon(Icons.broken_image, size: 30)),
          const SizedBox(width: 10),
          Expanded(
              child: Text("Soutenir: ${sdg['name']}",
                  style: GoogleFonts.poppins(fontSize: 18)))
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sdg['description'] as String? ?? "Contribuez à cet ODD.",
                style: GoogleFonts.poppins(fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: "Montant du don (en Lame Points)",
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  prefixIcon:
                      Icon(Icons.eco, color: Theme.of(context).primaryColor)),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text);
              if (amount != null && amount > 0) {
                Navigator.of(ctx).pop();
                _handleGenericLameSpend(
                    amount, "sdg_donation_${sdg['id']}", "Don à ${sdg['name']}",
                    isInstantApproval: true,
                    successMessage:
                        "Merci pour votre don de ${amount.toStringAsFixed(1)} Lame Points à ${sdg['name']}!");
              } else {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text("Veuillez entrer un montant valide."),
                      backgroundColor: Colors.orange));
              }
            },
            child: const Text("Envoyer"),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _treePlantConfirmTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingOffers) {
      return Scaffold(
          appBar: _buildAppBar(),
          body: const Center(child: CircularProgressIndicator()));
    }

    List<RewardOffer> freeOffers =
        _allOffers.where((o) => o.offerType == OfferType.freeOffer).toList();
    List<RewardOffer> promoCodes =
        _allOffers.where((o) => o.offerType == OfferType.promoCode).toList();
    List<RewardOffer> transfers =
        _allOffers.where((o) => o.offerType == OfferType.transfer).toList();
    List<RewardOffer> contests =
        _allOffers.where((o) => o.offerType == OfferType.contest).toList();
    List<RewardOffer> activeCampaigns = _allOffers
        .where((o) => o.offerType == OfferType.campaignDonation && o.isActive)
        .toList();

    List<RewardOffer> vouchersAndPoints = _allOffers
        .where((o) =>
            o.offerType == OfferType.voucher ||
            o.offerType == OfferType.travelPoints)
        .toList();

    return Scaffold(
      appBar: _buildAppBar(),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        children: [
          _buildOfferSection("Offres gratuites", freeOffers, Icons.redeem,
              Colors.red.shade400),
          _buildOfferSection("Codes promo", promoCodes, Icons.local_offer,
              Colors.orange.shade400),
          _buildOfferSection(
              "Virements", transfers, Icons.paypal, Colors.blue.shade700),
          _buildOfferSection("Bons d'achat & Points", vouchersAndPoints,
              Icons.storefront, Colors.purple.shade400),
          _buildContestSection(contests),
          _buildSolidaritySection(activeCampaigns),
        ],
      ),
      backgroundColor: Colors.grey[100],
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text('Récompenses',
          style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
      actions: [
        // --- DÉBUT MODIFICATION : BOUTON CLOCHE ---
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.black87),
          tooltip: "Suivi des demandes",
          onPressed: () {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (ctx) => NotificationHistorySheet(userId: user.uid),
              );
            }
          },
        ),
        // --- FIN MODIFICATION ---

        Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: Chip(
            avatar: Icon(Icons.eco,
                color: Theme.of(context).primaryColor, size: 18),
            label: Text("${widget.userProfile.lamePoints} Lame Points",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            backgroundColor: Colors.green.shade50,
          ),
        ),
      ],
    );
  }

  Widget _buildConvertirTab(
    List<RewardOffer> freeOffers,
    List<RewardOffer> promoCodes,
    List<RewardOffer> transfers,
    List<RewardOffer> contests,
    List<RewardOffer> activeCampaigns,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16.0),
      children: [
        _buildOfferSection(
            "Offres gratuites", freeOffers, Icons.redeem, Colors.red.shade400),
        _buildOfferSection("Codes promo", promoCodes, Icons.local_offer,
            Colors.orange.shade400),
        _buildOfferSection(
            "Virements", transfers, Icons.paypal, Colors.blue.shade700),
        _buildContestSection(contests),
        _buildSolidaritySection(activeCampaigns),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
      child: Text(
        title,
        style: GoogleFonts.poppins(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildOfferSection(String title, List<RewardOffer> offers,
      IconData defaultIcon, Color defaultColor) {
    if (offers.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title),
        ...offers
            .map((offer) =>
                _buildStandardOfferCard(offer, defaultIcon, defaultColor))
            .toList(),
        const SizedBox(height: 16),
      ],
    );
  }

  void _handleOfferClick(RewardOffer offer) {
    print(
        "Gestion du clic sur l'offre : ${offer.title}, type: ${offer.offerType}");

    if (offer.offerType == OfferType.contest) {
      final contestType = offer.detailsJson?['type'] as String?;
      if (contestType == 'auction') {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => AuctionScreen(offer: offer)));
      } else if (contestType == 'raffle') {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => RaffleTicketScreen(offer: offer)));
      } else {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  "Détails du concours '${offer.title}' non disponibles.")));
      }
      return;
    }

    if (offer.offerType == OfferType.campaignDonation) {
      Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => CampaignDetailPage(offer: offer)))
          .then((_) => _fetchOffersFromFirestore());
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OfferActionPage(
          offer: offer,
          userProfile: widget.userProfile,
          onClaimOffer: _spendLamePoints,
        ),
      ),
    );
  }

  void _showPromoCodeDialog(String offerTitle, String code) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(offerTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                "Voici votre code promo ! Copiez-le et utilisez-le chez notre partenaire."),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200)),
              child: SelectableText(
                code,
                style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal.shade700),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("Fermer")),
        ],
      ),
    );
  }

  void _showConfirmationDialog(String offerTitle) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green),
            SizedBox(width: 10),
            Text("Demande reçue !"),
          ],
        ),
        content: Text(
            "Votre demande pour \"$offerTitle\" a bien été prise en compte. Elle sera traitée manuellement et vous recevrez une confirmation."),
        actions: [
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text("OK")),
        ],
      ),
    );
  }

  Widget _buildStandardOfferCard(
      RewardOffer offer, IconData defaultIcon, Color defaultColor) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: InkWell(
        onTap: () => _handleOfferClick(offer),
        borderRadius: BorderRadius.circular(12.0),
        child: ListTile(
          leading: CircleAvatar(
            radius: 25,
            backgroundColor: defaultColor.withOpacity(0.15),
            child: offer.getIconWidget(size: 26, color: defaultColor),
          ),
          title: Text(
            offer.title,
            style:
                GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            offer.brandName ?? "Partenaire CleanPlanet",
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
          ),
          trailing:
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildContestSection(List<RewardOffer> contests) {
    if (contests.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Jeux concours"),
        SizedBox(
          height: 220,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: contests.length,
            itemBuilder: (context, index) {
              return _buildContestCard(contests[index]);
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildContestCard(RewardOffer offer) {
    final isAuction = offer.detailsJson?['type'] == 'auction';
    final contestTypeName = isAuction ? "ENCHÈRE" : "TIRAGE";
    final costText = isAuction
        ? "Mise min: ${(offer.detailsJson?['min_bid'] as num?)?.toDouble()?.toStringAsFixed(1) ?? '0.0'} Lame Points"
        : "${offer.ecoCost ?? 0} Lame Points / ticket";

    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.45,
      child: Card(
        margin: const EdgeInsets.only(right: 12.0),
        clipBehavior: Clip.antiAlias,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
        elevation: 3,
        child: InkWell(
          onTap: () => _handleOfferClick(offer),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 100,
                width: double.infinity,
                color: Colors.red.shade400,
                child: offer.getIconWidget(size: 40, color: Colors.white),
              ),
              Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contestTypeName,
                      style: GoogleFonts.poppins(
                        fontSize: 10,
                        color: Colors.red.shade700,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      offer.title,
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.2),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      costText,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Theme.of(context).primaryColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSolidaritySection(List<RewardOffer> activeCampaigns) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle("Dons et solidarité"),
        _buildSDGGrid(),
        _buildPlantTreeCard(),
        if (activeCampaigns.isNotEmpty)
          ...activeCampaigns
              .map((campaign) => _buildCampaignCard(campaign))
              .toList(),
      ],
    );
  }

  Widget _buildSDGGrid() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "17 Objectifs de Développement Durable",
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 12.0),
              child: Text(
                "Total récolté : $_totalSdgCollectedDisplay Lame Points",
                style: GoogleFonts.poppins(
                    fontSize: 13, color: Colors.grey.shade700),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: _sdgData.length,
              itemBuilder: (context, index) {
                final sdg = _sdgData[index];
                final imageUrl = sdg['imageUrl'] as String?;
                return Tooltip(
                  message: "${sdg['name']}",
                  child: InkWell(
                    onTap: () => _showSdgDonationDialog(sdg),
                    borderRadius: BorderRadius.circular(8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8.0),
                      child: (imageUrl != null && imageUrl.isNotEmpty)
                          ? Image.asset(
                              imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                    color: Colors.grey[200],
                                    child: const Icon(Icons.error_outline,
                                        color: Colors.red));
                              },
                            )
                          : Container(color: Colors.grey[300]),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlantTreeCard() {
    final isConfirming = _treePlantConfirming;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      elevation: 2,
      color: isConfirming ? Colors.orange.shade100 : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: InkWell(
        onTap: _plantTreeConfirmation,
        borderRadius: BorderRadius.circular(12.0),
        child: ListTile(
          leading: CircleAvatar(
            radius: 25,
            backgroundColor:
                isConfirming ? Colors.orange.shade600 : Colors.green.shade600,
            child: Text(
              "1k",
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18),
            ),
          ),
          title: Text(
            isConfirming ? "Confirmer pour planter" : "Planter un arbre",
            style:
                GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            "Coût : 1000.0 Lame Points",
            style: GoogleFonts.poppins(
              fontSize: 13,
              color:
                  isConfirming ? Colors.orange.shade800 : Colors.grey.shade600,
            ),
          ),
          trailing: const Icon(Icons.touch_app, color: Colors.grey),
        ),
      ),
    );
  }

  Widget _buildCampaignCard(RewardOffer offer) {
    double progress = 0.0;
    String progressText = "";
    if (offer.detailsJson != null) {
      final int current = offer.detailsJson!['current_amount_eco'] ?? 0;
      final int target = offer.detailsJson!['target_amount_eco'] ?? 1;
      if (target > 0) progress = (current / target).clamp(0.0, 1.0);
      progressText = "${(progress * 100).toStringAsFixed(0)}% atteint";
    }
    final String donorsText =
        "${offer.detailsJson?['current_donors'] ?? 0} donateur${(offer.detailsJson?['current_donors'] ?? 0) > 1 ? 's' : ''}";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      elevation: 3,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
      child: InkWell(
        onTap: () => _handleOfferClick(offer),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (offer.imageUrl != null && offer.imageUrl!.startsWith('http'))
              CachedNetworkImage(
                imageUrl: offer.imageUrl!,
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  height: 150,
                  color: Colors.grey[300],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (context, url, error) => Container(
                  height: 150,
                  color: Colors.grey[300],
                  child: const Icon(Icons.error),
                ),
              )
            else
              Container(height: 150, color: Colors.grey[300]),
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(offer.title,
                      style: GoogleFonts.poppins(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(
                        Theme.of(context).primaryColor),
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(progressText,
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.w500)),
                      Text(donorsText,
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.blueGrey.shade700)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBonsPlansTab(List<RewardOffer> bonsPlansOffers) {
    if (bonsPlansOffers.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text("Aucun bon plan disponible.",
                  style: GoogleFonts.poppins())));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: bonsPlansOffers
          .map((offer) => _buildOldConvertirCard(offer))
          .toList(),
    );
  }

  Widget _buildOldConvertirCard(RewardOffer offer) {
    Widget imageDisplay;
    if (offer.imageUrl != null && offer.imageUrl!.startsWith('http')) {
      imageDisplay = CachedNetworkImage(
        imageUrl: offer.imageUrl!,
        width: 60,
        height: 60,
        fit: BoxFit.contain,
        placeholder: (c, u) => const SizedBox(
            width: 60,
            height: 60,
            child: Center(
                child: CircularProgressIndicator(
              strokeWidth: 2,
            ))),
        errorWidget: (c, u, e) =>
            offer.getIconWidget(size: 30, color: Colors.blueGrey.shade700),
      );
    } else {
      imageDisplay =
          offer.getIconWidget(size: 30, color: Colors.blueGrey.shade700);
    }

    return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
        elevation: 2,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        child: InkWell(
          onTap: () => _handleOfferClick(offer),
          borderRadius: BorderRadius.circular(10.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              children: [
                Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(8.0)),
                    child: Center(child: imageDisplay)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(offer.brandName ?? "Partenaire",
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.grey[600])),
                      Text(offer.title,
                          style: GoogleFonts.poppins(
                              fontSize: 15, fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      Text(
                          "${offer.ecoCost ?? 0} Lame Points = ${offer.valueText ?? 'Valeur non spécifiée'}",
                          style: GoogleFonts.poppins(
                              fontSize: 13,
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_ios,
                    size: 16, color: Colors.grey),
              ],
            ),
          ),
        ));
  }
}

class OfferActionPage extends StatefulWidget {
  final RewardOffer offer;
  final UserProfile userProfile;
  // Mise à jour de la signature du callback
  final Future<bool> Function(
          double amount, String offerId, String offerTitle, String email)
      onClaimOffer;

  const OfferActionPage({
    super.key,
    required this.offer,
    required this.userProfile,
    required this.onClaimOffer,
  });

  @override
  State<OfferActionPage> createState() => _OfferActionPageState();
}

class _OfferActionPageState extends State<OfferActionPage> {
  bool _isOfferClaimed = false;
  bool _isClaiming = false;
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    // Pré-remplir avec l'email du compte si disponible
    final userEmail = FirebaseAuth.instance.currentUser?.email;
    if (userEmail != null) {
      _emailController.text = userEmail;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _claimOffer() async {
    // 1. Validation du formulaire
    if (!_formKey.currentState!.validate()) return;

    final double cost = widget.offer.ecoCost?.toDouble() ?? 0.0;

    if (widget.userProfile.lamePoints < cost) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Vous n'avez pas assez de Lame Points !"),
          backgroundColor: Colors.orange));
      return;
    }

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Confirmer l'action"),
        content: Text(
            "Voulez-vous vraiment utiliser ${cost.toStringAsFixed(0)} Lame Points pour obtenir \"${widget.offer.title}\" ?\n\nLa récompense sera envoyée à : ${_emailController.text}"),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Annuler")),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Confirmer")),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isClaiming = true);
    try {
      // 2. Appel de la fonction avec l'email saisi
      final bool success = await widget.onClaimOffer(cost, widget.offer.id,
          widget.offer.title, _emailController.text.trim());

      if (success) {
        setState(() {
          _isOfferClaimed = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Demande envoyée ! Vous recevrez un email sous peu."),
            backgroundColor: Colors.green));
      }
    } finally {
      setState(() => _isClaiming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double cost = widget.offer.ecoCost?.toDouble() ?? 0.0;
    final bool canAfford = widget.userProfile.lamePoints >= cost;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 200,
              color: Colors.grey[300],
              child: widget.offer.imageUrl != null &&
                      widget.offer.imageUrl!.startsWith('http')
                  ? CachedNetworkImage(
                      imageUrl: widget.offer.imageUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) =>
                          const Center(child: CircularProgressIndicator()),
                      errorWidget: (context, url, error) => Center(
                          child: widget.offer.getIconWidget(
                              size: 80,
                              color: Colors.grey.shade400.withOpacity(0.5))),
                    )
                  : Center(
                      child: widget.offer.getIconWidget(
                          size: 80,
                          color: Colors.grey.shade400.withOpacity(0.5))),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                // Ajout du Formulaire
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.offer.expiryDate != null
                          ? "Expire dans ${widget.offer.expiryDate!.difference(DateTime.now()).inDays} jours"
                          : "Offre permanente",
                      style: GoogleFonts.poppins(
                          color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.offer.title,
                        style: GoogleFonts.poppins(
                            fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("Par ${widget.offer.brandName ?? 'Partenaire'}",
                        style: GoogleFonts.poppins(
                            fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 24),

                    // --- NOUVELLE SECTION EMAIL ---
                    Text("Adresse de réception:",
                        style: GoogleFonts.poppins(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: "votre.email@exemple.com",
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.email_outlined),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez entrer votre email';
                        }
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Email invalide';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    // ------------------------------

                    Text("Vous recevez:",
                        style: GoogleFonts.poppins(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(10)),
                      child: Text(
                          widget.offer.valueText ?? "Un avantage exclusif!",
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(height: 24),
                    Text("À Propos de l'offre:",
                        style: GoogleFonts.poppins(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(widget.offer.description,
                        style: GoogleFonts.poppins(fontSize: 15, height: 1.5)),

                    if (_isOfferClaimed) ...[
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.shade200)),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.green),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(
                                    "Demande enregistrée pour ${_emailController.text}",
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green))),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: (_isOfferClaimed || !canAfford || _isClaiming)
              ? null
              : _claimOffer,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _isOfferClaimed ? Colors.grey : Theme.of(context).primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isClaiming
              ? const SizedBox(
                  height: 24,
                  width: 24,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 3,
                  ))
              : Text(
                  _isOfferClaimed
                      ? "Offre Réclamée"
                      : (cost > 0
                          ? "Obtenir pour ${cost.toStringAsFixed(0)} Lames"
                          : "Obtenir Gratuitement"),
                  style:
                      GoogleFonts.poppins(fontSize: 16, color: Colors.white)),
        ),
      ),
    );
  }
}

class AuctionScreen extends StatefulWidget {
  final RewardOffer offer;
  const AuctionScreen({super.key, required this.offer});

  @override
  _AuctionScreenState createState() => _AuctionScreenState();
}

class _AuctionScreenState extends State<AuctionScreen> {
  final TextEditingController _bidController = TextEditingController();
  double _currentBidInput = 0.0;
  String? _contestIdRef;
  Map<String, dynamic>? _contestDetails;
  bool _isLoadingContest = true;
  String? _errorMessage;
  Timer? _pollingTimer;

  late String _productName;
  String? _productImageUrl;
  late double _minBid;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _parseOfferDetails();
    _currentBidInput = _minBid;
    _bidController.text = _currentBidInput.toStringAsFixed(1);
    _bidController.addListener(() {
      final newBid = double.tryParse(_bidController.text);
      if (newBid != null) {
        setState(() => _currentBidInput = newBid);
      }
    });

    if (_contestIdRef != null) {
      _fetchContestDetails();
      _pollingTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
        if (mounted &&
            _contestIdRef != null &&
            _contestDetails?['status'] == 'open') {
          _fetchContestDetails(isSilent: true);
        }
      });
    } else {
      setState(() {
        _isLoadingContest = false;
        _errorMessage = "Référence du concours manquante.";
      });
    }
  }

  @override
  void dispose() {
    _bidController.dispose();
    _pollingTimer?.cancel();
    super.dispose();
  }

  void _parseOfferDetails() {
    _productName =
        widget.offer.detailsJson?['product_name'] ?? widget.offer.title;
    _productImageUrl =
        widget.offer.detailsJson?['product_image_url'] ?? widget.offer.imageUrl;
    _minBid =
        (widget.offer.detailsJson?['min_bid'] as num?)?.toDouble() ?? 10.0;
    _contestIdRef = widget.offer.detailsJson?['contest_id_ref'] as String?;
  }

  Future<void> _fetchContestDetails({bool isSilent = false}) async {
    if (_contestIdRef == null) return;
    if (!isSilent && mounted) {
      setState(() {
        _isLoadingContest = true;
        _errorMessage = null;
      });
    }

    try {
      final docSnapshot =
          await _firestore.collection('contests').doc(_contestIdRef).get();

      if (mounted) {
        if (docSnapshot.exists && docSnapshot.data() != null) {
          final data = docSnapshot.data()!;

          String? highestBidderUsername;
          if (data['highest_bidder_user_id'] != null) {
            final bidderProfile = await _firestore
                .collection('users')
                .doc(data['highest_bidder_user_id'])
                .get();
            highestBidderUsername =
                bidderProfile.data()?['username'] as String?;
          }

          setState(() {
            _contestDetails = {
              ...data,
              'highest_bidder_profile': {'username': highestBidderUsername},
            };
            if (!isSilent) _isLoadingContest = false;

            double dbHighestBid =
                (_contestDetails?['current_highest_bid'] as num?)?.toDouble() ??
                    _minBid;
            if (_currentBidInput <= dbHighestBid && dbHighestBid >= _minBid) {
              _currentBidInput = dbHighestBid + 0.1;
              _bidController.text = _currentBidInput.toStringAsFixed(1);
            } else if (_currentBidInput < _minBid) {
              _currentBidInput = _minBid;
              _bidController.text = _currentBidInput.toStringAsFixed(1);
            }
          });
        } else {
          setState(() {
            _errorMessage =
                "Détails du concours non trouvés (ID: $_contestIdRef). Vérifiez que l'enchère existe dans Firestore.";
            if (!isSilent) _isLoadingContest = false;
          });
        }
      }
    } catch (e) {
      print("Error fetching contest details from Firestore: $e");
      if (mounted) {
        setState(() {
          if (!isSilent) _isLoadingContest = false;
          _errorMessage = "Erreur chargement enchère: $e";
        });
      }
    }
  }

  Future<void> _placeBid() async {
    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Connectez-vous pour enchérir."),
            backgroundColor: Colors.red));
      return;
    }
    final currentUserId = currentUser.uid;

    // Récupérer le solde réel (lame_points) depuis users/{uid}
    final currentUserDocSnapshot =
        await _firestore.collection('users').doc(currentUserId).get();
    final double currentUserLamePoints =
        (currentUserDocSnapshot.data()?['lame_points'] as num?)?.toDouble() ??
            0.0;

    if (_contestDetails == null || _contestDetails!['status'] != 'open') {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("L'enchère n'est pas ouverte."),
            backgroundColor: Colors.orange));
      return;
    }

    // Accepte end_date en String ISO ou en Timestamp Firestore
    DateTime? endDate;
    final rawEndDate = _contestDetails!['end_date'];
    if (rawEndDate is String) {
      endDate = DateTime.tryParse(rawEndDate);
    } else if (rawEndDate is Timestamp) {
      endDate = rawEndDate.toDate();
    }

    if (endDate == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Date de fin invalide pour l'enchère."),
            backgroundColor: Colors.red));
      return;
    }
    if (DateTime.now().isAfter(endDate)) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("L'enchère est terminée."),
            backgroundColor: Colors.orange));
      _fetchContestDetails();
      return;
    }

    final double bidAmount = _currentBidInput;
    final double currentHighestBid =
        (_contestDetails?['current_highest_bid'] as num?)?.toDouble() ??
            _minBid;
    final String? currentHighestBidderId =
        _contestDetails?['highest_bidder_user_id'] as String?;

    if (bidAmount <= currentHighestBid) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Votre enchère doit être supérieure à ${currentHighestBid.toStringAsFixed(1)} Lame Points."),
            backgroundColor: Colors.orange));
      return;
    }
    if (bidAmount < _minBid) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Mise minimale: ${_minBid.toStringAsFixed(1)} Lame Points."),
            backgroundColor: Colors.orange));
      return;
    }
    if (bidAmount > currentUserLamePoints) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Pas assez de Lame Points."),
            backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoadingContest = true);

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('placeBid');
      final response = await callable.call({
        'contestId': _contestIdRef,
        'bidAmount': bidAmount,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Enchère placée avec succès !"),
            backgroundColor: Colors.green));
        _fetchContestDetails();
      }
    } catch (e) {
      print("Error placing bid via Cloud Function: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur enchère: ${e.toString().split("\n").first}"),
            backgroundColor: Colors.red));
        _fetchContestDetails();
      }
    } finally {
      if (mounted) setState(() => _isLoadingContest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userLamePoints = Get.find<UserStatsController>().totalLameGained;

    final double displayHighestBid =
        (_contestDetails?['current_highest_bid'] as num?)?.toDouble() ??
            (widget.offer.detailsJson?['current_highest_bid'] as num?)
                ?.toDouble() ??
            _minBid;
    final String? highestBidderUserId =
        _contestDetails?['highest_bidder_user_id'] as String?;
    String highestBidderUsername = highestBidderUserId != null
        ? (_contestDetails?['highest_bidder_profile']?['username'] ??
            'Chargement...')
        : 'Aucun';

    final String? contestStatus = _contestDetails?['status'] as String?;
    DateTime? endDate;
    if (_contestDetails?['end_date'] is String) {
      endDate = DateTime.tryParse(_contestDetails!['end_date']);
    } else if (_contestDetails?['end_date'] is Timestamp) {
      endDate = (_contestDetails!['end_date'] as Timestamp).toDate();
    }

    bool isAuctionOpen = contestStatus == 'open' &&
        (endDate == null || DateTime.now().isBefore(endDate));

    if (_isLoadingContest && _contestDetails == null && _errorMessage == null) {
      return Scaffold(
          appBar: AppBar(title: Text(_productName)),
          body: const Center(child: CircularProgressIndicator()));
    }
    if (_errorMessage != null && _contestDetails == null) {
      return Scaffold(
          appBar: AppBar(title: Text(_productName)),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text("Erreur: $_errorMessage",
                      style: const TextStyle(color: Colors.red)))));
    }

    return Scaffold(
      backgroundColor: Colors.green.shade700,
      appBar: AppBar(
        title: Text("Enchérir: $_productName",
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
        actions: [
          if (_isLoadingContest)
            const Padding(
                padding: EdgeInsets.only(right: 16.0),
                child: Center(
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))))
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_productImageUrl != null &&
                _productImageUrl!.startsWith('http'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: CachedNetworkImage(
                  imageUrl: _productImageUrl!,
                  height: 200,
                  fit: BoxFit.contain,
                  placeholder: (c, u) => const Center(
                      child: CircularProgressIndicator(color: Colors.white)),
                  errorWidget: (c, u, e) => const Icon(Icons.broken_image,
                      size: 100, color: Colors.white60),
                ),
              )
            else
              const SizedBox(
                  height: 200,
                  child: Center(
                      child: Icon(Icons.inventory_2_outlined,
                          size: 100, color: Colors.white60))),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(widget.offer.description,
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                  textAlign: TextAlign.center),
            ),
            Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(15)),
                child: Column(
                  children: [
                    Text("Votre enchère (Lame Points)",
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: _bidController,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.zero),
                        enabled: isAuctionOpen,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                        "Mise minimale: ${_minBid.toStringAsFixed(1)} Lame Points",
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 11)),
                    Text(
                        "Enchère la plus élevée: ${displayHighestBid.toStringAsFixed(1)} Lame Points ${highestBidderUserId != null && highestBidderUserId != _firebaseAuth.currentUser?.uid ? '(par @$highestBidderUsername)' : '(Aucune enchère)'}",
                        style: GoogleFonts.poppins(
                            color: Colors.yellowAccent, fontSize: 12)),
                    Text(
                        "Vos Lame Points: ${userLamePoints.toStringAsFixed(1)}",
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 12)),
                    if (endDate != null)
                      Text(
                          "Termine le: ${DateFormat('dd/MM/yyyy HH:mm').format(endDate)}",
                          style: GoogleFonts.poppins(
                              color: Colors.white70, fontSize: 11)),
                    if (!isAuctionOpen)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                            contestStatus == 'closed_pending_draw' ||
                                    contestStatus == 'completed'
                                ? "ENCHÈRE TERMINÉE"
                                : "ENCHÈRE PAS ENCORE OUVERTE",
                            style: GoogleFonts.poppins(
                                color: Colors.redAccent,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      )
                  ],
                )),
            if (isAuctionOpen)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 30.0, vertical: 10.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildIncrementDecrementButton(Icons.remove, () {
                      if (_currentBidInput > _minBid) {
                        _bidController.text =
                            (_currentBidInput - 0.1).toStringAsFixed(1);
                      }
                    }),
                    _buildIncrementDecrementButton(Icons.add, () {
                      _bidController.text =
                          (_currentBidInput + 0.1).toStringAsFixed(1);
                    }),
                    _buildIncrementDecrementButton(Icons.exposure_plus_1, () {
                      _bidController.text =
                          (_currentBidInput + 1.0).toStringAsFixed(1);
                    }, labelText: "+1"),
                    _buildIncrementDecrementButton(Icons.exposure_plus_1, () {
                      _bidController.text =
                          (_currentBidInput + 10.0).toStringAsFixed(1);
                    }, labelText: "+10"),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            if (isAuctionOpen)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20),
                child: ElevatedButton(
                  onPressed: _isLoadingContest ? null : _placeBid,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.yellowAccent,
                      foregroundColor: Colors.green.shade900,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: _isLoadingContest
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(color: Colors.green))
                      : Text(
                          "Enchérir ${_currentBidInput.toStringAsFixed(1)} Lame Points",
                          style: GoogleFonts.poppins(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            _buildBidHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildIncrementDecrementButton(IconData icon, VoidCallback onPressed,
      {String? labelText}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.15),
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(15)),
      child: labelText != null
          ? Text(labelText,
              style: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.bold))
          : Icon(icon, size: 22),
    );
  }

  Widget _buildBidHistory() {
    if (_contestIdRef == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("Historique des enchères (récentes):",
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
            future: _firestore
                .collection('contest_entries')
                .where('contest_id', isEqualTo: _contestIdRef)
                .orderBy('created_at', descending: true)
                .limit(5)
                .get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.white));
              }
              if (snapshot.hasError) {
                return Text("Erreur chargement historique: ${snapshot.error}",
                    style: const TextStyle(color: Colors.redAccent));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Text("Aucune enchère placée.",
                    style: TextStyle(color: Colors.white70));
              }
              final bids = snapshot.data!.docs;
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: bids.length,
                itemBuilder: (context, index) {
                  final bidDoc = bids[index].data();
                  final double bidAmount =
                      (bidDoc['submission_data']?['bid_amount'] as num?)
                              ?.toDouble() ??
                          0.0;
                  final userId = bidDoc['user_id'] as String?;
                  final timestamp =
                      (bidDoc['created_at'] as Timestamp?)?.toDate();

                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: userId != null
                        ? _firestore.collection('users').doc(userId).get()
                        : null,
                    builder: (context, userSnapshot) {
                      String bidderUsername = 'Anonyme';
                      if (userSnapshot.connectionState ==
                              ConnectionState.done &&
                          userSnapshot.hasData &&
                          userSnapshot.data!.exists) {
                        bidderUsername =
                            userSnapshot.data!.data()?['username'] ??
                                'Utilisateur inconnu';
                      } else if (userSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        bidderUsername = 'Chargement...';
                      }

                      final bidTime = timestamp != null
                          ? DateFormat('dd/MM HH:mm').format(timestamp)
                          : 'N/A';
                      return Card(
                        color: Colors.black.withOpacity(0.15),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          dense: true,
                          title: Text(
                              "${bidAmount.toStringAsFixed(1)} Lame Points par @$bidderUsername",
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500)),
                          trailing: Text(bidTime,
                              style: GoogleFonts.poppins(
                                  color: Colors.white70, fontSize: 10)),
                        ),
                      );
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class RaffleTicketScreen extends StatefulWidget {
  final RewardOffer offer;
  const RaffleTicketScreen({super.key, required this.offer});

  @override
  _RaffleTicketScreenState createState() => _RaffleTicketScreenState();
}

class _RaffleTicketScreenState extends State<RaffleTicketScreen> {
  final TextEditingController _ticketCountController =
      TextEditingController(text: "1");
  int _ticketCount = 1;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _ticketCountController.addListener(() {
      final newCount = int.tryParse(_ticketCountController.text);
      if (newCount != null && newCount >= 0) {
        setState(() {
          _ticketCount = newCount;
        });
      } else if (_ticketCountController.text.isEmpty) {
        setState(() {
          _ticketCount = 0;
        });
      }
    });
  }

  void _updateTicketCount(String value) {
    if (value == "del") {
      if (_ticketCountController.text.isNotEmpty) {
        if (_ticketCountController.text.length == 1) {
          _ticketCountController.text = "0";
        } else {
          _ticketCountController.text = _ticketCountController.text
              .substring(0, _ticketCountController.text.length - 1);
        }
      }
    } else if (value == ".") {
    } else {
      if (_ticketCountController.text == "0") {
        _ticketCountController.text = value;
      } else {
        _ticketCountController.text += value;
      }
    }
    if (_ticketCountController.text.length > 3) {
      _ticketCountController.text = _ticketCountController.text.substring(0, 3);
    }
  }

  Future<void> _buyTickets() async {
    final userStatsProvider = Get.find<UserStatsController>();
    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Connectez-vous pour acheter des tickets."),
            backgroundColor: Colors.red));
      return;
    }
    final currentUserId = currentUser.uid;

    final int ticketCostLame =
        (widget.offer.detailsJson?['ticket_cost_eco'] as num?)?.toInt() ??
            (widget.offer.ecoCost as num?)?.toInt() ??
            10;
    final int totalCost = _ticketCount * ticketCostLame;

    if (_ticketCount <= 0) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Veuillez entrer un nombre de tickets valide."),
            backgroundColor: Colors.orange));
      return;
    }

    // Lire les vraies lames depuis Firestore (users.lame_points) pour éviter la désynchronisation
    try {
      final userDoc =
          await _firestore.collection('users').doc(currentUserId).get();
      final int realLamePoints =
          (userDoc.data()?['lame_points'] as num?)?.toInt() ?? 0;
      if (totalCost > realLamePoints) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  "Pas assez de Lame Points (vous avez $realLamePoints, coût : $totalCost)."),
              backgroundColor: Colors.orange));
        return;
      }
    } catch (e) {
      // Fallback sur le provider si la lecture Firestore échoue
      final currentUserLamePoints = userStatsProvider.totalLameGained;
      if (totalCost > currentUserLamePoints) {
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("Vous n'avez pas assez de Lame Points."),
              backgroundColor: Colors.orange));
        return;
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('purchaseRaffleTicket');
      final response = await callable.call({
        'contestId': widget.offer.id,
        'ticketCount': _ticketCount,
      });

      final data = response.data != null
          ? Map<String, dynamic>.from(response.data as Map)
          : null;
      final int actualTotalCost =
          (data?['totalCost'] as num?)?.toInt() ?? totalCost;

      userStatsProvider.addLame(-actualTotalCost.toDouble());

      if (mounted) {
        Navigator.pop(context); // Fermer la modale de chargement
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Achat de $_ticketCount ticket(s) réussi pour $actualTotalCost Lame Points!"),
            backgroundColor: Colors.blue));
        Navigator.pop(context); // Fermer la modale du concours
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Fermer la modale de chargement
        print("Error buying tickets via Cloud Function: $e");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur d'achat: ${e.toString().split("\n").first}"),
            backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String productName =
        widget.offer.detailsJson?['product_name'] ?? widget.offer.title;
    final String? productImageUrl =
        widget.offer.detailsJson?['product_image_url'] ?? widget.offer.imageUrl;
    final int ticketCostLame = widget.offer.detailsJson?['ticket_cost_eco'] ??
        widget.offer.ecoCost ??
        10;
    final int totalCost = _ticketCount * ticketCostLame;
    final userLamePoints = Get.find<UserStatsController>().totalLameGained;

    return Scaffold(
      backgroundColor: Colors.green.shade700,
      appBar: AppBar(
        title: Text("Acheter Tickets: $productName",
            style: GoogleFonts.poppins(
                color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context)),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (productImageUrl != null && productImageUrl.startsWith('http'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: CachedNetworkImage(
                  imageUrl: productImageUrl,
                  height: 200,
                  fit: BoxFit.contain,
                  placeholder: (c, u) => const Center(
                      child: CircularProgressIndicator(color: Colors.white)),
                  errorWidget: (c, u, e) => const Icon(Icons.broken_image,
                      size: 100, color: Colors.white60),
                ),
              )
            else
              const SizedBox(
                  height: 200,
                  child: Center(
                      child: Icon(Icons.inventory_2_outlined,
                          size: 100, color: Colors.white60))),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                widget.offer.description,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            Container(
                margin:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(15)),
                child: Column(
                  children: [
                    Text("Nombre de participations",
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 5),
                    Text(_ticketCountController.text,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 40,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text(
                        "Coût total: $totalCost Lame Points ($ticketCostLame Lame Points/ticket)",
                        style: GoogleFonts.poppins(
                            color: Colors.yellowAccent, fontSize: 12)),
                    Text(
                        "Vos Lame Points: ${userLamePoints.toStringAsFixed(1)}",
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 12)),
                  ],
                )),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [1, 2, 3]
                          .map((n) => _buildNumberButton(n.toString()))
                          .toList()),
                  const SizedBox(height: 10),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [4, 5, 6]
                          .map((n) => _buildNumberButton(n.toString()))
                          .toList()),
                  const SizedBox(height: 10),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [7, 8, 9]
                          .map((n) => _buildNumberButton(n.toString()))
                          .toList()),
                  const SizedBox(height: 10),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildNumberButton("", isIcon: false, flex: 1),
                        _buildNumberButton("0", flex: 1),
                        _buildNumberButton("del",
                            isIcon: true,
                            icon: Icons.backspace_outlined,
                            flex: 1),
                      ]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20),
              child: ElevatedButton(
                onPressed: _buyTickets,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellowAccent,
                    foregroundColor: Colors.green.shade900,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                child: Text(
                    "Acheter ${_ticketCount} participation${_ticketCount > 1 ? 's' : ''}",
                    style: GoogleFonts.poppins(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildNumberButton(String text,
      {bool isIcon = false, IconData? icon, int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: ElevatedButton(
          onPressed: () => _updateTicketCount(text),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.15),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 18)),
          child: isIcon
              ? Icon(icon, size: 24)
              : Text(text,
                  style: GoogleFonts.poppins(
                      fontSize: 22, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ticketCountController.dispose();
    super.dispose();
  }
}

class CampaignDetailPage extends StatefulWidget {
  final RewardOffer offer;
  const CampaignDetailPage({super.key, required this.offer});

  @override
  _CampaignDetailPageState createState() => _CampaignDetailPageState();
}

class _CampaignDetailPageState extends State<CampaignDetailPage> {
  late int currentAmount;
  late int targetAmount;
  late int donors;
  late double progress;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;

  @override
  void initState() {
    super.initState();
    _fetchCampaignDetails();
  }

  Future<void> _fetchCampaignDetails() async {
    try {
      final docSnapshot =
          await _firestore.collection('rewards').doc(widget.offer.id).get();
      if (docSnapshot.exists && docSnapshot.data() != null) {
        final details =
            docSnapshot.data()!['details_json'] as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _updateCampaignDetails(details);
          });
        }
      }
    } catch (e) {
      print("Error fetching campaign details: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur de chargement de la campagne: $e"),
            backgroundColor: Colors.red));
      }
    }
  }

  void _updateCampaignDetails(Map<String, dynamic>? details) {
    currentAmount = (details?['current_amount_eco'] as num?)?.toInt() ?? 0;
    targetAmount = (details?['target_amount_eco'] as num?)?.toInt() ?? 1;
    donors = (details?['current_donors'] as num?)?.toInt() ?? 0;
    progress =
        targetAmount > 0 ? (currentAmount / targetAmount).clamp(0.0, 1.0) : 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final TextEditingController donationController = TextEditingController();

    return Scaffold(
      appBar: AppBar(title: Text(widget.offer.title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.offer.imageUrl != null &&
                widget.offer.imageUrl!.startsWith('http'))
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: widget.offer.imageUrl!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (c, u) =>
                      const Center(child: CircularProgressIndicator()),
                  errorWidget: (c, u, e) =>
                      const Icon(Icons.broken_image, size: 100),
                ),
              ),
            const SizedBox(height: 16),
            Text(widget.offer.title,
                style: GoogleFonts.poppins(
                    fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(widget.offer.description,
                style:
                    GoogleFonts.poppins(fontSize: 16, color: Colors.grey[700])),
            const SizedBox(height: 24),
            Text("Progrès: $currentAmount / $targetAmount Lame Points",
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
              backgroundColor: Colors.grey[300],
              valueColor:
                  AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
            ),
            const SizedBox(height: 8),
            Text("$donors donateurs ont déjà contribué!",
                style: GoogleFonts.poppins(color: Colors.grey[600])),
            const SizedBox(height: 24),
            TextField(
              controller: donationController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Montant de votre don (en Lame Points)",
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon:
                    Icon(Icons.eco, color: Theme.of(context).primaryColor),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final amount = int.tryParse(donationController.text);
                final currentUser = _firebaseAuth.currentUser;

                if (currentUser == null) {
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Vous devez être connecté."),
                        backgroundColor: Colors.red));
                  return;
                }
                final currentUserId = currentUser.uid;

                if (amount == null || amount <= 0) {
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Veuillez entrer un montant valide."),
                        backgroundColor: Colors.orange));
                  return;
                }

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (BuildContext context) {
                    return const Center(child: CircularProgressIndicator());
                  },
                );

                try {
                  await _firestore.runTransaction((transaction) async {
                    final campaignRef =
                        _firestore.collection('rewards').doc(widget.offer.id);
                    final userRef =
                        _firestore.collection('users').doc(currentUserId);

                    // Lectures (doivent être faites avant les écritures)
                    final campaignDoc = await transaction.get(campaignRef);
                    final userDoc = await transaction.get(userRef);

                    if (!campaignDoc.exists || campaignDoc.data() == null) {
                      throw Exception("Campagne non trouvée.");
                    }
                    if (!userDoc.exists || userDoc.data() == null) {
                      throw Exception("Profil utilisateur introuvable.");
                    }

                    final currentCampaignDetails = campaignDoc
                            .data()!['details_json'] as Map<String, dynamic>? ??
                        {};

                    // Vérification du solde lame_points
                    final double currentLamePoints =
                        (userDoc.data()!['lame_points'] as num?)?.toDouble() ??
                            0.0;
                    if (currentLamePoints < amount) {
                      throw Exception(
                          "Fonds insuffisants ($currentLamePoints Lames disponibles).");
                    }

                    // --- ECRITURES ---

                    // 1. Mise à jour du solde utilisateur (lame_points)
                    transaction.update(userRef, {
                      'lame_points': FieldValue.increment(-amount.toDouble()),
                      'updated_at': FieldValue.serverTimestamp(),
                    });

                    // Mise à jour locale (Provider) - Attention, c'est hors transaction mais nécessaire pour l'UI
                    final userStatsProvider = Get.find<UserStatsController>();
                    userStatsProvider.addLame(-amount.toDouble());

                    // 2. Mise à jour de la campagne
                    int newCurrentAmount =
                        (currentCampaignDetails['current_amount_eco'] as num?)
                                ?.toInt() ??
                            0;
                    newCurrentAmount += amount;
                    int newDonors =
                        (currentCampaignDetails['current_donors'] as num?)
                                ?.toInt() ??
                            0;
                    newDonors++;

                    currentCampaignDetails['current_amount_eco'] =
                        newCurrentAmount;
                    currentCampaignDetails['current_donors'] = newDonors;

                    transaction.update(campaignRef, {
                      'details_json': currentCampaignDetails,
                      'updated_at': FieldValue.serverTimestamp(),
                    });

                    // 3. Enregistrement technique du don
                    _firestore.collection('campaign_donations').add({
                      'campaign_id': widget.offer.id,
                      'user_id': currentUserId,
                      'amount_eco': amount.toDouble(),
                      'created_at': FieldValue.serverTimestamp(),
                    });

                    // 4. --- AJOUT POUR LA CLOCHE DE NOTIFICATION ---
                    final notificationRef =
                        _firestore.collection('user_claimed_offers').doc();
                    transaction.set(notificationRef, {
                      'user_id': currentUserId,
                      'reward_id': widget.offer.id,
                      'details': {
                        'offer_title': "Don : ${widget.offer.title}",
                        'claimed_for_lame': amount.toDouble(),
                      },
                      'claimed_at': FieldValue.serverTimestamp(),
                      'status':
                          'approved', // Un don est validé immédiatement (Reçu)
                    });
                    // ------------------------------------------------
                  });

                  if (mounted) {
                    Navigator.of(context).pop(); // Fermer le loader
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            "Merci pour votre don de $amount Lame Points à ${widget.offer.title}!"),
                        backgroundColor: Colors.green));

                    _fetchCampaignDetails(); // Rafraichir l'UI
                    donationController.clear();
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.of(context).pop();
                    print("Erreur de transaction Firestore (donation): $e");
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content:
                            Text("Erreur : ${e.toString().split("\n").first}"),
                        backgroundColor: Colors.red));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: Text("Faire un don",
                  style: GoogleFonts.poppins(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}

class UserStats {
  double totalLameGained;

  UserStats({
    this.totalLameGained = 0.0,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) {
    return UserStats(
      totalLameGained: (json['totalLameGained'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalLameGained': totalLameGained,
    };
  }
}

class UserStatsController extends GetxController {
  UserStats? _userStats;

  UserStats? get userStats => _userStats;

  double get totalLameGained => _userStats?.totalLameGained ?? 0.0;

  void setUserStats(UserStats stats) {
    _userStats = stats;
    update();
  }

  void addLame(double amount) {
    if (_userStats != null && amount > 0) {
      _userStats!.totalLameGained += amount;
      update();
    }
  }
}

class CooldownTimerController extends GetxController {
  final DateTime targetDate;
  final VoidCallback onTimerFinished;
  Timer? _timer;
  final RxString timeString = "".obs;

  CooldownTimerController(
      {required this.targetDate, required this.onTimerFinished});

  @override
  void onInit() {
    super.onInit();
    updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => updateTime());
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }

  void updateTime() {
    final diff = targetDate.difference(DateTime.now());
    if (diff.isNegative) {
      _timer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) => onTimerFinished());
    } else {
      int h = diff.inHours;
      int m = diff.inMinutes.remainder(60);
      int s = diff.inSeconds.remainder(60);
      timeString.value =
          "${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}";
    }
  }
}

class CooldownTimerWidget extends StatelessWidget {
  final DateTime targetDate;
  final VoidCallback onTimerFinished;

  const CooldownTimerWidget({
    Key? key,
    required this.targetDate,
    required this.onTimerFinished,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final controller = Get.put(
      CooldownTimerController(
          targetDate: targetDate, onTimerFinished: onTimerFinished),
      tag: targetDate.toIso8601String(),
    );

    return Obx(() => Text(
          "Revenez demain ! (${controller.timeString.value})",
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54),
        ));
  }
}

class SecurityBlockedScreen extends StatelessWidget {
  final String reason;
  const SecurityBlockedScreen({Key? key, required this.reason})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.red.shade900,
        body: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.security, size: 80, color: Colors.white),
              const SizedBox(height: 20),
              const Text(
                "Accès Refusé",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                reason,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              const SizedBox(height: 30),
              const Text(
                "Pour des raisons de sécurité et d'équité, l'application ne peut pas fonctionner sur cet appareil.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationHistorySheet extends StatefulWidget {
  final String userId;

  const NotificationHistorySheet({Key? key, required this.userId})
      : super(key: key);

  @override
  State<NotificationHistorySheet> createState() =>
      _NotificationHistorySheetState();
}

class _NotificationHistorySheetState extends State<NotificationHistorySheet> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.notifications_active_rounded,
                  color: Color(0xFF388E3C)),
              const SizedBox(width: 10),
              Text("Suivi des demandes",
                  style: GoogleFonts.poppins(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context))
            ],
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('user_claimed_offers')
                  .where('user_id', isEqualTo: widget.userId)
                  .orderBy('claimed_at', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                // 1. Gestion des erreurs (IMPORTANT POUR L'INDEX)
                if (snapshot.hasError) {
                  final String errorString = snapshot.error.toString();
                  final bool requiresIndex =
                      errorString.contains('requires an index') ||
                          errorString.contains('PERMISSION_DENIED');

                  print("Erreur Firestore: $errorString");

                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            requiresIndex
                                ? "Requête nécessite un index composite Firestore (user_id + claimed_at)."
                                : "Erreur de chargement des offres réclamées.",
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Détails techniques : $errorString",
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.grey, fontSize: 12),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton(
                            onPressed: () async {
                              // Permettre une tentative de récupération sans index composite.
                              await Future.delayed(
                                  const Duration(milliseconds: 100));
                              if (mounted) setState(() {});
                            },
                            child: const Text('Recharger / evidement fallback'),
                          ),
                          const SizedBox(height: 20),
                          FutureBuilder<QuerySnapshot>(
                            future: FirebaseFirestore.instance
                                .collection('user_claimed_offers')
                                .where('user_id', isEqualTo: widget.userId)
                                .limit(50)
                                .get(),
                            builder: (context, fallbackSnapshot) {
                              if (fallbackSnapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 16),
                                  child: CircularProgressIndicator(),
                                );
                              }
                              if (fallbackSnapshot.hasError) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 16),
                                  child: Text(
                                    'Fallback aussi échoué : ${fallbackSnapshot.error}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.red, fontSize: 12),
                                  ),
                                );
                              }
                              final docs = fallbackSnapshot.data?.docs ?? [];
                              if (docs.isEmpty) {
                                return const Padding(
                                  padding: EdgeInsets.only(top: 16),
                                  child: Text(
                                    'Aucune entrée disponible en fallback.',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                );
                              }

                              return Container(
                                height: 240,
                                padding: const EdgeInsets.only(top: 16),
                                child: ListView.separated(
                                  itemCount: docs.length,
                                  separatorBuilder: (ctx, i) => const Divider(),
                                  itemBuilder: (context, i) {
                                    final data =
                                        docs[i].data() as Map<String, dynamic>;
                                    final String title = data['details']
                                            ?['offer_title'] ??
                                        'Action';
                                    final Timestamp? dateTs =
                                        data['claimed_at'] as Timestamp?;
                                    final String dateStr = dateTs != null
                                        ? DateFormat('dd/MM à HH:mm')
                                            .format(dateTs.toDate())
                                        : '--/--';
                                    return ListTile(
                                      title: Text(title),
                                      subtitle: Text(dateStr),
                                    );
                                  },
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history, size: 60, color: Colors.grey[300]),
                        const SizedBox(height: 10),
                        Text("Aucune activité récente.",
                            style: GoogleFonts.poppins(color: Colors.grey)),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  itemCount: snapshot.data!.docs.length,
                  separatorBuilder: (ctx, i) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final doc = snapshot.data!.docs[index];
                    final data = doc.data() as Map<String, dynamic>;

                    final String title =
                        data['details']?['offer_title'] ?? "Action Inconnue";
                    final double cost =
                        (data['details']?['claimed_for_lame'] as num?)
                                ?.toDouble() ??
                            0.0;
                    final Timestamp? dateTs = data['claimed_at'] as Timestamp?;
                    final String dateStr = dateTs != null
                        ? DateFormat('dd/MM à HH:mm').format(dateTs.toDate())
                        : "--/--";

                    final String status = data['status'] ?? 'pending';

                    Color statusColor;
                    String statusText;
                    IconData statusIcon;

                    if (status == 'approved' || status == 'recus') {
                      statusColor = Colors.green;
                      statusText = "Validé";
                      statusIcon = Icons.check_circle;
                    } else if (status == 'rejected') {
                      statusColor = Colors.red;
                      statusText = "Refusé";
                      statusIcon = Icons.cancel;
                    } else {
                      statusColor = Colors.orange;
                      statusText = "En attente";
                      statusIcon = Icons.hourglass_bottom;
                    }

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 0),
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withOpacity(0.1),
                        child: Icon(statusIcon, color: statusColor),
                      ),
                      title: Text(title,
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(
                          "$dateStr • -${cost.toStringAsFixed(0)} Lames",
                          style: GoogleFonts.poppins(
                              fontSize: 12, color: Colors.grey)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: statusColor.withOpacity(0.5))),
                        child: Text(
                          statusText,
                          style: GoogleFonts.poppins(
                              color: statusColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// 🚀 FILTRE KINÉMATIQUE FLUIDE (AVANCÉE CONTINUE SANS RALENTISSEMENT)
// ===========================================================================
class KinematicFilter {
  // Points clés de rendu
  LatLng? simulatedPos; // Position actuelle de la flèche à l'écran
  Position? lastRealPos; // Dernière position GPS lissée

  // Chaîne des positions GPS brutes pour le diagnostic
  Position? _currentRawGps; // 🟡 JAUNE = GPS actuel
  Position? _previousRawGps; // 🟢 VERT  = GPS t-1
  Position? _previousPreviousRawGps; // 🔴 ROUGE = GPS t-2

  LatLng? _targetPos; // 🔵 BLEU = Cible future à +1.0s
  DateTime? _lastGpsTime;
  DateTime? _lastPredictTime;

  double calculatedSpeedMps = 0.0;
  double previousCalculatedSpeedMps = 0.0;
  int lastRouteIndex = -1;

  // ── GETTERS DIAGNOSTIC ──
  LatLng? get pointA => _previousPreviousRawGps != null
      ? LatLng(
          _previousPreviousRawGps!.latitude, _previousPreviousRawGps!.longitude)
      : null; // 🔴 ROUGE

  LatLng? get pointB => _targetPos; // 🔵 BLEU (Cible visée à 1s)

  LatLng? get pointC => _previousRawGps != null
      ? LatLng(_previousRawGps!.latitude, _previousRawGps!.longitude)
      : null; // 🟢 VERT

  LatLng? get rawGpsPos => _currentRawGps != null
      ? LatLng(_currentRawGps!.latitude, _currentRawGps!.longitude)
      : null; // 🟡 JAUNE

  /// Réception d'un nouveau point GPS réel (Intervalle ~1 seconde)
  void updateRealPosition(Position rawPos) {
    // 1. Décalage de la chaîne d'historique GPS
    _previousPreviousRawGps = _previousRawGps;
    _previousRawGps = _currentRawGps;
    _currentRawGps = rawPos;

    // 2. Calcul de la vitesse Doppler / secours distance
    double vInst = rawPos.speed;
    if (vInst <= 0 || vInst == 1.0) {
      if (lastRealPos != null) {
        double d = Geolocator.distanceBetween(
          lastRealPos!.latitude,
          lastRealPos!.longitude,
          rawPos.latitude,
          rawPos.longitude,
        );
        double dt =
            rawPos.timestamp.difference(lastRealPos!.timestamp).inMilliseconds /
                1000.0;
        if (dt > 0.05) vInst = d / dt;
      }
    }

    previousCalculatedSpeedMps = calculatedSpeedMps;

    // Lissage progressif de la vitesse (EMA)
    if (calculatedSpeedMps == 0.0) {
      calculatedSpeedMps = vInst;
    } else {
      calculatedSpeedMps = (calculatedSpeedMps * 0.3) + (vInst * 0.7);
    }

    if (calculatedSpeedMps < 0.4) calculatedSpeedMps = 0.0;

    lastRealPos = rawPos;
    _lastGpsTime = DateTime.now();

    // Première initialisation si la carte vient de s'ouvrir
    if (simulatedPos == null) {
      simulatedPos = LatLng(rawPos.latitude, rawPos.longitude);
    }

    _lastPredictTime ??= DateTime.now();
  }

  /// Appelée à chaque frame (60 / 120 FPS via le Ticker VSync)
  LatLng? predictNextPosition(List<LatLng> routePolyline) {
    if (lastRealPos == null || simulatedPos == null) return null;

    DateTime now = DateTime.now();
    double dt = now.difference(_lastPredictTime ?? now).inMilliseconds / 1000.0;
    _lastPredictTime = now;

    // Normalisation de la frame (évite les sauts de temps au réveil)
    if (dt <= 0 || dt > 0.2) dt = 1.0 / 60.0;

    double timeSinceGps = _lastGpsTime != null
        ? now.difference(_lastGpsTime!).inMilliseconds / 1000.0
        : 0.0;

    double moveSpeed = calculatedSpeedMps;

    // ──────────────────────────────────────────────────────────────
    // 1. CALCUL DE LA VITESSE CIBLE & EXTROPOLATION SANS FREINAGE
    // ──────────────────────────────────────────────────────────────
    if (calculatedSpeedMps > 0.3) {
      LatLng yellowPos = _currentRawGps != null
          ? LatLng(_currentRawGps!.latitude, _currentRawGps!.longitude)
          : LatLng(lastRealPos!.latitude, lastRealPos!.longitude);

      int gpsIndex = _findForwardRouteIndex(yellowPos,
          _currentRawGps?.heading ?? lastRealPos!.heading, routePolyline);

      // Le point BLEU est placé exactement 1.0 seconde devant le point GPS actuel
      double lookaheadDist = math.max(calculatedSpeedMps * 1.0, 2.0);
      _targetPos = _advanceForwardFromGps(
        yellowPos,
        lookaheadDist,
        _currentRawGps?.heading ?? lastRealPos!.heading,
        routePolyline,
        gpsIndex,
      );

      if (_targetPos != null) {
        double distToTarget = Geolocator.distanceBetween(
          simulatedPos!.latitude,
          simulatedPos!.longitude,
          _targetPos!.latitude,
          _targetPos!.longitude,
        );

        // Si le GPS a moins d'1 seconde : On adapte la vitesse pour atteindre le point bleu à t=1.0s
        if (timeSinceGps <= 1.0) {
          double timeRemaining = math.max(0.05, 1.0 - timeSinceGps);
          double requiredSpeed = distToTarget / timeRemaining;

          // Lissage de l'accélération pour éviter les à-coups brutaux
          moveSpeed = math.min(requiredSpeed, calculatedSpeedMps * 1.8);
        }
        // Si le GPS a du retard (> 1.0s) : ON NE RALENTIT PAS !
        // On continue d'avancer le long du tracé à vitesse nominale.
        else {
          moveSpeed = calculatedSpeedMps;
        }
      }
    } else {
      // Si le véhicule est arrêté depuis plus de 2.5 secondes
      if (_lastGpsTime != null &&
          now.difference(_lastGpsTime!).inMilliseconds > 2500) {
        return simulatedPos;
      }
    }

    // ──────────────────────────────────────────────────────────────
    // 2. DÉPLACEMENT EFFECTIF LE LONG DU TRACÉ
    // ──────────────────────────────────────────────────────────────
    double stepDistance = moveSpeed * dt;

    if (stepDistance > 0.0001) {
      int simIndex = _findForwardRouteIndex(
          simulatedPos!, lastRealPos!.heading, routePolyline);
      simulatedPos = _advanceForwardFromGps(
        simulatedPos!,
        stepDistance,
        lastRealPos!.heading,
        routePolyline,
        simIndex,
      );
    }

    return simulatedPos;
  }

  // ══════════════════════════════════════════════════════════════
  // 🎯 Outils de projection géométrique sur polyline
  // ══════════════════════════════════════════════════════════════

  int _findForwardRouteIndex(
      LatLng gpsPos, double heading, List<LatLng> polyline) {
    if (polyline.length < 2) return 0;

    int bestIndex = math.max(0, lastRouteIndex);
    double minScore = double.infinity;

    int searchStart = math.max(0, lastRouteIndex - 5);
    int searchEnd = math.min(polyline.length - 2, lastRouteIndex + 50);

    for (int i = searchStart; i <= searchEnd; i++) {
      LatLng proj = _projectOnSegment(gpsPos, polyline[i], polyline[i + 1]);
      double d = Geolocator.distanceBetween(
          gpsPos.latitude, gpsPos.longitude, proj.latitude, proj.longitude);

      double segBearing = Geolocator.bearingBetween(
          polyline[i].latitude,
          polyline[i].longitude,
          polyline[i + 1].latitude,
          polyline[i + 1].longitude);
      double angleDiff = (segBearing - heading).abs();
      if (angleDiff > 180) angleDiff = 360 - angleDiff;
      double penalty = angleDiff > 90 ? 100.0 : 0.0;

      double score = d + penalty;
      if (score < minScore) {
        minScore = score;
        bestIndex = i;
      }
    }
    lastRouteIndex = bestIndex;
    return bestIndex;
  }

  LatLng _advanceForwardFromGps(
    LatLng startPos,
    double distanceMeters,
    double heading,
    List<LatLng> polyline,
    int startIndex,
  ) {
    if (polyline.length < 2 ||
        startIndex < 0 ||
        startIndex >= polyline.length - 1) {
      var newLoc = toolkit.SphericalUtil.computeOffset(
        toolkit.LatLng(startPos.latitude, startPos.longitude),
        distanceMeters,
        heading,
      );
      return LatLng(newLoc.latitude, newLoc.longitude);
    }

    LatLng proj = _projectOnSegment(
        startPos, polyline[startIndex], polyline[startIndex + 1]);

    double remainingDistance = distanceMeters;
    LatLng currentPos = proj;

    for (int i = startIndex; i < polyline.length - 1; i++) {
      LatLng pNext = polyline[i + 1];

      double dSeg = Geolocator.distanceBetween(
        currentPos.latitude,
        currentPos.longitude,
        pNext.latitude,
        pNext.longitude,
      );

      if (dSeg < 0.001) continue;

      if (remainingDistance <= dSeg) {
        double t = remainingDistance / dSeg;
        return _lerpPosition(currentPos, pNext, t);
      } else {
        remainingDistance -= dSeg;
        currentPos = pNext;
      }
    }

    if (remainingDistance > 0 && polyline.length >= 2) {
      double lastBearing = Geolocator.bearingBetween(
        polyline[polyline.length - 2].latitude,
        polyline[polyline.length - 2].longitude,
        polyline.last.latitude,
        polyline.last.longitude,
      );
      var newLoc = toolkit.SphericalUtil.computeOffset(
        toolkit.LatLng(currentPos.latitude, currentPos.longitude),
        remainingDistance,
        lastBearing,
      );
      return LatLng(newLoc.latitude, newLoc.longitude);
    }

    return currentPos;
  }

  LatLng _projectOnSegment(LatLng p, LatLng a, LatLng b) {
    double latRad = (a.latitude + b.latitude) / 2.0 * (math.pi / 180.0);
    double cosLat = math.cos(latRad);

    double ax = a.longitude * cosLat;
    double ay = a.latitude;
    double bx = b.longitude * cosLat;
    double by = b.latitude;
    double px = p.longitude * cosLat;
    double py = p.latitude;

    double l2 = (bx - ax) * (bx - ax) + (by - ay) * (by - ay);
    if (l2 == 0.0) return a;

    double t = ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / l2;
    t = t.clamp(0.0, 1.0);

    return LatLng(
      a.latitude + t * (b.latitude - a.latitude),
      a.longitude + t * (b.longitude - a.longitude),
    );
  }

  LatLng _lerpPosition(LatLng a, LatLng b, double t) {
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  void reset() {
    simulatedPos = null;
    lastRealPos = null;
    _currentRawGps = null;
    _previousRawGps = null;
    _previousPreviousRawGps = null;
    _targetPos = null;
    _lastGpsTime = null;
    _lastPredictTime = null;
    calculatedSpeedMps = 0.0;
    previousCalculatedSpeedMps = 0.0;
    lastRouteIndex = -1;
  }
}
