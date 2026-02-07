
// MODIFIÉ: Ajout de google_maps_utils pour les calculs de distance et de polyline.
import 'dart:math' as gmaps_utils show Point;
import 'package:flutter_stripe/flutter_stripe.dart' hide Card;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // Pour détecter si on est sur le Web
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
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
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

class DirectionModel {
String? instructions;
DirectionModelDistance? distance;

DirectionModel({this.instructions, this.distance});

DirectionModel.fromJson(Map<String, dynamic> json) {
instructions = json['instructions']?.toString();
distance = (json['distance'] != null)
? DirectionModelDistance.fromJson(json['distance'])
    : null;
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
static const locateMeIcon = 'assets/images/locate_me.png';
static const mapIcon = 'assets/images/map_icon.png';
static const driverCarImage = 'assets/images/car.png';
static const idle = "idle";
static const route = "route";
static const onDestination = "on destination";
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
final Rx<CheatModeStatus> cheatStatus = CheatModeStatus.none.obs;
final RxString cheatWarningMessage = ''.obs;

StreamSubscription<Position>? _positionStreamSubscription;

TravelMode _currentExpectedTravelMode = TravelMode.walking;

static const double maxWalkSpeedKmH = 10.0;
static const double maxBikeSpeedKmH = 50.0;

// MODIFIÉ: Ajout de la vitesse maximale pour le transport en commun
static const double maxTransitSpeedKmH = 120.0; // Vitesse élevée pour bus/train/métro
static const double speedToleranceKmH = 5.0; // Tolérance un peu plus grande
static const int maxWarningCount = 3;
int _speedWarningCount = 0;

@override
void onInit() {
super.onInit();
_startSpeedUpdates();
}

@override
void onClose() {
_positionStreamSubscription?.cancel();
super.onClose();
}

void setExpectedTravelMode(TravelMode mode) {
_currentExpectedTravelMode = mode;
resetCheatStatus();
}

void resetCheatStatus() {
cheatStatus.value = CheatModeStatus.none;
cheatWarningMessage.value = '';
_speedWarningCount = 0;
}

void _startSpeedUpdates() {
const LocationSettings locationSettings = LocationSettings(
accuracy: LocationAccuracy.bestForNavigation,
distanceFilter: 0,
);

_positionStreamSubscription =
Geolocator.getPositionStream(locationSettings: locationSettings)
    .listen((Position position) {
double speedInMs = position.speed >= 0 ? position.speed : 0.0;
double speedInKmH = speedInMs * 3.6;

currentSpeed.value = speedInKmH;
_checkSpeedForCheating(speedInKmH);
});
}

void _checkSpeedForCheating(double speedKmH) {
double limit;

switch (_currentExpectedTravelMode) {
case TravelMode.walking:
limit = maxWalkSpeedKmH;
break;
case TravelMode.bicycling:
limit = maxBikeSpeedKmH;
break;
// MODIFIÉ: Ajout du cas pour le transport en commun
case TravelMode.transit:
limit = maxTransitSpeedKmH;
break;
default:
limit = maxBikeSpeedKmH;
}

if (speedKmH > limit + speedToleranceKmH) {
_speedWarningCount++;
if (_speedWarningCount >= maxWarningCount) {
cheatStatus.value = CheatModeStatus.exceededSpeedCheating;
cheatWarningMessage.value =
'TRICHE DÉTECTÉE: Vitesse excessive pour le mode de transport sélectionné!';
} else {
cheatStatus.value = CheatModeStatus.exceededSpeedWarning;
cheatWarningMessage.value =
'Attention! Vitesse trop élevée pour le mode actuel.';
}
} else if (speedKmH <= limit + speedToleranceKmH / 2) {
if (_speedWarningCount > 0) _speedWarningCount--;
if (_speedWarningCount == 0 &&
cheatStatus.value != CheatModeStatus.none) {
cheatStatus.value = CheatModeStatus.none;
cheatWarningMessage.value = '';
}
}
}
}

class HomeController extends GetxController with GetTickerProviderStateMixin {
late Completer<GoogleMapController> googleMapsController = Completer();
var destination = "".obs;
var distanceLeft = "".obs;
var timeLeft = "".obs;
var mapStatus = Constants.idle.obs;
var arrived = false.obs;
var gettingRoute = false.obs;
var markers = <MarkerId, Marker>{}.obs;
List<LatLng> polylineCoordinates = <LatLng>[].obs;
Set<Polyline> polyline = <Polyline>{}.obs;
AnimationController? _driverAnimationController;
LatLng destinationCoordinates = const LatLng(0, 0);
Animation<double>? animation;
var validationCountdown = Rx<Duration?>(null);
var isNavigatingToStore = false.obs;

var currentTravelMode = TravelMode.walking.obs;
var transitRouteOptions = <Map<String, dynamic>>[].obs;
var showTransitOptions = false.obs;
var activeRouteRawDistanceMeters = 0.0.obs;
var activeRouteRawDurationSeconds = 0.0.obs;
var activeRouteEstimatedGain = 0.obs;
CameraPosition initialCameraPosition = const CameraPosition(
target: LatLng(45.75, 4.85),
zoom: 14.4746,
tilt: 30.0,
);

@override
void onInit() {
super.onInit();
WidgetsBinding.instance.addPostFrameCallback((_) async {
DirectionsService.init(dotenv.env['GOOGLE_MAPS_API_KEY']!);
});
}

@override
void onClose() {
_driverAnimationController?.dispose();
super.onClose();
}

void selectAndDrawTransitRoute(int routeIndex) {
if (routeIndex >= transitRouteOptions.length) return;


polyline.clear();
polylineCoordinates.clear();
Get.find<NavigationController>().transitLegs.clear();

final route = transitRouteOptions[routeIndex];
final leg = route['legs'][0];
final NavigationController navigationController = Get.find();


distanceLeft.value = leg['distance']['text'] ?? "N/A";
timeLeft.value = leg['duration']['text'] ?? "N/A";

// MODIFIÉ: Stockage des valeurs brutes pour le calcul de gain
activeRouteRawDistanceMeters.value = (leg['distance']['value'] as num?)?.toDouble() ?? 0.0;
activeRouteRawDurationSeconds.value = (leg['duration']['value'] as num?)?.toDouble() ?? 0.0;


int stepIndex = 0;
List<LatLng> fullRouteCoordinates = [];

for (var step in leg['steps']) {
List<toolkit.LatLng> decodedStepPoints = toolkit.PolygonUtil.decode(step['polyline']['points']);
List<LatLng> stepPoints = decodedStepPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();
fullRouteCoordinates.addAll(stepPoints);

bool isWalking = step['travel_mode'] == 'WALKING';

PolylineId id = PolylineId('route_step_$stepIndex');
Polyline stepPolyline = Polyline(
polylineId: id,
visible: true,
points: stepPoints,
color: isWalking ? Colors.grey.shade700 : Colors.blueAccent,
width: 5,
patterns: isWalking ? [PatternItem.dot, PatternItem.gap(10)] : [],
);

polyline.add(stepPolyline);
stepIndex++;

MyTransitDetails? transitDetails;
if (step['transit_details'] != null) {
var detailsJson = step['transit_details'];
var lineJson = detailsJson['line'];
var vehicleJson = lineJson['vehicle'];
transitDetails = MyTransitDetails(
arrivalStop: MyStop(name: detailsJson['arrival_stop']['name'], location: LatLng(detailsJson['arrival_stop']['location']['lat'], detailsJson['arrival_stop']['location']['lng'])),
departureStop: MyStop(name: detailsJson['departure_stop']['name'], location: LatLng(detailsJson['departure_stop']['location']['lat'], detailsJson['departure_stop']['location']['lng'])),
line: MyLine(name: lineJson['name'], shortName: lineJson['short_name'], vehicle: MyVehicle(name: vehicleJson['name'], type: vehicleJson['type'], icon: vehicleJson['icon'])),
headsign: detailsJson['headsign'],
numStops: detailsJson['num_stops'],
);
}

navigationController.transitLegs.add(
TransitLeg(
instructions: step['html_instructions'] ?? "Continuez",
travelMode: isWalking ? TravelMode.walking : TravelMode.transit,
startLocation: LatLng(step['start_location']['lat'], step['start_location']['lng']),
endLocation: LatLng(step['end_location']['lat'], step['end_location']['lng']),
distance: step['distance']['text'] ?? "N/A",
duration: step['duration']['text'] ?? "N/A",
polylinePoints: stepPoints,
transitDetails: transitDetails,
)
);
}

polylineCoordinates = fullRouteCoordinates;
showTransitOptions.value = false;

if (mapStatus.value != Constants.onDestination) {
positionCameraToRoute(polyline);
}

update();
}
Future moveMapCamera(LatLng target,
{double zoom = 16, double bearing = 0, double tilt = 30.0}) async {
CameraPosition newCameraPosition =
CameraPosition(target: target, zoom: zoom, bearing: bearing, tilt: tilt);

final GoogleMapController controller = await googleMapsController.future;
controller.animateCamera(CameraUpdate.newCameraPosition(newCameraPosition));
}

Future getMyCurrentLocation() async {
bool serviceEnabled;
LocationPermission permission;

serviceEnabled = await Geolocator.isLocationServiceEnabled();
if (!serviceEnabled) {
return Future.error('Location services are disabled.');
}

permission = await Geolocator.checkPermission();
if (permission == LocationPermission.denied) {
permission = await Geolocator.requestPermission();
if (permission == LocationPermission.denied) {
return Future.error('Location permissions are denied');
}
}

if (permission == LocationPermission.deniedForever) {
return Future.error(
'Location permissions are permanently denied, we cannot request permissions.');
}

return await Geolocator.getCurrentPosition();
}

clearDestination() async {
destination.value = "";
distanceLeft.value = "";
timeLeft.value = "";
mapStatus.value = Constants.idle;
arrived.value = false;
validationCountdown.value = null;
isNavigatingToStore.value = false;
polyline.clear();
polylineCoordinates.clear();
markers.clear();
Get.find<NavigationController>().transitLegs.clear();


transitRouteOptions.clear();
showTransitOptions.value = false;
activeRouteRawDistanceMeters.value = 0.0;
activeRouteRawDurationSeconds.value = 0.0;
activeRouteEstimatedGain.value = 0;
update();
try {
Position position = await getMyCurrentLocation();
moveMapCamera(LatLng(position.latitude, position.longitude), tilt: 0);
} catch (e) {
print("Impossible d'obtenir la localisation: $e");
moveMapCamera(const LatLng(45.75, 4.85), zoom: 10, tilt: 0);
}
Get.find<SpeedController>().resetCheatStatus();
Get.find<SpeedController>().currentSpeed.value = 0.0;
}


void returnToTransitOptions() {

polyline.clear();
polylineCoordinates.clear();
Get.find<NavigationController>().transitLegs.clear();
markers.remove(const MarkerId("destination"));


if (transitRouteOptions.isNotEmpty) {
final recommendedRoute = transitRouteOptions.first;
final leg = recommendedRoute['legs'][0];
distanceLeft.value = leg['distance']['text'] ?? "N/A";
timeLeft.value = leg['duration']['text'] ?? "N/A";
} else {
distanceLeft.value = "";
timeLeft.value = "";
}


showTransitOptions.value = true;
update();
}
Future<void> setDestination(String destinationName, LatLng coordinates,
TravelMode travelMode,
{bool isStore = false}) async {
destination.value = destinationName;
mapStatus.value = Constants.route;
destinationCoordinates = coordinates;
currentTravelMode.value = travelMode;
isNavigatingToStore.value = isStore;

Get.find<SpeedController>().setExpectedTravelMode(travelMode);

await drawRoute(destinationCoordinates);
await addDestinationMarker(destinationCoordinates);
await getTotalDistanceAndTime(destinationCoordinates);
update();
}


// Dans la classe HomeController
drawRoute(LatLng destination, {LatLng? origin, DateTime? departureTime, DateTime? arrivalTime}) async {
polyline.clear();
polylineCoordinates.clear();
Get.find<NavigationController>().transitLegs.clear();
transitRouteOptions.clear();
showTransitOptions.value = false;
update();

if (gettingRoute.value) return;

try {
gettingRoute.value = true;

String originString;
if (origin != null) {
originString = "${origin.latitude},${origin.longitude}";
} else {
Position myCurrentLocation = await getMyCurrentLocation();
originString = "${myCurrentLocation.latitude},${myCurrentLocation.longitude}";
}

String dest = "${destination.latitude},${destination.longitude}";
String mode = currentTravelMode.value.toString().split('.').last;
String apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;

String url;
if (currentTravelMode.value == TravelMode.transit) {
String timeQuery = "";
if (departureTime != null) {
timeQuery = "&departure_time=${(departureTime.millisecondsSinceEpoch / 1000).round()}";
} else if (arrivalTime != null) {
timeQuery = "&arrival_time=${(arrivalTime.millisecondsSinceEpoch / 1000).round()}";
} else {

timeQuery = "&departure_time=${(DateTime.now().millisecondsSinceEpoch / 1000).round()}";
}
url = "https://maps.googleapis.com/maps/api/directions/json?origin=$originString&destination=$dest&mode=$mode&key=$apiKey&language=fr&alternatives=true$timeQuery";
} else {
url = "https://maps.googleapis.com/maps/api/directions/json?origin=$originString&destination=$dest&mode=$mode&key=$apiKey&language=fr";
}

print("--- GOOGLE DIRECTIONS API DEBUG ---");
print("Mode de transport : $mode");
print("URL de la requête : $url");

Dio dio = Dio();
var response = await dio.get(url);

print("Code de statut de la réponse : ${response.statusCode}");

print("--- FIN DU DEBUG ---");

if (response.statusCode == 200 && response.data['status'] == 'OK' && response.data['routes'].isNotEmpty) {
if (currentTravelMode.value == TravelMode.transit) {
final recommendedRoute = response.data['routes'][0];
final leg = recommendedRoute['legs'][0];
distanceLeft.value = leg['distance']['text'] ?? "N/A";
timeLeft.value = leg['duration']['text'] ?? "N/A";

transitRouteOptions.value = List<Map<String, dynamic>>.from(response.data['routes']);
showTransitOptions.value = true;
} else {
var route = response.data['routes'][0];
String overviewPolyline = route['overview_polyline']['points'];
List<toolkit.LatLng> decodedOverviewPoints = toolkit.PolygonUtil.decode(overviewPolyline);
polylineCoordinates = decodedOverviewPoints.map((p) => LatLng(p.latitude, p.longitude)).toList();

PolylineId id = const PolylineId('route');
Polyline myPolyline = Polyline(width: 4, visible: true, polylineId: id, color: Colors.blueAccent, points: polylineCoordinates);
polyline.add(myPolyline);

if (mapStatus.value != Constants.onDestination) {
await positionCameraToRoute(polyline);
}
await getTotalDistanceAndTime(destination);
}
} else {
String errorMessage = response.data['error_message'] ?? "Raison inconnue. Vérifiez les logs.";
String status = response.data['status'] ?? "STATUT_INCONNU";
Get.snackbar('Aucun itinéraire trouvé', 'Raison: $status. $errorMessage', snackPosition: SnackPosition.BOTTOM, duration: const Duration(seconds: 6));
showTransitOptions.value = false; // Assurez-vous de cacher les options si la recherche échoue
}
} catch (e) {
print("Exception dans drawRoute: $e");
Get.snackbar('Erreur Critique', 'Une erreur est survenue lors de la recherche d\'itinéraire. Voir les logs.', snackPosition: SnackPosition.BOTTOM);
showTransitOptions.value = false;
} finally {
gettingRoute.value = false;
update();
}
}

positionCameraToRoute(Set<Polyline> polylines) async {
try {
double minLat = polylines.first.points.first.latitude;
double minLong = polylines.first.points.first.longitude;
double maxLat = polylines.first.points.first.latitude;
double maxLong = polylines.first.points.first.longitude;
for (var poly in polylines) {
for (var point in poly.points) {
if (point.latitude < minLat) minLat = point.latitude;
if (point.latitude > maxLat) maxLat = point.latitude;
if (point.longitude < minLong) minLong = point.longitude;
if (point.longitude > maxLong) maxLong = point.longitude;
}
}
var c = await googleMapsController.future;
c.animateCamera(CameraUpdate.newLatLngBounds(
LatLngBounds(
southwest: LatLng(minLat, minLong),
northeast: LatLng(maxLat, maxLong)),
120));
} catch (e) {}
}

addDestinationMarker(LatLng destination) async {
final Uint8List markerIcon =
await getBytesFromAsset('assets/images/map_icon.png', 100);
MarkerId id = const MarkerId("destination");
Marker destinationMarker = Marker(
markerId: id,
position: destination,
rotation: 0,
visible: true,
icon: BitmapDescriptor.fromBytes(markerIcon));
markers[id] = destinationMarker;
update();
}

addDriverMarker(LatLng oldPos, LatLng newDriverPos) async {
final Uint8List markerIcon =
await getBytesFromAsset(Constants.driverCarImage, 100);
MarkerId id = const MarkerId("driverMarker");

AnimationController animationController = AnimationController(
duration: const Duration(seconds: 3),
vsync: this,
)..repeat(reverse: false);

Tween<double> tween = Tween(begin: 0, end: 1);

animation = tween.animate(animationController)
..addListener(() {
final v = animation!.value;

double lng = v * newDriverPos.longitude + (1 - v) * oldPos.longitude;

double lat = v * newDriverPos.latitude + (1 - v) * oldPos.latitude;

LatLng newPos = LatLng(lat, lng);
Marker newCar = Marker(
markerId: id,
position: newPos,
visible: true,
rotation: 0,
icon: BitmapDescriptor.fromBytes(markerIcon));
markers[id] = newCar;
update();
});
animationController.forward();
}

Future<Uint8List> getBytesFromAsset(String path, int width) async {
ByteData data = await rootBundle.load(path);
ui.Codec codec = await ui.instantiateImageCodec(data.buffer.asUint8List(),
targetWidth: width);
ui.FrameInfo fi = await codec.getNextFrame();
return (await fi.image.toByteData(format: ui.ImageByteFormat.png))!
    .buffer
    .asUint8List();
}

getTotalDistanceAndTime(LatLng destination) async {
if (arrived.value) return;

Position myCurrentLocation = await getMyCurrentLocation();
String origin =
"${myCurrentLocation.latitude},${myCurrentLocation.longitude}";
String destinations = "${destination.latitude},${destination.longitude}";

String mode = currentTravelMode.value.toString().split('.').last;

Dio dio = Dio();
var response = await dio.get(
"https://maps.googleapis.com/maps/api/distancematrix/json?units=metric&origins=$origin&destinations=$destinations&mode=$mode&key=${dotenv.env['GOOGLE_MAPS_API_KEY']}");
var data = response.data;
double distance = 0.0;
double duration = 0.0;
List<dynamic> elements = data['rows'][0]['elements'];

if (elements.isNotEmpty && elements[0]['status'] == 'OK') {
for (var i = 0; i < elements.length; i++) {
distance = distance + elements[i]['distance']['value'];
duration = duration + elements[i]['duration']['value'];
}
if (distance < 10) {
arrived.value = true;
} else {
arrived.value = false;
}
distanceLeft.value = "${(distance / 1000).toStringAsFixed(2)} km";
timeLeft.value = _formatDuration(duration);
} else {
distanceLeft.value = "N/A";
timeLeft.value = "N/A";
print("Distance Matrix API Error: ${elements[0]['status']}");
}
}

String _formatDuration(double seconds) {
final duration = Duration(seconds: seconds.round());
String twoDigits(int n) => n.toString().padLeft(2, "0");
final hours = duration.inHours;
final minutes = twoDigits(duration.inMinutes.remainder(60));

if (hours > 0) {
return "${hours}h ${minutes}min";
}
return "${minutes}min";
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

class NavigationController extends GetxController {
HomeController homeController = Get.find();
SpeedController speedController = Get.find();
late StreamSubscription<Position> positionStream;
var oldLatitude = 0.0.obs;
var oldLongitude = 0.0.obs;
var directions = [].obs;

var isCameraLocked = true.obs;
Timer? _validationTimer;

Function(Challenge challenge)? _onChallengeDestinationReached;
Function()? onStoreDestinationReached;

Function(String commuteType)? onWorkDestinationReached;


var transitLegs = <TransitLeg>[].obs;
var currentLegIndex = 0.obs;
TransitMonitor? _transitMonitor;

// NOUVEAU: États pour la validation des arrêts et la marche
var _currentTransitLegPhase = TransitLegPhase.BeforeBoarding.obs;
bool _validateWalkingLegs = false;

@override
void onInit() {
super.onInit();
// NOUVEAU: Réinitialiser la phase de l'étape de transport lorsque l'index change
ever(currentLegIndex, (_) {
_currentTransitLegPhase.value = TransitLegPhase.BeforeBoarding;
_transitMonitor?.reset();
});
}

void setOnChallengeDestinationReachedCallback(
Function(Challenge challenge) callback) {
_onChallengeDestinationReached = callback;
}

void setOnStoreDestinationReachedCallback(Function() callback) {
onStoreDestinationReached = callback;
}

void setOnWorkDestinationReachedCallback(Function(String commuteType) callback) {
onWorkDestinationReached = callback;
}

Challenge? activeChallenge;
String? activeWorkCommuteType;

// NOUVEAU: Paramètre pour activer la validation de la marche
navigateToDestination({bool validateWalkingLegs = false}) async {
homeController.mapStatus.value = Constants.onDestination;
_validateWalkingLegs = validateWalkingLegs;

const LocationSettings locationSettings = LocationSettings(
accuracy: LocationAccuracy.high,
distanceFilter: 1,
);

speedController.resetCheatStatus();


if (homeController.currentTravelMode.value == TravelMode.transit) {
currentLegIndex.value = 0;
_currentTransitLegPhase.value = TransitLegPhase.BeforeBoarding;
_transitMonitor = TransitMonitor(onWarning: (message) {
Get.snackbar(
'Attention',
message,
snackPosition: SnackPosition.TOP,
backgroundColor: Colors.orangeAccent,
colorText: Colors.white,
duration: const Duration(seconds: 7),
);
});
}

positionStream =
Geolocator.getPositionStream(locationSettings: locationSettings)
    .listen((Position? position) async {
if (position == null) return;

if (_validationTimer?.isActive ?? false) return;

LatLng newPosition = LatLng(position.latitude, position.longitude);
homeController.addDriverMarker(
LatLng(oldLatitude.value, oldLongitude.value), newPosition);
oldLatitude.value = position.latitude;
oldLongitude.value = position.longitude;

if (speedController.cheatStatus.value ==
CheatModeStatus.exceededSpeedCheating) {
stopNavigation(isCheating: true);
return;
}

if (isCameraLocked.value) {
homeController.moveMapCamera(newPosition,
zoom: 18.5, bearing: position.heading, tilt: 60.0);
}


if (homeController.currentTravelMode.value == TravelMode.transit) {
if (transitLegs.isEmpty) return;

TransitLeg currentLeg = transitLegs[currentLegIndex.value];

// NOUVEAU: Logique de validation de la marche et des arrêts de transport
if (currentLeg.isWalking && _validateWalkingLegs) {
// 1. Si c'est une étape de marche et que l'option est activée
speedController.setExpectedTravelMode(TravelMode.walking);
double distanceToEndOfWalk = toolkit.SphericalUtil.computeDistanceBetween(
toolkit.LatLng(newPosition.latitude, newPosition.longitude),
toolkit.LatLng(currentLeg.endLocation.latitude, currentLeg.endLocation.longitude)).toDouble();
if (distanceToEndOfWalk < 15) { // Seuil pour valider la marche
_completeCurrentLeg();
return;
}
} else if (currentLeg.isTransit) {
// 2. Si c'est une étape de transport en commun
speedController.setExpectedTravelMode(TravelMode.transit);

MyStop? departureStop = currentLeg.transitDetails?.departureStop;
MyStop? arrivalStop = currentLeg.transitDetails?.arrivalStop;

if (departureStop?.location == null || arrivalStop?.location == null) {
_completeCurrentLeg(); // Passer si les données de l'arrêt manquent
return;
}

// Machine à états pour la validation de l'embarquement et du débarquement
if (_currentTransitLegPhase.value == TransitLegPhase.BeforeBoarding) {
double distanceToDeparture = toolkit.SphericalUtil.computeDistanceBetween(
toolkit.LatLng(newPosition.latitude, newPosition.longitude),
toolkit.LatLng(departureStop!.location!.latitude, departureStop.location!.longitude)).toDouble();

if (distanceToDeparture < 5) { // Seuil de 5 mètres
_currentTransitLegPhase.value = TransitLegPhase.Onboard;
Get.snackbar(
'Confirmation',
'Vous êtes à l\'arrêt de départ. Le suivi commence.',
snackPosition: SnackPosition.TOP,
backgroundColor: Colors.lightGreen,
);
}
} else if (_currentTransitLegPhase.value == TransitLegPhase.Onboard) {
double distanceToArrival = toolkit.SphericalUtil.computeDistanceBetween(
toolkit.LatLng(newPosition.latitude, newPosition.longitude),
toolkit.LatLng(arrivalStop!.location!.latitude, arrivalStop.location!.longitude)).toDouble();

if (distanceToArrival < 5) { // Seuil de 5 mètres
_completeCurrentLeg();
return;
}
_transitMonitor?.checkPosition(newPosition, currentLeg.polylinePoints);
}
} else {
// 3. Cas par défaut (marche non validée, etc.)
double distanceToEndOfLeg = toolkit.SphericalUtil.computeDistanceBetween(
toolkit.LatLng(newPosition.latitude, newPosition.longitude),
toolkit.LatLng(currentLeg.endLocation.latitude, currentLeg.endLocation.longitude)).toDouble();
if (distanceToEndOfLeg < 15) {
_completeCurrentLeg();
return;
}
}

} else {

await homeController
    .getTotalDistanceAndTime(homeController.destinationCoordinates);

if (homeController.arrived.value) {

if (activeChallenge != null) {
if (activeChallenge!.stayDurationSeconds != null &&
activeChallenge!.stayDurationSeconds! > 0) {
if (_validationTimer == null) {
int duration = activeChallenge!.stayDurationSeconds!;
homeController.validationCountdown.value =
Duration(seconds: duration);
_validationTimer =
Timer.periodic(const Duration(seconds: 1), (timer) {
final newDuration =
homeController.validationCountdown.value! -
const Duration(seconds: 1);
if (newDuration.isNegative) {
timer.cancel();
_validationTimer = null;
homeController.validationCountdown.value = null;
if (_onChallengeDestinationReached != null) {
_onChallengeDestinationReached!(activeChallenge!);
}
stopNavigation();
} else {
homeController.validationCountdown.value = newDuration;
}
});
}
} else {
if (_onChallengeDestinationReached != null) {
_onChallengeDestinationReached!(activeChallenge!);
}
stopNavigation();
}
} else if (homeController.isNavigatingToStore.value) {
if (onStoreDestinationReached != null) {
onStoreDestinationReached!();
}
} else if (activeWorkCommuteType != null) {
if (onWorkDestinationReached != null) {
onWorkDestinationReached!(activeWorkCommuteType!);
}
}
return;
}

bool isOnRoute = getRouteDeviation(newPosition);
if (!isOnRoute || directions.isEmpty) {
await homeController.drawRoute(homeController.destinationCoordinates);
await getDirections(LatLng(position.latitude, position.longitude),
homeController.destinationCoordinates);
}
getNextDirection(LatLng(position.latitude, position.longitude));
}
});
}


void _completeCurrentLeg() {
if (currentLegIndex.value < transitLegs.length - 1) {

currentLegIndex.value++; // Ceci déclenche le "ever" pour réinitialiser la phase
Get.snackbar(
'Étape terminée !',
'Préparez-vous pour la prochaine étape: ${transitLegs[currentLegIndex.value].instructions}',
snackPosition: SnackPosition.TOP,
backgroundColor: Colors.green,
colorText: Colors.white,
);

_transitMonitor?.reset();
} else {

homeController.arrived.value = true;
stopNavigation();
Get.snackbar(
'Destination Atteinte !',
'Vous êtes arrivé(e) à destination.',
snackPosition: SnackPosition.TOP,
backgroundColor: Colors.green,
colorText: Colors.white,
);
}
}

stopNavigation({bool isCheating = false}) async {
_validationTimer?.cancel();
_validationTimer = null;
activeChallenge = null;
activeWorkCommuteType = null;
positionStream.cancel();

_transitMonitor?.dispose();
_transitMonitor = null;

homeController.clearDestination();
isCameraLocked.value = true;
speedController.resetCheatStatus();

if (isCheating) {
Get.snackbar(
'Triche détectée !',
'Votre vitesse est trop élevée pour le mode de transport sélectionné. Le trajet a été annulé.',
snackPosition: SnackPosition.TOP,
backgroundColor: Colors.redAccent,
colorText: Colors.white,
duration: const Duration(seconds: 5),
);
}
}

bool getRouteDeviation(LatLng location) {
List<gmaps_utils.Point<num>> points = [];
List<LatLng> list = homeController.polylineCoordinates.toList();
for (var i = 0; i < list.length; i++) {
points.add(gmaps_utils.Point(list[i].latitude, list[i].longitude));
}
bool r = gmaps_utils.PolyUtils.isLocationOnEdgeTolerance(
gmaps_utils.Point(location.latitude, location.longitude), points, false, 100);

return r;
}

getDirections(LatLng from, LatLng to) async {
String origin = "${from.latitude},${from.longitude}";
String destinations = "${to.latitude},${to.longitude}";
Dio dio = Dio();
var response = await dio.get(
"https://maps.googleapis.com/maps/api/directions/json?units=imperial&origin=$origin&destination=$destinations&key=${dotenv.env['GOOGLE_MAPS_API_KEY']}");
var data = response.data;

final dir = data['routes'][0]['legs'][0]['steps']
    .map((h) => {
"instructions": h['html_instructions'],
"distance": h['start_location']
})
    .toList();
directions.value = [...dir];
update();
}

getNextDirection(LatLng from) {
if (directions.length > 1) {
var closestDirectionIndex = directions.where((direction) =>
SphericalUtils.computeDistanceBetween(
gmaps_utils.Point(from.latitude, from.longitude),
gmaps_utils.Point(direction['distance']['lat'],
direction['distance']['lng'])) <
7);
if (closestDirectionIndex.isNotEmpty) {
directions.removeAt(0);
update();
}
}
}
}

class SpeedometerDisplay extends StatelessWidget {
final SpeedController speedController = Get.find();
final HomeController homeController = Get.find();

SpeedometerDisplay({Key? key}) : super(key: key);

@override
Widget build(BuildContext context) {
return Obx(() {
if (homeController.mapStatus.value != Constants.onDestination) {
return Container();
}

final speed = speedController.currentSpeed.value;
final cheatStatus = speedController.cheatStatus.value;
final cheatMessage = speedController.cheatWarningMessage.value;

Color displayColor = Colors.white;
if (cheatStatus == CheatModeStatus.exceededSpeedWarning) {
displayColor = Colors.orangeAccent;
} else if (cheatStatus == CheatModeStatus.exceededSpeedCheating) {
displayColor = Colors.redAccent;
}

return Positioned(
top: MediaQuery.of(context).padding.top + 80,
left: 0,
right: 0,
child: Column(
children: [
Container(
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
margin: const EdgeInsets.symmetric(horizontal: 20),
decoration: BoxDecoration(
color: Colors.black.withOpacity(0.6),
borderRadius: BorderRadius.circular(10),
border: Border.all(color: displayColor, width: 2),
),
child: Column(
children: [
Text(
'${speed.toStringAsFixed(1)}',
style: TextStyle(
fontSize: 48,
fontWeight: FontWeight.bold,
color: displayColor,
fontFeatures: const [FontFeature.tabularFigures()],
),
),
const Text(
'km/h',
style: TextStyle(
fontSize: 20,
color: Colors.white70,
),
),
],
),
),
if (cheatStatus != CheatModeStatus.none)
Padding(
padding: const EdgeInsets.only(top: 8.0),
child: Container(
padding:
const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
decoration: BoxDecoration(
color: displayColor.withOpacity(0.8),
borderRadius: BorderRadius.circular(8),
),
child: Text(
cheatMessage,
textAlign: TextAlign.center,
style: const TextStyle(
color: Colors.white,
fontSize: 14,
fontWeight: FontWeight.bold,
),
),
),
),
],
),
);
});
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
crossAxisAlignment: CrossAxisAlignment.center,
children: [
// Section gauche : Distance et temps
Row(
children: [
Text(
homeController.distanceLeft.value,
style: TextStyle(
color: Colors.green[900],
fontWeight: FontWeight.bold,
fontSize: 16),
),
const SizedBox(width: 8),
Text(
"(${homeController.timeLeft.value})",
style: const TextStyle(color: Colors.black54, fontSize: 16),
),
],
),

// Section droite : Boutons
if (homeController.mapStatus.value == Constants.onDestination)
// Cas 1 : Navigation en cours
ElevatedButton(
onPressed: () => navigationController.stopNavigation(),
style: ElevatedButton.styleFrom(
backgroundColor: Colors.redAccent,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20)),
padding: const EdgeInsets.symmetric(
horizontal: 20, vertical: 10)),
child: const Text("Arrêter",
style: TextStyle(
color: Colors.white, fontWeight: FontWeight.bold)),
)
else if (isTransitRouteSelected)
// Cas 2 : Itinéraire de transport en commun sélectionné
Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.end,
children: [
ElevatedButton(
onPressed: () =>
navigationController.navigateToDestination(),
style: ElevatedButton.styleFrom(
backgroundColor: Colors.blueAccent,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20)),
padding: const EdgeInsets.symmetric(
horizontal: 20, vertical: 12)),
child: const Text("Commencer le trajet",
style: TextStyle(
color: Colors.white,
fontWeight: FontWeight.bold)),
),
const SizedBox(height: 8),
OutlinedButton(
onPressed: () => homeController.returnToTransitOptions(),
style: OutlinedButton.styleFrom(
foregroundColor: textGrey,
side: const BorderSide(color: Colors.grey),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20)),
padding: const EdgeInsets.symmetric(
horizontal: 16, vertical: 8)),
child: const Text("Retour"),
),
],
)
else
// Cas 3 : Itinéraire normal (marche, vélo) sélectionné
Row(
children: [
OutlinedButton(
onPressed: () => homeController.clearDestination(),
style: OutlinedButton.styleFrom(
foregroundColor: textGrey,
side: const BorderSide(color: Colors.grey),
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20)),
padding: const EdgeInsets.symmetric(
horizontal: 16, vertical: 8)),
child: const Text("Annuler"),
),
const SizedBox(width: 10),
ElevatedButton(
onPressed: () =>
navigationController.navigateToDestination(),
style: ElevatedButton.styleFrom(
backgroundColor: Colors.blueAccent,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(20)),
padding: const EdgeInsets.symmetric(
horizontal: 16, vertical: 8)),
// MODIFIÉ: Texte du bouton changé
child: const Text("Commencer le trajet",
style: TextStyle(
color: Colors.white,
fontWeight: FontWeight.bold)),
),
],
)
],
);
}),
);
}
}
class MapPage extends StatelessWidget {
final Future<void> Function(EcoStore store)? onValidatePurchase;

const MapPage({super.key, this.onValidatePurchase});

@override
Widget build(BuildContext context) {
HomeController homeController = Get.find<HomeController>();
NavigationController navigationController =
Get.find<NavigationController>();

navigationController.setOnStoreDestinationReachedCallback(() {});

return Obx(() => GoogleMap(
mapType: MapType.normal,
initialCameraPosition: homeController.initialCameraPosition,
myLocationEnabled:
homeController.mapStatus.value != Constants.onDestination,
myLocationButtonEnabled: false,
zoomControlsEnabled: false,
markers: homeController.markers.values.toSet(),
polylines: Set<Polyline>.of(homeController.polyline),
onMapCreated: (GoogleMapController controller) async {
homeController.googleMapsController.complete(controller);
Position position = await homeController.getMyCurrentLocation();
homeController.mapStatus.value = Constants.idle;
homeController.moveMapCamera(
LatLng(position.latitude, position.longitude));
},
onCameraMoveStarted: () {
if (homeController.mapStatus.value == Constants.onDestination) {
Get.find<NavigationController>().isCameraLocked.value = false;
}
},
));
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
int rank;

LeaderboardEntry(
{required this.id,
required this.username,
required this.lamePoints,
required this.rank});

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
  final double lamePointMultiplier;
  final double cashbackRate;
  final double? minimumPurchase;
  final List<LoyaltyRule> loyaltyRules;
  final String? ownerId;
  final double currentMonthDebt;
  final double totalAmountSpentByUser;
  final double totalCashbackGiven;

  // OPTIONS
  final bool isPremiumAdBoostEnabled; // Option Pub x2
  final bool isVisibilityBoostEnabled; // Option Dorée + 1% offert

  EcoStore({
    required this.id,
    required this.name,
    required this.address,
    required this.coordinates,
    required this.description,
    this.lamePointMultiplier = 1.0,
    required this.cashbackRate,
    this.minimumPurchase,
    this.ownerId,
    this.currentMonthDebt = 0.0,
    this.totalAmountSpentByUser = 0.0,
    this.totalCashbackGiven = 0.0,
    this.loyaltyRules = const [],
    this.isPremiumAdBoostEnabled = false,
    this.isVisibilityBoostEnabled = false, // Défaut false
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
      name: data['name'] as String? ?? 'Magasin Partenaire',
      address: data['address'] as String? ?? 'Adresse inconnue',
      coordinates: coords,
      description: data['description'] as String? ?? 'Produits variés',
      lamePointMultiplier: (data['lame_point_multiplier'] as num?)?.toDouble() ?? 1.0,
      cashbackRate: UserProfile._parseFirestoreDouble(data['cashback_rate'], 0.02, 'cashback_rate'),
      minimumPurchase: UserProfile._parseFirestoreDouble(data['minimum_purchase'], 0.0, 'minimum_purchase'),
      ownerId: data['owner_id'] as String?,
      currentMonthDebt: UserProfile._parseFirestoreDouble(data['current_month_debt'], 0.0, 'current_month_debt'),
      totalAmountSpentByUser: UserProfile._parseFirestoreDouble(data['totalAmountSpentByUser'], 0.0, 'totalAmountSpentByUser'),
      totalCashbackGiven: UserProfile._parseFirestoreDouble(data['totalCashbackGiven'], 0.0, 'totalCashbackGiven'),
      loyaltyRules: rules,
      isPremiumAdBoostEnabled: data['is_premium_ad_boost_enabled'] as bool? ?? false,
      // NOUVEAU CHAMP LECTURE
      isVisibilityBoostEnabled: data['is_visibility_boost_enabled'] as bool? ?? false,
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

  // Options
  bool _enablePremiumBoost = false;   // Option Pub (Commission variable)
  bool _enableVisibilityBoost = false; // Option Dorée (Coût fixe 5€)

  // Simulation
  double _displayCashback = 5.0;
  double _displayFee = 1.25;
  double _displayTotalPer100 = 6.25;
  double _monthlyFixedCost = 0.0;

  bool _isLoading = false;
  CardFieldInputDetails? _cardDetails;

  @override
  void initState() {
    super.initState();
    _updateCostSimulation();
  }

  void _updateCostSimulation() {
    double rate = double.tryParse(_cashbackController.text) ?? 0.0;

    // Commission sur transaction
    double commissionRate = _enablePremiumBoost ? 0.40 : 0.25;

    // Frais fixes mensuels
    double fixedCost = 0.0;
    if (_enableVisibilityBoost) fixedCost += 5.0;

    setState(() {
      _displayCashback = rate;
      _displayFee = rate * commissionRate;
      _displayTotalPer100 = _displayCashback + _displayFee;
      _monthlyFixedCost = fixedCost;
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
      // 1. Stripe PaymentMethod
      // Ici vous créez la variable nommée "paymentMethod"
      final paymentMethod = await Stripe.instance.createPaymentMethod(
        params: const PaymentMethodParams.card(
          paymentMethodData: PaymentMethodData(),
        ),
      );

      // 2. Cloud Function
      // CORRECTION : Utilisez paymentMethod.id (au lieu de paymentMethodId.id)
      final result = await FirebaseFunctions.instance.httpsCallable('createStripeShop').call({
        'paymentMethodId': paymentMethod.id, // <-- C'était ici l'erreur
        'email': "magasin_${widget.userProfile.id}_${DateTime.now().millisecondsSinceEpoch}@econav.com",
        'name': _nameController.text,
        'isVisibilityBoostEnabled': _enableVisibilityBoost,
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
      final double lat = (location['lat'] as num).toDouble();
      final double lng = (location['lng'] as num).toDouble();

      // 4. Firestore
      await FirebaseFirestore.instance.collection('stores').add({
        'name': _nameController.text.trim(),
        'address': _addressController.text.trim(),
        'coordinates': GeoPoint(lat, lng),
        'latitude': lat,
        'longitude': lng,
        'description': _descController.text.trim(),
        'category': _categoryController.text.trim(),
        'phone': _phoneController.text.trim(),
        'loyalty_rules': [],
        'cashback_rate': double.parse(_cashbackController.text) / 100.0,
        'owner_id': widget.userProfile.id,
        'stripe_customer_id': stripeCustomerId,
        'stripe_meter_id': subscriptionItemId,
        'auto_billing_enabled': true,
        'current_month_debt': _monthlyFixedCost, // On ajoute le coût fixe dès le début (dette initiale du mois)

        // Options sauvegardées
        'is_premium_ad_boost_enabled': _enablePremiumBoost,
        'is_visibility_boost_enabled': _enableVisibilityBoost,

        'created_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Magasin créé avec succès !"), backgroundColor: Colors.green));
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
              const Text("1. Informations", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryGreen)),
              const SizedBox(height: 10),
              TextFormField(controller: _nameController, decoration: const InputDecoration(labelText: "Nom", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Requis" : null),
              const SizedBox(height: 10),
              TextFormField(controller: _addressController, decoration: const InputDecoration(labelText: "Adresse", border: OutlineInputBorder()), validator: (v) => v!.isEmpty ? "Requis" : null),
              // ... Autres champs (Catégorie, Tel, Desc) à ajouter ici si besoin ...

              const SizedBox(height: 30),
              const Text("2. Offre & Visibilité", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: primaryGreen)),
              const SizedBox(height: 10),

              TextFormField(
                controller: _cashbackController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: "Taux Cashback Client (%)", border: OutlineInputBorder(), suffixText: "%"),
                onChanged: (val) => _updateCostSimulation(),
              ),
              const SizedBox(height: 10),

              // Option 1 : Boost Pub (Commission variable)
              SwitchListTile(
                title: const Text("Sponsoriser Boost Pub (Premium)"),
                subtitle: const Text("x2 gains pubs pour vos clients. Attire du monde !\n(Commission majorée à 40%)"),
                value: _enablePremiumBoost,
                activeColor: Colors.purple,
                onChanged: (val) {
                  setState(() => _enablePremiumBoost = val);
                  _updateCostSimulation();
                },
              ),
              const Divider(),

              // Option 2 : Visibilité Gold (Coût fixe 5€/mois)
              SwitchListTile(
                title: const Row(children: [
                  Icon(Icons.star, color: Colors.amber),
                  SizedBox(width: 8),
                  Text("Visibilité Or + 1% Offert"),
                ]),
                subtitle: const Text("Carte en Or sur la map + EcoNav offre 1% de cashback supplémentaire à vos clients.\n(Coût: 5€ / mois)"),
                value: _enableVisibilityBoost,
                activeColor: Colors.amber,
                onChanged: (val) {
                  setState(() => _enableVisibilityBoost = val);
                  _updateCostSimulation();
                },
              ),

              const SizedBox(height: 15),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.blue.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: [
                    const Text("SIMULATION COÛT", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    _buildCostRow("Abonnement fixe :", "${_monthlyFixedCost.toStringAsFixed(2)} € / mois", Colors.black),
                    const Divider(),
                    _buildCostRow("Pour 100€ d'achat :", "", Colors.grey),
                    _buildCostRow("  - Reversé client (base) :", "${_displayCashback.toStringAsFixed(2)} €", Colors.black),
                    _buildCostRow("  - Commission App :", "${_displayFee.toStringAsFixed(2)} €", Colors.black),
                    _buildCostRow("  Total prélevé :", "${_displayTotalPer100.toStringAsFixed(2)} €", Colors.red[800]!, isBold: true),
                    if (_enableVisibilityBoost)
                      Padding(
                        padding: const EdgeInsets.only(top: 5.0),
                        child: Text("Note: Le client recevra ${_displayCashback + 1}% (dont 1% payé par nous).", style: TextStyle(fontSize: 11, color: Colors.green[800], fontStyle: FontStyle.italic)),
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
                child: kIsWeb ? const Text("Carte OK (Web)") : CardField(onCardChanged: (card) => setState(() => _cardDetails = card)),
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
  bool _enablePremiumBoost = false;
  bool _enableVisibilityBoost = false;

  List<LoyaltyRule> _latestRules = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.currentData['name']);
    _descCtrl = TextEditingController(text: widget.currentData['description']);
    _phoneCtrl = TextEditingController(text: widget.currentData['phone'] ?? "");
    _cashbackCtrl = TextEditingController(text: ((widget.currentData['cashback_rate'] ?? 0.05) * 100).toStringAsFixed(0));

    // Init Options
    _enablePremiumBoost = widget.currentData['is_premium_ad_boost_enabled'] as bool? ?? false;
    _enableVisibilityBoost = widget.currentData['is_visibility_boost_enabled'] as bool? ?? false;

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
      // Note: Si l'utilisateur active la visibilité boost ici, il faudrait idéalement appeler une Cloud Function
      // pour mettre à jour l'abonnement Stripe et ajouter les 5€.
      // Ici, on sauvegarde l'état, et on suppose qu'un trigger ou une fonction backend gère la facturation.

      Map<String, dynamic> updates = {
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'cashback_rate': double.parse(_cashbackCtrl.text) / 100.0,
        'is_premium_ad_boost_enabled': _enablePremiumBoost,
        'is_visibility_boost_enabled': _enableVisibilityBoost,
      };

      // Si l'option 5€ est activée et ne l'était pas avant, on pourrait ajouter +5€ à la dette du mois courant immédiatement
      if (_enableVisibilityBoost && !(widget.currentData['is_visibility_boost_enabled'] as bool? ?? false)) {
        updates['current_month_debt'] = FieldValue.increment(5.0);
      }

      await FirebaseFirestore.instance.collection('stores').doc(widget.storeId).update(updates);
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Modifications enregistrées !")));
    } catch(e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Calculs des coûts en temps réel pour l'affichage
    double rate = double.tryParse(_cashbackCtrl.text) ?? 5.0;

    // Commission variable (25% standard, 40% si boost pub activé)
    double commission = _enablePremiumBoost ? 0.40 : 0.25;

    // Coût variable total pour 100€ d'achat
    // Ex: 5€ cashback + (5 * 0.25) = 6.25€
    double totalCost = rate + (rate * commission);

    // Frais fixes (5€ si Visibilité Or activée)
    double fixedCost = _enableVisibilityBoost ? 5.0 : 0.0;

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
              TextFormField(controller: _descCtrl, decoration: const InputDecoration(labelText: "Description"), maxLines: 3),
              const SizedBox(height: 10),
              TextFormField(controller: _phoneCtrl, decoration: const InputDecoration(labelText: "Téléphone")),
              const SizedBox(height: 20),

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
              const Divider(),
              const Text("Offre Commerciale", style: TextStyle(fontWeight: FontWeight.bold)),

              TextFormField(
                controller: _cashbackCtrl,
                decoration: const InputDecoration(labelText: "Taux Cashback (%)", suffixText: "%"),
                keyboardType: TextInputType.number,
                onChanged: (v) => setState((){}), // Rafraîchir l'UI pour mettre à jour les calculs
              ),

              SwitchListTile(
                title: const Text("Boost Pub Premium"),
                subtitle: const Text("Commission majorée à 40%."),
                value: _enablePremiumBoost,
                activeColor: Colors.purple,
                onChanged: (val) => setState(() => _enablePremiumBoost = val),
              ),

              SwitchListTile(
                title: const Text("Visibilité Or + 1% Offert"),
                subtitle: const Text("Carte Dorée + 1% offert par nous.\nCoût fixe: 5€/mois."),
                value: _enableVisibilityBoost,
                activeColor: Colors.amber,
                onChanged: (val) => setState(() => _enableVisibilityBoost = val),
              ),

              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Frais Fixes: ${fixedCost.toStringAsFixed(2)} € / mois", style: const TextStyle(fontWeight: FontWeight.bold)),
                    // C'est ici que l'erreur se produisait, la variable 'totalCost' est maintenant bien définie en haut
                    Text("Coût Variable (pour 100€): ${totalCost.toStringAsFixed(2)} €", style: const TextStyle(fontWeight: FontWeight.bold)),
                    if(_enableVisibilityBoost)
                      Text("Client reçoit: ${(rate+1).toStringAsFixed(1)}% (dont 1% gratuit)", style: TextStyle(fontSize: 12, color: Colors.green[800])),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              ElevatedButton(onPressed: _saveChanges, child: const Text("Enregistrer"))
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
    return Scaffold(
      appBar: AppBar(title: Text("Stats : ${store.name}")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildStatCard("Chiffre d'Affaires généré", "${store.totalAmountSpentByUser.toStringAsFixed(2)} €", Icons.euro, Colors.blue),
            const SizedBox(height: 10),
            _buildStatCard("Cashback reversé aux clients", "${store.totalCashbackGiven.toStringAsFixed(2)} €", Icons.card_giftcard, Colors.green),
            const SizedBox(height: 10),
            _buildStatCard("Facture actuelle (Dette)", "${store.currentMonthDebt.toStringAsFixed(2)} €", Icons.receipt_long, Colors.orange),
            const SizedBox(height: 20),
            // Ici tu pourrais ajouter un graphique plus tard
            const Expanded(child: Center(child: Text("Graphiques détaillés bientôt disponibles...", style: TextStyle(color: Colors.grey)))),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color)),
        title: Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        subtitle: Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
      ),
    );
  }
}
class MerchantDashboard extends StatelessWidget {
  final UserProfile userProfile;

  const MerchantDashboard({Key? key, required this.userProfile})
      : super(key: key);

  void _payDebt(BuildContext context, EcoStore store) {
    // ICI : Intégration Stripe.
    // Pour une version "Gratuite à héberger", vous pouvez utiliser un lien de paiement Stripe généré dynamiquement
    // ou rediriger vers une page web.
    // Exemple simple : Afficher une alerte.

    showDialog(
      context: context,
      builder: (ctx) =>
          AlertDialog(
            title: const Text("Paiement Stripe"),
            content: Text(
                "Vous allez être redirigé vers Stripe pour payer la somme de ${store
                    .currentMonthDebt.toStringAsFixed(2)}€."),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: const Text("Annuler")),
              ElevatedButton(
                  onPressed: () async {
                    // Simulation de succès de paiement
                    Navigator.pop(ctx);

                    // Remise à zéro de la dette (Dans la réalité, faire ça via un Webhook Stripe sécurisé)
                    await FirebaseFirestore.instance.collection('stores').doc(
                        store.id).update({
                      'last_payment_date': FieldValue.serverTimestamp(),
                      'last_payment_amount': store.currentMonthDebt,
                      'current_month_debt': 0.0, // Reset dette
                    });

                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Paiement reçu ! Merci."),
                        backgroundColor: Colors.green));
                  },
                  child: const Text("Payer maintenant")
              ),
            ],
          ),
    );
  }

  Future<void> _simulateTestSale(BuildContext context, String storeId) async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Simulation d'envoi à Stripe..."),
              duration: Duration(seconds: 1)));

      // --- 1. LES FAUX CHIFFRES ---
      double fakePurchase = 50.00; // Achat de 50€
      double fakeCashback = 2.00; // 2€ donnés au client
      double commissionRatio = 1.25;

      // Ce que le magasin doit payer (2€ * 1.25 = 2.50€)
      double amountToBill = fakeCashback * commissionRatio;
      int amountInCents = (amountToBill * 100)
          .round(); // 250 unités pour Stripe

      // --- 2. RÉCUPÉRER L'ID COMPTEUR (METER ID) ---
      // On va le chercher frais dans la base de données
      DocumentSnapshot storeDoc = await FirebaseFirestore.instance.collection(
          'stores').doc(storeId).get();
      String? meterId = storeDoc.get('stripe_meter_id');

      if (meterId == null) {
        throw Exception(
            "Ce magasin n'a pas d'ID Compteur (meter_id). Recréez le magasin.");
      }

      // --- 3. ENVOYER À STRIPE (CLOUD FUNCTION) ---
      final result = await FirebaseFunctions.instance.httpsCallable(
          'reportCommission').call({
        'subscriptionItemId': meterId,
        'amountInCents': amountInCents,
      });

      // --- 4. METTRE À JOUR L'AFFICHAGE (FIRESTORE) ---
      // On ajoute 2.50€ à la dette locale pour voir le rouge augmenter
      await FirebaseFirestore.instance.collection('stores').doc(storeId).update(
          {
            'current_month_debt': FieldValue.increment(amountToBill),
            'totalAmountSpentByUser': FieldValue.increment(fakePurchase),
          });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                "Succès ! Envoye de +${amountInCents} unités à Stripe."),
            backgroundColor: Colors.green));
      }
    } catch (e) {
      print(e);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erreur: $e"), backgroundColor: Colors.red));
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
            .where('owner_id', isEqualTo: userProfile.id)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData)
            return const Center(child: CircularProgressIndicator());

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
                          MaterialPageRoute(builder: (_) =>
                              AddStoreScreen(userProfile: userProfile))),
                      child: const Text("Ajouter mon magasin")
                  ),
                ],
              ),
            );
          }

          // Liste des magasins possédés par l'user
          return ListView(
            padding: const EdgeInsets.all(16),
            children: snapshot.data!.docs.map((doc) {
              // Récupération des données brutes (Map) pour l'édition et typées (EcoStore) pour l'affichage
              Map<String, dynamic> rawData = doc.data() as Map<String, dynamic>;
              EcoStore store = EcoStore.fromFirestore(
                  doc as DocumentSnapshot<Map<String, dynamic>>);

              return Card(
                elevation: 4,
                margin: const EdgeInsets.only(bottom: 20),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- EN-TÊTE DU MAGASIN ---
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                                Icons.store, size: 30, color: Colors.blue),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(store.name, style: const TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Text(store.address,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.grey),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis
                                ),
                              ],
                            ),
                          ),
                        ],
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
                                const Text("Facture en cours (Mois)",
                                    style: TextStyle(
                                        fontWeight: FontWeight.w500)),
                                Text(
                                  "${store.currentMonthDebt.toStringAsFixed(
                                      2)} €",
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: store.currentMonthDebt > 0 ? Colors
                                          .orange : Colors.green
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                const Icon(Icons.check_circle, size: 14,
                                    color: Colors.green),
                                const SizedBox(width: 5),
                                Text("Prélèvement auto. actif via Stripe",
                                    style: TextStyle(fontSize: 11,
                                        color: Colors.green[800])),
                              ],
                            )
                          ],
                        ),
                      ),

                      const SizedBox(height: 20),

                      // --- NOUVEAUX BOUTONS D'ACTION (Modifier / Stats) ---
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.blue),
                            tooltip: "Modifier Infos",
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditStoreScreen(
                              // CORRECTION : On passe storeId et currentData
                                storeId: store.id,
                                currentData: rawData
                            )
                            ))
                          ),
                          IconButton(
                            icon: const Icon(Icons.bar_chart, color: Colors.purple),
                            tooltip: "Statistiques",
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StoreStatsScreen(store: store))),

                          ),
                        ],
                      ),

                      // --- ZONE DE TEST DÉVELOPPEUR (À retirer en prod) ---
                      const SizedBox(height: 20),
                      const Divider(),
                      Center(
                        child: Text("ZONE DE TEST (DEV ONLY)",
                            style: TextStyle(fontSize: 10,
                                color: Colors.grey[400],
                                fontWeight: FontWeight.bold)
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
                      // ----------------------------------------------------
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
            builder: (_) => AddStoreScreen(userProfile: userProfile))),
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


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("Firebase initialisé avec succès!");
    await initializeDateFormatting('fr_FR', null);

    // --- AJOUTE CE BLOC ICI ---
    // Remplace par ta VRAIE clé qui commence par pk_test_
    Stripe.publishableKey = "pk_test_51Sf3KIJmX9VkIHA6dTDUanwaG5w8v6wwdqryF4e42PDjd2yR1RkVc5SUay2fOQVDb1vkByBW9CBFejiryPtDcFqG00sCZ9K4gE";
    await Stripe.instance.applySettings(); // Important pour le Web
    // --------------------------

  } catch (e) {
    print("Erreur lors de l'initialisation : $e");
  }

  Get.put(HomeController());
  Get.put(SpeedController());
  Get.put(NavigationController());

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
Query<Map<String, dynamic>> query = _firestore
    .collection('users')
    .orderBy('lame_points', descending: true)
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
Text(
'${entry.lamePoints}',
style: const TextStyle(
fontWeight: FontWeight.bold,
color: accentGold,
fontSize: 16,
),
),
const SizedBox(width: 4),
const Icon(Icons.eco_rounded, color: accentGold, size: 20),
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

class _MainScreenControllerState extends State<MainScreenController> {
int _currentIndex = 0;
UserProfile? _userProfile;
WeatherData? _currentWeatherData;
List<EcoStore> _ecoStores = [];
StoreTripData? _pendingStoreTripData;
ChallengeTripData? _pendingChallengeTripData; // CORRIGÉ : Ajout de la déclaration manquante
late HomeController _homeController;
late NavigationController _navigationController;
late SpeedController _speedController;

String? get _currentUserId => _firebaseAuth.currentUser?.uid;

@override
void initState() {
super.initState();
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
_fetchWeather();
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
@override
void dispose() {
super.dispose();
}

Future<void> _fetchUserProfileData() async {
if (_currentUserId == null) return;
try {
final userDoc =
await _firestore.collection('users').doc(_currentUserId).get();
if (userDoc.exists) {
UserProfile profile = UserProfile.fromFirestore(userDoc);
UserProfile updatedProfile = await _processDailyLogin(profile);
if (mounted) {
setState(() => _userProfile = updatedProfile);
}
} else {
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
DateTime today = DateTime(now.year, now.month, now.day);
DateTime? lastLoginDateTime = profile.lastLoginDate?.toDate();
DateTime? lastLoginDay = lastLoginDateTime != null
? DateTime(
lastLoginDateTime.year, lastLoginDateTime.month, lastLoginDateTime.day)
    : null;

Map<String, dynamic> updates = {};
UserProfile tempUpdatedProfile = profile;

bool isNewDayLoginOrNewUser =
isNewUser || lastLoginDay == null || lastLoginDay.isBefore(today);

if (isNewDayLoginOrNewUser) {
int newConsecutiveLogins;
if (isNewUser || lastLoginDay == null) {
newConsecutiveLogins = 1;
} else if (today.difference(lastLoginDay).inDays == 1) {
newConsecutiveLogins = profile.consecutiveLogins + 1;
} else {


newConsecutiveLogins =
1;
}

int lamesToAdd = 1;
int paliersActuels =
(newConsecutiveLogins / LOGIN_STREAK_DAYS_PER_PALIER).floor();
double bonusSerie = (paliersActuels * LOGIN_STREAK_BONUS_PER_PALIER)
    .clamp(0.0, MAX_LOGIN_STREAK_BONUS_TOTAL);
double newNextLevelBoost = 1.0 + bonusSerie;

updates['lame_points'] = FieldValue.increment(lamesToAdd);
updates['consecutive_logins'] = newConsecutiveLogins;
updates['last_login_date'] = FieldValue.serverTimestamp();
updates['next_level_boost'] = newNextLevelBoost;

// NOUVEAU: Ajout à l'historique
_firestore
    .collection('users')
    .doc(profile.id)
    .collection('lame_history')
    .add({
'amount': lamesToAdd,
'source': 'Connexion quotidienne',
'timestamp': FieldValue.serverTimestamp(),
});

tempUpdatedProfile = tempUpdatedProfile.copyWith(
lamePoints: tempUpdatedProfile.lamePoints + lamesToAdd,
consecutiveLogins: newConsecutiveLogins,
lastLoginDate: () => Timestamp.fromDate(now),
nextLevelBoost: newNextLevelBoost);
}


DateTime? lastResetDate = profile.lastMonthlyAllowanceReset?.toDate();
if (lastResetDate == null ||
lastResetDate.month != now.month ||
lastResetDate.year != now.year) {
updates['monthly_work_absence_allowance'] = 3;
updates['last_monthly_allowance_reset'] = FieldValue.serverTimestamp();
tempUpdatedProfile = tempUpdatedProfile.copyWith(
monthlyWorkAbsenceAllowance: 3,
lastMonthlyAllowanceReset: () => Timestamp.now(),
);
print("Work commute allowance reset for new month.");
}

if (updates.isNotEmpty) {
updates['updated_at'] = FieldValue.serverTimestamp();
try {
await _firestore.collection('users').doc(profile.id).update(updates);
print("Daily login processed. Updates: $updates");
} catch (e) {
print("Error processing daily login update: $e");
return profile;
}
}

return tempUpdatedProfile;
}

// MODIFIÉ: Centralisation de l'ajout de points ET de l'historique
void _addLame(int amountToAdd, {String? source}) async {
if (_userProfile == null || _currentUserId == null || amountToAdd <= 0) return;

final sourceText = source ?? 'Inconnue';

UserProfile? oldProfileState = _userProfile;
if (mounted) {
setState(() {
_userProfile = _userProfile!.copyWith(lamePoints: _userProfile!.lamePoints + amountToAdd);
});
}

try {
WriteBatch batch = _firestore.batch();

// Mettre à jour le total
DocumentReference userRef = _firestore.collection('users').doc(_currentUserId!);
batch.update(userRef, {
'lame_points': FieldValue.increment(amountToAdd),
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
  pendingChallengeTrip: challengeTripDataForHomeScreen, // MODIFIÉ: Passer les données du défi
onProfileButtonPressed: _openProfile,
onShowLameHistory: _showLameHistory, // NOUVEAU
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
),
],
),
bottomNavigationBar: BottomNavigationBar(
currentIndex: _currentIndex,
onTap: (index) {
if (mounted) setState(() => _currentIndex = index);
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

  @override
  void initState() {
    super.initState();
    _fetchLocalPoisAsChallenges();
    _checkAndRefreshChallenges(); // NOUVELLE LOGIQUE

    _updateUserLocationForSorting();

    widget.navigationController
        .setOnChallengeDestinationReachedCallback((completedChallenge) async {
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

  Future<void> _checkAndRefreshChallenges() async {
    // Simulation de persistance locale (SharedPreferences serait idéal ici)
    // Pour cet exemple, on utilise Firestore pour stocker la date de dernière update de l'user

    final userDoc = await _firestore.collection('user_stats').doc(
        widget.currentUserId).get();
    DateTime? lastUpdate;
    if (userDoc.exists &&
        userDoc.data()!.containsKey('last_challenges_refresh')) {
      lastUpdate =
          (userDoc.data()!['last_challenges_refresh'] as Timestamp).toDate();
    }

    final now = DateTime.now();
    bool needsRefresh = lastUpdate == null || now
        .difference(lastUpdate)
        .inDays >= 14;

    if (needsRefresh) {
      print("Rafraîchissement des défis (14 jours passés)...");
      await _fetchLocalPoisAsChallenges(forceRefresh: true);

      // Mise à jour de la date
      await _firestore.collection('user_stats').doc(widget.currentUserId).set({
        'last_challenges_refresh': FieldValue.serverTimestamp()
      }, SetOptions(merge: true));
    } else {
      // Chargement normal sans forcer l'aléatoire complet
      await _fetchLocalPoisAsChallenges(forceRefresh: false);
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


  Future<int> _calculateDynamicReward(Challenge challenge,
      TravelType travelType) async {
    // Si le défi n'a pas de coordonnées, on retourne la récompense de base définie dans l'objet.
    if (challenge.latitude == null || challenge.longitude == null) {
      return challenge.rewardLame;
    }

    try {
      // 1. Récupération de la position actuelle
      final userPos = await widget.homeController.getMyCurrentLocation();

      // 2. Appel à l'API Google Directions pour obtenir la distance et la durée réelles
      final directionsService = DirectionsService();

      // Mapping du type de transport interne vers l'API Google
      final gmTravelMode = travelType == TravelType.walk
          ? TravelMode.walking
          : travelType == TravelType.bike
          ? TravelMode.bicycling
          : TravelMode.transit;

      final request = DirectionsRequest(
        origin: "${userPos.latitude},${userPos.longitude}",
        destination: "${challenge.latitude},${challenge.longitude}",
        travelMode: gmTravelMode,
      );

      double distanceKm = 0.0;
      double durationMinutes = 0.0;

      // On utilise un Completer ou on attend la callback (ici simplifié avec await implicite sur le service si dispo, sinon via callback)
      // Note: Dans ta structure actuelle, DirectionsService utilise un callback. On simule l'attente.
      await directionsService.route(
          request, (DirectionsResult response, status) {
        if (status == DirectionsStatus.ok && response.routes!.isNotEmpty) {
          final leg = response.routes!.first.legs!.first;
          distanceKm =
          (leg.distance!.value! / 1000.0); // Convertir mètres en km
          durationMinutes =
          (leg.duration!.value! / 60.0); // Convertir secondes en minutes
        }
      });

      // Si l'API échoue ou renvoie 0 (ex: trop proche), on estime à vol d'oiseau
      if (distanceKm == 0) {
        double distMeters = toolkit.SphericalUtil.computeDistanceBetween(
            toolkit.LatLng(userPos.latitude, userPos.longitude),
            toolkit.LatLng(challenge.latitude!, challenge.longitude!)
        ).toDouble();
        distanceKm = distMeters / 1000.0;
        // Estimation grossière : 5km/h à pied
        durationMinutes = (distanceKm / 5.0) * 60;
      }

      // 3. Application de la Formule de l'Effort
      // Formule : Effort = (Distance_km * 5.0) + (Dénivelé_m * 0.2) + (Durée_min * 0.5)

      // Note: L'API Directions standard ne renvoie pas le dénivelé.
      // Il faudrait l'API Elevation. On met 0 par défaut pour respecter la formule sans planter.
      double denivele_m = 0.0;

      double effortBase = (distanceKm * 5.0) + (denivele_m * 0.2) +
          (durationMinutes * 0.5);

      // 4. Multiplicateurs selon le mode de transport
      double transportMultiplier = 1.0;
      switch (travelType) {
        case TravelType.walk:
          transportMultiplier = 1.0; // Base
          break;
        case TravelType.bike:
          transportMultiplier = 1.2; // Prime à l'effort physique
          break;
        case TravelType.transit:
          transportMultiplier = 0.8; // Effort moindre (mais valorisation éco)
          break;
      }

      double totalReward = effortBase * transportMultiplier;

      // 5. Multiplicateurs liés à la difficulté du défi (Visites multiples / Durée sur place)
      int visitCount = challenge.visitCount ?? 1;
      int stayDurationMinutes = (challenge.stayDurationSeconds ?? 0) ~/ 60;

      double bonusDefiMultiplier = 1.0;
      if (visitCount > 1) {
        bonusDefiMultiplier += (visitCount - 1) * 0.1; // +10% par visite supp.
      }
      if (stayDurationMinutes > 0) {
        bonusDefiMultiplier +=
            stayDurationMinutes * 0.05; // +5% par minute restée
      }

      totalReward *= bonusDefiMultiplier;

      // 6. Boost Météo (x1.5)
      // Condition : Pluie, Froid (< 2°C) ou Forte chaleur (> 32°C)
      final weather = widget.weatherData;
      if (weather != null) {
        // Codes WMO : 51-67 (bruine/pluie), 71-77 (neige), 80-82 (averses), 95-99 (orage)
        bool isRainingOrSnowing = weather.weatherCode >= 51;
        bool isCold = weather.temperature < 2.0;
        bool isHot = weather.temperature > 32.0;

        if (isRainingOrSnowing || isCold || isHot) {
          totalReward *= 1.5;
        }
      }

      // 7. Boost Publicité (x1.2)
      if (widget.userProfile.isAdBoostCurrentlyActive) {
        totalReward *= 1.2;
      }

      // Sécurité pour éviter 0 si le défi a une récompense fixe mais que le GPS fail
      if (totalReward < 1 && challenge.rewardLame > 0) {
        return challenge.rewardLame;
      }

      // Plafonnement de sécurité (pour éviter les glitchs GPS donnant 10000 points)
      // On limite à 500 points max par trajet unitaire généré dynamiquement
      return min(totalReward.round(), 500);
    } catch (e) {
      print("Erreur calcul récompense dynamique: $e");
      // Fallback sur la valeur par défaut
      return challenge.rewardLame;
    }
  }

  Future<void> _fetchLocalPoisAsChallenges({bool forceRefresh = false}) async {
    // Empêcher les appels multiples simultanés
    if (_isLoadingLocalPois) return;

    if (!mounted) return;

    // Si on force le rafraîchissement (14 jours passés), on vide la liste actuelle
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
      // 1. Récupérer la position
      Position position = await widget.homeController.getMyCurrentLocation();
      final double lat = position.latitude;
      final double lng = position.longitude;

      // Rayon de recherche (ex: 5km pour avoir des défis proches)
      const double radius = 5000;

      final String apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;
      // Types de lieux intéressants pour des défis
      final String types = 'park|museum|tourist_attraction|church|library|stadium|university';

      final String url = 'https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=$radius&type=$types&key=$apiKey';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List<dynamic> results = data['results'] ?? [];

        List<Challenge> newLocalPoiChallenges = [];
        int challengeCounter = 0;
        final _random = Random();

        // Récupérer l'état des défis déjà existants pour cet utilisateur (pour ne pas écraser la progression)
        final userChallengesSnapshot = await _firestore
            .collection('user_challenges')
            .where('user_id', isEqualTo: widget.currentUserId)
            .get();

        final Map<String, dynamic> existingUserChallengeData = {
          for (var doc in userChallengesSnapshot.docs) doc.id: doc.data()
        };

        // Templates de défis aléatoires
        final List<Map<String, dynamic>> challengeTemplates = [
          {
            'type': ChallengeType.localPoiVisit,
            'title_prefix': 'Exploration :',
            'reward_base': 30,
            'visit_count': 1,
            'stay_duration_seconds': 0,
            'desc': "Rends-toi simplement à ce lieu."
          },
          {
            'type': ChallengeType.localPoiVisit,
            'title_prefix': 'Habitué de :',
            'reward_base': 80,
            'visit_count': 3, // Il faut y aller 3 fois
            'stay_duration_seconds': 0,
            'desc': "Rends-toi 3 fois à ce lieu pour valider le défi."
          },
          {
            'type': ChallengeType.localPoiVisit,
            'title_prefix': 'Pause détente à :',
            'reward_base': 50,
            'visit_count': 1,
            'stay_duration_seconds': 600, // 10 minutes
            'desc': "Rends-toi à ce lieu et restes-y 10 minutes."
          },
        ];

        // Mélanger les résultats pour avoir de la variété si beaucoup de lieux
        results.shuffle();

        for (var place in results) {
          // Limiter le nombre de défis POI affichés (ex: 10 max)
          if (challengeCounter >= 10) break;

          String placeId = place['place_id'];
          String name = place['name'] ?? 'Lieu Mystère';
          double placeLat = place['geometry']['location']['lat'];
          double placeLng = place['geometry']['location']['lng'];

          // ID unique combinant l'ID utilisateur et l'ID du lieu pour la persistance locale
          String challengeDocId = 'poi_$placeId';
          String userChallengeFullId = '${widget
              .currentUserId}_$challengeDocId';

          // Vérifier si ce défi existe déjà dans la progression de l'utilisateur
          Map<String, dynamic>? existingProgress;
          if (existingUserChallengeData.containsKey(userChallengeFullId)) {
            existingProgress = existingUserChallengeData[userChallengeFullId];
          }

          // Si le défi est déjà complété depuis plus de 14 jours, on le réinitialise (logique de réactualisation)
          if (existingProgress != null) {
            Timestamp? lastCompleted = existingProgress['last_completed_at'];
            if (lastCompleted != null) {
              DateTime completedDate = lastCompleted.toDate();
              if (DateTime
                  .now()
                  .difference(completedDate)
                  .inDays < 14) {
                // Défi complété récemment, on ne le propose plus ou on le montre comme fini
                // Pour l'instant, on ignore pour laisser place à d'autres
                continue;
              }
              // Si > 14 jours, on le repropose (réactualisation)
            }
          }

          // Choix aléatoire d'un type de défi pour ce lieu
          final template = challengeTemplates[_random.nextInt(
              challengeTemplates.length)];

          final generatedChallenge = Challenge(
            id: challengeDocId,
            title: "${template['title_prefix']} $name",
            rewardText: template['desc'],
            rewardLame: template['reward_base'],
            // Valeur indicative, recalculée dynamiquement
            totalDurationSeconds: 14 * 24 * 3600,
            // Expire dans 14 jours
            createdAt: Timestamp.now(),
            type: template['type'],
            totalSteps: template['visit_count'],
            latitude: placeLat,
            longitude: placeLng,
            googlePlaceId: placeId,
            visitCount: template['visit_count'],
            stayDurationSeconds: template['stay_duration_seconds'],
            // Récupération de l'état existant s'il y en a un
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

        // Tri par distance par rapport à l'utilisateur
        newLocalPoiChallenges.sort((a, b) {
          final distA = toolkit.SphericalUtil.computeDistanceBetween(
            toolkit.LatLng(lat, lng),
            toolkit.LatLng(a.latitude ?? 0, a.longitude ?? 0),
          );
          final distB = toolkit.SphericalUtil.computeDistanceBetween(
            toolkit.LatLng(lat, lng),
            toolkit.LatLng(b.latitude ?? 0, b.longitude ?? 0),
          );
          return distA.compareTo(distB);
        });

        if (mounted) {
          setState(() {
            _localPoiChallenges = newLocalPoiChallenges;
          });
        }
      } else {
        print("Erreur API Places: ${response.statusCode}");
        _localPoiError = "Erreur chargement lieux proches.";
      }
    } catch (e) {
      print("Exception fetching POIs: $e");
      _localPoiError = "Problème de connexion ou de localisation.";
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocalPois = false;
        });
      }
    }
  }

  Future<void> _handleChallengeAction(Challenge challenge,
      ChallengeStatus newStatus,
      {int? newStep,
        String? selectedStore,
        String? proofIdentifier,
        String? ocrResultText,
        bool? isProofValid}) async {
    Challenge updatedChallenge = challenge.copyWith(
      status: newStatus,
      currentStep: newStep ?? challenge.currentStep,
      selectedStore: () => selectedStore ?? challenge.selectedStore,
      proofImageIdentifier: () =>
      proofIdentifier ?? challenge.proofImageIdentifier,
      ocrResultText: () => ocrResultText ?? challenge.ocrResultText,
      isProofValid: () => isProofValid ?? challenge.isProofValid,
    );

    if (newStatus == ChallengeStatus.inProgress &&
        updatedChallenge.startedAtUser == null) {
      updatedChallenge =
          updatedChallenge.copyWith(startedAtUser: () => Timestamp.now());
    }

    bool challengeCompleted = false;
    if (updatedChallenge.type == ChallengeType.visitMultiple ||
        updatedChallenge.type == ChallengeType.localPoiVisit) {
      challengeCompleted = updatedChallenge.currentStep >=
          (updatedChallenge.visitCount ?? updatedChallenge.totalSteps);
    } else if (updatedChallenge.type == ChallengeType.purchaseScanProof ||
        updatedChallenge.type == ChallengeType.partnerStoreVisit) {
      challengeCompleted = (proofIdentifier != null && (isProofValid ?? false));
    }

    if (challengeCompleted &&
        updatedChallenge.status != ChallengeStatus.rewardClaimed) {
      updatedChallenge =
          updatedChallenge.copyWith(
              status: ChallengeStatus.completedPendingReward);
    }

    int rewardAmount = challenge.rewardLame;
    if (newStatus == ChallengeStatus.rewardClaimed) {
// MODIFIÉ: On ne peut pas connaître le mode de transport ici, on utilise une valeur par défaut.
// Le calcul idéal se ferait au moment du lancement.
      rewardAmount = await _calculateDynamicReward(challenge, TravelType.walk);
    }

    await widget.onUpdateUserChallenge(updatedChallenge, rewardAmount);

    if (updatedChallenge.type == ChallengeType.localPoiVisit &&
        (updatedChallenge.status == ChallengeStatus.rewardClaimed ||
            updatedChallenge.status == ChallengeStatus.expired)) {
      _fetchLocalPoisAsChallenges();
    }
    if (mounted) setState(() {});
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
    } catch (e) {
      print(
          "Erreur lors de la récupération de la localisation pour le tri : $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: defisScreenBackground,
      // 1. Écoute des défis globaux (Firebase/Admin)
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _firestore
            .collection('challenges')
            .orderBy('created_at', descending: true)
            .snapshots(),
        builder: (context, challengeListSnapshot) {
          if (challengeListSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: primaryGreen));
          }
          if (challengeListSnapshot.hasError) {
            return Center(child: Text("Erreur: ${challengeListSnapshot.error}", style: const TextStyle(color: Colors.red)));
          }

          final firebaseChallenges = challengeListSnapshot.data?.docs
              .map((doc) => Challenge.fromFirestore(doc))
              .toList() ?? [];

          // 2. Écoute de la progression de l'utilisateur (UserChallenges)
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _firestore
                .collection('user_challenges')
                .where('user_id', isEqualTo: widget.currentUserId)
                .snapshots(),
            builder: (context, userChallengesProgressSnapshot) {
              if (userChallengesProgressSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: primaryGreen));
              }
              if (userChallengesProgressSnapshot.hasError) {
                return Center(child: Text("Erreur progression: ${userChallengesProgressSnapshot.error}", style: const TextStyle(color: Colors.red)));
              }

              final Map<String, DocumentSnapshot<Map<String, dynamic>>> userProgressSnapshotsMap = {
                for (var doc in userChallengesProgressSnapshot.data!.docs) doc.id: doc
              };

              // 3. Fusion des Défis (Admin + Locaux générés)
              List<Challenge> challengesToDisplay = [];

              for (var challengeBase in [...firebaseChallenges, ..._localPoiChallenges]) {
                final userChallengeDocId = '${widget.currentUserId}_${challengeBase.id}';
                final userChallengeSnapshot = userProgressSnapshotsMap[userChallengeDocId];

                Challenge challengeInstance;

                // Si c'est un défi POI (Local Google Maps)
                if (challengeBase.id.startsWith('poi_')) {
                  challengeInstance = challengeBase.copyWith(
                    userChallengeDocId: () => userChallengeSnapshot?.id,
                    status: userChallengeSnapshot != null &&
                        userChallengeSnapshot.exists &&
                        userChallengeSnapshot.data() != null &&
                        userChallengeSnapshot.data()!['status'] != null
                        ? ChallengeStatus.values.firstWhere(
                          (e) => e.toString() == 'ChallengeStatus.${userChallengeSnapshot.data()!['status']}',
                      orElse: () => ChallengeStatus.notStarted,
                    )
                        : ChallengeStatus.notStarted,
                    currentStep: UserProfile._parseFirestoreInt(userChallengeSnapshot?.data()?['current_step'], 0, 'current_step'),
                    startedAtUser: () => userChallengeSnapshot?.data()?['started_at'] as Timestamp?,
                    proofImageIdentifier: () => userChallengeSnapshot?.data()?['proof_image_identifier'] as String?,
                    ocrResultText: () => userChallengeSnapshot?.data()?['ocr_result_text'] as String?,
                    isProofValid: () => userChallengeSnapshot?.data()?['is_proof_valid'] as bool?,
                  );
                } else {
                  // Si c'est un défi Firebase standard
                  challengeInstance = Challenge.fromFirestore(
                    challengeListSnapshot.data!.docs.firstWhere((doc) => doc.id == challengeBase.id),
                    userChallengeSnapshot: userChallengeSnapshot,
                  );
                }

                // Masquer les défis terminés il y a trop longtemps (si applicable)
                if (challengeInstance.status == ChallengeStatus.rewardClaimed ||
                    challengeInstance.status == ChallengeStatus.expired) {
                  final lastCompletedAt = userChallengeSnapshot?.data()?['last_completed_at'] as Timestamp?;
                  if (challengeInstance.isBlockedForUser(lastCompletedAt)) {
                    continue;
                  }
                }
                challengesToDisplay.add(challengeInstance);
              }

              // 4. Tri par distance
              challengesToDisplay.sort((a, b) {
                if (_lastKnownUserLocation == null) return 0;
                // On privilégie le tri des POI locaux
                if (a.type == ChallengeType.localPoiVisit && b.type == ChallengeType.localPoiVisit) {
                  final distA = toolkit.SphericalUtil.computeDistanceBetween(
                    toolkit.LatLng(_lastKnownUserLocation!.latitude, _lastKnownUserLocation!.longitude),
                    toolkit.LatLng(a.latitude ?? 0, a.longitude ?? 0),
                  );
                  final distB = toolkit.SphericalUtil.computeDistanceBetween(
                    toolkit.LatLng(_lastKnownUserLocation!.latitude, _lastKnownUserLocation!.longitude),
                    toolkit.LatLng(b.latitude ?? 0, b.longitude ?? 0),
                  );
                  return distA.compareTo(distB);
                }
                return 0;
              });

              // 5. Affichage final (Stats + Liste)
              return FutureBuilder<DocumentSnapshot>(
                future: _firestore.collection('user_stats').doc(widget.currentUserId).get(),
                builder: (context, statsSnapshot) {
                  // Calcul du temps restant avant nouveaux défis
                  int daysRemaining = 14;
                  if (statsSnapshot.hasData && statsSnapshot.data!.exists) {
                    final data = statsSnapshot.data!.data() as Map<String, dynamic>?;
                    if (data != null && data.containsKey('last_challenges_refresh')) {
                      DateTime lastRefresh = (data['last_challenges_refresh'] as Timestamp).toDate();
                      int daysPassed = DateTime.now().difference(lastRefresh).inDays;
                      daysRemaining = 14 - daysPassed;
                      if (daysRemaining < 0) daysRemaining = 0;
                    }
                  }

                  return Column(
                    children: [
                      // BANDEAU D'INFORMATION
                      Container(
                        width: double.infinity,
                        color: Colors.blueGrey.shade800,
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.refresh, color: Colors.white, size: 16),
                            const SizedBox(width: 8),
                            Text(
                              "Nouveaux défis dans $daysRemaining jour(s)",
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                      ),

                      // LISTE REFRESHABLE
                      Expanded(
                        child: RefreshIndicator(
                          // C'est ICI que la magie opère :
                          // On appelle _checkAndRefreshChallenges.
                          // Cette fonction vérifie la date en BD.
                          // Si < 14 jours, elle ne régénère PAS de nouveaux défis, elle recharge juste l'existant.
                          onRefresh: () async {
                            await _checkAndRefreshChallenges();
                            await _updateUserLocationForSorting();
                            if (mounted) setState(() {});
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12.0),
                            itemCount: challengesToDisplay.length +
                                (_isLoadingLocalPois ? 1 : 0) +
                                (_localPoiError != null ? 1 : 0),
                            itemBuilder: (context, index) {
                              // Loader
                              if (_isLoadingLocalPois && index == 0) {
                                return const Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Center(child: CircularProgressIndicator(color: primaryGreen)),
                                );
                              }
                              // Erreur
                              if (_localPoiError != null && index == 0) {
                                return Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(_localPoiError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                                );
                              }

                              final currentChallengeIndex = index - (_isLoadingLocalPois ? 1 : 0) - (_localPoiError != null ? 1 : 0);
                              if (currentChallengeIndex < 0 || currentChallengeIndex >= challengesToDisplay.length) {
                                return const SizedBox.shrink();
                              }

                              final challengeInstance = challengesToDisplay[currentChallengeIndex];

                              // Récupération magasin partenaire
                              EcoStore? associatedPartnerStore;
                              if (challengeInstance.type == ChallengeType.partnerStoreVisit && challengeInstance.partnerStoreId != null) {
                                associatedPartnerStore = widget.ecoStores.firstWhere(
                                      (store) => store.id == challengeInstance.partnerStoreId,
                                  orElse: () => EcoStore(id: "invalid", name: "Magasin Inconnu", address: "N/A", coordinates: latlong.LatLng(0, 0), description: "", cashbackRate: 0),
                                );
                                if (associatedPartnerStore.id == "invalid") {
                                  associatedPartnerStore = null;
                                }
                              }

                              // Carte Défi
                              return DefisCard(
                                challenge: challengeInstance,
                                onAction: _handleChallengeAction,
                                onStartChallengeTrip: widget.onStartChallengeTrip,
                                currentUserId: widget.currentUserId,
                                associatedPartnerStore: associatedPartnerStore,
                                userLocation: () async {
                                  try {
                                    Position p = await widget.homeController.getMyCurrentLocation();
                                    return latlong.LatLng(p.latitude, p.longitude);
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Impossible d'obtenir la localisation: $e"), backgroundColor: Colors.red));
                                    return null;
                                  }
                                },
                                homeController: widget.homeController,
                                navigationController: widget.navigationController,
                                calculateDynamicReward: _calculateDynamicReward,
                                userProfile: widget.userProfile,
                                weatherData: widget.weatherData,
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
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
final directionsService = DirectionsService();
final request = DirectionsRequest(
origin: "${userPos.latitude},${userPos.longitude}",
destination: "${widget.challenge.latitude},${widget.challenge.longitude}",
travelMode: _selectedTravelType == TravelType.walk
? TravelMode.walking
    : TravelMode.bicycling,
);

await directionsService.route(request,
(DirectionsResult response, status) {
if (status == DirectionsStatus.ok && response.routes!.isNotEmpty) {
distanceKm =
(response.routes!.first.legs!.first.distance!.value! / 1000.0);
simulatedDurationMinutes =
(response.routes!.first.legs!.first.duration!.value! / 60.0)
    .round();
}
});

double transportMultiplier =
(_selectedTravelType == TravelType.walk) ? 1.0 : 1.2;
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


if (widget.userProfile.isAdBoostCurrentlyActive) {
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
            // MODIFICATION : Au lieu de démarrer la navigation, on appelle la fonction de rappel
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
    String buttonText;
    bool enableButton = true;
    Function()? action;

    // Vérifie si la navigation est déjà active pour CE défi
    bool isNavigationActiveForThisChallenge =
        widget.homeController.mapStatus.value == Constants.onDestination &&
            widget.navigationController.activeChallenge?.id == widget.challenge.id;

    if (isNavigationActiveForThisChallenge) {
      buttonText = "Navigation en cours...";
      enableButton = false;
    } else if (isLocalPoiChallenge || isPartnerStoreChallenge) {
      buttonText = "Reprendre la navigation";
      action = () async {
        // MODIFICATION : Identique à ci-dessus pour le bouton de reprise
        widget.onStartChallengeTrip(widget.challenge, _selectedTravelType);
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
            onPressed: enableButton ? action : null, child: Text(buttonText))));
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
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
    elevation: 2,
    child: Padding(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.challenge.title, style: theme.textTheme.titleLarge),
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
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FutureBuilder<int>(
                future: widget.calculateDynamicReward(
                    widget.challenge, _selectedTravelType),
                builder: (context, snapshot) {
                  String gainText = "-";
                  if (snapshot.connectionState == ConnectionState.done &&
                      snapshot.hasData) {
                    gainText = snapshot.data.toString();
                  }

                  return InkWell(
                    onTap: () => _showGainDetailsDialog(context),
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: lightGreen.withOpacity(0.5),
                          border: Border.all(color: primaryGreen, width: 1.5)),
                      child: Center(
                        child: (snapshot.connectionState ==
                            ConnectionState.waiting)
                            ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: primaryGreen))
                            : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              gainText,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: textDark),
                            ),
                            const Text("Lames",
                                style: TextStyle(
                                    fontSize: 10, color: textGrey)),
                          ],
                        ),
                      ),
                    ),
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
final VoidCallback onShowLameHistory; // NOUVEAU
final ChallengeTripData? pendingChallengeTrip; // AJOUT
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
required this.onShowLameHistory, // NOUVEAU
this.pendingStoreTrip,
  this.pendingChallengeTrip, // AJOUT
}) : super(key: key);

@override
_MainHomeScreenState createState() => _MainHomeScreenState();
}

enum HomeScreenMode { trajet, trajetTravail }
enum TransitTimeOption { leaveNow, departAt, arriveBy }
class _MainHomeScreenState extends State<MainHomeScreen> {
late HomeController homeController;
late NavigationController navigationController;
late SpeedController speedController;
List<EcoStore> _dailySuggestedStores = [];

HomeScreenMode _currentMode = HomeScreenMode.trajet;

// MODIFIÉ: Ajout du type 'transit'
TravelType _selectedTravelType = TravelType.bike;
bool _isWorkCommuteBoostActive = false;
List<Map<String, dynamic>> _placePredictions = [];

final TextEditingController _destinationController = TextEditingController();
final TextEditingController _homeAddressController = TextEditingController();
final TextEditingController _workAddressController = TextEditingController();
List<bool> _selectedWorkDays = List.generate(7, (_) => false);

String? _currentCommuteTypeInProgress;

final GlobalKey _upperControlsBarKey = GlobalKey();
double _upperControlsBarHeight = 0.0;
final TextEditingController _originController = TextEditingController();
List<Map<String, dynamic>> _originPlacePredictions = [];
LatLng? _originCoords;

// NOUVEAU: États pour les options de transport en commun
TransitTimeOption _transitTimeOption = TransitTimeOption.leaveNow;
DateTime _selectedTransitTime = DateTime.now();
int _calculatedBaseGain = 0;
Map<String, dynamic> _currentRouteData = {
'duration': 'N/A',
'distance': 'N/A',
};
// NOUVEAU: État pour le switch de validation de marche
bool _validateWalkingLegs = true;

EcoStore? _activeStoreTrip;
int _activeStoreTripCashback = 0;

bool _canStartReturnTrip = false;

  @override
  void initState() {
    super.initState();

    homeController = Get.find<HomeController>();
    navigationController = Get.find<NavigationController>();
    speedController = Get.find<SpeedController>();

    _destinationController.addListener(() {
      if (_destinationController.text.length > 2) {
        _getPlacePredictions(_destinationController.text);
      } else {
        if (mounted) {
          setState(() => _placePredictions = []);
        }
      }
    });

    ever(homeController.arrived, _handleArrival);

    // --- CORRECTION 1 : Recalculer les gains quand la destination, la distance ou la durée changent ---
    ever(homeController.destination, (String dest) {
      if (dest.isEmpty && mounted) {
        _destinationController.clear();
        setState(() {
          _calculatedBaseGain = 0;
          _currentCommuteTypeInProgress = null;
        });
      } else {
        _updateGainAndRouteData();
      }
    });

    // Ces deux lignes forcent la mise à jour des points quand Google Maps renvoie les nouvelles durées (ex: passage de Piéton à Vélo)
    ever(homeController.distanceLeft, (_) => _updateGainAndRouteData());
    ever(homeController.timeLeft, (_) => _updateGainAndRouteData());
    // ------------------------------------------------------------------------------------------------

    _homeAddressController.text = widget.userProfile.homeAddressString ?? "";
    _workAddressController.text = widget.userProfile.workAddressString ?? "";

    if (widget.userProfile.workDays.isNotEmpty) {
      _selectedWorkDays =
          List.generate(7, (i) => widget.userProfile.workDays.contains(i));
    }

    navigationController.setOnWorkDestinationReachedCallback((commuteType) {
      _showSnackBar(
        "Vous êtes arrivé ! Trajet '$commuteType' terminé.",
        backgroundColor: primaryGreen,
      );
      _completeWorkCommute(commuteType);
      navigationController.stopNavigation();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_upperControlsBarKey.currentContext != null) {
        final RenderBox? renderBox =
        _upperControlsBarKey.currentContext!.findRenderObject() as RenderBox?;
        if (renderBox != null && mounted) {
          setState(() => _upperControlsBarHeight = renderBox.size.height);
        }
      }

      _generateDailyStoreSuggestions();

      if (widget.pendingStoreTrip != null) {
        _initiateStoreTrip(widget.pendingStoreTrip!);
      }
      if (widget.pendingChallengeTrip != null) {
        _initiateChallengeTrip(widget.pendingChallengeTrip!);
      }
      _checkReturnTripConditions();
    });
  }

@override
void didUpdateWidget(MainHomeScreen oldWidget) {
super.didUpdateWidget(oldWidget);
if (widget.userProfile != oldWidget.userProfile) {
_homeAddressController.text =
widget.userProfile.homeAddressString ?? _homeAddressController.text;
_workAddressController.text =
widget.userProfile.workAddressString ?? _workAddressController.text;
if (widget.userProfile.workDays.isNotEmpty) {
_selectedWorkDays =
List.generate(7, (i) => widget.userProfile.workDays.contains(i));
}
if (mounted) {
setState(() {});
_checkReturnTripConditions();
}
}
if (widget.pendingStoreTrip != null &&
oldWidget.pendingStoreTrip != widget.pendingStoreTrip) {
_initiateStoreTrip(widget.pendingStoreTrip!);
}
if (widget.pendingChallengeTrip != null &&
    oldWidget.pendingChallengeTrip != widget.pendingChallengeTrip) {
  _initiateChallengeTrip(widget.pendingChallengeTrip!);
}
}
  void _generateDailyStoreSuggestions() async {
    if (widget.ecoStores.isEmpty) return;

    Position userPos = await homeController.getMyCurrentLocation();
    List<EcoStore> candidates = [];
    final random = Random(); // Pour l'aléatoire quotidien (actualisation)

    // 1. Filtrer les magasins dans un rayon max de 30km
    for (var store in widget.ecoStores) {
      double distKm = Geolocator.distanceBetween(
          userPos.latitude, userPos.longitude,
          store.coordinates.latitude, store.coordinates.longitude
      ) / 1000.0;

      if (distKm <= 30.0) {
        candidates.add(store);
      }
    }

    // 2. Calculer un score de "Poids" pour chaque magasin basé sur tes critères
    Map<EcoStore, double> storeWeights = {};

    for (var store in candidates) {
      double distKm = Geolocator.distanceBetween(
          userPos.latitude, userPos.longitude,
          store.coordinates.latitude, store.coordinates.longitude
      ) / 1000.0;

      double weight = 0;

      // Critère 1: Distance (Probabilités demandées)
      if (distKm <= 5) weight += 80;      // 0-5 km: Forte chance
      else if (distKm <= 10) weight += 50; // 5-10 km: Moyenne chance
      else if (distKm <= 20) weight += 20; // 10-20 km: Faible chance
      else weight += 10;                   // 20-30 km: Très faible chance

      // Critère 2: Magasin Or (Abonnement 5€)
      // 80% de chance que ce soit un magasin Or
      if (store.isVisibilityBoostEnabled) {
        weight *= 4.0; // Multiplie le poids par 4 pour favoriser massivement les Gold
      }

      // Ajout d'un facteur aléatoire pour que ça change tous les jours
      // (Utilise le jour de l'année comme graine si on veut du "strictement quotidien",
      // ici simple random pour rafraichissement à l'ouverture)
      weight += random.nextDouble() * 20;

      storeWeights[store] = weight;
    }

    // 3. Trier par poids décroissant et prendre les 3 premiers
    candidates.sort((a, b) => storeWeights[b]!.compareTo(storeWeights[a]!));

    setState(() {
      _dailySuggestedStores = candidates.take(3).toList();
    });
  }
// Fonction qui calcule le boost actuel en fonction du temps écoulé (Decay)
  double calculateCurrentBoost(double storedBoost, Timestamp? lastUpdate, bool isPremium) {
    if (lastUpdate == null) return storedBoost;

    final now = DateTime.now();
    final diffMinutes = now.difference(lastUpdate.toDate()).inMinutes;

    if (diffMinutes <= 0) return storedBoost;

    double current = storedBoost;

    // Simulation minute par minute (ou par bloc) pour appliquer la perte
    // C'est une approximation de ta logique complexe

    int timeBlock = 60; // Par défaut 1h
    double loss = 0.01;

    if (current >= 1.0) { // Boost Spécial
      timeBlock = 5;
      loss = 0.10;
      if (current < 1.9) loss = 0.05; // Moitié moins
    } else if (current >= 0.6) {
      timeBlock = 5;
      loss = 0.06;
    } else if (current >= 0.3) {
      timeBlock = 20;
      loss = 0.03;
    } else if (current >= 0.2) {
      timeBlock = 25;
      loss = 0.02;
    } else if (current >= 0.1) {
      timeBlock = 30;
      loss = 0.02;
    }

    // Bonus Premium : Perte divisée par 2, temps augmenté
    if (isPremium) {
      loss = loss / 2;
      if (timeBlock < 15) timeBlock = 15; // Minimum 15 min de répit
    }

    int cycles = (diffMinutes / timeBlock).floor();
    double finalBoost = current - (cycles * loss);

    return finalBoost < 0 ? 0 : finalBoost;
  }

// Fonction pour regarder une pub
  Future<void> watchAdForBoost() async {
    // 1. Simuler pub
    await Future.delayed(const Duration(seconds: 2));

    double gain = widget.userProfile.isVip ? 0.02 : 0.01;
    // Logique du doublement si > 1.0
    if (widget.userProfile.currentCashbackBoost >= 1.0) gain *= 2;

    // Sauvegarde
    await FirebaseFirestore.instance.collection('users').doc(widget.userProfile.id).update({
      'current_cashback_boost': FieldValue.increment(gain),
      'last_boost_update': FieldValue.serverTimestamp(),
    });
  }
  Future<void> _watchAdAndBoost() async {
    // 1. Simuler la pub (AdMob ici normalement)
    await Future.delayed(const Duration(seconds: 2));

    // 2. Récupérer l'état actuel
    UserProfile p = widget.userProfile;
    double currentBoost = p.currentCashbackBoost;
    bool isPremium = p.isVip;

    // --- LOGIQUE DU GAIN ---
    double gainPerAd = 0.01;

    // Boost Spécial (>1.0) : Gain doublé
    if (currentBoost >= 1.0) {
      gainPerAd = 0.02; // Mode "Boost spécial"
    }

    // Premium : Gain doublé (se cumule potentiellement ou remplace)
    if (isPremium) {
      gainPerAd = 0.02;
      if (currentBoost >= 1.0) gainPerAd = 0.04; // Premium + Special = x4 ? Ou juste x2 ? Disons 0.04 pour récompenser.
    }

    double newBoost = currentBoost + gainPerAd;

    // --- LOGIQUE DE LA PERTE (DECAY) ---
    // On doit enregistrer QUAND la prochaine perte aura lieu et COMBIEN.
    // Cette logique est gérée lors de la lecture, mais ici on met à jour le timestamp.

    // Mise à jour Firestore
    await FirebaseFirestore.instance.collection('users').doc(p.id).update({
      'current_cashback_boost': newBoost,
      'last_boost_update': FieldValue.serverTimestamp(),
      'ad_points': FieldValue.increment(1), // On garde les points classiques aussi
    });

    widget.onProfileModified(); // Rafraîchir l'UI

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Boost activé ! +${gainPerAd.toStringAsFixed(2)}% de cashback."),
      backgroundColor: Colors.purple,
    ));
  }

// Fonction pour calculer la valeur ACTUELLE du boost (en appliquant la perte avec le temps)
// À appeler dans le build() pour afficher la valeur réelle
  double calculateRealTimeBoost(UserProfile p) {
    if (p.lastBoostUpdate == null) return p.currentCashbackBoost;

    DateTime lastUpdate = p.lastBoostUpdate!.toDate();
    DateTime now = DateTime.now();
    int minutesPassed = now.difference(lastUpdate).inMinutes;

    if (minutesPassed <= 0) return p.currentCashbackBoost;

    double currentVal = p.currentCashbackBoost;
    bool isPremium = p.isVip;

    // Boucle de simulation minute par minute (ou par bloc) pour être précis
    // Simplification pour l'exemple : On regarde dans quelle tranche on est

    double lossAmount = 0.01;
    int lossInterval = 60; // Minutes

    if (currentVal >= 1.0) {
      // Mode Special (>1.0)
      lossInterval = 5;
      lossAmount = 0.10; // Perte énorme
      if (currentVal < 1.9) lossAmount = 0.05; // "Moitié moins entre 1 et 1.9"
    } else if (currentVal >= 0.60) {
      lossInterval = 5;
      lossAmount = 0.06;
    } else if (currentVal >= 0.40) {
      // Premium change l'intervalle ici
      lossInterval = isPremium ? 15 : 20;
      lossAmount = 0.04;
    } else if (currentVal >= 0.10) {
      // Logique "diminue toutes les 10 pubs" -> on approxime
      lossInterval = (60 - (currentVal * 100)).round().clamp(5, 60); // ex: 0.20 -> 60 - 20 = 40 min
      lossAmount = currentVal / 10.0; // Perte proportionnelle
    }

    // Application Premium sur la perte
    if (isPremium) {
      lossAmount = lossAmount / 2;
    }

    // Calcul final de la perte
    int cycles = (minutesPassed / lossInterval).floor();
    if (cycles > 0) {
      double finalVal = currentVal - (cycles * lossAmount);
      return finalVal < 0 ? 0.0 : finalVal;
    }

    return currentVal;
  }
  void _initiateChallengeTrip(ChallengeTripData tripData) {
    if (!mounted) return;

    final challenge = tripData.challenge;

    // Logique pour trouver les coordonnées et le nom de la destination
    EcoStore? associatedPartnerStore = (challenge.type == ChallengeType.partnerStoreVisit && challenge.partnerStoreId != null)
        ? widget.ecoStores.firstWhereOrNull((store) => store.id == challenge.partnerStoreId)
        : null;
    if (challenge.type != ChallengeType.localPoiVisit && associatedPartnerStore == null) {
      _showSnackBar("Ce défi n'a pas de destination géographique.", backgroundColor: Colors.orange);
      return;
    }

    LatLng destinationCoords;
    String destinationName;

    if (challenge.type == ChallengeType.localPoiVisit) {
      if (challenge.latitude == null || challenge.longitude == null) {
        _showSnackBar("Coordonnées manquantes pour ce défi.", backgroundColor: Colors.red);
        return;
      }
      destinationCoords = LatLng(challenge.latitude!, challenge.longitude!);
      destinationName = challenge.title.replaceAll("Visitez ", "").replaceAll("Restez à ", "");
    } else { // PartnerStoreVisit
      destinationCoords = LatLng(associatedPartnerStore!.coordinates.latitude, associatedPartnerStore.coordinates.longitude);
      destinationName = associatedPartnerStore.name;
    }

    setState(() {
      _currentMode = HomeScreenMode.trajet;
      _destinationController.text = destinationName;
      _selectedTravelType = tripData.travelType;
    });

    // Point clé : on définit le défi actif dans le contrôleur de navigation
    navigationController.activeChallenge = challenge;
    navigationController.onStoreDestinationReached = null;

    final travelMode = _selectedTravelType == TravelType.walk
        ? TravelMode.walking
        : _selectedTravelType == TravelType.bike
        ? TravelMode.bicycling
        : TravelMode.transit;

    homeController.setDestination(
      destinationName,
      destinationCoords,
      travelMode,
      isStore: false, // Ce n'est pas un trajet vers un magasin pour un achat
    );
  }



@override
void dispose() {
_destinationController.dispose();
_homeAddressController.dispose();
_workAddressController.dispose();
navigationController.setOnWorkDestinationReachedCallback((_) {});
super.dispose();
}
// À ajouter dans la classe _MainHomeScreenState

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
_originPlacePredictions =
List<Map<String, dynamic>>.from(data['predictions'] ?? []);
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
if (homeController.destinationCoordinates.latitude == 0 && homeController.destinationCoordinates.longitude == 0) {
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
Future<void> _getPlacePredictions(String input) async {
if (input.isEmpty) return;
try {
final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;
Position position = await homeController.getMyCurrentLocation();

String typesParam = '';
if (!widget.userProfile.isVip) {
typesParam = '&types=establishment';
}

String url =
'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(input)}&location=${position.latitude},${position.longitude}&radius=50000&key=$apiKey&language=fr&components=country:fr$typesParam';

final response = await http.get(Uri.parse(url));
if (response.statusCode == 200) {
final data = jsonDecode(response.body);
if (mounted) {
setState(() {
_placePredictions =
List<Map<String, dynamic>>.from(data['predictions'] ?? []);
});
}
}
} catch (e) {
print("Erreur d'autocomplétion: $e");
}
}

Future<void> _selectPlace(String placeId, String placeDescription) async {
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

_destinationController.text = placeDescription;
setState(() => _placePredictions = []);

final travelMode = _selectedTravelType == TravelType.walk
? TravelMode.walking
    : _selectedTravelType == TravelType.bike
? TravelMode.bicycling
    : TravelMode.transit;

// Mise à jour manuelle pour éviter le calcul automatique
homeController.destination.value = destinationName;
homeController.destinationCoordinates = destinationCoords;
homeController.currentTravelMode.value = travelMode;
homeController.mapStatus.value = Constants.route;
speedController.setExpectedTravelMode(travelMode);
await homeController.addDestinationMarker(destinationCoords);

if (travelMode != TravelMode.transit) {
await homeController.drawRoute(destinationCoords);
await homeController.getTotalDistanceAndTime(destinationCoords);
_calculatedBaseGain = _calculateBaseLameGain();
homeController.activeRouteEstimatedGain.value = _calculateTotalLameGain();
}
homeController.update();
}
}
} catch (e) {
_showSnackBar("Erreur de sélection: $e", backgroundColor: Colors.red);
}
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

void _handleArrival(bool isArrived) {
if (isArrived && _currentCommuteTypeInProgress != null) {
if (_currentCommuteTypeInProgress == 'aller') {
_showSnackBar(
"Vous êtes arrivé au travail. Le bouton retour sera débloqué dans 3h si vous êtes sur place.",
backgroundColor: Colors.blue,
duration: const Duration(seconds: 5));
_completeWorkCommute('aller');
}
}
}

void _initiateStoreTrip(StoreTripData tripData) {
if (!mounted) return;
setState(() {
_activeStoreTrip = tripData.store;
_currentMode = HomeScreenMode.trajet;
_destinationController.text = tripData.store.name;
_selectedTravelType = tripData.travelType;
});

// AJOUT: Assurer qu'aucun défi n'est actif pour un trajet magasin
  navigationController.activeChallenge = null;
  navigationController.setOnStoreDestinationReachedCallback(() {});

  final travelMode = _selectedTravelType == TravelType.walk
      ? TravelMode.walking
      : _selectedTravelType == TravelType.bike
      ? TravelMode.bicycling
      : TravelMode.transit;
  homeController.setDestination(
      tripData.store.name,
      LatLng(tripData.store.coordinates.latitude,
          tripData.store.coordinates.longitude),
      travelMode,
      isStore: true);
}

void _cancelStoreTrip() {
if (!mounted) return;
setState(() {
_activeStoreTrip = null;
_activeStoreTripCashback = 0;
_destinationController.clear();
});
homeController.clearDestination();
}

Future<void> _calculateAndSetDestination() async {
if (!mounted) return;

final destinationText = _destinationController.text.trim();
if (destinationText.isEmpty) {
_showSnackBar(
"Veuillez entrer une destination.",
backgroundColor: Colors.orange,
);
return;
}

if (!widget.userProfile.isVip) {
_showSnackBar(
"Veuillez sélectionner un lieu dans la liste de suggestions. La recherche d'adresse directe est réservée aux membres VIP.",
backgroundColor: Colors.orange,
);
return;
}

LatLng? destinationCoords;
String destinationName = destinationText;

final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY']!;

try {
final geocodeUrl = Uri.parse(
'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(destinationText)}&key=$apiKey',
);
final response = await http.get(geocodeUrl);
if (response.statusCode == 200) {
final data = jsonDecode(response.body);
if (data['results'] != null && data['results'].isNotEmpty) {
final location = data['results'][0]['geometry']['location'];
destinationCoords = LatLng(location['lat'], location['lng']);
destinationName = data['results'][0]['formatted_address'];
}
}
} catch (e) {
_showSnackBar(
"Erreur de recherche: $e",
backgroundColor: Colors.red,
);
return;
}

if (destinationCoords == null) {
_showSnackBar(
"Destination non trouvée.",
backgroundColor: Colors.orange,
);
return;
}

final travelMode = _selectedTravelType == TravelType.walk
? TravelMode.walking
    : _selectedTravelType == TravelType.bike
? TravelMode.bicycling
    : TravelMode.transit;

homeController.setDestination(
destinationName, destinationCoords, travelMode);
}

Future<void> _calculateAndDisplayWorkCommuteRoute(
{required bool toWork}) async {
if (!mounted) return;
if (widget.userProfile.homeAddressCoordinates == null ||
widget.userProfile.workAddressCoordinates == null) {
_showSnackBar("Adresses domicile/travail non configurées.",
backgroundColor: Colors.red);
return;
}

LatLng originCoords;
LatLng destinationCoords;
String destinationName;

if (toWork) {
originCoords = LatLng(widget.userProfile.homeAddressCoordinates!.latitude,
widget.userProfile.homeAddressCoordinates!.longitude);
destinationCoords = LatLng(
widget.userProfile.workAddressCoordinates!.latitude,
widget.userProfile.workAddressCoordinates!.longitude);
destinationName = widget.userProfile.workAddressString ?? "Travail";
} else {
originCoords = LatLng(widget.userProfile.workAddressCoordinates!.latitude,
widget.userProfile.workAddressCoordinates!.longitude);
destinationCoords = LatLng(
widget.userProfile.homeAddressCoordinates!.latitude,
widget.userProfile.homeAddressCoordinates!.longitude);
destinationName = widget.userProfile.homeAddressString ?? "Domicile";
}

final travelMode = _selectedTravelType == TravelType.walk
? TravelMode.walking
    : _selectedTravelType == TravelType.bike
? TravelMode.bicycling
    : TravelMode.transit;
homeController.setDestination(
destinationName, destinationCoords, travelMode);
_calculatedBaseGain = _calculateBaseLameGain();
homeController.activeRouteEstimatedGain.value = _calculateTotalLameGain();
}

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

void _updateGainAndRouteData() {
if (mounted) {
setState(() {
_calculatedBaseGain = _calculateBaseLameGain();
_currentRouteData['distance'] = homeController.distanceLeft.value;
_currentRouteData['duration'] = homeController.timeLeft.value;
});
}
}


  int _calculateBaseLameGain() {
    // Cas Transit (Bus/Métro) : On utilise la fonction détaillée
    if (homeController.currentTravelMode.value == TravelMode.transit) {
      if (homeController.transitRouteOptions.isEmpty) return 0;
      final route = homeController.transitRouteOptions.first;
      final leg = route['legs'][0];
      return _calculateGainForTransitOption(leg);
    }

    // Cas Marche / Vélo
    if (homeController.distanceLeft.value.isEmpty || homeController.timeLeft.value == "N/A") return 0;

    try {
      // Nettoyage et parsing des données Google
      String distString = homeController.distanceLeft.value.replaceAll(' km', '').replaceAll(',', '.').trim();
      double distanceKm = double.tryParse(distString) ?? 0.0;

      double durationMinutes = 0;
      String timeValue = homeController.timeLeft.value;

      // Parsing "1 h 20 min" ou "45 min"
      if (timeValue.contains('h')) {
        var parts = timeValue.replaceAll('min', '').split('h');
        durationMinutes = (double.parse(parts[0].trim()) * 60) + (double.tryParse(parts[1].trim()) ?? 0);
      } else {
        durationMinutes = double.tryParse(timeValue.replaceAll('min', '').trim()) ?? 0;
      }

      if (durationMinutes == 0) return 0;

      // --- FORMULE ---
      // Distance * 5 + Durée * 0.5
      double effort = (distanceKm * 5.0) + (durationMinutes * 0.5);

      double transportMultiplier = 1.0;

      // On utilise _selectedTravelType qui est mis à jour par les boutons
      switch (_selectedTravelType) {
        case TravelType.walk:
          transportMultiplier = 1.0;
          break;
        case TravelType.bike:
        // Le vélo va plus vite, donc "durationMinutes" est faible.
        // Pour compenser et rendre le vélo attractif, on augmente le multiplicateur
        // Tu avais demandé 1.2, mais comme le temps est divisé par 3 ou 4, le score baisse.
        // Je le passe à 1.5 pour équilibrer avec la marche.
          transportMultiplier = 1.5;
          break;
        case TravelType.transit:
          transportMultiplier = 0.8;
          break;
      }

      // DEBUG : Affiche les valeurs dans la console pour vérifier
      print("Mode: $_selectedTravelType | Dist: $distanceKm | Durée: $durationMinutes | ScoreBrut: $effort | Mult: $transportMultiplier");

      return (effort * transportMultiplier).round();

    } catch (e) {
      print("Erreur calcul lames simple: $e");
      return 0;
    }
  }

  int _calculateTotalLameGain() {
    // On part d'un double pour garder la précision avant arrondi final
    double finalGainDouble = _calculatedBaseGain.toDouble();

    if (_currentMode == HomeScreenMode.trajetTravail) {
      int currentWorkStreak = widget.userProfile.currentWorkCommuteStreak;
      int streakBonusForCommute = (currentWorkStreak * 2).clamp(0, 30);
      finalGainDouble += streakBonusForCommute;
    }

    // Application des multiplicateurs en cascade
    if (_currentMode == HomeScreenMode.trajet && _isWeatherBoostApplicable()) {
      finalGainDouble *= 1.5;
    }
    if (_currentMode == HomeScreenMode.trajetTravail && _isWorkCommuteBoostActive) {
      finalGainDouble *= 1.1;
    }
    if (widget.userProfile.nextLevelBoost > 1.0) {
      finalGainDouble *= widget.userProfile.nextLevelBoost;
    }
    if (widget.userProfile.isVip) {
      finalGainDouble *= 1.15;
    }
    if (widget.userProfile.isAdBoostCurrentlyActive) {
      finalGainDouble *= 1.2;
    }

    int finalGain = finalGainDouble.round();
    // Sécurité: Si on a un trajet valide (_calculatedBaseGain > 0) mais que le résultat est 0 à cause d'arrondis, on donne au moins 1.
    return (finalGain <= 0 && _calculatedBaseGain > 0) ? 1 : finalGain;
  }

void _showLameCalculationDetails(BuildContext context) {
int baseGain = _calculatedBaseGain;
if (baseGain == 0) {
_showSnackBar("Calculez d'abord un itinéraire.",
backgroundColor: Colors.orange);
return;
}

List<Widget> details = [
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
];

details.add(
_buildDetailRowDialog("Gain de Base (Effort):", "$baseGain L", isBold: true));
double currentTotal = baseGain.toDouble();

List<Widget> bonusDetails = [];
if (_currentMode == HomeScreenMode.trajetTravail) {
int streakDT = widget.userProfile.currentWorkCommuteStreak;
int streakBonusDT = (streakDT * 2).clamp(0, 30);
if (streakBonusDT > 0) {
bonusDetails.add(_buildDetailRowDialog(
"Bonus Série D-T:", "+$streakBonusDT L (Série: $streakDT)"));
currentTotal += streakBonusDT;
}
}

if (bonusDetails.isNotEmpty) {
details.add(const Divider(height: 20));
details.addAll(bonusDetails);
}

List<Widget> multiplierDetails = [];
if (_currentMode == HomeScreenMode.trajet && _isWeatherBoostApplicable()) {
double gainFromWeather = currentTotal * 0.5;
multiplierDetails.add(_buildDetailRowDialog(
"Boost Météo (x1.5):",
"+${gainFromWeather.round()} L",
valueColor: primaryGreen,
));
currentTotal += gainFromWeather;
}
if (_currentMode == HomeScreenMode.trajetTravail &&
_isWorkCommuteBoostActive) {
double gainFromWorkBoost = currentTotal * 0.1;
multiplierDetails.add(_buildDetailRowDialog(
"Boost D-T (x1.1):",
"+${gainFromWorkBoost.round()} L",
valueColor: primaryGreen,
));
currentTotal += gainFromWorkBoost;
}
if (widget.userProfile.nextLevelBoost > 1.0) {
double gainFromLevel =
currentTotal * (widget.userProfile.nextLevelBoost - 1.0);
multiplierDetails.add(_buildDetailRowDialog(
"Boost Série Connexion (x${widget.userProfile.nextLevelBoost.toStringAsFixed(2)}):",
"+${gainFromLevel.round()} L",
valueColor: primaryGreen,
));
currentTotal += gainFromLevel;
}
if (widget.userProfile.isVip) {
double gainFromVip = currentTotal * 0.15;
multiplierDetails.add(_buildDetailRowDialog(
"Boost VIP (x1.15):",
"+${gainFromVip.round()} L",
valueColor: primaryGreen,
));
currentTotal += gainFromVip;
}
if (widget.userProfile.isAdBoostCurrentlyActive) {
double gainFromAdBoost = currentTotal * 0.2;
multiplierDetails.add(_buildDetailRowDialog(
"Boost Pub (x1.2):",
"+${gainFromAdBoost.round()} L",
valueColor: primaryGreen,
));
currentTotal += gainFromAdBoost;
}

if (multiplierDetails.isNotEmpty) {
details.add(const Divider(height: 20));
details.addAll(multiplierDetails);
}

details.add(const Divider(height: 20));
details.add(_buildDetailRowDialog(
"Total Estimé:",
"${currentTotal.round()} L",
isBold: true,
valueColor: accentGold,
));

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

Future<void> _watchAd() async {
if (!mounted) return;
int newAdPoints = widget.userProfile.adPoints + 1;
try {
await _firestore.collection('users').doc(widget.userProfile.id).update({
'ad_points': newAdPoints,
'last_ad_point_decay_time': FieldValue.serverTimestamp(),
});
widget.onProfileModified();
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(SnackBar(
content: Text("+1 AD Point! Vous en avez $newAdPoints."),
backgroundColor: primaryGreen,
));
}
} catch (e) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
}
}
}

Future<void> _activateAdBoost() async {
if (!mounted) return;
if (widget.userProfile.adPoints < 10) {
ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
content: Text("Nécessite 10 AD Points."),
backgroundColor: Colors.orange));
return;
}

int newAdPoints = widget.userProfile.adPoints - 10;
Timestamp boostEndTime =
Timestamp.fromDate(DateTime.now().add(const Duration(hours: 24)));

try {
await _firestore.collection('users').doc(widget.userProfile.id).update({
'ad_points': newAdPoints,
'ad_boost_end_time': boostEndTime,
'last_ad_point_decay_time': FieldValue.serverTimestamp(),
});
widget.onProfileModified();
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
content: Text("Boost x1.2 activé (24h)!"),
backgroundColor: accentGold));
}
} catch (e) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text("Erreur: $e"), backgroundColor: Colors.red));
}
}
}

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
AbsorbPointer(
absorbing: _activeStoreTrip != null,
child: Opacity(
opacity: _activeStoreTrip != null ? 0.5 : 1.0,
child: _buildModeSelectionTabsRow(),
),
),
const SizedBox(height: 10),
],
),
),
),
);
}

  Widget _buildTopInfoChipsRow() {
    return SingleChildScrollView( // <--- Ajout pour éviter le débordement
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          GestureDetector(
            onTap: widget.onShowLameHistory,
            child: _customChip(
                label: '${widget.userProfile.lamePoints} L',
                backgroundColor: const Color(0xFF8FBC8F),
                textColor: Colors.black,
                icon: Icons.eco_rounded),
          ),
          const SizedBox(width: 4),
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
                            fontWeight: FontWeight.bold)))),
          ),
          const SizedBox(width: 4),
          _buildAdMinimalistIndicator(),
          const SizedBox(width: 4),
          _buildLoginStreakIndicator(),
        ],
      ),
    );
  }

Widget _buildModeSelectionTabsRow() {
return Container(
decoration: BoxDecoration(
color: Colors.grey[300], borderRadius: BorderRadius.circular(25)),
padding: const EdgeInsets.all(3),
child: Row(children: [
Expanded(
child: _buildChoiceChipInternal(
"Trajet", _currentMode == HomeScreenMode.trajet, () {
if (_currentMode != HomeScreenMode.trajet) {
if (mounted) {
setState(() {
_currentMode = HomeScreenMode.trajet;
_destinationController.clear();
homeController.clearDestination();
});
}
}
})),
Expanded(
child: _buildChoiceChipInternal("Trajet Travail",
_currentMode == HomeScreenMode.trajetTravail, () {
if (_currentMode != HomeScreenMode.trajetTravail) {
if (mounted) {
setState(() {
_currentMode = HomeScreenMode.trajetTravail;
_destinationController.clear();
homeController.clearDestination();
_homeAddressController.text =
widget.userProfile.homeAddressString ?? "";
_workAddressController.text =
widget.userProfile.workAddressString ?? "";
if (widget.userProfile.workDays.isNotEmpty) {
_selectedWorkDays = List.generate(
7, (i) => widget.userProfile.workDays.contains(i));
}
_checkReturnTripConditions();
});
}
}
})),
]),
);
}

Widget _customChip(
{required String label,
required Color backgroundColor,
required Color textColor,
IconData? icon,
Widget? trailing,
bool show = true}) {
if (!show) return const SizedBox.shrink();
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
padding: icon != null
? const EdgeInsets.only(left: 0, right: 3)
    : const EdgeInsets.symmetric(horizontal: 1),
labelPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
visualDensity: VisualDensity.compact,
),
);
}

Widget _buildAdMinimalistIndicator() {
final profile = widget.userProfile;
bool canActivateBoost =
profile.adPoints >= 10 && !profile.isAdBoostCurrentlyActive;
String adBoostTimeLeftString = "";
String adPointsDecayTimeString = "";

if (profile.isAdBoostCurrentlyActive && profile.adBoostEndTime != null) {
final timeLeft =
profile.adBoostEndTime!.toDate().difference(DateTime.now());
if (!timeLeft.isNegative) {
adBoostTimeLeftString =
" ${timeLeft.inHours}h${timeLeft.inMinutes.remainder(60)}m";
}
}
if (profile.adPoints > 0) {
DateTime now = DateTime.now();
Timestamp lastDecayTime = profile.lastAdPointDecayTime ??
Timestamp.fromDate(now.subtract(const Duration(hours: 5)));
Duration timeSinceLastDecay = now.difference(lastDecayTime.toDate());
Duration timeUntilNextDecay =
const Duration(hours: 5) - timeSinceLastDecay;
if (timeUntilNextDecay.isNegative) {
adPointsDecayTimeString = " Perte imminente";
} else {
adPointsDecayTimeString =
" -1 dans ${timeUntilNextDecay.inHours}h${timeUntilNextDecay.inMinutes.remainder(60)}m";
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
Text("${profile.adPoints} ADP",
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
if (profile.isAdBoostCurrentlyActive)
const Tooltip(
message: "Boost AD actif!",
child:
Icon(Icons.bolt_rounded, color: accentGold, size: 14))
else if (canActivateBoost)
InkWell(
onTap: _activateAdBoost,
borderRadius: BorderRadius.circular(10),
child: Tooltip(
message: "Activer Boost AD (10 ADP)",
child: Icon(Icons.offline_bolt_outlined,
color: Colors.orange[700], size: 14)))
else
Tooltip(
message: "Nécessite 10 ADP",
child: Icon(Icons.offline_bolt_outlined,
color: textGrey.withOpacity(0.5), size: 14)),
],
),
),
);
}

void _showAdPointsDetailsDialog(BuildContext context) {
final profile = widget.userProfile;
DateTime now = DateTime.now();
String nextDecayTime = "N/A";
if (profile.adPoints > 0) {
Timestamp lastDecayTime = profile.lastAdPointDecayTime ??
Timestamp.fromDate(now.subtract(const Duration(hours: 5)));
Duration timeSinceLastDecay = now.difference(lastDecayTime.toDate());
Duration timeUntilNextDecay =
const Duration(hours: 5) - timeSinceLastDecay;

if (timeUntilNextDecay.isNegative) {
nextDecayTime = "Perte imminente";
} else {
nextDecayTime =
"${timeUntilNextDecay.inHours}h ${timeUntilNextDecay.inMinutes.remainder(60)}m";
}
}
String boostTimeLeft = "Aucun boost actif";
if (profile.isAdBoostCurrentlyActive && profile.adBoostEndTime != null) {
final timeLeft = profile.adBoostEndTime!.toDate().difference(now);
if (!timeLeft.isNegative) {
boostTimeLeft =
"${timeLeft.inHours}h ${timeLeft.inMinutes.remainder(60)}m";
} else {
boostTimeLeft = "Boost expiré";
}
}
showModalBottomSheet(
context: context,
isScrollControlled: true,
backgroundColor: Colors.transparent,
builder: (BuildContext sheetContext) {
return Container(
padding: EdgeInsets.fromLTRB(
20, 20, 20, MediaQuery.of(sheetContext).viewInsets.bottom + 20),
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
style: Theme.of(context)
    .textTheme
    .headlineSmall
    ?.copyWith(color: primaryGreen))),
const SizedBox(height: 16),
_buildDetailRowDialog("Ad Points actuels:",
"${profile.adPoints} ADP",
icon: Icons.slow_motion_video_rounded),
_buildDetailRowDialog(
"Temps avant perte (-1 ADP):", nextDecayTime,
icon: Icons.timer_outlined,
valueColor:
profile.adPoints > 0 ? Colors.orange[700] : textGrey),
_buildDetailRowDialog("Boost actuel:", boostTimeLeft,
icon: Icons.bolt_rounded,
valueColor: profile.isAdBoostCurrentlyActive
? accentGold
    : textGrey),
const SizedBox(height: 12),
const Divider(),
const SizedBox(height: 12),
const Text("💡 Règles des Ad Points :",
style: TextStyle(
fontSize: 14,
fontWeight: FontWeight.bold,
color: textDark)),
const SizedBox(height: 8),
const Text("• Regardez une pub = +1 Ad Point",
style: TextStyle(fontSize: 13, color: textGrey)),
const Text("• 10 Ad Points = Boost x1.2 pendant 24h",
style: TextStyle(fontSize: 13, color: textGrey)),
Text(
"• Perte de 1 Ad Point toutes les 5h d'inactivité (sauf si pub regardée récemment)",
style:
TextStyle(fontSize: 13, color: Colors.orange[700])),
const SizedBox(height: 20),
Row(
children: [
Expanded(
child: ElevatedButton.icon(
icon: const Icon(Icons.slow_motion_video_rounded),
label: const Text("Regarder une Pub"),
onPressed: () {
Navigator.of(sheetContext).pop();
_watchAd();
})),
if (profile.adPoints >= 10 &&
!profile.isAdBoostCurrentlyActive) ...[
const SizedBox(width: 10),
Expanded(
child: ElevatedButton.icon(
icon: const Icon(Icons.bolt_rounded),
label: const Text("Activer Boost"),
onPressed: () {
Navigator.of(sheetContext).pop();
_activateAdBoost();
},
style: ElevatedButton.styleFrom(
backgroundColor: accentGold))),
],
],
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

void _showLoginStreakDetailsDialog(BuildContext context) {
final profile = widget.userProfile;
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
((profile.consecutiveLogins / LOGIN_STREAK_DAYS_PER_PALIER).floor() +
1) *
LOGIN_STREAK_DAYS_PER_PALIER;
}
bonusDuProchainPalierReel = ((prochainPalierEnJours /
LOGIN_STREAK_DAYS_PER_PALIER)
    .floor() *
LOGIN_STREAK_BONUS_PER_PALIER)
    .clamp(0.0, MAX_LOGIN_STREAK_BONUS_TOTAL);
} else {
progressionProchainPalier = 1.0;
prochainPalierEnJours = profile.consecutiveLogins;
joursRestantsProchainPalier = 0;
}

List<Widget> paliersWidgets = [];
int maxPaliersPourAffichage = (MAX_LOGIN_STREAK_BONUS_TOTAL /
(LOGIN_STREAK_BONUS_PER_PALIER > 0
? LOGIN_STREAK_BONUS_PER_PALIER
    : 1))
    .ceil();
if (maxPaliersPourAffichage == 0 && MAX_LOGIN_STREAK_BONUS_TOTAL > 0) {
maxPaliersPourAffichage = 1;
}
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
backgroundColor: Colors.transparent,
builder: (BuildContext sheetContext) {
return StatefulBuilder(
builder: (BuildContext context, StateSetter setDialogState) {
bool canCollect = _canCollectTodayReward();
return Container(
padding: EdgeInsets.fromLTRB(20, 20, 20,
MediaQuery.of(sheetContext).viewInsets.bottom + 20),
decoration: const BoxDecoration(
color: cardWhite,
borderRadius:
BorderRadius.vertical(top: Radius.circular(25.0))),
child: SingleChildScrollView(
child: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Center(
child: Text("🔥 Votre Série de Connexion 🔥",
style: Theme.of(context)
    .textTheme
    .headlineSmall
    ?.copyWith(color: Colors.orangeAccent[700]))),
const SizedBox(height: 16),
_buildDetailRowDialog(
"Série Actuelle:", "${profile.consecutiveLogins} jours",
icon: Icons.calendar_today_rounded),
_buildDetailRowDialog("Multiplicateur Global Actuel (Série):",
"x${(profile.nextLevelBoost).toStringAsFixed(2)}",
icon: Icons.star_rate_rounded, valueColor: primaryGreen),
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
const AlwaysStoppedAnimation<Color>(accentGold),
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
canCollect ? primaryGreen : Colors.grey[400]),
onPressed: canCollect
? () async {
try {
await _firestore
    .collection('users')
    .doc(widget.userProfile.id)
    .update({
'lame_points': FieldValue.increment(1),
'last_daily_reward_collected_date':
Timestamp.now(),
'updated_at': FieldValue.serverTimestamp()
});
widget.onProfileModified();
setDialogState(() {});
_showSnackBar(
"Récompense récupérée (+1 Lame)!",
backgroundColor: primaryGreen);
} catch (e) {
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
});
},
);
}

Widget _buildChoiceChipInternal(
String label, bool isSelected, VoidCallback onPressed) {
return GestureDetector(
onTap: onPressed,
child: Container(
padding: const EdgeInsets.symmetric(vertical: 10),
decoration: BoxDecoration(
color: isSelected ? Colors.white : Colors.transparent,
borderRadius: BorderRadius.circular(20),
boxShadow: isSelected
? [
BoxShadow(
color: Colors.black.withOpacity(0.15),
blurRadius: 3,
offset: const Offset(0, 1))
]
    : [],
),
child: Center(
child: Text(label,
style: TextStyle(
color: isSelected ? textDark : Colors.grey[700],
fontWeight: FontWeight.bold,
fontSize: 14))),
),
);
}

Widget _buildDraggableSheet() {
double initialSheetSize = 0.28;
double minSheetSize = 0.28;
double maxSheetSize = 0.90;

if (_currentMode == HomeScreenMode.trajetTravail &&
(widget.userProfile.homeAddressString == null ||
widget.userProfile.workAddressString == null)) {
minSheetSize = 0.58;
initialSheetSize = 0.62;
} else if (homeController.destination.value.isNotEmpty) {
minSheetSize = 0.40;
initialSheetSize = 0.42;
}

return DraggableScrollableSheet(
initialChildSize: initialSheetSize,
minChildSize: minSheetSize,
maxChildSize: maxSheetSize,
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
]),
child: ListView(
controller: scrollController,
padding: const EdgeInsets.fromLTRB(16.0, 20.0, 16.0, 16.0),
children: [
...(_currentMode == HomeScreenMode.trajet
? _buildTrajetContentDraggablePart()
    : _buildTrajetTravailContentDraggablePart())
],
),
);
},
);
}
  Widget _buildSuggestedStoresSection() {
    if (_dailySuggestedStores.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4.0, vertical: 8.0),
          child: Text("Suggestions du jour", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        ),
        SizedBox(
          height: 140, // Hauteur fixe pour les cartes
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _dailySuggestedStores.length + 1, // +1 pour le bouton "Voir plus"
            itemBuilder: (context, index) {
              if (index == _dailySuggestedStores.length) {
                // Bouton "Voir Plus"
                return Container(
                  width: 100,
                  margin: const EdgeInsets.only(right: 10),
                  child: Card(
                    color: Colors.grey[100],
                    child: InkWell(
                      onTap: () {
                        // Redirige vers l'onglet Magasin (index 3)
                        // Note: Nécessite d'accéder au TabController ou SetState du parent
                        // Ici on simule un changement d'état si possible ou on affiche un message
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Allez dans l'onglet Magasins pour tout voir !")));
                      },
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.storefront, color: primaryGreen),
                            Text("Voir plus", style: TextStyle(color: primaryGreen, fontWeight: FontWeight.bold)),
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
                      side: isGold ? const BorderSide(color: Colors.amber, width: 2) : BorderSide.none
                  ),
                  child: InkWell(
                    onTap: () => _initiateStoreTrip(StoreTripData(store: store, travelType: _selectedTravelType)),
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(store.name, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
                              if(isGold) const Icon(Icons.star, color: Colors.amber, size: 16),
                            ],
                          ),
                          Text(store.address, style: const TextStyle(fontSize: 10, color: Colors.grey), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const Spacer(),
                          Text("+${store.cashbackRate * 100}% Cashback", style: TextStyle(fontWeight: FontWeight.bold, color: isGold ? Colors.amber[800] : Colors.green)),
                          const SizedBox(height: 5),
                          SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: isGold ? Colors.amber : primaryGreen,
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero
                                  ),
                                  onPressed: () => _initiateStoreTrip(StoreTripData(store: store, travelType: _selectedTravelType)),
                                  child: const Text("Y aller", style: TextStyle(fontSize: 12))
                              )
                          )
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

  List<Widget> _buildTrajetContentDraggablePart() {
    return [
      Obx(() {
        bool destinationSelected = homeController.destination.value.isNotEmpty;

        // CAS 1 : Aucune destination n'est sélectionnée
        // On affiche la Recherche + Les Suggestions
        if (!destinationSelected) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInitialSearchUI(),       // La barre de recherche (une seule fois)
              const SizedBox(height: 10),
              _buildSuggestedStoresSection(), // Les 3 magasins Or/Proches
            ],
          );
        }

        // CAS 2 : Recherche d'itinéraire Transit en cours
        else if (homeController.gettingRoute.value &&
            homeController.currentTravelMode.value == TravelMode.transit) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 60.0),
            child: Center(
              child: Column(
                children: [
                  CircularProgressIndicator(color: primaryGreen),
                  SizedBox(height: 20),
                  Text("Recherche des meilleurs itinéraires...",
                      style: TextStyle(color: textGrey, fontSize: 16)),
                ],
              ),
            ),
          );
        }

        // CAS 3 : Liste des options de bus/métro affichée
        else if (homeController.showTransitOptions.value) {
          return _buildTransitOptionsList();
        }

        // CAS 4 : Mode Transit sélectionné mais pas encore de route calculée (Options avancées)
        else if (_selectedTravelType == TravelType.transit && homeController.polyline.isEmpty) {
          return _buildAdvancedTransitOptionsUI();
        }

        // CAS 5 : Itinéraire affiché (Résumé du trajet pour Marche/Vélo ou Transit choisi)
        else {
          return _buildRouteSummaryUI();
        }
      }),
    ];
  }

Widget _buildInitialSearchUI() {
return Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: [
TextField(
controller: _destinationController,
decoration: InputDecoration(
hintText: "Où allez-vous ?",
prefixIcon: const Icon(Icons.search, color: primaryGreen),
border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
),
),
if (_placePredictions.isNotEmpty)
_buildPredictionsList(_placePredictions, _selectPlace),
const SizedBox(height: 10),
_buildTravelTypeToggle(),
// NOUVEAU: Affichage du switch pour la marche si le mode transit est sélectionné
if (_selectedTravelType == TravelType.transit)
Padding(
padding: const EdgeInsets.only(top: 8.0),
child: SwitchListTile(
title: const Text("Valider la marche jusqu'à l'arrêt"),
subtitle: const Text("Active les gains et la vérification pour la marche."),
value: _validateWalkingLegs,
onChanged: (bool value) {
setState(() {
_validateWalkingLegs = value;
});
},
activeColor: primaryGreen,
),
),
],
);
}

Widget _buildAdvancedTransitOptionsUI() {
return _buildTransitSearchControls();
}
  Widget _buildTransitSearchControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.location_on, color: primaryGreen),
          title: Text(homeController.destination.value, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text("Destination"),
          // CORRECTION: Ajout d'un bouton pour effacer la destination,
          // uniquement visible dans le flux des transports en commun.
          trailing: IconButton(
            tooltip: "Effacer la destination",
            icon: const Icon(Icons.clear, size: 20),
            onPressed: () => homeController.clearDestination(),
          ),
        ),
        const Divider(height: 10),
        const SizedBox(height: 10),

        TextField(
          controller: _originController,
          decoration: InputDecoration(
            hintText: "Partir de (votre position)",
            prefixIcon: const Icon(Icons.trip_origin, color: textGrey),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: _originController.text.isNotEmpty
                ? IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                setState(() {
                  _originController.clear();
                  _originCoords = null;
                  _originPlacePredictions = [];
                });
              },
            )
                : null,
          ),
          onChanged: _getOriginPlacePredictions,
        ),
        if (_originPlacePredictions.isNotEmpty)
          _buildPredictionsList(_originPlacePredictions, _selectOriginPlace),

        const SizedBox(height: 15),
        _buildTransitTimeOptions(),
        const SizedBox(height: 10),
        SwitchListTile(
          title: const Text("Valider la marche à pied"),
          value: _validateWalkingLegs,
          onChanged: (val) => setState(() => _validateWalkingLegs = val),
          activeColor: primaryGreen,
        ),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          icon: const Icon(Icons.directions_bus),
          label: const Text("Voir les itinéraires"),
          onPressed: _searchTransitRoute,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 45),
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
          ),
        )
      ],
    );
  }
  Widget _buildRouteSummaryUI() {
return Column(
children: [
_buildTravelTypeToggle(),
const SizedBox(height: 10),
_buildRouteSummary(),
const SizedBox(height: 6),
_buildTravelModeDetails(),
const SizedBox(height: 10),
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
crossAxisAlignment: CrossAxisAlignment.center,
children: [
_buildGainCircle(),
const Spacer(),
ElevatedButton(
onPressed: homeController.mapStatus.value == Constants.route
? () => navigationController.navigateToDestination(validateWalkingLegs: _validateWalkingLegs)
    : null,
// MODIFIÉ: Texte du bouton
child: const Text("Commencer le Trajet", style: TextStyle(fontSize: 16)),
),
],
),
const SizedBox(height: 15),
_buildWeatherSection(),
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
TransitTimeOption.leaveNow: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("Maintenant")),
TransitTimeOption.departAt: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("Partir à")),
TransitTimeOption.arriveBy: Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text("Arriver à")),
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

Widget _buildPredictionsList(
List<Map<String, dynamic>> predictions,
Function(String, String) onSelect,
) {
final double listHeight = (predictions.length * 55.0).clamp(0.0, 220.0);

return SizedBox(
height: listHeight,
child: ListView.builder(
padding: EdgeInsets.zero,
itemCount: predictions.length,
itemBuilder: (context, index) {
final prediction = predictions[index];
return ListTile(
leading: const Icon(Icons.location_on, color: textGrey),
title: Text(prediction['description']),
onTap: () => onSelect(prediction['place_id'], prediction['description']),
);
},
),
);
}

// Dans _MainHomeScreenState

  void _showTransitLameCalculationDetails(BuildContext context, Map<String, dynamic> leg) {
    int baseGain = _calculateGainForTransitOption(leg);
    if (baseGain == 0) return;

    // --- CALCUL DU CO2 POUR L'AFFICHAGE ---
    double co2EconomiseTotalGrams = 0.0;
    double co2EmisTotalGrams = 0.0;

    try {
      const double FE_VOITURE_KM = 180.0;
      const double BUS_NB_PASSAGERS = 50.0;
      const double BUS_CONSO_KM = 900.0;
      const double BUS_CONSO_MINUTE = 15.0;
      const double FE_RAIL_KM = 6.0;

      for (var step in leg['steps']) {
        double dKm = (step['distance']['value'] as num).toDouble() / 1000.0;
        double dMin = (step['duration']['value'] as num).toDouble() / 60.0;
        String mode = step['travel_mode'];

        double stepVoiture = dKm * FE_VOITURE_KM;
        double stepTransport = 0.0;

        if (mode == 'TRANSIT') {
          String vType = step['transit_details']?['line']?['vehicle']?['type'] ?? 'BUS';
          if (vType == 'BUS' || vType == 'INTERCITY_BUS' || vType == 'TROLLEYBUS') {
            stepTransport = ((dKm * BUS_CONSO_KM) + (dMin * BUS_CONSO_MINUTE)) / BUS_NB_PASSAGERS;
          } else {
            stepTransport = dKm * FE_RAIL_KM;
          }
        } else if (mode == 'WALKING') {
          stepTransport = 0.0;
        } else {
          stepTransport = stepVoiture;
        }

        co2EmisTotalGrams += stepTransport;
        if(stepTransport < stepVoiture) {
          co2EconomiseTotalGrams += (stepVoiture - stepTransport);
        }
      }
    } catch(e) { print(e); }
    // -------------------------------------

    List<Widget> details = [
      Center(
        child: Text(
          "Détail du Gain & Écologie",
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(color: primaryGreen),
        ),
      ),
      const SizedBox(height: 16),
    ];

    // Affichage CO2
    details.add(Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.green.shade200)
      ),
      child: Column(
          children: [
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("CO₂ Émis (Transport):"),
                  Text("${co2EmisTotalGrams.toStringAsFixed(0)} g", style: const TextStyle(fontWeight: FontWeight.bold))
                ]
            ),
            const SizedBox(height: 5),
            Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Économie vs Voiture :", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                  Text("- ${(co2EconomiseTotalGrams).toStringAsFixed(0)} g", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16))
                ]
            ),
          ]
      ),
    ));

    details.add(_buildDetailRowDialog("Gain de Base (Effort + CO₂):", "$baseGain L", isBold: true));
    double currentTotal = baseGain.toDouble();

    // ... (Le reste des multiplicateurs Météo/VIP reste identique) ...
    List<Widget> multiplierDetails = [];
    if (_isWeatherBoostApplicable()) {
      double gainFromWeather = currentTotal * 0.5;
      multiplierDetails.add(_buildDetailRowDialog(
        "Boost Météo (x1.5):",
        "+${gainFromWeather.round()} L",
        valueColor: primaryGreen,
      ));
      currentTotal += gainFromWeather;
    }
    // ... (Ajouter les autres boosts ici comme dans ton code précédent) ...
    if (widget.userProfile.nextLevelBoost > 1.0) {
      double gainFromLevel = currentTotal * (widget.userProfile.nextLevelBoost - 1.0);
      multiplierDetails.add(_buildDetailRowDialog("Boost Série (x${widget.userProfile.nextLevelBoost.toStringAsFixed(2)}):", "+${gainFromLevel.round()} L", valueColor: primaryGreen));
      currentTotal += gainFromLevel;
    }
    if (widget.userProfile.isVip) {
      double gainFromVip = currentTotal * 0.15;
      multiplierDetails.add(_buildDetailRowDialog("Boost VIP (x1.15):", "+${gainFromVip.round()} L", valueColor: primaryGreen));
      currentTotal += gainFromVip;
    }
    if (widget.userProfile.isAdBoostCurrentlyActive) {
      double gainFromAd = currentTotal * 0.2;
      multiplierDetails.add(_buildDetailRowDialog("Boost Pub (x1.2):", "+${gainFromAd.round()} L", valueColor: primaryGreen));
      currentTotal += gainFromAd;
    }

    if (multiplierDetails.isNotEmpty) {
      details.add(const Divider(height: 20));
      details.addAll(multiplierDetails);
    }

    details.add(const Divider(height: 20));
    details.add(_buildDetailRowDialog(
      "Total Estimé:",
      "${currentTotal.round()} L",
      isBold: true,
      valueColor: accentGold,
    ));

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

// Dans _MainHomeScreenState

  int _calculateGainForTransitOption(Map<String, dynamic> leg) {
    if (leg['distance'] == null || leg['duration'] == null) return 0;

    try {
      double totalPoints = 0.0;

      // --- CONSTANTES D'ÉMISSION (g de CO2) ---
      const double FE_VOITURE_KM = 180.0;     // Voiture thermique solo (g/km)

      // Paramètres Bus (Demande spécifique)
      const double BUS_NB_PASSAGERS = 50.0;   // Moyenne haute
      const double BUS_CONSO_KM = 900.0;      // Conso roulement (g/km)
      const double BUS_CONSO_MINUTE = 15.0;   // Conso temps/embouteillage (g/min)

      const double FE_RAIL_KM = 6.0;          // Métro/Tram/Train (g/km par personne)

      // --- RATIO DE CONVERSION ---
      // 1 Lame Point gagné pour 40g de CO2 économisés
      const double CONVERSION_CO2_POINTS = 1.0 / 40.0;

      for (var step in leg['steps']) {
        double distanceKm = (step['distance']['value'] as num).toDouble() / 1000.0;
        double durationMinutes = (step['duration']['value'] as num).toDouble() / 60.0;
        String travelMode = step['travel_mode'];

        // 1. CALCUL DE L'EFFORT (Ta formule physique)
        // Effort = (Distance * 5) + (Durée * 0.5)
        double effort = (distanceKm * 5.0) + (durationMinutes * 0.5);

        // 2. CALCUL SCIENTIFIQUE DU CO2
        double co2EmisVoiture = distanceKm * FE_VOITURE_KM;
        double co2EmisUtilisateur = 0.0;
        double transportMultiplier = 1.0;

        if (travelMode == 'WALKING') {
          // Marche : 0 émission, bonus maximal
          co2EmisUtilisateur = 0.0;
          transportMultiplier = 1.0;
        }
        else if (travelMode == 'TRANSIT') {
          String vehicleType = step['transit_details']?['line']?['vehicle']?['type'] ?? 'BUS';

          if (vehicleType == 'BUS' || vehicleType == 'INTERCITY_BUS' || vehicleType == 'TROLLEYBUS') {
            // Formule Bus Complexe : (Distance + Durée) / 50 passagers
            double emissionBusTotal = (distanceKm * BUS_CONSO_KM) + (durationMinutes * BUS_CONSO_MINUTE);
            co2EmisUtilisateur = emissionBusTotal / BUS_NB_PASSAGERS;

            transportMultiplier = 0.8; // Moins d'effort physique
          } else {
            // Rail : Très faible émission par km
            co2EmisUtilisateur = distanceKm * FE_RAIL_KM;
            transportMultiplier = 0.9;
          }
        }
        else {
          // Cas par défaut (ex: voiture)
          co2EmisUtilisateur = co2EmisVoiture;
          transportMultiplier = 0.1;
        }

        // 3. CALCUL DU GAIN ÉCOLOGIQUE
        // Économie = Ce que la voiture aurait émis - Ce que tu as émis
        double co2Economise = co2EmisVoiture - co2EmisUtilisateur;

        // On ne peut pas avoir de points négatifs si le bus pollue plus (cas rares bouchons extrêmes)
        if (co2Economise < 0) co2Economise = 0;

        double pointsEcologiques = co2Economise * CONVERSION_CO2_POINTS;

        // TOTAL ÉTAPE
        totalPoints += (effort * transportMultiplier) + pointsEcologiques;
      }

      // --- 4. APPLICATION DES BOOSTS ---
      if (_isWeatherBoostApplicable()) totalPoints *= 1.5;
      if (widget.userProfile.nextLevelBoost > 1.0) totalPoints *= widget.userProfile.nextLevelBoost;
      if (widget.userProfile.isVip) totalPoints *= 1.15;
      if (widget.userProfile.isAdBoostCurrentlyActive) totalPoints *= 1.2;

      int finalGain = totalPoints.round();
      return (finalGain <= 0 && leg['distance']['value'] > 0) ? 1 : finalGain;

    } catch (e) {
      print("Erreur calcul gain transit: $e");
      return 0;
    }
  }



int _calculateBaseGainForTransitOption(Map<String, dynamic> leg) {
if (leg['distance'] == null || leg['duration'] == null) return 0;
try {
double distanceKm = (leg['distance']['value'] as num).toDouble() / 1000.0;
double durationMinutes = (leg['duration']['value'] as num).toDouble() / 60.0;
if (durationMinutes == 0) return 0;
double denivele_m = 0;

const double W_DIST = 5.0;
const double W_DENIVELE = 0.2;
const double W_DUREE = 0.5;
double effort = (distanceKm * W_DIST) + (denivele_m * W_DENIVELE) + (durationMinutes * W_DUREE);

double transportMultiplier = 0.8;
return (effort * transportMultiplier).round();
} catch (e) {
print("Erreur dans _calculateBaseGainForTransitOption: $e");
return 0;
}
}
Widget _buildTransitOptionsList() {
return Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
// 1. On affiche à nouveau les contrôles de recherche (Départ, Arrivée, Heure)
_buildTransitSearchControls(),
const SizedBox(height: 20),
const Divider(),
const SizedBox(height: 10),

// 2. NOUVEAU: Ajout du titre de la section des résultats
Padding(
padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
child: Text(
"Résultats :",
style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 18),
),
),

// 3. Le ListView.builder est maintenant à l'intérieur du Column
Obx(
() => ListView.builder(
shrinkWrap: true, // Important dans un Column
physics: const NeverScrollableScrollPhysics(), // Important dans un ListView parent
itemCount: homeController.transitRouteOptions.length,
itemBuilder: (context, index) {
final route = homeController.transitRouteOptions[index];
final leg = route['legs'][0];
final duration = leg['duration']['text'];
final arrivalTime = leg['arrival_time']?['text'];
final departureTime = leg['departure_time']?['text'];
final int estimatedGain = _calculateGainForTransitOption(leg);

final bool isRecommended = index == 0;

List<Widget> lineIcons = [];
Set<String> uniqueLines = {};
for (var step in leg['steps']) {
if (step['travel_mode'] == 'TRANSIT') {
final lineName = step['transit_details']?['line']?['short_name'] ?? '';
if (lineName.isNotEmpty && !uniqueLines.contains(lineName)) {
uniqueLines.add(lineName);
lineIcons.add(Container(
padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
margin: const EdgeInsets.only(right: 4),
decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(4)),
child: Text(lineName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
));
lineIcons.add(const Icon(Icons.arrow_right_alt, color: Colors.grey, size: 16));
}
} else if(step['travel_mode'] == 'WALKING' && lineIcons.isNotEmpty && lineIcons.last is! Icon) {
lineIcons.add(const Icon(Icons.directions_walk, color: Colors.grey, size: 16));
lineIcons.add(const Icon(Icons.arrow_right_alt, color: Colors.grey, size: 16));
}
}
if(lineIcons.isNotEmpty) lineIcons.removeLast();

return Card(
margin: const EdgeInsets.only(bottom: 10),
elevation: isRecommended ? 4 : 2,
shape: RoundedRectangleBorder(
borderRadius: BorderRadius.circular(12),
side: BorderSide(
color: isRecommended ? primaryGreen : Colors.transparent,
width: 2,
),
),
child: Padding(
padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
child: Column(
children: [
if(isRecommended)
Align(
alignment: Alignment.centerLeft,
child: Chip(
label: const Text("Recommandé"),
backgroundColor: primaryGreen.withOpacity(0.15),
labelStyle: const TextStyle(color: primaryGreen, fontWeight: FontWeight.bold, fontSize: 11),
padding: EdgeInsets.zero,
visualDensity: VisualDensity.compact,
),
),
Row(
children: [
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(duration, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
if(departureTime != null && arrivalTime != null)
Padding(
padding: const EdgeInsets.only(top: 4.0),
child: Text("$departureTime arrivant à $arrivalTime", style: const TextStyle(color: textGrey, fontSize: 14)),
),
const SizedBox(height: 10),
if (lineIcons.isNotEmpty)
Wrap(
crossAxisAlignment: WrapCrossAlignment.center,
spacing: 4.0,
runSpacing: 4.0,
children: lineIcons,
),
],
),
),
const SizedBox(width: 12),
Column(
mainAxisAlignment: MainAxisAlignment.center,
children: [
InkWell(
onTap: () => _showTransitLameCalculationDetails(context, leg),
borderRadius: BorderRadius.circular(32.5),
child: Container(
width: 65,
height: 65,
decoration: BoxDecoration(
shape: BoxShape.circle,
color: accentGold.withOpacity(0.15),
border: Border.all(color: accentGold, width: 1.5)),
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: [
Text(estimatedGain.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: textDark)),
const Text("Lames", style: TextStyle(fontSize: 10, color: textGrey)),
],
),
),
),
const SizedBox(height: 10),
ElevatedButton(
onPressed: () {
final int totalGainForThisRoute = _calculateGainForTransitOption(leg);
homeController.activeRouteEstimatedGain.value = totalGainForThisRoute;
homeController.selectAndDrawTransitRoute(index);
},
child: const Text("Choisir"),
style: ElevatedButton.styleFrom(
backgroundColor: isRecommended ? primaryGreen : Colors.blueAccent,
padding: const EdgeInsets.symmetric(horizontal: 10),
),
)
],
)
],
),
],
),
),
);
},
),
),
],
);
}

List<Widget> _buildTrajetTravailContentDraggablePart() {
final today = DateTime.now();
final currentDayOfWeek = today.weekday - 1;
final bool isWorkDay = widget.userProfile.workDays.contains(currentDayOfWeek);
bool allerValidatedToday = false;
bool retourValidatedToday = false;

if (widget.userProfile.lastWorkCommuteTimestamp != null) {
DateTime lastCommuteDate =
widget.userProfile.lastWorkCommuteTimestamp!.toDate();
if (DateUtils.isSameDay(lastCommuteDate, today)) {
if (widget.userProfile.lastCommuteType == 'aller') {
allerValidatedToday = true;
} else if (widget.userProfile.lastCommuteType == 'retour') {
allerValidatedToday = true;
retourValidatedToday = true;
}
}
}

bool canCalculateAller = !allerValidatedToday &&
homeController.mapStatus.value != Constants.onDestination;
bool canCalculateRetour = allerValidatedToday &&
!retourValidatedToday &&
_canStartReturnTrip &&
homeController.mapStatus.value != Constants.onDestination;

String returnButtonTooltip = "";
if (allerValidatedToday && !retourValidatedToday) {
if (!_canStartReturnTrip) {
if (widget.userProfile.lastWorkArrivalTimestamp == null) {
returnButtonTooltip = "Trajet aller non complété.";
} else {
final timeSinceArrival = DateTime.now()
    .difference(widget.userProfile.lastWorkArrivalTimestamp!.toDate());
if (timeSinceArrival < const Duration(hours: 3)) {
final remaining = const Duration(hours: 3) - timeSinceArrival;
returnButtonTooltip =
"Disponible dans ${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m.";
} else {
returnButtonTooltip =
"Veuillez vous rapprocher de votre lieu de travail.";
}
}
}
}

return [
Text("Mon Trajet Quotidien",
style: Theme.of(context).textTheme.headlineSmall),
const SizedBox(height: 8),
ListTile(
leading: const Icon(Icons.home_outlined, color: primaryGreen),
title: Text(widget.userProfile.homeAddressString ?? "Non défini",
style: const TextStyle(fontSize: 13)),
dense: true,
),
ListTile(
leading: const Icon(Icons.work_outline_outlined, color: primaryGreen),
title: Text(widget.userProfile.workAddressString ?? "Non défini",
style: const TextStyle(fontSize: 13)),
dense: true,
),
const SizedBox(height: 8),
_buildWeatherSection(),
const SizedBox(height: 10),
_buildWorkCommuteInfoSection(),
if (!isWorkDay &&
!allerValidatedToday)
Container(
padding: const EdgeInsets.all(10),
margin: const EdgeInsets.only(top: 10),
decoration: BoxDecoration(
color: Colors.amber.withOpacity(0.15),
borderRadius: BorderRadius.circular(8)),
child: Text("Aujourd'hui n'est pas un jour de travail.",
textAlign: TextAlign.center,
style: TextStyle(color: Colors.amber.shade900)),
)
else ...[
_buildTravelTypeToggle(),
const SizedBox(height: 10),
Obx(() => Visibility(
visible: homeController.gettingRoute.value,
child: const Padding(
padding: EdgeInsets.all(8.0),
child: Center(
child: CircularProgressIndicator(color: primaryGreen))),
)),
Obx(() => homeController.destination.value.isNotEmpty &&
!homeController.gettingRoute.value &&
homeController.polyline.isEmpty
? const Padding(
padding: EdgeInsets.symmetric(vertical: 8.0),
child: Text(
"Aucun itinéraire trouvé pour cette destination.",
style: TextStyle(color: Colors.red, fontSize: 12),
textAlign: TextAlign.center),
)
    : const SizedBox.shrink()),
Obx(() => Visibility(
visible: homeController.destination.value.isNotEmpty &&
!homeController.gettingRoute.value &&
homeController.polyline.isNotEmpty,
child: Column(children: [
_buildRouteSummary(),
_buildTravelModeDetails(),
const SizedBox(height: 10),
Row(
mainAxisAlignment: MainAxisAlignment.spaceBetween,
children: [
_buildGainCircle(),
const Spacer(),
ElevatedButton(
onPressed:
homeController.mapStatus.value == Constants.route
? () => _startWorkCommuteTracking(
allerValidatedToday ? 'retour' : 'aller')
    : null,
// MODIFIÉ: Texte du bouton
child: const Text("Commencer le Trajet",
style: TextStyle(fontSize: 16)),
),
],
),
const SizedBox(height: 15),
]),
)),
Row(
mainAxisAlignment: MainAxisAlignment.spaceEvenly,
children: [
Expanded(
child: ElevatedButton.icon(
icon: const Icon(Icons.arrow_forward_rounded, size: 20),
label: Text(
allerValidatedToday ? "Aller Validé" : "Calculer Aller",
style: const TextStyle(fontSize: 13)),
onPressed: homeController.gettingRoute.value ||
!canCalculateAller
? null
    : () => _calculateAndDisplayWorkCommuteRoute(toWork: true),
style: ElevatedButton.styleFrom(
backgroundColor: allerValidatedToday
? Colors.grey[400]
    : const Color(0xFF66BB6A),
padding: const EdgeInsets.symmetric(vertical: 10)),
),
),
const SizedBox(width: 10),
Expanded(
child: Tooltip(
message: returnButtonTooltip,
child: ElevatedButton.icon(
icon: const Icon(Icons.arrow_back_rounded, size: 20),
label: Text(
retourValidatedToday ? "Retour Validé" : "Calculer Retour",
style: const TextStyle(fontSize: 13)),
onPressed: homeController.gettingRoute.value ||
!canCalculateRetour
? null
    : () =>
_calculateAndDisplayWorkCommuteRoute(toWork: false),
style: ElevatedButton.styleFrom(
backgroundColor: retourValidatedToday
? Colors.grey[400]
    : const Color(0xFF66BB6A),
padding: const EdgeInsets.symmetric(vertical: 10)),
),
),
),
],
),
const SizedBox(height: 20),
Center(
child: Text(
"Série D-T actuelle: ${widget.userProfile.currentWorkCommuteStreak} trajets",
style: Theme.of(context)
    .textTheme
    .bodyLarge
    ?.copyWith(fontWeight: FontWeight.bold),
),
),
],
const SizedBox(height: 15),
OutlinedButton.icon(
icon: const Icon(Icons.settings_outlined, size: 20),
label:
const Text("Modifier Paramètres D-T", style: TextStyle(fontSize: 13)),
onPressed: () {
Navigator.of(context)
    .push(MaterialPageRoute(
builder: (_) => Scaffold(
appBar:
AppBar(title: const Text("Configurer Domicile-Travail")),
body: SingleChildScrollView(
padding: const EdgeInsets.all(16),
child: Column(
children: _buildAddressSetupForm())),
)))
    .then((_) => widget.onProfileModified());
},
)
];
}

List<Widget> _buildAddressSetupForm() {
final bool canEdit = _canEditAddresses();
return [
Text("Configuration Domicile-Travail",
style: Theme.of(context).textTheme.headlineSmall),
const SizedBox(height: 15),
TextField(
controller: _homeAddressController,
decoration: const InputDecoration(
labelText: "Adresse Domicile",
border: OutlineInputBorder(),
prefixIcon: Icon(Icons.home_work_outlined)),
enabled: canEdit),
const SizedBox(height: 10),
TextField(
controller: _workAddressController,
decoration: const InputDecoration(
labelText: "Adresse Travail",
border: OutlineInputBorder(),
prefixIcon: Icon(Icons.work_outline)),
enabled: canEdit),
if (!canEdit && widget.userProfile.lastAddressUpdateTime != null)
Padding(
padding: const EdgeInsets.only(top: 8.0),
child: Text(
"Modification des adresses possible à partir du ${DateFormat('dd/MM/yyyy', 'fr_FR').format(widget.userProfile.lastAddressUpdateTime!.toDate().add(const Duration(days: 365)))}.",
style: TextStyle(color: Colors.orange.shade700, fontSize: 12)),
),
const SizedBox(height: 15),
Text("Vos jours de travail :",
style: Theme.of(context).textTheme.titleMedium),
const SizedBox(height: 8),
ToggleButtons(
children: const [
Text("L"),
Text("M"),
Text("M"),
Text("J"),
Text("V"),
Text("S"),
Text("D")
],
isSelected: _selectedWorkDays,
onPressed: (int index) {
setState(() => _selectedWorkDays[index] = !_selectedWorkDays[index]);
},
borderRadius: BorderRadius.circular(8),
selectedColor: Colors.white,
fillColor: primaryGreen,
color: primaryGreen,
constraints: BoxConstraints(
minHeight: 36.0,
minWidth: (MediaQuery.of(context).size.width - 48) / 7),
),
const SizedBox(height: 20),
ElevatedButton(
onPressed: _saveWorkCommuteSettings,
child: Text((widget.userProfile.homeAddressString == null)
? "Enregistrer"
    : "Sauvegarder"),
style: ElevatedButton.styleFrom(
minimumSize: const Size(double.infinity, 45)),
),
];
}

Future<void> _saveWorkCommuteSettings() async {
final String homeAddressText = _homeAddressController.text.trim();
final String workAddressText = _workAddressController.text.trim();
if (homeAddressText.isEmpty || workAddressText.isEmpty) {
_showSnackBar("Adresses requises.", backgroundColor: Colors.red);
return;
}

latlong.LatLng? homeCoords = widget.userProfile.homeAddressCoordinates;
if (widget.userProfile.homeAddressString != homeAddressText ||
homeCoords == null) {
homeCoords = await _geocodeAddress(homeAddressText);
if (homeCoords == null) {
_showSnackBar("Adresse domicile introuvable.",
backgroundColor: Colors.red);
return;
}
}
latlong.LatLng? workCoords = widget.userProfile.workAddressCoordinates;
if (widget.userProfile.workAddressString != workAddressText ||
workCoords == null) {
workCoords = await _geocodeAddress(workAddressText);
if (workCoords == null) {
_showSnackBar("Adresse travail introuvable.",
backgroundColor: Colors.red);
return;
}
}
List<int> workDaysList = [];
for (int i = 0; i < _selectedWorkDays.length; i++) {
if (_selectedWorkDays[i]) workDaysList.add(i);
}
if (workDaysList.isEmpty) {
_showSnackBar("Sélectionnez au moins un jour de travail.",
backgroundColor: Colors.red);
return;
}

Map<String, dynamic> updates = {
'home_address_string': homeAddressText,
'home_address_coordinates': homeCoords != null
? GeoPoint(homeCoords.latitude, homeCoords.longitude)
    : null,
'work_address_string': workAddressText,
'work_address_coordinates': workCoords != null
? GeoPoint(workCoords.latitude, workCoords.longitude)
    : null,
'work_days': workDaysList,
'updated_at': FieldValue.serverTimestamp(),
};
bool addressesChanged =
(widget.userProfile.homeAddressString != homeAddressText) ||
(widget.userProfile.workAddressString != workAddressText) ||
(widget.userProfile.homeAddressCoordinates?.latitude !=
homeCoords?.latitude) ||
(widget.userProfile.homeAddressCoordinates?.longitude !=
homeCoords?.longitude) ||
(widget.userProfile.workAddressCoordinates?.latitude !=
workCoords?.latitude) ||
(widget.userProfile.workAddressCoordinates?.longitude !=
workCoords?.longitude);
if (addressesChanged &&
(_canEditAddresses() ||
widget.userProfile.lastAddressUpdateTime == null)) {
updates['last_address_update_time'] = FieldValue.serverTimestamp();
} else if (addressesChanged && !_canEditAddresses()) {
_showSnackBar("Modification des adresses limitée à une fois par an.",
backgroundColor: Colors.orange,
duration: const Duration(seconds: 5));
updates.remove('home_address_string');
updates.remove('home_address_coordinates');
updates.remove('work_address_string');
updates.remove('work_address_coordinates');
}
try {
await _firestore
    .collection('users')
    .doc(widget.userProfile.id)
    .update(updates);
_showSnackBar("Paramètres D-T enregistrés !");
widget.onProfileModified();
} catch (e) {
_showSnackBar("Erreur: $e", backgroundColor: Colors.red);
}
}

bool _canEditAddresses() {
return widget.userProfile.lastAddressUpdateTime == null ||
DateTime.now()
    .difference(widget.userProfile.lastAddressUpdateTime!.toDate())
    .inDays >=
365;
}

Future<latlong.LatLng?> _geocodeAddress(String address) async {
if (address.isEmpty) return null;
try {
final geocodeUrl = Uri.parse(
'https://maps.googleapis.com/maps/api/geocode/json?address=${Uri.encodeComponent(address)}&key=${dotenv.env['GOOGLE_MAPS_API_KEY']}');
final response = await http.get(geocodeUrl);
if (response.statusCode == 200) {
final data = jsonDecode(response.body);
if (data['results'] != null && data['results'].isNotEmpty) {
final location = data['results'][0]['geometry']['location'];
return latlong.LatLng(location['lat'], location['lng']);
}
} else {
print(
"Erreur géocodage ($address): ${response.statusCode} - ${response.body}");
}
} catch (e) {
print("Exception géocodage pour $address: $e");
}
return null;
}

Future<void> _startWorkCommuteTracking(String commuteType) async {
if (!mounted) return;
bool isCorrectRouteLoaded = (homeController
    .destinationCoordinates.latitude !=
0.0 ||
homeController.destinationCoordinates.longitude != 0.0);

if (!isCorrectRouteLoaded) {
_showSnackBar("Veuillez d'abord calculer l'itinéraire.",
backgroundColor: Colors.orange,
duration: const Duration(seconds: 5));
return;
}

setState(() {
_currentCommuteTypeInProgress = commuteType;
});

navigationController.activeWorkCommuteType = commuteType;

navigationController.navigateToDestination(validateWalkingLegs: _validateWalkingLegs);
_showSnackBar("Début du trajet D-T '$commuteType'.",
backgroundColor: Colors.blue);
}

Future<void> _completeWorkCommute(String commuteType) async {
if (!mounted) return;

int points = _calculateTotalLameGain();
widget.addLamePoints(points, source: "Trajet D-T ($commuteType)");

Map<String, dynamic> updates = {
'last_work_commute_timestamp': FieldValue.serverTimestamp(),
'last_commute_type': commuteType,
'current_work_commute_streak': FieldValue.increment(1),
};

if (commuteType == 'aller') {
updates['last_work_arrival_timestamp'] = FieldValue.serverTimestamp();
}

try {
await _firestore
    .collection('users')
    .doc(widget.userProfile.id)
    .update(updates);
widget.onProfileModified();
_checkReturnTripConditions();
} catch (e) {
_showSnackBar("Erreur lors de la sauvegarde du trajet : $e",
backgroundColor: Colors.red);
}

setState(() {
_currentCommuteTypeInProgress = null;
});
}

Future<void> _checkReturnTripConditions() async {
if (!mounted) return;

final profile = widget.userProfile;
bool conditionsMet = false;

bool allerValidatedToday = false;
if (profile.lastWorkCommuteTimestamp != null &&
profile.lastCommuteType == 'aller') {
if (DateUtils.isSameDay(
profile.lastWorkCommuteTimestamp!.toDate(), DateTime.now())) {
allerValidatedToday = true;
}
}

if (allerValidatedToday) {
bool retourValidatedToday = false;
if (profile.lastCommuteType == 'retour' &&
DateUtils.isSameDay(
profile.lastWorkCommuteTimestamp!.toDate(), DateTime.now())) {
retourValidatedToday = true;
}

if (!retourValidatedToday) {
if (profile.lastWorkArrivalTimestamp != null) {
final arrivalTime = profile.lastWorkArrivalTimestamp!.toDate();
if (DateTime.now().isAfter(arrivalTime.add(const Duration(hours: 3)))) {
if (profile.workAddressCoordinates != null) {
try {
Position currentPos = await Geolocator.getCurrentPosition(
desiredAccuracy: LocationAccuracy.medium);
double distance = toolkit.SphericalUtil.computeDistanceBetween(
toolkit.LatLng(
currentPos.latitude, currentPos.longitude),
toolkit.LatLng(profile.workAddressCoordinates!.latitude,
profile.workAddressCoordinates!.longitude))
    .toDouble();

if (distance <= 200) {
conditionsMet = true;
}
} catch (e) {
print("Could not get location for return trip check: $e");
}
}
}
}
}
}

if (mounted) {
setState(() {
_canStartReturnTrip = conditionsMet;
});
}
}

Widget _buildWorkCommuteInfoSection() {
final profile = widget.userProfile;
String nextCommuteAction = "N/A";
int currentStreak = profile.currentWorkCommuteStreak;
if (profile.lastWorkCommuteTimestamp == null) {
nextCommuteAction = "Effectuer l'aller";
} else {
DateTime lastCommuteDate = profile.lastWorkCommuteTimestamp!.toDate();
DateTime today = DateTime.now();
bool isSameDay = DateUtils.isSameDay(lastCommuteDate, today);
if (profile.lastCommuteType == 'aller' && isSameDay) {
nextCommuteAction = "Effectuer le retour";
} else {
nextCommuteAction = "Effectuer l'aller";
}
}

bool canActivateBoostDt = profile.homeAddressCoordinates != null &&
profile.workAddressCoordinates != null;
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
child: Row(
children: [
const Icon(Icons.commute_rounded, color: accentGold, size: 40),
const SizedBox(width: 12),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text("Infos Domicile-Travail",
style: Theme.of(context).textTheme.headlineSmall?.copyWith(
fontWeight: FontWeight.w600,
color: textDark,
fontSize: 16)),
Text("Série: $currentStreak / Prochain: $nextCommuteAction",
style: Theme.of(context)
    .textTheme
    .bodyMedium
    ?.copyWith(color: textGrey, fontSize: 13)),
Text("Séries protégées: ${profile.monthlyWorkAbsenceAllowance}",
style: Theme.of(context).textTheme.bodyMedium?.copyWith(
color: primaryGreen,
fontWeight: FontWeight.bold,
fontSize: 13)),
],
),
),
const SizedBox(width: 8),
Column(
mainAxisSize: MainAxisSize.min,
children: [
Transform.scale(
scale: 0.8,
child: Switch(
value: _isWorkCommuteBoostActive,
onChanged: canActivateBoostDt
? (val) {
if (mounted) {
setState(
() => _isWorkCommuteBoostActive = val);
_updateGainAndRouteData();
}
}
    : null,
activeColor: primaryGreen,
inactiveThumbColor: canActivateBoostDt
? Colors.grey[300]
    : Colors.grey[400]?.withOpacity(0.5),
inactiveTrackColor: canActivateBoostDt
? Colors.grey[200]
    : Colors.grey[300]?.withOpacity(0.5))),
Text(canActivateBoostDt ? "Boost D-T x1.1" : "Boost Indispo.",
style: TextStyle(
fontSize: 10,
color: (_isWorkCommuteBoostActive && canActivateBoostDt)
? primaryGreen
    : textGrey,
fontWeight:
(_isWorkCommuteBoostActive && canActivateBoostDt)
? FontWeight.bold
    : FontWeight.normal))
],
)
],
),
);
}


// MODIFIÉ: Ajout de l'icône Transport en commun
Widget _buildTravelTypeToggle() {
return Container(
padding: const EdgeInsets.symmetric(horizontal: 20),
child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
_travelTypeIcon(Icons.directions_walk_rounded, TravelType.walk,
_selectedTravelType == TravelType.walk),
Container(
width: 1.5,
height: 25,
color: Colors.grey[300],
margin: const EdgeInsets.symmetric(horizontal: 10)),
_travelTypeIcon(Icons.directions_bike_rounded, TravelType.bike,
_selectedTravelType == TravelType.bike),
Container(
width: 1.5,
height: 25,
color: Colors.grey[300],
margin: const EdgeInsets.symmetric(horizontal: 10)),
_travelTypeIcon(Icons.directions_bus_rounded, TravelType.transit,
_selectedTravelType == TravelType.transit),
]),
);
}


  Widget _travelTypeIcon(IconData icon, TravelType type, bool isSelected) {
    return InkWell(
      onTap: () {
        if (homeController.mapStatus.value == Constants.onDestination) return;
        if (_selectedTravelType != type) {
          setState(() {
            _selectedTravelType = type;
          });

          final newTravelMode = _selectedTravelType == TravelType.walk
              ? TravelMode.walking
              : _selectedTravelType == TravelType.bike
              ? TravelMode.bicycling
              : TravelMode.transit;

          speedController.setExpectedTravelMode(newTravelMode);

          // --- CORRECTION: Forcer le recalcul immédiat pour appliquer le nouveau multiplicateur ---
          // Cela met à jour les lames affichées avant même que l'API Google ne réponde
          _updateGainAndRouteData();

          if (homeController.destination.value.isNotEmpty) {
            homeController.currentTravelMode.value = newTravelMode;
            // On réinitialise l'itinéraire précédent
            homeController.polyline.clear();
            homeController.polylineCoordinates.clear();
            homeController.transitRouteOptions.clear();
            homeController.showTransitOptions.value = false;

            if (newTravelMode != TravelMode.transit) {
              // Pour les autres modes, on recalcule immédiatement
              homeController.drawRoute(homeController.destinationCoordinates);
            } else {
              // Pour le mode transit, on ne fait rien, l'UI affichera les options
              homeController.distanceLeft.value = "";
              homeController.timeLeft.value = "";
            }
            homeController.update();
          }
        }
      },
      borderRadius: BorderRadius.circular(25),
      child: Container(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, color: isSelected ? textDark : Colors.grey[500], size: 30)),
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
margin:
EdgeInsets.only(bottom: _currentMode == HomeScreenMode.trajet ? 0 : 12),
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
child:
Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text(
"${weather.temperature.toStringAsFixed(0)}°C à ${weather.cityOrRegion}",
style: Theme.of(context).textTheme.headlineSmall?.copyWith(
fontWeight: FontWeight.w600, color: textDark, fontSize: 16),
maxLines: 1,
overflow: TextOverflow.ellipsis),
Text(weather.getWeatherDescription(),
style: Theme.of(context)
    .textTheme
    .bodyMedium
    ?.copyWith(color: textGrey, fontSize: 13),
overflow: TextOverflow.ellipsis,
maxLines: 1),
if (weather.minTempToday != null && weather.maxTempToday != null)
Text(
"Min ${weather.minTempToday?.toStringAsFixed(0)}° / Max ${weather.maxTempToday?.toStringAsFixed(0)}°",
style: TextStyle(fontSize: 11, color: Colors.blueGrey[400]))
])),
const SizedBox(width: 8),
if (_currentMode == HomeScreenMode.trajet)
if (weatherBoostIsActive)
const Tooltip(
message: "Boost Météo (x1.5) actif !",
child:
Icon(Icons.shield_moon_rounded, color: primaryGreen, size: 28),
)
else
Tooltip(
message: "Conditions météo normales",
child: Icon(Icons.shield_outlined,
color: Colors.grey[400], size: 28),
)
else
Tooltip(
message: "Boost météo non applicable au Trajet Travail",
child: Icon(Icons.info_outline_rounded,
color: Colors.grey[400], size: 20))
]));
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

String _getMultiplierText() {
List<String> activeBoosts = [];
if (_currentMode == HomeScreenMode.trajet && _isWeatherBoostApplicable()) {
activeBoosts.add("Météo x1.5");
}
if (_currentMode == HomeScreenMode.trajetTravail &&
_isWorkCommuteBoostActive) {
activeBoosts.add("D-T x1.1");
}
if (widget.userProfile.nextLevelBoost > 1.0) {
activeBoosts.add(
"Global x${widget.userProfile.nextLevelBoost.toStringAsFixed(2)}");
}
if (widget.userProfile.isVip) activeBoosts.add("VIP x1.15");
if (widget.userProfile.isAdBoostCurrentlyActive)
activeBoosts.add("AD x1.2");
if (activeBoosts.isEmpty) return "";
return activeBoosts.join(" / ");
}

Widget _buildGainCircle() {
return Obx(() { // On enveloppe tout dans un Obx pour la réactivité
String topText;
int currentTotalGain = homeController.activeRouteEstimatedGain.value;
String totalGainText = currentTotalGain > 0 ? currentTotalGain.toString() : "-";
bool canCalculate = homeController.destination.value.isNotEmpty &&
(homeController.polyline.isNotEmpty || homeController.showTransitOptions.value);

if (_activeStoreTrip != null) {
topText = "GAIN TRAJET";
} else if (_currentMode == HomeScreenMode.trajetTravail) {
topText = "GAIN TRAVAIL";
} else {
topText = "GAIN ESTIMÉ";
}
if (!canCalculate) {
topText = "CALCULER TRAJET";
}
String multiplierText = _getMultiplierText();

return InkWell(
onTap: () {
if (canCalculate && currentTotalGain > 0) {
_showLameCalculationDetails(context);
} else if (canCalculate) {
_showSnackBar("Le gain pour cet itinéraire est de 0.",
backgroundColor: Colors.orange);
} else {
_showSnackBar("Calculez un itinéraire pour voir le gain.",
backgroundColor: Colors.orange);
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

@override
Widget build(BuildContext context) {
return Scaffold(
extendBodyBehindAppBar: true,
appBar: PreferredSize(
preferredSize: const Size.fromHeight(110.0),
child: Obx(() => Visibility(
visible: homeController.mapStatus.value != Constants.onDestination,
child: _buildUpperControlsBar(),
)),
),
body: Stack(
children: [
MapPage(
onValidatePurchase: (store) async {
showDialog(
context: context,
builder: (ctx) => AlertDialog(
title: const Text("Valider l'achat"),
content: Text(
"Pour valider votre achat chez ${store.name}, veuillez aller dans l'onglet 'Magasins' et utiliser le bouton sur la carte du magasin."),
actions: [
TextButton(
child: const Text("OK"),
onPressed: () => Navigator.of(ctx).pop(),
)
],
),
);
},
),
Obx(() => Visibility(
visible: homeController.mapStatus.value == Constants.idle,
child: Positioned(
bottom: 30,
right: 20,
child: FloatingActionButton(
onPressed: () async {
try {
Position position =
await homeController.getMyCurrentLocation();
homeController.moveMapCamera(
LatLng(position.latitude, position.longitude));
} catch (e) {
_showSnackBar("Impossible d'obtenir votre position: $e",
backgroundColor: Colors.red);
}
},
backgroundColor: Colors.white,
child: Image.asset(
Constants.locateMeIcon,
scale: 4,
),
),
),
)),
Obx(() {
final isNavigating =
homeController.mapStatus.value == Constants.onDestination;
final isCameraUnlocked =
!navigationController.isCameraLocked.value;

return Visibility(
visible: isNavigating && isCameraUnlocked,
child: Positioned(
bottom: 80,
right: 20,
child: FloatingActionButton(
onPressed: () async {
navigationController.isCameraLocked.value = true;

try {
Position position =
await homeController.getMyCurrentLocation();
homeController.moveMapCamera(
LatLng(position.latitude, position.longitude),
zoom: 18.5,
bearing: position.heading,
tilt: 60.0,
);
} catch (e) {
_showSnackBar("Impossible de recentrer: $e",
backgroundColor: Colors.red);
}
},
backgroundColor: Colors.blueAccent,
child:
const Icon(Icons.navigation_rounded, color: Colors.white),
tooltip: 'Recentrer',
),
),
);
}),
SpeedometerDisplay(),
Obx(() => Visibility(
visible:
homeController.mapStatus.value == Constants.onDestination,
child: Positioned(
top: MediaQuery.of(context).padding.top + 10,
left: 0,
right: 0,
child: DirectionsStatusBar(onValidatePurchase: () async {
Get.snackbar(
"Action requise",
"Veuillez retourner à l'onglet 'Magasins' pour valider votre achat.",
snackPosition: SnackPosition.BOTTOM,
backgroundColor: Colors.blueAccent,
colorText: Colors.white,
);
navigationController.stopNavigation();
})),
)),

Obx(() => Visibility(
visible: homeController.mapStatus.value != Constants.idle,
child: const Positioned(
bottom: 0,
left: 0,
right: 0,
child: BottomBar(),
),
)),

Obx(() => Visibility(
visible: homeController.mapStatus.value != Constants.onDestination,
child: _buildDraggableSheet())),
],
),
);
}
}

enum StoreSortOption { proximity, profitability }

class StoresScreen extends StatefulWidget {
  final List<EcoStore> ecoStores;
  final Function(EcoStore, TravelType) onStartTrip;
  final UserProfile userProfile;
  final Function(int, {String? source}) onAddLame;
  final WeatherData? weatherData;

  const StoresScreen({
    Key? key,
    required this.ecoStores,
    required this.onStartTrip,
    required this.userProfile,
    required this.onAddLame,
    this.weatherData,
  }) : super(key: key);

  @override
  _StoresScreenState createState() => _StoresScreenState();
}


class _StoresScreenState extends State<StoresScreen> {
  // --- ÉTATS DU FILTRE ET TRI ---
  StoreSortOption _currentSort = StoreSortOption.proximity;
  bool _useRadius = true; // Par défaut activé
  double _radiusKm = 20.0; // Par défaut 20km

  // --- PAGINATION ---
  int _visibleCount = 10; // On affiche 10 par défaut

  // --- DONNÉES LOCALES ---
  List<EcoStore> _sortedStores = [];
  latlong.LatLng? _userPosition;
  bool _isLoadingLoc = true;

  @override
  void initState() {
    super.initState();
    _initLocationAndData();
  }

  // Initialisation : On récupère la position GPS une seule fois au chargement
  Future<void> _initLocationAndData() async {
    try {
      Position p = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      _userPosition = latlong.LatLng(p.latitude, p.longitude);
    } catch (e) {
      print("Erreur localisation StoresScreen: $e");
      // Position par défaut (ex: Domicile utilisateur ou centre ville par défaut)
      _userPosition = widget.userProfile.homeAddressCoordinates ?? latlong.LatLng(45.75, 4.85);
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLoc = false;
        });
        _applySortAndFilter(); // On applique le tri dès qu'on a la position
      }
    }
  }

  // C'est ici que toute la logique de tri demandée se trouve
  void _applySortAndFilter() {
    if (_userPosition == null) return;

    List<EcoStore> tempStores = List.from(widget.ecoStores);

    // Pré-calcul des distances pour éviter de le refaire à chaque comparaison
    Map<String, double> distances = {};
    for (var store in tempStores) {
      // CORRECTION ICI : Utilisation de Geolocator pour la distance (en mètres) puis conversion en km
      double distMeters = Geolocator.distanceBetween(
          _userPosition!.latitude,
          _userPosition!.longitude,
          store.coordinates.latitude,
          store.coordinates.longitude
      );
      distances[store.id] = distMeters / 1000.0; // Distance en km
    }

    // 1. FILTRAGE PAR RAYON
    // Si le rayon est activé, on retire les magasins trop loin.
    if (_useRadius) {
      tempStores = tempStores.where((s) => (distances[s.id] ?? 99999) <= _radiusKm).toList();
    }

    // 2. TRI (Logique Gold + Critère choisi)
    tempStores.sort((a, b) {
      // Règle 1 : Les magasins Gold (Visibility Boost) apparaissent TOUJOURS en premier
      if (a.isVisibilityBoostEnabled && !b.isVisibilityBoostEnabled) return -1;
      if (!a.isVisibilityBoostEnabled && b.isVisibilityBoostEnabled) return 1;

      // Règle 2 : Tri selon l'option choisie
      if (_currentSort == StoreSortOption.proximity) {
        // Le plus proche d'abord
        double distA = distances[a.id] ?? 99999;
        double distB = distances[b.id] ?? 99999;
        return distA.compareTo(distB);
      } else {
        // Le plus rentable (Cashback le plus haut) d'abord
        return b.cashbackRate.compareTo(a.cashbackRate);
      }
    });

    // 3. FALLBACK : Si le rayon ne donne rien, on prend les meilleurs hors rayon (Top 10)
    // pour éviter une page vide, sauf si l'utilisateur veut vraiment filtrer strict.
    // (Optionnel : ici je laisse le filtrage strict demandé, mais je propose un bouton dans l'UI pour désactiver)

    setState(() {
      _sortedStores = tempStores;
      // Reset pagination si nécessaire
      if (_visibleCount > _sortedStores.length && _sortedStores.isNotEmpty) {
        // On garde la logique simple
      }
    });
  }

  void _loadMore() {
    setState(() {
      _visibleCount += 10;
    });
  }

  @override
  Widget build(BuildContext context) {
    // On coupe la liste triée pour la pagination
    final displayList = _sortedStores.take(_visibleCount).toList();
    final bool hasMore = _visibleCount < _sortedStores.length;

    return Scaffold(
      backgroundColor: defisScreenBackground,
      // Bouton Espace Pro
      floatingActionButton: FloatingActionButton.extended(
        heroTag: "btn_merchant_dashboard",
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(
              builder: (_) => MerchantDashboard(userProfile: widget.userProfile)
          ));
        },
        label: const Text("Espace Pro"),
        icon: const Icon(Icons.storefront),
        backgroundColor: Colors.white,
        foregroundColor: textDark,
        elevation: 4,
      ),
      body: Column(
        children: [
          // --- BARRE DE CONTRÔLE (TRI & RAYON) ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), offset: const Offset(0, 2), blurRadius: 5)],
            ),
            child: Column(
              children: [
                // Ligne 1 : Tri
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Trier par :", style: TextStyle(fontWeight: FontWeight.bold, color: textGrey)),
                    DropdownButton<StoreSortOption>(
                      value: _currentSort,
                      icon: const Icon(Icons.sort, color: primaryGreen),
                      underline: Container(), // Retire la ligne par défaut
                      style: const TextStyle(color: primaryGreen, fontWeight: FontWeight.bold),
                      items: const [
                        DropdownMenuItem(value: StoreSortOption.proximity, child: Text("Proximité")),
                        DropdownMenuItem(value: StoreSortOption.profitability, child: Text("Rentabilité")),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _currentSort = val);
                          _applySortAndFilter();
                        }
                      },
                    ),
                  ],
                ),
                // Ligne 2 : Rayon
                Row(
                  children: [
                    SizedBox(
                      height: 24,
                      width: 24,
                      child: Checkbox(
                        value: _useRadius,
                        activeColor: primaryGreen,
                        onChanged: (v) {
                          setState(() => _useRadius = v ?? true);
                          _applySortAndFilter();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_useRadius ? "${_radiusKm.round()} km" : "∞", style: const TextStyle(fontWeight: FontWeight.bold)),
                    Expanded(
                      child: Slider(
                        value: _radiusKm,
                        min: 5,
                        max: 100,
                        divisions: 19,
                        activeColor: _useRadius ? primaryGreen : Colors.grey,
                        inactiveColor: Colors.grey[200],
                        label: "${_radiusKm.round()} km",
                        onChanged: _useRadius ? (val) {
                          setState(() => _radiusKm = val);
                        } : null,
                        onChangeEnd: (val) => _applySortAndFilter(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // --- LISTE DES MAGASINS ---
          Expanded(
            child: _isLoadingLoc
                ? const Center(child: CircularProgressIndicator(color: primaryGreen))
                : _sortedStores.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.location_off, size: 50, color: Colors.grey),
                  const SizedBox(height: 10),
                  const Text("Aucun magasin trouvé dans ce rayon."),
                  if (_useRadius)
                    TextButton(
                        onPressed: () {
                          setState(() {
                            _useRadius = false; // Désactive le rayon pour montrer les résultats
                            _applySortAndFilter();
                          });
                        },
                        child: const Text("Afficher tout sans limite")
                    )
                ],
              ),
            )
                : RefreshIndicator(
              onRefresh: () async => await _initLocationAndData(),
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12.0, 12.0, 12.0, 80.0), // Padding bas pour le FAB
                // +1 pour le bouton "Charger plus"
                itemCount: displayList.length + 1,
                itemBuilder: (context, index) {
                  // Bouton Charger Plus à la fin
                  if (index == displayList.length) {
                    if (hasMore) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        child: Center(
                          child: OutlinedButton(
                            onPressed: _loadMore,
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: const Text("Charger plus de magasins"),
                          ),
                        ),
                      );
                    } else {
                      return const SizedBox.shrink(); // Fin de liste
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

  const StoreCard({
    Key? key,
    required this.store,
    required this.onStartTrip,
    required this.userPositionForCalcul,
    required this.userProfile,
    required this.onAddLame,
    this.weatherData,
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
    setState(() => _isLoading = true);

    try {
      latlong.LatLng userPos = await widget.userPositionForCalcul();
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

      double durationMins = 15;
      double distKm = 1.0;

      await directionsService.route(
          request, (DirectionsResult response, status) {
        if (status == DirectionsStatus.ok && response.routes!.isNotEmpty) {
          final leg = response.routes!.first.legs!.first;
          durationMins = (leg.duration!.value! / 60.0);
          distKm = (leg.distance!.value! / 1000.0);
        }
      });

      // Calcul des Lames (Utilisation de doubles pour éviter le 0 intempestif)
      const double W_DIST = 5.0;
      const double W_DUREE = 0.5;

      double effort = (distKm * W_DIST) + (durationMins * W_DUREE);

      double mult = 1.0;
      if (_selectedTravelType == TravelType.bike) mult = 1.2;
      if (_selectedTravelType == TravelType.transit) mult = 0.8;

      // Bonus de niveau, VIP, etc. devraient idéalement être appliqués ici aussi si on veut être cohérent avec le Home
      if (widget.userProfile.nextLevelBoost > 1.0)
        effort *= widget.userProfile.nextLevelBoost;
      if (widget.userProfile.isVip) effort *= 1.15;
      if (widget.userProfile.isAdBoostCurrentlyActive) effort *= 1.2;

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
        if (_totalLameGain == 0 && distKm > 0)
          _totalLameGain = 1; // Minimum 1 si trajet existe
        _durationText = "${durationMins.round()} min";
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
                  )
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

              // --- ACTIONS (Y ALLER / VALIDER) ---
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        widget.onStartTrip(widget.store, _selectedTravelType),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: isGold
                          ? Colors.amber[700]!
                          : primaryGreen),
                      foregroundColor: isGold
                          ? Colors.amber[900]!
                          : primaryGreen,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.near_me),
                        const SizedBox(width: 5),
                        Text("Y aller ${_totalLameGain != null
                            ? '($_totalLameGain L)'
                            : ''}"),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: ElevatedButton.icon(
                        icon: const Icon(Icons.receipt),
                        label: const Text("Valider"),
                        onPressed: () {
                          /* Fonction de validation future */
                        },
                        style: ElevatedButton.styleFrom(
                            backgroundColor: primaryGreen,
                            foregroundColor: Colors.white)
                    )
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class ShopScreen extends StatelessWidget {
final UserProfile userProfile;

final Function(int cost) onPurchase;

ShopScreen({Key? key, required this.userProfile, required this.onPurchase}) : super(key: key);

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
await _firestore.collection('users').doc(userProfile.id).update({
'lame_points': FieldValue.increment(-item.costLame),
'updated_at': FieldValue.serverTimestamp(),
});
if (context.mounted) {
ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text('${item.name} acheté!'), backgroundColor: Colors.green));
}
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

const ProfileBottomSheet({Key? key, required this.userProfile, required this.onOpenShop}) : super(key: key);

void _showPremiumDialog(BuildContext context) {
showDialog(
context: context,
builder: (BuildContext dialogContext) {
return AlertDialog(
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
title: Row(
children: const [
Icon(Icons.workspace_premium, color: accentGold),
SizedBox(width: 8),
Text("Avantages Premium"),
],
),
content: Column(
mainAxisSize: MainAxisSize.min,
crossAxisAlignment: CrossAxisAlignment.start,
children: const [
Text("Devenez membre Premium pour débloquer :"),
SizedBox(height: 12),
_PremiumBenefit(icon: Icons.search, text: "Recherche d'adresse complète (pas seulement commerces)"),
_PremiumBenefit(icon: Icons.local_offer_outlined, text: "Accès à des offres exclusives partenaires"),
_PremiumBenefit(icon: Icons.no_accounts, text: "Aucun montant d'achat minimum requis chez les partenaires"),
_PremiumBenefit(icon: Icons.star_border_rounded, text: "Et bien plus à venir !"),
],
),
actions: <Widget>[
TextButton(
child: const Text("Fermer"),
onPressed: () => Navigator.of(dialogContext).pop(),
),
ElevatedButton(
child: const Text("Obtenir Premium"),
onPressed: () {
Navigator.of(dialogContext).pop();
ScaffoldMessenger.of(context).showSnackBar(
const SnackBar(content: Text("Fonctionnalité d'achat à venir !")),
);
},
),
],
);
},
);
}

@override
Widget build(BuildContext context) {
return Container(
padding: const EdgeInsets.all(20),
decoration: const BoxDecoration(
color: cardWhite,
borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
child: Column(
mainAxisSize: MainAxisSize.min,
children: [
CircleAvatar(
radius: 40,
backgroundColor: primaryGreen,
child: Text(
userProfile.username.isNotEmpty ? userProfile.username.substring(0, 1).toUpperCase() : "U",
style: const TextStyle(fontSize: 30, color: Colors.white))),
const SizedBox(height: 12),
Text(userProfile.username, style: Theme.of(context).textTheme.headlineMedium),
if (userProfile.isVip)
const Chip(
label: Text('Membre VIP'),
avatar: Icon(Icons.workspace_premium, color: accentGold),
backgroundColor: accentGold)
else
Padding(
padding: const EdgeInsets.only(top: 8.0),
child: OutlinedButton.icon(
onPressed: () => _showPremiumDialog(context),
icon: const Icon(Icons.workspace_premium_outlined, color: accentGold),
label: const Text("Obtenir Premium", style: TextStyle(color: accentGold)),
style: OutlinedButton.styleFrom(
side: const BorderSide(color: accentGold),
backgroundColor: accentGold.withOpacity(0.1)
),
),
),
const SizedBox(height: 15),
const Divider(),
ListTile(
leading: const Icon(Icons.eco_rounded, color: accentGold),
title: Text('${userProfile.lamePoints} Lame Points')),
ListTile(
leading: const Icon(Icons.trending_up_rounded, color: primaryGreen),
title: Text('Niveau ${userProfile.currentLevel}')),
ListTile(
leading: const Icon(Icons.login_rounded, color: textGrey),
title: Text('${userProfile.consecutiveLogins} jours de connexion')),
const Divider(),
const SizedBox(height: 10),
ElevatedButton.icon(
icon: const Icon(Icons.store_rounded),
label: const Text('Ouvrir la Boutique'),
onPressed: onOpenShop,
style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 45))),
const SizedBox(height: 10),
TextButton(
onPressed: () => Navigator.pop(context),
child: const Text("Fermer", style: TextStyle(color: textGrey))),
],
),
);
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



Future<bool> _spendLamePoints(double amount, String offerIdContext, String offerTitleContext) async {
final currentUser = FirebaseAuth.instance.currentUser;
if (currentUser == null) {
if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Erreur: Utilisateur non connecté."), backgroundColor: Colors.red));
return false;
}

if (widget.userProfile.lamePoints < amount) {
if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pas assez de Lame Points!"), backgroundColor: Colors.orange));
return false;
}

final userRef = firestore.collection('users').doc(currentUser.uid);
final claimedOfferRef = firestore.collection('user_claimed_offers').doc();

try {
await firestore.runTransaction((transaction) async {
transaction.update(userRef, {'lame_points': FieldValue.increment(-amount)});
transaction.set(claimedOfferRef, {
'user_id': currentUser.uid,
'reward_id': offerIdContext,
'details': {'claimed_for_lame': amount, 'offer_title': offerTitleContext},
'claimed_at': FieldValue.serverTimestamp(),
});
});


await widget.onPurchase(amount.toInt());
return true;

} catch(error) {
print("Erreur de transaction Firestore: $error");
if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Erreur serveur: $error"), backgroundColor: Colors.red));
return false;
}
}
Future<void> _handleGenericLameSpend(double lameCost, String idContext, String titleContext, {String? successMessage, VoidCallback? onSuccess}) async {
bool success = await _spendLamePoints(lameCost, idContext, titleContext);
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

final Future<bool> Function(double amount, String offerId, String offerTitle) onClaimOffer;

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

Future<void> _claimOffer() async {
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
content: Text("Voulez-vous vraiment utiliser ${cost.toStringAsFixed(0)} Lame Points pour obtenir \"${widget.offer.title}\" ?"),
actions: [
TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("Annuler")),
ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Confirmer")),
],
),
);

if (confirmed != true) return;


setState(() => _isClaiming = true);
try {
final bool success = await widget.onClaimOffer(cost, widget.offer.id, widget.offer.title);

if (success) {
setState(() {
_isOfferClaimed = true;
});
ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
content: Text("Offre obtenue avec succès !"),
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


if (_isOfferClaimed && widget.offer.detailsJson?['code'] != null) ...[
const SizedBox(height: 24),
Text("Votre Code Promo:", style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
const SizedBox(height: 8),
Container(
padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
decoration: BoxDecoration(
color: Colors.teal.shade50,
borderRadius: BorderRadius.circular(8),
border: Border.all(color: Colors.teal.shade200)),
child: SelectableText(
widget.offer.detailsJson!['code'],
style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal.shade700),
),
),
],
],
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

final campaignDoc = await transaction.get(campaignRef);
final userStatsDoc = await transaction.get(userStatsRef);

if (!campaignDoc.exists || campaignDoc.data() == null) {
throw Exception("Campagne non trouvée.");
}
if (!userStatsDoc.exists || userStatsDoc.data() == null) {
throw Exception("Statistiques utilisateur non trouvées.");
}

final currentCampaignDetails = campaignDoc.data()!['details_json'] as Map<String, dynamic>? ?? {};
final currentUserStatsData = userStatsDoc.data()!;


final double currentLamePoints = (currentUserStatsData['totalLameGained'] as num?)?.toDouble() ?? 0.0;
if (currentLamePoints < amount) {
throw Exception("Fonds insuffisants.");
}


transaction.update(userStatsRef, {'totalLameGained': FieldValue.increment(-amount.toDouble())});
final userStatsProvider = Provider.of<UserStatsProvider>(context, listen: false);
userStatsProvider.addLame(-amount.toDouble());


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


_firestore.collection('campaign_donations').add({
'campaign_id': widget.offer.id,
'user_id': currentUserId,
'amount_eco': amount.toDouble(),
'created_at': FieldValue.serverTimestamp(),
});
});

if (mounted) {
Navigator.of(context).pop();
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text("Merci pour votre don de $amount Lame Points à ${widget.offer.title}!"), backgroundColor: Colors.green));

_fetchCampaignDetails();
donationController.clear();
}
} catch (e) {
if (mounted) {
Navigator.of(context).pop();
print("Erreur de transaction Firestore (donation): $e");
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text("Erreur de communication: ${e.toString().split("\n").first}"), backgroundColor: Colors.red));
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
