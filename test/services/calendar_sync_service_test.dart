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
      await CalendarSyncService.enable();
      bridge.calls.clear();
      permitted = false;

      await CalendarSyncService.onSaved(_trip());

      expect(bridge.calls, isEmpty);
      expect(await CalendarSyncService.currentCalendar(), isNull);
    });

    test('never throws into the save, even when Android refuses', () async {
      await CalendarSyncService.enable();
      bridge.isRevoked = true;

      await expectLater(CalendarSyncService.onSaved(_trip()), completes);
      await expectLater(CalendarSyncService.onRemoved('x'), completes);
    });
  });

  group('switching on', () {
    test('makes the app its own calendar and sends trips there', () async {
      final calendar = await CalendarSyncService.enable();

      expect(calendar.isOwn, isTrue);
      expect(calendar.isLocal, isTrue);
      expect(calendar.name, 'Transportia+');
      expect((await CalendarSyncService.currentCalendar())!.id, calendar.id);
    });

    test('reuses its calendar rather than making a second', () async {
      await CalendarSyncService.enable();
      await CalendarSyncService.disable(remove: false);
      await CalendarSyncService.enable();

      expect(bridge.calendars.values.where((c) => c.isLocal), hasLength(1));
    });

    test('offers only trips still to come that have no event', () async {
      await CalendarSyncService.enable();
      final added = _trip(tripId: 'a');
      await CalendarSyncService.onSaved(added);
      final past = _trip(tripId: 'b', departure: DateTime(2029, 1, 1, 9));
      final upcoming = _trip(tripId: 'c');

      final offered = await CalendarSyncService.upcomingWithoutEvent([
        added,
        past,
        upcoming,
      ], now: DateTime(2030));

      expect(offered.map((t) => t.id), [upcoming.id]);
    });
  });

  group('saving', () {
    test('adds one event with the trip, in the chosen calendar', () async {
      await CalendarSyncService.enable();
      await CalendarSyncService.onSaved(_trip(label: 'Airport run'));

      final event = bridge.eventsIn(own().id).single;
      expect(event.title, 'Airport run');
      expect(event.start.toLocal(), _departure);
      expect(event.description, contains('RE7 towards Flughafen BER'));
      expect(event.location, 'S+U Berlin Hauptbahnhof');
    });

    test('saving the same trip again keeps the first event', () async {
      await CalendarSyncService.enable();
      final trip = _trip();
      await CalendarSyncService.onSaved(trip);
      await CalendarSyncService.onSaved(trip);

      expect(bridge.events, hasLength(1));
    });

    test('a new calendar takes new saves; old events stay put', () async {
      await CalendarSyncService.enable();
      await CalendarSyncService.onSaved(_trip(tripId: 'a'));
      await CalendarSyncService.choose(_nextcloud);
      await CalendarSyncService.onSaved(_trip(tripId: 'b'));

      expect(bridge.eventsIn(own().id), hasLength(1));
      expect(bridge.eventsIn(_nextcloud.id), hasLength(1));
    });

    test('remakes its calendar when the chosen one is gone', () async {
      await CalendarSyncService.enable();
      await CalendarSyncService.choose(_nextcloud);
      bridge.calendars.remove(_nextcloud.id);

      await CalendarSyncService.onSaved(_trip());

      expect(bridge.eventsIn(own().id), hasLength(1));
    });
  });

  group('the guard', () {
    late SavedTrip trip;
    late int eventId;

    setUp(() async {
      await CalendarSyncService.enable();
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
      await CalendarSyncService.enable();
      await CalendarSyncService.onSaved(_trip());

      await CalendarSyncService.disable(remove: false);

      expect(await CalendarSyncService.isWanted(), isFalse);
      expect(bridge.events, hasLength(1));
      expect(await CalendarSyncService.countIn(own().id), 0);
    });

    test('removing deletes the app\'s own calendar whole', () async {
      final calendar = await CalendarSyncService.enable();
      await CalendarSyncService.onSaved(_trip());

      await CalendarSyncService.disable(remove: true);

      expect(bridge.calendars, isNot(contains(calendar.id)));
      expect(bridge.events, isEmpty);
    });

    test('removing from another calendar checks every event', () async {
      await CalendarSyncService.enable();
      await CalendarSyncService.choose(_nextcloud);
      await CalendarSyncService.onSaved(_trip(tripId: 'a'));
      await CalendarSyncService.onSaved(_trip(tripId: 'b'));
      final edited = bridge.events.keys.last;
      bridge.events[edited]!.title = 'Mine now';

      await CalendarSyncService.disable(remove: true);

      expect(bridge.events.keys, [edited]);
      expect(bridge.calendars, contains(_nextcloud.id));
    });

    test('removing leaves calendars it is not switching off alone', () async {
      await CalendarSyncService.enable();
      await CalendarSyncService.onSaved(_trip(tripId: 'a'));
      final ownId = own().id;
      await CalendarSyncService.choose(_nextcloud);

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

    test('picking the placeholder makes the calendar', () async {
      final calendars = await CalendarSyncService.calendars();
      final picked = await CalendarSyncService.choose(calendars.first);

      expect(picked.id, isNot(kOwnCalendarPlaceholderId));
      expect(picked.isOwn, isTrue);
      expect(bridge.calendars, contains(picked.id));
    });

    test('marks the app\'s own calendar once it exists', () async {
      final made = await CalendarSyncService.enable();
      final calendars = await CalendarSyncService.calendars();

      expect(calendars.where((c) => c.isOwn).single.id, made.id);
    });

    test('leaving it and removing it deletes only that calendar', () async {
      await CalendarSyncService.enable();
      await CalendarSyncService.onSaved(_trip());
      await CalendarSyncService.choose(_nextcloud);

      await CalendarSyncService.removeOwnCalendar();

      expect(bridge.calendars.keys, [_nextcloud.id]);
      expect((await CalendarSyncService.currentCalendar())!.id, _nextcloud.id);
    });
  });
}
