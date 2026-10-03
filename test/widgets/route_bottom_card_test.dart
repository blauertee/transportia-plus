import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/models/my_location.dart';
import 'package:transportia/models/saved_trip.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/widgets/map/bottom_sheet_chrome.dart';
import 'package:transportia/widgets/search/editable_value.dart';

import '../support/bottom_card_host.dart';
import '../support/plan_fixtures.dart';

SavedTrip _trip({String from = 'Home', String to = 'Airport', String? id}) =>
    SavedTrip.fromItinerary(
      itinerary: Itinerary.fromJson(
        planItineraryJson(
          departure: DateTime.utc(2026, 9, 28, 8),
          tripId: id ?? 'trip-$to',
        ),
      ),
      fromName: from,
      toName: to,
    );

Future<void> _pump(WidgetTester tester, BottomCardHost host) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(host);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('the origin and time', () {
    testWidgets('start from where the rider is, leaving now', (tester) async {
      // The screen fills My Location in; the card only shows it.
      await _pump(tester, const BottomCardHost(from: myLocationName));

      expect(find.text(myLocationName), findsOneWidget);
      expect(find.text('Leave now'), findsOneWidget);
    });

    testWidgets('each opens its own picker', (tester) async {
      var from = 0;
      var time = 0;
      await _pump(
        tester,
        BottomCardHost(
          from: myLocationName,
          onFromPressed: () => from++,
          onTimeSelectionTap: () => time++,
        ),
      );

      await tester.tap(find.text(myLocationName));
      await tester.tap(find.text('Leave now'));

      expect(from, 1);
      expect(time, 1);
    });

    testWidgets('an empty origin asks for one', (tester) async {
      // No more standing in for My Location: that is a value of its own.
      await _pump(tester, const BottomCardHost());

      expect(find.text('From'), findsOneWidget);
      expect(find.text(myLocationName), findsNothing);
    });

    testWidgets('a picked origin is shown by name', (tester) async {
      await _pump(tester, const BottomCardHost(from: 'Hauptbahnhof'));

      expect(find.text('Hauptbahnhof'), findsOneWidget);
      expect(find.text(myLocationName), findsNothing);
    });
  });

  testWidgets('swap always swaps, whatever the fields hold', (tester) async {
    var swaps = 0;
    await _pump(tester, BottomCardHost(onSwapRequested: () => swaps++));

    // Both empty included: nothing to refuse, so no toast either.
    await tester.tap(find.bySemanticsLabel('Swap origin and destination'));
    await tester.pump();
    expect(swaps, 1);
    expect(find.textContaining('Supply at least'), findsNothing);
  });

  testWidgets('the ends are not kept from here', (tester) async {
    // Keeping a place happens where it is found, in the place search; a
    // heart here was a second way to do it with less to go on.
    await _pump(
      tester,
      const BottomCardHost(from: 'Hauptbahnhof', to: 'Ostkreuz'),
    );

    expect(find.byIcon(LucideIcons.heart), findsNothing);
  });

  group('the destination', () {
    testWidgets('asks to be searched for while empty', (tester) async {
      await _pump(tester, const BottomCardHost());

      expect(find.text('Search destination'), findsOneWidget);
      expect(find.byIcon(LucideIcons.search), findsOneWidget);
    });

    testWidgets('once set, offers to be changed like the others', (
      tester,
    ) async {
      await _pump(tester, const BottomCardHost(to: 'Alexanderplatz'));

      expect(find.text('Alexanderplatz'), findsOneWidget);
      expect(find.text('Search destination'), findsNothing);
      expect(find.byIcon(LucideIcons.search), findsNothing);
      // Origin, time and destination each carry one.
      expect(
        find.descendant(
          of: find.byType(EditableValue),
          matching: find.byIcon(LucideIcons.chevronDown),
        ),
        findsNWidgets(3),
      );
    });

    testWidgets('picks up a place set after the card was built', (
      tester,
    ) async {
      // It is text now, not a field that repaints itself, so the card has to
      // follow the controller.
      await _pump(tester, const BottomCardHost());

      tester
              .state<BottomCardHostState>(find.byType(BottomCardHost))
              .toCtrl
              .text =
          'Ostkreuz';
      await tester.pump();

      expect(find.text('Ostkreuz'), findsOneWidget);
    });
  });

  testWidgets('Search sends the chosen time', (tester) async {
    final chosen = TimeSelection(
      dateTime: DateTime(2026, 9, 28, 9),
      isArriveBy: true,
    );
    TimeSelection? sent;
    await _pump(
      tester,
      BottomCardHost(timeSelection: chosen, onSearch: (t) => sent = t),
    );

    await tester.tap(find.text('Search'));

    expect(sent, same(chosen));
  });

  group('recent trips', () {
    testWidgets('are not listed when there are none', (tester) async {
      await _pump(tester, const BottomCardHost());

      expect(find.text('Recent trips'), findsNothing);
    });

    testWidgets('show where each went from and to, one heading', (
      tester,
    ) async {
      await _pump(
        tester,
        BottomCardHost(
          recentTrips: [
            _trip(from: 'Home', to: 'Airport'),
            _trip(from: 'Office', to: 'Stadium'),
          ],
        ),
      );

      expect(find.text('Recent trips'), findsOneWidget);
      expect(find.text('Recent destinations'), findsNothing);
      for (final name in ['Home', 'Airport', 'Office', 'Stadium']) {
        expect(find.text(name), findsOneWidget);
      }
    });

    testWidgets('hand back the trip that was tapped', (tester) async {
      final second = _trip(from: 'Office', to: 'Stadium');
      SavedTrip? tapped;
      await _pump(
        tester,
        BottomCardHost(
          recentTrips: [_trip(), second],
          onRecentTripTap: (t) => tapped = t,
        ),
      );

      await tester.tap(find.text('Stadium'));

      expect(tapped, same(second));
    });
  });

  group('without the map', () {
    testWidgets('the card is the page: no handle to drag it by', (
      tester,
    ) async {
      await _pump(tester, const BottomCardHost(asPage: true));

      expect(find.byType(BottomSheetHandle), findsNothing);
      expect(find.text('Search destination'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
    });

    testWidgets('over the map it keeps its handle', (tester) async {
      await _pump(tester, const BottomCardHost());

      expect(find.byType(BottomSheetHandle), findsOneWidget);
    });
  });
}
