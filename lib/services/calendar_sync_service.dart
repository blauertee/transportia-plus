import 'dart:async';
import 'dart:convert';

import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/prefs_keys.dart';
import '../environment.dart';
import '../models/device_calendar.dart';
import '../models/saved_trip.dart';
import '../providers/theme_provider.dart';
import '../utils/calendar_fingerprint.dart';
import '../utils/itinerary_calendar_event.dart';
import '../utils/trip_link.dart';
import 'calendar_bridge.dart';
import 'calendar_service.dart';
import 'saved_trips_service.dart';

/// Stands for the app's own calendar in the picker while it does not exist
/// yet; picking it makes it. Calendar ids from Android are never negative.
const int kOwnCalendarPlaceholderId = -1;

/// The event the app wrote for one saved trip, and how it looked then.
class _Written {
  const _Written({
    required this.eventId,
    required this.calendarId,
    required this.fingerprint,
  });

  factory _Written.fromJson(Map<String, dynamic> json) => _Written(
    eventId: json['event'] as int,
    calendarId: json['calendar'] as int,
    fingerprint: json['fingerprint'] as String,
  );

  final int eventId;
  final int calendarId;
  final String fingerprint;

  Map<String, Object> toJson() => {
    'event': eventId,
    'calendar': calendarId,
    'fingerprint': fingerprint,
  };
}

/// Puts the trips the rider saves into a calendar, when they asked for it.
///
/// It only ever touches events it wrote itself, and only while they are
/// exactly as it wrote them: before renaming or deleting one it reads that
/// event back by id and compares it with the fingerprint taken when writing
/// it. An event the rider edited, moved or deleted is left alone for good.
/// It never searches a calendar.
///
/// Events hold the timetable, never live data, and live refreshes of a saved
/// trip never reach the calendar.
///
/// Every hook is a no-op while the setting is off or Android withholds the
/// permission, and none of them throws: a calendar that cannot be written
/// must never fail a save.
class CalendarSyncService {
  const CalendarSyncService._();

  /// The device's calendars. Replaced in tests.
  static CalendarBridge bridge = const MethodChannelCalendarBridge();

  /// Whether Android lets the app at the calendars right now. Replaced in
  /// tests.
  static Future<bool> Function() hasAccess = _systemHasAccess;

  static Future<bool> _systemHasAccess() async =>
      (await Permission.calendarFullAccess.status).isGranted;

  /// Tells this service about the rider's saved trips.
  static const SavedTripsListener listener = _CalendarSyncListener();

  /// Android only for now, like the one-off "Add to calendar".
  static bool get isSupported => CalendarService.isSupported;

  static const String ownCalendarName = Environment.appName;
  static final int _ownCalendarColor = ThemeProvider.defaultAccentColor
      .toARGB32();

  /// One calendar change at a time: a save and a rename arriving together
  /// must not both read the same list of written events and drop each
  /// other's change. Null while nothing runs, so a finished change is never
  /// waited on.
  static Future<void>? _running;

  static Future<T> _serial<T>(Future<T> Function() task) async {
    while (_running != null) {
      await _running;
    }
    final done = Completer<void>();
    _running = done.future;
    try {
      return await task();
    } finally {
      _running = null;
      done.complete();
    }
  }

  static SharedPreferencesAsync get _prefs => SharedPreferencesAsync();

  /// Whether the rider switched the setting on. It does nothing without the
  /// permission too.
  static Future<bool> isWanted() async =>
      await _prefs.getBool(PrefsKeys.calendarSyncWanted) ?? false;

  /// Where saved trips go now, or null while the setting is off or Android
  /// withholds the permission. The app's own calendar until another is
  /// chosen, or when the chosen one is gone; while it does not exist yet,
  /// [kOwnCalendarPlaceholderId] stands for it.
  static Future<DeviceCalendar?> currentCalendar() async {
    try {
      if (!await isWanted() || !await hasAccess()) return null;
      return await _serial(_current);
    } catch (_) {
      return null;
    }
  }

  /// Switches the setting on, once the permission is granted, and adds the
  /// upcoming trips among [savedTrips] straight away: whoever turns this on
  /// wants to see their trips. Says where they went.
  static Future<DeviceCalendar> enable(
    List<SavedTrip> savedTrips, {
    DateTime? now,
  }) async {
    await _prefs.setBool(PrefsKeys.calendarSyncWanted, true);
    return _serial(() async {
      final at = now ?? DateTime.now();
      final written = await _readWritten();
      try {
        for (final trip in savedTrips) {
          if (!trip.arrivalTime.isAfter(at)) continue;
          if (written.containsKey(trip.id)) continue;
          written[trip.id] = await _write(trip);
        }
      } finally {
        await _writeWritten(written);
      }
      return _current();
    });
  }

  /// Switches the setting off. With [remove], the events added to the
  /// current calendar go too: the app's own calendar is deleted whole, since
  /// it is the app's; in any other, each event is checked before it is
  /// removed. Events anywhere else are left where they are. Either way the
  /// app stops looking after them.
  static Future<void> disable({required bool remove}) => _serial(() async {
    final prefs = _prefs;
    try {
      if (remove) {
        final current = await _current();
        if (current.isOwn) {
          await _deleteOwnCalendar();
        } else {
          final written = await _readWritten();
          for (final entry in written.values) {
            if (entry.calendarId != current.id) continue;
            if (!await _isUntouched(entry)) continue;
            await bridge.deleteEvent(entry.eventId);
          }
        }
      }
    } catch (_) {
      // Whatever could not be removed stays; the setting still goes off.
    } finally {
      await prefs.remove(PrefsKeys.calendarSyncEvents);
      await prefs.setBool(PrefsKeys.calendarSyncWanted, false);
    }
  });

  /// The calendars saved trips can go to, the app's own first. While it
  /// does not exist it is offered as [kOwnCalendarPlaceholderId].
  static Future<List<DeviceCalendar>> calendars() async {
    final ownId = await _prefs.getInt(PrefsKeys.calendarSyncOwnCalendar);
    final listed = await bridge.listCalendars();
    final calendars = [for (final c in listed) c.id == ownId ? c.asOwn : c];
    if (calendars.any((c) => c.isOwn)) return calendars;
    return [_ownPlaceholder, ...calendars];
  }

  static DeviceCalendar get _ownPlaceholder => DeviceCalendar(
    id: kOwnCalendarPlaceholderId,
    name: ownCalendarName,
    accountName: ownCalendarName,
    accountType: kLocalCalendarAccountType,
    color: _ownCalendarColor,
    isOwn: true,
  );

  /// Sends saved trips to [calendar] from now on, and takes the upcoming
  /// ones among [savedTrips] along: each untouched event moves over, and a
  /// trip without one gets one. Past trips stay where they are, and so does
  /// an event the rider edited, which the app then forgets.
  ///
  /// The app's own calendar, left holding nothing the app looks after and
  /// nothing the rider changed, is deleted. Returns where trips go now.
  static Future<DeviceCalendar> choose(
    DeviceCalendar calendar, {
    required List<SavedTrip> savedTrips,
    DateTime? now,
  }) => _serial(() async {
    final prefs = _prefs;
    final ownId = await prefs.getInt(PrefsKeys.calendarSyncOwnCalendar);
    if (calendar.isOwn) {
      await prefs.remove(PrefsKeys.calendarSyncCalendar);
    } else {
      await prefs.setInt(PrefsKeys.calendarSyncCalendar, calendar.id);
    }
    final targetId = calendar.isOwn ? ownId : calendar.id;

    final at = now ?? DateTime.now();
    final written = await _readWritten();
    var riderKeptOne = false;
    try {
      for (final trip in savedTrips) {
        if (!trip.arrivalTime.isAfter(at)) continue;
        final entry = written[trip.id];
        if (entry != null) {
          if (entry.calendarId == targetId) continue;
          written.remove(trip.id);
          if (!await _isUntouched(entry)) {
            if (entry.calendarId == ownId) riderKeptOne = true;
            continue;
          }
          await bridge.deleteEvent(entry.eventId);
        }
        written[trip.id] = await _write(trip);
      }
    } finally {
      await _writeWritten(written);
    }

    final ownIsEmpty = !written.values.any((w) => w.calendarId == ownId);
    if (!calendar.isOwn && ownId != null && ownIsEmpty && !riderKeptOne) {
      await _deleteOwnCalendar();
    }
    return _current();
  });

  /// How many events the app looks after in [calendarId].
  static Future<int> countIn(int calendarId) async {
    final written = await _readWritten();
    return written.values.where((w) => w.calendarId == calendarId).length;
  }

  /// Adds an event for a trip the rider just saved. A trip that already has
  /// one keeps it as first written: saving again does not re-plan it.
  static Future<void> onSaved(SavedTrip trip) => _quietly(() async {
    final written = await _readWritten();
    if (written.containsKey(trip.id)) return;
    written[trip.id] = await _write(trip);
    await _writeWritten(written);
  });

  /// Gives a renamed trip's event the new name, if the event is untouched.
  static Future<void> onRenamed(SavedTrip trip) => _quietly(() async {
    final written = await _readWritten();
    final entry = written[trip.id];
    if (entry == null) return;

    final event = await _untouchedEvent(entry);
    if (event == null) {
      written.remove(trip.id);
      await _writeWritten(written);
      return;
    }

    final fallback = savedTripAsCalendarEvent(trip).title;
    final title = savedTripEventTitle(trip, fallback: fallback);
    if (title == event.title) return;
    await bridge.updateEventTitle(entry.eventId, title);
    written[trip.id] = _Written(
      eventId: entry.eventId,
      calendarId: entry.calendarId,
      fingerprint: calendarEventFingerprint(
        title: title,
        description: event.description,
        startMillis: event.startMillis,
        endMillis: event.endMillis,
      ),
    );
    await _writeWritten(written);
  });

  /// Deletes an unsaved trip's event, if the event is untouched.
  static Future<void> onRemoved(String tripId) => _quietly(() async {
    final written = await _readWritten();
    final entry = written.remove(tripId);
    if (entry == null) return;
    if (await _isUntouched(entry)) {
      await bridge.deleteEvent(entry.eventId);
    }
    await _writeWritten(written);
  });

  /// Stops looking after the events of trips the app cleared from the list
  /// once they were long past. The events stay: they are history now.
  static Future<void> forget(Iterable<String> tripIds) => _quietly(() async {
    final written = await _readWritten();
    final before = written.length;
    written.removeWhere((id, _) => tripIds.contains(id));
    if (written.length != before) await _writeWritten(written);
  });

  /// Runs [task] in turn, only while the setting is on and permitted, and
  /// swallows anything it throws.
  static Future<void> _quietly(Future<void> Function() task) =>
      _serial(() async {
        try {
          if (!await isWanted() || !await hasAccess()) return;
          await task();
        } catch (_) {
          // A calendar that cannot be written must never fail a save; the trip
          // just goes without an event.
        }
      });

  /// Where trips go: the chosen calendar while it exists, else the app's
  /// own, or [kOwnCalendarPlaceholderId] while that does not exist yet.
  static Future<DeviceCalendar> _current() async {
    final prefs = _prefs;
    final chosenId = await prefs.getInt(PrefsKeys.calendarSyncCalendar);
    final ownId = await prefs.getInt(PrefsKeys.calendarSyncOwnCalendar);
    if (chosenId != null && chosenId != ownId) {
      final chosen = await bridge.readCalendar(chosenId);
      if (chosen != null) return chosen;
    }
    if (ownId != null) {
      final own = await bridge.readCalendar(ownId);
      if (own != null) return own.asOwn;
    }
    return _ownPlaceholder;
  }

  /// Writes [trip]'s event where trips go, making the app's own calendar
  /// first if that is where and it does not exist yet: it is only made once
  /// there is a trip to put in it.
  static Future<_Written> _write(SavedTrip trip) async {
    var calendar = await _current();
    if (calendar.id == kOwnCalendarPlaceholderId) {
      calendar = await _ensureOwnCalendar();
    }
    final event = savedTripAsCalendarEvent(trip, link: _linkFor(trip));
    final eventId = await bridge.insertEvent(
      calendarId: calendar.id,
      title: event.title,
      description: event.description,
      location: event.location,
      start: event.start,
      end: event.end,
    );
    return _Written(
      eventId: eventId,
      calendarId: calendar.id,
      fingerprint: calendarEventFingerprint(
        title: event.title,
        description: event.description,
        startMillis: event.start.millisecondsSinceEpoch,
        endMillis: event.end.millisecondsSinceEpoch,
      ),
    );
  }

  static Future<DeviceCalendar> _ensureOwnCalendar() async {
    final prefs = _prefs;
    final ownId = await prefs.getInt(PrefsKeys.calendarSyncOwnCalendar);
    if (ownId != null) {
      final own = await bridge.readCalendar(ownId);
      if (own != null) return own.asOwn;
    }
    final id = await bridge.createOwnCalendar(
      name: ownCalendarName,
      color: _ownCalendarColor,
    );
    await prefs.setInt(PrefsKeys.calendarSyncOwnCalendar, id);
    final made = await bridge.readCalendar(id);
    if (made != null) return made.asOwn;
    return DeviceCalendar(
      id: id,
      name: ownCalendarName,
      accountName: ownCalendarName,
      accountType: kLocalCalendarAccountType,
      color: _ownCalendarColor,
      isOwn: true,
    );
  }

  static Future<void> _deleteOwnCalendar() async {
    final prefs = _prefs;
    final ownId = await prefs.getInt(PrefsKeys.calendarSyncOwnCalendar);
    if (ownId == null) return;
    await bridge.deleteOwnCalendar(ownId);
    await prefs.remove(PrefsKeys.calendarSyncOwnCalendar);
    if (await prefs.getInt(PrefsKeys.calendarSyncCalendar) == ownId) {
      await prefs.remove(PrefsKeys.calendarSyncCalendar);
    }
    final written = await _readWritten();
    written.removeWhere((_, w) => w.calendarId == ownId);
    await _writeWritten(written);
  }

  static Uri? _linkFor(SavedTrip trip) {
    final id = trip.itinerary.id;
    if (id == null || id.isEmpty) return null;
    return TripLink(
      itineraryId: id,
      host: Environment.transitousHost,
    ).shareLink;
  }

  static Future<bool> _isUntouched(_Written entry) async =>
      await _untouchedEvent(entry) != null;

  /// The event [entry] points at, if it is still exactly as the app wrote
  /// it: there, not deleted, in the same calendar, and matching the
  /// fingerprint.
  static Future<CalendarEventRecord?> _untouchedEvent(_Written entry) async {
    final event = await bridge.readEvent(entry.eventId);
    if (event == null || event.isDeleted) return null;
    if (event.calendarId != entry.calendarId) return null;
    final fingerprint = calendarEventFingerprint(
      title: event.title,
      description: event.description,
      startMillis: event.startMillis,
      endMillis: event.endMillis,
    );
    return fingerprint == entry.fingerprint ? event : null;
  }

  static Future<Map<String, _Written>> _readWritten() async {
    final encoded = await _prefs.getString(PrefsKeys.calendarSyncEvents);
    if (encoded == null || encoded.isEmpty) return {};
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic>) return {};
      final written = <String, _Written>{};
      for (final MapEntry(:key, :value) in decoded.entries) {
        if (value is! Map<String, dynamic>) continue;
        try {
          written[key] = _Written.fromJson(value);
        } catch (_) {
          continue;
        }
      }
      return written;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeWritten(Map<String, _Written> written) =>
      _prefs.setString(
        PrefsKeys.calendarSyncEvents,
        jsonEncode({
          for (final MapEntry(:key, :value) in written.entries)
            key: value.toJson(),
        }),
      );
}

class _CalendarSyncListener implements SavedTripsListener {
  const _CalendarSyncListener();

  @override
  void saved(SavedTrip trip) => unawaited(CalendarSyncService.onSaved(trip));

  @override
  void renamed(SavedTrip trip) =>
      unawaited(CalendarSyncService.onRenamed(trip));

  @override
  void removed(String id) => unawaited(CalendarSyncService.onRemoved(id));

  @override
  void pruned(List<String> ids) => unawaited(CalendarSyncService.forget(ids));
}
