import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/device_calendar.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/saved_trip.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/services/calendar_sync_service.dart';

import '../support/fake_calendar_bridge.dart';
import '../support/plan_fixtures.dart';

final _departure = DateTime(2030, 3, 4, 8, 15);

SavedTrip _trip({
  String tripId = 'trip-re7',
  DateTime? departure,
  String? label,
}) {
  final at = departure ?? _departure;
  return SavedTrip.fromItinerary(
    itinerary: Itinerary.fromJson(
      planItineraryJson(tripId: tripId, departure: at),
    ),
    timeSelection: TimeSelection(dateTime: at, isArriveBy: false),
    label: label,
  );
}

const _nextcloud = DeviceCalendar(
  id: 7,
  name: 'Trips',
  accountName: 'me@cloud.example.org',
  accountType: 'bitfire.at.davdroid',
  color: 0xFF8E5BD0,
);

void main() {
  late FakeCalendarBridge bridge;
  late bool permitted;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    bridge = FakeCalendarBridge(calendars: [_nextcloud]);
    permitted = true;
    CalendarSyncService.bridge = bridge;
    CalendarSyncService.hasAccess = () async => permitted;
  });

  /// The app's own calendar, once [CalendarSyncService.enable] made it.
  DeviceCalendar own() => bridge.calendars.values.singleWhere((c) => c.isLocal);

  group('off', () {
    test('is off until the rider switches it on', () async {
      expect(await CalendarSyncService.isWanted(), isFalse);
      await CalendarSyncService.onSaved(_trip());

      expect(bridge.calls, isEmpty);
    });

    test('does nothing without the permission', () async {
      await CalendarSyncService.enable(const []);
      bridge.calls.clear();
      permitted = false;

      await CalendarSyncService.onSaved(_trip());

      expect(bridge.calls, isEmpty);
      expect(await CalendarSyncService.currentCalendar(), isNull);
    });

    test('never throws into the save, even when Android refuses', () async {
      await CalendarSyncService.enable(const []);
      bridge.isRevoked = true;

      await expectLater(CalendarSyncService.onSaved(_trip()), completes);
      await expectLater(CalendarSyncService.onRemoved('x'), completes);
    });
  });

  group('switching on', () {
    test('adds the upcoming saved trips straight away', () async {
      final upcoming = _trip(tripId: 'a');
      final past = _trip(tripId: 'b', departure: DateTime(2029, 1, 1, 9));

      final calendar = await CalendarSyncService.enable([
        upcoming,
        past,
      ], now: DateTime(2030));

      expect(calendar.isOwn, isTrue);
      expect(calendar.name, 'Transportia+');
      expect(bridge.eventsIn(calendar.id), hasLength(1));
      expect(await CalendarSyncService.countIn(calendar.id), 1);
    });

    test('makes no calendar until there is a trip to put in it', () async {
      final calendar = await CalendarSyncService.enable(const []);

      expect(calendar.id, kOwnCalendarPlaceholderId);
      expect(bridge.calendars.values.where((c) => c.isLocal), isEmpty);
      expect(
        (await CalendarSyncService.currentCalendar())!.id,
        kOwnCalendarPlaceholderId,
      );
    });

    test('reuses its calendar rather than making a second', () async {
      await CalendarSyncService.enable([
        _trip(tripId: 'a'),
      ], now: DateTime(2030));
      await CalendarSyncService.disable(remove: false);
      await CalendarSyncService.enable([
        _trip(tripId: 'b'),
      ], now: DateTime(2030));

      expect(bridge.calendars.values.where((c) => c.isLocal), hasLength(1));
    });

    test('switching on again does not add a trip twice', () async {
      final trip = _trip();
      await CalendarSyncService.enable([trip], now: DateTime(2030));
      await CalendarSyncService.enable([trip], now: DateTime(2030));

      expect(bridge.events, hasLength(1));
    });
  });

  group('saving', () {
    test('adds one event with the trip, in the chosen calendar', () async {
      await CalendarSyncService.enable(const []);
      await CalendarSyncService.onSaved(_trip(label: 'Airport run'));

      final event = bridge.eventsIn(own().id).single;
      expect(event.title, 'Airport run');
      expect(event.start.toLocal(), _departure);
      expect(event.description, contains('RE7 towards Flughafen BER'));
      expect(event.location, 'S+U Berlin Hauptbahnhof');
    });

    test('saving the same trip again keeps the first event', () async {
      await CalendarSyncService.enable(const []);
      final trip = _trip();
      await CalendarSyncService.onSaved(trip);
      await CalendarSyncService.onSaved(trip);

      expect(bridge.events, hasLength(1));
    });

    test('makes its calendar for the first trip it adds', () async {
      await CalendarSyncService.enable(const []);
      await CalendarSyncService.onSaved(_trip());

      expect(bridge.eventsIn(own().id), hasLength(1));
    });

    test('remakes its calendar when the chosen one is gone', () async {
      await CalendarSyncService.enable(const []);
      await CalendarSyncService.choose(_nextcloud, savedTrips: const []);
      bridge.calendars.remove(_nextcloud.id);

      await CalendarSyncService.onSaved(_trip());

      expect(bridge.eventsIn(own().id), hasLength(1));
    });
  });

  group('the guard', () {
    late SavedTrip trip;
    late int eventId;

    setUp(() async {
      await CalendarSyncService.enable(const []);
      trip = _trip();
      await CalendarSyncService.onSaved(trip);
      eventId = bridge.events.keys.single;
    });

    test('a rename renames an untouched event, again and again', () async {
      await CalendarSyncService.onRenamed(trip.withLabel('Airport run'));
      expect(bridge.events[eventId]!.title, 'Airport run');

      await CalendarSyncService.onRenamed(trip.withLabel('Flight home'));
      expect(bridge.events[eventId]!.title, 'Flight home');
    });

    test('clearing the name goes back to the route', () async {
      await CalendarSyncService.onRenamed(trip.withLabel('Airport run'));
      await CalendarSyncService.onRenamed(trip.withLabel(null));

      expect(
        bridge.events[eventId]!.title,
        'S+U Berlin Hauptbahnhof → Flughafen BER',
      );
    });

    test('unsaving deletes an untouched event', () async {
      await CalendarSyncService.onRemoved(trip.id);
      expect(bridge.events, isEmpty);
    });

    test('an event the rider edited is never touched again', () async {
      bridge.events[eventId]!.description += '\nBring the passport';

      await CalendarSyncService.onRenamed(trip.withLabel('Airport run'));
      await CalendarSyncService.onRemoved(trip.id);

      expect(bridge.events[eventId]!.title, isNot('Airport run'));
      expect(bridge.events, contains(eventId));
      expect(bridge.calls.where((c) => c == 'deleteEvent'), isEmpty);
    });

    test('an event the rider moved in time is left alone', () async {
      final event = bridge.events[eventId]!;
      event.start = event.start.add(const Duration(minutes: 30));

      await CalendarSyncService.onRemoved(trip.id);

      expect(bridge.events, contains(eventId));
    });

    test('an event moved to another calendar is left alone', () async {
      bridge.events[eventId]!.calendarId = _nextcloud.id;

      await CalendarSyncService.onRemoved(trip.id);

      expect(bridge.events, contains(eventId));
    });

    test('an event already deleted is not deleted again', () async {
      bridge.events[eventId]!.isDeleted = true;

      await CalendarSyncService.onRemoved(trip.id);

      expect(bridge.calls.where((c) => c == 'deleteEvent'), isEmpty);
    });

    test('a failed check forgets the event, even if it is put back', () async {
      final event = bridge.events[eventId]!;
      final title = event.title;
      event.title = 'Mine now';
      await CalendarSyncService.onRenamed(trip.withLabel('Airport run'));

      event.title = title;
      await CalendarSyncService.onRemoved(trip.id);

      expect(bridge.events, contains(eventId));
    });

    test('pruned trips keep their events, and are forgotten', () async {
      await CalendarSyncService.forget([trip.id]);
      await CalendarSyncService.onRemoved(trip.id);

      expect(bridge.events, contains(eventId));
      expect(await CalendarSyncService.countIn(own().id), 0);
    });
  });

  group('switching off', () {
    test('keeping leaves every event and forgets them', () async {
      await CalendarSyncService.enable(const []);
      await CalendarSyncService.onSaved(_trip());

      await CalendarSyncService.disable(remove: false);

      expect(await CalendarSyncService.isWanted(), isFalse);
      expect(bridge.events, hasLength(1));
      expect(await CalendarSyncService.countIn(own().id), 0);
    });

    test('removing deletes the app\'s own calendar whole', () async {
      await CalendarSyncService.enable(const []);
      await CalendarSyncService.onSaved(_trip());
      final ownId = own().id;

      await CalendarSyncService.disable(remove: true);

      expect(bridge.calendars, isNot(contains(ownId)));
      expect(bridge.events, isEmpty);
    });

    test('removing from another calendar checks every event', () async {
      await CalendarSyncService.enable(const []);
      await CalendarSyncService.choose(_nextcloud, savedTrips: const []);
      await CalendarSyncService.onSaved(_trip(tripId: 'a'));
      await CalendarSyncService.onSaved(_trip(tripId: 'b'));
      final edited = bridge.events.keys.last;
      bridge.events[edited]!.title = 'Mine now';

      await CalendarSyncService.disable(remove: true);

      expect(bridge.events.keys, [edited]);
      expect(bridge.calendars, contains(_nextcloud.id));
    });

    test('removing leaves calendars it is not switching off alone', () async {
      await CalendarSyncService.enable(const []);
      await CalendarSyncService.onSaved(_trip(tripId: 'a'));
      final ownId = own().id;
      // Nothing to take along: the trip is not among those passed.
      await CalendarSyncService.choose(_nextcloud, savedTrips: const []);

      await CalendarSyncService.disable(remove: true);

      expect(bridge.eventsIn(ownId), hasLength(1));
    });
  });

  group('the calendar list', () {
    test('offers the app\'s own calendar first, before it exists', () async {
      final calendars = await CalendarSyncService.calendars();

      expect(calendars.first.id, kOwnCalendarPlaceholderId);
      expect(calendars.first.isOwn, isTrue);
      expect(calendars.map((c) => c.id), contains(_nextcloud.id));
    });

    test('marks the app\'s own calendar once it exists', () async {
      final made = await CalendarSyncService.enable([
        _trip(),
      ], now: DateTime(2030));
      final calendars = await CalendarSyncService.calendars();

      expect(calendars.where((c) => c.isOwn).single.id, made.id);
    });
  });

  group('choosing another calendar', () {
    final now = DateTime(2030);
    final upcoming = _trip(tripId: 'a');
    final past = _trip(tripId: 'b', departure: DateTime(2029, 1, 1, 9));

    test('right after switching on never makes a local calendar', () async {
      await CalendarSyncService.enable(const []);
      final chosen = await CalendarSyncService.choose(
        _nextcloud,
        savedTrips: [upcoming],
        now: now,
      );

      expect(chosen.id, _nextcloud.id);
      expect(bridge.calendars.values.where((c) => c.isLocal), isEmpty);
      expect(bridge.eventsIn(_nextcloud.id), hasLength(1));
    });

    test('takes upcoming trips along and drops the emptied calendar', () async {
      await CalendarSyncService.enable([upcoming], now: now);

      await CalendarSyncService.choose(
        _nextcloud,
        savedTrips: [upcoming],
        now: now,
      );

      expect(bridge.eventsIn(_nextcloud.id), hasLength(1));
      expect(bridge.calendars.values.where((c) => c.isLocal), isEmpty);
      expect((await CalendarSyncService.currentCalendar())!.id, _nextcloud.id);
    });

    test('moved events are looked after where they are now', () async {
      await CalendarSyncService.enable([upcoming], now: now);
      await CalendarSyncService.choose(
        _nextcloud,
        savedTrips: [upcoming],
        now: now,
      );

      await CalendarSyncService.onRemoved(upcoming.id);

      expect(bridge.events, isEmpty);
    });

    test('past trips stay, and so does the calendar holding them', () async {
      await CalendarSyncService.enable(const []);
      await CalendarSyncService.onSaved(past);
      await CalendarSyncService.onSaved(upcoming);
      final ownId = own().id;

      await CalendarSyncService.choose(
        _nextcloud,
        savedTrips: [upcoming, past],
        now: now,
      );

      expect(bridge.eventsIn(ownId), hasLength(1));
      expect(bridge.eventsIn(_nextcloud.id), hasLength(1));
    });

    test(
      'an event the rider edited stays, with its calendar, and only there',
      () async {
        await CalendarSyncService.enable([upcoming], now: now);
        final ownId = own().id;
        bridge.events.values.single.title = 'Mine now';

        await CalendarSyncService.choose(
          _nextcloud,
          savedTrips: [upcoming],
          now: now,
        );

        expect(bridge.eventsIn(ownId).single.title, 'Mine now');
        // The rider's now: no second event for the same trip.
        expect(bridge.eventsIn(_nextcloud.id), isEmpty);
        expect(await CalendarSyncService.countIn(ownId), 0);
      },
    );

    test('back to the app\'s own calendar makes it again', () async {
      await CalendarSyncService.enable(const []);
      await CalendarSyncService.choose(
        _nextcloud,
        savedTrips: [upcoming],
        now: now,
      );
      final calendars = await CalendarSyncService.calendars();

      final back = await CalendarSyncService.choose(
        calendars.first,
        savedTrips: [upcoming],
        now: now,
      );

      expect(back.isOwn, isTrue);
      expect(back.id, isNot(kOwnCalendarPlaceholderId));
      expect(bridge.eventsIn(back.id), hasLength(1));
      expect(bridge.eventsIn(_nextcloud.id), isEmpty);
    });
  });
}
