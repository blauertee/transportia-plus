import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/constants/prefs_keys.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/saved_trip.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/services/itinerary_refresh_service.dart';
import 'package:transportia/services/saved_trips_service.dart';

import 'support/plan_fixtures.dart';

SavedTrip _savedTrip({
  String tripId = 'trip-re7',
  required DateTime departure,
  String? label,
}) {
  return SavedTrip.fromItinerary(
    itinerary: Itinerary.fromJson(
      planItineraryJson(tripId: tripId, departure: departure),
    ),
    timeSelection: TimeSelection(dateTime: departure, isArriveBy: false),
    label: label,
  );
}

/// Notes what [SavedTripsService] tells the calendar.
class _Recorder implements SavedTripsListener {
  final List<String> heard = [];

  @override
  void saved(SavedTrip trip) => heard.add('saved ${trip.label}');

  @override
  void renamed(SavedTrip trip) => heard.add('renamed ${trip.label}');

  @override
  void removed(String id) => heard.add('removed');

  @override
  void pruned(List<String> ids) => heard.add('pruned ${ids.length}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Recorder recorder;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    SavedTripsService.savedTripsListenable.value = const [];
    recorder = _Recorder();
    SavedTripsService.listener = recorder;
  });

  final future = DateTime.now().add(const Duration(days: 2));

  group('SavedTrip', () {
    test('round-trips through JSON', () {
      final original = _savedTrip(departure: future, label: 'Airport run');

      final restored = SavedTrip.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.id, original.id);
      expect(restored.label, 'Airport run');
      expect(restored.fromName, 'S+U Berlin Hauptbahnhof');
      expect(restored.toName, 'Flughafen BER');
      expect(restored.fromStopId, 'stop-from');
      expect(restored.toStopId, 'stop-to');
      expect(restored.departureTime, original.departureTime);
      expect(restored.arrivalTime, original.arrivalTime);
      expect(restored.timeSelection.dateTime, original.timeSelection.dateTime);
      // The snapshot survives and still parses into the same connection.
      expect(restored.itinerary.legs, hasLength(3));
      expect(restored.itinerary.legs[1].tripId, 'trip-re7');
      expect(restored.itinerary.startTime, original.itinerary.startTime);
    });

    test('falls back to a generated label, and prefers a user one', () {
      final generated = _savedTrip(departure: future);
      expect(
        generated.displayLabel,
        contains('S+U Berlin Hauptbahnhof → Flughafen BER'),
      );

      final named = _savedTrip(departure: future, label: 'Airport run');
      expect(named.displayLabel, 'Airport run');

      final blank = _savedTrip(departure: future, label: '   ');
      expect(blank.displayLabel, blank.defaultLabel);
    });

    test('refuses to save an itinerary that did not come from the API', () {
      expect(
        () => SavedTrip.fromItinerary(
          itinerary: Itinerary(
            duration: 60,
            startTime: future,
            endTime: future.add(const Duration(minutes: 1)),
            transfers: 0,
            legs: const [],
          ),
          fromName: 'A',
          fromLat: 0,
          fromLon: 0,
          toName: 'B',
          toLat: 1,
          toLon: 1,
          timeSelection: TimeSelection.now(),
        ),
        throwsArgumentError,
      );
    });

    test('is never named after the planner placeholders', () {
      final trip = _savedTrip(departure: future);

      // The planner wraps this journey in walk legs called START and END.
      // Naming the trip after them is the bug this guards.
      expect(trip.fromName, isNot(equalsIgnoringCase('START')));
      expect(trip.toName, isNot(equalsIgnoringCase('END')));
      expect(trip.fromName, 'S+U Berlin Hauptbahnhof');
      expect(trip.toName, 'Flughafen BER');
    });

    test('prefers the places the user searched for', () {
      final trip = SavedTrip.fromItinerary(
        itinerary: Itinerary.fromJson(planItineraryJson(departure: future)),
        fromName: 'Home',
        toName: 'Berlin Brandenburg Airport',
      );

      expect(trip.fromName, 'Home');
      expect(trip.toName, 'Berlin Brandenburg Airport');
    });

    test('ignores a searched name that is itself a placeholder', () {
      final trip = SavedTrip.fromItinerary(
        itinerary: Itinerary.fromJson(planItineraryJson(departure: future)),
        fromName: 'START',
        toName: '   ',
      );

      expect(trip.fromName, 'S+U Berlin Hauptbahnhof');
      expect(trip.toName, 'Flughafen BER');
    });

    test('repairs placeholder names stored by an earlier version', () {
      final trip = _savedTrip(departure: future);
      final stored = trip.toJson();
      // Exactly what the buggy version wrote to shared_preferences.
      stored['fromName'] = 'START';
      stored['toName'] = 'END';

      final healed = SavedTrip.fromJson(
        jsonDecode(jsonEncode(stored)) as Map<String, dynamic>,
      );

      expect(healed.fromName, 'S+U Berlin Hauptbahnhof');
      expect(healed.toName, 'Flughafen BER');
    });

    test('marks a finished trip as past', () {
      final old = _savedTrip(
        departure: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(old.isPast, isTrue);
      expect(_savedTrip(departure: future).isPast, isFalse);
    });
  });

  group('SavedTripsService', () {
    test('saves and reads back a trip', () async {
      await SavedTripsService.saveTrip(_savedTrip(departure: future));

      final trips = await SavedTripsService.getSavedTrips();
      expect(trips, hasLength(1));
      expect(trips.single.toName, 'Flughafen BER');
      expect(await SavedTripsService.isSaved(trips.single.id), isTrue);
    });

    test('replaces rather than duplicates the same connection', () async {
      final trip = _savedTrip(departure: future);
      await SavedTripsService.saveTrip(trip);
      await SavedTripsService.saveTrip(_savedTrip(departure: future));

      expect(await SavedTripsService.getSavedTrips(), hasLength(1));
    });

    test('keeps a user label when the same connection is re-saved', () async {
      await SavedTripsService.saveTrip(_savedTrip(departure: future));
      final id = (await SavedTripsService.getSavedTrips()).single.id;
      await SavedTripsService.renameTrip(id, 'Airport run');

      await SavedTripsService.saveTrip(_savedTrip(departure: future));

      final trips = await SavedTripsService.getSavedTrips();
      expect(trips.single.label, 'Airport run');
    });

    test('treats different departures as different trips', () async {
      await SavedTripsService.saveTrip(_savedTrip(departure: future));
      await SavedTripsService.saveTrip(
        _savedTrip(departure: future.add(const Duration(hours: 1))),
      );

      expect(await SavedTripsService.getSavedTrips(), hasLength(2));
    });

    test('returns trips soonest first', () async {
      await SavedTripsService.saveTrip(
        _savedTrip(departure: future.add(const Duration(days: 3))),
      );
      await SavedTripsService.saveTrip(_savedTrip(departure: future));

      final trips = await SavedTripsService.getSavedTrips();
      expect(
        trips.first.departureTime.isBefore(trips.last.departureTime),
        isTrue,
      );
    });

    test('does not cap the list the way recent trips does', () async {
      for (var i = 0; i < 12; i++) {
        await SavedTripsService.saveTrip(
          _savedTrip(departure: future.add(Duration(hours: i))),
        );
      }

      expect(await SavedTripsService.getSavedTrips(), hasLength(12));
    });

    test('renames and clears a label', () async {
      await SavedTripsService.saveTrip(_savedTrip(departure: future));
      final id = (await SavedTripsService.getSavedTrips()).single.id;

      await SavedTripsService.renameTrip(id, 'Airport run');
      expect(
        (await SavedTripsService.getSavedTrips()).single.label,
        'Airport run',
      );

      await SavedTripsService.renameTrip(id, '  ');
      expect((await SavedTripsService.getSavedTrips()).single.label, isNull);
    });

    test('removes a trip', () async {
      await SavedTripsService.saveTrip(_savedTrip(departure: future));
      final id = (await SavedTripsService.getSavedTrips()).single.id;

      await SavedTripsService.removeTrip(id);

      expect(await SavedTripsService.getSavedTrips(), isEmpty);
      expect(await SavedTripsService.isSaved(id), isFalse);
    });

    test('prunes only long-finished trips', () async {
      await SavedTripsService.saveTrip(
        _savedTrip(
          departure: DateTime.now().subtract(const Duration(days: 40)),
        ),
      );
      await SavedTripsService.saveTrip(
        _savedTrip(departure: DateTime.now().subtract(const Duration(days: 2))),
      );
      await SavedTripsService.saveTrip(_savedTrip(departure: future));

      final removed = await SavedTripsService.pruneExpired();

      expect(removed, 1);
      expect(await SavedTripsService.getSavedTrips(), hasLength(2));
    });

    test('publishes changes on the listenable', () async {
      expect(SavedTripsService.savedTripsListenable.value, isEmpty);

      await SavedTripsService.saveTrip(_savedTrip(departure: future));
      expect(SavedTripsService.savedTripsListenable.value, hasLength(1));

      await SavedTripsService.removeTrip(
        SavedTripsService.savedTripsListenable.value.single.id,
      );
      expect(SavedTripsService.savedTripsListenable.value, isEmpty);
    });

    test(
      'skips unreadable entries instead of dropping the whole list',
      () async {
        final good = _savedTrip(departure: future);
        SharedPreferencesAsyncPlatform.instance =
            InMemorySharedPreferencesAsync.withData({
              PrefsKeys.savedTrips: jsonEncode([
                {'id': 'broken'},
                good.toJson(),
              ]),
            });

        final trips = await SavedTripsService.getSavedTrips();
        expect(trips, hasLength(1));
        expect(trips.single.id, good.id);
      },
    );
  });

  group('tells the calendar', () {
    test('about saves, renames and removals', () async {
      await SavedTripsService.saveTrip(_savedTrip(departure: future));
      final id = (await SavedTripsService.getSavedTrips()).single.id;
      await SavedTripsService.renameTrip(id, '  Airport run ');
      await SavedTripsService.removeTrip(id);

      expect(recorder.heard, ['saved null', 'renamed Airport run', 'removed']);
    });

    test('a re-save carries the name the rider gave it', () async {
      final trip = _savedTrip(departure: future);
      await SavedTripsService.saveTrip(trip);
      await SavedTripsService.renameTrip(trip.id, 'Airport run');
      await SavedTripsService.saveTrip(trip);

      expect(recorder.heard.last, 'saved Airport run');
    });

    test('not about a removal of a trip that was not saved', () async {
      await SavedTripsService.removeTrip('nothing');
      expect(recorder.heard, isEmpty);
    });

    test('which trips were pruned, and nothing when none were', () async {
      final now = DateTime(2030, 6, 1);
      await SavedTripsService.saveTrip(
        _savedTrip(departure: now.subtract(const Duration(days: 40))),
      );
      recorder.heard.clear();

      await SavedTripsService.pruneExpired(now: now);
      await SavedTripsService.pruneExpired(now: now);

      expect(recorder.heard, ['pruned 1']);
    });

    test('never about a live refresh', () async {
      final trip = _savedTrip(departure: future);
      await SavedTripsService.saveTrip(trip);
      recorder.heard.clear();

      await SavedTripsService.storeLiveItinerary(
        id: trip.id,
        refreshed: trip.itinerary,
        didRefresh: true,
        freshness: ItineraryFreshness.live,
        at: future,
      );

      expect(recorder.heard, isEmpty);
    });
  });
}
