import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/itinerary_response.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/providers/journey_locks_controller.dart';
import 'package:transportia/services/journey_graph_service.dart';
import 'package:transportia/utils/duration_formatter.dart';
import 'package:transportia/utils/journey_graph.dart';
import 'package:transportia/utils/time_utils.dart';
import 'package:transportia/widgets/journey/journey_graph_panel.dart';
import 'package:transportia/widgets/journey/journey_graph_view.dart';

import '../support/app_shell.dart';

List<Itinerary> _load(String name) => ItineraryResponse.fromJson(
  jsonDecode(File('test/fixtures/transitous/$name.json').readAsStringSync())
      as Map<String, dynamic>,
).itineraries;

final _query = JourneyQuery(
  fromLat: 52.29,
  fromLon: 13.63,
  toLat: 47.54,
  toLon: 9.68,
  time: TimeSelection(
    dateTime: DateTime.utc(2026, 10, 27, 9, 40),
    isArriveBy: false,
  ),
);

void main() {
  final results = _load('plan_journey_graph');
  final onward = _load('plan_journey_graph_onward');
  final viaIngolstadt = results.firstWhere(
    (it) => it.legs.any((leg) => leg.displayName == 'ICE 1009'),
  );
  final ice1009 = viaIngolstadt.legs.firstWhere(
    (leg) => leg.displayName == 'ICE 1009',
  );

  /// Answers a ride lock with the search on from Ingolstadt, joined as the
  /// real service joins it, and anything else with [results].
  late List<JourneyGraphSearch> searches;
  Future<JourneyGraphPage> fakeSearch(JourneyGraphSearch search) async {
    searches.add(search);
    final lock = search.lock;
    if (lock == null) return JourneyGraphPage(results);
    return JourneyGraphPage(continueAfter(lock.itinerary, lock.upTo, onward));
  }

  Itinerary? opened;

  /// The bar of the ride called [name].
  Finder rideBar(String name) => find.byWidgetPredicate(
    (widget) =>
        widget.runtimeType.toString() == '_RideBar' &&
        ((widget as dynamic).ride as GraphRide).leg.displayName == name,
  );

  /// The lines of text on [bar], top to bottom.
  List<Text> linesOn(Finder bar) => [
    for (final line
        in find.descendant(of: bar, matching: find.byType(Text)).evaluate())
      line.widget as Text,
  ];

  /// What the screen shows before anything is locked; set to show a page
  /// more.
  final shown = ValueNotifier<List<Itinerary>>(const []);
  var earlier = 0, later = 0;

  Future<void> pumpPanel(
    WidgetTester tester, {
    RideLock? initialLock,
    JourneyGraphSearcher? search,
    List<Itinerary>? first,
    bool showCopyData = false,
  }) async {
    searches = [];
    opened = null;
    earlier = later = 0;
    shown.value = first ?? results;
    final controller = JourneyLocksController(
      query: () => _query,
      initialLock: initialLock,
      search: search ?? fakeSearch,
    );
    addTearDown(controller.dispose);
    await pumpInAppShell(
      tester,
      ValueListenableBuilder<List<Itinerary>>(
        valueListenable: shown,
        builder: (_, results, _) => JourneyGraphPanel(
          controller: controller,
          results: results,
          onOpen: (itinerary) => opened = itinerary,
          now: () => DateTime.utc(2026, 10, 27, 8),
          onLoadEarlier: () => earlier++,
          onLoadLater: () => later++,
          showCopyData: showCopyData,
        ),
      ),
    );
  }

  /// Drags the graph sideways by [by], a step at a time as a finger would.
  Future<void> pull(WidgetTester tester, double by) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(JourneyGraphView)),
    );
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(Offset(by / 20, 0));
      await tester.pump();
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('shows the results as they are, with nothing locked', (
    tester,
  ) async {
    await pumpPanel(tester);

    expect(searches, isEmpty);
    expect(rideBar('ICE 1507'), findsOneWidget);
    expect(find.textContaining('Open journey'), findsOneWidget);
  });

  testWidgets('locking a ride on the selected result searches on from it', (
    tester,
  ) async {
    await pumpPanel(tester);

    await tester.tap(rideBar('ICE 1507'));
    await tester.pumpAndSettle();

    expect(searches, hasLength(1));
    expect(searches.single.lock?.upTo.displayName, 'ICE 1507');
    expect(find.textContaining('Locked until'), findsOneWidget);
  });

  testWidgets('tapping a ride off the selected result selects one instead', (
    tester,
  ) async {
    await pumpPanel(tester);

    await tester.tap(rideBar('ICE 1009'));
    await tester.pumpAndSettle();

    expect(searches, isEmpty);
    await tester.tap(find.textContaining('Open journey'));
    expect(opened, same(viaIngolstadt));
  });

  testWidgets('opens on a fixed journey and fills in the search on from it', (
    tester,
  ) async {
    await pumpPanel(tester, initialLock: RideLock(viaIngolstadt, ice1009));

    expect(searches, hasLength(1));
    expect(searches.single.lock?.key, GraphRide.keyOf(ice1009));
    expect(find.text('Locked until Ingolstadt Hbf'), findsOneWidget);

    await tester.tap(find.textContaining('Open journey'));
    final legs = opened!.legs;
    expect(legs.map((leg) => leg.displayName), contains('ICE 1009'));
    expect(legs.last.endTime, onward.first.legs.last.endTime);
  });

  testWidgets('removing the lock goes back to the results', (tester) async {
    await pumpPanel(tester, initialLock: RideLock(viaIngolstadt, ice1009));

    await tester.tap(find.text('Locked until Ingolstadt Hbf'));
    await tester.pumpAndSettle();

    expect(searches, hasLength(1));
    expect(find.text('Locked until Ingolstadt Hbf'), findsNothing);
    expect(rideBar('ICE 1507'), findsOneWidget);
  });

  testWidgets('locking a station searches again through it', (tester) async {
    await pumpPanel(tester);

    await tester.tap(find.text('München Hbf').first);
    await tester.pumpAndSettle();

    expect(searches, hasLength(1));
    expect(searches.single.lock, isNull);
    expect(searches.single.via.single.name, 'München Hbf');
    expect(find.text('Locked via München Hbf'), findsOneWidget);
  });

  testWidgets('a failed search says so and keeps what is shown', (
    tester,
  ) async {
    await pumpPanel(
      tester,
      search: (search) => Future.error(const SocketException('offline')),
    );

    await tester.tap(rideBar('ICE 1507'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not search again'), findsOneWidget);
    expect(rideBar('ICE 1507'), findsOneWidget);
  });

  testWidgets('an answer to an older search is dropped', (tester) async {
    final slow = Completer<JourneyGraphPage>();
    var calls = 0;
    await pumpPanel(
      tester,
      search: (search) {
        searches.add(search);
        calls++;
        // The first search hangs; the second, unlocking, is not sent.
        return calls == 1
            ? slow.future
            : Future.value(JourneyGraphPage(results));
      },
    );

    await tester.tap(rideBar('ICE 1507'));
    await tester.pump();
    await tester.tap(find.textContaining('Locked until'));
    await tester.pumpAndSettle();
    slow.complete(
      JourneyGraphPage(continueAfter(viaIngolstadt, ice1009, onward)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Locked until'), findsNothing);
    expect(rideBar('ICE 1507'), findsOneWidget);
  });

  group('pulled past an edge', () {
    testWidgets('asks for later results past the right edge', (tester) async {
      await pumpPanel(tester);

      await pull(tester, -400);

      expect(later, 1);
      expect(earlier, 0);
    });

    testWidgets('asks for earlier results past the left edge', (tester) async {
      await pumpPanel(tester);

      await pull(tester, 400);

      expect(earlier, 1);
      expect(later, 0);
    });

    testWidgets('a short pull asks for nothing', (tester) async {
      await pumpPanel(tester);

      await pull(tester, 40);

      expect(earlier, 0);
    });

    testWidgets('keeps the selected result when a page comes in', (
      tester,
    ) async {
      await pumpPanel(tester, first: results.sublist(1));
      await tester.tap(rideBar('ICE 1009'));
      await tester.pumpAndSettle();

      shown.value = results;
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Open journey'));

      expect(opened, same(viaIngolstadt));
    });
  });

  group('copying the canvas data', () {
    testWidgets('has no button unless asked for', (tester) async {
      await pumpPanel(tester);

      expect(find.text('Copy canvas data'), findsNothing);
    });

    testWidgets('copies what it draws, enough to draw it again', (
      tester,
    ) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pumpPanel(tester, showCopyData: true);

      await tester.tap(find.text('Copy canvas data'));
      await tester.pump();

      expect(find.text('Copied'), findsOneWidget);
      final data = jsonDecode(copied!) as Map<String, dynamic>;
      final again = JourneyGraph.build(
        ItineraryResponse.fromJson({
          'itineraries': data['itineraries'],
        }).itineraries,
      );
      final graph = JourneyGraph.build(results);
      expect(again.columnCount, graph.columnCount);
      expect(
        [for (final ride in again.rides) ride.key],
        [for (final ride in graph.rides) ride.key],
      );
      expect(data['rides'], hasLength(graph.rides.length));
      expect(data['columns'], hasLength(graph.columnCount));
      // Without the shapes for the map, which are most of a result.
      expect(copied, isNot(contains('legGeometry')));

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Copy canvas data'), findsOneWidget);
    });
  });

  group('names on rides', () {
    testWidgets('shows what a name has in brackets on lines of its own', (
      tester,
    ) async {
      await pumpPanel(tester);
      final lines = linesOn(rideBar('RB15 (84284)').first);
      String text(Iterable<Text> lines) =>
          lines.map((line) => line.data).join();
      final name = lines.where((line) => line.style!.fontSize == 12);
      final note = lines.where(
        (line) =>
            line.style!.fontSize == 10 &&
            line.style!.fontWeight == FontWeight.w400,
      );

      expect(text(name).replaceAll('-', ''), 'RB15');
      expect(text(note), '84284');
      expect(lines.indexOf(note.first), greaterThan(lines.indexOf(name.last)));
    });

    testWidgets('cuts nothing short, however narrow the bar', (tester) async {
      for (final name in ['plan_journey_graph', 'plan_same_departure']) {
        await pumpPanel(tester, first: _load(name));
        final bars = find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_RideBar',
        );
        expect(bars, findsWidgets);
        for (final bar in bars.evaluate()) {
          final box = bar.renderObject! as RenderBox;
          final edges = box.localToGlobal(Offset.zero) & box.size;
          final lines = find.descendant(
            of: find.byElementPredicate((element) => element == bar),
            matching: find.byType(RichText),
          );
          for (final line in lines.evaluate()) {
            final text = line.renderObject! as RenderParagraph;
            final at = text.localToGlobal(Offset.zero) & text.size;
            final drawn = (line.widget as RichText).text.toPlainText();
            expect(
              text.getMaxIntrinsicWidth(double.infinity),
              lessThanOrEqualTo(text.size.width + 0.01),
              reason: '"$drawn" is cut short',
            );
            expect(
              at.left >= edges.left &&
                  at.top >= edges.top &&
                  at.right <= edges.right &&
                  at.bottom <= edges.bottom + 0.01,
              isTrue,
              reason: '"$drawn" runs past its bar',
            );
          }
        }
      }
    });

    testWidgets('shows how long each ride takes, not when it leaves', (
      tester,
    ) async {
      await pumpPanel(tester);
      final ice1507 = results
          .expand((it) => it.legs)
          .firstWhere((leg) => leg.displayName == 'ICE 1507');
      final lines = [
        for (final line in linesOn(rideBar('ICE 1507'))) line.data!,
      ];

      expect(
        lines.join(' '),
        endsWith(
          formatDuration(
            ice1507.endTime.difference(ice1507.startTime).inSeconds,
          ),
        ),
      );
      expect(lines, isNot(contains(formatTime(ice1507.startTime))));
    });
  });
}
