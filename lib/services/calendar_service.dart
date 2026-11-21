import 'package:android_intent_plus/android_intent.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/itinerary_calendar_event.dart';

/// `Intent.ACTION_INSERT`.
const String _kInsertAction = 'android.intent.action.INSERT';

/// `CalendarContract.Events.CONTENT_URI`.
const String _kEventsUri = 'content://com.android.calendar/events';

/// `CalendarContract.Events.AVAILABILITY_BUSY`: the rider is travelling.
const int _kAvailabilityBusy = 0;

/// Puts trips into the rider's calendar through their calendar app.
///
/// The app opens with the entry filled in and the rider saves it there, so
/// Transportia+ needs no calendar permission and never writes to a calendar
/// itself; the rider also picks which calendar it goes into.
class CalendarService {
  /// Whether this platform has a way in. Android only for now: elsewhere the
  /// entry would need EventKit or an .ics file.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Opens the calendar app on [event]. False when no app takes it.
  static Future<bool> addEvent(CalendarEvent event) async {
    final intent = AndroidIntent(
      action: _kInsertAction,
      data: _kEventsUri,
      arguments: <String, dynamic>{
        'title': event.title,
        'description': event.description,
        'eventLocation': event.location,
        // Millis outgrow 32 bits, so these cross the channel as longs, which
        // is what CalendarContract reads.
        'beginTime': event.start.millisecondsSinceEpoch,
        'endTime': event.end.millisecondsSinceEpoch,
        'availability': _kAvailabilityBusy,
      },
    );
    try {
      // Checked first: launching with no app to take it would throw on the
      // Android side, past where Dart can catch it. Needs the <queries>
      // entry in AndroidManifest.xml to see calendar apps at all.
      if (await intent.canResolveActivity() != true) return false;
      await intent.launch();
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
