import 'package:flutter/services.dart';

import '../models/device_calendar.dart';

/// The error code `CalendarBridge.kt` answers with when Android refuses the
/// calendar permission.
const String _kNotPermittedCode = 'not_permitted';

/// Thrown when Android no longer lets the app at the calendars, typically
/// because the rider revoked the permission in system settings.
class CalendarNotPermittedException implements Exception {
  const CalendarNotPermittedException();
}

/// One event as the calendar holds it now.
class CalendarEventRecord {
  const CalendarEventRecord({
    required this.calendarId,
    required this.title,
    required this.description,
    required this.startMillis,
    required this.endMillis,
    required this.isDeleted,
  });

  final int calendarId;
  final String title;
  final String description;
  final int startMillis;
  final int endMillis;

  /// Marked for removal and waiting for its account to sync that.
  final bool isDeleted;
}

/// The device's calendars, as far as the calendar sync needs them.
///
/// Only events the app wrote are ever passed in by id; there is no search.
/// Behind an interface so tests can run the sync against a fake.
abstract class CalendarBridge {
  /// Calendars the app may add events to, visible ones only.
  Future<List<DeviceCalendar>> listCalendars();

  /// The calendar with [id], or null when it is gone.
  Future<DeviceCalendar?> readCalendar(int id);

  /// Makes a calendar for the app on this phone, that nothing syncs.
  Future<int> createOwnCalendar({required String name, required int color});

  /// Deletes the calendar [createOwnCalendar] made, with everything in it.
  /// Refuses, returning false, for any calendar it did not make.
  Future<bool> deleteOwnCalendar(int id);

  Future<int> insertEvent({
    required int calendarId,
    required String title,
    required String description,
    required String location,
    required DateTime start,
    required DateTime end,
  });

  /// The event with [id], or null when it is gone.
  Future<CalendarEventRecord?> readEvent(int id);

  Future<void> updateEventTitle(int id, String title);

  Future<void> deleteEvent(int id);
}

/// [CalendarBridge] over the `transportia/calendar` channel that
/// `CalendarBridge.kt` answers.
class MethodChannelCalendarBridge implements CalendarBridge {
  const MethodChannelCalendarBridge();

  static const MethodChannel _channel = MethodChannel('transportia/calendar');

  Future<T?> _call<T>(String method, [Map<String, Object?>? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (e) {
      if (e.code == _kNotPermittedCode) {
        throw const CalendarNotPermittedException();
      }
      rethrow;
    }
  }

  static DeviceCalendar _calendar(Map<Object?, Object?> map) => DeviceCalendar(
    id: map['id']! as int,
    name: map['name'] as String? ?? '',
    accountName: map['accountName'] as String? ?? '',
    accountType: map['accountType'] as String? ?? '',
    color: map['color'] as int? ?? 0,
  );

  @override
  Future<List<DeviceCalendar>> listCalendars() async {
    final list = await _call<List<Object?>>('listCalendars') ?? const [];
    return [
      for (final item in list)
        if (item is Map<Object?, Object?>) _calendar(item),
    ];
  }

  @override
  Future<DeviceCalendar?> readCalendar(int id) async {
    final map = await _call<Map<Object?, Object?>>('readCalendar', {'id': id});
    return map == null ? null : _calendar(map);
  }

  @override
  Future<int> createOwnCalendar({
    required String name,
    required int color,
  }) async {
    final id = await _call<int>('createOwnCalendar', {
      'name': name,
      'color': color,
    });
    return id!;
  }

  @override
  Future<bool> deleteOwnCalendar(int id) async =>
      await _call<bool>('deleteOwnCalendar', {'id': id}) ?? false;

  @override
  Future<int> insertEvent({
    required int calendarId,
    required String title,
    required String description,
    required String location,
    required DateTime start,
    required DateTime end,
  }) async {
    final id = await _call<int>('insertEvent', {
      'calendarId': calendarId,
      'title': title,
      'description': description,
      'location': location,
      'start': start.millisecondsSinceEpoch,
      'end': end.millisecondsSinceEpoch,
    });
    return id!;
  }

  @override
  Future<CalendarEventRecord?> readEvent(int id) async {
    final map = await _call<Map<Object?, Object?>>('readEvent', {'id': id});
    if (map == null) return null;
    return CalendarEventRecord(
      calendarId: map['calendarId']! as int,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      startMillis: map['start']! as int,
      endMillis: map['end'] as int? ?? 0,
      isDeleted: map['deleted'] as bool? ?? false,
    );
  }

  @override
  Future<void> updateEventTitle(int id, String title) =>
      _call<void>('updateEventTitle', {'id': id, 'title': title});

  @override
  Future<void> deleteEvent(int id) => _call<void>('deleteEvent', {'id': id});
}
