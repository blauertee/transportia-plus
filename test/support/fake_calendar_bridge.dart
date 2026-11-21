import 'package:transportia/models/device_calendar.dart';
import 'package:transportia/services/calendar_bridge.dart';

/// One event in a [FakeCalendarBridge], editable the way a rider would edit
/// it in their calendar app.
class FakeEvent {
  FakeEvent({
    required this.calendarId,
    required this.title,
    required this.description,
    required this.location,
    required this.start,
    required this.end,
  });

  int calendarId;
  String title;
  String description;
  String location;
  DateTime start;
  DateTime end;
  bool isDeleted = false;
}

/// The device's calendars, in memory, recording what the app asked of them.
class FakeCalendarBridge implements CalendarBridge {
  FakeCalendarBridge({List<DeviceCalendar> calendars = const []})
    : calendars = {for (final c in calendars) c.id: c};

  final Map<int, DeviceCalendar> calendars;
  final Map<int, FakeEvent> events = {};
  final List<String> calls = [];

  /// Makes every call throw, as Android does once access is revoked.
  bool isRevoked = false;

  int _nextCalendarId = 100;
  int _nextEventId = 1;

  void _check(String call) {
    calls.add(call);
    if (isRevoked) throw const CalendarNotPermittedException();
  }

  /// The events in calendar [id].
  Iterable<FakeEvent> eventsIn(int id) =>
      events.values.where((e) => e.calendarId == id && !e.isDeleted);

  @override
  Future<List<DeviceCalendar>> listCalendars() async {
    _check('listCalendars');
    return calendars.values.toList();
  }

  @override
  Future<DeviceCalendar?> readCalendar(int id) async {
    _check('readCalendar');
    return calendars[id];
  }

  @override
  Future<int> createOwnCalendar({
    required String name,
    required int color,
  }) async {
    _check('createOwnCalendar');
    final id = _nextCalendarId++;
    calendars[id] = DeviceCalendar(
      id: id,
      name: name,
      accountName: name,
      accountType: kLocalCalendarAccountType,
      color: color,
    );
    return id;
  }

  @override
  Future<bool> deleteOwnCalendar(int id) async {
    _check('deleteOwnCalendar');
    final calendar = calendars[id];
    if (calendar == null || !calendar.isLocal) return false;
    calendars.remove(id);
    events.removeWhere((_, e) => e.calendarId == id);
    return true;
  }

  @override
  Future<int> insertEvent({
    required int calendarId,
    required String title,
    required String description,
    required String location,
    required DateTime start,
    required DateTime end,
  }) async {
    _check('insertEvent');
    final id = _nextEventId++;
    events[id] = FakeEvent(
      calendarId: calendarId,
      title: title,
      description: description,
      location: location,
      start: start,
      end: end,
    );
    return id;
  }

  @override
  Future<CalendarEventRecord?> readEvent(int id) async {
    _check('readEvent');
    final event = events[id];
    if (event == null) return null;
    return CalendarEventRecord(
      calendarId: event.calendarId,
      title: event.title,
      description: event.description,
      startMillis: event.start.millisecondsSinceEpoch,
      endMillis: event.end.millisecondsSinceEpoch,
      isDeleted: event.isDeleted,
    );
  }

  @override
  Future<void> updateEventTitle(int id, String title) async {
    _check('updateEventTitle');
    events[id]?.title = title;
  }

  @override
  Future<void> deleteEvent(int id) async {
    _check('deleteEvent');
    events.remove(id);
  }
}
