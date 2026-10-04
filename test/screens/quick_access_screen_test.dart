import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/quick_access_layout.dart';
import 'package:transportia/models/street_leg_choice.dart';
import 'package:transportia/models/transitous/enums.dart';
import 'package:transportia/screens/quick_access_screen.dart';
import 'package:transportia/services/quick_access_service.dart';

import '../support/app_shell.dart';

QuickAccessLayout get _layout => QuickAccessService.layoutListenable.value;

QuickGroup<StreetItem> _street(String id) =>
    _layout.streetSections.firstWhere((s) => s.id == id);

Future<void> _pump(WidgetTester tester) async {
  QuickAccessService.invalidate();
  // Tall enough that every section is on screen without scrolling.
  await pumpInAppShell(
    tester,
    const QuickAccessScreen(),
    size: const Size(400, 2000),
  );
}

/// Holds [label] long enough to lift it, then drops it on [onto].
Future<void> _drag(WidgetTester tester, Finder label, Finder onto) async {
  final gesture = await tester.startGesture(tester.getCenter(label));
  await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  await gesture.moveTo(tester.getCenter(onto));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists both halves, each section with its modes', (tester) async {
    await _pump(tester);
    expect(find.text('Public transport'), findsOneWidget);
    expect(find.text('To and from the station'), findsOneWidget);
    expect(find.text('SHARED CARS & MOPEDS'), findsOneWidget);
    expect(find.text('Moped'), findsOneWidget);
    expect(find.text('OTHER'), findsNWidgets(2));
  });

  testWidgets('every section but Other can be edited', (tester) async {
    await _pump(tester);
    expect(find.bySemanticsLabel('Edit Walk'), findsOneWidget);
    expect(find.bySemanticsLabel('Edit Rail'), findsOneWidget);
    expect(find.bySemanticsLabel('Edit Other'), findsNothing);
  });

  testWidgets('a mode dragged onto another section moves there', (
    tester,
  ) async {
    await _pump(tester);
    await _drag(
      tester,
      find.text('Seated scooter'),
      find.text('SHARED CARS & MOPEDS'),
    );
    expect(
      _street('shared-car').items,
      contains(const SharedVehicle(RentalFormFactor.scooterSeated)),
    );
    expect(
      _street('shared-light').items,
      isNot(contains(const SharedVehicle(RentalFormFactor.scooterSeated))),
    );
  });

  testWidgets('a mode stays in its own half', (tester) async {
    await _pump(tester);
    final before = _layout.toJson();
    await _drag(tester, find.text('Ferry'), find.text('WALK'));
    expect(_layout.toJson(), before);
  });

  testWidgets('an emptied section waits for modes to be dropped back', (
    tester,
  ) async {
    await _pump(tester);
    await _drag(tester, find.text('Shared car'), find.text('OWN CAR'));
    await _drag(tester, find.text('Moped'), find.text('OWN CAR'));
    expect(_street('shared-car').items, isEmpty);
    expect(find.text('Drop modes here'), findsOneWidget);
  });

  testWidgets('the pencil renames a section', (tester) async {
    await _pump(tester);
    await tester.tap(find.bySemanticsLabel('Edit Walk'));
    await tester.pumpAndSettle();
    expect(find.text('Edit section'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), 'On foot');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(_street('walk').title, 'On foot');
    expect(find.text('ON FOOT'), findsOneWidget);
  });

  testWidgets('reset brings the default sections back', (tester) async {
    await _pump(tester);
    await _drag(tester, find.text('Moped'), find.text('OWN CAR'));
    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();
    expect(_layout.toJson(), QuickAccessLayout.defaults.toJson());
  });

  group('without dragging', () {
    testWidgets('a tap offers every other section of its half', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('Moped'));
      await tester.pumpAndSettle();

      expect(find.text('Move “Moped” to'), findsOneWidget);
      // The sheet's own entries, not the headings behind it.
      final sheet = find.byType(CupertinoActionSheet);
      Finder entry(String title) =>
          find.descendant(of: sheet, matching: find.text(title));
      expect(entry('Own car'), findsOneWidget);
      expect(entry('Other'), findsOneWidget);
      expect(entry('Shared cars & mopeds'), findsNothing);
      expect(entry('Rail'), findsNothing);

      await tester.tap(entry('Own car'));
      await tester.pumpAndSettle();
      expect(
        _street('own-car').items,
        contains(const SharedVehicle(RentalFormFactor.moped)),
      );
    });

    testWidgets('cancelling moves nothing', (tester) async {
      await _pump(tester);
      final before = _layout.toJson();
      await tester.tap(find.text('Moped'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(_layout.toJson(), before);
    });

    testWidgets('a screen reader can move a mode by its actions', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester);

      final node = tester.getSemantics(
        find.bySemanticsLabel('Moped, in Shared cars & mopeds'),
      );
      final actions = [
        for (final id in node.getSemanticsData().customSemanticsActionIds!)
          CustomSemanticsAction.getAction(id)!.label,
      ];
      expect(actions, contains('Move to Own car'));
      expect(actions, contains('Move to Other'));
      expect(actions, isNot(contains('Move to Shared cars & mopeds')));

      tester.semantics.customAction(
        find.semantics.byLabel('Moped, in Shared cars & mopeds'),
        const CustomSemanticsAction(label: 'Move to Own car'),
      );
      await tester.pumpAndSettle();
      expect(
        _street('own-car').items,
        contains(const SharedVehicle(RentalFormFactor.moped)),
      );
      semantics.dispose();
    });
  });
}
