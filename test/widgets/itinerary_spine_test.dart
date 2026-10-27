import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/utils/leg_notices.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/itinerary_detail_screen.dart';
import 'package:transportia/theme/journey_metrics.dart';
import 'package:transportia/utils/changeover.dart';
import 'package:transportia/utils/journey_colors.dart';
import 'package:transportia/utils/journey_progress.dart';
import 'package:transportia/widgets/custom_card.dart';
import 'package:transportia/widgets/journey/spine_node.dart';
import 'package:transportia/widgets/journey/spine_rail.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:transportia/utils/time_utils.dart';

/// The guard on the redesign: moving the itinerary onto one spine was not
/// allowed to drop anything the leg cards used to print. Each test below names
/// a thing the old cards showed and checks it is still reachable.
final DateTime _t0 = DateTime(2026, 6, 1, 14, 30);

String _at(Duration offset) => _t0.add(offset).toUtc().toIso8601String();

Leg _ride() => Leg.fromJson({
  'mode': 'HIGHSPEED_RAIL',
  'startTime': _at(const Duration(minutes: 10)),
  'endTime': _at(const Duration(minutes: 60)),
  'scheduledStartTime': _at(const Duration(minutes: 8)),
  'scheduledEndTime': _at(const Duration(minutes: 58)),
  'duration': 3000,
  'headsign': 'Flughafen BER',
  'displayName': 'ICE 599',
  'routeLongName': 'Intercity-Express 599',
  'agencyName': 'Deutsche Bahn',
  'routeColor': '1A3D8F',
  'realTime': true,
  'interlineWithPreviousLeg': true,
  'distance': 41000.0,
  'tripId': 'trip-ice',
  'alerts': [
    {'headerText': 'Lift out of order', 'descriptionText': 'Use the stairs.'},
  ],
  'from': {
    'name': 'Berlin Hauptbahnhof',
    'lat': 52.525,
    'lon': 13.369,
    'stopId': 'stop-hbf',
    'track': '7',
  },
  'to': {
    'name': 'Flughafen BER',
    'lat': 52.366,
    'lon': 13.503,
    'stopId': 'stop-ber',
    'track': '3',
  },
  'intermediateStops': [
    {
      'name': 'Ostkreuz',
      'lat': 52.503,
      'lon': 13.469,
      'stopId': 'stop-ost',
      'track': '9',
      'scheduledArrival': _at(const Duration(minutes: 25)),
      'arrival': _at(const Duration(minutes: 27)),
      'scheduledDeparture': _at(const Duration(minutes: 28)),
      'departure': _at(const Duration(minutes: 30)),
    },
  ],
});

/// The short walk between two services the planner returns for a change.
///
/// [arrivesAtTrack] is the platform the walk ends on. It defaults to the one
/// the ride leaves from, which is the ordinary case — you walk to your train.
Leg _change({String arrivesAtTrack = '7'}) => Leg.fromJson({
  'mode': 'WALK',
  'startTime': _at(const Duration(minutes: 3)),
  'endTime': _at(const Duration(minutes: 8)),
  'duration': 300,
  'distance': 260.0,
  'from': {
    'name': 'Naturkundemuseum',
    'lat': 52.53,
    'lon': 13.38,
    'stopId': 'stop-nat',
    'track': '2',
  },
  'to': {
    'name': 'Berlin Hauptbahnhof',
    'lat': 52.525,
    'lon': 13.369,
    'stopId': 'stop-hbf',
    'track': arrivesAtTrack,
  },
});

/// A service leaving this node at [departs] past the hour.
Leg _onward(Duration departs, {bool realTime = true}) => Leg.fromJson({
  'mode': 'SUBURBAN',
  'startTime': _at(departs),
  'endTime': _at(departs + const Duration(minutes: 20)),
  'duration': 1200,
  'displayName': 'S46',
  'realTime': realTime,
  'from': {
    'name': 'Berlin Hauptbahnhof',
    'lat': 52.525,
    'lon': 13.369,
    'stopId': 'stop-hbf',
  },
  'to': {'name': 'S Westend', 'lat': 52.51, 'lon': 13.28, 'stopId': 'stop-wes'},
});

/// A ride arriving at this node at [arrives] past the hour.
Leg _arriving(Duration arrives, {bool realTime = true}) => Leg.fromJson({
  'mode': 'HIGHSPEED_RAIL',
  'startTime': _at(Duration.zero),
  'endTime': _at(arrives),
  'duration': arrives.inSeconds,
  'realTime': realTime,
  'from': {'name': 'München Hbf', 'lat': 48.1, 'lon': 11.5},
  'to': {
    'name': 'Naturkundemuseum',
    'lat': 52.53,
    'lon': 13.38,
    'stopId': 'stop-nat',
  },
});

/// The change from the report: the train is ten minutes down and gets in on
/// the very minute the walk was scheduled to start.
Leg _lateChange() => Leg.fromJson({
  'mode': 'WALK',
  'startTime': _at(const Duration(minutes: 24)),
  'scheduledStartTime': _at(const Duration(minutes: 24)),
  'endTime': _at(const Duration(minutes: 26)),
  'duration': 120,
  'distance': 50.0,
  'from': {
    'name': 'S Südkreuz',
    'lat': 52.475,
    'lon': 13.365,
    'stopId': 'stop-sxf',
    'track': '6',
    'arrival': _at(const Duration(minutes: 24)),
    'scheduledArrival': _at(const Duration(minutes: 14)),
    'departure': _at(const Duration(minutes: 24)),
    'scheduledDeparture': _at(const Duration(minutes: 24)),
  },
  'to': {
    'name': 'S Südkreuz',
    'lat': 52.475,
    'lon': 13.365,
    'stopId': 'stop-sxf',
    'track': '11',
  },
});

/// The change in the report: five minutes of walking, three minutes to do it.
Changeover _missed() => Changeover(
  transfer: _change(),
  arriving: _arriving(const Duration(minutes: 5)),
  departing: _onward(const Duration(minutes: 8)),
);

Changeover _made() => Changeover(
  transfer: _change(),
  arriving: _arriving(const Duration(minutes: 1)),
  departing: _onward(const Duration(minutes: 30)),
);

Itinerary _journey() => Itinerary(
  duration: 3600,
  startTime: _t0,
  endTime: _t0.add(const Duration(minutes: 60)),
  transfers: 1,
  legs: [_ride()],
);

/// The 1px line the header ends on.
Rect _ruleRect(WidgetTester tester) {
  final rects = <Rect>[];
  for (final element
      in find
          .descendant(
            of: find.byType(JourneyOverviewWidget),
            matching: find.byType(Container),
          )
          .evaluate()) {
    final box = element.renderObject as RenderBox;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (rect.height == 1) rects.add(rect);
  }
  return rects.single;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(420, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: WidgetsApp(
        color: const Color(0xFF000000),
        localizationsDelegates: const [DefaultWidgetsLocalizations.delegate],
        supportedLocales: const [Locale('en', 'US')],
        onGenerateRoute: (settings) => PageRouteBuilder<void>(
          settings: settings,
          pageBuilder: (_, _, _) => SingleChildScrollView(child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _noop({
  required String? stopId,
  required String stopName,
  required DateTime referenceTime,
}) {}

Future<void> _pumpRide(
  WidgetTester tester, {
  Leg? previous,
  JourneyProgress progress = JourneyProgress.never,
}) => _pump(
  tester,
  LegDetailsWidget(
    leg: _ride(),
    previousLeg: previous,
    openStopSheet: _noop,
    onShowOnMap: () {},
    progress: progress,
  ),
);

/// How much of each rail on screen is drawn as already ridden, top to bottom.
List<double> _travelled(WidgetTester tester) => [
  for (final element in find.byType(SpineRail).evaluate())
    (element.widget as SpineRail).travelled,
];

Future<void> _expand(WidgetTester tester) async {
  await tester.tap(find.text('Show stops'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('collapsed, the node still carries the old card front', () {
    testWidgets('the service badge and where it is going', (tester) async {
      await _pumpRide(tester);
      expect(find.text('ICE 599'), findsOneWidget);
      expect(find.text('Flughafen BER'), findsOneWidget);
    });

    testWidgets('the stop it leaves from, and its platform', (tester) async {
      await _pumpRide(tester);
      expect(find.text('Berlin Hauptbahnhof'), findsOneWidget);
      expect(find.text('Track 7'), findsOneWidget);
    });

    testWidgets('the real departure time, and how late it is', (tester) async {
      // The timetable said :38; the train is leaving at :40 and that is the
      // number a rider needs. The delay explains it, under the station name.
      await _pumpRide(tester);
      expect(
        find.text(formatTime(_t0.add(const Duration(minutes: 10)))),
        findsOneWidget,
      );
      expect(
        find.text(formatTime(_t0.add(const Duration(minutes: 8)))),
        findsNothing,
      );
      expect(find.text('+2m'), findsOneWidget);
    });

    testWidgets('how long it takes and how far it goes', (tester) async {
      await _pumpRide(tester);
      expect(find.textContaining('50m'), findsOneWidget);
      expect(find.textContaining('41.00 km'), findsOneWidget);
    });

    testWidgets('that it has something wrong with it', (tester) async {
      // The triangle was on the old card and is the only warning until the
      // leg is opened.
      await _pumpRide(tester);
      expect(find.byIcon(LucideIcons.triangleAlert), findsOneWidget);
    });
  });

  group('expanded, the rest of the old card is there', () {
    testWidgets('the class of vehicle', (tester) async {
      await _pumpRide(tester);
      await _expand(tester);
      expect(find.textContaining('High-speed Train'), findsOneWidget);
    });

    testWidgets('the alert, in full', (tester) async {
      await _pumpRide(tester);
      await _expand(tester);
      expect(find.text('Lift out of order'), findsOneWidget);
      expect(find.text('Use the stairs.'), findsOneWidget);
    });

    testWidgets('every metadata chip the leg qualifies for', (tester) async {
      await _pumpRide(tester);
      await _expand(tester);
      expect(find.text('Real-time'), findsOneWidget);
      expect(find.text('Deutsche Bahn'), findsOneWidget);
      expect(find.text('Intercity-Express 599'), findsOneWidget);
      expect(find.text('Interlined'), findsOneWidget);
      // Not a chip: the red time and the grey minutes already say it.
      expect(find.text('Delayed'), findsNothing);
    });

    testWidgets('each stop between, with both its times and its platform', (
      tester,
    ) async {
      await _pumpRide(tester);
      await _expand(tester);

      expect(find.text('Ostkreuz'), findsOneWidget);
      expect(
        find.text(formatTime(_t0.add(const Duration(minutes: 27)))),
        findsOneWidget,
      );
      expect(
        find.text(formatTime(_t0.add(const Duration(minutes: 30)))),
        findsOneWidget,
      );
      expect(find.text('Track 9'), findsOneWidget);
    });
  });

  testWidgets('a node shared with the leg before it shows both times', (
    tester,
  ) async {
    // The old screen printed the arrival on one card and the departure on the
    // next. One row now owns that point, so it has to print both or a time is
    // simply gone.
    final arrivesEarly = Leg.fromJson({
      'mode': 'WALK',
      'startTime': _at(const Duration(minutes: 1)),
      'endTime': _at(const Duration(minutes: 4)),
      'scheduledEndTime': _at(const Duration(minutes: 4)),
      'duration': 180,
      'from': {'name': 'Naturkundemuseum', 'lat': 52.53, 'lon': 13.38},
      'to': {'name': 'Berlin Hauptbahnhof', 'lat': 52.525, 'lon': 13.369},
    });

    await _pumpRide(tester, previous: arrivesEarly);

    // You get in at :34 and leave at :38 — the wait is the point.
    expect(
      find.text(formatTime(_t0.add(const Duration(minutes: 4)))),
      findsOneWidget,
    );
    expect(
      find.text(formatTime(_t0.add(const Duration(minutes: 10)))),
      findsOneWidget,
    );
  });

  testWidgets('a node reached and left at the same moment prints one time', (
    tester,
  ) async {
    // The change gets in at :38 and the ride leaves at :40, so the two are
    // still distinct — what must not happen is one number printed twice.
    await _pumpRide(tester, previous: _change());
    expect(
      find.text(formatTime(_t0.add(const Duration(minutes: 8)))),
      findsOneWidget,
    );
    expect(
      find.text(formatTime(_t0.add(const Duration(minutes: 10)))),
      findsOneWidget,
    );
  });

  group('a change is its own stretch of the line', () {
    testWidgets('it says it is a change, and how long you have', (
      tester,
    ) async {
      await _pump(
        tester,
        TransferLegCard(leg: _change(), openStopSheet: _noop),
      );
      expect(find.textContaining('Change'), findsOneWidget);
      expect(find.textContaining('5m'), findsOneWidget);
    });

    testWidgets('it names the place and both platforms', (tester) async {
      await _pump(
        tester,
        TransferLegCard(leg: _change(), openStopSheet: _noop),
      );
      expect(find.text('Naturkundemuseum'), findsOneWidget);
      expect(find.text('Track 2 → Track 7'), findsOneWidget);
    });

    testWidgets('it keeps the walking distance the old card printed', (
      tester,
    ) async {
      await _pump(
        tester,
        TransferLegCard(leg: _change(), openStopSheet: _noop),
      );
      expect(find.textContaining('0.26 km walk'), findsOneWidget);
    });
  });

  group('the line shows how far you have got', () {
    testWidgets('a journey not yet started is drawn whole', (tester) async {
      await _pumpRide(
        tester,
        progress: JourneyProgress(_t0.subtract(const Duration(hours: 1))),
      );

      expect(_travelled(tester), everyElement(0.0));
    });

    testWidgets('part-way through a leg, its line is part faded', (
      tester,
    ) async {
      // The ride takes 50 minutes; the clock is 20 minutes into it. A leg
      // this long is exactly why the fade splits inside a row rather than
      // flipping at its end.
      await _pumpRide(
        tester,
        progress: JourneyProgress(_t0.add(const Duration(minutes: 30))),
      );

      expect(_travelled(tester).single, closeTo(20 / 50, 0.01));
    });

    testWidgets('a leg behind you is faded end to end, ring and all', (
      tester,
    ) async {
      await _pumpRide(
        tester,
        progress: JourneyProgress(_t0.add(const Duration(hours: 2))),
      );

      expect(_travelled(tester).single, 1.0);
      final ring = tester.widget<SpineNode>(find.byType(SpineNode));
      expect(ring.color.a, lessThan(1.0));
    });

    testWidgets('the ring stays solid until you are standing at it', (
      tester,
    ) async {
      await _pumpRide(
        tester,
        progress: JourneyProgress(_t0.add(const Duration(minutes: 9))),
      );

      expect(tester.widget<SpineNode>(find.byType(SpineNode)).color.a, 1.0);
    });

    testWidgets('expanded, the fade lands between the stops you are between', (
      tester,
    ) async {
      // Ostkreuz is left at :30 past and the ride ends at :30 past the next
      // hour. Sitting at :45 puts the traveller a quarter of the way down the
      // stop's own stretch, and the leg above it fully behind.
      await _pumpRide(
        tester,
        progress: JourneyProgress(_t0.add(const Duration(minutes: 45))),
      );
      await _expand(tester);

      final rails = _travelled(tester);
      expect(rails, hasLength(2), reason: 'the leg and its one stop');
      expect(rails.first, 1.0, reason: 'the run into Ostkreuz is done');
      expect(rails.last, closeTo(15 / 30, 0.01));
    });

    testWidgets('a stop still ahead keeps its dot solid', (tester) async {
      await _pumpRide(
        tester,
        progress: JourneyProgress(_t0.add(const Duration(minutes: 20))),
      );
      await _expand(tester);

      expect(tester.widget<SpineDot>(find.byType(SpineDot)).color.a, 1.0);
    });

    testWidgets('a stop behind you has its dot faded', (tester) async {
      await _pumpRide(
        tester,
        progress: JourneyProgress(_t0.add(const Duration(minutes: 45))),
      );
      await _expand(tester);

      expect(
        tester.widget<SpineDot>(find.byType(SpineDot)).color.a,
        lessThan(1.0),
      );
    });

    testWidgets('with no clock nothing is faded at all', (tester) async {
      // The default, and what the search screen's spine relies on.
      await _pumpRide(tester);
      await _expand(tester);

      expect(_travelled(tester), everyElement(0.0));
      expect(tester.widget<SpineNode>(find.byType(SpineNode)).color.a, 1.0);
    });
  });

  group('a change keeps the delay it was told about', () {
    Future<void> pumpLate(WidgetTester tester) => _pump(
      tester,
      TransferLegCard(
        leg: _lateChange(),
        previousLeg: _arriving(const Duration(minutes: 24)),
        openStopSheet: _noop,
      ),
    );

    testWidgets('a late arrival is not overwritten by the walk beside it', (
      tester,
    ) async {
      // The two land on the same minute, and the walk has no real-time. The
      // reading that came from an observation is the one worth keeping — this
      // is why a train ten minutes down used to print calm and black.
      await pumpLate(tester);

      final shown = tester.widget<Text>(
        find.text(formatTime(_t0.add(const Duration(minutes: 24)))),
      );
      expect(shown.style!.color, kLateDeparture);
    });

    testWidgets('and says how late it is', (tester) async {
      await pumpLate(tester);
      expect(find.text('+10m'), findsOneWidget);
    });

    testWidgets('the scheduled time it beat is not printed as well', (
      tester,
    ) async {
      // One number, the real one. The rider wants the time the train is at
      // the platform, not two numbers and a subtraction.
      await pumpLate(tester);
      expect(
        find.text(formatTime(_t0.add(const Duration(minutes: 14)))),
        findsNothing,
      );
    });
  });

  group('a change the journey cannot make', () {
    testWidgets('the row says so, in words as well as in red', (tester) async {
      // Colour alone reaches nobody using a screen reader, and a rider
      // scrolling past needs the sentence to know what the red means.
      await _pump(
        tester,
        TransferLegCard(
          leg: _change(),
          openStopSheet: _noop,
          changeover: _missed(),
        ),
      );

      expect(find.text(kMissedChangeMessage), findsOneWidget);
      final node = tester.widget<SpineNode>(find.byType(SpineNode));
      // The problem notice's shape, so node and notice read as one.
      expect(node.icon, LucideIcons.octagonAlert);
      expect(node.color, kMissedChangeColor);
    });

    testWidgets('a change that works says nothing at all', (tester) async {
      await _pump(
        tester,
        TransferLegCard(
          leg: _change(),
          openStopSheet: _noop,
          changeover: _made(),
        ),
      );

      expect(find.text(kMissedChangeMessage), findsNothing);
      final node = tester.widget<SpineNode>(find.byType(SpineNode));
      expect(node.icon, LucideIcons.arrowLeftRight);
      expect(node.color, kStreetLegColor);
    });

    testWidgets('the walking time and the platforms are still there', (
      tester,
    ) async {
      // The warning replaces nothing: which platform and how far is exactly
      // what you need in order to try anyway.
      await _pump(
        tester,
        TransferLegCard(
          leg: _change(),
          openStopSheet: _noop,
          changeover: _missed(),
        ),
      );

      expect(find.textContaining('Change'), findsOneWidget);
      expect(find.text('Track 2 → Track 7'), findsOneWidget);
      expect(find.textContaining('0.26 km walk'), findsOneWidget);
    });
  });

  group('the warning at the head of the journey', () {
    testWidgets('names the station, above the rule', (tester) async {
      // Above, because it is a fact about the journey rather than a note
      // appended to it: the times below stop being true there.
      await _pump(
        tester,
        JourneyOverviewWidget(
          itinerary: _journey(),
          changeovers: [_missed()],
          onFindAlternatives: () {},
        ),
      );

      final warning = find.textContaining('Naturkundemuseum');
      expect(warning, findsOneWidget);
      expect(tester.getRect(warning).bottom, lessThan(_ruleRect(tester).top));
    });

    testWidgets('offers the search, and reports it once', (tester) async {
      var asked = 0;
      await _pump(
        tester,
        JourneyOverviewWidget(
          itinerary: _journey(),
          changeovers: [_missed()],
          onFindAlternatives: () => asked++,
        ),
      );

      await tester.tap(find.text('Find alternatives'));
      await tester.pump();
      expect(asked, 1);
    });

    testWidgets('a journey that still connects carries no warning', (
      tester,
    ) async {
      await _pump(
        tester,
        JourneyOverviewWidget(
          itinerary: _journey(),
          changeovers: [_made()],
          onFindAlternatives: () {},
        ),
      );

      expect(find.text('Find alternatives'), findsNothing);
      // Not by icon: the header's own alerts chip is a triangle too.
      expect(find.textContaining('You will not make'), findsNothing);
    });

    testWidgets('more than one break names the first and counts the rest', (
      tester,
    ) async {
      // Naming every station would list places nobody has reached yet; the
      // first is the one you get to, and the one the search starts from.
      expect(
        JourneyOverviewWidget.missedChangeMessage([_missed(), _missed()]),
        contains('1 more change'),
      );
      expect(
        JourneyOverviewWidget.missedChangeMessage([
          _missed(),
          _missed(),
          _missed(),
        ]),
        contains('2 more changes'),
      );
      expect(
        JourneyOverviewWidget.missedChangeMessage([_missed()]),
        isNot(contains('more change')),
      );
    });
  });

  group('the end of the line', () {
    testWidgets('names where you were going, which the old card did not', (
      tester,
    ) async {
      await _pump(
        tester,
        FinishLegCard(
          leg: _ride(),
          arrivalTime: _t0.add(const Duration(minutes: 60)),
          totalDuration: 3600,
          openStopSheet: _noop,
        ),
      );

      expect(find.text('Flughafen BER'), findsOneWidget);
      expect(find.textContaining('Finish'), findsOneWidget);
      expect(find.text('Track 3'), findsOneWidget);
    });
  });

  group('the row reads in the right order', () {
    testWidgets('the end station follows its own line number', (tester) async {
      // An Align in the badge used to fill half the row, so every leg put its
      // end station at the same x whatever the line was called.
      await _pump(
        tester,
        Column(
          children: [
            LegDetailsWidget(leg: _ride(), openStopSheet: _noop),
            LegDetailsWidget(
              leg: Leg.fromJson({
                'mode': 'BUS',
                'startTime': _at(Duration.zero),
                'endTime': _at(const Duration(minutes: 5)),
                'duration': 300,
                'headsign': 'Rathaus',
                'displayName': 'M4',
                'from': {'name': 'Alexanderplatz', 'lat': 52.5, 'lon': 13.4},
                'to': {'name': 'Rathaus', 'lat': 52.5, 'lon': 13.4},
              }),
              openStopSheet: _noop,
            ),
          ],
        ),
      );

      final wide = tester.getRect(find.text('ICE 599'));
      final narrow = tester.getRect(find.text('M4'));
      final afterWide = tester.getRect(find.text('Flughafen BER'));
      final afterNarrow = tester.getRect(find.text('Rathaus').first);

      // Same margin after the badge, so different badges put their end
      // stations at different x.
      expect(
        afterWide.left - wide.right,
        closeTo(afterNarrow.left - narrow.right, 1.0),
      );
      expect(afterWide.left, isNot(closeTo(afterNarrow.left, 4.0)));
    });

    testWidgets('the departure holds the row, the arrival hangs above it', (
      tester,
    ) async {
      final arrivesEarly = Leg.fromJson({
        'mode': 'WALK',
        'startTime': _at(const Duration(minutes: 1)),
        'endTime': _at(const Duration(minutes: 4)),
        'scheduledEndTime': _at(const Duration(minutes: 4)),
        'duration': 180,
        'from': {'name': 'Naturkundemuseum', 'lat': 52.53, 'lon': 13.38},
        'to': {'name': 'Berlin Hauptbahnhof', 'lat': 52.525, 'lon': 13.369},
      });
      await _pumpRide(tester, previous: arrivesEarly);

      final arrival = tester.getRect(
        find.text(formatTime(_t0.add(const Duration(minutes: 4)))),
      );
      final departure = tester.getRect(
        find.text(formatTime(_t0.add(const Duration(minutes: 10)))),
      );
      final ring = tester.getRect(find.byType(SpineNode));

      // The one you can still catch is the one level with the ring.
      expect(departure.center.dy, closeTo(ring.center.dy, 3.0));
      expect(arrival.bottom, lessThanOrEqualTo(departure.top));
    });

    testWidgets('lateness and liveness are in the colour', (tester) async {
      // A reported service arriving on the minute, into a reported one
      // leaving two minutes late.
      final arrivesEarly = Leg.fromJson({
        'mode': 'BUS',
        'startTime': _at(const Duration(minutes: 1)),
        'endTime': _at(const Duration(minutes: 4)),
        'scheduledEndTime': _at(const Duration(minutes: 4)),
        'realTime': true,
        'duration': 180,
        'from': {'name': 'Naturkundemuseum', 'lat': 52.53, 'lon': 13.38},
        'to': {'name': 'Berlin Hauptbahnhof', 'lat': 52.525, 'lon': 13.369},
      });
      await _pumpRide(tester, previous: arrivesEarly);

      Color colourOf(String time) =>
          tester.widget<Text>(find.text(time)).style!.color!;

      // The ride is two minutes late, so its departure is the strong red;
      // the walk got in on the minute, so its arrival is the light green.
      expect(
        colourOf(formatTime(_t0.add(const Duration(minutes: 10)))),
        kLateDeparture,
      );
      expect(
        colourOf(formatTime(_t0.add(const Duration(minutes: 4)))),
        kOnTimeArrival,
      );
    });

    testWidgets('a leg nobody is reporting on stays black', (tester) async {
      // Green has to mean "the operator is saying this". A purely planned
      // time must look no different from how it always did.
      await _pump(
        tester,
        LegDetailsWidget(
          leg: Leg.fromJson({
            'mode': 'BUS',
            'startTime': _at(const Duration(minutes: 5)),
            'endTime': _at(const Duration(minutes: 20)),
            'duration': 900,
            'displayName': 'M4',
            'from': {'name': 'Alexanderplatz', 'lat': 52.5, 'lon': 13.4},
            'to': {'name': 'Rathaus', 'lat': 52.5, 'lon': 13.4},
          }),
          openStopSheet: _noop,
        ),
      );

      final colour = tester
          .widget<Text>(
            find.text(formatTime(_t0.add(const Duration(minutes: 5)))),
          )
          .style!
          .color!;
      expect(colour, isNot(kOnTimeDeparture));
      expect(colour, isNot(kLateDeparture));
    });

    testWidgets('a stop keeps its own times, and clears the next stop', (
      tester,
    ) async {
      await _pump(
        tester,
        LegDetailsWidget(
          leg: Leg.fromJson({
            'mode': 'HIGHSPEED_RAIL',
            'startTime': _at(Duration.zero),
            'endTime': _at(const Duration(minutes: 60)),
            'duration': 3600,
            'displayName': 'ICE 599',
            'from': {'name': 'Hbf', 'lat': 52.5, 'lon': 13.4},
            'to': {'name': 'BER', 'lat': 52.4, 'lon': 13.5},
            'intermediateStops': [
              {
                'name': 'Ostkreuz',
                'lat': 52.5,
                'lon': 13.4,
                'stopId': 'stop-ost',
                'scheduledArrival': _at(const Duration(minutes: 20)),
                'scheduledDeparture': _at(const Duration(minutes: 22)),
              },
              {
                'name': 'Schönefeld',
                'lat': 52.5,
                'lon': 13.4,
                'stopId': 'stop-sxf',
                'scheduledArrival': _at(const Duration(minutes: 40)),
                'scheduledDeparture': _at(const Duration(minutes: 42)),
              },
            ],
          }),
          openStopSheet: _noop,
        ),
      );
      await _expand(tester);

      final first = tester.getRect(find.text('Ostkreuz'));
      final second = tester.getRect(find.text('Schönefeld'));
      final arrival = tester.getRect(
        find.text(formatTime(_t0.add(const Duration(minutes: 20)))),
      );
      final departure = tester.getRect(
        find.text(formatTime(_t0.add(const Duration(minutes: 22)))),
      );

      // Every point on the spine reads the same way now: the departure is
      // level with the station name, the arrival hangs above it, and the
      // spacing to the next station is what says which one they belong to.
      expect(departure.center.dy, closeTo(first.center.dy, 2.0));
      expect(arrival.bottom, lessThanOrEqualTo(departure.top + 1));

      // And the next station is far enough off that the pair reads as this
      // one's rather than as floating between the two.
      expect(second.top - first.bottom, greaterThan(24));
    });
  });

  group('the journey header', () {
    testWidgets('shows calories only while the setting allows', (tester) async {
      await _pump(
        tester,
        JourneyOverviewWidget(
          itinerary: Itinerary(
            duration: 3600,
            startTime: _t0,
            endTime: _t0.add(const Duration(minutes: 60)),
            transfers: 0,
            legs: [_change(), _ride()],
          ),
        ),
      );
      expect(find.byIcon(LucideIcons.flame), findsNothing);

      await Provider.of<ThemeProvider>(
        tester.element(find.byType(JourneyOverviewWidget)),
        listen: false,
      ).setShowCalories(true);
      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.flame), findsOneWidget);
    });

    testWidgets('has no box, and a rule under it instead', (tester) async {
      await _pump(
        tester,
        JourneyOverviewWidget(
          itinerary: Itinerary(
            duration: 3600,
            startTime: _t0,
            endTime: _t0.add(const Duration(minutes: 60)),
            transfers: 1,
            legs: [_ride()],
          ),
        ),
      );

      expect(find.byType(CustomCard), findsNothing);
    });

    testWidgets("its map icon matches a leg's, on the same edge", (
      tester,
    ) async {
      await _pump(
        tester,
        Column(
          children: [
            JourneyOverviewWidget(
              itinerary: Itinerary(
                duration: 3600,
                startTime: _t0,
                endTime: _t0.add(const Duration(minutes: 60)),
                transfers: 1,
                legs: [_ride()],
              ),
            ),
            LegDetailsWidget(
              leg: _change(),
              openStopSheet: _noop,
              onShowOnMap: () {},
            ),
          ],
        ),
      );

      final icons = find.byIcon(LucideIcons.map);
      expect(icons, findsNWidgets(2));
      final header = tester.getRect(icons.first);
      final leg = tester.getRect(icons.last);
      expect(header.right, closeTo(leg.right, 0.5));
      expect(header.width, closeTo(leg.width, 0.5));
      expect(header.right, closeTo(420 - JourneyMetrics.screenPadding, 0.5));
    });
  });

  testWidgets('nothing a row prints lands on the row above it', (tester) async {
    // The bug this rework started from: the arrival was raised with a paint
    // transform, which moves pixels without reserving layout, so on a stop
    // with a delay it landed on top of the times of the station before.
    //
    // A guard rather than a proof. What actually cured that case was the
    // delay leaving the time column, which shrank the lift to one line;
    // reserving the space in layout is what stops it coming back whatever
    // else grows. This catches the class of fault, not the instance — see
    // the delay tests for the instance.
    await _pump(
      tester,
      Column(
        children: [
          LegDetailsWidget(
            leg: _ride(),
            previousLeg: _change(),
            openStopSheet: _noop,
          ),
          TransferLegCard(
            leg: _change(),
            previousLeg: _ride(),
            openStopSheet: _noop,
          ),
        ],
      ),
    );
    await tester.tap(find.text('Show stops'));
    await tester.pumpAndSettle();

    final texts = find.byType(Text).evaluate().toList();
    final boxes = <String, Rect>{};
    for (final element in texts) {
      final widget = element.widget as Text;
      final label = widget.data;
      if (label == null || label.isEmpty) continue;
      final rect = tester.getRect(find.byWidget(widget));
      if (rect.isEmpty) continue;
      boxes['\$label@\${rect.top}'] = rect;
    }

    final entries = boxes.entries.toList();
    for (var i = 0; i < entries.length; i++) {
      for (var j = i + 1; j < entries.length; j++) {
        final a = entries[i].value;
        final b = entries[j].value;
        final overlap = a.intersect(b);
        expect(
          overlap.width <= 0 || overlap.height <= 0,
          isTrue,
          reason: '\${entries[i].key} overlaps \${entries[j].key}',
        );
      }
    }
  });

  group('the platform column mirrors the times', () {
    testWidgets('a platform arrived at and left from is printed once', (
      tester,
    ) async {
      // The walk ends on the platform the ride leaves from, so the column
      // read "Track 7" over "Track 7" — true twice and useful once.
      await _pumpRide(tester, previous: _change());

      expect(find.text('Track 7'), findsOneWidget);
    });

    testWidgets('two different platforms are both printed, in order', (
      tester,
    ) async {
      // Arriving at one and leaving from another is the whole of what this
      // column is for, and the arrival belongs above.
      await _pumpRide(tester, previous: _change(arrivesAtTrack: '4'));

      final arrival = tester.getRect(find.text('Track 4'));
      final departure = tester.getRect(find.text('Track 7'));
      expect(arrival.bottom, lessThanOrEqualTo(departure.top + 1));
    });

    testWidgets('the platforms line up with the times beside them', (
      tester,
    ) async {
      await _pumpRide(tester, previous: _change(arrivesAtTrack: '4'));

      final arrivalTime = tester.getRect(
        find.text(formatTime(_t0.add(const Duration(minutes: 8)))),
      );
      final departureTime = tester.getRect(
        find.text(formatTime(_t0.add(const Duration(minutes: 10)))),
      );

      expect(
        tester.getRect(find.text('Track 4')).center.dy,
        closeTo(arrivalTime.center.dy, 2.0),
      );
      expect(
        tester.getRect(find.text('Track 7')).center.dy,
        closeTo(departureTime.center.dy, 2.0),
      );
    });

    testWidgets('dropping the repeat does not move the row', (tester) async {
      // The empty slot is kept, or the platform column would ride up and
      // stop being level with the times it mirrors.
      await _pumpRide(tester, previous: _change());
      final same = tester.getRect(find.text('Track 7'));

      await _pumpRide(tester, previous: _change(arrivesAtTrack: '4'));
      final differing = tester.getRect(find.text('Track 7'));

      expect(same.center.dy, closeTo(differing.center.dy, 0.5));
    });
  });

  testWidgets('the delay is grey, not the colour of its time', (tester) async {
    // The time above it is already the real one. A red "+2m" reads as two
    // minutes still to add to a number that has had them added.
    await _pumpRide(tester);

    final delay = tester.widget<Text>(find.text('+2m')).style!.color!;
    expect(delay, isNot(kLateDeparture));
    expect(delay, isNot(kLateArrival));
    // Grey: no hue of its own.
    expect(delay.r, closeTo(delay.g, 0.01));
    expect(delay.g, closeTo(delay.b, 0.01));
  });
}
