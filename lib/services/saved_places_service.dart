import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/prefs_keys.dart';
import '../models/saved_place.dart';
import '../models/transitous/enums.dart';
import '../utils/stored_list.dart';
import 'transitous_geocode_service.dart';

enum SavedPlacesBucket { search, timetable }

class SavedPlacesService {
  static const String _searchKey = PrefsKeys.savedPlacesSearch;
  static const String _timetableKey = PrefsKeys.savedPlacesTimetable;
  static const int maxPlaces = 50;
  static const int importanceStep = 3;
  static const int initialImportance = 15;

  static Future<List<SavedPlace>> loadPlaces({
    required SavedPlacesBucket bucket,
  }) async {
    final prefs = SharedPreferencesAsync();
    final raw = await prefs.getString(_keyFor(bucket));
    return _normalize(decodeStoredList(raw, SavedPlace.fromJson));
  }

  static Future<void> savePlaces({
    required SavedPlacesBucket bucket,
    required List<SavedPlace> places,
  }) async {
    final prefs = SharedPreferencesAsync();
    final normalized = _normalize(places);
    final encoded = jsonEncode(
      normalized.map((place) => place.toJson()).toList(growable: false),
    );
    await prefs.setString(_keyFor(bucket), encoded);
  }

  static List<SavedPlace> applySelection(
    List<SavedPlace> places,
    SavedPlace selected,
  ) {
    final normalizedKey = selected.key;
    final updated = <SavedPlace>[];
    bool matched = false;

    for (final place in places) {
      if (place.key == normalizedKey) {
        matched = true;
        updated.add(
          place.copyWith(
            name: selected.name,
            type: selected.type,
            lat: selected.lat,
            lon: selected.lon,
            importance: place.importance + importanceStep,
            // Backfills the id onto a place stored before it was recorded, so
            // re-picking a stop makes its timetable reachable again.
            stopId: selected.stopId ?? place.stopId,
            city: selected.city ?? place.city,
            countryCode: selected.countryCode ?? place.countryCode,
            // A pick from the recents list itself carries what was stored; a
            // geocoder answer can say nothing for a stop that has modes.
            modes: selected.modes.isNotEmpty ? selected.modes : place.modes,
          ),
        );
      } else {
        final nextImportance = place.importance - 1;
        if (nextImportance > 0) {
          updated.add(place.copyWith(importance: nextImportance));
        }
      }
    }

    if (!matched) {
      updated.add(selected.copyWith(importance: initialImportance));
    }

    return _normalize(updated);
  }

  /// Records that [suggestion] was picked, and returns the bucket's new
  /// contents. Persisting happens in the background, so the caller can show
  /// the updated list at once.
  ///
  /// Returns [places] unchanged for a suggestion with no name, which is not
  /// worth remembering and would sort as an empty row.
  static List<SavedPlace> recordSelection({
    required SavedPlacesBucket bucket,
    required List<SavedPlace> places,
    required TransitousLocationSuggestion suggestion,
  }) {
    final name = suggestion.name.trim();
    if (name.isEmpty) return places;

    final updated = applySelection(
      places,
      SavedPlace(
        name: name,
        type: suggestion.type,
        lat: suggestion.lat,
        lon: suggestion.lon,
        importance: SavedPlace.defaultImportance,
        stopId: suggestion.stopId,
        city: suggestion.defaultArea,
        countryCode: suggestion.country,
        modes: suggestion.modes,
      ),
    );
    unawaited(savePlaces(bucket: bucket, places: updated));
    return updated;
  }

  /// Records what serves the stop with [stopId], wherever it is remembered.
  ///
  /// A departure board says which modes call at its stop, so opening one fills
  /// in a recent that was stored before modes were, or picked from the recents
  /// list, which never asks the geocoder again. Nothing is written when no
  /// recent is that stop or it already says the same.
  static Future<void> recordModes({
    required SavedPlacesBucket bucket,
    required String stopId,
    required List<TransitMode> modes,
  }) async {
    if (modes.isEmpty) return;
    final places = await loadPlaces(bucket: bucket);
    var changed = false;
    for (var i = 0; i < places.length; i++) {
      final place = places[i];
      if (place.stopId != stopId || listEquals(place.modes, modes)) continue;
      places[i] = place.copyWith(modes: modes);
      changed = true;
    }
    if (!changed) return;
    await savePlaces(bucket: bucket, places: places);
  }

  static List<SavedPlace> _normalize(List<SavedPlace> places) {
    final filtered = [
      for (final place in places)
        if (place.importance > 0 && place.name.trim().isNotEmpty) place,
    ];
    filtered.sort((a, b) {
      final diff = b.importance.compareTo(a.importance);
      if (diff != 0) return diff;
      return a.name.compareTo(b.name);
    });
    if (filtered.length > maxPlaces) {
      filtered.removeRange(maxPlaces, filtered.length);
    }
    return filtered;
  }

  static String _keyFor(SavedPlacesBucket bucket) {
    return switch (bucket) {
      SavedPlacesBucket.search => _searchKey,
      SavedPlacesBucket.timetable => _timetableKey,
    };
  }
}
