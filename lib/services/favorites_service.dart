import 'package:flutter/foundation.dart';
import '../constants/prefs_keys.dart';
import '../utils/geo_utils.dart';
import 'stored_list_store.dart';

class FavoritePlace {
  final String id;

  /// What the place is actually called, as searched for.
  ///
  /// Kept even when the place is renamed, so clearing the alias restores it
  /// rather than leaving the place nameless.
  final String name;

  /// The rider's name for it — "Home", "Work". Null means [name] stands.
  final String? label;

  final double lat;
  final double lon;
  final DateTime addedAt;
  final String iconName;

  /// What the geocoder called this place — `STOP`, `ADDRESS`, `PLACE`.
  ///
  /// Kept so a screen can ask which favourites are stations without
  /// re-geocoding them; the timetable screen offers only those.
  final String type;

  /// The feed's id for this stop, when the place was saved from one.
  ///
  /// Null for anywhere that is not a stop, and for stops favourited before the
  /// app started recording it.
  final String? stopId;

  const FavoritePlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.addedAt,
    this.label,
    this.type = 'PLACE',
    this.stopId,
    this.iconName = defaultIconName,
  });

  /// The icon a place is kept with until the rider picks one.
  static const String defaultIconName = 'mapPin';

  bool get isStation => type.toUpperCase() == 'STOP';

  /// Whether a departure board can be opened for this place. A station whose
  /// id was never recorded cannot answer one, so it is not offered.
  bool get hasTimetable => isStation && (stopId?.isNotEmpty ?? false);

  /// What to show. The alias when there is one, the searched name otherwise.
  String get displayName => (label?.trim().isNotEmpty ?? false) ? label! : name;

  /// True when the alias says something the searched name does not, so a row
  /// can show both without repeating itself.
  bool get hasAlias => displayName != name;

  FavoritePlace copyWith({
    String? id,
    String? name,
    String? label,
    bool clearLabel = false,
    String? type,
    String? stopId,
    double? lat,
    double? lon,
    DateTime? addedAt,
    String? iconName,
  }) {
    return FavoritePlace(
      id: id ?? this.id,
      name: name ?? this.name,
      label: clearLabel ? null : (label ?? this.label),
      type: type ?? this.type,
      stopId: stopId ?? this.stopId,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      addedAt: addedAt ?? this.addedAt,
      iconName: iconName ?? this.iconName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'label': label,
      'type': type,
      'stopId': stopId,
      'lat': lat,
      'lon': lon,
      'addedAt': addedAt.toIso8601String(),
      'iconName': iconName,
    };
  }

  factory FavoritePlace.fromJson(Map<String, dynamic> json) {
    return FavoritePlace(
      id: json['id'] as String,
      name: json['name'] as String,
      label: json['label'] as String?,
      type: json['type'] as String? ?? 'PLACE',
      stopId: json['stopId'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      addedAt: DateTime.parse(json['addedAt'] as String),
      iconName: json['iconName'] as String? ?? defaultIconName,
    );
  }
}

class FavoritesService {
  static final StoredListStore<FavoritePlace> _store = StoredListStore(
    key: PrefsKeys.favoritePlaces,
    fromJson: FavoritePlace.fromJson,
    toJson: (place) => place.toJson(),
  );
  static final ValueNotifier<List<FavoritePlace>> favoritesListenable =
      ValueNotifier<List<FavoritePlace>>(<FavoritePlace>[]);

  static Future<List<FavoritePlace>> getFavorites() async {
    final favourites = await _store.read();
    favoritesListenable.value = List.unmodifiable(favourites);
    return favourites;
  }

  static Future<void> saveFavorite(FavoritePlace place) async {
    await _update((favorites) {
      if (favorites.any((f) => f.id == place.id)) return false;
      favorites.insert(0, place);
      return true;
    });
  }

  static Future<void> removeFavorite(String id) async {
    await _update((favorites) {
      final before = favorites.length;
      favorites.removeWhere((f) => f.id == id);
      return favorites.length < before;
    });
  }

  static Future<void> updateFavorite(FavoritePlace updatedPlace) async {
    await _update((favorites) {
      final index = favorites.indexWhere((f) => f.id == updatedPlace.id);
      if (index == -1) return false;
      favorites[index] = updatedPlace;
      return true;
    });
  }

  static Future<void> reorderFavorites(List<FavoritePlace> reordered) async {
    await _update((favorites) {
      favorites
        ..clear()
        ..addAll(reordered);
      return true;
    });
  }

  /// The favourite at these coordinates among those loaded, if there is one.
  ///
  /// Synchronous, for drawing a heart: it reads the list as last loaded,
  /// and finds nothing before the first load. Anything that changes what is
  /// stored decides on the stored list instead, as [toggleAt] does.
  ///
  /// Matched on position rather than id: a place hearted from a search and the
  /// same place reached from a deep link carry different ids, and a rider
  /// would not call them two places. Five decimals is about a metre.
  static FavoritePlace? findAt(double lat, double lon) {
    final key = _coordinateKey(lat, lon);
    for (final favourite in favoritesListenable.value) {
      if (_coordinateKey(favourite.lat, favourite.lon) == key) return favourite;
    }
    return null;
  }

  /// Five decimals is ~1 m — close enough that two coordinates naming the
  /// same doorway agree, far enough that neighbouring stops do not.
  static const int _coordinateKeyDecimals = 5;

  static String _coordinateKey(double lat, double lon) =>
      coordKey(lat, lon, decimals: _coordinateKeyDecimals);

  /// Adds a place, or removes it when it is already there.
  ///
  /// Decided on the stored list, in turn with every other change, rather
  /// than on what was loaded: a heart tapped before the list has loaded, or
  /// twice in quick succession, must not keep the same place twice.
  ///
  /// [isListed] says whether the screen that asked shows a kept place. One
  /// it does not show, though the heart was tapped on it, is a stop kept
  /// before stop ids were recorded: given a [stopId], it is filled in rather
  /// than let go, which lists it.
  ///
  /// Returns the favourite as kept afterwards, or null when it was let go,
  /// so the caller can say which happened.
  static Future<FavoritePlace?> toggleAt({
    required String name,
    required double lat,
    required double lon,
    String type = 'PLACE',
    String? stopId,
    String? iconName,
    bool Function(FavoritePlace kept)? isListed,
  }) async {
    final key = _coordinateKey(lat, lon);
    final place = FavoritePlace(
      id: 'fav_${DateTime.now().microsecondsSinceEpoch}',
      name: name,
      lat: lat,
      lon: lon,
      type: type,
      stopId: stopId,
      iconName: iconName ?? FavoritePlace.defaultIconName,
      addedAt: DateTime.now(),
    );
    final canFillIn = stopId?.isNotEmpty ?? false;

    FavoritePlace? kept;
    await _update((favorites) {
      final index = favorites.indexWhere(
        (f) => _coordinateKey(f.lat, f.lon) == key,
      );
      if (index == -1) {
        favorites.insert(0, place);
        kept = place;
        return true;
      }
      final existing = favorites[index];
      if (isListed != null && !isListed(existing) && canFillIn) {
        kept = favorites[index] = existing.copyWith(type: type, stopId: stopId);
        return true;
      }
      // Every copy, so a place kept twice before this was decided here
      // is let go of in one tap.
      favorites.removeWhere((f) => _coordinateKey(f.lat, f.lon) == key);
      kept = null;
      return true;
    });
    return kept;
  }

  static Future<bool> isFavorite(String id) async {
    try {
      final favorites = await _store.read();
      return favorites.any((f) => f.id == id);
    } catch (e) {
      return false;
    }
  }

  /// [change] applied in turn with every other change to the list, which is
  /// then shown.
  static Future<void> _update(
    bool Function(List<FavoritePlace> favorites) change,
  ) async {
    final written = await _store.update(change);
    if (written != null) {
      favoritesListenable.value = List.unmodifiable(written);
    }
  }
}
