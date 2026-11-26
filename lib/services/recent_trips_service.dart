import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../constants/prefs_keys.dart';
import '../models/itinerary.dart';
import '../models/saved_trip.dart';
import '../utils/stored_list.dart';

/// The connections the rider most recently opened, kept as [SavedTrip]s.
///
/// A recent trip is a saved trip nobody asked to keep: the same snapshot of
/// a real departure, so reopening one shows that journey rather than
/// searching the same two places again. They live under their own key, so
/// the saved trips screen never lists them and saving one is still a
/// deliberate act.
///
/// Recorded when a result is opened, not when a search is run: a search
/// names two places, and the picker already offers recent places. What only
/// this list can give back is the connection itself.
class RecentTripsService {
  const RecentTripsService._();

  static const String _key = PrefsKeys.recentTrips;

  /// How many are kept. The card lists every one of them, so this is also
  /// how long that list can get.
  static const int maxTrips = 5;

  /// Puts [itinerary] at the top, replacing the same connection if it was
  /// already there. Silently skips an itinerary the planner did not produce,
  /// which has no snapshot to keep.
  static Future<void> record(
    Itinerary itinerary, {
    String? fromName,
    String? toName,
    DateTime? now,
  }) async {
    final SavedTrip trip;
    try {
      trip = SavedTrip.fromItinerary(
        itinerary: itinerary,
        fromName: fromName,
        toName: toName,
        savedAt: now,
      );
    } on ArgumentError {
      return;
    }

    final prefs = SharedPreferencesAsync();
    final trips = await getRecentTrips()
      ..removeWhere((t) => t.id == trip.id)
      ..insert(0, trip);
    await prefs.setString(
      _key,
      jsonEncode([for (final t in trips.take(maxTrips)) t.toJson()]),
    );
  }

  /// Most recently opened first.
  static Future<List<SavedTrip>> getRecentTrips() async {
    try {
      return decodeStoredList(
        await SharedPreferencesAsync().getString(_key),
        SavedTrip.fromJson,
      );
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearHistory() async {
    await SharedPreferencesAsync().remove(_key);
  }
}
