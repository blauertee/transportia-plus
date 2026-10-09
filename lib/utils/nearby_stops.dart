import 'dart:math' as math;

import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/stop_time.dart';
import '../services/transitous_map_service.dart';
import 'geo_utils.dart';

/// Metres each way from the rider that stops are looked for, which is as far
/// as most people will walk to a departure they can see on a list.
const double kNearbyStopsRadiusMetres = 500;

/// The most stops listed; each one is a request for its departures.
const int kNearbyStopsLimit = 5;

/// A box [kNearbyStopsRadiusMetres] each way around [center].
LatLngBounds nearbyStopsBounds(LatLng center) {
  const metresPerDegreeOfLatitude = 111320.0;
  final latitudeDelta = kNearbyStopsRadiusMetres / metresPerDegreeOfLatitude;
  // A degree of longitude shrinks towards the poles; the clamp keeps the box
  // finite there.
  final longitudeDelta =
      latitudeDelta /
      math.cos(center.latitude * math.pi / 180).clamp(0.01, 1.0);
  return LatLngBounds(
    southwest: LatLng(
      center.latitude - latitudeDelta,
      center.longitude - longitudeDelta,
    ),
    northeast: LatLng(
      center.latitude + latitudeDelta,
      center.longitude + longitudeDelta,
    ),
  );
}

/// The [limit] stops with an id closest to [center], nearest first.
///
/// A stop without an id cannot be asked for its departures, so it is no use
/// here however close it is.
List<MapStop> nearestStops(
  List<MapStop> stops,
  LatLng center, {
  int limit = kNearbyStopsLimit,
}) {
  double distance(MapStop stop) => coordinateDistanceInMeters(
    center.latitude,
    center.longitude,
    stop.lat,
    stop.lon,
  );
  final withIds = [
    for (final stop in stops)
      if (stop.stopId != null && stop.stopId!.isNotEmpty) stop,
  ]..sort((a, b) => distance(a).compareTo(distance(b)));
  return withIds.take(limit).toList();
}

/// When [stopTime] leaves, or arrives where it does not leave again.
DateTime? departureKey(StopTime stopTime) {
  final place = stopTime.place;
  return place.departure ??
      place.scheduledDeparture ??
      place.arrival ??
      place.scheduledArrival;
}

/// What the stops would show, as one string per stop: its name and the trips
/// and times it would list.
///
/// A backend may split one physical stop into several ids — platforms,
/// directions, or plain duplicates — that all serve the same departures. Two
/// stops with the same name and the same trips at the same times are that one
/// stop, and it should be listed once.
String departuresSignature(String stopName, List<StopTime> departures) {
  final trips = departures
      .map((d) => '${d.tripId}@${departureKey(d)?.toIso8601String()}')
      .join('|');
  return '${stopName.trim().toLowerCase()}::$trips';
}
