import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:transportia/models/transit_mode_group.dart';
import 'package:transportia/widgets/app_toggle_switch.dart';
import 'package:transportia/widgets/options/icon_controls.dart';
import 'package:transportia/widgets/search/leg_panel.dart';

class _Taps {
  final List<String> log = [];
  VoidCallback tap(String what) =>
      () => log.add(what);

  /// What the panel handed its slider to call when the rider lets go.
  VoidCallback? sliderDone;
  int slidersBuilt = 0;
}

String _describe(LegView view) {
  if (view.isFull) return 'full';
  if (view.revealed case final title?) return 'reveal $title';
  return 'compact';
}

Future<_Taps> _pump(
  WidgetTester tester, {
  LegView view = LegView.compact,
  GroupState railState = GroupState.some,
  String? changes,
}) async {
  final taps = _Taps();
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 360,
            child: LegPanel(
              tooltips: OptionTooltipController(),
              view: view,
              onViewChanged: (next) => taps.log.add(_describe(next)),
              sections: [
                LegSection(
                  mark: const Icon(LucideIcons.trainFront),
                  title: 'Rail',
                  state: railState,
                  onToggle: taps.tap('rail'),
                  choices: [
                    LegChoice(
                      label: 'Regional rail',
                      selected: true,
                      onPressed: taps.tap('regional rail'),
                    ),
                  ],
                ),
              ],
              options: [
                LegOption.toggle(
                  mark: const RegionalGlyph(),
                  title: 'Regional only',
                  on: false,
                  onToggle: taps.tap('regional only'),
                ),
                LegOption.value(
                  icon: LucideIcons.waypoints,
                  title: 'Maximum changes',
                  value: changes,
                  slider: (onChangeEnd) {
                    taps
                      ..sliderDone = onChangeEnd
                      ..slidersBuilt += 1;
                    return const SizedBox(height: 10, key: Key('slider'));
                  },
                ),
                LegOption.toggle(
                  mark: const Icon(LucideIcons.mapPin),
                  title: 'Travel through a stop',
                  on: false,
                  onToggle: taps.tap('via'),
                  inCompactRow: false,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  return taps;
}

Finder _pick(String label) =>
    find.byWidgetPredicate((w) => w is IconPick && w.label == label);

void main() {
  group('compact', () {
    testWidgets('a section icon switches its section', (tester) async {
      final taps = await _pump(tester);
      await tester.tap(_pick('Rail'));
      expect(taps.log, ['rail']);
    });

    testWidgets('partly on is its own state, not half of on', (tester) async {
      await _pump(tester);
      final rail = tester.widget<IconPick>(_pick('Rail'));
      expect(rail.partial, isTrue);
      expect(rail.selected, isFalse);
    });

    testWidgets('an action is kept for the full view', (tester) async {
      await _pump(tester);
      expect(_pick('Travel through a stop'), findsNothing);
      expect(_pick('Regional only'), findsOneWidget);
    });

    testWidgets('no limit is the infinity sign, a limit its number', (
      tester,
    ) async {
      await _pump(tester);
      final chip = tester.widget<ValueChip>(find.byType(ValueChip));
      expect(chip.valueIcon, LucideIcons.infinity);

      await _pump(tester, changes: '2');
      final limited = tester.widget<ValueChip>(find.byType(ValueChip));
      expect(limited.value, '2');
      expect(limited.valueIcon, isNull);
    });

    testWidgets('a value chip opens its slider under the rows', (tester) async {
      final taps = await _pump(tester);
      expect(find.byKey(const Key('slider')), findsNothing);
      await tester.tap(find.byType(ValueChip));
      expect(taps.log, ['reveal Maximum changes']);
    });

    testWidgets('an opened slider sits in the compact view, chip marked', (
      tester,
    ) async {
      await _pump(tester, view: const LegView.revealing('Maximum changes'));
      expect(find.byKey(const Key('slider')), findsOneWidget);
      expect(_pick('Rail'), findsOneWidget);
      expect(tester.widget<ValueChip>(find.byType(ValueChip)).expanded, true);
    });

    testWidgets('letting go of the slider closes it', (tester) async {
      final taps = await _pump(
        tester,
        view: const LegView.revealing('Maximum changes'),
      );
      taps.sliderDone!();
      expect(taps.log, ['compact']);
    });

    testWidgets('tapping the chip again closes it', (tester) async {
      final taps = await _pump(
        tester,
        view: const LegView.revealing('Maximum changes'),
      );
      await tester.tap(find.byType(ValueChip));
      expect(taps.log, ['compact']);
    });

    testWidgets('an unknown revealed title opens nothing', (tester) async {
      final taps = await _pump(tester, view: const LegView.revealing('Gone'));
      expect(find.byKey(const Key('slider')), findsNothing);
      expect(taps.slidersBuilt, 0);
    });

    testWidgets('the link opens the full view', (tester) async {
      final taps = await _pump(tester);
      await tester.tap(find.text('All options'));
      expect(taps.log, ['full']);
    });
  });

  group('full', () {
    testWidgets('each section is a heading with its choices under it', (
      tester,
    ) async {
      final taps = await _pump(tester, view: LegView.full);
      expect(find.byType(IconPick), findsNothing);
      expect(find.text('RAIL'), findsOneWidget);

      await tester.tap(find.text('Regional rail'));
      expect(taps.log, ['regional rail']);
    });

    testWidgets('the whole heading switches its section', (tester) async {
      final taps = await _pump(tester, view: LegView.full);
      final row = tester.getRect(
        find.byWidgetPredicate((w) => w is LegHeading && w.title == 'Rail'),
      );
      await tester.tapAt(Offset(row.right - 10, row.center.dy));
      await tester.tapAt(Offset(row.left + 5, row.center.dy));
      expect(taps.log, ['rail', 'rail']);
    });

    testWidgets('choices and sliders start where the headings\' text does', (
      tester,
    ) async {
      await _pump(tester, view: LegView.full);
      final title = tester.getTopLeft(find.text('RAIL'));
      final choice = tester.getTopLeft(find.byType(Wrap));
      expect(choice.dx, title.dx);
    });

    testWidgets('every option is there, slider open and action included', (
      tester,
    ) async {
      final taps = await _pump(tester, view: LegView.full);
      expect(find.byKey(const Key('slider')), findsOneWidget);
      // Open for good here: letting go must not close anything.
      expect(taps.sliderDone, isNull);
      expect(find.byIcon(LucideIcons.infinity), findsOneWidget);

      await tester.tap(find.text('TRAVEL THROUGH A STOP'));
      await tester.tap(find.text('REGIONAL ONLY'));
      expect(taps.log, ['via', 'regional only']);
    });

    testWidgets('a value is not a switch: its heading does nothing', (
      tester,
    ) async {
      final taps = await _pump(tester, view: LegView.full);
      await tester.tap(find.text('MAXIMUM CHANGES'));
      expect(taps.log, isEmpty);
    });

    testWidgets('the link closes it again', (tester) async {
      final taps = await _pump(tester, view: LegView.full);
      await tester.tap(find.text('Fewer options'));
      expect(taps.log, ['compact']);
    });

    testWidgets('a letter mark is centred like the icons above it', (
      tester,
    ) async {
      await _pump(tester, view: LegView.full);
      final letter = tester.getCenter(find.text('R')).dx;
      final icon = tester.getCenter(find.byIcon(LucideIcons.trainFront)).dx;
      expect(letter, closeTo(icon, 0.5));
    });
  });

  group('full view only', () {
    Future<List<String>> pumpWith(WidgetTester tester, LegView view) async {
      final log = <String>[];
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(),
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 360,
                child: LegPanel(
                  tooltips: OptionTooltipController(),
                  view: view,
                  onViewChanged: (_) {},
                  sections: [
                    LegSection(
                      mark: const Icon(LucideIcons.footprints),
                      title: 'Walk',
                      state: GroupState.all,
                      onToggle: () => log.add('walk'),
                    ),
                    LegSection(
                      mark: const Icon(LucideIcons.shapes),
                      title: 'Other',
                      state: GroupState.none,
                      onToggle: () => log.add('other'),
                      inCompactRow: false,
                    ),
                  ],
                  options: [
                    LegOption.switchRow(
                      icon: LucideIcons.userCheck,
                      title: 'Only my sharing providers',
                      subtitle: 'Dott, VOI',
                      on: false,
                      onToggle: () => log.add('providers'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      return log;
    }

    testWidgets('a section can stay off the compact row', (tester) async {
      await pumpWith(tester, LegView.compact);
      expect(_pick('Walk'), findsOneWidget);
      expect(_pick('Other'), findsNothing);
    });

    testWidgets('but is still listed with everything else', (tester) async {
      final log = await pumpWith(tester, LegView.full);
      await tester.tap(find.text('OTHER'));
      expect(log, ['other']);
    });

    testWidgets('a switch row is a sentence, not a heading', (tester) async {
      await pumpWith(tester, LegView.compact);
      expect(find.text('Only my sharing providers'), findsNothing);

      final log = await pumpWith(tester, LegView.full);
      expect(find.text('Only my sharing providers'), findsOneWidget);
      expect(find.text('ONLY MY SHARING PROVIDERS'), findsNothing);
      expect(find.text('Dott, VOI'), findsOneWidget);

      // The whole row is the target, the switch included.
      await tester.tap(find.text('Dott, VOI'));
      await tester.tap(find.byType(AppToggleSwitch));
      expect(log, ['providers', 'providers']);
    });
  });
}
