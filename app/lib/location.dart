import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

/// Current GPS position, or throws a readable message. Never waits forever:
/// if the phone/browser does not answer (e.g. the permission pop-up was ignored) it gives up after 25 s.
Future<({double lat, double lng})> currentLocation() async {
  try {
    return await _locate().timeout(const Duration(seconds: 25));
  } on TimeoutException {
    throw 'Could not get your location. Allow location access when asked (check the address bar in a browser), '
        'or type the location instead.';
  } on LocationServiceDisabledException {
    throw 'Location services are turned off. Turn them on or type the location instead.';
  } on PermissionDeniedException {
    throw 'Location permission was denied. Allow it in settings or type the location instead.';
  } on String {
    rethrow;
  } catch (_) {
    throw 'Could not get your location. Type the location instead.';
  }
}

Future<({double lat, double lng})> _locate() async {
  // On the web the browser decides; this check is unreliable there, so skip it.
  if (!kIsWeb && !await Geolocator.isLocationServiceEnabled()) {
    throw 'Location services are turned off. Turn them on or type the location instead.';
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
  if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
    throw 'Location permission was denied. Allow it in settings or type the location instead.';
  }
  final p = await Geolocator.getCurrentPosition(
    locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 15)),
  );
  return (lat: p.latitude, lng: p.longitude);
}

/// Straight-line distance in km between two GPS points.
double kmBetween(double lat1, double lng1, double lat2, double lng2) {
  double rad(double d) => d * math.pi / 180;
  final h = math.pow(math.sin(rad(lat2 - lat1) / 2), 2) +
      math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(rad(lng2 - lng1) / 2), 2);
  return 2 * 6371 * math.asin(math.sqrt(h.toDouble()));
}

/// Is the point inside the polygon of [lat, lng] pairs?
bool insidePolygon(double lat, double lng, List<List<double>> ring) {
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final yi = ring[i][0], xi = ring[i][1], yj = ring[j][0], xj = ring[j][1];
    if ((yi > lat) != (yj > lat) && lng < (xj - xi) * (lat - yi) / (yj - yi) + xi) inside = !inside;
  }
  return inside;
}
