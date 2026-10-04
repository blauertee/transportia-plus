import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:transportia/models/quick_access_layout.dart';
import 'package:transportia/models/routing_options.dart';
import 'package:transportia/models/transit_mode_group.dart';
import 'package:transportia/models/transitous/enums.dart';
import 'package:transportia/models/transitous/server_config.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/widgets/options/icon_controls.dart';
import 'package:transportia/theme/journey_metrics.dart';
import 'package:transportia/utils/app_icons.dart';
import 'package:transportia/utils/stage_summary.dart';
import 'package:transportia/widgets/journey/spine_node.dart';
import 'package:transportia/widgets/journey/spine_row.dart';
import 'package:transportia/widgets/search/journey_segment.dart';
import 'package:transportia/widgets/search/journey_spine.dart';
import 'package:transportia/widgets/search/leg_panel.dart';
import 'package:transportia/widgets/search/traveller_strip.dart';

/// Holds the options the way the search screen will, so a tap on a control
/// comes back as a rebuilt spine rather than only as a callback.
class _Host extends StatefulWidget {
  const _Host({
    required this.initial,
    this.providerNames = const [],
    this.opening = SearchOptionsOpening.closed,
  });

  final RoutingOptions initial;
  final List<String> providerNames;
  final SearchOptionsOpening opening;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late RoutingOptions options = widget.initial;
  int viaTaps = 0;
  bool limitToMyProviders = false;
  late SearchOptionsOpening opening = widget.opening;

  /// The setting arriving, or changing, while the card is up.
  void setOpening(SearchOptionsOpening next) => setState(() => opening = next);

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 380,
            child: JourneySpine(
              options: options,
              capabilities: ServerConfig.fallback,
              onChanged: (next) => setState(() => options = next),
              onAddViaStop: () => viaTaps++,
              limitToMyProviders: limitToMyProviders,
              rentalProviderNames: widget.providerNames,
              onLimitToMyProvidersChanged: (value) =>
                  setState(() => limitToMyProviders = value),
              opening: opening,
            ),
          ),
        ),
      ),
    );
  }
}

Future<_HostState> _pumpSpine(
  WidgetTester tester, {
  RoutingOptions initial = RoutingOptions.defaults,
  List<String> providerNames = const [],
  SearchOptionsOpening opening = SearchOptionsOpening.closed,
}) async {
  // Tall enough that an expanded stage is on screen and so tappable; the
  // default 800x600 surface would push the last stage past the bottom.
  tester.view.physicalSize = const Size(420, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    _Host(initial: initial, providerNames: providerNames, opening: opening),
  );
  return tester.state<_HostState>(find.byType(_Host));
}

/// A stage's summary line, put together the way the card does it.
Finder _summary(String what, String limit) =>
    find.text(stageSummary(what, limit));

/// An icon-only pick that is actually on screen.
///
/// `AnimatedCrossFade` keeps the collapsed branch in the tree behind an
/// `IgnorePointer`, so "is it offered" has to mean "can it be pressed".
Finder _pick(String label) => find
    .byWidgetPredicate((w) => w is IconPick && w.label == label)
    .hitTestable();

Finder _valueChip(String label) => find
    .byWidgetPredicate((w) => w is ValueChip && w.label == label)
    .hitTestable();

Future<void> _open(WidgetTester tester, String headline) async {
  await tester.tap(find.text(headline));
  await tester.pumpAndSettle();
}

/// Lets an on-screen message time out, so it does not outlive the test.
Future<void> _quiet(WidgetTester tester) =>
    tester.pump(const Duration(seconds: 2));

void main() {
  testWidgets('collapsed sections summarise the current state', (tester) async {
    await _pumpSpine(tester);

    expect(find.text('TO THE STATION'), findsOneWidget);
    expect(find.text('PUBLIC TRANSPORT'), findsOneWidget);
    expect(find.text('FROM THE STATION'), findsOneWidget);

    // Both street legs default to a quarter-hour walk.
    expect(_summary('Walk', '15 min'), findsNWidgets(2));
    expect(_summary('All transport', 'unlimited changes'), findsOneWidget);
  });

  testWidgets('the summary names the sections that are on', (tester) async {
    await _pumpSpine(
      tester,
      initial: RoutingOptions.defaults.copyWith(
        firstMileModes: const [TransitMode.walk, TransitMode.rental],
        firstMileRentalFormFactors: const [RentalFormFactor.scooterStanding],
        maxFirstMileTime: const Duration(minutes: 90),
      ),
    );

    expect(_summary('Walk, shared bikes & scooters', '1 h 30'), findsOneWidget);
    expect(_summary('Walk', '15 min'), findsOneWidget);
  });

  testWidgets('opening one stage leaves the others closed', (tester) async {
    await _pumpSpine(tester);
    expect(_pick('Shared bikes & scooters'), findsNothing);

    await _open(tester, 'TO THE STATION');
    expect(_pick('Shared bikes & scooters'), findsOneWidget);
    expect(_pick('No reservation needed'), findsNothing);

    await _open(tester, 'PUBLIC TRANSPORT');
    // Stages expand independently, so both stay open.
    expect(_pick('Shared bikes & scooters'), findsOneWidget);
    expect(_pick('No reservation needed'), findsOneWidget);

    await _open(tester, 'TO THE STATION');
    expect(_pick('Shared bikes & scooters'), findsNothing);
    expect(_pick('No reservation needed'), findsOneWidget);
  });

  group('a street leg', () {
    testWidgets('offers every section as an icon, but not Other', (
      tester,
    ) async {
      await _pumpSpine(tester);
      await _open(tester, 'TO THE STATION');
      for (final section in QuickAccessLayout.defaults.street) {
        expect(_pick(section.title), findsOneWidget, reason: section.id);
      }
      expect(_pick('Other'), findsNothing);
    });

    testWidgets('a section icon switches the whole section, and says so', (
      tester,
    ) async {
      final host = await _pumpSpine(tester);
      await _open(tester, 'TO THE STATION');

      await tester.tap(_pick('Shared bikes & scooters'));
      await tester.pump();

      expect(
        host.options.firstMileRentalFormFactors,
        unorderedEquals(const [
          RentalFormFactor.bicycle,
          RentalFormFactor.cargoBicycle,
          RentalFormFactor.scooterStanding,
          RentalFormFactor.scooterSeated,
          RentalFormFactor.other,
        ]),
      );
      expect(host.options.firstMileModes, contains(TransitMode.rental));
      expect(find.text('Shared bikes & scooters to the station'), findsOne);
      // And it stays this leg's business.
      expect(host.options.lastMileRentalFormFactors, isEmpty);

      await tester.tap(_pick('Shared bikes & scooters'));
      await tester.pump();
      expect(host.options.firstMileRentalFormFactors, isEmpty);
      expect(host.options.firstMileModes, isNot(contains(TransitMode.rental)));
      await _quiet(tester);
    });

    testWidgets('a partly-on section is drawn as partly on', (tester) async {
      await _pumpSpine(
        tester,
        initial: RoutingOptions.defaults.copyWith(
          firstMileModes: const [TransitMode.walk, TransitMode.rental],
          firstMileRentalFormFactors: const [RentalFormFactor.bicycle],
        ),
      );
      await _open(tester, 'TO THE STATION');

      final shared = tester.widget<IconPick>(_pick('Shared bikes & scooters'));
      expect(shared.selected, isFalse);
      expect(shared.partial, isTrue);
    });

    testWidgets('all options shows every choice under its section', (
      tester,
    ) async {
      final host = await _pumpSpine(tester);
      await _open(tester, 'TO THE STATION');
      await tester.tap(find.text('All options').hitTestable());
      await tester.pumpAndSettle();

      // Every street mode and shared vehicle has a tick somewhere, so none
      // the defaults editor can store is out of reach here.
      for (final section in QuickAccessLayout.defaults.streetSections) {
        expect(find.text(section.title.toUpperCase()), findsOneWidget);
        if (section.items.length < 2) continue;
        for (final item in section.items) {
          expect(find.text(item.label).hitTestable(), findsWidgets);
        }
      }
      expect(find.text('Shared car').hitTestable(), findsOneWidget);
      expect(find.text('Lorry').hitTestable(), findsOneWidget);

      await tester.tap(find.text('Drop-off').hitTestable());
      await tester.pump();
      expect(host.options.firstMileModes, contains(TransitMode.carDropoff));
      await _quiet(tester);
    });

    testWidgets('a section heading switches its section too', (tester) async {
      final host = await _pumpSpine(tester);
      await _open(tester, 'TO THE STATION');
      await tester.tap(find.text('All options').hitTestable());
      await tester.pumpAndSettle();

      final heading = tester.getRect(
        find.byWidgetPredicate((w) => w is LegHeading && w.title == 'Own car'),
      );
      // Near the far end of the row, clear of the word itself: the whole row
      // is the target.
      await tester.tapAt(Offset(heading.right - 20, heading.center.dy));
      await tester.pump();

      expect(
        host.options.firstMileModes,
        containsAll(const [
          TransitMode.car,
          TransitMode.carParking,
          TransitMode.carDropoff,
        ]),
      );
      // Own and shared cars are separate sections now.
      expect(host.options.firstMileRentalFormFactors, isEmpty);
      await _quiet(tester);
    });

    testWidgets('the budget chip opens its slider in place for one change', (
      tester,
    ) async {
      final host = await _pumpSpine(tester);
      await _open(tester, 'TO THE STATION');
      expect(find.byType(OptionSlider), findsNothing);

      await tester.tap(_valueChip('Time budget'));
      await tester.pumpAndSettle();
      // Under the compact rows, not in the full view.
      expect(find.text('All options').hitTestable(), findsOneWidget);

      final slider = tester.widget<OptionSlider>(find.byType(OptionSlider));
      slider.onChanged(30);
      await tester.pump();
      expect(host.options.maxFirstMileTime, const Duration(minutes: 30));
      expect(_summary('Walk', '30 min'), findsOneWidget);

      slider.onChangeEnd!();
      await tester.pumpAndSettle();
      expect(find.byType(OptionSlider), findsNothing);
    });

    testWidgets('the budget slider stays open in the full view', (
      tester,
    ) async {
      await _pumpSpine(tester);
      await _open(tester, 'TO THE STATION');
      await tester.tap(find.text('All options').hitTestable());
      await tester.pumpAndSettle();

      final slider = tester.widget<OptionSlider>(find.byType(OptionSlider));
      expect(slider.onChangeEnd, isNull);
    });

    testWidgets('the stage icon follows the last section on', (tester) async {
      await _pumpSpine(
        tester,
        initial: RoutingOptions.defaults.copyWith(
          firstMileModes: const [TransitMode.walk, TransitMode.bike],
        ),
      );

      expect(_summary('Walk, own bike', '15 min'), findsOneWidget);
      final ring = tester.widget<SpineNode>(find.byType(SpineNode).first);
      expect(ring.appIcon, const GlyphIcon(LucideIcons.bike));
    });
  });

  group('transport', () {
    testWidgets('"All transport" holds only while nothing is narrowed', (
      tester,
    ) async {
      final host = await _pumpSpine(tester);
      await _open(tester, 'PUBLIC TRANSPORT');

      await tester.tap(_pick('Boat'));
      await tester.pump();

      expect(_summary('All transport', 'unlimited changes'), findsNothing);
      expect(host.options.transitModes, isNotEmpty);
      expect(host.options.transitModes, isNot(contains(TransitMode.ferry)));

      await tester.tap(_pick('Boat'));
      await tester.pump();

      expect(_summary('All transport', 'unlimited changes'), findsOneWidget);
      // Everything on sends nothing, so a mode added upstream is not
      // silently excluded by an enumerated list.
      expect(host.options.transitModes, isEmpty);
      await _quiet(tester);
    });

    testWidgets('the modes no group covers have a section of their own', (
      tester,
    ) async {
      final host = await _pumpSpine(tester);
      await _open(tester, 'PUBLIC TRANSPORT');

      await tester.tap(_pick('Other'));
      await tester.pump();

      for (final mode in TransitModeGroup.extras) {
        expect(host.options.transitModes, isNot(contains(mode)));
      }
      await _quiet(tester);
    });

    testWidgets('unticking a mode in the full view narrows the search', (
      tester,
    ) async {
      final host = await _pumpSpine(tester);
      await _open(tester, 'PUBLIC TRANSPORT');
      await tester.tap(find.text('All options').hitTestable());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Flights').hitTestable());
      await tester.pump();

      expect(host.options.transitModes, isNotEmpty);
      expect(host.options.transitModes, isNot(contains(TransitMode.airplane)));
      expect(_summary('All transport', 'unlimited changes'), findsNothing);
      await _quiet(tester);
    });

    testWidgets('a half-picked group is drawn as partly on', (tester) async {
      await _pumpSpine(
        tester,
        initial: RoutingOptions.defaults.withTransitSelection(
          TransitSelection({TransitMode.longDistance}),
        ),
      );
      await _open(tester, 'PUBLIC TRANSPORT');

      final rail = tester.widget<IconPick>(_pick('Rail'));
      expect(rail.selected, isFalse);
      expect(rail.partial, isTrue);
    });

    testWidgets('regional only drops every long-distance service', (
      tester,
    ) async {
      final host = await _pumpSpine(tester);
      await _open(tester, 'PUBLIC TRANSPORT');

      await tester.tap(_pick('Regional only'));
      await tester.pump();

      for (final mode in TransitModeGroup.longDistance) {
        expect(host.options.transitModes, isNot(contains(mode)));
      }
      expect(host.options.transitModes, contains(TransitMode.regionalRail));
      expect(host.options.transitModes, contains(TransitMode.bus));
      expect(_summary('Regional only', 'unlimited changes'), findsOneWidget);
      expect(tester.widget<IconPick>(_pick('Regional only')).selected, isTrue);
      expect(tester.widget<IconPick>(_pick('Rail')).partial, isTrue);

      await tester.tap(_pick('Regional only'));
      await tester.pump();
      expect(host.options.transitModes, isEmpty);
      await _quiet(tester);
    });

    testWidgets('the transfer limit reads as a number, else infinity', (
      tester,
    ) async {
      final host = await _pumpSpine(tester);
      await _open(tester, 'PUBLIC TRANSPORT');
      expect(
        tester.widget<ValueChip>(_valueChip('Maximum changes')).valueIcon,
        LucideIcons.infinity,
      );

      await tester.tap(_valueChip('Maximum changes'));
      await tester.pumpAndSettle();

      final slider = tester.widget<OptionSlider>(find.byType(OptionSlider));
      expect(slider.max, RoutingOptions.unlimitedTransfersSliderValue);

      slider.onChanged(2);
      await tester.pump();
      expect(host.options.maxTransfers, 2);
      expect(_summary('All transport', 'max 2 changes'), findsOneWidget);

      slider.onChanged(RoutingOptions.unlimitedTransfersSliderValue.toDouble());
      await tester.pump();
      // Unlimited omits the parameter rather than sending a large number.
      expect(host.options.maxTransfers, isNull);
      expect(_summary('All transport', 'unlimited changes'), findsOneWidget);
      await _quiet(tester);
    });
  });

  group('opening', () {
    Finder visible(String text) => find.text(text).hitTestable();

    testWidgets('closing a stage forgets that it showed everything', (
      tester,
    ) async {
      await _pumpSpine(tester);
      await _open(tester, 'TO THE STATION');
      await tester.tap(visible('All options'));
      await tester.pumpAndSettle();
      expect(visible('Fewer options'), findsOneWidget);

      await _open(tester, 'TO THE STATION');
      await _open(tester, 'TO THE STATION');
      expect(visible('Fewer options'), findsNothing);
      expect(visible('All options'), findsOneWidget);
    });

    testWidgets('closing a stage closes a slider opened from its chip', (
      tester,
    ) async {
      await _pumpSpine(tester);
      await _open(tester, 'PUBLIC TRANSPORT');
      await tester.tap(_valueChip('Maximum changes'));
      await tester.pumpAndSettle();
      expect(find.byType(OptionSlider), findsOneWidget);

      await _open(tester, 'PUBLIC TRANSPORT');
      await _open(tester, 'PUBLIC TRANSPORT');
      expect(find.byType(OptionSlider), findsNothing);
    });

    testWidgets('closed by default', (tester) async {
      await _pumpSpine(tester);
      expect(visible('All options'), findsNothing);
    });

    testWidgets('stages open shows every stage\'s quick picks', (tester) async {
      await _pumpSpine(tester, opening: SearchOptionsOpening.stagesOpen);
      await tester.pumpAndSettle();
      expect(visible('All options'), findsNWidgets(3));
      expect(visible('Fewer options'), findsNothing);
    });

    testWidgets('everything open shows every option, still closable', (
      tester,
    ) async {
      await _pumpSpine(tester, opening: SearchOptionsOpening.everything);
      await tester.pumpAndSettle();
      expect(visible('Fewer options'), findsNWidgets(3));

      await tester.tap(visible('Fewer options').first);
      await tester.pumpAndSettle();
      expect(visible('Fewer options'), findsNWidgets(2));

      await _open(tester, 'PUBLIC TRANSPORT');
      expect(visible('Fewer options'), findsNWidgets(1));
    });

    testWidgets('a stage reopened under "everything" shows everything again', (
      tester,
    ) async {
      await _pumpSpine(tester, opening: SearchOptionsOpening.everything);
      await tester.pumpAndSettle();
      await tester.tap(visible('Fewer options').first);
      await tester.pumpAndSettle();

      await _open(tester, 'TO THE STATION');
      await _open(tester, 'TO THE STATION');
      expect(visible('Fewer options'), findsNWidgets(3));
    });

    testWidgets('a setting read late still applies until the rider acts', (
      tester,
    ) async {
      final host = await _pumpSpine(tester);
      host.setOpening(SearchOptionsOpening.stagesOpen);
      await tester.pumpAndSettle();
      expect(visible('All options'), findsNWidgets(3));

      await _open(tester, 'TO THE STATION');
      host.setOpening(SearchOptionsOpening.closed);
      await tester.pumpAndSettle();
      // Taken as the rider's own arrangement: left alone.
      expect(visible('All options'), findsNWidgets(2));
    });
  });

  group('bike carriage', () {
    testWidgets('is always offered, and comes on with a bike at both ends', (
      tester,
    ) async {
      final host = await _pumpSpine(tester);
      await _open(tester, 'PUBLIC TRANSPORT');
      // Offered from the start, so asking for a service that carries bikes is
      // possible whatever the street legs say.
      expect(tester.widget<IconPick>(_pick('Bike on board')).selected, false);

      await _open(tester, 'TO THE STATION');
      await tester.tap(_pick('Own bike'));
      await tester.pumpAndSettle();
      // One end is not enough: the bike is being left at the station.
      expect(tester.widget<IconPick>(_pick('Bike on board')).selected, false);

      await _open(tester, 'FROM THE STATION');
      await tester.tap(_pick('Own bike').last);
      await tester.pumpAndSettle();

      expect(tester.widget<IconPick>(_pick('Bike on board')).selected, true);
      expect(host.options.requireBikeTransport, isTrue);
      expect(host.options.bikeCarriageIsManual, isFalse);
      await _quiet(tester);
    });

    testWidgets('can be asked for without a bike at both ends', (tester) async {
      final host = await _pumpSpine(tester);
      await _open(tester, 'PUBLIC TRANSPORT');

      await tester.tap(_pick('Bike on board'));
      await tester.pump();

      expect(host.options.bikeAtBothEnds, isFalse);
      expect(host.options.requireBikeTransport, isTrue);
      await _quiet(tester);
    });

    testWidgets('stays the rider\'s to turn off', (tester) async {
      final host = await _pumpSpine(
        tester,
        initial: RoutingOptions.defaults.copyWith(
          firstMileModes: const [TransitMode.bike],
          lastMileModes: const [TransitMode.bike],
        ),
      );
      await _open(tester, 'PUBLIC TRANSPORT');

      await tester.tap(_pick('Bike on board'));
      await tester.pump();

      expect(host.options.requireBikeTransport, isFalse);
      expect(host.options.bikeCarriageIsManual, isTrue);
      expect(find.text('Bike not carried'), findsOneWidget);
      await _quiet(tester);
    });
  });

  group('traveller', () {
    testWidgets('step-free keeps its name and says what it did', (
      tester,
    ) async {
      final host = await _pumpSpine(tester);

      expect(find.text('Step-free'), findsOneWidget);
      await tester.tap(find.text('Step-free'));
      await tester.pump();

      expect(host.options.wheelchairAccessibleOnly, isTrue);
      expect(find.text('Step-free only'), findsOneWidget);
      await _quiet(tester);
    });

    testWidgets('pace hides its sliders until asked, cycling until it cycles', (
      tester,
    ) async {
      await _pumpSpine(tester);
      expect(find.text('Walking'), findsNothing);

      await tester.tap(_pick('Pace'));
      await tester.pumpAndSettle();

      expect(find.text('Walking'), findsOneWidget);
      // Nothing in the journey cycles yet, so no cycling speed applies.
      expect(find.text('Cycling'), findsNothing);

      await _open(tester, 'TO THE STATION');
      await tester.tap(_pick('Own bike'));
      await tester.pumpAndSettle();

      expect(find.text('Cycling'), findsOneWidget);
      await _quiet(tester);
    });
  });

  testWidgets('the via picker is left to the screen that owns the search', (
    tester,
  ) async {
    final host = await _pumpSpine(tester);
    await _open(tester, 'PUBLIC TRANSPORT');
    // An action, not a switch: only in the full view.
    expect(find.text('TRAVEL THROUGH A STOP'), findsNothing);

    await tester.tap(find.text('All options').hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('TRAVEL THROUGH A STOP'));
    await tester.pump();

    expect(host.viaTaps, 1);
  });

  testWidgets('a tooltip does not outlive the layout it pointed at', (
    tester,
  ) async {
    await _pumpSpine(tester);
    await _open(tester, 'TO THE STATION');

    // Held rather than tester.longPress, which lifts the finger and so
    // dismisses the tooltip on its way out.
    final held = await tester.startGesture(
      tester.getCenter(_pick('Shared bikes & scooters')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    // The picks carry no text of their own, so this is the bubble.
    expect(find.text('Shared bikes & scooters'), findsOneWidget);

    // Picking a mode moves the row out from under the finger, so no exit
    // gesture ever fires and the bubble would otherwise strand itself.
    await tester.tap(_pick('Own bike'));
    await tester.pump();
    expect(find.text('Shared bikes & scooters'), findsNothing);

    await held.up();
    await _quiet(tester);
  });

  test('every mode the dropdown offers has a name', () {
    for (final mode in TransitModeGroup.allSelectable) {
      expect(TransitModeGroup.modeLabel(mode), isNotEmpty);
    }
  });

  group('the stages read as one line', () {
    testWidgets('every stage puts its node on the same centre', (tester) async {
      // The rings and the two endpoint markers share one gutter, which is what
      // makes the card the top and bottom of a single drawing.
      await _pumpSpine(tester);

      final centres = {
        for (final node in find.byType(SpineNode).evaluate())
          tester.getRect(find.byWidget(node.widget)).center.dx.roundToDouble(),
      };
      expect(centres, hasLength(1));
    });

    testWidgets('the three stages leave no gap for the line to fall down', (
      tester,
    ) async {
      // Each row paints its own stretch, so a gap between rows is a gap in the
      // line. The rows have to touch.
      await _pumpSpine(tester);

      final rects = find
          .byType(JourneySegment)
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)))
          .toList();

      expect(rects, hasLength(3));
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].top, closeTo(rects[i - 1].bottom, 0.5));
      }
    });

    testWidgets('a street stage is dotted and a ride is not', (tester) async {
      await _pumpSpine(tester);

      final stages = find
          .byType(JourneySegment)
          .evaluate()
          .map((e) => e.widget as JourneySegment)
          .toList();

      expect(stages[0].dashed, isTrue);
      expect(stages[1].dashed, isFalse);
      expect(stages[2].dashed, isTrue);
    });

    testWidgets('a ring is wide enough to hold its glyph', (tester) async {
      await _pumpSpine(tester);

      final ring = tester.getRect(find.byType(SpineNode).first);
      expect(ring.width, JourneyMetrics.ring);
      expect(ring.height, JourneyMetrics.ring);
    });
  });

  group('a stage answers to the whole row', () {
    testWidgets('a tap well clear of the title still opens it', (tester) async {
      // The hit area used to be the width of the two lines of text, so most
      // of a row looked pressable and did nothing.
      await _pumpSpine(tester);
      expect(_pick('Own bike'), findsNothing);

      final row = tester.getRect(find.byType(JourneySegment).first);
      // Right-hand end of the row, past where any of the text reaches.
      await tester.tapAt(Offset(row.right - 30, row.top + 12));
      await tester.pumpAndSettle();

      expect(_pick('Own bike'), findsOneWidget);
    });

    testWidgets('the ring opens it too', (tester) async {
      await _pumpSpine(tester);
      await tester.tap(find.byType(SpineNode).first);
      await tester.pumpAndSettle();

      expect(_pick('Own bike'), findsOneWidget);
    });

    testWidgets('a miss inside the controls does not fold it away', (
      tester,
    ) async {
      await _pumpSpine(tester);
      await tester.tap(find.byType(SpineNode).first);
      await tester.pumpAndSettle();
      expect(_pick('Own bike'), findsOneWidget);

      // Just under the row of icon controls: inside the expanded area, on no
      // control in particular.
      final walk = tester.getRect(_pick('Walk'));
      await tester.tapAt(Offset(walk.right + 4, walk.center.dy));
      await tester.pumpAndSettle();

      expect(_pick('Own bike'), findsOneWidget);
    });
  });

  group('the card has one text edge', () {
    testWidgets('the traveller controls start where a stage summary does', (
      tester,
    ) async {
      // Three edges before this: the strip at the card's own left, the fields
      // at the gutter, the stages a gap further in.
      await _pumpSpine(tester);

      // The strip's own leading edge, not its chip's label, which sits
      // inside that chip's icon and padding.
      final strip = tester.getRect(find.byType(TravellerStrip));
      final summary = tester.getRect(_summary('Walk', '15 min').first);
      expect(strip.left, closeTo(summary.left, 0.5));
    });

    testWidgets('the line runs unbroken past the traveller strip', (
      tester,
    ) async {
      // The dotted rail from the origin used to stop short of the first
      // stage's ring by the height of this strip.
      await _pumpSpine(tester);

      final rows =
          find
              .byType(SpineRow)
              .evaluate()
              .map((e) => tester.getRect(find.byWidget(e.widget)))
              .toList()
            ..sort((a, b) => a.top.compareTo(b.top));

      expect(rows.length, greaterThanOrEqualTo(4));
      for (var i = 1; i < rows.length; i++) {
        expect(rows[i].top, closeTo(rows[i - 1].bottom, 0.5));
      }
    });
  });

  group('only my sharing providers', () {
    final renting = RoutingOptions.defaults.copyWith(
      firstMileModes: const [TransitMode.walk, TransitMode.rental],
      firstMileRentalFormFactors: const [RentalFormFactor.bicycle],
    );
    Finder row() => find.text('Only my sharing providers').hitTestable();

    Future<void> openAll(WidgetTester tester, String stage) async {
      await _open(tester, stage);
      await tester.tap(find.text('All options').hitTestable());
      await tester.pumpAndSettle();
    }

    testWidgets('shows under the line on a leg that rents, only there', (
      tester,
    ) async {
      await _pumpSpine(tester, initial: renting);
      expect(row(), findsNothing);

      await openAll(tester, 'TO THE STATION');
      expect(row(), findsOneWidget);
      // Below the sections, above the budget.
      final line = tester.getTopLeft(row()).dy;
      expect(line, greaterThan(tester.getTopLeft(find.text('OTHER')).dy));
      expect(line, lessThan(tester.getTopLeft(find.text('TIME BUDGET')).dy));

      await _open(tester, 'TO THE STATION');
      await openAll(tester, 'FROM THE STATION');
      expect(row(), findsNothing);
    });

    testWidgets('lists the providers, or says there are none yet', (
      tester,
    ) async {
      await _pumpSpine(
        tester,
        initial: renting,
        providerNames: const ['Dott', 'VOI'],
      );
      await openAll(tester, 'TO THE STATION');
      expect(find.text('Dott, VOI').hitTestable(), findsOneWidget);
    });

    testWidgets('with no providers set, says so and stays off', (tester) async {
      final host = await _pumpSpine(tester, initial: renting);
      await openAll(tester, 'TO THE STATION');
      expect(find.text('None set yet').hitTestable(), findsOneWidget);

      await tester.tap(row());
      await tester.pump();

      expect(host.limitToMyProviders, isFalse);
      expect(
        find.text('No providers set. Add yours in Search and routing options'),
        findsOneWidget,
      );
      await _quiet(tester);
    });

    testWidgets('with providers set, turns on and off', (tester) async {
      final host = await _pumpSpine(
        tester,
        initial: renting,
        providerNames: const ['Dott', 'VOI'],
      );
      await openAll(tester, 'TO THE STATION');

      await tester.tap(row());
      await tester.pump();
      expect(host.limitToMyProviders, isTrue);
      expect(find.text('Only your providers'), findsOneWidget);

      await tester.tap(row());
      await tester.pump();
      expect(host.limitToMyProviders, isFalse);
      await _quiet(tester);
    });

    testWidgets('switching a section leaves it as it is', (tester) async {
      // It says which providers, not which vehicles, so a section has no
      // business turning it on or off.
      final host = await _pumpSpine(
        tester,
        initial: renting,
        providerNames: const ['Dott', 'VOI'],
      );
      await openAll(tester, 'TO THE STATION');
      await tester.tap(row());
      await tester.pump();

      await tester.tap(find.text('SHARED CARS & MOPEDS'));
      await tester.pump();
      expect(
        host.options.firstMileRentalFormFactors,
        contains(RentalFormFactor.car),
      );
      expect(host.limitToMyProviders, isTrue);
      await _quiet(tester);
    });

    testWidgets('does not count as changing the search', (tester) async {
      final host = await _pumpSpine(
        tester,
        initial: renting,
        providerNames: const ['Dott', 'VOI'],
      );
      await openAll(tester, 'TO THE STATION');

      await tester.tap(row());
      await tester.pump();

      expect(host.options, renting);
      await _quiet(tester);
    });
  });

  group('from the station can follow the way there', () {
    Finder link() => find.byIcon(LucideIcons.link2).hitTestable();
    Finder visible(String text) => find.text(text).hitTestable();

    Future<void> tapLink(WidgetTester tester) async {
      await tester.tap(link());
      await tester.pumpAndSettle();
    }

    testWidgets('only the way from the station offers it', (tester) async {
      await _pumpSpine(tester);
      expect(link(), findsOneWidget);
      final row = tester.getRect(find.text('FROM THE STATION'));
      expect(tester.getCenter(link()).dy, closeTo(row.center.dy, 1));
    });

    testWidgets('linked, it says so and cannot be opened', (tester) async {
      final host = await _pumpSpine(tester);
      await tapLink(tester);
      expect(host.options.lastMileSameAsFirst, isTrue);
      expect(visible('Same as to the station'), findsOneWidget);
      expect(find.text('From the station: same as to the station'), findsOne);

      await tester.tap(find.text('FROM THE STATION'));
      await tester.pumpAndSettle();
      expect(visible('All options'), findsNothing);
      await _quiet(tester);
    });

    testWidgets('linked, it follows what the way there uses', (tester) async {
      final host = await _pumpSpine(tester);
      await tapLink(tester);
      await _open(tester, 'TO THE STATION');
      await tester.tap(_pick('Own bike'));
      await tester.pumpAndSettle();

      expect(host.options.lastMileModesInUse, contains(TransitMode.bike));
      expect(visible('Same as to the station'), findsOneWidget);
      // Its ring shows how the rider will travel.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SpineNode && w.appIcon == const GlyphIcon(LucideIcons.bike),
        ),
        findsNWidgets(2),
      );
      await _quiet(tester);
    });

    testWidgets('linking an open stage closes it', (tester) async {
      await _pumpSpine(tester);
      await _open(tester, 'FROM THE STATION');
      expect(visible('All options'), findsOneWidget);

      await tapLink(tester);
      expect(visible('All options'), findsNothing);
      await _quiet(tester);
    });

    testWidgets('unlinking opens it, starting from the way there', (
      tester,
    ) async {
      final host = await _pumpSpine(
        tester,
        initial: RoutingOptions.defaults.copyWith(
          firstMileModes: const [TransitMode.walk, TransitMode.bike],
          lastMileSameAsFirst: true,
        ),
      );
      await tapLink(tester);

      expect(host.options.lastMileSameAsFirst, isFalse);
      expect(host.options.lastMileModes, host.options.firstMileModes);
      expect(visible('All options'), findsOneWidget);
      expect(_summary('Walk, own bike', '15 min'), findsNWidgets(2));
      expect(find.text('From the station: set separately'), findsOne);
      await _quiet(tester);
    });

    testWidgets('stays closed when the card opens everything', (tester) async {
      await _pumpSpine(
        tester,
        initial: RoutingOptions.defaults.copyWith(lastMileSameAsFirst: true),
        opening: SearchOptionsOpening.stagesOpen,
      );
      await tester.pumpAndSettle();
      expect(visible('All options'), findsNWidgets(2));
    });

    testWidgets('the link is a finger wide, not a glyph wide', (tester) async {
      final host = await _pumpSpine(tester);
      final centre = tester.getCenter(link());
      await tester.tapAt(centre + const Offset(0, 16));
      await tester.pumpAndSettle();
      expect(host.options.lastMileSameAsFirst, isTrue);
      await _quiet(tester);
    });

    testWidgets('a long summary wraps instead of being cut short', (
      tester,
    ) async {
      await _pumpSpine(
        tester,
        initial: RoutingOptions.defaults.copyWith(
          lastMileModes: const [
            TransitMode.walk,
            TransitMode.bike,
            TransitMode.car,
            TransitMode.flex,
          ],
          maxLastMileTime: const Duration(minutes: 90),
        ),
      );
      final text = tester.widget<Text>(
        _summary('Walk, own bike, own car, other', '1 h 30'),
      );
      expect(text.maxLines, 2);
    });
  });
}
