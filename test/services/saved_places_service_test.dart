import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/saved_place.dart';
import 'package:transportia/models/transitous/enums.dart';
import 'package:transportia/services/saved_places_service.dart';
import 'package:transportia/services/transitous_geocode_service.dart';

SavedPlace _place({
  required String name,
  String type = 'STOP',
  String? stopId,
  double lat = 52.5,
  double lon = 13.4,
  int? importance,
  List<TransitMode> modes = const [],
}) => SavedPlace(
  name: name,
  type: type,
  lat: lat,
  lon: lon,
  stopId: stopId,
  importance: importance ?? SavedPlacesService.initialImportance,
  modes: modes,
);

TransitousLocationSuggestion _suggestion({
  required String name,
  String? stopId,
  double lat = 52.5,
  double lon = 13.4,
  List<TransitMode> modes = const [],
}) => TransitousLocationSuggestion(
  id: 'geocoded-$name',
  stopId: stopId,
  name: name,
  lat: lat,
  lon: lon,
  type: 'STOP',
  modes: modes,
);

const _rail = [TransitMode.regionalRail, TransitMode.suburban];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('remembering a picked place', () {
    test('the feed id is stored alongside it', () async {
      final updated = SavedPlacesService.recordSelection(
        bucket: SavedPlacesBucket.timetable,
        places: const [],
        suggestion: _suggestion(name: 'Ostkreuz', stopId: 'de-DELFI_stop:42'),
      );

      expect(updated.single.stopId, 'de-DELFI_stop:42');
    });

    test('picking again backfills an id onto a place stored without one', () {
      // Places kept before ids were recorded cannot open a departure board.
      // Choosing one from search is the moment its id becomes known, so it is
      // the moment to keep it — rather than leaving the entry dead forever.
      final before = [_place(name: 'Ostkreuz')];
      expect(before.single.stopId, isNull);

      final updated = SavedPlacesService.applySelection(
        before,
        _place(name: 'Ostkreuz', stopId: 'de-DELFI_stop:42'),
      );

      expect(updated, hasLength(1), reason: 'backfill must not duplicate');
      expect(updated.single.stopId, 'de-DELFI_stop:42');
    });

    test('a pick without an id does not erase one already stored', () {
      final before = [_place(name: 'Ostkreuz', stopId: 'de-DELFI_stop:42')];

      final updated = SavedPlacesService.applySelection(
        before,
        _place(name: 'Ostkreuz'),
      );

      expect(updated.single.stopId, 'de-DELFI_stop:42');
    });

    test('the id survives a save and load', () async {
      await SavedPlacesService.savePlaces(
        bucket: SavedPlacesBucket.timetable,
        places: [_place(name: 'Ostkreuz', stopId: 'de-DELFI_stop:42')],
      );

      final loaded = await SavedPlacesService.loadPlaces(
        bucket: SavedPlacesBucket.timetable,
      );

      expect(loaded.single.stopId, 'de-DELFI_stop:42');
    });

    test('a place stored before ids existed still reads', () {
      // 1.0.3 wrote no stopId; absent must mean null, not a failed decode.
      final place = SavedPlace.fromJson(const {
        'name': 'Ostkreuz',
        'type': 'STOP',
        'lat': 52.5,
        'lon': 13.4,
        'importance': 15,
      });

      expect(place, isNotNull);
      expect(place!.stopId, isNull);
    });
  });

  group('what serves a remembered stop', () {
    test('is stored from the pick', () {
      final updated = SavedPlacesService.recordSelection(
        bucket: SavedPlacesBucket.timetable,
        places: const [],
        suggestion: _suggestion(name: 'Ostkreuz', modes: _rail),
      );

      expect(updated.single.modes, _rail);
    });

    test('survives a save and load', () async {
      await SavedPlacesService.savePlaces(
        bucket: SavedPlacesBucket.timetable,
        places: [_place(name: 'Ostkreuz', modes: _rail)],
      );

      final loaded = await SavedPlacesService.loadPlaces(
        bucket: SavedPlacesBucket.timetable,
      );

      expect(loaded.single.modes, _rail);
    });

    test('a place stored before modes were still reads, with none', () {
      final place = SavedPlace.fromJson(const {
        'name': 'Ostkreuz',
        'type': 'STOP',
        'lat': 52.5,
        'lon': 13.4,
        'importance': 15,
        'stopId': 'de-DELFI_stop:42',
      });

      expect(place!.modes, isEmpty);
      expect(place.stopId, 'de-DELFI_stop:42');
    });

    test('a mode this build does not know is dropped, not the place', () {
      final place = SavedPlace.fromJson(const {
        'name': 'Ostkreuz',
        'type': 'STOP',
        'lat': 52.5,
        'lon': 13.4,
        'modes': ['HOVERCRAFT', 'TRAM'],
      });

      expect(place!.modes, [TransitMode.tram]);
    });

    test('picking it from the recents keeps what was stored', () {
      // The recents list carries the stored modes back in; a geocoder answer
      // that happens to have none must not wipe them.
      final before = [_place(name: 'Ostkreuz', modes: _rail)];

      final updated = SavedPlacesService.applySelection(
        before,
        _place(name: 'Ostkreuz'),
      );

      expect(updated.single.modes, _rail);
    });

    test('a fresh answer replaces what was stored', () {
      final before = [_place(name: 'Ostkreuz', modes: _rail)];

      final updated = SavedPlacesService.applySelection(
        before,
        _place(name: 'Ostkreuz', modes: const [TransitMode.bus]),
      );

      expect(updated.single.modes, [TransitMode.bus]);
    });
  });

  group('a departure board filling in modes', () {
    Future<List<SavedPlace>> load() =>
        SavedPlacesService.loadPlaces(bucket: SavedPlacesBucket.timetable);

    test('fills in the stop it is for, and only that stop', () async {
      await SavedPlacesService.savePlaces(
        bucket: SavedPlacesBucket.timetable,
        places: [
          _place(name: 'Ostkreuz', stopId: 'stop:1', importance: 20),
          _place(name: 'Warschauer', stopId: 'stop:2', lat: 52.6),
        ],
      );

      await SavedPlacesService.recordModes(
        bucket: SavedPlacesBucket.timetable,
        stopId: 'stop:1',
        modes: _rail,
      );

      final loaded = await load();
      expect(loaded.firstWhere((p) => p.stopId == 'stop:1').modes, _rail);
      expect(loaded.firstWhere((p) => p.stopId == 'stop:2').modes, isEmpty);
    });

    test('leaves the order and importance alone', () async {
      await SavedPlacesService.savePlaces(
        bucket: SavedPlacesBucket.timetable,
        places: [
          _place(name: 'Ostkreuz', stopId: 'stop:1', importance: 20),
          _place(name: 'Warschauer', stopId: 'stop:2', lat: 52.6),
        ],
      );

      await SavedPlacesService.recordModes(
        bucket: SavedPlacesBucket.timetable,
        stopId: 'stop:2',
        modes: _rail,
      );

      final loaded = await load();
      expect([for (final p in loaded) p.name], ['Ostkreuz', 'Warschauer']);
      expect(loaded.first.importance, 20);
    });

    test('a board that names no modes changes nothing', () async {
      await SavedPlacesService.savePlaces(
        bucket: SavedPlacesBucket.timetable,
        places: [_place(name: 'Ostkreuz', stopId: 'stop:1', modes: _rail)],
      );

      await SavedPlacesService.recordModes(
        bucket: SavedPlacesBucket.timetable,
        stopId: 'stop:1',
        modes: const [],
      );

      expect((await load()).single.modes, _rail);
    });

    test('a stop that is not remembered is not added', () async {
      await SavedPlacesService.recordModes(
        bucket: SavedPlacesBucket.timetable,
        stopId: 'stop:9',
        modes: _rail,
      );

      expect(await load(), isEmpty);
    });
  });

  group('a remembered place this build cannot read', () {
    test('is skipped, not the whole list', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            // Literal, as a released build would have written it.
            'saved_places_search': jsonEncode([
              _place(name: 'Alexanderplatz').toJson(),
              {'name': 42, 'type': 'STOP', 'lat': 52.5, 'lon': 13.4},
              _place(name: 'Ostkreuz', lat: 52.503, lon: 13.469).toJson(),
            ]),
          });

      final places = await SavedPlacesService.loadPlaces(
        bucket: SavedPlacesBucket.search,
      );

      expect(places.map((p) => p.name), ['Alexanderplatz', 'Ostkreuz']);
    });

    test(
      'a value that is not JSON reads as empty rather than throwing',
      () async {
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData({
              'saved_places_timetable': '[{"name":',
            });

        final places = await SavedPlacesService.loadPlaces(
          bucket: SavedPlacesBucket.timetable,
        );

        expect(places, isEmpty);
      },
    );
  });
}
