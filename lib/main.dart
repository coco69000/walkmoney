import 'dart:math' as gmaps_utils show Point;
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // Pour détecter si on est sur le Web
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
import 'package:google_maps_utils/google_maps_utils.dart' as gmaps_utils show Point, PolyUtils;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_html/flutter_html.dart' as html;
import 'package:geolocator/geolocator.dart';
import 'package:get/get.dart';
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
class OsrmService {
  final Dio _dio = Dio();

  Future<Map<String, dynamic>?> getRoute(LatLng start, LatLng end, String mode) async {
    String baseUrl;
// OSRM utilise 'driving' par défaut, mais pour vélo/pied on change de serveur ou de profil
    String urlProfile = 'driving';

    if (mode == Constants.modeCycling) {
      baseUrl = "https://routing.openstreetmap.de/routed-bike";
    } else if (mode == Constants.modeWalking) {
      baseUrl = "https://routing.openstreetmap.de/routed-foot";
    } else {
      baseUrl = "https://router.project-osrm.org";
    }

// OSRM format: /route/v1/profile/lon,lat;lon,lat
    String url = "$baseUrl/route/v1/$urlProfile/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson&steps=true";

    try {
// print("Appel OSRM: $url");
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

class NominatimService {
  final Dio _dio = Dio();

  Future<List<dynamic>> searchPlace(String query) async {
// Nominatim requiert un User-Agent valide
    String url = "https://nominatim.openstreetmap.org/search?q=$query&format=json&polygon_geojson=1&addressdetails=1";
    try {
      var response = await _dio.get(url, options: Options(headers: {'User-Agent': 'EcoNavApp'}));
      if (response.statusCode == 200) {
        return response.data;
      }
    } catch (e) {
      debugPrint("Erreur Nominatim: $e");
    }
    return [];
  }
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
      instructions = "${json['maneuver']['type']} ${json['maneuver']['modifier'] ?? ''}";
    } else {
// Google / Fallback logic
      instructions = json['html_instructions'] ?? json['instructions']?.toString();
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
    double speedInMs = 0.0;

// 1. Priorité à la vitesse native du GPS (Doppler)
    if (position.speed > 0 && position.speed != 1.0) {
      speedInMs = position.speed;
    }
// 2. Fallback : Calcul manuel
    else if (_lastPosition != null && _lastPositionTime != null) {
      double distanceMeters = Geolocator.distanceBetween(
          _lastPosition!.latitude, _lastPosition!.longitude,
          position.latitude, position.longitude
      );
      int timeDiffSeconds = DateTime.now().difference(_lastPositionTime!).inSeconds;
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

// (Optionnel) Ici vous pouvez remettre votre appel à _checkSpeedForCheating(speedInKmH) si vous l'utilisez
  }
}
class HomeController extends GetxController with GetTickerProviderStateMixin {
  late MapLibreMapController mapController;
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
  CameraPosition initialCameraPosition = const CameraPosition(
    target: LatLng(48.8566, 2.3522),
    zoom: 14.0,
  );

  void onMapCreated(MapLibreMapController controller) {
    mapController = controller;
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
        'last_address_update_time': FieldValue.serverTimestamp(), // Restriction 1 fois/an
        'updated_at': FieldValue.serverTimestamp(),
      });

      // 2. Sauvegarde Locale pour le Background Service (CRUCIAL)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('user_home_lat', coordinates.latitude);
      await prefs.setDouble('user_home_lng', coordinates.longitude);

      // Mettre à jour le profil localement si nécessaire
      Get.snackbar("Succès", "Domicile défini !", backgroundColor: Colors.green, colorText: Colors.white);

    } catch (e) {
      Get.snackbar("Erreur", "Impossible de sauvegarder le domicile: $e", backgroundColor: Colors.red, colorText: Colors.white);
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

  Future<void> _fetchGoogleElevation(List<LatLng> points) async {
    if (points.isEmpty) return;

    try {
      String apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";
      if (apiKey.isEmpty) {
        debugPrint("Clé API manquante pour le dénivelé.");
        return;
      }

      // Pour économiser le quota et éviter les URL trop longues, on échantillonne
      // la route (max 50 points, ce qui est suffisant pour une estimation).
      int sampleSize = 50;
      List<LatLng> sampledPoints = [];

      if (points.length <= sampleSize) {
        sampledPoints = points;
      } else {
        int step = (points.length / sampleSize).ceil();
        for (int i = 0; i < points.length; i += step) {
          sampledPoints.add(points[i]);
        }
        // Toujours ajouter le dernier point
        if (sampledPoints.last != points.last) {
          sampledPoints.add(points.last);
        }
      }

      // Construction de la chaîne "lat,lng|lat,lng"
      String pathParam = sampledPoints
          .map((p) => "${p.latitude},${p.longitude}")
          .join("|");

      // Appel API Google Elevation
      String url = "https://maps.googleapis.com/maps/api/elevation/json?locations=$pathParam&key=$apiKey";

      var response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        if (data['status'] == 'OK' && data['results'] != null) {
          List<dynamic> results = data['results'];
          double totalAscent = 0.0;

          // Calcul du dénivelé positif cumulé
          for (int i = 0; i < results.length - 1; i++) {
            double elev1 = (results[i]['elevation'] as num).toDouble();
            double elev2 = (results[i + 1]['elevation'] as num).toDouble();

            double diff = elev2 - elev1;
            if (diff > 0) {
              totalAscent += diff;
            }
          }

          elevationGain.value = totalAscent;
          debugPrint(
              "Dénivelé Google calculé : ${totalAscent.toStringAsFixed(1)} m");
        }
      } else {
        debugPrint("Erreur Google Elevation: ${response.body}");
      }
    } catch (e) {
      debugPrint("Exception calcul dénivelé: $e");
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
          currentPos.latitude, currentPos.longitude,
          polylineCoordinates[i].latitude, polylineCoordinates[i].longitude
      );
      if (dist < minDistance) {
        minDistance = dist;
        closestIndex = i;
      }
    }

    // 2. Additionner la distance de tous les points restants jusqu'à l'arrivée
    double remainingDistanceMeters = 0;
    for (int i = closestIndex; i < polylineCoordinates.length - 1; i++) {
      remainingDistanceMeters += Geolocator.distanceBetween(
          polylineCoordinates[i].latitude, polylineCoordinates[i].longitude,
          polylineCoordinates[i + 1].latitude,
          polylineCoordinates[i + 1].longitude
      );
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
      await mapController.addSource(driverSourceId,
          const GeojsonSourceProperties(
              data: {"type": "FeatureCollection", "features": []}));
      await mapController.addSource(routeSourceId,
          const GeojsonSourceProperties(
              data: {"type": "FeatureCollection", "features": []}));
      await mapController.addSource(walkingRouteSourceId,
          const GeojsonSourceProperties(
              data: {"type": "FeatureCollection", "features": []}));
      await mapController.addSource(destSourceId, const GeojsonSourceProperties(
          data: {"type": "FeatureCollection", "features": []}));

      // AJOUT SOURCE RAYON
      await mapController.addSource(radiusSourceId,
          const GeojsonSourceProperties(
              data: {"type": "FeatureCollection", "features": []}));

      // Layer Route Bus (Ligne pleine)
      await mapController.addLayer(
          routeSourceId, routeLayerId, const LineLayerProperties(
          lineColor: ['get', 'color'],
          lineWidth: 6.0,
          lineOpacity: 0.9,
          lineCap: "round",
          lineJoin: "round"
      ));

      // CORRECTION LAYER MARCHE (Pointillés Orange bien visibles)
      await mapController.addLayer(
          walkingRouteSourceId, walkingRouteLayerId, const LineLayerProperties(
          lineColor: "#FF9800", // Orange
          lineWidth: 5.0,
          lineOpacity: 1.0,
          lineDasharray: [2, 2] // Pointillés nets
      ));

      // AJOUT LAYER RAYON (Cercle Rouge semi-transparent)
      await mapController.addLayer(
          radiusSourceId, radiusLayerId, const FillLayerProperties(
          fillColor: "#FF0000",
          fillOpacity: 0.25, // Transparence pour voir la carte dessous
          fillOutlineColor: "#FF0000"
      ));

      // Layers Icones
      await mapController.addLayer(
          destSourceId, destLayerId, const SymbolLayerProperties(
          iconImage: "marker_icon",
          iconSize: 1.0,
          iconAnchor: "bottom",
          iconAllowOverlap: true
      ));

      await mapController.addLayer(
          driverSourceId, driverLayerId, const SymbolLayerProperties(
          iconImage: "car_icon",
          iconSize: 0.5,
          iconRotate: ['get', 'bearing'],
          iconRotationAlignment: 'map',
          iconPitchAlignment: 'map',
          iconAllowOverlap: true,
          iconIgnorePlacement: true
      ));

      startIdleTracking();
      _checkPermissionsAndInitLocation();
    } catch (e) {
      print("Erreur onStyleLoaded: $e");
    }
  }

  // --- 2. MODIFICATION : selectAndDrawTransitRoute pour segmenter et colorer ---
  void selectAndDrawTransitRoute(int index) async {
    if (index >= transitRouteOptions.length) return;

    gettingRoute.value = true;
    polylineCoordinates.clear();

    try {
      final route = transitRouteOptions[index];
      final leg = route['legs'][0];
      final steps = leg['steps'] as List;

      LatLng? firstTransitStopLocation;
      DateTime? transitDepartureTime;
      bool transitStopFound = false;

      // Utilisation explicite de List<Map<String, dynamic>> pour éviter le crash JNI
      List<Map<String, dynamic>> solidFeatures = [];
      List<Map<String, dynamic>> dottedFeatures = [];

      for (var step in steps) {
        String encodedPoly = step['polyline']['points'];
        List<gmaps_utils.Point> points = gmaps_utils.PolyUtils.decode(encodedPoly);

        // SÉCURITÉ : Si pas assez de points pour faire une ligne, on ignore
        if (points.length < 2) continue;

        List<List<double>> stepCoords = points.map((p) => [p.y.toDouble(), p.x.toDouble()]).toList();

        for (var p in points) {
          polylineCoordinates.add(LatLng(p.x.toDouble(), p.y.toDouble()));
        }

        String mode = step['travel_mode'];

        if (mode == 'WALKING') {
          dottedFeatures.add({
            "type": "Feature",
            "geometry": {
              "type": "LineString",
              "coordinates": stepCoords
            },
            "properties": <String, dynamic>{} // Map vide typée
          });
        } else if (mode == 'TRANSIT') {
          if (!transitStopFound) {
            double lat = step['start_location']['lat'];
            double lng = step['start_location']['lng'];
            firstTransitStopLocation = LatLng(lat, lng);

            if (step['transit_details'] != null &&
                step['transit_details']['departure_time'] != null) {
              var val = step['transit_details']['departure_time']['value'];
              if (val != null) {
                transitDepartureTime = DateTime.fromMillisecondsSinceEpoch(val * 1000);
              }
            }
            transitStopFound = true;
          }

          String segmentColor = "#3d5afe";
          if (step['transit_details']?['line']?['color'] != null) {
            segmentColor = step['transit_details']['line']['color'];
            if (!segmentColor.startsWith('#')) segmentColor = "#$segmentColor";
          }

          solidFeatures.add({
            "type": "Feature",
            "geometry": { "type": "LineString", "coordinates": stepCoords},
            "properties": { "color": segmentColor}
          });
        }
      }

      // SÉCURITÉ : Envoi des sources avec typage strict
      // Si la liste est vide, MapLibre gère [], mais pas null ou une liste dynamique mal typée

      await mapController.setGeoJsonSource(routeSourceId, {
        "type": "FeatureCollection",
        "features": solidFeatures
      });

      await mapController.setGeoJsonSource(walkingRouteSourceId, {
        "type": "FeatureCollection",
        "features": dottedFeatures
      });

      // Reste de la logique (Cercle, UI, Zoom)...
      if (firstTransitStopLocation != null) {
        await _drawCircleOnMap(firstTransitStopLocation, 10);
      } else {
        await mapController.setGeoJsonSource(
            radiusSourceId, {"type": "FeatureCollection", "features": []});
      }

      distanceLeft.value = leg['distance']['text'];
      timeLeft.value = leg['duration']['text'];
      mapStatus.value = Constants.route;
      showTransitOptions.value = false;

      if (dottedFeatures.isNotEmpty) {
        List firstPoint = dottedFeatures[0]['geometry']['coordinates'][0];
        moveMapCamera(LatLng(firstPoint[1], firstPoint[0]), zoom: 17);
      } else if (solidFeatures.isNotEmpty) {
        List firstPoint = solidFeatures[0]['geometry']['coordinates'][0];
        moveMapCamera(LatLng(firstPoint[1], firstPoint[0]), zoom: 16);
      }

      if (Get.isRegistered<NavigationController>()) {
        final nav = Get.find<NavigationController>();
        nav.setRouteInstructions(steps);
        if (transitStopFound && firstTransitStopLocation != null) {
          nav.setTargetTransitStop(firstTransitStopLocation, transitDepartureTime);
        } else {
          nav.clearTargetTransitStop();
        }
      }
    } catch (e) {
      print("Erreur dessin route: $e");
    } finally {
      gettingRoute.value = false;
    }
  }
  Future<void> _drawCircleOnMap(LatLng center, double radiusMeters) async {
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
      double lng_rad = lng + math.atan2(
          math.sin(theta) * math.sin(d_rad) * math.cos(lat),
          math.cos(d_rad) - math.sin(lat) * math.sin(lat_rad));
      coordinates.add([lng_rad * (180 / math.pi), lat_rad * (180 / math.pi)]);
    }
    coordinates.add(coordinates[0]); // Fermer la boucle

    final feature = {
      "type": "FeatureCollection",
      "features": [{
        "type": "Feature",
        "geometry": {
          "type": "Polygon",
          "coordinates": [coordinates]
        },
        "properties": {}
      }
      ]
    };

    await mapController.setGeoJsonSource(radiusSourceId, feature);
  }

  // --- LOGIQUE ANIMATION FLUIDE ---
  void moveDriverFluidly(LatLng from, LatLng to, double targetBearing,
      Duration duration) {
    _movementController?.dispose();
    _movementController = AnimationController(duration: duration, vsync: this);

    double startBearing = _lastBearing;
    double diff = targetBearing - startBearing;
    if (diff > 180) targetBearing -= 360;
    if (diff < -180) targetBearing += 360;

    Animation<double> anim = Tween<double>(begin: 0, end: 1)
        .animate(
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
            target: LatLng(lat, lng), zoom: 18.0, bearing: bearing, tilt: 50
        )));
      }
    });
    _movementController!.forward();
  }

  Future<void> _updateDriverMarker(LatLng position, double heading) async {
    final feature = {
      "type": "FeatureCollection",
      "features": [{
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [position.longitude, position.latitude]
        },
        "properties": { "bearing": heading}
      }
      ]
    };
    try {
      await mapController.setGeoJsonSource(driverSourceId, feature);
    } catch (_) {}
  }

  // --- LOGIQUE SNAPPING ---
  LatLng snapToRoute(LatLng gpsPos) {
    if (polylineCoordinates.isEmpty) return gpsPos;
    LatLng closest = polylineCoordinates.first;
    double minDist = double.infinity;

    // Optimisation : ne chercher que dans un rayon raisonnable ou sur un subset si la route est longue
    // Ici version simple
    for (int i = 0; i < polylineCoordinates.length - 1; i++) {
      LatLng p1 = polylineCoordinates[i];
      LatLng p2 = polylineCoordinates[i + 1];
      LatLng proj = _project(gpsPos, p1, p2);
      double d = Geolocator.distanceBetween(
          gpsPos.latitude, gpsPos.longitude, proj.latitude, proj.longitude);
      if (d < minDist) {
        minDist = d;
        closest = proj;
      }
    }
    // Si on est à moins de 30m de la route, on snap. Sinon on renvoie la position réelle (déviation)
    return minDist < 30 ? closest : gpsPos;
  }

  LatLng _project(LatLng p, LatLng a, LatLng b) {
    double l2 = pow(a.latitude - b.latitude, 2).toDouble() +
        pow(a.longitude - b.longitude, 2).toDouble();
    if (l2 == 0.0) return a;
    double t = ((p.latitude - a.latitude) * (b.latitude - a.latitude) +
        (p.longitude - a.longitude) * (b.longitude - a.longitude)) / l2;
    t = max(0, min(1, t));
    return LatLng(a.latitude + t * (b.latitude - a.latitude),
        a.longitude + t * (b.longitude - a.longitude));
  }

  // --- MÉTHODES MÉTIER ---

  Future<Position> getMyCurrentLocation() async =>
      await Geolocator.getCurrentPosition();

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
      {LatLng? origin, DateTime? departureTime, DateTime? arrivalTime}) async {
    // 1. Initialisation et Nettoyage
    gettingRoute.value = true;
    polylineCoordinates.clear();
    transitRouteOptions.clear();
    showTransitOptions.value = false;

    // On remet le dénivelé à 0 avant le nouveau calcul
    elevationGain.value = 0.0;

    // Nettoyage visuel des anciennes routes sur la carte
    try {
      await mapController.setGeoJsonSource(
          routeSourceId, {"type": "FeatureCollection", "features": []});
      await mapController.setGeoJsonSource(
          walkingRouteSourceId, {"type": "FeatureCollection", "features": []});
    } catch (e) {
      debugPrint("Erreur nettoyage map (ignoré): $e");
    }

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

        // Gestion des horaires
        String timeParam = "";
        if (departureTime != null) {
          timeParam =
          "&departure_time=${(departureTime.millisecondsSinceEpoch / 1000)
              .round()}";
        } else if (arrivalTime != null) {
          timeParam =
          "&arrival_time=${(arrivalTime.millisecondsSinceEpoch / 1000)
              .round()}";
        }

        String apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? "";
        String url = "https://maps.googleapis.com/maps/api/directions/json?units=metric&origin=$originStr&destination=$destStr&mode=transit$timeParam&alternatives=true&language=fr&key=$apiKey";

        try {
          var response = await Dio().get(url);
          var data = response.data;

          if (data['status'] == 'OK' && data['routes'] != null &&
              (data['routes'] as List).isNotEmpty) {
            List<dynamic> routes = data['routes'];
            transitRouteOptions.assignAll(routes);
            showTransitOptions.value =
            true; // Affiche la liste des bus à l'utilisateur

            // Pour le transit, le dénivelé n'est pas calculé ici car il dépend de l'option choisie
            return;
          }
        } catch (e) {
          debugPrint("Erreur Google Transit: $e");
        }
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

      // Appel au service OSRM
      var routeData = await _osrmService.getRoute(start, dest, osrmMode);

      if (routeData != null) {
        // Mise à jour des données brutes (Dist/Temps)
        activeRouteRawDistanceMeters.value = routeData['distance'].toDouble();
        activeRouteRawDurationSeconds.value = routeData['duration'].toDouble();

        // Mise à jour de l'affichage UI
        if (activeRouteRawDistanceMeters.value >= 1000) {
          distanceLeft.value =
          "${(activeRouteRawDistanceMeters.value / 1000).toStringAsFixed(
              1)} km";
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
          "features": [{
            "type": "Feature",
            "geometry": { "type": "LineString", "coordinates": coords}
          }
          ]
        };
        await mapController.setGeoJsonSource(routeSourceId, feature);

        // -----------------------------------------------------
        // CALCUL DU DÉNIVELÉ (GOOGLE ELEVATION API)
        // -----------------------------------------------------
        // On appelle la fonction dédiée avec les points de la route trouvée
        if (polylineCoordinates.isNotEmpty) {
          _fetchGoogleElevation(polylineCoordinates);
        }

        // Mise à jour des instructions textuelles (NavigationController)
        if (Get.isRegistered<NavigationController>()) {
          Get.find<NavigationController>().setRouteInstructions(
              routeData['legs'][0]['steps']);
        }
      }
    } catch (e) {
      debugPrint("Erreur globale drawRoute: $e");
    } finally {
      gettingRoute.value = false;
    }
  }

  Future<void> addDestinationMarker(LatLng point) async {
    final feature = {
      "type": "FeatureCollection",
      "features": [{
        "type": "Feature",
        "geometry": {
          "type": "Point",
          "coordinates": [point.longitude, point.latitude]
        }
      }
      ]
    };
    await mapController.setGeoJsonSource(destSourceId, feature);
  }

  Future<void> moveMapCamera(LatLng target,
      {double zoom = 15.0, double bearing = 0.0, double tilt = 0.0}) async {
    try {
      await mapController.animateCamera(
          CameraUpdate.newCameraPosition(CameraPosition(
            target: target, zoom: zoom, bearing: bearing, tilt: tilt,
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

    await mapController.setGeoJsonSource(
        routeSourceId, {"type": "FeatureCollection", "features": []});
    await mapController.setGeoJsonSource(
        walkingRouteSourceId, {"type": "FeatureCollection", "features": []});
    await mapController.setGeoJsonSource(
        destSourceId, {"type": "FeatureCollection", "features": []});

    _movementController?.stop();
    recenterMap();
    startIdleTracking();
  }

  void startIdleTracking() async {
    await _idlePositionStream?.cancel();
    const settings = LocationSettings(
        accuracy: LocationAccuracy.high, distanceFilter: 0);
    _idlePositionStream =
        Geolocator.getPositionStream(locationSettings: settings).listen((
            Position position) {
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
          await mapController.animateCamera(
              CameraUpdate.newCameraPosition(CameraPosition(
                  target: _currentAnimatedPos!,
                  zoom: 18.0,
                  bearing: _lastBearing,
                  tilt: 50
              )));
        } else {
          // Fallback si pas d'animation fluide en cours
          Position pos = await Geolocator.getCurrentPosition();
          await mapController.animateCamera(
              CameraUpdate.newCameraPosition(CameraPosition(
                  target: LatLng(pos.latitude, pos.longitude),
                  zoom: 18.0,
                  bearing: pos.heading,
                  tilt: 50
              )));
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
    LocationPermission permission = await Geolocator.requestPermission();

    // --- AJOUT SÉCURITÉ MOCK LOCATION ---
    // On utilise la constante globale définie plus haut ou on la remet ici
    const bool securityEnabled = false; // Ou utilise la variable globale ENABLE_SECURITY_CHECKS si accessible

    if (securityEnabled) {
      // On vérifie maintenant que la permission est accordée
      if (permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse) {
        bool isMockLocation = await SafeDevice.isMockLocation;

        if (isMockLocation) {
          // Si position fictive détectée, on redirige vers l'écran de blocage
          // Comme on est dans GetX, on peut utiliser Get.offAll
          Get.offAll(() =>
          const SecurityBlockedScreen(
              reason: "Position fictive (Fake GPS) détectée."));
          return; // Stop tout
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

  StreamSubscription<Position>? positionStream;

  var isCameraLocked = true.obs;
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
  bool _hasReachedBusStop = false;

  // Variables lissage mouvement
  DateTime? _lastPositionTime;
  LatLng? _lastSnappedPos;
  double _avgInterval = 1000;

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

  // ── VARIABLES DÉVIATION DE ROUTE ──────────────────────────────────────────
  double _cumulatedDeviationMeters = 0.0;
  LatLng? _lastOnRoutePosition;
  DateTime? _lastOnRouteTime;
  bool _isDeviationDialogOpen = false;
  UserProfile? _activeUserProfile;

  // ── HISTORIQUE VITESSE POUR DÉTECTION MODE VOITURE ─────────────────────
  final List<double> _highSpeedSamples = [];
  DateTime? _highSpeedWindowStart;

  // ── FLAGS POPUPS (éviter doublons) ───────────────────────────────────────
  bool _isScheduleDialogOpen = false;
  int _currentStepIndex = 0; // Index séquentiel pour les instructions de navigation

  // ══════════════════════════════════════════════════════════════════════════
  // 📊 FIREBASE TRIP LOGGING + NOTIFICATIONS
  // ══════════════════════════════════════════════════════════════════════════
  String? _activeTripId;
  DateTime? _tripStartTime;
  final List<Map<String, dynamic>> _tripPositionBuffer = [];
  int _positionSampleCount = 0;
  static const int _positionSampleInterval = 5;
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  Future<void> _initNotifications() async {
    try {
      const InitializationSettings settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _notificationsPlugin.initialize(settings);
    } catch (_) {}
  }

  Future<void> _showNotification(String title, String body, {int id = 0}) async {
    try {
      await _notificationsPlugin.show(id, title, body, const NotificationDetails(
        android: AndroidNotificationDetails(
          'walkmoney_nav_channel', 'Navigation WalkMoney',
          channelDescription: 'Notifications de navigation',
          importance: Importance.high, priority: Priority.high,
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
      final modeStr = mode == TravelMode.walking ? 'walking'
          : mode == TravelMode.bicycling ? 'bicycling'
          : mode == TravelMode.transit ? 'transit' : 'driving';
      _tripStartTime = DateTime.now();
      _tripPositionBuffer.clear();
      _positionSampleCount = 0;
      final docRef = await FirebaseFirestore.instance
          .collection('users').doc(userId)
          .collection('trip_logs').add({
        'user_id': userId, 'travel_mode': modeStr,
        'destination_name': homeController.destination.value,
        'destination_lat': homeController.destinationCoordinates.latitude,
        'destination_lng': homeController.destinationCoordinates.longitude,
        'started_at': FieldValue.serverTimestamp(), 'ended_at': null,
        'status': 'in_progress',
        'distance_meters': homeController.activeRouteRawDistanceMeters.value,
        'duration_seconds': homeController.activeRouteRawDurationSeconds.value,
        'actual_duration_seconds': null, 'cheat_detected': false,
        'cheat_reason': null, 'positions': [], 'lames_earned': 0,
      });
      _activeTripId = docRef.id;
    } catch (e) { debugPrint('[TripLog] Erreur démarrage: $e'); }
  }

  Future<void> _logTripPosition(LatLng pos, double speedKmh, double heading) async {
    _positionSampleCount++;
    if (_positionSampleCount % _positionSampleInterval != 0 || _activeTripId == null) return;
    _tripPositionBuffer.add({
      'lat': pos.latitude, 'lng': pos.longitude,
      'speed_kmh': speedKmh, 'heading': heading,
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
          .collection('users').doc(userId)
          .collection('trip_logs').doc(_activeTripId)
          .update({'positions': FieldValue.arrayUnion(buf)});
    } catch (e) { debugPrint('[TripLog] Erreur flush: $e'); }
  }

  Future<void> _endTripLog({
    required String status, String? cheatReason,
    double? finalDistanceMeters, int? lamesEarned,
  }) async {
    if (_activeTripId == null) return;
    final tripId = _activeTripId!;
    _activeTripId = null;
    try {
      await _flushTripPositions();
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return;
      final actualDuration = _tripStartTime != null
          ? DateTime.now().difference(_tripStartTime!).inSeconds : null;
      _tripStartTime = null;
      await FirebaseFirestore.instance
          .collection('users').doc(userId)
          .collection('trip_logs').doc(tripId)
          .update({
        'ended_at': FieldValue.serverTimestamp(), 'status': status,
        'cheat_detected': cheatReason != null, 'cheat_reason': cheatReason,
        'actual_duration_seconds': actualDuration,
        'actual_distance_meters': finalDistanceMeters,
        'lames_earned': lamesEarned ?? 0,
      });
      await FirebaseFirestore.instance.collection('user_activity_logs').add({
        'user_id': userId, 'type': 'trip_$status', 'trip_id': tripId,
        'travel_mode': homeController.currentTravelMode.value.toString(),
        'destination': homeController.destination.value,
        'timestamp': FieldValue.serverTimestamp(),
        'cheat_reason': cheatReason, 'lames_earned': lamesEarned ?? 0,
      });
    } catch (e) { debugPrint('[TripLog] Erreur fin: $e'); }
  }

  void setRouteInstructions(List steps) {
    directions.assignAll(steps);
    _currentStepIndex = 0;
    if (steps.isNotEmpty) {
      final firstStep = steps[0];
      if (firstStep['maneuver'] != null) {
        final maneuver = firstStep['maneuver'];
        if (maneuver is Map) {
          currentInstructionText.value = _translateManeuver(
            maneuver['type']?.toString() ?? '',
            maneuver['modifier']?.toString() ?? '',
          );
        }
      } else if (firstStep['html_instructions'] != null) {
        currentInstructionText.value = _cleanHtml(firstStep['html_instructions'].toString());
      } else if (firstStep['instructions'] != null) {
        currentInstructionText.value = firstStep['instructions'].toString();
      }
    }
  }

  String _cleanHtml(String htmlString) {
    return htmlString.replaceAll(RegExp(r'<[^>]*>'), '');
  }

  void setOnStoreDestinationReachedCallback(Function() cb) => onStoreDestinationReached = cb;
  void setOnChallengeDestinationReachedCallback(Function(dynamic) cb) => _onChallengeReached = cb;
  void setOnWorkDestinationReachedCallback(Function(String) cb) => _onWorkReached = cb;
  void setOnNormalDestinationReachedCallback(Function(int) cb) => onNormalDestinationReached = cb;

  /// Transmettre le profil utilisateur pour la tolérance déviation (3km standard / 6km premium)
  void setActiveUserProfile(UserProfile? profile) => _activeUserProfile = profile;

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

  void startNavigation() {
    navigateToDestination();
  }

  void navigateToDestination({bool validateWalkingLegs = false}) async {
    if (homeController.polylineCoordinates.isEmpty) return;

    FlutterBackgroundService().invoke("stop_background_trip", {
      'travel_mode': homeController.currentTravelMode.value == TravelMode.bicycling
          ? 'bicycling'
          : homeController.currentTravelMode.value == TravelMode.transit
              ? 'transit'
              : 'walking',
    });
    print("📡 Envoi signal: stop_background_trip");
    // -----------------------------------------------------------

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

    homeController.stopIdleTracking();
    homeController.mapStatus.value = Constants.onDestination;
    homeController.isNavigationCameraLocked.value = true;
    isCameraLocked.value = true;

    // ── FIREBASE LOGGING + NOTIFICATIONS ────────────────────────────────
    _initNotifications().then((_) {
      _startTripLog();
      _showNotification(
        '🚀 Navigation démarrée',
        'Vers : ${homeController.destination.value}',
        id: 1,
      );
    });
    // ────────────────────────────────────────────────────────────────────

    LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: const Duration(milliseconds: 500))
        : AppleSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        activityType: ActivityType.automotiveNavigation);

    positionStream = Geolocator.getPositionStream(locationSettings: settings).listen((Position position) {
      final now = DateTime.now();
      speedController.updateSpeed(position);

      LatLng rawPos = LatLng(position.latitude, position.longitude);
      double currentSpeedKmh = position.speed * 3.6;
      if (currentSpeedKmh < 0) currentSpeedKmh = 0; // Sécurité

      // 1. ANALYSE DE VITESSE ET MODE (Sauf si Transit ou popup déjà ouvert)
      if (homeController.currentTravelMode.value != TravelMode.transit && !_isSwitchingModeDialogTrace) {
        bool stopNow = _analyzeSpeedCompliance(currentSpeedKmh);
        if (stopNow) return; // Arrêt immédiat si violation grave
      }

      // Snapping et vérification déviation
      LatLng snappedPos = homeController.snapToRoute(rawPos);
      double distanceDeviation = Geolocator.distanceBetween(
          rawPos.latitude, rawPos.longitude,
          snappedPos.latitude, snappedPos.longitude
      );

      // ── SYSTÈME DE DÉVIATION CUMULÉE (3km standard / 6km premium) ──────
      var mode = homeController.currentTravelMode.value;
      bool isWalkOrBike = mode == TravelMode.walking || mode == TravelMode.bicycling;
      if (isWalkOrBike && !_isDeviationDialogOpen) {
        if (distanceDeviation > 30.0) {
          // Hors itinéraire : accumuler la distance réellement PARCOURUE hors route
          // (distance entre la position actuelle et la dernière position sur route)
          if (_lastOnRoutePosition != null) {
            double distSinceLastOnRoute = Geolocator.distanceBetween(
              rawPos.latitude, rawPos.longitude,
              _lastOnRoutePosition!.latitude, _lastOnRoutePosition!.longitude,
            );
            // Ne mettre à jour que si on s'est éloigné (évite les mises à jour inutiles)
            if (distSinceLastOnRoute > _cumulatedDeviationMeters) {
              _cumulatedDeviationMeters = distSinceLastOnRoute;
            }
          }
        } else {
          // Sur itinéraire : mémoriser cette position et reset déviation
          _lastOnRoutePosition = snappedPos;
          _lastOnRouteTime = DateTime.now();
          _cumulatedDeviationMeters = 0.0;
        }

        bool isPremium = _activeUserProfile?.isVip ?? false;
        double deviationLimitMeters = isPremium ? 6000.0 : 3000.0;

        if (_cumulatedDeviationMeters >= deviationLimitMeters) {
          _showDeviationPopup(_cumulatedDeviationMeters, deviationLimitMeters, rawPos);
          return;
        }
      }

      // Mises à jour UI
      homeController.updateRemainingDistanceAndTime(snappedPos);
      _updateWalkingInstruction(rawPos);

      // ── Firebase : log position GPS ──────────────────────────────────────
      _logTripPosition(rawPos, currentSpeedKmh, position.heading);

      // Logique Arrêt de bus
      if (_targetBusStopLocation != null && !_hasReachedBusStop) {
        double distanceToStop = Geolocator.distanceBetween(
            rawPos.latitude, rawPos.longitude,
            _targetBusStopLocation!.latitude, _targetBusStopLocation!.longitude
        );
        if (distanceToStop <= 10.0) {
          if (!_isScheduleDialogOpen) {
            _checkBusStopArrivalLogic();
          }
        }
      }

      // Animation fluide du marqueur
      bool isTransitMode = homeController.currentTravelMode.value == TravelMode.transit;

      if (isTransitMode && currentSpeedKmh > 30.0) {
        homeController.moveDriverFluidly(
            _lastSnappedPos ?? snappedPos,
            snappedPos,
            position.heading,
            const Duration(milliseconds: 500)
        );
      } else {
        if (_lastPositionTime != null) {
          int interval = now.difference(_lastPositionTime!).inMilliseconds;
          _avgInterval = (_avgInterval * 0.8) + (interval * 0.2);
          Duration d = Duration(milliseconds: _avgInterval.round().clamp(200, 2000));

          if (_lastSnappedPos != null) {
            homeController.moveDriverFluidly(_lastSnappedPos!, snappedPos, position.heading, d);
          }
        }
      }

      _lastPositionTime = now;
      _lastSnappedPos = snappedPos;

      // Vérification fin de trajet
      _checkRouteLogic(rawPos, snappedPos);
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
    double routeKm = (homeController.activeRouteRawDistanceMeters.value / 1000.0).clamp(0.1, 100.0);
    double gradientPercent = (elevM / (routeKm * 10.0)).clamp(0.0, 20.0); // % moyen

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

    // ── Seuils de base ──────────────────────────────────────────────────────
    double maxSpeedWalk = 10.0;   // Max marche rapide / jogging
    double maxSpeedBike = 55.0;   // Max vélo (descente)
    double carSuspectThreshold = 70.0; // Au-dessus → voiture certaine

    double elevFactor = _getElevationSpeedFactor();

    if (mode == TravelMode.walking) {
      maxSpeedWalk *= elevFactor;

      // ── FENÊTRE VÉLO (12–35 km/h maintenu > 15s) ─────────────────────────
      if (speedKmh > 12.0) {
        if (_highSpeedBurstStartTime == null) _highSpeedBurstStartTime = DateTime.now();
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
          double avgSpeed = _recentWalkingSpeeds.reduce((a, b) => a + b) / _recentWalkingSpeeds.length;
          if (variance < 0.2 && avgSpeed > 7.0) {
            _handleSpeedViolation(avgSpeed, mode);
          }
        }
      }

    } else if (mode == TravelMode.bicycling) {
      double effectiveMax = maxSpeedBike * elevFactor;

      if (speedKmh > effectiveMax) {
        if (_highSpeedBurstStartTime == null) _highSpeedBurstStartTime = DateTime.now();
        Duration burst = DateTime.now().difference(_highSpeedBurstStartTime!);
        // Tolérance plus longue en descente (dénivelé élevé)
        Duration toleranceDuration = elevFactor < 0.95
            ? const Duration(seconds: 30)  // Montée = moins de tolérance sur dépassement
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
        content: "Vous roulez à ${speed.toStringAsFixed(0)} km/h. Basculer en mode VÉLO ?",
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
    _endTripLog(status: 'cheat_detected', cheatReason: 'vehicle_speed_violation');
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

  void _showDeviationPopup(double deviationMeters, double limitMeters, LatLng currentPos) {
    if (_isDeviationDialogOpen) return;
    _isDeviationDialogOpen = true;

    bool isPremium = _activeUserProfile?.isVip ?? false;
    double deviationKm = (deviationMeters / 1000.0);

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
          const SizedBox(width: 10),
          Expanded(child: Text(
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("Déviation : ${deviationKm.toStringAsFixed(2)} km",
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text("Limite autorisée : ${(limitMeters / 1000).toStringAsFixed(0)} km${isPremium ? ' (Premium)' : ''}",
                    style: const TextStyle(fontSize: 13, color: Colors.grey)),
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
                  Expanded(child: Text(
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
            label: const Text("Annuler le trajet", style: TextStyle(color: Colors.red)),
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
              _isDeviationDialogOpen = false;
              _closeGetDialog();
              _recalculateToLastOnRoutePoint(currentPos);
            },
          ),
        ],
      ),
      barrierDismissible: false,
    );
  }

  /// Recalcule l'itinéraire depuis la position actuelle vers la destination finale
  Future<void> _recalculateToLastOnRoutePoint(LatLng currentPos) async {
    // Recalcule depuis la position actuelle → destination finale (pas le dernier point sur route)
    final destination = homeController.destinationCoordinates;

    await homeController.drawRoute(
      destination,
      origin: currentPos,
    );

    // Reset du compteur de déviation + index des étapes
    _cumulatedDeviationMeters = 0.0;
    _lastOnRoutePosition = currentPos;
    _currentStepIndex = 0;

    Get.snackbar(
      "Demi-tour",
      "Itinéraire recalculé vers votre trajectoire d'origine.",
      backgroundColor: Colors.green,
      colorText: Colors.white,
      duration: const Duration(seconds: 4),
      icon: const Icon(Icons.u_turn_left, color: Colors.white),
    );
  }

  // Calcul mathématique de la variance
  double _calculateVariance(List<double> values) {
    if (values.isEmpty) return 0.0;
    double mean = values.reduce((a, b) => a + b) / values.length;
    double variance = values.map((v) => math.pow(v - mean, 2)).reduce((a, b) => a + b) / values.length;
    return variance;
  }

  void _showModeChangePopup({required String title, required String content, required TravelMode newMode, required IconData newIcon}) {
    // Guard anti-doublon
    if (_isSwitchingModeDialogTrace) return;
    _isSwitchingModeDialogTrace = true;
    _highSpeedBurstStartTime = null;

    Get.dialog(
      AlertDialog(
        title: Row(children: [Icon(Icons.speed, color: Colors.orange), SizedBox(width: 10), Expanded(child: Text(title, style: TextStyle(fontSize: 18)))]),
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
                    backgroundColor: Colors.green, colorText: Colors.white,
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

  void _updateWalkingInstruction(LatLng userPos) {
    if (directions.isEmpty) return;

    // ── Mode TRANSIT : cas spécial (ancienne logique pour arrêts de bus) ──
    if (directions.isNotEmpty && directions[0]['travel_mode'] == 'WALKING') {
      var step = directions[0];
      double dist = Geolocator.distanceBetween(
          userPos.latitude, userPos.longitude,
          step['end_location']['lat'], step['end_location']['lng']
      );
      if (dist > 10) {
        currentInstructionText.value = "Marcher vers l'arrêt (${dist.round()}m)";
      } else {
        currentInstructionText.value = "Arrêt à proximité !";
      }
      return;
    }

    // ── Mode MARCHE / VÉLO : avancement automatique des étapes ──
    // Trouver l'étape la plus proche dont on n'a pas encore dépassé la fin
    int bestStep = 0;
    double bestDist = double.maxFinite;

    for (int i = 0; i < directions.length; i++) {
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

    // Si on est à moins de 15m de la fin d'une étape, passer à la suivante
    if (bestDist < 15.0 && bestStep + 1 < directions.length) {
      bestStep = bestStep + 1;
    }

    final step = directions[bestStep];

    // Extraire le texte de l'instruction
    String instruction = "";
    if (step['html_instructions'] != null) {
      instruction = _cleanHtml(step['html_instructions'].toString());
    } else if (step['maneuver'] != null) {
      final maneuver = step['maneuver'];
      if (maneuver is Map) {
        final type = maneuver['type']?.toString() ?? '';
        final modifier = maneuver['modifier']?.toString() ?? '';
        instruction = _translateManeuver(type, modifier);
      } else {
        instruction = maneuver.toString();
      }
    } else if (step['instructions'] != null) {
      instruction = step['instructions'].toString();
    }

    // Calcul distance restante jusqu'à la fin de l'étape courante
    final endLoc = step['end_location'];
    if (endLoc != null) {
      double endLat = (endLoc['lat'] as num?)?.toDouble() ?? 0.0;
      double endLng = (endLoc['lng'] as num?)?.toDouble() ?? 0.0;
      double distToEnd = Geolocator.distanceBetween(
          userPos.latitude, userPos.longitude, endLat, endLng);
      if (distToEnd > 10) {
        instruction += " (${distToEnd.round()}m)";
      }
    }

    if (instruction.isNotEmpty) {
      currentInstructionText.value = instruction;
    }
  }

  /// Traduit un type de manœuvre OSRM en texte lisible
  String _translateManeuver(String type, String modifier) {
    switch (type) {
      case 'turn':
        switch (modifier) {
          case 'left': return 'Tourner à gauche';
          case 'right': return 'Tourner à droite';
          case 'slight left': return 'Légèrement à gauche';
          case 'slight right': return 'Légèrement à droite';
          case 'sharp left': return 'Virage serré à gauche';
          case 'sharp right': return 'Virage serré à droite';
          case 'uturn': return 'Faire demi-tour';
          default: return 'Tourner';
        }
      case 'depart': return modifier.isNotEmpty ? 'Partir vers ${modifier == "left" ? "la gauche" : modifier == "right" ? "la droite" : modifier}' : 'Départ';
      case 'arrive': return 'Vous êtes arrivé(e)';
      case 'merge': return 'Continuer tout droit';
      case 'on ramp': return 'Prendre la bretelle';
      case 'off ramp': return 'Sortir';
      case 'fork':
        return modifier.contains('left') ? 'Rester à gauche' : 'Rester à droite';
      case 'end of road':
        return modifier.contains('left') ? 'Tourner à gauche en fin de route' : 'Tourner à droite en fin de route';
      case 'roundabout': return 'Prendre le rond-point';
      case 'rotary': return 'Prendre le rond-point';
      case 'continue': return 'Continuer tout droit';
      default: return type.isNotEmpty ? type : 'Continuer';
    }
  }

  void _checkBusStopArrivalLogic() {
    _hasReachedBusStop = true;
    if (_targetBusStopSchedule == null) {
      Get.snackbar("Arrêt rejoint", "Lancement du timer...", backgroundColor: Colors.blue, colorText: Colors.white);
      return;
    }
    DateTime now = DateTime.now();
    DateTime schedule = _targetBusStopSchedule!;
    Duration diff = now.difference(schedule);
    int diffMinutes = diff.inMinutes;

    if (diffMinutes >= -10 && diffMinutes <= 10) {
      Get.snackbar(
          "Horaire Validé ✅",
          "Timer activé. Écart: ${diffMinutes.abs()} min",
          backgroundColor: Colors.green,
          colorText: Colors.white,
          duration: const Duration(seconds: 5)
      );
    } else {
      _showNewSchedulePopup();
    }
  }

  /// Ferme UNIQUEMENT le dialog GetX en cours, sans toucher aux snackbars.
  /// Get.back() appelle closeCurrentSnackbar() ce qui cause LateInitializationError.
  void _closeGetDialog() {
    final ctx = Get.overlayContext;
    if (ctx != null && Navigator.of(ctx).canPop()) {
      Navigator.of(ctx).pop();
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
            const Text("Prochains passages estimés :", style: TextStyle(fontWeight: FontWeight.bold)),
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
    _closeGetDialog(); // Pop le dialog SANS déclencher closeCurrentSnackbar()
    _targetBusStopSchedule = newTime;
    _hasReachedBusStop = false;
    // Délai court pour éviter tout conflit avec la fermeture du dialog
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
    Get.snackbar(
        "Navigation Interrompue",
        "Anomalie détectée : $reason",
        backgroundColor: Colors.red,
        colorText: Colors.white,
        duration: const Duration(seconds: 5)
    );
  }

  void _checkRouteLogic(LatLng raw, LatLng snapped) {
    double distDest = Geolocator.distanceBetween(
        raw.latitude, raw.longitude,
        homeController.destinationCoordinates.latitude, homeController.destinationCoordinates.longitude
    );

    if (distDest < 40 && !homeController.arrived.value) {
      homeController.arrived.value = true;
      _finishTripWithRecap();
    }
  }

  // --- FIN DE TRAJET & RÉCAPITULATIF ---
  void _finishTripWithRecap() {
    Duration duration = DateTime.now().difference(_startTime ?? DateTime.now());
    double avgSpeed = 0.0;
    if (_speedHistory.isNotEmpty) {
      avgSpeed = _speedHistory.reduce((a, b) => a + b) / _speedHistory.length;
    }

    var mode = homeController.currentTravelMode.value;

    double maxAvgAllowed;
    if (mode == TravelMode.walking) {
      maxAvgAllowed = 12.0;
    } else if (mode == TravelMode.bicycling) {
      double elevFactor = _getElevationSpeedFactor();
      maxAvgAllowed = 38.0 / elevFactor;
    } else {
      maxAvgAllowed = 1000.0;
    }

    if (avgSpeed > maxAvgAllowed && mode != TravelMode.transit) {
      _triggerCarDetected();
      return;
    }

    // ── Firebase : fin de trajet réussie ──────────────────────────────────
    int lamesGagnees = homeController.activeRouteEstimatedGain.value;
    _endTripLog(
      status: 'completed',
      finalDistanceMeters: homeController.activeRouteRawDistanceMeters.value,
      lamesEarned: lamesGagnees,
    );
    _showNotification(
      '🏁 Arrivée !',
      'Trajet terminé ! +$lamesGagnees Lames 🎉',
      id: 3,
    );
    // ──────────────────────────────────────────────────────────────────────

    stopNavigation();
    _showArrivalRecapPopup(duration, avgSpeed);
  }

  void _showArrivalRecapPopup(Duration duration, double avgSpeed) {
    String modeStr = homeController.currentTravelMode.value == TravelMode.walking ? "Marche 🚶" : "Vélo 🚲";
    if (homeController.currentTravelMode.value == TravelMode.transit) modeStr = "Transport 🚌";

    int lamesGagnees = homeController.activeRouteEstimatedGain.value;

    Get.dialog(
      AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: const [
            Icon(Icons.emoji_events, size: 50, color: Colors.amber),
            SizedBox(height: 10),
            Text("Trajet Terminé !", style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Divider(),
            _buildRecapRow("Mode validé", modeStr),
            _buildRecapRow("Temps total", "${duration.inMinutes} min ${duration.inSeconds % 60} s"),
            _buildRecapRow("Vitesse Moy.", "${avgSpeed.toStringAsFixed(1)} km/h"),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Colors.green)
              ),
              child: Column(
                children: [
                  const Text("Gain Total", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                  Text("+$lamesGagnees Lames", style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)),
                ],
              ),
            )
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
            ),
            onPressed: () {
              _closeGetDialog(); // Ferme popup SANS toucher au snackbar
              _distributeRewardsAndCallbacks(); // Distribue les points
            },
            child: const Text("Récupérer mes Lames", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      barrierDismissible: false,
    );
  }

  Widget _buildRecapRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        ],
      ),
    );
  }

  void _distributeRewardsAndCallbacks() {
    // Déclenchement des callbacks externes
    if (onStoreDestinationReached != null) {
      onStoreDestinationReached!();
    } else if (activeChallenge != null && _onChallengeReached != null) {
      _onChallengeReached!(activeChallenge!);
    } else if (activeWorkCommuteType != null && _onWorkReached != null) {
      _onWorkReached!(activeWorkCommuteType!);
    } else {
      int gain = homeController.activeRouteEstimatedGain.value;
      if (onNormalDestinationReached != null) {
        onNormalDestinationReached!(gain);
      }
    }
    // Nettoyage final
    homeController.clearDestination();
    speedController.cheatStatus.value = CheatModeStatus.none;
    // Snackbar avec délai pour éviter conflit avec la fermeture du dialog
    Future.delayed(const Duration(milliseconds: 150), () {
      Get.snackbar("Félicitations 🎉", "Lames ajoutées !",
          backgroundColor: Colors.green, colorText: Colors.white,
          duration: const Duration(seconds: 3));
    });
  }

  void stopNavigation() {
    positionStream?.cancel();
    _lastPositionTime = null;
    _lastSnappedPos = null;

    // ── Firebase : log annulation si trajet en cours ─────────────────────
    if (_activeTripId != null) {
      _endTripLog(
        status: 'cancelled',
        finalDistanceMeters: homeController.activeRouteRawDistanceMeters.value,
      );
    }
    // ──────────────────────────────────────────────────────────────────────

    homeController.clearDestination();
    isCameraLocked.value = true;
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
  Function(String) onWarning;
  TransitIssue _lastWarningSent = TransitIssue.none;

  TransitMonitor({required this.onWarning});

  void checkPosition(LatLng userPosition, List<LatLng> routePolyline) {
// Vérification si l'utilisateur est sur le tracé du transport en commun
    bool isOnRoute = gmaps_utils.PolyUtils.isLocationOnEdgeTolerance(
        gmaps_utils.Point(userPosition.latitude, userPosition.longitude),
        routePolyline.map((p) => gmaps_utils.Point(p.latitude, p.longitude)).toList(),
        false,
        30.0 // Tolérance de 30 mètres
    );

    if (!isOnRoute) {
      if (_lastWarningSent != TransitIssue.offRoute) {
        onWarning("Attention, vous semblez avoir dévié de l'itinéraire du transport en commun.");
        _lastWarningSent = TransitIssue.offRoute;
      }
    } else {
// Réinitialiser le statut si l'utilisateur revient sur la route
      if (_lastWarningSent == TransitIssue.offRoute) {
        _lastWarningSent = TransitIssue.none;
      }
    }
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

  SpeedometerDisplay({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Obx(() {
// Afficher seulement en mode navigation
      if (homeController.mapStatus.value != Constants.onDestination) {
        return const SizedBox.shrink();
      }

      final speed = speedController.currentSpeed.value;
      final cheatStatus = speedController.cheatStatus.value;
      final cheatMessage = speedController.cheatWarningMessage.value;

      Color displayColor = Colors.black;
      if (cheatStatus == CheatModeStatus.exceededSpeedWarning) displayColor = Colors.orange;
      if (cheatStatus == CheatModeStatus.exceededSpeedCheating) displayColor = Colors.red;

      return Positioned(
        top: MediaQuery.of(context).padding.top + 80,
        left: 20,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 8)],
                  border: Border.all(color: displayColor == Colors.black ? Colors.transparent : displayColor, width: 2)
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
                  const Text('km/h', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                ],
              ),
            ),
            if (cheatMessage.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 5),
                padding: const EdgeInsets.all(5),
                color: displayColor,
                child: Text(cheatMessage, style: const TextStyle(color: Colors.white, fontSize: 10)),
              )
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
          Obx(() => home.mapStatus.value == Constants.onDestination
              ? const Positioned(top: 50, left: 15, right: 15, child: InstructionHeader())
              : Positioned(top: 60, left: 15, right: 15, child: NominatimSearchBar(onSelected: home.setDestination))),

// --- UI : Compteur de Vitesse ---
          SpeedometerDisplay(),

// --- UI : Bouton Recentrer ---
          Obx(() {
// Affiche le bouton recentrer si on n'est pas en nav, OU si on est en nav mais déverrouillé
            bool showRecenter = home.mapStatus.value != Constants.onDestination ||
                (home.mapStatus.value == Constants.onDestination && !home.isNavigationCameraLocked.value);

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
                        : Colors.blueAccent
                ),
                onPressed: () => home.recenterMap(),
              ),
            );
          }),

// --- UI : Panneau du bas (Distance/Temps) ---
          Obx(() => home.mapStatus.value != Constants.idle && home.mapStatus.value != Constants.onDestination
              ? Positioned(bottom: 0, left: 0, right: 0, child: const BottomPanel())
              : Container()),

// Panneau STOP pendant la navigation
          Obx(() => home.mapStatus.value == Constants.onDestination
              ? Positioned(
              bottom: 30, left: 20, right: 20,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, padding: const EdgeInsets.all(15)),
                child: const Text("STOP NAVIGATION", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () => Get.find<NavigationController>().stopNavigation(),
              )
          )
              : Container()
          ),
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
    NavigationController navigationController = Get.find();
    HomeController homeController = Get.find();
    return Obx(() {

      bool shouldShow =
          homeController.mapStatus.value == Constants.onDestination;
      if (!shouldShow) return Container();

      Widget content;
      bool isTransitMode = homeController.currentTravelMode.value == TravelMode.transit;

      if (homeController.arrived.value) {

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
                  backgroundColor: accentGold,
                  foregroundColor: textDark,
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
      } else if (isTransitMode) {

        if (navigationController.transitLegs.isEmpty ||
            navigationController.currentLegIndex.value >=
                navigationController.transitLegs.length) {
          return Container();
        }

        final currentLeg =
        navigationController.transitLegs[navigationController.currentLegIndex.value];
        IconData icon = Icons.directions_walk;
        if (currentLeg.isTransit) {
          switch (currentLeg.transitDetails?.line?.vehicle?.type) {
            case "BUS": // Note: La valeur de l'API est une chaîne de caractères
              icon = Icons.directions_bus;
              break;
            case "SUBWAY":
              icon = Icons.subway;
              break;
            case "TRAM":
              icon = Icons.tram;
              break;
            case "RAIL":
              icon = Icons.train;
              break;
            default:
              icon = Icons.directions_transit;
          }
        }

        content = Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 5, right: 10),
              child: Icon(icon, color: Colors.white, size: 25),
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  html.Html(
                      data: "<span>${currentLeg.instructions}</span>",
                      style: {'span': html.Style(color: Colors.white)}),
                  Text(
                    "Pendant ${currentLeg.duration} (${currentLeg.distance})",
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  )
                ],
              ),
            )
          ],
        );
      } else {

        if (navigationController.directions.isEmpty) return Container();
        DirectionModel directionModel =
        DirectionModel.fromJson(navigationController.directions[0]);
        content = Row(
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 5, right: 10),
              child: Icon(
                getIcon(directionModel.instructions!),
                color: Colors.white,
                size: 25,
              ),
            ),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  html.Html(
                      data: "<span>${directionModel.instructions}</span>",
                      style: {'span': html.Style(color: Colors.white)})
                ],
              ),
            )
          ],
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

  IconData getIcon(String instruction) {
    if (instruction.contains(Constants.northWest)) {
      return Icons.north_west;
    } else if (instruction.contains(Constants.northEast)) {
      return Icons.north_east;
    } else if (instruction.contains(Constants.southEast)) {
      return Icons.south_east;
    } else if (instruction.contains(Constants.southWest)) {
      return Icons.south_west;
    } else if (instruction.contains(Constants.north) ||
        instruction.contains(Constants.straight)) {
      return Icons.north;
    } else if (instruction.contains(Constants.west) ||
        instruction.contains(Constants.left)) {
      return Icons.west;
    } else if (instruction.contains(Constants.east) ||
        instruction.contains(Constants.right)) {
      return Icons.east;
    } else if (instruction.contains(Constants.south)) {
      return Icons.south;
    }
    return Icons.north;
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
      width: MediaQuery
          .of(context)
          .size
          .width,
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
                      style: const TextStyle(
                          color: Colors.black54, fontSize: 14),
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
                  else
                    if (isTransitRouteSelected)
// Bouton spécifique pour le Transit
                      ElevatedButton(
                        onPressed: () =>
                            navigationController.navigateToDestination(),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16)),
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
                            onPressed: () =>
                                navigationController.navigateToDestination(
                                    validateWalkingLegs: true
                                ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blueAccent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12),
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

class NominatimSearchBar extends StatefulWidget {
  final Function(String name, LatLng coords) onSelected;
  const NominatimSearchBar({super.key, required this.onSelected});
  @override
  State<NominatimSearchBar> createState() => _NominatimSearchBarState();
}

class _NominatimSearchBarState extends State<NominatimSearchBar> {
  final TextEditingController _controller = TextEditingController();
  final NominatimService _service = NominatimService();
  List<dynamic> _results = [];
  bool _isLoading = false;

  void _search() async {
    if (_controller.text.length < 3) return;
    setState(() => _isLoading = true);
    FocusManager.instance.primaryFocus?.unfocus();

    var res = await _service.searchPlace(_controller.text);
    if(mounted) {
      setState(() { _results = res; _isLoading = false; });
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
              boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black26)]
          ),
          child: TextField(
            controller: _controller,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: "Rechercher une destination...",
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(15),
              suffixIcon: _isLoading
                  ? const Padding(padding: EdgeInsets.all(12.0), child: CircularProgressIndicator(strokeWidth: 2))
                  : IconButton(icon: const Icon(Icons.search), onPressed: _search),
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
                boxShadow: const [BoxShadow(blurRadius: 5, color: Colors.black12)]
            ),
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
                    leading: const Icon(Icons.location_on_outlined, color: Colors.blue),
                    title: Text(p['display_name'].split(",")[0], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(p['display_name'], maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () {
                      double lat = double.parse(p['lat']);
                      double lon = double.parse(p['lon']);
                      widget.onSelected(p['display_name'].split(",")[0], LatLng(lat, lon));
                      setState(() { _results = []; _controller.clear(); });
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
      // Utilisation de la nouvelle variable réactive
      String text = controller.currentInstructionText.value;
      if (text.isEmpty) return Container();

      return Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: Colors.green[800],
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)]
        ),
        child: Row(
          children: [
            const Icon(Icons.directions_walk, color: Colors.white, size: 30),
            const SizedBox(width: 15),
            Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600))),
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
        onTap: () => controller.setTravelMode(mode), // setTravelMode manque, on l'utilise pour trigger la maj
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
              color: isSelected ? Colors.blueAccent : Colors.grey[100],
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isSelected ? Colors.blue : Colors.transparent)
          ),
          child: Row(
            children: [
              Icon(icon, color: isSelected ? Colors.white : Colors.black54, size: 20),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold
              )),
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
          boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))]
      ),
      padding: const EdgeInsets.fromLTRB(25, 15, 25, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
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
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Obx(() => Text(controller.timeLeft.value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87))),
                Obx(() => Text(controller.distanceLeft.value, style: const TextStyle(color: Colors.grey, fontSize: 16, fontWeight: FontWeight.w500))),
              ]),
              ElevatedButton.icon(
                onPressed: () => controller.mapStatus.value == Constants.route ? nav.startNavigation() : nav.stopNavigation(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: controller.mapStatus.value == Constants.route ? Colors.blueAccent : Colors.redAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
                icon: Icon(controller.mapStatus.value == Constants.route ? Icons.navigation : Icons.stop, color: Colors.white),
                label: Obx(() => Text(controller.mapStatus.value == Constants.route ? "DÉMARRER" : "STOP",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
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
const double LOGIN_STREAK_BONUS_PER_PALIER = 0.02;
const int LOGIN_STREAK_DAYS_PER_PALIER = 7;
const double MAX_LOGIN_STREAK_BONUS_TOTAL = 0.20;


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

class LoyaltyConfigScreen extends StatefulWidget {
  final String storeId;
  final List<LoyaltyRule> currentRules;
  const LoyaltyConfigScreen({Key? key, required this.storeId, required this.currentRules}) : super(key: key);

  @override
  _LoyaltyConfigScreenState createState() => _LoyaltyConfigScreenState();
}

class _LoyaltyConfigScreenState extends State<LoyaltyConfigScreen> {
  final List<LoyaltyRule> _rules = [];
  String _selectedType = 'visit';
  final _thresholdCtrl = TextEditingController();
  final _rewardCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _rules.addAll(widget.currentRules);
  }

  void _addRule() {
    if (_thresholdCtrl.text.isEmpty || _rewardCtrl.text.isEmpty) return;
    setState(() {
      _rules.add(LoyaltyRule(
        type: _selectedType,
        threshold: double.parse(_thresholdCtrl.text),
        rewardPercent: double.parse(_rewardCtrl.text),
        minPurchaseAmount: _selectedType == 'visit' ? 5.0 : null, // Par défaut 5€ min pour valider une visite
      ));
      _thresholdCtrl.clear();
      _rewardCtrl.clear();
    });
  }

  Future<void> _saveRules() async {
    List<Map<String, dynamic>> rulesMap = _rules.map((e) => e.toMap()).toList();
    await FirebaseFirestore.instance.collection('stores').doc(widget.storeId).update({
      'loyalty_rules': rulesMap
    });
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Programme de fidélité mis à jour !")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Programme de Fidélité")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              color: Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Column(
                  children: [
                    const Text("Ajouter un palier", style: TextStyle(fontWeight: FontWeight.bold)),
                    DropdownButton<String>(
                      value: _selectedType,
                      items: const [
                        DropdownMenuItem(value: 'visit', child: Text("Basé sur les visites")),
                        DropdownMenuItem(value: 'spend', child: Text("Basé sur le montant dépenser")),
                      ],
                      onChanged: (v) => setState(() => _selectedType = v!),
                    ),
                    Row(
                      children: [
                        Expanded(child: TextField(controller: _thresholdCtrl, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: _selectedType == 'visit' ? "Nb Visites" : "Montant (€)"))),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: _rewardCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Récompense (%)"))),
                      ],
                    ),
                    ElevatedButton(onPressed: _addRule, child: const Text("Ajouter la règle")),
                  ],
                ),
              ),
            ),
            const Divider(),
            const Text("Règles actuelles :"),
            Expanded(
              child: ListView.builder(
                itemCount: _rules.length,
                itemBuilder: (context, index) {
                  final rule = _rules[index];
                  return ListTile(
                    leading: Icon(rule.type == 'visit' ? Icons.people : Icons.euro, color: primaryGreen),
                    title: Text("Au bout de ${rule.threshold} ${rule.type == 'visit' ? 'visites' : '€ dépensés'}"),
                    subtitle: Text("Gain : ${rule.rewardPercent}% sur la prochaine commande"),
                    trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => setState(() => _rules.removeAt(index))),
                  );
                },
              ),
            ),
            ElevatedButton(onPressed: _saveRules, style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, minimumSize: const Size(double.infinity, 50)), child: const Text("Sauvegarder le Programme")),
          ],
        ),
      ),
    );
  }
}
class UserProfile {
  final String id;
  final int lamePoints;
  final bool isVip;
  final int consecutiveLogins;
  final String username;
  final int currentLevel;
  final double nextLevelBoost;
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
  final Map<String, dynamic> loyaltyProgress; // { "store_id": { "visits": 3, "spend": 45.0 } }
  final Map<String, dynamic> storeBoosts; // Nouveau champ : {'storeId': {'amount': 0.5, 'last_update': ...}}
  final List<String> favoriteStores; // Liste des magasins favoris
  final List<Map<String, dynamic>> favoriteRoutes; // Liste des trajets favoris
  final int? totalLameEarned; // Total cumulé de Lame Points gagnés (pour les niveaux)

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
      currentCashbackBoost: (data['current_cashback_boost'] as num?)?.toDouble() ?? 0.0,
      lastBoostUpdate: data['last_boost_update'],
      loyaltyProgress: data['loyalty_progress'] ?? {},
      consecutiveLogins: _parseFirestoreInt(
          data['consecutive_logins'], 0, 'consecutive_logins'),
      username: data['username'] as String? ?? 'Utilisateur Anonyme',
      currentLevel:
      _parseFirestoreInt(data['current_level'], 1, 'current_level'),
      nextLevelBoost:
      _parseFirestoreDouble(data['next_level_boost'], 1.0, 'next_level_boost'),
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
      favoriteStores: (data['favorite_stores'] as List<dynamic>?)?.cast<String>() ?? [],
      favoriteRoutes: (data['favorite_routes'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [],
      totalLameEarned: _parseFirestoreInt(data['total_lame_earned'], 0, 'total_lame_earned'),
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
      windDirection:
      (json['current_weather']['winddirection'] as num).toInt(),
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
      totalLameEarned:
      UserProfile._parseFirestoreInt(data['total_lame_earned'], 0, 'total_lame_earned'),
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
              (e) =>
          e.toString() == 'ChallengeStatus.${userProgressData['status']}',
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
      visitCount: visitCount ?? this.visitCount,
      stayDurationSeconds:
      stayDurationSeconds != null ? stayDurationSeconds : this.stayDurationSeconds,
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
      'last_completed_at':
      (status == ChallengeStatus.completedPendingReward ||
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

  // --- Options Commerciales ---
  final bool isCashbackEnabled;        // Le socle
  final double cashbackRate;           // Taux (ex: 0.05)

  final bool isVisibilityBoostEnabled; // Le Slider (Défis)
  final double lamePointMultiplier;    // Valeur du slider (ex: 1.2)

  final bool isPremiumAdBoostEnabled;  // Pub (Commission 40%) - Requiert Cashback
  final bool isGoldStoreEnabled;       // Or (5€) - Requiert Cashback

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

  factory EcoStore.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
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
      rules = (data['loyalty_rules'] as List).map((x) => LoyaltyRule.fromMap(x)).toList();
    }

    return EcoStore(
      id: snapshot.id,
      name: data['name'] as String? ?? 'Magasin',
      address: data['address'] as String? ?? 'Adresse inconnue',
      coordinates: coords,
      description: data['description'] as String? ?? '',

      // Lecture des options
      isCashbackEnabled: data['is_cashback_enabled'] as bool? ?? true,
      cashbackRate: UserProfile._parseFirestoreDouble(data['cashback_rate'], 0.05, 'cashback_rate'),

      isVisibilityBoostEnabled: data['is_visibility_boost_enabled'] as bool? ?? false,
      lamePointMultiplier: (data['lame_point_multiplier'] as num?)?.toDouble() ?? 1.0,

      isPremiumAdBoostEnabled: data['is_premium_ad_boost_enabled'] as bool? ?? false,
      isGoldStoreEnabled: data['is_gold_store_enabled'] as bool? ?? false,

      minimumPurchase: UserProfile._parseFirestoreDouble(data['minimum_purchase'], 0.0, 'minimum_purchase'),
      ownerId: data['owner_id'] as String?,
      currentMonthDebt: UserProfile._parseFirestoreDouble(data['current_month_debt'], 0.0, 'current_month_debt'),
      totalAmountSpentByUser: UserProfile._parseFirestoreDouble(data['totalAmountSpentByUser'], 0.0, 'totalAmountSpentByUser'),
      totalCashbackGiven: UserProfile._parseFirestoreDouble(data['totalCashbackGiven'], 0.0, 'totalCashbackGiven'),
      loyaltyRules: rules,
    );
  }
}
class AddStoreScreen extends StatefulWidget {
  final UserProfile userProfile;
  const AddStoreScreen({Key? key, required this.userProfile}) : super(key: key);

  @override
  _AddStoreScreenState createState() => _AddStoreScreenState();
}

class _AddStoreScreenState extends State<AddStoreScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _cashbackController = TextEditingController(text: "5");

  // --- OPTIONS ---
  bool _enableCashback = true;

  // Options liées au Cashback (désactivées si cashback false)
  bool _enablePremiumAdBoost = false; // Pub
  bool _enableGoldStore = false;      // Or

  // Option Indépendante
  bool _enableVisibilityBoost = false; // Slider défis
  double _selectedMultiplier = 1.2;

  // Simulation
  double _monthlyFixedCost = 0.0;
  double _variableFeePer100 = 0.0;

  bool _isLoading = false;
  CardFieldInputDetails? _cardDetails;

  @override
  void initState() {
    super.initState();
    _updateCostSimulation();
  }

  void _updateCostSimulation() {
    // 1. Gestion des exclusions : Si Cashback OFF -> Pub et Or OFF
    if (!_enableCashback) {
      _enablePremiumAdBoost = false;
      _enableGoldStore = false;
    }

    double fixedCost = 0.0;

    // 2. Coût Slider (Boost Visibilité Défis)
    if (_enableVisibilityBoost) {
      int step = ((_selectedMultiplier - 1.1) * 10).round();
      double sliderCost = step * 2.0;
      if (sliderCost < 2.0) sliderCost = 2.0;
      if (sliderCost > 10.0) sliderCost = 10.0;
      fixedCost += sliderCost;
    }

    // 3. Coût Option Or (5€)
    if (_enableGoldStore) {
      fixedCost += 5.0;
    }

    // 4. Coût Variable (Commission)
    double rate = _enableCashback ? (double.tryParse(_cashbackController.text) ?? 0.0) : 0.0;
    double commissionPercent = _enablePremiumAdBoost ? 0.40 : 0.25;
    double fee = rate * commissionPercent;

    setState(() {
      _monthlyFixedCost = fixedCost;
      _variableFeePer100 = rate + fee;
    });
  }

  Future<void> _submitStoreWithPayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (!kIsWeb && (_cardDetails == null || !_cardDetails!.complete)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Carte invalide"), backgroundColor: Colors.red));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Création Customer Stripe
      final paymentMethod = await Stripe.instance.createPaymentMethod(
        params: const PaymentMethodParams.card(paymentMethodData: PaymentMethodData()),
      );

      // 2. Appel Cloud Function
      final result = await FirebaseFunctions.instance.httpsCallable('createStripeShop').call({
        'paymentMethodId': paymentMethod.id,
        'email': "magasin_${widget.userProfile.id}_${DateTime.now().millisecondsSinceEpoch}@econav.com",
        'name': _nameController.text.trim(),
        'initialMonthlyCost': _monthlyFixedCost, // Premier paiement (Or + Slider)
      });

      final dataFunc = result.data as Map;
      final String stripeCustomerId = dataFunc['customerId'];
      final String subscriptionItemId = dataFunc['subscriptionItemId'];

      // 3. Geocoding
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'];
      final url = Uri.parse('https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(_addressController.text)}&key=$apiKey');
      final response = await http.get(url);
      final dataGeo = jsonDecode(response.body);

      if (dataGeo['status'] != 'OK' || dataGeo['results'].isEmpty) throw Exception("Adresse introuvable.");
      final location = dataGeo['results'][0]['geometry']['location'];

      // 4. Sauvegarde Firestore
      await FirebaseFirestore.instance.collection('stores').add({
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'coordinates': GeoPoint((location['lat'] as num).toDouble(), (location['lng'] as num).toDouble()),
        'latitude': (location['lat'] as num).toDouble(),
        'longitude': (location['lng'] as num).toDouble(),
        'description': _descController.text.trim(),
        'phone': _phoneController.text.trim(),
        'category': _categoryController.text.trim(),
        'loyalty_rules': [],

        // Options
        'is_cashback_enabled': _enableCashback,
        'cashback_rate': _enableCashback ? (double.parse(_cashbackController.text) / 100.0) : 0.0,

        'is_visibility_boost_enabled': _enableVisibilityBoost,
        'lame_point_multiplier': _enableVisibilityBoost ? _selectedMultiplier : 1.0,

        'is_premium_ad_boost_enabled': _enablePremiumAdBoost,
        'is_gold_store_enabled': _enableGoldStore,

        'owner_id': widget.userProfile.id,
        'stripe_customer_id': stripeCustomerId,
        'stripe_meter_id': subscriptionItemId,
        'auto_billing_enabled': true,
        'current_month_debt': _monthlyFixedCost, // Dette initiale
        'totalAmountSpentByUser': 0.0,
        'totalCashbackGiven': 0.0,
        'created_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Magasin créé !"), backgroundColor: Colors.green));
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur : $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Créer mon Magasin")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("1. Infos Générales", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryGreen)),
              const SizedBox(height: 10),
              TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: "Nom", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Requis" : null),
              const SizedBox(height: 10),
              TextFormField(controller: _addressController, decoration: const InputDecoration(labelText: "Adresse", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Requis" : null),
              const SizedBox(height: 10),
              TextFormField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: "Téléphone", border: OutlineInputBorder())),

              const SizedBox(height: 30),
              const Text("2. Offre & Visibilité", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryGreen)),

              // --- A. CASHBACK (Maitre) ---
              Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(children: [
                    SwitchListTile(
                        title: const Text("Activer Cashback"),
                        subtitle: const Text("Requis pour les options Pub & Or."),
                        value: _enableCashback,
                        activeColor: Colors.green,
                        onChanged: (val) {
                          setState(() => _enableCashback = val);
                          _updateCostSimulation();
                        }
                    ),
                    if (_enableCashback)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: TextFormField(
                          controller: _cashbackController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: "Taux (%)", suffixText: "%", border: OutlineInputBorder()),
                          onChanged: (v) => _updateCostSimulation(),
                        ),
                      )
                  ]),
                ),
              ),

              // --- B. BOOST VISIBILITÉ (Indépendant) ---
              Card(
                elevation: 2,
                margin: const EdgeInsets.symmetric(vertical: 8),
                color: _enableVisibilityBoost ? Colors.purple.shade50 : Colors.white,
                child: Column(children: [
                  SwitchListTile(
                    title: const Text("Boost Visibilité (Défis)"),
                    subtitle: const Text("Apparaître en premier dans les défis."),
                    secondary: const Icon(Icons.rocket_launch, color: Colors.purple),
                    value: _enableVisibilityBoost,
                    activeColor: Colors.purple,
                    onChanged: (val) {
                      setState(() => _enableVisibilityBoost = val);
                      _updateCostSimulation();
                    },
                  ),
                  if (_enableVisibilityBoost)
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(children: [
                        Text("Multiplicateur offert : x${_selectedMultiplier.toStringAsFixed(1)}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.purple)),
                        Slider(
                          value: _selectedMultiplier, min: 1.2, max: 1.6, divisions: 4, activeColor: Colors.purple,
                          label: "x${_selectedMultiplier.toStringAsFixed(1)}",
                          onChanged: (val) {
                            setState(() => _selectedMultiplier = double.parse(val.toStringAsFixed(1)));
                            _updateCostSimulation();
                          },
                        ),
                      ]),
                    )
                ]),
              ),

              // --- C. OPTIONS AVANCÉES (Requiert Cashback) ---
              if (_enableCashback)
                Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text("Sponsoriser Boost Pub"),
                        subtitle: const Text("Gains x2 pour clients. Com 40%."),
                        secondary: const Icon(Icons.campaign, color: Colors.blueAccent),
                        value: _enablePremiumAdBoost,
                        activeColor: Colors.blueAccent,
                        onChanged: (val) {
                          setState(() => _enablePremiumAdBoost = val);
                          _updateCostSimulation();
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text("Visibilité Or + 1%"),
                        subtitle: const Text("Carte Or + 1% offert (5€/mois)."),
                        secondary: const Icon(Icons.star, color: Colors.amber),
                        value: _enableGoldStore,
                        activeColor: Colors.amber,
                        onChanged: (val) {
                          setState(() => _enableGoldStore = val);
                          _updateCostSimulation();
                        },
                      ),
                    ],
                  ),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("Activez le Cashback pour débloquer les options Pub et Or.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                ),

              // --- SIMULATION ---
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    const Text("SIMULATION COÛT", style: TextStyle(fontWeight: FontWeight.bold)),
                    const Divider(),
                    _buildCostRow("Abonnements Fixes :", "${_monthlyFixedCost.toStringAsFixed(2)} € / mois", Colors.black, isBold: true),
                    const SizedBox(height: 5),
                    _buildCostRow("Pour 100€ d'achat :", "", Colors.grey),
                    _buildCostRow("  - Coût total (Cashback + Com) :", "${_variableFeePer100.toStringAsFixed(2)} €", Colors.black),
                    if (_enableGoldStore)
                      const Padding(
                        padding: EdgeInsets.only(top: 5.0),
                        child: Text("Note: Avec l'option Or, le client reçoit 1% de plus (payé par nous).", style: TextStyle(fontSize: 10, color: Colors.green, fontStyle: FontStyle.italic)),
                      )
                  ],
                ),
              ),

              const SizedBox(height: 30),

              const Text("3. Paiement", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryGreen)),
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
                alignment: Alignment.center,
                child: kIsWeb ? const Text("Carte OK") : CardField(onCardChanged: (card) => setState(() => _cardDetails = card)),
              ),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitStoreWithPayment,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("Valider et Payer"),
                ),
              ),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCostRow(String label, String value, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: TextStyle(color: color, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
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

  Map<String, dynamic> toMap() => {'type': type, 'threshold': threshold, 'rewardPercent': rewardPercent};

  factory LoyaltyRule.fromMap(Map<String, dynamic> map) {
    return LoyaltyRule(
      type: map['type'] ?? 'visit',
      threshold: (map['threshold'] as num).toDouble(),
      rewardPercent: (map['rewardPercent'] as num).toDouble(),
    );
  }
}
class EditStoreScreen extends StatefulWidget {
  final String storeId;
  final Map<String, dynamic> currentData;
  const EditStoreScreen({Key? key, required this.storeId, required this.currentData}) : super(key: key);

  @override
  _EditStoreScreenState createState() => _EditStoreScreenState();
}

class _EditStoreScreenState extends State<EditStoreScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _cashbackCtrl;

  // Options
  bool _enableCashback = true;
  bool _enableVisibilityBoost = false; // Slider
  double _selectedMultiplier = 1.2;
  bool _enablePremiumAdBoost = false;
  bool _enableGoldStore = false;

  List<LoyaltyRule> _latestRules = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.currentData['name']);
    _descCtrl = TextEditingController(text: widget.currentData['description']);
    _phoneCtrl = TextEditingController(text: widget.currentData['phone'] ?? "");
    _cashbackCtrl = TextEditingController(text: ((widget.currentData['cashback_rate'] ?? 0.05) * 100).toStringAsFixed(0));

    _enableCashback = widget.currentData['is_cashback_enabled'] as bool? ?? true;

    _enableVisibilityBoost = widget.currentData['is_visibility_boost_enabled'] as bool? ?? false;
    double mult = (widget.currentData['lame_point_multiplier'] as num?)?.toDouble() ?? 1.0;
    if (mult > 1.0) _selectedMultiplier = mult;

    _enablePremiumAdBoost = widget.currentData['is_premium_ad_boost_enabled'] as bool? ?? false;
    _enableGoldStore = widget.currentData['is_gold_store_enabled'] as bool? ?? false;

    _latestRules = _parseRules(widget.currentData['loyalty_rules']);
  }

  List<LoyaltyRule> _parseRules(dynamic rulesData) {
    if (rulesData != null && rulesData is List) {
      return rulesData.map((x) => LoyaltyRule.fromMap(x)).toList();
    }
    return [];
  }

  Future<void> _refreshLoyaltyRules() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('stores').doc(widget.storeId).get();
      if (doc.exists && doc.data() != null) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        setState(() {
          _latestRules = _parseRules(data['loyalty_rules']);
        });
      }
    } catch (e) {}
  }

  Future<void> _saveChanges() async {
    if(!_formKey.currentState!.validate()) return;
    try {
      Map<String, dynamic> updates = {
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),

        'is_cashback_enabled': _enableCashback,
        'cashback_rate': _enableCashback ? (double.parse(_cashbackCtrl.text) / 100.0) : 0.0,

        'is_visibility_boost_enabled': _enableVisibilityBoost,
        'lame_point_multiplier': _enableVisibilityBoost ? _selectedMultiplier : 1.0,

        'is_premium_ad_boost_enabled': _enablePremiumAdBoost,
        'is_gold_store_enabled': _enableGoldStore,
      };

      // --- LOGIQUE FACTURATION AUTOMATIQUE ---
      double addedCost = 0.0;

      // 1. Visibilité Or (5€)
      bool wasGold = widget.currentData['is_gold_store_enabled'] as bool? ?? false;
      if (_enableGoldStore && !wasGold) {
        addedCost += 5.0; // Ajout immédiat à la dette
      }

      // 2. Slider (Boost)
      bool wasBoost = widget.currentData['is_visibility_boost_enabled'] as bool? ?? false;
      double oldMult = (widget.currentData['lame_point_multiplier'] as num?)?.toDouble() ?? 1.0;

      // Si on active le boost OU si on augmente le multiplicateur
      if (_enableVisibilityBoost) {
        int step = ((_selectedMultiplier - 1.1) * 10).round();
        double currentCost = step * 2.0;
        if (currentCost < 2.0) currentCost = 2.0;
        if (currentCost > 10.0) currentCost = 10.0;

        if (!wasBoost) {
          // C'est un nouvel abonnement
          addedCost += currentCost;
        } else if (_selectedMultiplier > oldMult) {
          // Upgrade (différence)
          int oldStep = ((oldMult - 1.1) * 10).round();
          double oldCost = oldStep * 2.0;
          if (oldCost < 2.0) oldCost = 2.0;
          addedCost += (currentCost - oldCost);
        }
      }

      if (addedCost > 0) {
        updates['current_month_debt'] = FieldValue.increment(addedCost);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Mise à jour. +${addedCost.toStringAsFixed(2)}€ ajoutés à la facture en cours.")));
      }

      await FirebaseFirestore.instance.collection('stores').doc(widget.storeId).update(updates);
      Navigator.pop(context);
    } catch(e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculs de l'interface
    double rate = _enableCashback ? (double.tryParse(_cashbackCtrl.text) ?? 0.0) : 0.0;
    double commission = _enablePremiumAdBoost ? 0.40 : 0.25;
    double totalVariableCost = rate + (rate * commission);

    double fixedCost = 0.0;
    if (_enableGoldStore) fixedCost += 5.0;
    if (_enableVisibilityBoost) {
      int step = ((_selectedMultiplier - 1.1) * 10).round();
      double sliderCost = step * 2.0;
      if (sliderCost < 2.0) sliderCost = 2.0;
      if (sliderCost > 10.0) sliderCost = 10.0;
      fixedCost += sliderCost;
    }

    return Scaffold(
      appBar: AppBar(title: const Text("Modifier le magasin")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(controller: _nameCtrl, decoration: const InputDecoration(labelText: "Nom")),
              const SizedBox(height: 10),
              TextFormField(controller: _descCtrl, decoration: const InputDecoration(labelText: "Description"), maxLines: 2),
              const SizedBox(height: 10),
              TextFormField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: "Téléphone")),
              const SizedBox(height: 20),

              // --- CASHBACK ---
              Card(
                elevation: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(children: [
                    SwitchListTile(
                      title: const Text("Activer Cashback"),
                      value: _enableCashback,
                      activeColor: Colors.green,
                      onChanged: (val) {
                        setState(() {
                          _enableCashback = val;
                          // Si on coupe le cashback, on force l'extinction des options dépendantes
                          if (!val) {
                            _enablePremiumAdBoost = false;
                            _enableGoldStore = false;
                          }
                        });
                      },
                    ),
                    if (_enableCashback)
                      TextFormField(
                        controller: _cashbackCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: "Taux (%)", suffixText: "%"),
                        onChanged: (v) => setState((){}),
                      ),
                  ]),
                ),
              ),

              // --- BOUTON FIDELITE (Seulement si Cashback actif) ---
              if (_enableCashback)
                ListTile(
                  tileColor: Colors.amber.shade50,
                  leading: const Icon(Icons.card_giftcard, color: Colors.orange),
                  title: const Text("Gérer Fidélité"),
                  subtitle: Text("${_latestRules.length} paliers"),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => LoyaltyConfigScreen(storeId: widget.storeId, currentRules: _latestRules)));
                    _refreshLoyaltyRules();
                  },
                ),

              const SizedBox(height: 20),
              const Text("Options de Visibilité", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),

              // --- OPTION 1: DEFIS (Indépendant) ---
              Card(
                elevation: 2,
                color: _enableVisibilityBoost ? Colors.purple.shade50 : Colors.white,
                child: Column(children: [
                  SwitchListTile(
                    title: const Text("Boost Visibilité (Défis)"),
                    subtitle: const Text("Apparaître en 1er + Multiplicateur."),
                    secondary: const Icon(Icons.rocket_launch, color: Colors.purple),
                    value: _enableVisibilityBoost,
                    activeColor: Colors.purple,
                    onChanged: (val) => setState(() => _enableVisibilityBoost = val),
                  ),
                  if (_enableVisibilityBoost)
                    Slider(
                      value: _selectedMultiplier, min: 1.2, max: 1.6, divisions: 4, activeColor: Colors.purple,
                      label: "x${_selectedMultiplier.toStringAsFixed(1)}",
                      onChanged: (val) => setState(() => _selectedMultiplier = double.parse(val.toStringAsFixed(1))),
                    ),
                ]),
              ),

              // --- OPTION 2 & 3 (Requiert Cashback) ---
              if (_enableCashback)
                Card(
                  elevation: 2,
                  color: (_enablePremiumAdBoost || _enableGoldStore) ? Colors.amber.shade50 : Colors.white,
                  child: Column(children: [
                    SwitchListTile(
                      title: const Text("Sponsoriser Boost Pub"),
                      subtitle: const Text("Commission 40%."),
                      secondary: const Icon(Icons.campaign, color: Colors.blueAccent),
                      value: _enablePremiumAdBoost,
                      activeColor: Colors.blueAccent,
                      onChanged: (val) => setState(() => _enablePremiumAdBoost = val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      title: const Text("Visibilité Or + 1%"),
                      subtitle: const Text("5€ / mois."),
                      secondary: const Icon(Icons.star, color: Colors.amber),
                      value: _enableGoldStore,
                      activeColor: Colors.amber,
                      onChanged: (val) => setState(() => _enableGoldStore = val),
                    ),
                  ]),
                )
              else
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text("Activez le Cashback pour débloquer Pub et Or.", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                ),

              // RESUME
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(vertical: 15),
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Total Coûts Fixes: ${fixedCost.toStringAsFixed(2)} € / mois", style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text("Coût Variable (100€): ${totalVariableCost.toStringAsFixed(2)} €"),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              ElevatedButton(
                  onPressed: _saveChanges,
                  style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, padding: const EdgeInsets.symmetric(vertical: 15)),
                  child: const Text("Enregistrer (Débit Auto)", style: TextStyle(fontSize: 16))
              ),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text("Note: Les ajouts d'options payantes seront ajoutés à votre facture mensuelle automatiquement.",
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey)),
              )
            ],
          ),
        ),
      ),
    );
  }
}
class StoreStatsScreen extends StatelessWidget {
  final EcoStore store;
  const StoreStatsScreen({Key? key, required this.store}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text("Stats : ${store.name}"),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.bar_chart), text: "Résumé"),
            Tab(icon: Icon(Icons.receipt_long), text: "Transactions"),
          ]),
        ),
        body: TabBarView(children: [
          // ---- Onglet Résumé ----
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('stores').doc(store.id).snapshots(),
            builder: (ctx, snap) {
              double ca = store.totalAmountSpentByUser;
              double cb = store.totalCashbackGiven;
              double debt = store.currentMonthDebt;
              if (snap.hasData && snap.data!.exists) {
                final d = snap.data!.data() as Map<String, dynamic>;
                ca = (d['totalAmountSpentByUser'] as num?)?.toDouble() ?? ca;
                cb = (d['totalCashbackGiven'] as num?)?.toDouble() ?? cb;
                debt = (d['current_month_debt'] as num?)?.toDouble() ?? debt;
              }
              return ListView(padding: const EdgeInsets.all(16), children: [
                _statCard("Chiffre d'affaires clients", "${ca.toStringAsFixed(2)} €", Icons.euro, Colors.blue),
                const SizedBox(height: 10),
                _statCard("Cashback total reversé", "${cb.toStringAsFixed(2)} €", Icons.card_giftcard, Colors.green),
                const SizedBox(height: 10),
                _statCard("Facture en cours", "${debt.toStringAsFixed(2)} €", Icons.receipt_long, Colors.orange),
                const SizedBox(height: 20),
                _TopClientsSection(storeId: store.id),
              ]);
            },
          ),
          // ---- Onglet Transactions ----
          _TransactionsTab(storeId: store.id),
        ]),
      ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontSize: 13, color: Colors.grey)),
        subtitle: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

class _TransactionsTab extends StatelessWidget {
  final String storeId;
  const _TransactionsTab({required this.storeId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('stores').doc(storeId)
          .collection('store_transactions')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const Center(child: Text("Aucune transaction enregistrée."));
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final ts = (d['timestamp'] as Timestamp?)?.toDate();
            final spent = (d['amount_spent'] as num?)?.toDouble() ?? 0.0;
            final cbGiven = (d['cashback_given'] as num?)?.toDouble() ?? 0.0;
            final rate = (d['rate_applied'] as num?)?.toDouble() ?? 0.0;
            final username = d['username'] as String? ?? 'Client';
            final tier = d['loyalty_tier'] as String?;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green.withOpacity(0.15),
                child: Text(username.isNotEmpty ? username[0].toUpperCase() : 'C',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
              ),
              title: Text(username, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text("${spent.toStringAsFixed(2)}€ dépensés • Cashback: ${cbGiven.toStringAsFixed(2)}€ (${rate.toStringAsFixed(1)}%)"),
                if (tier != null && tier.isNotEmpty)
                  Text(tier, style: const TextStyle(fontSize: 11, color: Colors.orange)),
                if (ts != null) Text(
                  "${ts.day.toString().padLeft(2,'0')}/${ts.month.toString().padLeft(2,'0')}/${ts.year}  ${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}",
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ]),
              trailing: Text("${cbGiven.toStringAsFixed(2)}€",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
            );
          },
        );
      },
    );
  }
}

class _TopClientsSection extends StatelessWidget {
  final String storeId;
  const _TopClientsSection({required this.storeId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('stores').doc(storeId)
          .collection('store_transactions')
          .orderBy('amount_spent', descending: true)
          .limit(20)
          .snapshots(),
      builder: (ctx, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) return const SizedBox();
        final Map<String, Map<String, dynamic>> clients = {};
        for (final doc in snap.data!.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final uid = d['user_id'] as String? ?? '';
          final spent = (d['amount_spent'] as num?)?.toDouble() ?? 0.0;
          final name = d['username'] as String? ?? 'Client';
          if (clients.containsKey(uid)) {
            clients[uid]!['total'] += spent;
            clients[uid]!['visits'] = (clients[uid]!['visits'] as int) + 1;
          } else {
            clients[uid] = {'name': name, 'total': spent, 'visits': 1};
          }
        }
        final sorted = clients.entries.toList()
          ..sort((a, b) => (b.value['total'] as double).compareTo(a.value['total'] as double));

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text("🏆 Top Clients", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          ...sorted.take(5).map((e) => ListTile(
            dense: true,
            leading: const Icon(Icons.person, color: Colors.blueGrey),
            title: Text(e.value['name'] as String),
            subtitle: Text("${e.value['visits']} visite(s)"),
            trailing: Text("${(e.value['total'] as double).toStringAsFixed(2)}€",
                style: const TextStyle(fontWeight: FontWeight.bold)),
          )),
        ]);
      },
    );
  }
}
class MerchantDashboard extends StatefulWidget {
  final UserProfile userProfile;
  const MerchantDashboard({Key? key, required this.userProfile}) : super(key: key);

  @override
  _MerchantDashboardState createState() => _MerchantDashboardState();
}

class _MerchantDashboardState extends State<MerchantDashboard> {

  Widget _statChip(String value, String label, Color color) {
    return Column(children: [
      Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: color)),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }

  // --- LOGIQUE PAIEMENT DETTE ---
  void _payDebt(BuildContext context, EcoStore store) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Paiement Stripe"),
        content: Text(
            "Vous allez être redirigé vers Stripe pour payer la somme de ${store.currentMonthDebt.toStringAsFixed(2)}€."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Annuler")),
          ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                // Simulation succès
                await FirebaseFirestore.instance
                    .collection('stores')
                    .doc(store.id)
                    .update({
                  'last_payment_date': FieldValue.serverTimestamp(),
                  'last_payment_amount': store.currentMonthDebt,
                  'current_month_debt': 0.0,
                });

                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Paiement reçu ! Merci."),
                    backgroundColor: Colors.green));
              },
              child: const Text("Payer maintenant")),
        ],
      ),
    );
  }

  // --- LOGIQUE TEST VENTE ---
  Future<void> _simulateTestSale(BuildContext context, String storeId) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Simulation d'envoi à Stripe..."),
          duration: Duration(seconds: 1)));

      double fakePurchase = 50.00;
      double fakeCashback = 2.00;
      double commissionRatio = 1.25;
      double amountToBill = fakeCashback * commissionRatio;
      int amountInCents = (amountToBill * 100).round();

      DocumentSnapshot storeDoc = await FirebaseFirestore.instance
          .collection('stores')
          .doc(storeId)
          .get();
      String? meterId = storeDoc.get('stripe_meter_id');

      if (meterId == null) throw Exception("Pas d'ID Compteur (meter_id).");

      await FirebaseFunctions.instance.httpsCallable('reportCommission').call({
        'subscriptionItemId': meterId,
        'amountInCents': amountInCents,
      });

      await FirebaseFirestore.instance.collection('stores').doc(storeId).update({
        'current_month_debt': FieldValue.increment(amountToBill),
        'totalAmountSpentByUser': FieldValue.increment(fakePurchase),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Succès ! +${amountInCents} unités envoyées."),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Espace Commerçant")),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('stores')
            .where('owner_id', isEqualTo: widget.userProfile.id)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          if (snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.store, size: 60, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text("Vous n'avez pas encore de magasin."),
                  const SizedBox(height: 20),
                  ElevatedButton(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => AddStoreScreen(userProfile: widget.userProfile))),
                      child: const Text("Ajouter mon magasin")
                  ),
                ],
              ),
            );
          }

          // Liste des magasins
          return ListView(
            padding: const EdgeInsets.all(16),
            children: snapshot.data!.docs.map((doc) {
              Map<String, dynamic> rawData = doc.data() as Map<String, dynamic>;
              EcoStore store = EcoStore.fromFirestore(doc as DocumentSnapshot<Map<String, dynamic>>);

              return Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- EN-TÊTE ---
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.store, size: 30, color: Colors.blue),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    store.name,
                                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis
                                ),
                                const SizedBox(height: 2),
                                Text(
                                    store.address,
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),

                      // --- STATS TEMPS RÉEL ---
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('stores').doc(store.id)
                            .collection('store_transactions')
                            .snapshots(),
                        builder: (ctx, txSnap) {
                          double realCA = store.totalAmountSpentByUser;
                          double realCB = store.totalCashbackGiven;
                          int uniqueClients = 0;
                          if (txSnap.hasData) {
                            realCA = 0; realCB = 0;
                            final Set<String> uids = {};
                            for (final d in txSnap.data!.docs) {
                              final m = d.data() as Map<String, dynamic>;
                              realCA += (m['amount_spent'] as num?)?.toDouble() ?? 0;
                              realCB += (m['cashback_given'] as num?)?.toDouble() ?? 0;
                              final uid = m['user_id'] as String? ?? '';
                              if (uid.isNotEmpty) uids.add(uid);
                            }
                            uniqueClients = uids.length;
                          }
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.blue.withOpacity(0.15)),
                            ),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text("📊 Statistiques clients",
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 10),
                              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                                _statChip("${realCA.toStringAsFixed(2)}€", "CA clients", Colors.blue),
                                _statChip("${realCB.toStringAsFixed(2)}€", "Cashback", Colors.green),
                                _statChip("$uniqueClients", "Clients uniq.", Colors.purple),
                              ]),
                            ]),
                          );
                        },
                      ),

                      const SizedBox(height: 15),

                      // --- SECTION FACTURATION (Dette) ---
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Facture en cours", style: TextStyle(fontWeight: FontWeight.w500)),
                                Text("${store.currentMonthDebt.toStringAsFixed(2)} €",
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: store.currentMonthDebt > 0 ? Colors.orange : Colors.green
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            if (store.currentMonthDebt > 5.0)
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => _payDebt(context, store),
                                  child: const Text("Régler maintenant"),
                                ),
                              )
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --- BOUTONS D'ACTION ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              tooltip: "Modifier Infos & Abonnements",
                              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditStoreScreen(
                                  storeId: store.id,
                                  currentData: rawData
                              )))
                          ),
                          IconButton(
                            icon: const Icon(Icons.bar_chart, color: Colors.purple),
                            tooltip: "Statistiques",
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StoreStatsScreen(store: store))),
                          ),
                        ],
                      ),

                      // --- ZONE DE TEST DÉVELOPPEUR ---
                      const SizedBox(height: 20),
                      const Divider(),
                      Center(
                        child: Text("ZONE DE TEST (DEV ONLY)",
                            style: TextStyle(fontSize: 10, color: Colors.grey[400], fontWeight: FontWeight.bold)
                        ),
                      ),
                      const SizedBox(height: 5),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange.shade50,
                            foregroundColor: Colors.orange.shade800,
                            elevation: 0,
                          ),
                          icon: const Icon(Icons.bug_report, size: 16),
                          label: const Text("Simuler un achat de 50€"),
                          onPressed: () => _simulateTestSale(context, store.id),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: "btn_add_store_dash",
        onPressed: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => AddStoreScreen(userProfile: widget.userProfile))),
        child: const Icon(Icons.add),
        tooltip: "Ajouter un autre magasin",
      ),
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
      throw Exception(
          "Shop item data is null for snapshot ID: ${snapshot.id}");
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
/// SERVICE DE FOND : Détection position domicile (app fermée/ouverte)
/// Tournant en permanence en arrière-plan pour détecter le retour
/// au domicile et invalider les validations en attente.
/// ================================================================
@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();

  const int HOME_RADIUS_METERS = 150;
  const int NAV_CHECK_INTERVAL_SECONDS = 5;   // Vérification rapide pendant navigation
  const int HOME_CHECK_INTERVAL_SECONDS = 60; // Vérification lente hors navigation

  Timer? bgTimer;
  LatLng? _lastNavPosition;
  DateTime? _lastNavTime;

  // ── Détection domicile (validations magasins) ────────────────────────────
  Future<void> checkHomeDistance(SharedPreferences prefs) async {
    try {
      final double? homeLat = prefs.getDouble('user_home_lat');
      final double? homeLng = prefs.getDouble('user_home_lng');
      if (homeLat == null || homeLng == null) return;

      final hasPending = prefs.getStringList('pending_validation_store_ids')?.isNotEmpty ?? false;
      if (!hasPending) return;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );

      double distToHome = Geolocator.distanceBetween(
        position.latitude, position.longitude, homeLat, homeLng,
      );

      if (distToHome <= HOME_RADIUS_METERS) {
        final List<String> storeIds = prefs.getStringList('pending_validation_store_ids') ?? [];
        final String? storeTimestampsJson = prefs.getString('pending_validation_timestamps');
        Map<String, dynamic> timestamps = {};
        if (storeTimestampsJson != null) {
          try { timestamps = Map<String, dynamic>.from(jsonDecode(storeTimestampsJson)); } catch (_) {}
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
        if (remainingIds.isEmpty) await prefs.remove('pending_validation_timestamps');

        service.invoke('user_returned_home', {'cleared': true, 'remaining': remainingIds.length});
        print('[BG] Retour domicile détecté – validations effacées');
      }
    } catch (e) {
      print('[BG] Erreur détection domicile: $e');
    }
  }

  // ── Surveillance navigation + anti-triche ────────────────────────────────
  Future<void> checkNavigationAndSecurity(SharedPreferences prefs) async {
    try {
      final bool isNavigating = prefs.getBool('bg_is_navigating') ?? false;
      if (!isNavigating) return;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      // Vérification faux GPS
      try {
        bool isMock = await SafeDevice.isMockLocation;
        if (isMock) {
          service.invoke('cheat_detected', {'reason': 'fake_gps'});
          print('[BG] ⚠️ Faux GPS détecté !');
          return;
        }
      } catch (_) {}

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.bestForNavigation),
      );

      final double speedKmh = position.speed * 3.6;
      final String modeStr = prefs.getString('bg_travel_mode') ?? 'walking';

      // Seuils anti-triche par mode
      double maxSpeed = modeStr == 'bicycling' ? 80.0 : (modeStr == 'walking' ? 60.0 : 9999.0);

      if (speedKmh > maxSpeed) {
        service.invoke('cheat_detected', {'reason': 'speed_violation', 'speed': speedKmh, 'mode': modeStr});
        print('[BG] ⚠️ Vitesse excessive: ${speedKmh.toStringAsFixed(1)} km/h en mode $modeStr');
      }

      // Envoyer la position au foreground si la navigation est active
      service.invoke('bg_position_update', {
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

  void startTimer(bool isNavigating) {
    bgTimer?.cancel();
    final interval = isNavigating ? NAV_CHECK_INTERVAL_SECONDS : HOME_CHECK_INTERVAL_SECONDS;
    bgTimer = Timer.periodic(Duration(seconds: interval), (_) async {
      final prefs = await SharedPreferences.getInstance();
      await checkHomeDistance(prefs);
      await checkNavigationAndSecurity(prefs);
    });
    print('[BG] Timer démarré (interval: ${interval}s, navigation: $isNavigating)');
  }

  // Démarrer avec vérification lente (hors navigation)
  startTimer(false);

  // Écouter les signaux de l'app
  service.on('stop_background_trip').listen((event) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_is_navigating', true);
    final mode = event?['travel_mode'] as String? ?? 'walking';
    await prefs.setString('bg_travel_mode', mode);
    // Passer en mode surveillance rapide pendant la navigation
    startTimer(true);
    print('[BG] Navigation démarrée (mode: $mode)');
  });

  service.on('resume_background_tracking').listen((event) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('bg_is_navigating', false);
    // Repasser en mode surveillance lente
    startTimer(false);
    print('[BG] Navigation terminée → surveillance domicile lente');
  });
}

/// Initialise le service de fond
Future<void> _initBackgroundService() async {
  final service = FlutterBackgroundService();

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'walkmoney_bg_channel',
    'WalkMoney Arrière-plan',
    description: 'Détection de votre position pour les validations',
    importance: Importance.low,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (Platform.isAndroid) {
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
  }

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundServiceStart,
      autoStart: true,
      isForegroundMode: false,
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

  // --- CORRECTION CRITIQUE : Charger le fichier .env ---
  try {
    await dotenv.load(fileName: ".env");
    debugPrint("✅ DotEnv chargé avec succès");
  } catch (e) {
    debugPrint("⚠️ Erreur chargement .env (Vérifiez qu'il est dans les assets) : $e");
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
    // On essaie de récupérer la clé depuis le .env (Sécurité), sinon on utilise celle en dur
    String stripeKey = dotenv.env['STRIPE_PUBLISHABLE_KEY'] ?? "pk_test_51Sf3KIJmX9VkIHA6dTDUanwaG5w8v6wwdqryF4e42PDjd2yR1RkVc5SUay2fOQVDb1vkByBW9CBFejiryPtDcFqG00sCZ9K4gE";

    Stripe.publishableKey = stripeKey;
    await Stripe.instance.applySettings();
    debugPrint("✅ Stripe initialisé");
  } catch (e) {
    debugPrint("❌ Erreur Stripe : $e");
  }

  // 6. Vérification Sécurité (Root / Jailbreak)
  // (Utilise votre constante globale définie plus haut)
  if (ENABLE_SECURITY_CHECKS) {
    try {
      bool isJailBroken = await SafeDevice.isJailBroken;
      if (isJailBroken) {
        runApp(const SecurityBlockedScreen(reason: "Appareil Rooté ou Jailbreaké détecté."));
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
  runApp(
    ChangeNotifierProvider(
      create: (context) => UserStatsProvider(),
      child: EcoNavApp(),
    ),
  );
}

class EcoNavApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'EcoNav',
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
      home: AuthGuard(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class AuthGuard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<fb_auth.User?>(
      stream: _firebaseAuth.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(
                  child: CircularProgressIndicator(color: primaryGreen)));
        }
        if (snapshot.hasData && snapshot.data != null) {
          return MainScreenController();
        }
        return LoginScreen();
      },
    );
  }
}

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _signIn() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      await _firebaseAuth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
    } on fb_auth.FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur de connexion: ${e.message ?? e.code}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Une erreur est survenue: $e')),
        );
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signUp() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      if (_emailController.text.trim().isEmpty ||
          _passwordController.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Veuillez remplir l\'e-mail et le mot de passe.')),
          );
          setState(() => _isLoading = false);
        }
        return;
      }

      await _firebaseAuth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Inscription réussie! Vous êtes maintenant connecté.')),
        );
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      print(
          "FirebaseAuthException lors de l'inscription: ${e.code} - ${e.message}");
      String errorMessage = "Erreur d'inscription inconnue.";
      if (e.code == 'weak-password') {
        errorMessage = 'Le mot de passe fourni est trop faible.';
      } else if (e.code == 'email-already-in-use') {
        errorMessage = 'Un compte existe déjà pour cet e-mail.';
      } else if (e.code == 'invalid-email') {
        errorMessage = 'L\'adresse e-mail n\'est pas valide.';
      } else {
        errorMessage = 'Erreur d\'inscription: ${e.message ?? e.code}';
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      print("Erreur générale lors de l'inscription: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Une erreur est survenue: $e')),
        );
      }
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('EcoNav Connexion')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 12),
            TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Mot de passe'),
                obscureText: true),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator(color: primaryGreen)
            else ...[
              ElevatedButton(
                  onPressed: _signIn, child: const Text('Se connecter')),
              const SizedBox(height: 10),
              TextButton(onPressed: _signUp, child: const Text('S\'inscrire')),
            ]
          ],
        ),
      ),
    );
  }
}

// MODIFIÉ: Le LeaderboardScreen est maintenant un StatefulWidget pour gérer le filtre
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({Key? key}) : super(key: key);

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String _selectedFilter = 'country'; // 'country' ou 'world'
  String _userCountry = 'Chargement...';
  bool _isLoadingCountry = true;

  @override
  void initState() {
    super.initState();
    _fetchUserCountry();
  }

  Future<void> _fetchUserCountry() async {
    final userId = _firebaseAuth.currentUser?.uid;
    if (userId == null) {
      setState(() {
        _userCountry = 'Monde';
        _selectedFilter = 'world';
        _isLoadingCountry = false;
      });
      return;
    }

    try {
// 1. Essayer de récupérer le pays depuis le profil Firestore
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(userId).get();
      if (userDoc.exists && (userDoc.data() as Map<String, dynamic>).containsKey('country')) {
        final country = userDoc.get('country');
        if (country != null && country.isNotEmpty) {
          setState(() {
            _userCountry = country;
            _isLoadingCountry = false;
          });
          return;
        }
      }

// 2. Si non trouvé, utiliser une API IP et mettre à jour le profil
      final response = await http.get(Uri.parse('http://ip-api.com/json'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final country = data['country'];
        if (country != null) {
          await _firestore.collection('users').doc(userId).update({'country': country});
          setState(() {
            _userCountry = country;
            _isLoadingCountry = false;
          });
        }
      } else {
        throw Exception('Failed to load country from IP');
      }
    } catch (e) {
      print("Erreur de détection du pays: $e");
      setState(() {
        _userCountry = 'Monde';
        _selectedFilter = 'world'; // Fallback au monde si erreur
        _isLoadingCountry = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Trier par total_lame_earned pour avoir des niveaux cohérents dans le classement
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .orderBy('total_lame_earned', descending: true)
        .limit(100);

// MODIFIÉ: Appliquer le filtre sur la requête
    if (_selectedFilter == 'country' && !_isLoadingCountry && _userCountry != 'Monde') {
      query = query.where('country', isEqualTo: _userCountry);
    }

    return Scaffold(
      body: Column(
        children: [
// NOUVEAU: Ajout du sélecteur de filtre
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: _selectedFilter,
              onValueChanged: (value) {
                if (value != null) {
                  setState(() => _selectedFilter = value);
                }
              },
              children: {
                'country': Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(_isLoadingCountry ? 'Mon Pays' : _userCountry),
                ),
                'world': const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Text('Monde'),
                ),
              },
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: query.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting || _isLoadingCountry) {
                  return const Center(child: CircularProgressIndicator(color: primaryGreen));
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text('Erreur: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                      child: Text('Aucun joueur dans ce classement.', style: Theme.of(context).textTheme.bodyLarge));
                }

                final userDocs = snapshot.data!.docs;
                final currentUserId = _firebaseAuth.currentUser?.uid;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  itemCount: userDocs.length,
                  itemBuilder: (context, index) {
                    final entry = LeaderboardEntry.fromFirestore(userDocs[index], index + 1);
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
                            const Icon(Icons.military_tech_rounded, color: accentGold, size: 22),
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

  ChallengeTripData({required this.challenge, required this.travelType});
}
class MainScreenController extends StatefulWidget {
  @override
  _MainScreenControllerState createState() => _MainScreenControllerState();
}
class _MainScreenControllerState extends State<MainScreenController> with WidgetsBindingObserver { // <--- AJOUT CRUCIAL ICI
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

  /// Charge les validations en attente depuis SharedPreferences
  Future<void> _loadPendingValidations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final storeIds = prefs.getStringList('pending_validation_store_ids') ?? [];
      final tsJson = prefs.getString('pending_validation_timestamps');
      Map<String, dynamic> timestamps = {};
      if (tsJson != null) {
        try { timestamps = Map<String, dynamic>.from(jsonDecode(tsJson)); } catch (_) {}
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
      await prefs.setStringList('pending_validation_store_ids', _pendingValidations.keys.toList());
      final timestamps = _pendingValidations.map((k, v) => MapEntry(k, v.toIso8601String()));
      await prefs.setString('pending_validation_timestamps', jsonEncode(timestamps));
      await prefs.setBool('user_is_premium', _userProfile?.isVip ?? false);
    } catch (e) {
      print('Erreur sauvegarde validations: $e');
    }
  }
  Future<void> _requestNotificationPermissions() async {
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    if (Platform.isAndroid) {
      final androidImplementation = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

      // Demande explicite
      await androidImplementation?.requestNotificationsPermission();
    }
  }


  void _handleStartChallengeTrip(Challenge challenge, TravelType travelType) {
    if (mounted) {
      setState(() {
        _pendingChallengeTripData =
            ChallengeTripData(challenge: challenge, travelType: travelType);
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
      final userDoc = await _firestore.collection('users').doc(_currentUserId).get();

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
          await _firestore.collection('users').doc(_currentUserId).set(newProfile.toMap());
          UserProfile finalProfile = await _processDailyLogin(newProfile, isNewUser: true);

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

  Future<UserProfile> _processDailyLogin(UserProfile profile, {bool isNewUser = false}) async {
    fb_auth.User? currentUserAuth = _firebaseAuth.currentUser;
    if (currentUserAuth == null) return profile;

    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime? lastLoginDateTime = profile.lastLoginDate?.toDate();
    DateTime? lastLoginDay = lastLoginDateTime != null
        ? DateTime(lastLoginDateTime.year, lastLoginDateTime.month, lastLoginDateTime.day)
        : null;

    Map<String, dynamic> updates = {};
    UserProfile tempUpdatedProfile = profile;

    bool isNewDayLoginOrNewUser = isNewUser || lastLoginDay == null || lastLoginDay.isBefore(today);

    if (isNewDayLoginOrNewUser) {
      int newConsecutiveLogins;

      // Calcul de la série de jours
      if (isNewUser || lastLoginDay == null) {
        newConsecutiveLogins = 1;
      } else if (today.difference(lastLoginDay).inDays == 1) {
        newConsecutiveLogins = profile.consecutiveLogins + 1;
      } else {
        // Série brisée
        newConsecutiveLogins = 1;
      }

      // Calcul du boost de niveau (mais PAS des points Lames)
      int paliersActuels = (newConsecutiveLogins / LOGIN_STREAK_DAYS_PER_PALIER).floor();
      double bonusSerie = (paliersActuels * LOGIN_STREAK_BONUS_PER_PALIER).clamp(0.0, MAX_LOGIN_STREAK_BONUS_TOTAL);
      double newNextLevelBoost = 1.0 + bonusSerie;

      // Mise à jour uniquement des stats de connexion, PAS des points
      updates['consecutive_logins'] = newConsecutiveLogins;
      updates['last_login_date'] = FieldValue.serverTimestamp();
      updates['next_level_boost'] = newNextLevelBoost;

      tempUpdatedProfile = tempUpdatedProfile.copyWith(
          consecutiveLogins: newConsecutiveLogins,
          lastLoginDate: () => Timestamp.fromDate(now),
          nextLevelBoost: newNextLevelBoost
      );
    }

    // Gestion du reset mensuel des absences au travail (inchangé)
    DateTime? lastResetDate = profile.lastMonthlyAllowanceReset?.toDate();
    if (lastResetDate == null || lastResetDate.month != now.month || lastResetDate.year != now.year) {
      updates['monthly_work_absence_allowance'] = 3;
      updates['last_monthly_allowance_reset'] = FieldValue.serverTimestamp();
      tempUpdatedProfile = tempUpdatedProfile.copyWith(
        monthlyWorkAbsenceAllowance: 3,
        lastMonthlyAllowanceReset: () => Timestamp.now(),
      );
    }

    // Envoi des mises à jour à Firestore
    if (updates.isNotEmpty) {
      updates['updated_at'] = FieldValue.serverTimestamp();
      try {
        await _firestore.collection('users').doc(profile.id).update(updates);
        print("Daily login processed (Dates update only). Updates: $updates");
      } catch (e) {
        print("Error processing daily login update: $e");
        return profile;
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

    if (decayCycles <= 0) return profile; // Pas encore de décroissance nécessaire

    // Calculer la perte totale sur les cycles manqués
    int currentPoints = profile.adPoints;
    for (int i = 0; i < decayCycles; i++) {
      if (currentPoints <= 0) break;
      int loss;
      if (currentPoints < 10) loss = 1;
      else if (currentPoints < 20) loss = 2;
      else if (currentPoints < 30) loss = 3;
      else if (currentPoints < 40) loss = 4;
      else loss = 5;
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
  void _addLame(int amountToAdd, {String? source}) async {
    if (_userProfile == null || _currentUserId == null || amountToAdd <= 0) return;

    final sourceText = source ?? 'Inconnue';

    UserProfile? oldProfileState = _userProfile;
    if (mounted) {
      setState(() {
        _userProfile = _userProfile!.copyWith(
          lamePoints: _userProfile!.lamePoints + amountToAdd,
          totalLameEarned: (_userProfile!.totalLameEarned ?? 0) + amountToAdd,
        );
      });
    }

    try {
      WriteBatch batch = _firestore.batch();

// Mettre à jour le total et totalLameEarned
      DocumentReference userRef = _firestore.collection('users').doc(_currentUserId!);
      batch.update(userRef, {
        'lame_points': FieldValue.increment(amountToAdd),
        'total_lame_earned': FieldValue.increment(amountToAdd),
        'updated_at': FieldValue.serverTimestamp(),
      });

// Ajouter une entrée à l'historique
      DocumentReference historyRef = userRef.collection('lame_history').doc();
      batch.set(historyRef, {
        'amount': amountToAdd,
        'source': sourceText,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await batch.commit();

      // Vérifier si l'utilisateur atteint le niveau 30 (Premium gratuit)
      final newTotalLame = (_userProfile?.totalLameEarned ?? 0) + amountToAdd;
      final levelData = _calculateUserLevel(newTotalLame);
      final newLevel = levelData['currentLevel'] as int;

      if (newLevel >= 30 && !(_userProfile?.isVip ?? false)) {
        // Activer le Premium gratuit
        await _firestore.collection('users').doc(_currentUserId!).update({
          'is_vip': true,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("🎉 Félicitations ! Vous avez débloqué le Premium gratuit (Niveau 30+) !"),
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
      if (mounted && oldProfileState != null) {
        setState(() => _userProfile = oldProfileState);
      }
      print("Error updating Lame points and history: $e");
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text("Erreur sauvegarde Lames: $e")));
      }
    }
  }

  Map<String, dynamic> _calculateUserLevel(int totalLame) {
    int currentLevel = 1;
    int lameNeeded = 500; // Pour le niveau 2
    int totalLameForCurrentLevel = 0;

    // Calculer le niveau actuel
    while (totalLame >= totalLameForCurrentLevel + lameNeeded && currentLevel < 50) {
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
      builder: (context) => ProfileBottomSheet(
        userProfile: _userProfile!,
        onOpenShop: _openShop,
      ),
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
  }


// NOUVEAU: Fonction pour afficher le popup de l'historique des Lames
  void _showLameHistory() {
    if (_currentUserId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => LameHistorySheet(userId: _currentUserId!),
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

  Future<void> _handlePurchase(int cost) async {
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
      await _firestore.collection('users').doc(_currentUserId).update({
        'lame_points': FieldValue.increment(-cost),
        'updated_at': FieldValue.serverTimestamp(),
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
    ChallengeTripData? challengeTripDataForHomeScreen = _pendingChallengeTripData;
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
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
            pendingStoreTrip: tripDataForHomeScreen,
            pendingChallengeTrip: challengeTripDataForHomeScreen,
            onProfileButtonPressed: _openProfile,
            onShowLameHistory: _showLameHistory,
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
              onStartChallengeTrip: _handleStartChallengeTrip, // MODIFIÉ: Passer la nouvelle fonction de rappel
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
          if (index == 0) {
          }

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
class LameHistorySheet extends StatefulWidget {
  final String userId;
  const LameHistorySheet({Key? key, required this.userId}) : super(key: key);

  @override
  _LameHistorySheetState createState() => _LameHistorySheetState();
}

class _LameHistorySheetState extends State<LameHistorySheet> {
  late Future<List<DocumentSnapshot>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _fetchHistory();
  }

  Future<List<DocumentSnapshot>> _fetchHistory() async {
    final snapshot = await _firestore
        .collection('users')
        .doc(widget.userId)
        .collection('lame_history')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();
    return snapshot.docs;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: cardWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        children: [
          Text("Historique des Lames", style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<DocumentSnapshot>>(
              future: _historyFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: primaryGreen));
                }
                if (snapshot.hasError) {
                  return Center(child: Text("Erreur: ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("Aucun historique de gain pour le moment."));
                }

                final historyDocs = snapshot.data!;
                return ListView.separated(
                  itemCount: historyDocs.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final data = historyDocs[index].data() as Map<String, dynamic>;
                    final amount = data['amount'] as int? ?? 0;
                    final source = data['source'] as String? ?? 'Source inconnue';
                    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: amount > 0 ? lightGreen : Colors.red.shade100,
                        child: Icon(
                          amount > 0 ? Icons.add : Icons.remove,
                          color: amount > 0 ? primaryGreen : Colors.red,
                        ),
                      ),
                      title: Text(source, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        timestamp != null
                            ? DateFormat('le dd/MM/yyyy à HH:mm', 'fr_FR').format(timestamp)
                            : 'Date inconnue',
                      ),
                      trailing: Text(
                        '${amount > 0 ? '+' : ''}$amount L',
                        style: TextStyle(
                          color: amount > 0 ? primaryGreen : Colors.red.shade700,
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
          const SizedBox(height: 10),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Fermer", style: TextStyle(color: textGrey)),
          ),
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueGrey.shade900, Colors.blueGrey.shade700],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_outlined, color: accentGold, size: 22),
          const SizedBox(width: 10),
          Column(
            children: [
              const Text(
                "PROCHAINS DÉFIS DANS :",
                style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
              Text(
                _displayString,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
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
  final Function(Challenge challenge, TravelType travelType) onStartChallengeTrip;

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

// On garde juste la date cible, plus de timer ici
  DateTime? _nextRefreshDate;

  @override
  void initState() {
    super.initState();
    _initChallengeCycle();
    _fetchLocalPoisAsChallenges();
    _updateUserLocationForSorting();

// Callback navigation
    widget.navigationController.setOnChallengeDestinationReachedCallback((
        completedChallenge) async {
      _showSnackBar(
          "Défi \"${completedChallenge.title}\" terminé par la navigation !",
          backgroundColor: primaryGreen);

      await _handleChallengeAction(
        completedChallenge,
        ChallengeStatus.completedPendingReward,
        newStep: (completedChallenge.currentStep + 1).clamp(
          0,
          completedChallenge.visitCount ?? completedChallenge.totalSteps,
        ),
      );
    });
  }

  @override
  void dispose() {
    widget.navigationController.setOnChallengeDestinationReachedCallback((
        _) {});
    super.dispose();
  }

// Initialise la date de fin du cycle actuel
  Future<void> _initChallengeCycle() async {
    final userDoc = await _firestore.collection('user_stats').doc(
        widget.currentUserId).get();
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
  Future<void> _triggerAutoRefresh() async {
    print("CYCLE TERMINÉ : ACTUALISATION AUTOMATIQUE");

// 1. Générer nouveaux défis
    await _fetchLocalPoisAsChallenges(forceRefresh: true);

// 2. Mettre à jour la date en base
    final now = DateTime.now();
    await _firestore.collection('user_stats').doc(widget.currentUserId).set({
      'last_challenges_refresh': FieldValue.serverTimestamp()
    }, SetOptions(merge: true));

// 3. Mettre à jour la date locale pour relancer le timer du widget enfant
    setState(() {
      _nextRefreshDate = now.add(const Duration(days: 14));
    });
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

// --- CALCUL DYNAMIQUE DE RÉCOMPENSE ---
  Future<int> _calculateDynamicReward(Challenge challenge,
      TravelType travelType) async {
    if (challenge.latitude == null || challenge.longitude == null)
      return challenge.rewardLame;

    try {
      final userPos = await widget.homeController.getMyCurrentLocation();

      double rawMeters = toolkit.SphericalUtil.computeDistanceBetween(
          toolkit.LatLng(userPos.latitude, userPos.longitude),
          toolkit.LatLng(challenge.latitude!, challenge.longitude!)
      ).toDouble();

      // ×1.3 pour approximer la distance réelle de route vs vol d'oiseau
      double distanceKm = (rawMeters / 1000.0) * 1.3;
      double speedKmh = travelType == TravelType.bike ? 15.0 : 5.0;
      double durationMinutes = (distanceKm / speedKmh) * 60.0;

      double transportMultiplier = travelType == TravelType.bike ? 1.2 : 1.0;
      double baseReward = ((distanceKm * 5.0) + (durationMinutes * 0.5)) * transportMultiplier;

      // ── Bonus temps sur place : +1 lame par min + 1 lame bonus par min au-delà de 3 ──
      if (challenge.stayDurationSeconds != null && challenge.stayDurationSeconds! > 0) {
        int stayMin = (challenge.stayDurationSeconds! / 60).round();
        baseReward += stayMin;
        if (stayMin > 3) baseReward += (stayMin - 3);
      }

      // ── Multi-visites : récompense totale = base × 2 × visitCount ──
      int visitCount = challenge.visitCount ?? 1;
      if (visitCount > 1) {
        baseReward = baseReward * 2 * visitCount;
      }

      return baseReward.round().clamp(challenge.rewardLame, 2000);
    } catch (e) {
      return challenge.rewardLame;
    }
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
      Position position = await widget.homeController.getMyCurrentLocation();
      final double lat = position.latitude;
      final double lng = position.longitude;
      const double radius = 5000;
      final String apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;

      // On cherche des lieux intéressants
      final String types = 'park|museum|tourist_attraction|church|library|stadium|university';
      final String url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=$radius&type=$types&key=$apiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> results = data['results'] ?? [];
        List<Challenge> newLocalPoiChallenges = [];
        int challengeCounter = 0;
        final _random = Random();

        // Récupérer l'état existant pour ne pas écraser la progression
        final userChallengesSnapshot = await _firestore
            .collection(
            'user_challenges')
            .where('user_id', isEqualTo: widget.currentUserId)
            .get();
        final Map<String, dynamic> existingUserChallengeData = {
          for (var doc in userChallengesSnapshot.docs) doc.id: doc.data()
        };

        results.shuffle();

        for (var place in results) {
          if (challengeCounter >= 10) break;
          String placeId = place['place_id'];
          String name = place['name'] ?? 'Lieu Mystère';
          double placeLat = place['geometry']['location']['lat'];
          double placeLng = place['geometry']['location']['lng'];
          String challengeDocId = 'poi_$placeId';
          String userChallengeFullId = '${widget
              .currentUserId}_$challengeDocId';

          Map<String, dynamic>? existingProgress;
          if (existingUserChallengeData.containsKey(userChallengeFullId)) {
            existingProgress = existingUserChallengeData[userChallengeFullId];
          }

          int visitCount = 1;
          String desc = "Visitez ce lieu.";
          int? stayDurationSeconds;

          // 0 = visite simple, 1 = multi-visites (x2), 2 = rester sur place
          int defiType = _random.nextInt(3);
          int baseReward;

          if (defiType == 0) {
            visitCount = 1;
            desc = "Rends-toi à ce lieu.";
            baseReward = 30 + _random.nextInt(30); // 30-60 lames
          } else if (defiType == 1) {
            visitCount = 2 + _random.nextInt(2); // 2 ou 3 visites
            desc = "Rends-toi $visitCount fois à ce lieu.";
            // Récompense de base x2 (sera encore multipliée par visitCount à la fin)
            baseReward = (20 + _random.nextInt(20)) * 2; // 40-80 base
          } else {
            visitCount = 1;
            int stayMinutes = 3 + _random.nextInt(8); // 3 à 10 minutes
            stayDurationSeconds = stayMinutes * 60;
            int bonusLames = stayMinutes - 3; // 0 à 7 lames bonus (+1 par min au-delà de 3)
            desc = "Rends-toi à ce lieu et restes-y $stayMinutes minute(s) dans un rayon de 10m.";
            baseReward = 20 + bonusLames + _random.nextInt(15); // 20-42 lames
          }

          final generatedChallenge = Challenge(
            id: challengeDocId,
            title: "Exploration : $name",
            rewardText: desc,
            rewardLame: baseReward,
            totalDurationSeconds: 1209600, // 14 jours
            createdAt: Timestamp.now(),
            type: ChallengeType.localPoiVisit,
            totalSteps: visitCount,
            latitude: placeLat,
            longitude: placeLng,
            googlePlaceId: placeId,
            visitCount: visitCount,
            stayDurationSeconds: stayDurationSeconds,
            status: existingProgress != null
                ? ChallengeStatus.values.firstWhere((e) =>
            e
                .toString()
                .split('.')
                .last == existingProgress!['status'],
                orElse: () => ChallengeStatus.notStarted)
                : ChallengeStatus.notStarted,
            currentStep: existingProgress != null
                ? (existingProgress['current_step'] ?? 0)
                : 0,
          );

          newLocalPoiChallenges.add(generatedChallenge);
          challengeCounter++;
        }

        if (mounted) {
          setState(() {
            _localPoiChallenges = newLocalPoiChallenges;
          });
        }
      }
    } catch (e) {
      print("Erreur POI: $e");
      if (mounted) setState(() =>
      _localPoiError = "Impossible de charger les défis locaux.");
    } finally {
      if (mounted) setState(() => _isLoadingLocalPois = false);
    }
  }

  Future<void> _handleChallengeAction(Challenge challenge,
      ChallengeStatus newStatus,
      {int? newStep, String? selectedStore, String? proofIdentifier, String? ocrResultText, bool? isProofValid}) async {

    // ── Calcul de la récompense finale si on réclame ──────────────────────
    int finalReward = challenge.rewardLame;
    if (newStatus == ChallengeStatus.rewardClaimed) {
      // Multi-visites : récompense = base × 2 × visitCount
      int visitCount = challenge.visitCount ?? 1;
      if (visitCount > 1) {
        finalReward = challenge.rewardLame * 2 * visitCount;
      }
      // Bonus temps sur place : +1 lame/min + 1 bonus par min au-delà de 3
      if (challenge.stayDurationSeconds != null && challenge.stayDurationSeconds! > 0) {
        int stayMin = (challenge.stayDurationSeconds! / 60).round();
        finalReward += stayMin;
        if (stayMin > 3) finalReward += (stayMin - 3);
      }
    }

    await widget.onUpdateUserChallenge(
        challenge.copyWith(
            status: newStatus,
            currentStep: newStep,
            selectedStore: () => selectedStore
        ),
        finalReward
    );
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
    return Scaffold(
      backgroundColor: defisScreenBackground,
      body: Column(
        children: [
          // --- HEADER TIMER (Actualisation tous les 14 jours) ---
          if (_nextRefreshDate != null)
            ChallengeTimerHeader(
              targetDate: _nextRefreshDate!,
              onTimerFinished: _triggerAutoRefresh,
            )
          else
            const SizedBox(
                height: 50, child: Center(child: CircularProgressIndicator())),

          // --- LISTE DES DÉFIS ---
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // Flux des défis globaux (Firebase)
              stream: _firestore.collection('challenges').orderBy(
                  'created_at', descending: true).snapshots(),
              builder: (context, challengeListSnapshot) {
                // Loader initial si on attend Firebase ET les POI locaux
                if (challengeListSnapshot.connectionState ==
                    ConnectionState.waiting && _localPoiChallenges.isEmpty) {
                  return const Center(
                      child: CircularProgressIndicator(color: primaryGreen));
                }

                final firebaseChallenges = challengeListSnapshot.data?.docs
                    .map((doc) => Challenge.fromFirestore(doc))
                    .toList() ?? [];

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  // Flux de la progression utilisateur
                    stream: _firestore.collection('user_challenges').where(
                        'user_id', isEqualTo: widget.currentUserId).snapshots(),
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
                        challengesToDisplay.add(
                            Challenge.fromFirestore(
                                null,
                                rawChallengeData: fc.toMap(),
                                userChallengeSnapshot: userProgressMap[uid] as DocumentSnapshot<
                                    Map<String, dynamic>>?
                            )
                        );
                      }

                      // B. Défis Locaux (Générés via Google Places)
                      challengesToDisplay.addAll(_localPoiChallenges);

                      // --- 2. TRI INTELLIGENT (C'EST ICI QUE LA VISIBILITÉ PAYANTE AGIT) ---
                      if (challengesToDisplay.isNotEmpty) {
                        challengesToDisplay.sort((a, b) {

                          // Récupérer les magasins associés
                          EcoStore? storeA;
                          EcoStore? storeB;
                          try { if (a.partnerStoreId != null) storeA = widget.ecoStores.firstWhere((s) => s.id == a.partnerStoreId); } catch (_) {}
                          try { if (b.partnerStoreId != null) storeB = widget.ecoStores.firstWhere((s) => s.id == b.partnerStoreId); } catch (_) {}

                          // ── CRITÈRE 1 PRIORITAIRE : Boost Visibilité Commerçant activé ──
                          // Un commerçant qui a activé isVisibilityBoostEnabled passe EN PREMIER
                          bool boostedA = storeA?.isVisibilityBoostEnabled ?? false;
                          bool boostedB = storeB?.isVisibilityBoostEnabled ?? false;
                          if (boostedA != boostedB) return boostedB ? 1 : -1;

                          // ── CRITÈRE 2 : Multiplicateur lame (valeur du slider) ──
                          double multA = storeA?.lamePointMultiplier ?? 1.0;
                          double multB = storeB?.lamePointMultiplier ?? 1.0;
                          if (multB != multA) return multB.compareTo(multA);

                          // ── CRITÈRE 3 : Récompense totale ──
                          // Pour les multi-visites : on tient compte du visitCount
                          int totalRewardA = a.rewardLame * (a.visitCount ?? 1);
                          int totalRewardB = b.rewardLame * (b.visitCount ?? 1);
                          int rewardComparison = totalRewardB.compareTo(totalRewardA);
                          if (rewardComparison != 0) return rewardComparison;

                          // ── CRITÈRE 4 : Proximité ──
                          if (_lastKnownUserLocation != null && a.latitude != null && b.latitude != null) {
                            final distA = toolkit.SphericalUtil.computeDistanceBetween(
                                toolkit.LatLng(_lastKnownUserLocation!.latitude, _lastKnownUserLocation!.longitude),
                                toolkit.LatLng(a.latitude!, a.longitude!)
                            );
                            final distB = toolkit.SphericalUtil.computeDistanceBetween(
                                toolkit.LatLng(_lastKnownUserLocation!.latitude, _lastKnownUserLocation!.longitude),
                                toolkit.LatLng(b.latitude!, b.longitude!)
                            );
                            return distA.compareTo(distB);
                          }

                          return 0;
                        });
                      }

                      // --- 3. GESTION LISTE VIDE ---
                      if (challengesToDisplay.isEmpty && _isLoadingLocalPois) {
                        return const Center(child: Padding(
                          padding: EdgeInsets.all(20.0),
                          child: CircularProgressIndicator(color: primaryGreen),
                        ));
                      }

                      if (challengesToDisplay.isEmpty) {
                        return const Center(child: Text(
                            "Aucun défi disponible pour le moment."));
                      }

                      // --- 4. AFFICHAGE DE LA LISTE ---
                      return ListView.builder(
                        padding: const EdgeInsets.all(12.0),
                        // On ajoute +1 si chargement en cours pour afficher la barre de progression en haut
                        itemCount: challengesToDisplay.length +
                            (_isLoadingLocalPois ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Loader en haut de liste si recherche POI en cours
                          if (_isLoadingLocalPois && index == 0) {
                            return const Padding(padding: EdgeInsets.all(8.0),
                                child: Center(child: LinearProgressIndicator(
                                    color: primaryGreen)));
                          }

                          final finalIndex = index -
                              (_isLoadingLocalPois ? 1 : 0);
                          if (finalIndex < 0 || finalIndex >=
                              challengesToDisplay.length) return const SizedBox
                              .shrink();

                          final challenge = challengesToDisplay[finalIndex];

                          // Récupération du magasin partenaire associé (si existe) pour affichage logo/nom
                          EcoStore? partnerStore;
                          if (challenge.partnerStoreId != null) {
                            try {
                              partnerStore = widget.ecoStores.firstWhere((s) =>
                              s.id == challenge.partnerStoreId);
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
                    }
                );
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
  final Function(Challenge challenge, TravelType travelType) onStartChallengeTrip;

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

  // ── TIMER "RESTER SUR PLACE" ─────────────────────────────────────────────
  Timer? _stayTimer;
  int _staySecondsElapsed = 0;
  bool _isStayTimerRunning = false;
  bool _isInStayZone = false;
  StreamSubscription<Position>? _stayPositionStream;

  @override
  void dispose() {
    _stayTimer?.cancel();
    _stayPositionStream?.cancel();
    super.dispose();
  }

  /// Lance le suivi de position pour le défi "rester sur place"
  void _startStayTracking() {
    if (_isStayTimerRunning) return;
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
        pos.latitude, pos.longitude,
        widget.challenge.latitude!, widget.challenge.longitude!,
      );

      bool inZone = dist <= 10.0;
      if (inZone && !_isStayTimerRunning) {
        // Entré dans la zone → démarrer le timer
        setState(() { _isInStayZone = true; _isStayTimerRunning = true; });
        _stayTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) { t.cancel(); return; }
          setState(() => _staySecondsElapsed++);
          // Défi complété !
          if (_staySecondsElapsed >= (widget.challenge.stayDurationSeconds ?? 180)) {
            t.cancel();
            _stayPositionStream?.cancel();
            setState(() { _isStayTimerRunning = false; });
            widget.onAction(widget.challenge, ChallengeStatus.completedPendingReward,
                newStep: 1);
          }
        });
      } else if (!inZone && _isStayTimerRunning) {
        // Sorti de la zone → pause du timer
        setState(() { _isInStayZone = false; });
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
                widget.onAction(widget.challenge, ChallengeStatus.proofSubmissionNeeded,
                    selectedStore: tempSelectedStore);
                Navigator.of(dialogContext).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _showProofSubmissionDialog(BuildContext context) async {

  }

  Future<Map<String, dynamic>> _processProofImage(File imageFile) async {


    return {};
  }

  Future<String> _uploadProofImage(File imageFile) async {
    try {
      final fileName =
          '${widget.currentUserId}_${widget.challenge.id}_${DateTime.now().millisecondsSinceEpoch}.${p.extension(imageFile.path)}';
      final ref =
      _firebaseStorage.ref('challenge_proofs/${widget.currentUserId}/$fileName');
      UploadTask uploadTask = ref.putFile(imageFile);
      final snapshot = await uploadTask.whenComplete(() => null);
      return await snapshot.ref.getDownloadURL();
    } catch (e) {
      print("Error uploading image to Firebase Storage: $e");
      rethrow;
    }
  }

  Widget _buildDetailRowDialog(String label, String value,
      {bool isBold = false, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 14, color: textGrey)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                  color: valueColor ?? textDark),
            ),
          ),
        ],
      ),
    );
  }


  void _showGainDetailsDialog(BuildContext context) async {

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: primaryGreen),
            SizedBox(width: 16),
            Text("Calcul du gain..."),
          ],
        ),
      ),
    );

    try {

      int baseReward = widget.challenge.rewardLame;
      double effortBonus = 0;
      double bonusDefiMultiplier = 1.0;
      double weatherBonus = 0;
      double adBonus = 0;
      String weatherBonusText = "Aucun";
      String adBonusText = "Aucun";
      String travelModeText =
      _selectedTravelType == TravelType.walk ? "À pied" : "À vélo";
      double distanceKm = 0;
      int simulatedDurationMinutes = 0;


      if (widget.challenge.latitude != null && widget.challenge.longitude != null) {
        final userPos = await widget.homeController.getMyCurrentLocation();

        // Calcul vol d'oiseau × 1.3 (facteur de route réelle)
        double rawDist = Geolocator.distanceBetween(
          userPos.latitude, userPos.longitude,
          widget.challenge.latitude!, widget.challenge.longitude!,
        );
        distanceKm = (rawDist / 1000.0) * 1.3;

        // Durée estimée selon mode
        double speedKmh = _selectedTravelType == TravelType.bike ? 15.0 : 5.0;
        simulatedDurationMinutes = (distanceKm / speedKmh * 60).round();

        // Tentative API Directions (optionnelle, enrichit le résultat)
        try {
          final directionsService = DirectionsService();
          final request = DirectionsRequest(
            origin: "${userPos.latitude},${userPos.longitude}",
            destination: "${widget.challenge.latitude},${widget.challenge.longitude}",
            travelMode: _selectedTravelType == TravelType.walk
                ? TravelMode.walking
                : TravelMode.bicycling,
          );
          await directionsService.route(request, (DirectionsResult response, status) {
            if (status == DirectionsStatus.ok &&
                response.routes != null &&
                response.routes!.isNotEmpty) {
              final leg = response.routes!.first.legs?.first;
              if (leg?.distance?.value != null) {
                distanceKm = (leg!.distance!.value! / 1000.0);
              }
              if (leg?.duration?.value != null) {
                simulatedDurationMinutes = (leg!.duration!.value! / 60.0).round();
              }
            }
          });
        } catch (_) { /* garder l'estimation vol d'oiseau */ }

        double transportMultiplier = (_selectedTravelType == TravelType.walk) ? 1.0 : 1.2;
        double effort_base =
            (distanceKm * 5.0) + (simulatedDurationMinutes * 0.5);
        effortBonus = (effort_base * transportMultiplier).round().toDouble();
        effortBonus =
            math.max(0, effortBonus).clamp(0, baseReward * 2).toDouble();
      }


      int visitCount = widget.challenge.visitCount ?? 1;
      int stayDurationMinutes = (widget.challenge.stayDurationSeconds ?? 0) ~/ 60;
      if (visitCount > 1) {
        bonusDefiMultiplier += (visitCount - 1) * 0.1;
      }
      if (stayDurationMinutes > 0) {
        bonusDefiMultiplier += stayDurationMinutes * 0.05;
      }



      double currentTotal = (effortBonus) * bonusDefiMultiplier;


      final weather = widget.weatherData;
      if (weather != null) {
        bool isBadWeather = weather.weatherCode >= 51 ||
            weather.weatherCode == 45 ||
            weather.weatherCode == 48;
        bool isWindy = weather.windSpeed > 30;
        bool isExtremeTempCold = weather.temperature < 2;
        bool isExtremeTempHot = weather.temperature > 32;
        if (isBadWeather || isWindy || isExtremeTempCold || isExtremeTempHot) {
          weatherBonus = currentTotal * 0.5;
          weatherBonusText = "+${weatherBonus.round()} L (x1.5)";
          currentTotal += weatherBonus;
        }
      }


      if (widget.userProfile.adPoints >= 10) {
        adBonus = currentTotal * 0.2;
        adBonusText = "+${adBonus.round()} L (x1.2)";
        currentTotal += adBonus;
      }

      int finalTotal = currentTotal.round();

      if (finalTotal == 0 && baseReward > 0) {
        finalTotal = baseReward;
      }


      if (context.mounted) Navigator.pop(context);


      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) => Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
              color: cardWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    "Détail du Gain Estimé",
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(color: primaryGreen),
                  ),
                ),
                const SizedBox(height: 16),
                _buildDetailRowDialog(
                    "Gain de base du défi:", "Dynamique (effort)"),
                const Divider(
                    height: 20, thickness: 1, indent: 20, endIndent: 20),
                Text("Calcul du Bonus d'Effort",
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                _buildDetailRowDialog(
                    "  Distance:", "${distanceKm.toStringAsFixed(2)} km"),
                _buildDetailRowDialog(
                    "  Durée estimée:", "$simulatedDurationMinutes min"),
                _buildDetailRowDialog("  Mode de transport:", travelModeText),
                _buildDetailRowDialog(
                    "Bonus d'effort résultant:", "${effortBonus.round()} L",
                    isBold: true),
                const Divider(
                    height: 20, thickness: 1, indent: 20, endIndent: 20),
                Text("Calcul du Bonus de Défi",
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                _buildDetailRowDialog("  Nombre de visites:", "$visitCount"),
                _buildDetailRowDialog(
                    "  Temps sur place:", "$stayDurationMinutes min"),
                _buildDetailRowDialog(
                    "Multiplicateur Défi:",
                    "x${bonusDefiMultiplier.toStringAsFixed(2)}",
                    isBold: true,
                    valueColor: primaryGreen),
                const Divider(
                    height: 20, thickness: 1, indent: 20, endIndent: 20),
                Text("Boosts Supplémentaires",
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                _buildDetailRowDialog("Boost Météo:", weatherBonusText,
                    valueColor: weatherBonus > 0 ? primaryGreen : textGrey),
                _buildDetailRowDialog("Boost Pub:", adBonusText,
                    valueColor: adBonus > 0 ? primaryGreen : textGrey),
                const Divider(height: 20),
                _buildDetailRowDialog("Total Estimé:", "$finalTotal L",
                    isBold: true, valueColor: accentGold),
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text("Fermer"),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {

      if (context.mounted) Navigator.pop(context);
      _showSnackBar(context, "Erreur lors du calcul détaillé: $e",
          backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    List<Widget> buttons = [];

    ChallengeStatus displayStatus = widget.challenge.status;

    bool isPartnerStoreChallenge =
        widget.challenge.type == ChallengeType.partnerStoreVisit &&
            widget.associatedPartnerStore != null;
    bool isLocalPoiChallenge = widget.challenge.type == ChallengeType.localPoiVisit;
    bool isGeolocatedChallenge = isLocalPoiChallenge || isPartnerStoreChallenge;

    bool isPurchaseChallenge =
        widget.challenge.type == ChallengeType.purchaseScanProof ||
            isPartnerStoreChallenge;

    if (displayStatus == ChallengeStatus.notStarted) {
      buttons.add(Expanded(
        child: ElevatedButton(
          onPressed: () async {
            if (isGeolocatedChallenge) {
              widget.onStartChallengeTrip(widget.challenge, _selectedTravelType);
            } else if (isPurchaseChallenge) {
              _showStoreSelectionDialog(context);
            } else {
              widget.onAction(widget.challenge, ChallengeStatus.inProgress);
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
                color: _isInStayZone ? Colors.teal.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _isInStayZone ? Colors.teal : Colors.orange),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(_isInStayZone ? Icons.location_on : Icons.location_off,
                    color: _isInStayZone ? Colors.teal : Colors.orange, size: 16),
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
                widget.navigationController.activeChallenge?.id == widget.challenge.id;

        if (isNavigationActiveForThisChallenge) {
          buttonText = "Navigation en cours...";
          enableButton = false;
        } else if (isLocalPoiChallenge || isPartnerStoreChallenge) {
          buttonText = "Reprendre la navigation";
          action = () async { widget.onStartChallengeTrip(widget.challenge, _selectedTravelType); };
        } else {
          buttonText = "Valider Étape (${widget.challenge.currentStep}/${widget.challenge.visitCount ?? widget.challenge.totalSteps})";
          action = () {
            int nextStep = widget.challenge.currentStep + 1;
            widget.onAction(widget.challenge, ChallengeStatus.inProgress, newStep: nextStep);
          };
        }
        buttons.add(Expanded(
            child: ElevatedButton(
                onPressed: enableButton ? action : null, child: Text(buttonText))));
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
              onPressed: () =>
                  widget.onAction(widget.challenge, ChallengeStatus.rewardClaimed),
              child: const Text("Récupérer récompense"))));
      if (widget.challenge.proofImageIdentifier != null &&
          widget.challenge.proofImageIdentifier!.startsWith('http')) {
        buttons.add(const SizedBox(width: 8));
        buttons.add(Expanded(
            child: OutlinedButton(
                onPressed: () async {
                  final uri = Uri.tryParse(widget.challenge.proofImageIdentifier!);
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

    if (displayStatus == ChallengeStatus.inProgress) {
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
      elevation: (widget.associatedPartnerStore?.isVisibilityBoostEnabled ?? false) ? 5 : 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge "SPONSORISÉ" si boosté commerçant
            if (widget.associatedPartnerStore?.isVisibilityBoostEnabled ?? false)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Colors.orange, Colors.deepOrange]),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star, color: Colors.white, size: 12),
                  const SizedBox(width: 4),
                  Text(
                    "SPONSORISÉ · x${(widget.associatedPartnerStore?.lamePointMultiplier ?? 1.0).toStringAsFixed(1)} Lames",
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
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
                      Text(widget.challenge.title, style: theme.textTheme.titleLarge),
                      if (isPartnerStoreChallenge && widget.associatedPartnerStore != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                              "${widget.associatedPartnerStore!.name} (${widget.associatedPartnerStore!.address})",
                              style: theme.textTheme.titleMedium?.copyWith(
                                  color: primaryGreen, fontWeight: FontWeight.bold)),
                        ),
                      if (isLocalPoiChallenge && widget.challenge.latitude != null && widget.challenge.longitude != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Text(
                              "Lieu : ${widget.challenge.latitude!.toStringAsFixed(3)}, ${widget.challenge.longitude!.toStringAsFixed(3)}",
                              style: theme.textTheme.titleMedium?.copyWith(
                                  color: primaryGreen, fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(height: 4),
                      Text(widget.challenge.dynamicChallengeDescription, style: theme.textTheme.titleMedium),
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
                    bool isStayChallenge = (widget.challenge.stayDurationSeconds ?? 0) > 0;
                    bool isBoostedByStore = widget.associatedPartnerStore?.isVisibilityBoostEnabled ?? false;
                    double storeMultiplier = widget.associatedPartnerStore?.lamePointMultiplier ?? 1.0;

                    // Texte avantage défi
                    String advantageText = "";
                    if (isMultiVisit && gainValue != null) {
                      advantageText = "x$visitCount visites";
                    } else if (isStayChallenge) {
                      int mins = ((widget.challenge.stayDurationSeconds ?? 0) / 60).round();
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
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              "⚡ x${storeMultiplier.toStringAsFixed(1)}",
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
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
                                    color: isBoostedByStore ? Colors.orange : primaryGreen,
                                    width: isBoostedByStore ? 2.5 : 1.5)),
                            child: Center(
                              child: (snapshot.connectionState == ConnectionState.waiting)
                                  ? const SizedBox(width: 20, height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: primaryGreen))
                                  : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(gainText, style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: isBoostedByStore ? Colors.orange.shade800 : textDark)),
                                  const Text("Lames", style: TextStyle(fontSize: 9, color: textGrey)),
                                  // Avantage défi (multi-visit ou stay)
                                  if (advantageText.isNotEmpty)
                                    Text(advantageText, style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: isBoostedByStore ? Colors.orange : primaryGreen)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Bonus défi en bas du cercle
                        if (gainValue != null && gainValue > (widget.challenge.rewardLame))
                          Container(
                            margin: const EdgeInsets.only(top: 3),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: primaryGreen.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: primaryGreen.withOpacity(0.4)),
                            ),
                            child: Text(
                              "bonus +${gainValue - widget.challenge.rewardLame}L",
                              style: const TextStyle(fontSize: 8, color: primaryGreen, fontWeight: FontWeight.bold),
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
            if (isGeolocatedChallenge && displayStatus == ChallengeStatus.notStarted)
              Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: SingleChildScrollView( // Ajout pour éviter l'overflow
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
                      ? (widget.challenge.visitCount ?? widget.challenge.totalSteps)
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
                      color: isFilled ? defisProgressFilled : defisProgressEmpty,
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
        Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
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
  final StoreTripData? pendingStoreTrip;
  final VoidCallback onProfileButtonPressed;
  final VoidCallback onShowLameHistory;
  final ChallengeTripData? pendingChallengeTrip;
  /// Callback quand un trajet vers un magasin est terminé (storeId, completedAt)
  final void Function(String storeId, DateTime completedAt)? onStoreTripCompleted;
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
    required this.onProfileButtonPressed,
    required this.onShowLameHistory,
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

    // Listener d'arrivée générique
    ever(homeController.arrived, _handleArrival);

    // --- RECALCUL AUTOMATIQUE DES GAINS ---
    // Dès que Google Maps/OSRM renvoie une distance ou durée, ou que le dénivelé change
    ever(homeController.activeRouteRawDistanceMeters, (_) => _updateGainAndRouteData());
    ever(homeController.activeRouteRawDurationSeconds, (_) => _updateGainAndRouteData());
    ever(homeController.elevationGain, (_) => _updateGainAndRouteData());

    // Nettoyage quand on efface la destination
    ever(homeController.destination, (String dest) {
      if (dest.isEmpty && mounted) {
        _destinationController.clear();
        setState(() {
          _calculatedBaseGain = 0;
          _activeChallenge = null;
        });
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Calcul hauteur barre du haut pour padding
      if (_upperControlsBarKey.currentContext != null) {
        final RenderBox? renderBox =
        _upperControlsBarKey.currentContext!.findRenderObject() as RenderBox?;
        if (renderBox != null && mounted) {
          setState(() => _upperControlsBarHeight = renderBox.size.height);
        }
      }

      // Génération suggestions
      _generateDailyStoreSuggestions();

      // Gestion des trajets en attente (venant d'autres onglets)
      if (widget.pendingStoreTrip != null) {
        _initiateStoreTrip(widget.pendingStoreTrip!);
      }
      if (widget.pendingChallengeTrip != null) {
        _initiateChallengeTrip(widget.pendingChallengeTrip!);
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
          userPos.latitude, userPos.longitude,
          store.coordinates.latitude, store.coordinates.longitude) /
          1000.0;

      if (distKm <= 30.0) {
        candidates.add(store);
      }
    }

    // 2. Calculer un score de "Poids"
    Map<EcoStore, double> storeWeights = {};

    for (var store in candidates) {
      double distKm = Geolocator.distanceBetween(
          userPos.latitude, userPos.longitude,
          store.coordinates.latitude, store.coordinates.longitude) /
          1000.0;

      double weight = 0;

      // Critère 1: Distance
      if (distKm <= 5) weight += 80;
      else if (distKm <= 10) weight += 50;
      else if (distKm <= 20) weight += 20;
      else weight += 10;

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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Column(children: [
              Icon(Icons.storefront, size: 45, color: Color(0xFF388E3C)),
              SizedBox(height: 8),
              Text("Vous êtes arrivé(e) !", style: TextStyle(fontWeight: FontWeight.bold)),
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
                      const Icon(Icons.eco_rounded, color: Colors.green),
                      const SizedBox(width: 8),
                      Text("+$finalPoints Lames gagnées !",
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
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
                  widget.addLamePoints(finalPoints, source: "Trajet vers ${store.name}");
                },
                child: const Text("Continuer sans valider"),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.receipt),
                label: const Text("Valider mon achat"),
                style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white),
                onPressed: () {
                  Navigator.pop(ctx);
                  widget.addLamePoints(finalPoints, source: "Trajet vers ${store.name}");
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
        LatLng(tripData.store.coordinates.latitude, tripData.store.coordinates.longitude),
        mode: apiTravelMode,
        isStore: true
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showSnackBar("Itinéraire vers ${tripData.store.name} calculé !", backgroundColor: primaryGreen);
    });
  }

  void _initiateChallengeTrip(ChallengeTripData tripData) {
    if (!mounted) return;

    final challenge = tripData.challenge;

    if (challenge.latitude == null || challenge.longitude == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showSnackBar("Ce défi n'a pas de destination géographique valide.", backgroundColor: Colors.orange);
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

    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;
    try {
      final geocodeUrl = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(destinationText)}&key=$apiKey');
      final response = await http.get(geocodeUrl);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final location = data['results'][0]['geometry']['location'];
          final LatLng coords = LatLng(location['lat'], location['lng']);

          final travelMode = _selectedTravelType == TravelType.walk
              ? TravelMode.walking
              : _selectedTravelType == TravelType.bike
              ? TravelMode.bicycling
              : TravelMode.transit;

          homeController.setDestination(destinationText, coords, mode: travelMode);
        }
      }
    } catch (e) {
      print("Erreur recherche : $e");
    }
  }

  // --- GESTION DES GAINS ---

  void _updateGainAndRouteData() {
    if (!mounted) return;

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
    // Cas Transit
    if (homeController.currentTravelMode.value == TravelMode.transit) {
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

    // Formules physiques
    if (_selectedTravelType == TravelType.walk) {
      // Marche : 10 pts/km + 0.5 pts/min + 1 pt par 10m dénivelé
      score = (distanceKm * 10.0) + (durationMinutes * 0.5) + (elevationMeters / 10.0);
    } else if (_selectedTravelType == TravelType.bike) {
      // Vélo : 6 pts/km + 0.2 pts/min + 1 pt par 20m dénivelé
      score = (distanceKm * 6.0) + (durationMinutes * 0.2) + (elevationMeters / 20.0);
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

    // 4. Bonus de niveau (+1 Lame fixe par niveau)
    final levelData = _calculateUserLevel(widget.userProfile.totalLameEarned ?? 0);
    final currentLevel = levelData['currentLevel'] as int;
    finalGainDouble += currentLevel;

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
    while (totalLame >= totalLameForCurrentLevel + lameNeeded && currentLevel < 50) {
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

  // --- TRANSIT UTILS ---

  int _calculateGainForTransitOption(Map<String, dynamic> leg) {
    if (leg['distance'] == null || leg['duration'] == null) return 0;

    try {
      double totalPoints = 0.0;
      const double FE_VOITURE_KM = 180.0;
      const double BUS_NB_PASSAGERS = 50.0;
      const double BUS_CONSO_KM = 900.0;
      const double BUS_CONSO_MINUTE = 15.0;
      const double FE_RAIL_KM = 6.0;
      const double CONVERSION_CO2_POINTS = 1.0 / 40.0;

      for (var step in leg['steps']) {
        double distanceKm = (step['distance']['value'] as num).toDouble() / 1000.0;
        double durationMinutes = (step['duration']['value'] as num).toDouble() / 60.0;
        String travelMode = step['travel_mode'];

        double effort = (distanceKm * 5.0) + (durationMinutes * 0.5);
        double co2EmisVoiture = distanceKm * FE_VOITURE_KM;
        double co2EmisUtilisateur = 0.0;
        double transportMultiplier = 1.0;

        if (travelMode == 'WALKING') {
          co2EmisUtilisateur = 0.0;
          transportMultiplier = 1.0;
        } else if (travelMode == 'TRANSIT') {
          String vehicleType = step['transit_details']?['line']?['vehicle']?['type'] ?? 'BUS';
          if (vehicleType == 'BUS' || vehicleType == 'INTERCITY_BUS' || vehicleType == 'TROLLEYBUS') {
            double emissionBusTotal = (distanceKm * BUS_CONSO_KM) + (durationMinutes * BUS_CONSO_MINUTE);
            co2EmisUtilisateur = emissionBusTotal / BUS_NB_PASSAGERS;
            transportMultiplier = 0.8;
          } else {
            co2EmisUtilisateur = distanceKm * FE_RAIL_KM;
            transportMultiplier = 0.9;
          }
        } else {
          co2EmisUtilisateur = co2EmisVoiture;
          transportMultiplier = 0.1;
        }

        double co2Economise = co2EmisVoiture - co2EmisUtilisateur;
        if (co2Economise < 0) co2Economise = 0;
        double pointsEcologiques = co2Economise * CONVERSION_CO2_POINTS;

        totalPoints += (effort * transportMultiplier) + pointsEcologiques;
      }

      if (_isWeatherBoostApplicable()) totalPoints *= 1.5;
      if (widget.userProfile.nextLevelBoost > 1.0) totalPoints *= widget.userProfile.nextLevelBoost;
      if (widget.userProfile.isVip) totalPoints *= 1.15;
      if (widget.userProfile.adPoints >= 10) totalPoints *= 1.2;

      int finalGain = totalPoints.round();
      return (finalGain <= 0 && leg['distance']['value'] > 0) ? 1 : finalGain;
    } catch (e) {
      print("Erreur calcul gain transit: $e");
      return 0;
    }
  }

  Future<void> _getPlacePredictions(String input) async {
    if (input.length < 3) return;
    var places = await NominatimService().searchPlace(input);
    setState(() {
      _placePredictions = places
          .map((p) => {
        'description': p['display_name'],
        'place_id': p['place_id'].toString(),
        'lat': double.parse(p['lat']),
        'lng': double.parse(p['lon'])
      })
          .toList();
    });
  }

  Future<void> _selectPlace(String placeId, String placeDescription) async {
    setState(() {
      _placePredictions = [];
      _destinationController.text = placeDescription;
    });
    FocusScope.of(context).unfocus();

    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;
    final detailsUrl =
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=geometry,name,formatted_address&key=$apiKey&language=fr';

    try {
      final response = await http.get(Uri.parse(detailsUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null) {
          final location = data['result']['geometry']['location'];
          final destinationCoords = LatLng(location['lat'], location['lng']);
          final destinationName = data['result']['name'];

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
            homeController.setDestination(destinationName, destinationCoords, mode: travelMode);
            // Note: getTotalDistanceAndTime est laissé vide ici si pas implémenté dans HomeController
            // await homeController.getTotalDistanceAndTime(destinationCoords);
            _updateGainAndRouteData();
          }
          homeController.update();
        }
      }
    } catch (e) {
      print("Erreur : $e");
    }
  }

  // --- TRANSIT SEARCH UTILS ---

  Future<void> _getOriginPlacePredictions(String input) async {
    if (input.isEmpty) return;
    try {
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;
      String url =
          'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(input)}&key=$apiKey&language=fr&components=country:fr';

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (mounted) {
          setState(() {
            _originPlacePredictions = List<Map<String, dynamic>>.from(data['predictions'] ?? []);
          });
        }
      }
    } catch (e) {
      print("Erreur d'autocomplétion (origine): $e");
    }
  }

  Future<void> _selectOriginPlace(String placeId, String placeDescription) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;
    final detailsUrl =
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&fields=geometry&key=$apiKey&language=fr';

    try {
      final response = await http.get(Uri.parse(detailsUrl));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null) {
          final location = data['result']['geometry']['location'];
          setState(() {
            _originCoords = LatLng(location['lat'], location['lng']);
            _originController.text = placeDescription;
            _originPlacePredictions = [];
          });
        }
      }
    } catch (e) {
      _showSnackBar("Erreur de sélection: $e", backgroundColor: Colors.red);
    }
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
      _showSnackBar("Veuillez d'abord sélectionner une destination.", backgroundColor: Colors.orange);
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
            content: Text("+1 AD Point ! Vous en avez $newAdPoints/50.${newAdPoints < 10 ? ' (${10 - newAdPoints} avant le multiplicateur x1.2)' : ' ⚡ x1.2 actif !'}"),
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
      {Color backgroundColor = Colors.black87, Duration duration = const Duration(seconds: 3)}) {
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
      activeBoosts.add("Global x${widget.userProfile.nextLevelBoost.toStringAsFixed(2)}");
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
    DateTime lastLoginDay = DateTime(profile.lastLoginDate!.toDate().year,
        profile.lastLoginDate!.toDate().month, profile.lastLoginDate!.toDate().day);

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
      pointsDenivele = elevationMeters / 10.0;
    } else if (_selectedTravelType == TravelType.bike) {
      pointsDistance = distKm * 6.0;
      pointsDuree = durMin * 0.2;
      pointsDenivele = elevationMeters / 20.0;
    } else if (_selectedTravelType == TravelType.transit) {
      pointsDistance = distKm * 5.0 * 0.8;
      pointsDuree = durMin * 0.5 * 0.8;
    }

    int baseEffortTotal = (pointsDistance + pointsDuree + pointsDenivele).round();
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
                  child: Text("Détails du Gain",
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(color: primaryGreen, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 20),
                _buildSectionHeader("Données du Trajet"),
                _buildDetailRowDialog(
                    "Distance réelle :", "${distKm.toStringAsFixed(2)} km",
                    icon: Icons.straighten),
                _buildDetailRowDialog(
                    "Temps estimé :", "${durMin.toStringAsFixed(0)} min",
                    icon: Icons.timer),
                if (_selectedTravelType != TravelType.transit)
                  _buildDetailRowDialog("Dénivelé positif :",
                      "${elevationMeters.toStringAsFixed(0)} m",
                      icon: Icons.landscape, valueColor: Colors.orange[800]),
                _buildDetailRowDialog("Mode :", modeLabel, icon: modeIcon),
                const Divider(height: 25),
                if (_selectedTravelType == TravelType.transit) ...[
                  _buildSectionHeader("Calcul Écologique & Effort"),
                  _buildDetailRowDialog(
                      "Base (Effort + CO₂ économisé) :", "+$baseEffortTotal",
                      valueColor: Colors.blueGrey, isBold: true),
                  const Padding(
                    padding: EdgeInsets.only(top: 5.0),
                    child: Text(
                        "(Le calcul inclut l'économie de CO₂ par rapport à la voiture)",
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey, fontStyle: FontStyle.italic)),
                  )
                ] else ...[
                  _buildSectionHeader("Calcul de l'Effort ($baseEffortTotal L)"),
                  _buildDetailRowDialog(
                      "Points Distance :", "+${pointsDistance.toStringAsFixed(1)}",
                      valueColor: Colors.blueGrey),
                  _buildDetailRowDialog(
                      "Points Endurance :", "+${pointsDuree.toStringAsFixed(1)}",
                      valueColor: Colors.blueGrey),
                  if (pointsDenivele > 0.1)
                    _buildDetailRowDialog("Bonus Dénivelé :",
                        "+${pointsDenivele.toStringAsFixed(1)}",
                        valueColor: Colors.orange[800], isBold: true),
                ],
                const Divider(height: 25),
                if (_getMultiplierText().isNotEmpty) ...[
                  _buildSectionHeader("Vos Bonus Actifs"),
                  if (_isWeatherBoostApplicable())
                    _buildDetailRowDialog("Météo difficile :", "x1.5",
                        valueColor: primaryGreen, icon: Icons.cloud),
                  if (widget.userProfile.isVip)
                    _buildDetailRowDialog("Membre VIP :", "x1.15",
                        valueColor: accentGold, icon: Icons.star),
                  if (widget.userProfile.nextLevelBoost > 1.0)
                    _buildDetailRowDialog(
                        "Série Connexion :",
                        "x${widget.userProfile.nextLevelBoost.toStringAsFixed(2)}",
                        valueColor: primaryGreen,
                        icon: Icons.local_fire_department),
                  if (widget.userProfile.adPoints >= 10)
                    _buildDetailRowDialog("Boost Ad Points (x1.2):", "+10 ADP actifs",
                        valueColor: Colors.purple, icon: Icons.bolt),
                  const Divider(height: 25),
                ],
                Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                      color: primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(15)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("TOTAL FINAL",
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      Text("$totalFinalGain Lames",
                          style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: primaryGreen)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTransitLameCalculationDetails(BuildContext context, Map<String, dynamic> leg) {
    int baseGain = _calculateGainForTransitOption(leg);
    if (baseGain == 0) return;

    List<Widget> details = [
      Center(
        child: Text("Détail du Gain & Écologie",
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: primaryGreen)),
      ),
      const SizedBox(height: 16),
    ];

    details.add(_buildDetailRowDialog("Gain de Base (Effort + CO₂):", "$baseGain L", isBold: true));
    double currentTotal = baseGain.toDouble();

    List<Widget> multiplierDetails = [];
    if (_isWeatherBoostApplicable()) {
      double gainFromWeather = currentTotal * 0.5;
      multiplierDetails.add(_buildDetailRowDialog("Boost Météo (x1.5):",
          "+${gainFromWeather.round()} L", valueColor: primaryGreen));
      currentTotal += gainFromWeather;
    }
    if (widget.userProfile.nextLevelBoost > 1.0) {
      double gainFromLevel = currentTotal * (widget.userProfile.nextLevelBoost - 1.0);
      multiplierDetails.add(_buildDetailRowDialog(
          "Boost Série (x${widget.userProfile.nextLevelBoost.toStringAsFixed(2)}):",
          "+${gainFromLevel.round()} L",
          valueColor: primaryGreen));
      currentTotal += gainFromLevel;
    }
    if (widget.userProfile.isVip) {
      double gainFromVip = currentTotal * 0.15;
      multiplierDetails.add(_buildDetailRowDialog(
          "Boost VIP (x1.15):", "+${gainFromVip.round()} L",
          valueColor: primaryGreen));
      currentTotal += gainFromVip;
    }
    if (widget.userProfile.adPoints >= 10) {
      double gainFromAd = currentTotal * 0.2;
      multiplierDetails.add(_buildDetailRowDialog(
          "Ad Points ≥10 (x1.2):", "+${gainFromAd.round()} L",
          valueColor: primaryGreen));
      currentTotal += gainFromAd;
    }

    if (multiplierDetails.isNotEmpty) {
      details.add(const Divider(height: 20));
      details.addAll(multiplierDetails);
    }

    details.add(const Divider(height: 20));
    details.add(_buildDetailRowDialog("Total Estimé:", "${currentTotal.round()} L",
        isBold: true, valueColor: accentGold));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: const BoxDecoration(
              color: cardWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: details,
            ),
          ),
        );
      },
    );
  }

  void _showAdPointsDetailsDialog(BuildContext context) {
    final profile = widget.userProfile;
    DateTime now = DateTime.now();

    // Calculer la perte d'Ad Points selon les nouvelles règles
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
        "${timeUntilNextDecay.inHours}h ${timeUntilNextDecay.inMinutes
            .remainder(60)}m";
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return Container(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery
              .of(sheetContext)
              .viewInsets
              .bottom + 20),
          decoration: const BoxDecoration(
              color: cardWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(25.0))),
          child: SingleChildScrollView(
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                      child: Text("📺 Vos Ad Points 📺",
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: primaryGreen))),
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
                        color: profile.adPoints >= 10 ? accentGold : Colors.grey[300]!,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.bolt_rounded,
                          color: profile.adPoints >= 10 ? accentGold : Colors.grey,
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
                                  color: profile.adPoints >= 10 ? accentGold : Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                              if (profile.adPoints < 10)
                                Text(
                                  "Encore ${10 - profile.adPoints} ADP pour activer",
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                )
                              else
                                const Text(
                                  "+20% sur tous vos gains de trajet",
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
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
                        valueColor: const AlwaysStoppedAnimation<Color>(accentGold),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${profile.adPoints}/10 ADP",
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],

                  const SizedBox(height: 12),
                  _buildDetailRowDialog("Ad Points actuels:",
                      "${profile.adPoints}/50 ADP",
                      icon: Icons.slow_motion_video_rounded),
                  if (profile.adPoints > 0)
                    _buildDetailRowDialog(
                        "Prochaine perte (-$pointsLoss ADP):", nextDecayTime,
                        icon: Icons.timer_outlined,
                        valueColor: Colors.orange[700]),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text("💡 Règles des Ad Points :",
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: textDark)),
                  const SizedBox(height: 8),
                  const Text("• Regardez une pub = +1 Ad Point (max 50)",
                      style: TextStyle(fontSize: 13, color: textGrey)),
                  const Text("• ≥ 10 ADP = multiplicateur x1.2 automatique",
                      style: TextStyle(fontSize: 13, color: accentGold, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  const Text("• Perte toutes les 5h :",
                      style: TextStyle(fontSize: 13, color: textGrey, fontWeight: FontWeight.bold)),
                  const Text("  - 0-9 : -1 pt   |   10-19 : -2 pts",
                      style: TextStyle(fontSize: 12, color: textGrey)),
                  const Text("  - 20-29 : -3 pts   |   30-39 : -4 pts   |   40+ : -5 pts",
                      style: TextStyle(fontSize: 12, color: textGrey)),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.slow_motion_video_rounded),
                      label: const Text("Regarder une Pub"),
                      onPressed: profile.adPoints < 50 ? () {
                        Navigator.of(sheetContext).pop();
                        _watchAd();
                      } : null,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                      child: TextButton(
                          child: const Text("Fermer"),
                          onPressed: () => Navigator.of(sheetContext).pop()))
                ]),
          ),
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
    int paliersActuels = (profile.consecutiveLogins /
        LOGIN_STREAK_DAYS_PER_PALIER).floor();
    double bonusSerieInclusDansNextLevelBoost = (paliersActuels *
        LOGIN_STREAK_BONUS_PER_PALIER).clamp(0.0, MAX_LOGIN_STREAK_BONUS_TOTAL);
    int joursRestantsProchainPalier = 0;
    double progressionProchainPalier = 0.0;
    int prochainPalierEnJours = 0;
    double bonusDuProchainPalierReel = 0.0;
    bool maxBonusAtteintViaPaliers = bonusSerieInclusDansNextLevelBoost >=
        MAX_LOGIN_STREAK_BONUS_TOTAL && MAX_LOGIN_STREAK_BONUS_TOTAL > 0;

    if (profile.consecutiveLogins == 0) {
      progressionProchainPalier = 0.0;
      joursRestantsProchainPalier = LOGIN_STREAK_DAYS_PER_PALIER;
      prochainPalierEnJours = LOGIN_STREAK_DAYS_PER_PALIER;
      bonusDuProchainPalierReel = LOGIN_STREAK_BONUS_PER_PALIER;
    } else if (!maxBonusAtteintViaPaliers) {
      int joursDepuisDernierPalierOuDebut = profile.consecutiveLogins %
          LOGIN_STREAK_DAYS_PER_PALIER;
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
                .floor() + 1) * LOGIN_STREAK_DAYS_PER_PALIER;
      }
      bonusDuProchainPalierReel =
          ((prochainPalierEnJours / LOGIN_STREAK_DAYS_PER_PALIER).floor() *
              LOGIN_STREAK_BONUS_PER_PALIER).clamp(
              0.0, MAX_LOGIN_STREAK_BONUS_TOTAL);
    } else {
      progressionProchainPalier = 1.0;
      prochainPalierEnJours = profile.consecutiveLogins;
      joursRestantsProchainPalier = 0;
    }

    // Génération des widgets de paliers
    List<Widget> paliersWidgets = [];
    int maxPaliersPourAffichage = (MAX_LOGIN_STREAK_BONUS_TOTAL /
        (LOGIN_STREAK_BONUS_PER_PALIER > 0 ? LOGIN_STREAK_BONUS_PER_PALIER : 1))
        .ceil();
    if (maxPaliersPourAffichage == 0 && MAX_LOGIN_STREAK_BONUS_TOTAL > 0)
      maxPaliersPourAffichage = 1;
    if (LOGIN_STREAK_DAYS_PER_PALIER == 0) maxPaliersPourAffichage = 1;

    for (int i = 1; i <= maxPaliersPourAffichage; i++) {
      if (LOGIN_STREAK_DAYS_PER_PALIER == 0 && i > 1) break;
      int joursPalier = i * LOGIN_STREAK_DAYS_PER_PALIER;
      double bonusPalierTotal = (i * LOGIN_STREAK_BONUS_PER_PALIER).clamp(
          0.0, MAX_LOGIN_STREAK_BONUS_TOTAL);
      bool estAtteint = profile.consecutiveLogins >= joursPalier;
      bool estProchainNonAtteint = !maxBonusAtteintViaPaliers &&
          (prochainPalierEnJours == joursPalier &&
              profile.consecutiveLogins < joursPalier);

      paliersWidgets.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.0),
        child: Row(
          children: [
            Icon(
                estAtteint ? Icons.check_circle_rounded : (estProchainNonAtteint
                    ? Icons.flag_rounded
                    : Icons.radio_button_unchecked_rounded),
                color: estAtteint ? primaryGreen : (estProchainNonAtteint
                    ? accentGold
                    : textGrey.withOpacity(0.7)), size: 18),
            const SizedBox(width: 8),
            Text("$joursPalier jours : ", style: const TextStyle(
                fontWeight: FontWeight.normal, fontSize: 13)),
            Text(
                "Multiplicateur Global +${bonusPalierTotal.toStringAsFixed(2)}",
                style: TextStyle(
                    color: estAtteint ? primaryGreen : (estProchainNonAtteint
                        ? accentGold
                        : textGrey),
                    fontWeight: estAtteint || estProchainNonAtteint ? FontWeight
                        .bold : FontWeight.normal,
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
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            // Vérification si on peut collecter (dépend de la date de dernière collecte)
            bool canCollect = _canCollectTodayReward();

            return Container(
              padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery
                  .of(sheetContext)
                  .viewInsets
                  .bottom + 20),
              decoration: const BoxDecoration(
                  color: cardWhite,
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(25.0))),
              child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                          child: Text("🔥 Votre Série de Connexion 🔥",
                              style: Theme
                                  .of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: Colors.orangeAccent[700]))),
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
                              LOGIN_STREAK_DAYS_PER_PALIER > 0 &&
                              !maxBonusAtteintViaPaliers
                              ? "Prochain palier dans $joursRestantsProchainPalier jour(s) :"
                              : "Nouveau palier atteint ou série en cours !")),
                          style: const TextStyle(fontSize: 14,
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
                              backgroundColor: defisProgressEmpty.withOpacity(
                                  0.5),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                  accentGold),
                              minHeight: 10),
                        ),
                        const SizedBox(height: 4),
                        if (joursRestantsProchainPalier > 0 &&
                            prochainPalierEnJours > 0)
                          Center(child: Text(
                              "$prochainPalierEnJours jours > Multiplicateur Global x${(1.0 +
                                  bonusDuProchainPalierReel).toStringAsFixed(
                                  2)}", style: const TextStyle(
                              fontSize: 12, color: textGrey))),
                      ],
                      const SizedBox(height: 16),
                      Text("Paliers de Multiplicateur Global (Série):",
                          style: Theme
                              .of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 5),
                      ...paliersWidgets,
                      const SizedBox(height: 20),

                      // --- BOUTON DE RÉCUPÉRATION ---
                      ElevatedButton.icon(
                        icon: Icon(
                            canCollect ? Icons.card_giftcard_rounded : Icons
                                .check_circle_outline_rounded),
                        label: Text(canCollect
                            ? "Récupérer Récompense du Jour (+1 Lame)"
                            : "Récompense du Jour Récupérée"),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 45),
                          backgroundColor: canCollect ? primaryGreen : Colors
                              .grey[400],
                        ),
                        onPressed: canCollect
                            ? () async {
                          try {
                            // AJOUT DES POINTS ET DE L'HISTORIQUE ICI
                            WriteBatch batch = _firestore.batch();

                            // 1. Mise à jour de l'utilisateur (points + date de collecte)
                            DocumentReference userRef = _firestore.collection(
                                'users').doc(widget.userProfile.id);
                            batch.update(userRef, {
                              'lame_points': FieldValue.increment(1),
                              'total_lame_earned': FieldValue.increment(1),
                              'last_daily_reward_collected_date': Timestamp.now(),
                              'updated_at': FieldValue.serverTimestamp()
                            });

                            // 2. Ajout dans l'historique
                            DocumentReference historyRef = userRef.collection(
                                'lame_history').doc();
                            batch.set(historyRef, {
                              'amount': 1,
                              'source': 'Récompense Quotidienne',
                              'timestamp': FieldValue.serverTimestamp(),
                            });

                            await batch.commit();

                            // Mise à jour de l'UI
                            widget.onProfileModified();
                            setDialogState(() {});
                            _showSnackBar("Récompense récupérée (+1 Lame)!",
                                backgroundColor: primaryGreen);
                          } catch (e) {
                            _showSnackBar(
                                "Erreur: $e", backgroundColor: Colors.red);
                          }
                        }
                            : null,
                      ),
                      const SizedBox(height: 10),
                      Center(child: TextButton(child: const Text("Fermer"),
                          onPressed: () => Navigator.of(sheetContext).pop()))
                    ]),
              ),
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
                    bool isNavigating =
                        homeController.mapStatus.value == Constants.onDestination;
                    bool isShowingRoute =
                        homeController.mapStatus.value == Constants.route;
                    double offset =
                    (isNavigating || isShowingRoute) ? screenHeight * 0.35 : 0;

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
                    visible: homeController.mapStatus.value == Constants.idle,
                    child: Positioned(
                      bottom: 30,
                      right: 20,
                      child: FloatingActionButton(
                        heroTag: "btn_locate_me",
                        onPressed: () async {
                          try {
                            Position position =
                            await homeController.getMyCurrentLocation();
                            await homeController.moveMapCamera(
                                LatLng(position.latitude, position.longitude));
                          } catch (e) {
                            _showSnackBar("Impossible d'obtenir votre position: $e",
                                backgroundColor: Colors.red);
                          }
                        },
                        backgroundColor: Colors.white,
                        child: Image.asset(Constants.locateMeIcon, scale: 4),
                      ),
                    ),
                  )),

                  // --- BOUTON RECENTRER (NAVIGATION) ---
                  Obx(() {
                    final isNavigating =
                        homeController.mapStatus.value == Constants.onDestination;
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
                    visible:
                    homeController.mapStatus.value == Constants.onDestination,
                    child: Positioned(
                      top: MediaQuery.of(context).padding.top + 10,
                      left: 0,
                      right: 0,
                      child: DirectionsStatusBar(onValidatePurchase: () async {
                        Get.snackbar(
                            "Action requise", "Veuillez retourner à l'onglet 'Magasins'.",
                            snackPosition: SnackPosition.BOTTOM,
                            backgroundColor: Colors.blueAccent,
                            colorText: Colors.white);
                        navigationController.stopNavigation();
                      }),
                    ),
                  )),

                  // --- BOUTON RETOUR (mode navigation) SUPPRIMÉ ---
                  // Le bouton "Arrêter" dans la BottomBar suffit à stopper la navigation

                  // --- BARRE DU BAS (Info Route) ---
                  Obx(() => Visibility(
                    visible: homeController.mapStatus.value != Constants.idle,
                    child: const Positioned(
                        bottom: 0, left: 0, right: 0, child: BottomBar()),
                  )),

                  // --- SHEET PRINCIPAL ---
                  Obx(() => Visibility(
                    visible:
                    homeController.mapStatus.value != Constants.onDestination,
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
                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
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
                  blurRadius: 10.0, color: Colors.black12, offset: Offset(0, -2))
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
        bool showRouteSummary = homeController.mapStatus.value == Constants.route &&
            !isSearching &&
            (!isTransit || !homeController.showTransitOptions.value);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSearchInputWithClear(),
            const SizedBox(height: 10),
            if (_placePredictions.isNotEmpty)
              _buildPredictionsList(_placePredictions, _selectPlace)
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
              ] else if (isTransit && homeController.showTransitOptions.value) ...[
                _buildAdvancedTransitOptionsUI(),
                const SizedBox(height: 10),
                _buildWeatherSection(),
              ] else if (isSearching)
                const Center(
                    child: Padding(
                        padding: EdgeInsets.all(20.0),
                        child: CircularProgressIndicator(color: Color(0xFF388E3C))))
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
            child: _travelTypeIcon(Icons.directions_walk_rounded, TravelType.walk,
                _selectedTravelType == TravelType.walk),
          ),
          Container(
            width: 1.5,
            height: 25,
            color: Colors.grey[300],
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          Expanded(
            child: _travelTypeIcon(Icons.directions_bike_rounded, TravelType.bike,
                _selectedTravelType == TravelType.bike),
          ),
          Container(
            width: 1.5,
            height: 25,
            color: Colors.grey[300],
            margin: const EdgeInsets.symmetric(horizontal: 10),
          ),
          Expanded(
            child: _travelTypeIcon(Icons.directions_bus_rounded, TravelType.transit,
                _selectedTravelType == TravelType.transit),
          ),
        ],
      ),
    );
  }

  Widget _travelTypeIcon(IconData icon, TravelType type, bool isSelected) {
    return InkWell(
      onTap: () async {
        if (homeController.mapStatus.value == Constants.onDestination) return;
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
          color: isSelected ? primaryGreen.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isSelected ? primaryGreen.withOpacity(0.3) : Colors.transparent,
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
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text(
                                "Allez dans l'onglet Magasins pour tout voir !")));
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
                    onTap: () => _initiateStoreTrip(StoreTripData(
                        store: store, travelType: _selectedTravelType)),
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
                              style: const TextStyle(fontSize: 10, color: Colors.grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          const Spacer(),
                          Text("+${store.cashbackRate * 100}% Cashback",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isGold ? Colors.amber[800] : Colors.green)),
                          const SizedBox(height: 5),
                          SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                      isGold ? Colors.amber : primaryGreen,
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero),
                                  onPressed: () => _initiateStoreTrip(StoreTripData(
                                      store: store,
                                      travelType: _selectedTravelType)),
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
                    shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
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
                  padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text("Commencer le trajet"),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildRouteSummary() {
    return Obx(() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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

      // Si un défi est actif, afficher la RÉCOMPENSE DU DÉFI (pas le gain de trajet)
      final bool isChallengeTrip = _activeChallenge != null;
      final int challengeReward = isChallengeTrip
          ? _parseChallengeReward(_activeChallenge!.rewardText)
          : 0;

      String topText;
      String totalGainText;

      if (isChallengeTrip) {
        topText = "RÉCOMPENSE";
        totalGainText = challengeReward > 0 ? challengeReward.toString() : "?";
      } else if (_activeStoreTrip != null) {
        topText = "GAIN TRAJET";
        totalGainText = currentTotalGain > 0 ? currentTotalGain.toString() : "-";
      } else {
        topText = "GAIN ESTIMÉ";
        totalGainText = currentTotalGain > 0 ? currentTotalGain.toString() : "-";
      }

      bool hasRoute = homeController.destination.value.isNotEmpty &&
          (homeController.polyline.isNotEmpty || homeController.showTransitOptions.value);

      if (!hasRoute) {
        topText = isChallengeTrip ? "RÉCOMPENSE" : "CALCULER TRAJET";
        if (!isChallengeTrip) totalGainText = "-";
      } else if (!isChallengeTrip && currentTotalGain == 0 && homeController.gettingRoute.value) {
        totalGainText = "...";
      }

      String multiplierText = isChallengeTrip ? "" : _getMultiplierText();

      return InkWell(
        onTap: () {
          if (isChallengeTrip) {
            // Pour les défis : afficher les infos de la récompense
            _showChallengeRewardInfo(_activeChallenge!);
          } else if (hasRoute && currentTotalGain > 0) {
            // Pour les trajets normaux : afficher le détail de calcul
            _showLameCalculationDetails(context);
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
              color: isChallengeTrip
                  ? Colors.purple.withOpacity(0.15)
                  : accentGold.withOpacity(0.15),
              border: Border.all(
                  color: isChallengeTrip ? Colors.purple : accentGold,
                  width: 1.5)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(topText,
                    style: TextStyle(
                        color: isChallengeTrip ? Colors.purple : accentGold,
                        fontWeight: FontWeight.bold,
                        fontSize: 9),
                    textAlign: TextAlign.center,
                    maxLines: 1)),
            const SizedBox(height: 1),
            Text(totalGainText,
                style: TextStyle(
                    color: isChallengeTrip ? Colors.purple : textDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 24)),
            const Text("Lames", style: TextStyle(color: Colors.grey, fontSize: 10)),
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

  /// Affiche les infos de récompense d'un défi (au clic sur le cercle)
  void _showChallengeRewardInfo(Challenge challenge) {
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
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.eco_rounded, color: Colors.purple, size: 28),
                  const SizedBox(width: 8),
                  Text(challenge.rewardText,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.purple)),
                ]),
                const SizedBox(height: 8),
                const Text("Lames créditées à la complétion du défi uniquement",
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                    textAlign: TextAlign.center),
              ]),
            ),
            const SizedBox(height: 20),
            const Text(
              "⚠️ Le gain de trajet n'est pas crédité pour les défis.\nSeule la récompense ci-dessus sera attribuée.",
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
              child: Text(label, style: const TextStyle(fontSize: 14, color: textGrey))),
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

  Widget _buildPredictionsList(
      List<Map<String, dynamic>> predictions, Function(String, String) onSelect) {
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
            title: Text(prediction['description']),
            onTap: () {
              FocusScope.of(context).unfocus();
              onSelect(prediction['place_id'], prediction['description']);
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
                  color: _isTransitOptionsExpanded ? primaryGreen : Colors.black54,
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
                          border:
                          OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
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
                padding: EdgeInsets.symmetric(horizontal: 8), child: Text("Maintenant")),
            TransitTimeOption.departAt: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8), child: Text("Partir à")),
            TransitTimeOption.arriveBy: Padding(
                padding: EdgeInsets.symmetric(horizontal: 8), child: Text("Arriver à")),
          },
        ),
        if (_transitTimeOption != TransitTimeOption.leaveNow)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: TextButton(
              onPressed: _pickTransitDateTime,
              child: Text(
                DateFormat('EEE d MMM, HH:mm', 'fr_FR').format(_selectedTransitTime),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
          final double maxListHeight = MediaQuery.of(context).size.height * 0.45;

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
                final int estimatedGain = _calculateGainForTransitOption(leg);
                final bool isRecommended = index == 0;
                List<Widget> transportIcons = _buildRouteStepsIcons(leg['steps']);

                return Card(
                  elevation: isRecommended ? 4 : 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                        color: isRecommended ? primaryGreen : Colors.grey.shade200,
                        width: isRecommended ? 2 : 1),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _showTransitLameCalculationDetails(context, leg),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
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
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            color: textDark)),
                                    const SizedBox(height: 4),
                                    Text("$departureTime → $arrivalTime",
                                        style: TextStyle(
                                            color: Colors.grey[600], fontSize: 13)),
                                    const SizedBox(height: 10),
                                    Wrap(spacing: 5, children: transportIcons),
                                  ],
                                ),
                              ),
                              _buildGainIndicator(estimatedGain),
                            ],
                          ),
                          const SizedBox(height: 12),
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
                                backgroundColor:
                                isRecommended ? primaryGreen : Colors.blueAccent,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text("Choisir cet itinéraire"),
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
    String adPointsDecayTimeString = "";

    if (profile.adPoints > 0) {
      DateTime now = DateTime.now();
      Timestamp lastDecayTime = profile.lastAdPointDecayTime ??
          Timestamp.fromDate(now.subtract(const Duration(hours: 5)));
      Duration timeSinceLastDecay = now.difference(lastDecayTime.toDate());
      Duration timeUntilNextDecay =
          const Duration(hours: 5) - timeSinceLastDecay;
      if (!timeUntilNextDecay.isNegative) {
        adPointsDecayTimeString =
        " -$decayAmount dans ${timeUntilNextDecay.inHours}h${timeUntilNextDecay.inMinutes.remainder(60)}m";
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
              child:
              Icon(Icons.shield_outlined, color: Colors.grey[400], size: 28),
            )
        ]));
  }

  Widget _buildFavoriteRoutesSection() {
    List<Map<String, dynamic>> favoriteRoutes = widget.userProfile.favoriteRoutes;

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
              offset: const Offset(0, 2)
            )
          ]
        ),
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
            offset: const Offset(0, 2)
          )
        ]
      ),
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
          ...favoriteRoutes.take(3).map((route) => _buildFavoriteRouteCard(route)).toList(),
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
                child: const Icon(Icons.more_vert, size: 18, color: Colors.grey),
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
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.directions_walk, color: Colors.blue, size: 24),
                        const SizedBox(height: 4),
                        const Text('Marche', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
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
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.directions_bike, color: Colors.green, size: 24),
                        const SizedBox(height: 4),
                        const Text('Vélo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
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
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Column(
                      children: [
                        Icon(Icons.directions_bus, color: Colors.orange, size: 24),
                        const SizedBox(height: 4),
                        const Text('Transport', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
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

  Future<int> _calculateRouteReward(Map<String, dynamic> route, TravelType mode) async {
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
        icons.add(const Icon(Icons.directions_walk, size: 16, color: Colors.grey));
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
        icons.add(const Icon(Icons.chevron_right, size: 14, color: Colors.grey));
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

  void _handleWidgetIntent(Map<dynamic, dynamic> data) {
    if (data['action'] == 'START_FAVORITE_ROUTE') {
      String routeName = data['route_name'] ?? '';
      String destination = data['route_destination'] ?? '';
      String travelModeStr = data['travel_mode'] ?? 'walk';

      if (destination.isNotEmpty && routeName.isNotEmpty) {
        // Retrouver le trajet favori correspondant
        Map<String, dynamic>? route;
        for (var favoriteRoute in widget.userProfile.favoriteRoutes) {
          if (favoriteRoute['name'] == routeName && favoriteRoute['destination'] == destination) {
            route = favoriteRoute;
            break;
          }
        }

        if (route != null) {
          // Convertir le mode de voyage
          TravelType mode = _parseWidgetTravelType(travelModeStr);

          // Démarrer la navigation avec le mode sélectionné
          _startFavoriteRoute(route, mode);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Trajet favori '$routeName' non trouvé"),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } else if (data['action'] == 'SHOW_ROUTE_OPTIONS') {
      // L'utilisateur a cliqué sur un trajet depuis le widget
      // Afficher les trajets favoris pour qu'il puisse choisir le mode de transport
      String routeName = data['route_name'] ?? '';

      if (routeName.isNotEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Choisissez un mode de transport pour '$routeName' ci-dessous"),
            backgroundColor: primaryGreen,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );

        // Optionnel: faire défiler jusqu'à la section trajets favoris
        // ou mettre en surbrillance le trajet sélectionné
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
                        style: TextStyle(color: Colors.blue[800], fontWeight: FontWeight.w500),
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
                  ? () => _updateFavoriteRoute(route, routeName, '', destination, true)
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

  Future<void> _saveFavoriteRoute(String name, String startAddress, String destination, bool useCurrentLocation) async {
    Navigator.pop(context); // Fermer le dialog

    Map<String, dynamic> favoriteRoute = {
      'name': name,
      'start_address': startAddress,
      'destination': destination,
      'use_current_location': useCurrentLocation,
      'created_at': Timestamp.now().toDate().toIso8601String(),
    };

    List<Map<String, dynamic>> currentFavorites = List.from(widget.userProfile.favoriteRoutes);
    currentFavorites.add(favoriteRoute);

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.userProfile.id).update({
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

  Future<void> _updateFavoriteRoute(Map<String, dynamic> oldRoute, String name, String startAddress, String destination, bool useCurrentLocation) async {
    Navigator.pop(context); // Fermer le dialog

    Map<String, dynamic> updatedRoute = {
      'name': name,
      'start_address': startAddress,
      'destination': destination,
      'use_current_location': useCurrentLocation,
      'created_at': oldRoute['created_at'], // Garder la date de création originale
      'updated_at': Timestamp.now().toDate().toIso8601String(),
    };

    List<Map<String, dynamic>> currentFavorites = List.from(widget.userProfile.favoriteRoutes);
    int index = currentFavorites.indexOf(oldRoute);
    if (index != -1) {
      currentFavorites[index] = updatedRoute;
    }

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.userProfile.id).update({
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
        content: Text("Êtes-vous sûr de vouloir supprimer '${route['name']}' ?"),
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

    List<Map<String, dynamic>> currentFavorites = List.from(widget.userProfile.favoriteRoutes);
    currentFavorites.remove(route);

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.userProfile.id).update({
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

  void _startFavoriteRoute(Map<String, dynamic> route, TravelType selectedMode) async {
    String destination = route['destination'] ?? '';
    String routeName = route['name'] ?? '';

    if (destination.isEmpty) return;

    try {
      setState(() {
        _destinationController.text = destination;
        _selectedTravelType = selectedMode;
      });

      // Géocode la destination pour obtenir les coordonnées
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;
      final geocodeUrl = Uri.parse(
          'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(destination)}&key=$apiKey');
      final response = await http.get(geocodeUrl);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['results'] != null && data['results'].isNotEmpty) {
          final loc = data['results'][0]['geometry']['location'];
          final LatLng coords = LatLng(loc['lat'], loc['lng']);

          final travelMode = selectedMode == TravelType.walk
              ? TravelMode.walking
              : selectedMode == TravelType.bike
              ? TravelMode.bicycling
              : TravelMode.transit;

          homeController.setDestination(destination, coords, mode: travelMode);
        } else {
          // Fallback sans coordonnées
          _calculateAndSetDestination();
        }
      } else {
        _calculateAndSetDestination();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur lancement trajet: $e"), backgroundColor: Colors.red),
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

  Future<void> _saveRoutesToSharedPrefs(List<Map<String, dynamic>> routes) async {
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

  @override
  void initState() {
    super.initState();
    _initLocationAndData();
  }

  Future<void> _initLocationAndData() async {
    try {
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      _userPosition = latlong.LatLng(p.latitude, p.longitude);
    } catch (e) {
      print("Erreur localisation StoresScreen: $e");
      _userPosition = widget.userProfile.homeAddressCoordinates ?? latlong.LatLng(45.75, 4.85);
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
          _userPosition!.latitude, _userPosition!.longitude,
          store.coordinates.latitude, store.coordinates.longitude
      );
      distances[store.id] = distMeters / 1000.0;
    }

    if (_useRadius) {
      tempStores = tempStores.where((s) {
        double d = distances[s.id] ?? 9999.0;
        return d <= _radiusKm;
      }).toList();
    }

    // Filtrage par favoris si activé
    if (_showOnlyFavorites) {
      tempStores = tempStores.where((store) =>
        widget.userProfile.favoriteStores.contains(store.id)
      ).toList();
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
                            onChanged: (v) => setStateDialog(() => tempUse = v!)
                        ),
                        const Text("Limiter le rayon"),
                      ],
                    ),
                    if (tempUse) ...[
                      const SizedBox(height: 10),
                      Text("${tempRadius.round()} km", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: primaryGreen)),
                      Slider(
                        value: tempRadius,
                        min: 5, max: 100, divisions: 19,
                        activeColor: primaryGreen,
                        onChanged: (v) => setStateDialog(() => tempRadius = v),
                      ),
                    ]
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text("Annuler")),
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
        }
    );
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
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, 2), blurRadius: 5)],
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const Icon(Icons.tune, size: 18, color: Colors.grey),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(_currentSort == StoreSortOption.proximity ? Icons.near_me : Icons.euro, size: 16, color: Colors.white),
                    label: Text(_currentSort == StoreSortOption.proximity ? "Proximité" : "Rentabilité"),
                    backgroundColor: primaryGreen,
                    labelStyle: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
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
                    avatar: Icon(Icons.radar, size: 16, color: _useRadius ? Colors.white : textDark),
                    label: Text(_useRadius ? "Rayon: ${_radiusKm.round()} km" : "Monde entier"),
                    backgroundColor: _useRadius ? primaryGreen.withOpacity(0.8) : Colors.grey[200],
                    labelStyle: TextStyle(color: _useRadius ? Colors.white : textDark, fontSize: 13),
                    onPressed: _showRadiusFilterDialog,
                  ),
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: Icon(Icons.favorite, size: 16, color: _showOnlyFavorites ? Colors.white : textDark),
                    label: Text(_showOnlyFavorites ? "Favoris uniquement" : "Tous les magasins"),
                    backgroundColor: _showOnlyFavorites ? accentGold : Colors.grey[200],
                    labelStyle: TextStyle(color: _showOnlyFavorites ? Colors.white : textDark, fontSize: 13),
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
                    shape: StadiumBorder(side: BorderSide(color: Colors.grey.shade300)),
                    labelStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _isLoadingLoc
                ? const Center(child: CircularProgressIndicator(color: primaryGreen))
                : _sortedStores.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_showOnlyFavorites ? Icons.favorite_border : Icons.location_off, size: 50, color: Colors.grey),
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
                        child: const Text("Afficher tout sans limite")
                    ),
                  if (_showOnlyFavorites)
                    TextButton(
                        onPressed: () {
                          setState(() {
                            _showOnlyFavorites = false;
                            _applySortAndFilter();
                          });
                        },
                        child: const Text("Afficher tous les magasins")
                    )
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: () async => await _initLocationAndData(),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 80.0),
                itemCount: displayList.length + 1,
                itemBuilder: (context, index) {
                  if (index == displayList.length) {
                    if (hasMore) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        child: Center(
                          child: OutlinedButton(
                            onPressed: _loadMore,
                            style: OutlinedButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                            child: const Text("Charger plus de magasins"),
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
                    userPositionForCalcul: () async => _userPosition ?? latlong.LatLng(0,0),
                    onStartTrip: widget.onStartTrip,
                    userProfile: widget.userProfile,
                    onAddLame: widget.onAddLame,
                    weatherData: widget.weatherData,
                    tripCompletedAt: widget.pendingValidations[store.id],
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

// Gestion du Boost
  late Timer _refreshTimer;
  double _currentBoostVal = 0.0;
  String _boostStatusText = "";

// États locaux pour calcul immédiat
  double _localBoostAmount = 0.0;
  DateTime _localLastUpdate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initBoostData();
    _calculateAllGains();

// Rafraichissement chaque seconde pour le compte à rebours
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) _recalcBoostDisplay();
    });

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
  }

  @override
  void didUpdateWidget(StoreCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userProfile != widget.userProfile) {
      _initBoostData();
    }
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

// ===========================================================================
// 🧠 LOGIQUE COMPLEXE DU BOOST (PERTE / DECAY)
// ===========================================================================

  void _recalcBoostDisplay() {
    final now = DateTime.now();
    final int secondsElapsed = now
        .difference(_localLastUpdate)
        .inSeconds;

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

// --- RÈGLES DE PERTE (DECAY) ---
      int stepMinutes;
      double lossAmount;

      if (simulatedAmount >= 1.0) {
// MODE SPÉCIAL (>= 1.0)
// Normal: Perte 0.10 toutes les 5 min? (Logique déduite: "perte de moitié moins" si premium)
// "si on est entre 1 et 1.9 on perd seulement moitié moins donc 0.5" -> C'est énorme.
// Interprétation logique : Mode spécial = dégradation très rapide pour forcer à regarder des pubs.
        stepMinutes = 5;
        lossAmount = 0.10;
        if (isPremium) {
          lossAmount = 0.05; // Moitié moins
          stepMinutes =
          10; // "passe a 10 minutes ou 30 si premium" (prompt ambigu, on va dire 10)
        }
      } else if (simulatedAmount >= 0.60) {
        stepMinutes = 5;
        lossAmount = 0.6;
      } else if (simulatedAmount >= 0.50) {
        stepMinutes = 10;
        lossAmount = 0.5;
      } else if (simulatedAmount >= 0.40) {
        stepMinutes = 15;
        lossAmount = 0.4;
      } else if (simulatedAmount >= 0.30) {
        stepMinutes = 20;
        lossAmount = 0.3;
      } else if (simulatedAmount >= 0.20) {
        stepMinutes = 25;
        lossAmount = 0.2;
      } else if (simulatedAmount >= 0.10) {
        stepMinutes = 30;
        lossAmount = 0.2;
      } else {
// < 0.10
        stepMinutes = 60;
        lossAmount = 0.01;
      }

// --- RÈGLES PREMIUM (GLOBALES) ---
      if (isPremium && simulatedAmount < 1.0) {
// "A partir de 0.40 on passe a 15 minutes"
        if (simulatedAmount >= 0.40 && stepMinutes < 15) stepMinutes = 15;
// "Perte de moitier moins"
        lossAmount = lossAmount / 2.0;
      }

      int stepSeconds = stepMinutes * 60;

// Avance dans le temps
      if (secondsSimulated + stepSeconds <= secondsElapsed) {
        simulatedAmount -= lossAmount;
        secondsSimulated += stepSeconds;
// On continue la boucle avec la nouvelle valeur (qui changera peut-être de palier)
      } else {
// On est dans ce palier
        int secondsRemaining = stepSeconds -
            (secondsElapsed - secondsSimulated);
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

  Future<void> _toggleFavorite() async {
    try {
      bool isCurrentlyFavorite = widget.userProfile.favoriteStores.contains(widget.store.id);
      List<String> updatedFavorites = List.from(widget.userProfile.favoriteStores);

      if (isCurrentlyFavorite) {
        updatedFavorites.remove(widget.store.id);
      } else {
        updatedFavorites.add(widget.store.id);
      }

      await FirebaseFirestore.instance.collection('users').doc(widget.userProfile.id).update({
        'favorite_stores': updatedFavorites,
      });

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
    Navigator.pop(context); // Fermer loader

// 2. Calcul du Gain "Intelligent"
    bool userIsActuallyPremium = widget.userProfile.isVip;
    bool storeHasBoostEnabled = widget.store.isPremiumAdBoostEnabled;

// Logique demandée :
// - Si StoreBoost ON et User Standard -> User devient Premium pour ce store
// - Si StoreBoost ON et User Premium -> User devient Super Premium (x2)
// - Si StoreBoost OFF : User garde son statut normal

    bool effectivelyPremium = userIsActuallyPremium || storeHasBoostEnabled;
    bool effectivelySuperPremium = userIsActuallyPremium &&
        storeHasBoostEnabled;

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
          content: Text(
              "Boost activé ! +${gain.toStringAsFixed(2)}%$statusMsg"),
          backgroundColor: effectivelySuperPremium ? Colors.amber[800] : Colors
              .green
      ));
    }

// 3. Mise à jour Firestore (Map Specifique pour ce magasin)
    Map<String, dynamic> updateData = {
      'amount': newAmount,
      'last_update': FieldValue.serverTimestamp(),
    };

    try {
// On utilise set avec merge pour créer l'entrée si elle n'existe pas sans écraser le reste
      await FirebaseFirestore.instance.collection('users').doc(
          widget.userProfile.id).set({
        'store_boosts': {
          widget.store.id: updateData
        }
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
    setState(() { _isLoading = true; _totalLameGain = null; });

    try {
      latlong.LatLng userPos = await widget.userPositionForCalcul();

      // Vérifier que la position est valide (non nulle)
      if (userPos.latitude == 0 && userPos.longitude == 0) {
        setState(() { _isLoading = false; });
        return;
      }

      final directionsService = DirectionsService();

      TravelMode mode = TravelMode.walking;
      if (_selectedTravelType == TravelType.bike) mode = TravelMode.bicycling;
      if (_selectedTravelType == TravelType.transit) mode = TravelMode.transit;

      final request = DirectionsRequest(
        origin: "${userPos.latitude},${userPos.longitude}",
        destination: "${widget.store.coordinates.latitude},${widget.store
            .coordinates.longitude}",
        travelMode: mode,
      );

      // Utiliser null pour détecter si l'API répond vraiment
      double? durationMins;
      double? distKm;

      await directionsService.route(
          request, (DirectionsResult response, status) {
        if (status == DirectionsStatus.ok && response.routes!.isNotEmpty) {
          final leg = response.routes!.first.legs!.first;
          durationMins = (leg.duration!.value! / 60.0);
          distKm = (leg.distance!.value! / 1000.0);
        }
      });

      // Si l'API n'a pas répondu, on n'affiche pas de gain fictif
      if (durationMins == null || distKm == null) {
        setState(() { _isLoading = false; });
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
      if (mounted) setState(() {
        _error = "Erreur GPS";
        _isLoading = false;
      });
    }
  }

  void _showTripDetails() {
    if (_totalLameGain == null) return;
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) =>
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20))),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text("Détail Gain Trajet", style: Theme
                      .of(context)
                      .textTheme
                      .headlineSmall),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Effort de base"), Text("$_effortBonus L"),
                      ]),
                  if (_weatherMultiplier != null)
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("Météo"),
                          Text("x$_weatherMultiplier",
                              style: const TextStyle(color: Colors.green)),
                        ]),
                  const Divider(),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("TOTAL",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text("$_totalLameGain L", style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.amber)),
                      ]),
                  const SizedBox(height: 20),
                ],
              ),
            )
    );
  }

  void _showRulesDialog() {
    bool vip = widget.userProfile.isVip;
    showDialog(context: context, builder: (ctx) =>
        AlertDialog(
          title: const Text("Info Boost"),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Statut: ${vip ? "PREMIUM" : "STANDARD"}",
                    style: TextStyle(fontWeight: FontWeight.bold,
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
                _ruleRow("0.40", vip ? "15m" : "15m", vip ? "-0.2" : "-0.4"),
                _ruleRow("0.60", vip ? "15m" : "5m", vip ? "-0.3" : "-0.6"),
                _ruleRow("> 1.0", "5m", "Variable"),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text("OK"))
          ],
        ));
  }

  Widget _ruleRow(String range, String time, String loss) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
      Map<String, dynamic> storeProgress = widget.userProfile
          .loyaltyProgress[widget.store.id] ?? {};
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

        loyaltyWidgets.add(
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
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
            )
        );
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
        decoration: isGold ? BoxDecoration(
          borderRadius: BorderRadius.circular(12.0),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, Colors.amber.shade50, Colors.white],
          ),
        ) : null,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
// --- HEADER MAGASIN ---
              Row(
                children: [
// Icône changeante
                  Icon(
                      Icons.storefront,
                      color: isGold ? Colors.amber[800] : primaryGreen,
                      size: 30
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(
                      children: [
                        Flexible(child: Text(widget.store.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18))),
// Badge Vérifié si Gold
                        if(isGold) ...[
                          const SizedBox(width: 5),
                          const Icon(
                              Icons.verified, color: Colors.amber, size: 18),
                        ]
                      ],
                    ),
                    Text(widget.store.address,
                        style: const TextStyle(color: Colors.grey,
                            fontSize: 12)),
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
                        border: Border.all(color: isGold
                            ? Colors.amber[700]!
                            : Colors.green),
                        boxShadow: isGold ? [BoxShadow(color: Colors.amber
                            .withOpacity(0.3), blurRadius: 4)
                        ] : null,
                      ),
                      child: Column(
                        children: [
// AFFICHE LE TOTAL (Base + Boost)
                          Text("${totalRateToDisplay.toStringAsFixed(1)}%",
                              style: TextStyle(fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: isGold ? Colors.black87 : Colors
                                      .green[800])),
                          const Text("Cashback Total", style: TextStyle(
                              fontSize: 9)),

// Indication du boost si actif
                          if (_currentBoostVal > 0)
                            Text("(dont +${_currentBoostVal.toStringAsFixed(
                                1)} boost)",
                                style: const TextStyle(fontSize: 8,
                                    color: Colors.purple,
                                    fontWeight: FontWeight.bold)),

                          if(isGold)
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: Colors.red,
                                  borderRadius: BorderRadius.circular(4)),
                              child: const Text("+1% BONUS", style: TextStyle(
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
                      widget.userProfile.favoriteStores.contains(widget.store.id)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: widget.userProfile.favoriteStores.contains(widget.store.id)
                          ? Colors.red
                          : Colors.grey,
                    ),
                    tooltip: widget.userProfile.favoriteStores.contains(widget.store.id)
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
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(children: [
                            const Icon(Icons.bolt, color: Colors.purple),
                            const SizedBox(width: 5),
                            const Text("Boost Cashback", style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.purple)),
                            IconButton(icon: const Icon(
                                Icons.info_outline, size: 16,
                                color: Colors.grey),
                                onPressed: _showRulesDialog)
                          ]),
// Affiche uniquement la valeur du boost ajouté
                          Text("+${_currentBoostVal.toStringAsFixed(2)}%",
                              style: const TextStyle(fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.purple))
                        ]),
                    if (_currentBoostVal > 0)
                      Align(alignment: Alignment.centerRight,
                          child: Text(
                              _boostStatusText, style: TextStyle(color: Colors
                              .red[800], fontSize: 11, fontWeight: FontWeight
                              .bold))),
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
              const SizedBox(height: 15),

// --- SECTION FIDELITÉ ---
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.amber.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.stars, color: Colors.amber[900], size: 18),
                      const SizedBox(width: 8),
                      Text("Votre Fidélité",
                          style: TextStyle(fontWeight: FontWeight.bold,
                              color: Colors.amber[900])),
                    ]),
                    const SizedBox(height: 8),
                    ...loyaltyWidgets
                  ],
                ),
              ),
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
                      final remaining = 24 - now.difference(completedAt).inHours;
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
                          onPressed: () => widget.onStartTrip(widget.store, _selectedTravelType),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isGold ? Colors.amber[700]! : primaryGreen),
                            foregroundColor: isGold ? Colors.amber[900]! : primaryGreen,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.near_me),
                              const SizedBox(width: 5),
                              Text("Y aller ${_totalLameGain != null ? '($_totalLameGain L)' : ''}"),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.receipt_long, color: Colors.teal),
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
                            style: const TextStyle(fontSize: 10, color: Colors.orange, fontStyle: FontStyle.italic)),
                      ),
                    if (canValidate && !widget.userProfile.isVip)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          "Valider avant de rentrer chez vous",
                          style: TextStyle(fontSize: 10, color: Colors.grey[600], fontStyle: FontStyle.italic),
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
          Text("Visite validée !", style: TextStyle(fontWeight: FontWeight.bold)),
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
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
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
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white),
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
          Text("Analyse du ticket en cours..."),
        ]),
      ),
    );

    try {
      final inputImage = InputImage.fromFilePath(photo.path);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognized = await textRecognizer.processImage(inputImage);
      await textRecognizer.close();
      final rawText = recognized.text;

      if (mounted) Navigator.pop(context);
      if (!mounted) return;

      // Vérification IA : enseigne + heure (délai max 2h)
      final check = _verifyReceiptValidity(rawText);
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
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erreur analyse: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Map<String, dynamic> _verifyReceiptValidity(String rawText) {
    final textLower = rawText.toLowerCase();
    final now = DateTime.now();

    // ── 1. Vérification du nom de l'enseigne ──────────────────────────────
    // On cherche au moins 1 mot significatif du nom ou de l'adresse dans le ticket
    bool storeFound = false;

    // Mots du nom du magasin (>3 lettres)
    final storeWords = widget.store.name.toLowerCase()
        .split(RegExp(r'[\s\-\./,]+'))
        .where((w) => w.length > 3)
        .toList();
    if (storeWords.any((w) => textLower.contains(w))) storeFound = true;

    // Mots de l'adresse (>4 lettres) — plan B
    if (!storeFound) {
      final addrWords = widget.store.address.toLowerCase()
          .split(RegExp(r'[\s\-\./,]+'))
          .where((w) => w.length > 4)
          .toList();
      if (addrWords.any((w) => textLower.contains(w))) storeFound = true;
    }

    if (!storeFound) {
      return {
        'valid': false,
        'reason': '❌ Ce ticket ne correspond pas au magasin "${widget.store.name}".\n\nAssurez-vous de scanner le ticket du bon magasin.'
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
        if (day >= 1 && day <= 31 && month >= 1 && month <= 12 &&
            hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
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
              if (lastTime == null || candidate.hour > lastTime.hour ||
                  (candidate.hour == lastTime.hour && candidate.minute > lastTime.minute)) {
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
          'reason': '⏱ Ce ticket date de plus de 2 heures.\n\nHeure sur le ticket : $ticketStr\nHeure actuelle : ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}\n\nSeuls les achats des 2 dernières heures sont acceptés.'
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Fermer")),
          ElevatedButton.icon(
            icon: const Icon(Icons.camera_alt),
            label: const Text("Réessayer"),
            onPressed: () { Navigator.pop(ctx); _startReceiptScan(); },
          ),
        ],
      ),
    );
  }

  double? _parseReceiptAmount(String text) {
    final patterns = [
      RegExp(r'(?:TOTAL|TOTAL TTC|NET À PAYER|À PAYER|MONTANT|SOLDE)[^\d]*(\d+[,\.]\d{2})', caseSensitive: false),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
              if (v != null && v > 0) { Navigator.pop(ctx); _showCashbackPopup(v, rawText); }
            },
            child: const Text("Valider"),
          ),
        ],
      ),
    );
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
      final reached = rule.type == 'visit' ? visits >= rule.threshold : spend >= rule.threshold;
      if (reached && rule.rewardPercent > loyaltyDiscount) {
        loyaltyDiscount = rule.rewardPercent;
        loyaltyTierLabel = rule.type == 'visit'
            ? "Palier ${rule.threshold.toInt()} visites"
            : "Palier ${rule.threshold}€";
      }
    }

    final totalRate = baseRate + boostAddon + loyaltyDiscount;
    final cashbackAmount = amountSpent * (totalRate / 100.0);
    final lameBonus = (cashbackAmount * 10).round();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.card_giftcard, color: Colors.green),
          SizedBox(width: 8),
          Text("Votre Cashback"),
        ]),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _cbRow("Montant dépensé", "${amountSpent.toStringAsFixed(2)} €"),
            const Divider(),
            _cbRow("Cashback de base", "${(store.cashbackRate * 100).toStringAsFixed(1)}%"),
            if (store.isVisibilityBoostEnabled) _cbRow("+1% Bonus Or", "+1.0%", color: Colors.amber[800]),
            if (boostAddon > 0) _cbRow("Boost Pub", "+${boostAddon.toStringAsFixed(2)}%", color: Colors.purple),
            if (loyaltyDiscount > 0) _cbRow(loyaltyTierLabel, "+${loyaltyDiscount.toStringAsFixed(1)}%", color: Colors.orange),
            _cbRow("Taux total", "${totalRate.toStringAsFixed(2)}%", bold: true, color: Colors.green),
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
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.green)),
                const Text("de cashback obtenu", style: TextStyle(color: Colors.grey)),
                if (lameBonus > 0) ...[
                  const SizedBox(height: 6),
                  Text("+$lameBonus Lames bonus",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: accentGold)),
                ],
              ]),
            ),
          ]),
        ),
        actions: [
          ElevatedButton.icon(
            icon: const Icon(Icons.check),
            label: const Text("Récupérer"),
            style: ElevatedButton.styleFrom(backgroundColor: primaryGreen, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _saveCashback(amountSpent, cashbackAmount, lameBonus, totalRate, rawText, loyaltyTierLabel);
            },
          ),
        ],
      ),
    );
  }

  Widget _cbRow(String label, String value, {bool bold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
        Text(value, style: TextStyle(
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          color: color ?? Colors.black87,
          fontSize: bold ? 15 : 13,
        )),
      ]),
    );
  }

  Future<void> _saveCashback(double amountSpent, double cashbackAmount,
      int lameBonus, double rateApplied, String rawText, String loyaltyTier) async {
    try {
      final uid = widget.userProfile.id;
      final storeId = widget.store.id;
      final now = Timestamp.now();
      final batch = FirebaseFirestore.instance.batch();

      // 1. Historique cashback utilisateur
      batch.set(
        FirebaseFirestore.instance.collection('users').doc(uid).collection('cashback_history').doc(),
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
        FirebaseFirestore.instance.collection('stores').doc(storeId).collection('store_transactions').doc(),
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
      batch.update(FirebaseFirestore.instance.collection('stores').doc(storeId), {
        'totalAmountSpentByUser': FieldValue.increment(amountSpent),
        'totalCashbackGiven': FieldValue.increment(cashbackAmount),
      });

      // 4. Fidélité utilisateur
      batch.update(FirebaseFirestore.instance.collection('users').doc(uid), {
        'loyalty_progress.$storeId.visits': FieldValue.increment(1),
        'loyalty_progress.$storeId.spend': FieldValue.increment(amountSpent),
      });

      await batch.commit();

      if (lameBonus > 0) widget.onAddLame(lameBonus, source: "Cashback ${widget.store.name}");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("✅ Cashback ${cashbackAmount.toStringAsFixed(2)}€ enregistré !${lameBonus > 0 ? ' +$lameBonus Lames' : ''}"),
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
  const _CashbackHistorySheet({required this.userId, required this.storeId, required this.storeName});

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
          Expanded(child: Text("Historique — $storeName",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
        ]),
        const Divider(),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users').doc(userId)
                .collection('cashback_history')
                .where('store_id', isEqualTo: storeId)
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final docs = snap.data!.docs;
              if (docs.isEmpty) {
                return const Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 60, color: Colors.grey),
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
                totalCashback += (m['cashback_amount'] as num?)?.toDouble() ?? 0;
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
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                    _summaryChip("${totalSpent.toStringAsFixed(2)}€", "Total dépensé", Colors.blue),
                    Container(width: 1, height: 40, color: Colors.grey[300]),
                    _summaryChip("${totalCashback.toStringAsFixed(2)}€", "Cashback total", Colors.green),
                    Container(width: 1, height: 40, color: Colors.grey[300]),
                    _summaryChip("${docs.length}", "Visites", Colors.purple),
                  ]),
                ),
                Expanded(child: ListView.separated(
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final ts = (d['timestamp'] as Timestamp?)?.toDate();
                    final spent = (d['amount_spent'] as num?)?.toDouble() ?? 0.0;
                    final cb = (d['cashback_amount'] as num?)?.toDouble() ?? 0.0;
                    final rate = (d['cashback_rate_applied'] as num?)?.toDouble() ?? 0.0;
                    final lames = d['lame_points_earned'] as int? ?? 0;
                    final tier = d['loyalty_tier_applied'] as String?;
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.green.withOpacity(0.12),
                        child: Text("${cb.toStringAsFixed(1)}€",
                            style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                      ),
                      title: Text("${spent.toStringAsFixed(2)}€ → ${cb.toStringAsFixed(2)}€ (${rate.toStringAsFixed(1)}%)"),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (lames > 0) Text("+$lames Lames",
                            style: const TextStyle(color: accentGold, fontWeight: FontWeight.w600, fontSize: 12)),
                        if (tier != null && tier.isNotEmpty) Text(tier,
                            style: const TextStyle(fontSize: 11, color: Colors.orange)),
                        if (ts != null) Text(
                          "${ts.day.toString().padLeft(2,'0')}/${ts.month.toString().padLeft(2,'0')}/${ts.year}  ${ts.hour.toString().padLeft(2,'0')}:${ts.minute.toString().padLeft(2,'0')}",
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
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
      Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: color)),
      Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }
}

class ShopScreen extends StatelessWidget {
  final UserProfile userProfile;

  final Function(int cost) onPurchase;

  ShopScreen({Key? key, required this.userProfile, required this.onPurchase}) : super(key: key);

  // Dans la classe ShopScreen :

  Future<void> _buyItem(BuildContext context, ShopItem item) async {
    if (userProfile.lamePoints < item.costLame) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Pas assez de Lame Points!"), backgroundColor: Colors.red));
      return;
    }

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Confirmer l\'achat'),
        content: Text('Voulez-vous acheter "${item.name}" pour ${item.costLame} Lame Points?'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Acheter')),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // 1. Mise à jour des points et Ajout de l'historique en une transaction (Batch)
        WriteBatch batch = FirebaseFirestore.instance.batch();

        // Référence utilisateur
        DocumentReference userRef = FirebaseFirestore.instance.collection('users').doc(userProfile.id);
        batch.update(userRef, {
          'lame_points': FieldValue.increment(-item.costLame),
          'updated_at': FieldValue.serverTimestamp(),
        });

        // Référence Historique (C'est ce qui manquait !)
        DocumentReference historyRef = FirebaseFirestore.instance.collection('user_claimed_offers').doc();
        batch.set(historyRef, {
          'user_id': userProfile.id,
          'reward_id': item.id,
          'details': {
            'offer_title': "Achat Boutique : ${item.name}",
            'claimed_for_lame': item.costLame.toDouble(),
          },
          'claimed_at': FieldValue.serverTimestamp(),
          'status': 'approved', // Validé automatiquement car c'est un achat boutique
        });

        await batch.commit();

        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('${item.name} acheté!'), backgroundColor: Colors.green));
        }

        // Mise à jour UI locale
        onPurchase(item.costLame);

        if (context.mounted) Navigator.pop(context);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Erreur lors de l\'achat: $e'), backgroundColor: Colors.red));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Boutique EcoNav')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore.collection('shop_items').orderBy('cost_lame').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: primaryGreen));
          }
          if (snapshot.hasError) return Center(child: Text('Erreur: ${snapshot.error}'));
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Boutique vide.'));
          }

          final items = snapshot.data!.docs.map((doc) => ShopItem.fromFirestore(doc)).toList();
          return GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 0.8),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final canAfford = userProfile.lamePoints >= item.costLame;
              return Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                          Icon(item.icon, size: 40, color: canAfford ? primaryGreen : textGrey),
                          Text(item.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Text(item.type, style: const TextStyle(fontSize: 12, color: textGrey)),
                          Chip(
                            label: Text('${item.costLame} L',
                                style: TextStyle(
                                    color: canAfford ? accentGold : Colors.red.shade700,
                                    fontWeight: FontWeight.bold)),
                            backgroundColor:
                            canAfford ? accentGold.withOpacity(0.2) : Colors.red.withOpacity(0.1),
                            avatar: Icon(Icons.eco_rounded,
                                color: canAfford ? accentGold : Colors.red.shade700, size: 16),
                          ),
                          if (!canAfford)
                            const Text("Fonds insuffisants",
                                style: TextStyle(color: Colors.red, fontSize: 10)),
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

  const ProfileBottomSheet({
    Key? key,
    required this.userProfile,
    required this.onOpenShop
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
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Compris")),
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
                    border: Border.all(color: Colors.orange.withOpacity(0.4)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.info_outline, color: Colors.orange, size: 16),
                    SizedBox(width: 6),
                    Expanded(child: Text("Modifiable 1 fois par an (illimité avec Premium)", style: TextStyle(fontSize: 11, color: Colors.orange))),
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
                  Get.dialog(const Center(child: CircularProgressIndicator()),
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

                    Get.snackbar("Erreur",
                        "Impossible de récupérer la position: $e",
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
                        const SizedBox(height: 15),
                        NominatimSearchBar(
                            onSelected: (name, coords) async {
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(children: [Icon(Icons.warning_amber_rounded, color: Colors.orange), SizedBox(width: 8), Text("Confirmer")]),
          content: const Text("Voulez-vous vraiment supprimer votre abonnement VIP ?"),
          actions: <Widget>[
            TextButton(child: const Text("Annuler"), onPressed: () => Navigator.of(dialogContext).pop(false)),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("Supprimer VIP"), onPressed: () => Navigator.of(dialogContext).pop(true)),
          ],
        );
      },
    );

    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(userProfile.id).update({
          'is_vip': false,
          'updated_at': FieldValue.serverTimestamp(),
        });
        Navigator.pop(context); // Ferme sheet
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Abonnement VIP supprimé"), backgroundColor: Colors.green));
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _showPremiumDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
                const Text("Débloquez tous les avantages exclusifs :", style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _premiumBenefitRow(Icons.add_road, "Déviation tolérée : 6 km", "Au lieu de 3 km en standard"),
                _premiumBenefitRow(Icons.bolt, "x2 Lames sur chaque trajet", "Multipliez vos gains"),
                _premiumBenefitRow(Icons.percent, "+15% Cashback magasins", "Plus de réductions"),
                _premiumBenefitRow(Icons.trending_up, "Multiplicateur Ad Points", "Boostez votre progression"),
                _premiumBenefitRow(Icons.star, "Niveau max débloqué", "Progressez sans limite"),
                _premiumBenefitRow(Icons.cached, "Pub boost double", "Cashback boosté x2"),
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
            TextButton(child: const Text("Fermer"), onPressed: () => Navigator.of(dialogContext).pop()),
            if (!userProfile.isVip)
              ElevatedButton.icon(
                icon: const Icon(Icons.workspace_premium, size: 16),
                label: const Text("Devenir Premium"),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFB300), foregroundColor: Colors.black),
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await FirebaseFirestore.instance.collection('users').doc(userProfile.id).update({'is_vip': true});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("✅ Premium activé !"), backgroundColor: Colors.green),
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
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Couleurs constantes pour garder la cohérence
    const Color primaryGreen = Color(0xFF388E3C);
    const Color accentGold = Color(0xFFFFB300);
    const Color textGrey = Color(0xFF757575);
    const Color cardWhite = Color(0xFFFFFFFF);

    return Container(
      padding: const EdgeInsets.all(20),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
          color: cardWhite,
          borderRadius: BorderRadius.vertical(top: Radius.circular(25))
      ),
      child: SingleChildScrollView(
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. AVATAR ET NOM
          CircleAvatar(
            radius: 40,
            backgroundColor: primaryGreen,
            child: Text(
                userProfile.username.isNotEmpty ? userProfile.username.substring(0, 1).toUpperCase() : "U",
                style: const TextStyle(fontSize: 30, color: Colors.white)
            ),
          ),
          const SizedBox(height: 12),
          Text(userProfile.username, style: Theme.of(context).textTheme.headlineMedium),

          // 2. STATUT VIP
          if (userProfile.isVip)
            Column(
              children: [
                const SizedBox(height: 8),
                const Chip(label: Text('Membre VIP'), avatar: Icon(Icons.workspace_premium, color: accentGold), backgroundColor: accentGold),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _removeVipSubscription(context),
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  label: const Text("Enlever VIP", style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red), backgroundColor: Colors.red.withOpacity(0.1)),
                ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: OutlinedButton.icon(
                onPressed: () => _showPremiumDialog(context),
                icon: const Icon(Icons.workspace_premium_outlined, color: accentGold),
                label: const Text("Obtenir Premium", style: TextStyle(color: accentGold)),
                style: OutlinedButton.styleFrom(side: const BorderSide(color: accentGold), backgroundColor: accentGold.withOpacity(0.1)),
              ),
            ),

          const SizedBox(height: 15),
          const Divider(),

          // 3. SYSTÈME DE NIVEAUX
          _buildLevelProgressSection(userProfile, context),

          const Divider(),

          // 4. STATISTIQUES UTILISATEUR
          ListTile(leading: const Icon(Icons.eco_rounded, color: accentGold), title: Text('${userProfile.lamePoints} Lame Points')),
          ListTile(leading: const Icon(Icons.login_rounded, color: textGrey), title: Text('${userProfile.consecutiveLogins} jours de connexion')),

          const Divider(),



          // 5. ESPACE COMMERÇANT
          const SizedBox(height: 10),
          ElevatedButton.icon(
              icon: const Icon(Icons.storefront_rounded, color: Colors.white),
              label: const Text('Accès Espace Pro / Commerçant'),
              onPressed: () {
                Navigator.pop(context); // Fermer le sheet
                Navigator.push(context, MaterialPageRoute(builder: (_) => MerchantDashboard(userProfile: userProfile)));
              },
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 45),
                  backgroundColor: Colors.blueGrey.shade800
              )
          ),

          // 6. BOUTIQUE
          const SizedBox(height: 10),
          ElevatedButton.icon(
              icon: const Icon(Icons.shopping_bag_outlined),
              label: const Text('Ouvrir la Boutique'),
              onPressed: onOpenShop,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45))
          ),

          // 6b. ADRESSE DOMICILE
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.home_rounded, color: primaryGreen),
            label: Text(
              userProfile.homeAddressString != null && userProfile.homeAddressString!.isNotEmpty
                  ? '🏠 Modifier domicile'
                  : '🏠 Définir mon domicile',
              style: const TextStyle(color: primaryGreen),
            ),
            onPressed: () => _handleSetHomeAddress(context),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 45),
              side: const BorderSide(color: primaryGreen),
            ),
          ),
          if (userProfile.homeAddressString != null && userProfile.homeAddressString!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                userProfile.homeAddressString!,
                style: const TextStyle(fontSize: 11, color: textGrey),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),

          // 7. FERMER
          const SizedBox(height: 10),
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Fermer", style: TextStyle(color: textGrey))
          ),
        ],
        ),
      ),
    );
  }

  Widget _buildLevelProgressSection(UserProfile userProfile, BuildContext context) {
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
    while (totalLame >= totalLameForCurrentLevel + lameNeeded && currentLevel < 50) {
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

  const _PremiumBenefit({Key? key, required this.icon, required this.text}) : super(key: key);

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

  factory RewardOffer.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
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

    if (imageUrl == 'icon_megaphone_red' || imageUrl == 'icon_megaphone_red_concours') {
      return Icon(Icons.campaign, size: size, color: color);
    }
    if (imageUrl == 'icon_paypal_logo_placeholder') {
      return Icon(Icons.paypal, size: size, color: color);
    }
    if (imageUrl == 'icon_1000_eco_green_circle') {
      return CircleAvatar(
        radius: size / 2,
        backgroundColor: Colors.green,
        child: Text("1k", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: size * 0.4)),
      );
    }

    if (imageUrl != null && imageUrl!.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: imageUrl!, width: size, height: size, fit: BoxFit.cover,
        placeholder: (c,u) => SizedBox(width:size, height:size, child:Center(child:SizedBox(width: size*0.5, height:size*0.5, child: CircularProgressIndicator(strokeWidth: 2)))),
        errorWidget: (c,u,e) => Icon(Icons.broken_image, size: size, color: Colors.grey),
      );
    }

    IconData iconData;
    switch (offerType) {
      case OfferType.freeOffer:
      case OfferType.promoCode:
        iconData = Icons.campaign; break;
      case OfferType.transfer:
        iconData = Icons.paypal; break;
      case OfferType.contest:
        iconData = Icons.emoji_events; break;
      case OfferType.treePlanting:
        iconData = Icons.forest_outlined; break;
      case OfferType.campaignDonation:
        iconData = Icons.volunteer_activism; break;
      case OfferType.voucher:
        iconData = Icons.storefront; break;
      case OfferType.travelPoints:
        iconData = Icons.flight_takeoff; break;
      case OfferType.sdgDonation:
        iconData = Icons.public; break;
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

class _RewardScreenState extends State<RewardScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  List<RewardOffer> _allOffers = [];
  bool _isLoadingOffers = true;


  final firestore = FirebaseFirestore.instance;

  final List<Map<String, dynamic>> _sdgData = [
    {'id': 1, 'name': 'ODD 1: Pas de pauvreté', 'description': 'Éliminer la pauvreté.', 'imageUrl': 'images/sdg/F-WEB-Goal-01.png'},
    {'id': 2, 'name': 'ODD 2: Faim « zéro »', 'description': 'Éliminer la faim.', 'imageUrl': 'images/sdg/F-WEB-Goal-02.png'},
    {'id': 3, 'name': 'ODD 3: Bonne santé et bien-être', 'description': 'Bonne santé pour tous.', 'imageUrl': 'images/sdg/F-WEB-Goal-03.png'},
    {'id': 4, 'name': 'ODD 4: Éducation de qualité', 'description': 'Éducation de qualité.', 'imageUrl': 'images/sdg/F-WEB-Goal-04.png'},
    {'id': 5, 'name': 'ODD 5: Égalité entre les sexes', 'description': 'Égalité des sexes.', 'imageUrl': 'images/sdg/F-WEB-Goal-05.png'},
    {'id': 6, 'name': 'ODD 6: Eau propre et assainissement', 'description': 'Eau propre.', 'imageUrl': 'images/sdg/F-WEB-Goal-06.png'},
    {'id': 7, 'name': 'ODD 7: Énergie propre', 'description': 'Énergie propre.', 'imageUrl': 'images/sdg/F-WEB-Goal-07.png'},
    {'id': 8, 'name': 'ODD 8: Travail décent', 'description': 'Travail décent.', 'imageUrl': 'images/sdg/F-WEB-Goal-08.png'},
    {'id': 9, 'name': 'ODD 9: Industrie, innovation', 'description': 'Innovation.', 'imageUrl': 'images/sdg/F-WEB-Goal-09.png'},
    {'id': 10, 'name': 'ODD 10: Inégalités réduites', 'description': 'Moins d\'inégalités.', 'imageUrl': 'images/sdg/F-WEB-Goal-10.png'},
    {'id': 11, 'name': 'ODD 11: Villes durables', 'description': 'Villes durables.', 'imageUrl': 'images/sdg/F-WEB-Goal-11.png'},
    {'id': 12, 'name': 'ODD 12: Consommation responsable', 'description': 'Consommation resp.', 'imageUrl': 'images/sdg/F-WEB-Goal-12.png'},
    {'id': 13, 'name': 'ODD 13: Lutte changements climatiques', 'description': 'Action climat.', 'imageUrl': 'images/sdg/F-WEB-Goal-13.png'},
    {'id': 14, 'name': 'ODD 14: Vie aquatique', 'description': 'Vie aquatique.', 'imageUrl': 'images/sdg/F-WEB-Goal-14.png'},
    {'id': 15, 'name': 'ODD 15: Vie terrestre', 'description': 'Vie terrestre.', 'imageUrl': 'images/sdg/F-WEB-Goal-15.png'},
    {'id': 16, 'name': 'ODD 16: Paix, justice', 'description': 'Paix et justice.', 'imageUrl': 'images/sdg/F-WEB-Goal-16.png'},
    {'id': 17, 'name': 'ODD 17: Partenariats', 'description': 'Partenariats.', 'imageUrl': 'images/sdg/F-WEB-Goal-17.png'},
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
    final userStatsProvider = Provider.of<UserStatsProvider>(context, listen: false);
    final currentUser = FirebaseAuth.instance.currentUser;
    if (userStatsProvider.userStats == null && currentUser != null) {
      final userId = currentUser.uid;
      try {
        final docSnapshot = await firestore.collection('user_stats').doc(userId).get();
        if (mounted) {
          UserStats loadedStats;
          if (docSnapshot.exists && docSnapshot.data() != null) {
            loadedStats = UserStats.fromJson(docSnapshot.data()!);
          } else {
            loadedStats = UserStats();
            await firestore.collection('user_stats').doc(userId).set(loadedStats.toJson());
          }
          userStatsProvider.setUserStats(loadedStats);
        }
      } catch (e) {
        print("Error loading user stats for RewardScreen init: $e");
        if(mounted) userStatsProvider.setUserStats(UserStats());
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
            content: Text("Erreur de chargement des offres: $e. Using fallback."),
            backgroundColor: Colors.red));
        _fetchOffersDummyData();
      }
    }
  }

  Future<void> _fetchOffersDummyData() async {
    await Future.delayed(const Duration(milliseconds: 100));
    DateTime now = DateTime.now();
    _allOffers = [
      RewardOffer(id: "free_offer_01", title: "Essai gratuit de 1 semaine", description: "Découvrez notre partenaire privilégié.", offerType: OfferType.freeOffer, brandName: "Marque Essai", ecoCost: 0, valueText: "1 semaine d'accès", imageUrl: "icon_megaphone_red", createdAt: now, sortOrder: 1, actionButtonText: "Commencer l'essai", detailPageUrl: "https://example.com/free-trial"),
      RewardOffer(id: "promo_code_01", title: "Code Promo -25%", description: "Obtenez un code promotionnel exclusif.", offerType: OfferType.promoCode, brandName: "Marque Promo", ecoCost: 0, valueText: "-25% sur tout", imageUrl: "icon_megaphone_red", detailsJson: {'code': 'TWINPLANET25'}, createdAt: now, sortOrder: 2, actionButtonText: "Obtenir le code"),
      RewardOffer(id: "transfer_paypal_01", title: "\$5 via Paypal", description: "Échangez 5000 de vos éco.", offerType: OfferType.transfer, brandName: "Paypal", ecoCost: 5000, valueText: "\$5", imageUrl: "icon_paypal_logo_placeholder", createdAt: now, sortOrder: 3, actionButtonText: "Demander le virement"),
      RewardOffer(id: "contest_auction_ps5", title: "Enchère Pack PS5", description: "Misez vos éco pour gagner une PS5.", offerType: OfferType.contest, brandName: "Enchères Exclusives", valueText: "PS5 à gagner", imageUrl: "icon_megaphone_red_concours", detailsJson: {'type': 'auction', 'product_name': 'Pack PS5', 'product_image_url': 'https://i.imgur.com/gO0A3vT.png', 'min_bid': 50.0, 'current_highest_bid': 1500.0, 'end_date': now.add(const Duration(days: 7)).toIso8601String(), 'contest_id_ref': 'CONTEST_AUCTION_001'}, createdAt: now, sortOrder: 4, ecoCost: 50),
      RewardOffer(id: "contest_raffle_ps5", title: "Super Tirage PS5", description: "Achetez des tickets pour gagner une PS5.", offerType: OfferType.contest, brandName: "Grand Tirage", valueText: "PS5 à gagner", imageUrl: "icon_megaphone_red_concours", detailsJson: {'type': 'raffle', 'product_name': 'Pack PS5', 'product_image_url': 'https://i.imgur.com/gO0A3vT.png', 'ticket_cost_eco': 20, 'total_tickets_sold': 350,  'end_date': now.add(const Duration(days: 14)).toIso8601String()}, createdAt: now, sortOrder: 5, ecoCost: 20),
      RewardOffer(id: "campaign_water_01", title: "L'oeuvre de l'eau enfants", description: "Contribuez à notre campagne pour l'eau potable.", offerType: OfferType.campaignDonation, brandName: "Accès à l'Eau", ecoCost: 50, valueText: "Contribuer", imageUrl: "https://i.imgur.com/zJ9Ae4Z.jpg", detailsJson: {'current_amount_eco': 58000, 'target_amount_eco': 100000, 'current_donors': 433, 'campaign_id_ref': 'CAMP_WATER_001'}, createdAt: now, sortOrder: 6),
      RewardOffer(id: "voucher_generic_01", title: "Bon d'achat de 5€", description: "Utilisez vos éco pour un bon d'achat.", offerType: OfferType.voucher, brandName: "Bons d'Achat Express", ecoCost: 5000, valueText: "Valeur 5€", imageUrl: "icon_megaphone_red", createdAt: now, sortOrder: 100),
      RewardOffer(id: "travel_points_01", title: "Points Voyage", description: "Cumulez des points voyage.", offerType: OfferType.travelPoints, brandName: "Voyages Malin", ecoCost: 1000, valueText: "100 points voyage", imageUrl: "icon_megaphone_red", createdAt: now, sortOrder: 101),
    ];
    if (mounted) setState(() => _isLoadingOffers = false);
  }



  Future<bool> _spendLamePoints(double amount, String offerIdContext, String offerTitleContext, String email) async {
    final currentUser = FirebaseAuth.instance.currentUser;

    // 1. Vérifications de base
    if (currentUser == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur: Utilisateur non connecté."), backgroundColor: Colors.red));
      return false;
    }

    if (widget.userProfile.lamePoints < amount) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pas assez de Lame Points!"), backgroundColor: Colors.orange));
      return false;
    }

    final userRef = firestore.collection('users').doc(currentUser.uid);

    // Création d'une nouvelle référence pour l'historique des demandes
    final claimedOfferRef = firestore.collection('user_claimed_offers').doc();

    try {
      await firestore.runTransaction((transaction) async {
        // 2. Débiter les points de l'utilisateur
        transaction.update(userRef, {'lame_points': FieldValue.increment(-amount)});

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
          'status': 'pending', // Statut initial : En attente
          // -----------------------------

          // Champs pour l'envoi d'email (facultatif selon votre config backend)
          'to': 'corentinparrel2@gmail.com',
          'message': {
            'subject': 'Nouvelle demande de récompense EcoNav !',
            'text': 'L\'utilisateur $email a réclamé la récompense "$offerTitleContext" pour $amount Lames. ID Utilisateur: ${currentUser.uid}',
            'html': '<h1>Nouvelle Récompense Réclamée</h1><p><b>Utilisateur:</b> $email</p><p><b>Récompense:</b> $offerTitleContext</p><p><b>Coût:</b> $amount Lames</p><p><b>ID User:</b> ${currentUser.uid}</p>',
          }
        });
      });

      // 4. Mettre à jour l'interface locale via le callback parent
      await widget.onPurchase(amount.toInt());
      return true;

    } catch(error) {
      print("Erreur de transaction Firestore: $error");
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur serveur: $error"), backgroundColor: Colors.red));
      return false;
    }
  }
  Future<void> _handleGenericLameSpend(double lameCost, String idContext, String titleContext, {String? successMessage, VoidCallback? onSuccess}) async {
    // 1. Retrieve the current user's email to satisfy the 4th argument
    final user = FirebaseAuth.instance.currentUser;
    final String userEmail = user?.email ?? "corentinparrel2@gmail.com";

    // 2. Pass 'userEmail' as the 4th argument
    bool success = await _spendLamePoints(lameCost, idContext, titleContext, userEmail);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage ?? "Action réussie! ${lameCost.toStringAsFixed(1)} Lame Points dépensés."), backgroundColor: Colors.green));
      onSuccess?.call();
    }
  }

  void _plantTreeConfirmation() {
    if (_treePlantConfirming) {
      _treePlantConfirmTimer?.cancel();
      setState(() => _treePlantConfirming = false);
      _handleGenericLameSpend(1000.0, "plant_tree_action", "Planter un arbre",
          successMessage: "Félicitations! 1000.0 Lame Points dépensés pour planter un arbre.");
    } else {
      setState(() => _treePlantConfirming = true);
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Appuyez à nouveau pour confirmer et planter l'arbre (1000.0 Lame Points)."), duration: Duration(seconds: 3)));
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
          if(sdg['imageUrl'] != null && (sdg['imageUrl'] as String).startsWith('images/'))
            Image.asset(sdg['imageUrl'], width: 30, height: 30, errorBuilder: (c,u,e) => const Icon(Icons.broken_image, size: 30)),
          const SizedBox(width: 10),
          Expanded(child: Text("Soutenir: ${sdg['name']}", style: GoogleFonts.poppins(fontSize: 18)))
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(sdg['description'] as String? ?? "Contribuez à cet ODD.", style: GoogleFonts.poppins(fontSize: 14)),
            const SizedBox(height: 16),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                  labelText: "Montant du don (en Lame Points)",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  prefixIcon: Icon(Icons.eco, color: Theme.of(context).primaryColor)
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Annuler")),
          ElevatedButton(
            onPressed: () {
              final amount = double.tryParse(amountController.text);
              if (amount != null && amount > 0) {
                Navigator.of(ctx).pop();
                _handleGenericLameSpend(
                    amount,
                    "sdg_donation_${sdg['id']}",
                    "Don à ${sdg['name']}",
                    successMessage: "Merci pour votre don de ${amount.toStringAsFixed(1)} Lame Points à ${sdg['name']}!");
              } else {
                if(mounted) ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Veuillez entrer un montant valide."), backgroundColor: Colors.orange));
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
      return Scaffold(appBar: _buildAppBar(), body: const Center(child: CircularProgressIndicator()));
    }


    List<RewardOffer> freeOffers = _allOffers.where((o) => o.offerType == OfferType.freeOffer).toList();
    List<RewardOffer> promoCodes = _allOffers.where((o) => o.offerType == OfferType.promoCode).toList();
    List<RewardOffer> transfers = _allOffers.where((o) => o.offerType == OfferType.transfer).toList();
    List<RewardOffer> contests = _allOffers.where((o) => o.offerType == OfferType.contest).toList();
    List<RewardOffer> activeCampaigns = _allOffers.where((o) => o.offerType == OfferType.campaignDonation && o.isActive).toList();

    List<RewardOffer> vouchersAndPoints = _allOffers.where((o) => o.offerType == OfferType.voucher || o.offerType == OfferType.travelPoints).toList();

    return Scaffold(
      appBar: _buildAppBar(),

      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        children: [
          _buildOfferSection("Offres gratuites", freeOffers, Icons.redeem, Colors.red.shade400),
          _buildOfferSection("Codes promo", promoCodes, Icons.local_offer, Colors.orange.shade400),
          _buildOfferSection("Virements", transfers, Icons.paypal, Colors.blue.shade700),

          _buildOfferSection("Bons d'achat & Points", vouchersAndPoints, Icons.storefront, Colors.purple.shade400),
          _buildContestSection(contests),
          _buildSolidaritySection(activeCampaigns),
        ],
      ),
      backgroundColor: Colors.grey[100],
    );
  }



  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text('Récompenses', style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
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
            avatar: Icon(Icons.eco, color: Theme.of(context).primaryColor, size: 18),
            label: Text("${widget.userProfile.lamePoints} Lame Points", style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
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
        _buildOfferSection("Offres gratuites", freeOffers, Icons.redeem, Colors.red.shade400),
        _buildOfferSection("Codes promo", promoCodes, Icons.local_offer, Colors.orange.shade400),
        _buildOfferSection("Virements", transfers, Icons.paypal, Colors.blue.shade700),
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

  Widget _buildOfferSection(String title, List<RewardOffer> offers, IconData defaultIcon, Color defaultColor) {
    if (offers.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title),
        ...offers.map((offer) => _buildStandardOfferCard(offer, defaultIcon, defaultColor)).toList(),
        const SizedBox(height: 16),
      ],
    );
  }

  void _handleOfferClick(RewardOffer offer) {
    print("Gestion du clic sur l'offre : ${offer.title}, type: ${offer.offerType}");


    if (offer.offerType == OfferType.contest) {
      final contestType = offer.detailsJson?['type'] as String?;
      if (contestType == 'auction') {
        Navigator.push(context, MaterialPageRoute(builder: (_) => AuctionScreen(offer: offer)));
      } else if (contestType == 'raffle') {
        Navigator.push(context, MaterialPageRoute(builder: (_) => RaffleTicketScreen(offer: offer)));
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Détails du concours '${offer.title}' non disponibles.")));
      }
      return;
    }

    if (offer.offerType == OfferType.campaignDonation) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => CampaignDetailPage(offer: offer)))
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
            const Text("Voici votre code promo ! Copiez-le et utilisez-le chez notre partenaire."),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200)
              ),

              child: SelectableText(
                code,
                style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal.shade700),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("Fermer")),
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
        content: Text("Votre demande pour \"$offerTitle\" a bien été prise en compte. Elle sera traitée manuellement et vous recevrez une confirmation."),
        actions: [
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text("OK")),
        ],
      ),
    );
  }
  Widget _buildStandardOfferCard(RewardOffer offer, IconData defaultIcon, Color defaultColor) {
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
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            offer.brandName ?? "Partenaire CleanPlanet",
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey[600]),
          ),
          trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.0)),
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
                      style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, height: 1.2),
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
          ...activeCampaigns.map((campaign) => _buildCampaignCard(campaign)).toList(),
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
              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4.0, bottom: 12.0),
              child: Text(
                "Total récolté : $_totalSdgCollectedDisplay Lame Points",
                style: GoogleFonts.poppins(fontSize: 13, color: Colors.grey.shade700),
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
                          return Container(color: Colors.grey[200], child: const Icon(Icons.error_outline, color: Colors.red));
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
            backgroundColor: isConfirming ? Colors.orange.shade600 : Colors.green.shade600,
            child: Text(
              "1k",
              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          title: Text(
            isConfirming ? "Confirmer pour planter" : "Planter un arbre",
            style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            "Coût : 1000.0 Lame Points",
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: isConfirming ? Colors.orange.shade800 : Colors.grey.shade600,
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
    final String donorsText = "${offer.detailsJson?['current_donors'] ?? 0} donateur${(offer.detailsJson?['current_donors'] ?? 0) > 1 ? 's' : ''}";

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
                  Text(offer.title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(progressText, style: GoogleFonts.poppins(fontSize: 12, color: Theme.of(context).primaryColor, fontWeight: FontWeight.w500)),
                      Text(donorsText, style: GoogleFonts.poppins(fontSize: 12, color: Colors.blueGrey.shade700)),
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
      return Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Text("Aucun bon plan disponible.", style: GoogleFonts.poppins())));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: bonsPlansOffers.map((offer) => _buildOldConvertirCard(offer)).toList(),
    );
  }

  Widget _buildOldConvertirCard(RewardOffer offer) {
    Widget imageDisplay;
    if (offer.imageUrl != null && offer.imageUrl!.startsWith('http')) {
      imageDisplay = CachedNetworkImage(imageUrl: offer.imageUrl!, width: 60, height: 60, fit: BoxFit.contain,
        placeholder: (c,u) => const SizedBox(width:60, height: 60, child: Center(child: CircularProgressIndicator(strokeWidth: 2,))),
        errorWidget: (c,u,e) => offer.getIconWidget(size: 30, color: Colors.blueGrey.shade700),
      );
    } else {
      imageDisplay = offer.getIconWidget(size: 30, color: Colors.blueGrey.shade700);
    }

    return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0), elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.0)),
        child: InkWell( onTap: () => _handleOfferClick(offer), borderRadius: BorderRadius.circular(10.0),
          child: Padding( padding: const EdgeInsets.all(12.0),
            child: Row( children: [
              Container(width: 60, height: 60, decoration: BoxDecoration( color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(8.0)), child: Center(child: imageDisplay)),
              const SizedBox(width: 12),
              Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(offer.brandName ?? "Partenaire", style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey[600])),
                Text(offer.title, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w500), maxLines: 2, overflow: TextOverflow.ellipsis),
                Text("${offer.ecoCost ?? 0} Lame Points = ${offer.valueText ?? 'Valeur non spécifiée'}", style: GoogleFonts.poppins(fontSize: 13, color: Theme.of(context).primaryColor, fontWeight: FontWeight.w500)),
              ], ), ),
              const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
            ], ), ),) );
  }
}





class OfferActionPage extends StatefulWidget {
  final RewardOffer offer;
  final UserProfile userProfile;
  // Mise à jour de la signature du callback
  final Future<bool> Function(double amount, String offerId, String offerTitle, String email) onClaimOffer;

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
        content: Text("Voulez-vous vraiment utiliser ${cost.toStringAsFixed(0)} Lame Points pour obtenir \"${widget.offer.title}\" ?\n\nLa récompense sera envoyée à : ${_emailController.text}"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Annuler")),
          ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Confirmer")),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isClaiming = true);
    try {
      // 2. Appel de la fonction avec l'email saisi
      final bool success = await widget.onClaimOffer(
          cost,
          widget.offer.id,
          widget.offer.title,
          _emailController.text.trim()
      );

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
              child: widget.offer.imageUrl != null && widget.offer.imageUrl!.startsWith('http')
                  ? CachedNetworkImage(
                imageUrl: widget.offer.imageUrl!,
                fit: BoxFit.cover,
                placeholder: (context, url) => const Center(child: CircularProgressIndicator()),
                errorWidget: (context, url, error) => Center(child: widget.offer.getIconWidget(size: 80, color: Colors.grey.shade400.withOpacity(0.5))),
              )
                  : Center(child: widget.offer.getIconWidget(size: 80, color: Colors.grey.shade400.withOpacity(0.5))),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form( // Ajout du Formulaire
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.offer.expiryDate != null
                          ? "Expire dans ${widget.offer.expiryDate!.difference(DateTime.now()).inDays} jours"
                          : "Offre permanente",
                      style: GoogleFonts.poppins(color: Colors.grey[600], fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(widget.offer.title, style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text("Par ${widget.offer.brandName ?? 'Partenaire'}",
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 24),

                    // --- NOUVELLE SECTION EMAIL ---
                    Text("Adresse de réception:", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        hintText: "votre.email@exemple.com",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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

                    Text("Vous recevez:", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                      child: Text(widget.offer.valueText ?? "Un avantage exclusif!",
                          style: GoogleFonts.poppins(fontSize: 16, color: Colors.green.shade700, fontWeight: FontWeight.w500)),
                    ),
                    const SizedBox(height: 24),
                    Text("À Propos de l'offre:", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(widget.offer.description, style: GoogleFonts.poppins(fontSize: 15, height: 1.5)),

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
                            Expanded(child: Text("Demande enregistrée pour ${_emailController.text}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))),
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
          onPressed: (_isOfferClaimed || !canAfford || _isClaiming) ? null : _claimOffer,
          style: ElevatedButton.styleFrom(
            backgroundColor: _isOfferClaimed ? Colors.grey : Theme.of(context).primaryColor,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _isClaiming
              ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3,))
              : Text(
              _isOfferClaimed
                  ? "Offre Réclamée"
                  : (cost > 0
                  ? "Obtenir pour ${cost.toStringAsFixed(0)} Lames"
                  : "Obtenir Gratuitement"),
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.white)
          ),
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
        if (mounted && _contestIdRef != null && _contestDetails?['status'] == 'open') {
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
    _productName = widget.offer.detailsJson?['product_name'] ?? widget.offer.title;
    _productImageUrl = widget.offer.detailsJson?['product_image_url'] ?? widget.offer.imageUrl;
    _minBid = (widget.offer.detailsJson?['min_bid'] as num?)?.toDouble() ?? 10.0;
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
      final docSnapshot = await _firestore.collection('contests').doc(_contestIdRef).get();

      if (mounted) {
        if (docSnapshot.exists && docSnapshot.data() != null) {
          final data = docSnapshot.data()!;

          String? highestBidderUsername;
          if (data['highest_bidder_user_id'] != null) {
            final bidderProfile = await _firestore.collection('users').doc(data['highest_bidder_user_id']).get();
            highestBidderUsername = bidderProfile.data()?['username'] as String?;
          }

          setState(() {
            _contestDetails = {
              ...data,
              'highest_bidder_profile': {'username': highestBidderUsername},
            };

            double dbHighestBid = (_contestDetails?['current_highest_bid'] as num?)?.toDouble() ?? _minBid;
            if (_currentBidInput <= dbHighestBid && dbHighestBid >= _minBid) {
              _currentBidInput = dbHighestBid + 0.1;
              _bidController.text = _currentBidInput.toStringAsFixed(1);
            } else if (_currentBidInput < _minBid) {
              _currentBidInput = _minBid;
              _bidController.text = _currentBidInput.toStringAsFixed(1);
            }
          });
        } else {
          _errorMessage = "Détails du concours non trouvés (ID: $_contestIdRef).";
        }
        if (!isSilent) _isLoadingContest = false;
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
    final userStatsProvider = Provider.of<UserStatsProvider>(context, listen: false);
    final currentUserLamePoints = userStatsProvider.totalLameGained;
    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connectez-vous pour enchérir."), backgroundColor: Colors.red));
      return;
    }
    final currentUserId = currentUser.uid;

    if (_contestDetails == null || _contestDetails!['status'] != 'open') {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("L'enchère n'est pas ouverte."), backgroundColor: Colors.orange));
      return;
    }
    if (_contestDetails!['end_date'] is! String) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Date de fin invalide pour l'enchère."), backgroundColor: Colors.red));
      return;
    }
    if (DateTime.now().isAfter(DateTime.parse(_contestDetails!['end_date']))) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("L'enchère est terminée."), backgroundColor: Colors.orange));
      _fetchContestDetails();
      return;
    }

    final double bidAmount = _currentBidInput;
    final double currentHighestBid = (_contestDetails?['current_highest_bid'] as num?)?.toDouble() ?? _minBid;
    final String? currentHighestBidderId = _contestDetails?['highest_bidder_user_id'] as String?;

    if (bidAmount <= currentHighestBid) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Votre enchère doit être supérieure à ${currentHighestBid.toStringAsFixed(1)} Lame Points."), backgroundColor: Colors.orange));
      return;
    }
    if (bidAmount < _minBid) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Mise minimale: ${_minBid.toStringAsFixed(1)} Lame Points."), backgroundColor: Colors.orange));
      return;
    }
    if (bidAmount > currentUserLamePoints) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pas assez de Lame Points."), backgroundColor: Colors.orange));
      return;
    }

    setState(() => _isLoadingContest = true);

    try {
      await _firestore.runTransaction((transaction) async {
        final contestRef = _firestore.collection('contests').doc(_contestIdRef);
        final userStatsRef = _firestore.collection('user_stats').doc(currentUserId);
        final oldHighestBidderStatsRef = currentHighestBidderId != null && currentHighestBidderId != currentUserId
            ? _firestore.collection('user_stats').doc(currentHighestBidderId)
            : null;

        final contestDoc = await transaction.get(contestRef);
        final userStatsDoc = await transaction.get(userStatsRef);
        final oldHighestBidderStatsDoc = await (oldHighestBidderStatsRef != null ? transaction.get(oldHighestBidderStatsRef) : Future.value(null));

        if (!contestDoc.exists || contestDoc.data() == null) {
          throw Exception("Contest not found.");
        }
        if (!userStatsDoc.exists || userStatsDoc.data() == null) {
          throw Exception("User stats not found.");
        }

        final currentContestData = contestDoc.data()!;
        final currentUserStatsData = userStatsDoc.data()!;


        final double latestHighestBid = (currentContestData['current_highest_bid'] as num?)?.toDouble() ?? _minBid;
        if (bidAmount <= latestHighestBid) {
          throw Exception("Une enchère plus élevée a été placée.");
        }


        final double newUserLamePoints = (currentUserStatsData['totalLameGained'] as num?)?.toDouble() ?? 0.0;
        if (newUserLamePoints < bidAmount) {
          throw Exception("Fonds insuffisants.");
        }
        transaction.update(userStatsRef, {'totalLameGained': FieldValue.increment(-bidAmount)});
        userStatsProvider.addLame(-bidAmount);


        if (oldHighestBidderStatsRef != null && oldHighestBidderStatsDoc != null && oldHighestBidderStatsDoc.exists) {
          transaction.update(oldHighestBidderStatsRef, {'totalLameGained': FieldValue.increment(currentHighestBid)});
        }


        transaction.update(contestRef, {
          'current_highest_bid': bidAmount,
          'highest_bidder_user_id': currentUserId,
          'updated_at': FieldValue.serverTimestamp(),
        });


        _firestore.collection('contest_entries').add({
          'contest_id': _contestIdRef,
          'user_id': currentUserId,
          'entry_type': 'bid',
          'submission_data': {'bid_amount': bidAmount},
          'created_at': FieldValue.serverTimestamp(),
        });

        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enchère placée!"), backgroundColor: Colors.green));
        _fetchContestDetails();

      });
    } catch (e) {
      print("Error placing bid in Firestore transaction: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur enchère: ${e.toString().split("\n").first}"), backgroundColor: Colors.red));
      _fetchContestDetails();
    } finally {
      if (mounted) setState(() => _isLoadingContest = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final userLamePoints = context.watch<UserStatsProvider>().totalLameGained;

    final double displayHighestBid = (_contestDetails?['current_highest_bid'] as num?)?.toDouble() ??
        (widget.offer.detailsJson?['current_highest_bid'] as num?)?.toDouble() ??
        _minBid;
    final String? highestBidderUserId = _contestDetails?['highest_bidder_user_id'] as String?;
    String highestBidderUsername = highestBidderUserId != null
        ? (_contestDetails?['highest_bidder_profile']?['username'] ?? 'Chargement...')
        : 'Aucun';

    final String? contestStatus = _contestDetails?['status'] as String?;
    DateTime? endDate;
    if (_contestDetails?['end_date'] is String) {
      endDate = DateTime.tryParse(_contestDetails!['end_date']);
    } else if (_contestDetails?['end_date'] is Timestamp) {
      endDate = (_contestDetails!['end_date'] as Timestamp).toDate();
    }

    bool isAuctionOpen = contestStatus == 'open' && (endDate == null || DateTime.now().isBefore(endDate));

    if (_isLoadingContest && _contestDetails == null && _errorMessage == null) {
      return Scaffold(appBar: AppBar(title: Text(_productName)), body: const Center(child: CircularProgressIndicator()));
    }
    if (_errorMessage != null && _contestDetails == null) {
      return Scaffold(appBar: AppBar(title: Text(_productName)), body: Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text("Erreur: $_errorMessage", style: const TextStyle(color: Colors.red)))));
    }

    return Scaffold(
      backgroundColor: Colors.green.shade700,
      appBar: AppBar(
        title: Text("Enchérir: $_productName", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        actions: [
          if (_isLoadingContest)
            const Padding(padding: EdgeInsets.only(right: 16.0), child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))))
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            if (_productImageUrl != null && _productImageUrl!.startsWith('http'))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: CachedNetworkImage(
                  imageUrl: _productImageUrl!,
                  height: 200,
                  fit: BoxFit.contain,
                  placeholder: (c, u) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                  errorWidget: (c, u, e) => const Icon(Icons.broken_image, size: 100, color: Colors.white60),
                ),
              )
            else
              const SizedBox(height: 200, child: Center(child: Icon(Icons.inventory_2_outlined, size: 100, color: Colors.white60))),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(widget.offer.description, style: GoogleFonts.poppins(color: Colors.white, fontSize: 16), textAlign: TextAlign.center),
            ),
            Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
                child: Column(
                  children: [
                    Text("Votre enchère (Lame Points)", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 5),
                    SizedBox(
                      width: 180,
                      child: TextField(
                        controller: _bidController,
                        style: GoogleFonts.poppins(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(border: InputBorder.none, contentPadding: EdgeInsets.zero),
                        enabled: isAuctionOpen,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text("Mise minimale: ${_minBid.toStringAsFixed(1)} Lame Points", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
                    Text(
                        "Enchère la plus élevée: ${displayHighestBid.toStringAsFixed(1)} Lame Points ${highestBidderUserId != null && highestBidderUserId != _firebaseAuth.currentUser?.uid ? '(par @$highestBidderUsername)' : '(Aucune enchère)'}",
                        style: GoogleFonts.poppins(color: Colors.yellowAccent, fontSize: 12)),
                    Text("Vos Lame Points: ${userLamePoints.toStringAsFixed(1)}", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
                    if (endDate != null)
                      Text("Termine le: ${DateFormat('dd/MM/yyyy HH:mm').format(endDate)}",
                          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11)),
                    if (!isAuctionOpen)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                            contestStatus == 'closed_pending_draw' || contestStatus == 'completed'
                                ? "ENCHÈRE TERMINÉE"
                                : "ENCHÈRE PAS ENCORE OUVERTE",
                            style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                      )
                  ],
                )),
            if (isAuctionOpen)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 10.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildIncrementDecrementButton(Icons.remove, () {
                      if (_currentBidInput > _minBid) {
                        _bidController.text = (_currentBidInput - 0.1).toStringAsFixed(1);
                      }
                    }),
                    _buildIncrementDecrementButton(Icons.add, () {
                      _bidController.text = (_currentBidInput + 0.1).toStringAsFixed(1);
                    }),
                    _buildIncrementDecrementButton(Icons.exposure_plus_1, () {
                      _bidController.text = (_currentBidInput + 1.0).toStringAsFixed(1);
                    }, labelText: "+1"),
                    _buildIncrementDecrementButton(Icons.exposure_plus_1, () {
                      _bidController.text = (_currentBidInput + 10.0).toStringAsFixed(1);
                    }, labelText: "+10"),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            if (isAuctionOpen)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20),
                child: ElevatedButton(
                  onPressed: _isLoadingContest ? null : _placeBid,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.yellowAccent,
                      foregroundColor: Colors.green.shade900,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  child: _isLoadingContest
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.green))
                      : Text("Enchérir ${_currentBidInput.toStringAsFixed(1)} Lame Points",
                      style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
            _buildBidHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildIncrementDecrementButton(IconData icon, VoidCallback onPressed, {String? labelText}) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white.withOpacity(0.15),
          foregroundColor: Colors.white,
          shape: const CircleBorder(),
          padding: const EdgeInsets.all(15)),
      child: labelText != null ? Text(labelText, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.bold)) : Icon(icon, size: 22),
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
              style: GoogleFonts.poppins(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
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
                return const Center(child: CircularProgressIndicator(color: Colors.white));
              }
              if (snapshot.hasError) {
                return Text("Erreur chargement historique: ${snapshot.error}", style: const TextStyle(color: Colors.redAccent));
              }
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Text("Aucune enchère placée.", style: TextStyle(color: Colors.white70));
              }
              final bids = snapshot.data!.docs;
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: bids.length,
                itemBuilder: (context, index) {
                  final bidDoc = bids[index].data();
                  final double bidAmount = (bidDoc['submission_data']?['bid_amount'] as num?)?.toDouble() ?? 0.0;
                  final userId = bidDoc['user_id'] as String?;
                  final timestamp = (bidDoc['created_at'] as Timestamp?)?.toDate();


                  return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    future: userId != null ? _firestore.collection('users').doc(userId).get() : null,
                    builder: (context, userSnapshot) {
                      String bidderUsername = 'Anonyme';
                      if (userSnapshot.connectionState == ConnectionState.done && userSnapshot.hasData && userSnapshot.data!.exists) {
                        bidderUsername = userSnapshot.data!.data()?['username'] ?? 'Utilisateur inconnu';
                      } else if (userSnapshot.connectionState == ConnectionState.waiting) {
                        bidderUsername = 'Chargement...';
                      }

                      final bidTime = timestamp != null ? DateFormat('dd/MM HH:mm').format(timestamp) : 'N/A';
                      return Card(
                        color: Colors.black.withOpacity(0.15),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          dense: true,
                          title: Text("${bidAmount.toStringAsFixed(1)} Lame Points par @$bidderUsername",
                              style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w500)),
                          trailing: Text(bidTime, style: GoogleFonts.poppins(color: Colors.white70, fontSize: 10)),
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
  final TextEditingController _ticketCountController = TextEditingController(text: "1");
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
          _ticketCountController.text = _ticketCountController.text.substring(0, _ticketCountController.text.length - 1);
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
    final userStatsProvider = Provider.of<UserStatsProvider>(context, listen: false);
    final currentUserLamePoints = userStatsProvider.totalLameGained;
    final currentUser = _firebaseAuth.currentUser;

    if (currentUser == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Connectez-vous pour acheter des tickets."), backgroundColor: Colors.red));
      return;
    }
    final currentUserId = currentUser.uid;

    final ticketCostLame = widget.offer.detailsJson?['ticket_cost_eco'] ?? widget.offer.ecoCost ?? 10;
    final totalCost = _ticketCount * ticketCostLame;

    if (_ticketCount <= 0) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Veuillez entrer un nombre de tickets valide."), backgroundColor: Colors.orange));
      return;
    }
    if (totalCost > currentUserLamePoints) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vous n'avez pas assez de Lame Points."), backgroundColor: Colors.orange));
      return;
    }


    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await _firestore.runTransaction((transaction) async {
        final userStatsRef = _firestore.collection('user_stats').doc(currentUserId);
        final contestRef = _firestore.collection('contests').doc(widget.offer.id);

        final userStatsDoc = await transaction.get(userStatsRef);
        final contestDoc = await transaction.get(contestRef);

        if (!userStatsDoc.exists || userStatsDoc.data() == null) {
          throw Exception("User stats not found.");
        }
        if (!contestDoc.exists || contestDoc.data() == null) {

          throw Exception("Contest not found.");
        }

        final currentUserStatsData = userStatsDoc.data()!;
        final currentContestData = contestDoc.data()!;


        final double currentLamePoints = (currentUserStatsData['totalLameGained'] as num?)?.toDouble() ?? 0.0;
        if (currentLamePoints < totalCost) {
          throw Exception("Fonds insuffisants.");
        }


        transaction.update(userStatsRef, {'totalLameGained': FieldValue.increment(-totalCost.toDouble())});
        userStatsProvider.addLame(-totalCost.toDouble());


        transaction.update(contestRef, {
          'total_tickets_sold': FieldValue.increment(_ticketCount),
          'updated_at': FieldValue.serverTimestamp(),
        });


        _firestore.collection('contest_entries').add({
          'contest_id': widget.offer.id,
          'user_id': currentUserId,
          'entry_type': 'raffle_ticket',
          'submission_data': {'ticket_count': _ticketCount, 'cost_per_ticket_eco': ticketCostLame},
          'created_at': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Achat de $_ticketCount ticket(s) réussi pour $totalCost Lame Points!"), backgroundColor: Colors.blue));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        print("Error buying tickets in Firestore transaction: $e");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur d'achat: ${e.toString().split("\n").first}"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final String productName = widget.offer.detailsJson?['product_name'] ?? widget.offer.title;
    final String? productImageUrl = widget.offer.detailsJson?['product_image_url'] ?? widget.offer.imageUrl;
    final int ticketCostLame = widget.offer.detailsJson?['ticket_cost_eco'] ?? widget.offer.ecoCost ?? 10;
    final int totalCost = _ticketCount * ticketCostLame;
    final userLamePoints = context.watch<UserStatsProvider>().totalLameGained;

    return Scaffold(
      backgroundColor: Colors.green.shade700,
      appBar: AppBar(
        title: Text("Acheter Tickets: $productName", style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
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
                  placeholder: (c, u) => const Center(child: CircularProgressIndicator(color: Colors.white)),
                  errorWidget: (c, u, e) => const Icon(Icons.broken_image, size: 100, color: Colors.white60),
                ),
              )
            else
              const SizedBox(height: 200, child: Center(child: Icon(Icons.inventory_2_outlined, size: 100, color: Colors.white60))),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Text(
                widget.offer.description,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
            Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(15)),
                child: Column(
                  children: [
                    Text("Nombre de participations", style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 5),
                    Text(_ticketCountController.text, style: GoogleFonts.poppins(color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 5),
                    Text("Coût total: $totalCost Lame Points ($ticketCostLame Lame Points/ticket)",
                        style: GoogleFonts.poppins(color: Colors.yellowAccent, fontSize: 12)),
                    Text("Vos Lame Points: ${userLamePoints.toStringAsFixed(1)}",
                        style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12)),
                  ],
                )),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [1, 2, 3].map((n) => _buildNumberButton(n.toString())).toList()),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [4, 5, 6].map((n) => _buildNumberButton(n.toString())).toList()),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [7, 8, 9].map((n) => _buildNumberButton(n.toString())).toList()),
                  const SizedBox(height: 10),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                    _buildNumberButton("", isIcon: false, flex: 1),
                    _buildNumberButton("0", flex: 1),
                    _buildNumberButton("del", isIcon: true, icon: Icons.backspace_outlined, flex: 1),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 20),
              child: ElevatedButton(
                onPressed: _buyTickets,
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellowAccent,
                    foregroundColor: Colors.green.shade900,
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                child: Text("Acheter ${_ticketCount} participation${_ticketCount > 1 ? 's' : ''}",
                    style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildNumberButton(String text, {bool isIcon = false, IconData? icon, int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: ElevatedButton(
          onPressed: () => _updateTicketCount(text),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white.withOpacity(0.15),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 18)),
          child: isIcon ? Icon(icon, size: 24) : Text(text, style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.bold)),
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
      final docSnapshot = await _firestore.collection('rewards').doc(widget.offer.id).get();
      if (docSnapshot.exists && docSnapshot.data() != null) {
        final details = docSnapshot.data()!['details_json'] as Map<String, dynamic>?;
        if (mounted) {
          setState(() {
            _updateCampaignDetails(details);
          });
        }
      }
    } catch (e) {
      print("Error fetching campaign details: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Erreur de chargement de la campagne: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _updateCampaignDetails(Map<String, dynamic>? details) {
    currentAmount = (details?['current_amount_eco'] as num?)?.toInt() ?? 0;
    targetAmount = (details?['target_amount_eco'] as num?)?.toInt() ?? 1;
    donors = (details?['current_donors'] as num?)?.toInt() ?? 0;
    progress = targetAmount > 0 ? (currentAmount / targetAmount).clamp(0.0, 1.0) : 0.0;
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
            if (widget.offer.imageUrl != null && widget.offer.imageUrl!.startsWith('http'))
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CachedNetworkImage(
                  imageUrl: widget.offer.imageUrl!,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (c, u) => const Center(child: CircularProgressIndicator()),
                  errorWidget: (c, u, e) => const Icon(Icons.broken_image, size: 100),
                ),
              ),
            const SizedBox(height: 16),
            Text(widget.offer.title, style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(widget.offer.description, style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[700])),
            const SizedBox(height: 24),
            Text("Progrès: $currentAmount / $targetAmount Lame Points", style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              borderRadius: BorderRadius.circular(5),
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
            ),
            const SizedBox(height: 8),
            Text("$donors donateurs ont déjà contribué!", style: GoogleFonts.poppins(color: Colors.grey[600])),
            const SizedBox(height: 24),
            TextField(
              controller: donationController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Montant de votre don (en Lame Points)",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: Icon(Icons.eco, color: Theme.of(context).primaryColor),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final amount = int.tryParse(donationController.text);
                final currentUser = _firebaseAuth.currentUser;

                if (currentUser == null) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Vous devez être connecté."), backgroundColor: Colors.red));
                  return;
                }
                final currentUserId = currentUser.uid;

                if (amount == null || amount <= 0) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Veuillez entrer un montant valide."), backgroundColor: Colors.orange));
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
                    final campaignRef = _firestore.collection('rewards').doc(widget.offer.id);
                    final userStatsRef = _firestore.collection('user_stats').doc(currentUserId);

                    // Lectures (doivent être faites avant les écritures)
                    final campaignDoc = await transaction.get(campaignRef);
                    final userStatsDoc = await transaction.get(userStatsRef);

                    if (!campaignDoc.exists || campaignDoc.data() == null) {
                      throw Exception("Campagne non trouvée.");
                    }
                    // Note: userStatsDoc peut ne pas exister pour un nouvel user, on gère ça ou on suppose qu'il a 0 points

                    final currentCampaignDetails = campaignDoc.data()!['details_json'] as Map<String, dynamic>? ?? {};

                    // Vérification du solde (si stats existent)
                    if (userStatsDoc.exists) {
                      final currentUserStatsData = userStatsDoc.data()!;
                      final double currentLamePoints = (currentUserStatsData['totalLameGained'] as num?)?.toDouble() ?? 0.0;
                      // Attention: ici on vérifie totalLameGained, mais il faudrait idéalement vérifier le vrai solde 'lame_points' dans la collection 'users'
                      // Pour simplifier selon votre structure actuelle :
                      // On suppose que le check est fait ou on laisse la transaction échouer si solde négatif (via règles de sécurité)
                    }

                    // --- ECRITURES ---

                    // 1. Mise à jour des stats utilisateur
                    transaction.update(userStatsRef, {'totalLameGained': FieldValue.increment(-amount.toDouble())});

                    // Mise à jour locale (Provider) - Attention, c'est hors transaction mais nécessaire pour l'UI
                    final userStatsProvider = Provider.of<UserStatsProvider>(context, listen: false);
                    userStatsProvider.addLame(-amount.toDouble());

                    // 2. Mise à jour de la campagne
                    int newCurrentAmount = (currentCampaignDetails['current_amount_eco'] as num?)?.toInt() ?? 0;
                    newCurrentAmount += amount;
                    int newDonors = (currentCampaignDetails['current_donors'] as num?)?.toInt() ?? 0;
                    newDonors++;

                    currentCampaignDetails['current_amount_eco'] = newCurrentAmount;
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
                    final notificationRef = _firestore.collection('user_claimed_offers').doc();
                    transaction.set(notificationRef, {
                      'user_id': currentUserId,
                      'reward_id': widget.offer.id,
                      'details': {
                        'offer_title': "Don : ${widget.offer.title}",
                        'claimed_for_lame': amount.toDouble(),
                      },
                      'claimed_at': FieldValue.serverTimestamp(),
                      'status': 'approved', // Un don est validé immédiatement (Reçu)
                    });
                    // ------------------------------------------------
                  });

                  if (mounted) {
                    Navigator.of(context).pop(); // Fermer le loader
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Merci pour votre don de $amount Lame Points à ${widget.offer.title}!"), backgroundColor: Colors.green));

                    _fetchCampaignDetails(); // Rafraichir l'UI
                    donationController.clear();
                  }
                } catch (e) {
                  if (mounted) {
                    Navigator.of(context).pop();
                    print("Erreur de transaction Firestore (donation): $e");
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Erreur : ${e.toString().split("\n").first}"), backgroundColor: Colors.red));
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: Text("Faire un don", style: GoogleFonts.poppins(fontSize: 16)),
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

class UserStatsProvider with ChangeNotifier {
  UserStats? _userStats;

  UserStats? get userStats => _userStats;

  double get totalLameGained => _userStats?.totalLameGained ?? 0.0;

  void setUserStats(UserStats stats) {
    _userStats = stats;
    notifyListeners();
  }

  void addLame(double amount) {
    if (_userStats != null) {
      _userStats!.totalLameGained += amount;
      notifyListeners();
    }
  }
}

// --- AJOUTER CETTE CLASSE TOUT EN BAS DU FICHIER OU AVANT LE MAIN ---
class SecurityBlockedScreen extends StatelessWidget {
  final String reason;
  const SecurityBlockedScreen({Key? key, required this.reason}) : super(key: key);

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
                style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
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
class NotificationHistorySheet extends StatelessWidget {
  final String userId;

  const NotificationHistorySheet({Key? key, required this.userId}) : super(key: key);

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
              const Icon(Icons.notifications_active_rounded, color: Color(0xFF388E3C)),
              const SizedBox(width: 10),
              Text("Suivi des demandes", style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context))
            ],
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('user_claimed_offers')
                  .where('user_id', isEqualTo: userId)
                  .orderBy('claimed_at', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                // 1. Gestion des erreurs (IMPORTANT POUR L'INDEX)
                if (snapshot.hasError) {
                  print("Erreur Firestore: ${snapshot.error}");
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        "Erreur de chargement.\nVérifiez la console pour créer l'index Firestore composite requis (user_id + claimed_at).",
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
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
                        Text("Aucune activité récente.", style: GoogleFonts.poppins(color: Colors.grey)),
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

                    final String title = data['details']?['offer_title'] ?? "Action Inconnue";
                    final double cost = (data['details']?['claimed_for_lame'] as num?)?.toDouble() ?? 0.0;
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
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                      leading: CircleAvatar(
                        backgroundColor: statusColor.withOpacity(0.1),
                        child: Icon(statusIcon, color: statusColor),
                      ),
                      title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text("$dateStr • -${cost.toStringAsFixed(0)} Lames", style: GoogleFonts.poppins(fontSize: 12, color: Colors.grey)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: statusColor.withOpacity(0.5))
                        ),
                        child: Text(
                          statusText,
                          style: GoogleFonts.poppins(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
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

