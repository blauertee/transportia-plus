import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/utils/itinerary_calendar_event.dart';
import 'package:transportia/widgets/share_trip_sheet.dart';

import '../support/plan_fixtures.dart';

const _id = 'CmEh+w/UoXI9CSkA=';

Itinerary _trip({String? id}) => Itinerary.fromJson({
  ...planItineraryJson(departure: DateTime(2026, 10, 2, 16, 20)),
  'id': ?id,
});

class _Shared {
  final texts = <String>[];
  final subjects = <String?>[];
  final events = <CalendarEvent>[];
  var dismissed = 0;
  var noCalendarApp = 0;

  /// What the fake calendar answers: whether an app took the entry.
  var calendarTakes = true;

  Future<void> share(String text, {String? subject}) async {
    texts.add(text);
    subjects.add(subject);
  }

  Future<bool> addToCalendar(CalendarEvent event) async {
    events.add(event);
    return calendarTakes;
  }
}

Future<_Shared> _pump(
  WidgetTester tester,
  Itinerary itinerary, {
  bool withCalendar = true,
  bool calendarTakes = true,
}) async {
  final shared = _Shared()..calendarTakes = calendarTakes;
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: WidgetsApp(
        color: const Color(0xFF000000),
        localizationsDelegates: const [
          DefaultWidgetsLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
        ],
        builder: (_, _) => ShareTripSheet(
          itinerary: itinerary,
          onDismiss: () => shared.dismissed++,
          share: shared.share,
          addToCalendar: withCalendar ? shared.addToCalendar : null,
          onNoCalendarApp: () => shared.noCalendarApp++,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 300));
  return shared;
}

/// Taps, then lets the row's press highlight run out.
Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label), warnIfMissed: false);
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('the app link is an https link to the share page', (
    tester,
  ) async {
    final shared = await _pump(tester, _trip(id: _id));
    await _tap(tester, 'App link');

    // https, so a messenger shows it as a link at all.
    final link = Uri.parse(shared.texts.single);
    expect(link.scheme, 'https');
    expect(link.host, 'blauertee.github.io');
    expect(link.path, '/fw/');
    expect(link.queryParameters['itineraryId'], _id);
    expect(link.queryParameters['host'], 'api.transitous.org');
    expect(shared.dismissed, 1);
  });

  testWidgets('the app and web links are different links', (tester) async {
    final shared = await _pump(tester, _trip(id: _id));
    await _tap(tester, 'App link');
    await _tap(tester, 'Web link');

    expect(Uri.parse(shared.texts.first).host, 'blauertee.github.io');
    // Straight to the MOTIS web app, not through the share page.
    expect(Uri.parse(shared.texts.last).host, 'api.transitous.org');
  });

  testWidgets('the web link opens on the rider\'s server', (tester) async {
    final shared = await _pump(tester, _trip(id: _id));
    await _tap(tester, 'Web link');

    final link = Uri.parse(shared.texts.single);
    expect(link.origin, 'https://api.transitous.org');
    expect(link.queryParameters['itineraryId'], _id);
  });

  testWidgets('the text is the trip written out, and nothing else', (
    tester,
  ) async {
    final shared = await _pump(tester, _trip(id: _id));
    await _tap(tester, 'Text');

    final text = shared.texts.single;
    expect(text, startsWith('S+U Berlin Hauptbahnhof → Flughafen BER\n'));
    expect(text, isNot(contains('motis://')));
    expect(text, isNot(contains('https://')));
  });

  testWidgets('every share is titled with where the trip goes', (tester) async {
    final shared = await _pump(tester, _trip(id: _id));
    await _tap(tester, 'Text');
    expect(shared.subjects.single, 'S+U Berlin Hauptbahnhof → Flughafen BER');
  });

  testWidgets('a trip without an id offers only the text', (tester) async {
    final shared = await _pump(tester, _trip());
    expect(find.text('Not available for this trip'), findsNWidgets(2));

    await _tap(tester, 'App link');
    await _tap(tester, 'Web link');
    expect(shared.texts, isEmpty);

    await _tap(tester, 'Text');
    expect(shared.texts, hasLength(1));
  });

  testWidgets('add to calendar hands over the whole trip, linked', (
    tester,
  ) async {
    final itinerary = _trip(id: _id);
    final shared = await _pump(tester, itinerary);
    await _tap(tester, 'Add to calendar');

    final event = shared.events.single;
    expect(event.title, 'S+U Berlin Hauptbahnhof → Flughafen BER');
    expect(event.start, itinerary.startTime);
    expect(event.end, itinerary.endTime);
    // The share page, which opens the trip in the app with live times.
    expect(event.description, contains('https://blauertee.github.io/fw/'));
    expect(shared.texts, isEmpty);
    expect(shared.dismissed, 1);
    expect(shared.noCalendarApp, 0);
  });

  testWidgets('a trip without an id still goes into the calendar', (
    tester,
  ) async {
    final shared = await _pump(tester, _trip());
    await _tap(tester, 'Add to calendar');

    expect(shared.events.single.description, isNot(contains('https://')));
  });

  testWidgets('no calendar app to take it says so', (tester) async {
    final shared = await _pump(tester, _trip(id: _id), calendarTakes: false);
    await _tap(tester, 'Add to calendar');

    expect(shared.events, hasLength(1));
    expect(shared.noCalendarApp, 1);
  });

  testWidgets('without a calendar to add to, the row is left out', (
    tester,
  ) async {
    await _pump(tester, _trip(id: _id), withCalendar: false);
    expect(find.text('Add to calendar'), findsNothing);
    expect(find.text('Text'), findsOneWidget);
  });
}
