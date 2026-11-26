import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/services/favorites_service.dart';

FavoritePlace _place({
  String id = 'fav_1',
  String name = 'Hauptbahnhof',
  String? label,
  double lat = 52.525,
  double lon = 13.369,
}) => FavoritePlace(
  id: id,
  name: name,
  label: label,
  lat: lat,
  lon: lon,
  addedAt: DateTime.utc(2026, 1, 1),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FavoritesService.favoritesListenable.value = const [];
  });

  group('the alias sits on top of the name', () {
    test('an unrenamed place shows what was searched for', () {
      final place = _place();
      expect(place.displayName, 'Hauptbahnhof');
      expect(place.hasAlias, isFalse);
    });

    test('a renamed place shows the alias and keeps the name', () {
      final renamed = _place().copyWith(label: 'Home');
      expect(renamed.displayName, 'Home');
      expect(renamed.name, 'Hauptbahnhof');
      expect(renamed.hasAlias, isTrue);
    });

    test('clearing the alias restores the name rather than emptying it', () {
      final cleared = _place(label: 'Home').copyWith(clearLabel: true);
      expect(cleared.displayName, 'Hauptbahnhof');
      expect(cleared.hasAlias, isFalse);
    });

    test('a blank alias is not an alias', () {
      expect(_place(label: '   ').displayName, 'Hauptbahnhof');
    });

    test('the alias round-trips through storage', () {
      final restored = FavoritePlace.fromJson(_place(label: 'Work').toJson());
      expect(restored.label, 'Work');
      expect(restored.name, 'Hauptbahnhof');
    });
  });

  group('finding a place by where it is', () {
    test('matches the same spot whatever id it arrived with', () async {
      // A place hearted from a search and the same place reached from a deep
      // link carry different ids, and a rider would not call them two places.
      await FavoritesService.saveFavorite(_place());

      final found = FavoritesService.findAt(52.525, 13.369);
      expect(found?.id, 'fav_1');
    });

    test('does not match a different place', () async {
      await FavoritesService.saveFavorite(_place());
      expect(FavoritesService.findAt(48.137, 11.575), isNull);
    });
  });

  group('the heart toggles', () {
    test('keeps a place that is not kept yet', () async {
      final added = await FavoritesService.toggleAt(
        name: 'Alexanderplatz',
        lat: 52.521,
        lon: 13.413,
      );

      expect(added, isNotNull);
      expect(added!.name, 'Alexanderplatz');
      expect(FavoritesService.findAt(52.521, 13.413), isNotNull);
    });

    test('lets go of one that is', () async {
      await FavoritesService.toggleAt(
        name: 'Alexanderplatz',
        lat: 52.521,
        lon: 13.413,
      );
      final removed = await FavoritesService.toggleAt(
        name: 'Alexanderplatz',
        lat: 52.521,
        lon: 13.413,
      );

      expect(removed, isNull);
      expect(FavoritesService.findAt(52.521, 13.413), isNull);
    });

    test('a renamed place is still let go of by its position', () async {
      final added = await FavoritesService.toggleAt(
        name: 'Hauptbahnhof',
        lat: 52.525,
        lon: 13.369,
      );
      await FavoritesService.updateFavorite(added!.copyWith(label: 'Home'));

      final removed = await FavoritesService.toggleAt(
        name: 'Hauptbahnhof',
        lat: 52.525,
        lon: 13.369,
      );
      expect(removed, isNull);
      expect(FavoritesService.favoritesListenable.value, isEmpty);
    });
  });

  group('a favourite this build cannot read', () {
    // Literal, as a released build would have written it.
    const key = 'favorite_places';

    void seed(List<Object?> entries) {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({key: jsonEncode(entries)});
    }

    test('is skipped, not the whole list', () async {
      seed([
        _place(id: 'fav_1').toJson(),
        {'id': 'fav_broken', 'name': 'No position'},
        _place(id: 'fav_2', lat: 52.4, lon: 13.5).toJson(),
      ]);

      final favourites = await FavoritesService.getFavorites();

      expect(favourites.map((f) => f.id), ['fav_1', 'fav_2']);
    });

    test('does not cost the others their place on the next write', () async {
      seed([
        _place(id: 'fav_1').toJson(),
        {'id': 'fav_broken', 'lat': 'north'},
      ]);

      await FavoritesService.saveFavorite(
        _place(id: 'fav_2', lat: 52.4, lon: 13.5),
      );

      final stored = await SharedPreferencesAsync().getString(key);
      final ids = [
        for (final entry in jsonDecode(stored!) as List) (entry as Map)['id'],
      ];
      expect(ids, ['fav_2', 'fav_1']);
    });
  });

  group('changes made at once', () {
    test('both land', () async {
      await FavoritesService.saveFavorite(_place(id: 'fav_1'));

      await Future.wait([
        FavoritesService.saveFavorite(
          _place(id: 'fav_2', lat: 52.4, lon: 13.5),
        ),
        FavoritesService.updateFavorite(_place(id: 'fav_1', label: 'Home')),
      ]);

      final favourites = await FavoritesService.getFavorites();
      expect(favourites.map((f) => f.id), ['fav_2', 'fav_1']);
      expect(favourites.last.label, 'Home');
    });
  });
}
