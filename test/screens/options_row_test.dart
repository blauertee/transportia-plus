import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:transportia/screens/search_options/search_options_rows.dart';

Future<List<String>> _pump(WidgetTester tester, {Widget? below}) async {
  final taps = <String>[];
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 360,
          child: OptionsRow(
            icon: LucideIcons.layoutGrid,
            label: 'Quick access icons',
            description: 'Which modes each icon on the routing card switches.',
            below: below,
            onTap: () => taps.add('row'),
          ),
        ),
      ),
    ),
  );
  return taps;
}

void main() {
  testWidgets('the label, the description and the space around are one '
      'target', (tester) async {
    final taps = await _pump(tester);
    await tester.tap(find.text('Quick access icons'));
    await tester.tap(find.textContaining('Which modes'));
    final row = tester.getRect(find.byType(OptionsRow));
    // Above the label, in the row's own padding.
    await tester.tapAt(Offset(row.center.dx, row.top + 3));
    expect(taps, ['row', 'row', 'row']);
  });

  testWidgets('what sits below keeps its own taps', (tester) async {
    final belowTaps = <String>[];
    final taps = await _pump(
      tester,
      below: GestureDetector(
        onTap: () => belowTaps.add('below'),
        child: const SizedBox(height: 40, child: Text('control')),
      ),
    );
    await tester.tap(find.text('control'));
    expect(belowTaps, ['below']);
    expect(taps, isEmpty);
  });
}
