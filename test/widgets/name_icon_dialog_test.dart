import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/widgets/icon_picker.dart';
import 'package:transportia/widgets/name_icon_dialog.dart';

import '../support/app_shell.dart';

Finder _tile(String name) =>
    find.byWidgetPredicate((w) => w is IconTile && w.semanticLabel == name);

Future<List<(String, String)>> _pump(
  WidgetTester tester, {
  String iconName = 'lucide:car',
  VoidCallback? onDeleted,
}) async {
  final saved = <(String, String)>[];
  await pumpInAppShell(
    tester,
    NameIconDialog(
      title: 'Edit section',
      name: 'Shared car',
      iconName: iconName,
      suggestions: const ['lucide:car', 'lucide:key-round'],
      pickerTitle: 'Section icon',
      onSaved: (name, icon) => saved.add((name, icon)),
      deleteLabel: onDeleted == null ? null : 'Remove favourite',
      onDeleted: onDeleted,
    ),
  );
  return saved;
}

void main() {
  testWidgets('offers the suggestions, the current icon picked', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Edit section'), findsOneWidget);
    expect(tester.widget<IconTile>(_tile('lucide:car')).selected, isTrue);
    expect(tester.widget<IconTile>(_tile('lucide:key-round')).selected, false);
  });

  testWidgets('shows the current icon even when it is no suggestion', (
    tester,
  ) async {
    // An old favourite's name, shown under the name it will be saved as.
    await _pump(tester, iconName: 'home');
    expect(tester.widget<IconTile>(_tile('lucide:house')).selected, isTrue);
  });

  testWidgets('saves the trimmed name and the icon picked', (tester) async {
    final saved = await _pump(tester);
    await tester.enterText(find.byType(EditableText), '  Car share  ');
    await tester.tap(_tile('lucide:key-round'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved, [('Car share', 'lucide:key-round')]);
  });

  testWidgets('the magnifier opens the full picker, and its pick sticks', (
    tester,
  ) async {
    final saved = await _pump(tester);
    await tester.tap(find.bySemanticsLabel('More icons'));
    await tester.pumpAndSettle();
    expect(find.text('Section icon'), findsOneWidget);

    await tester.enterText(find.byType(EditableText).last, 'truck');
    await tester.pump();
    await tester.tap(_tile('lucide:truck').first);
    await tester.tap(find.text('Use icon'));
    await tester.pumpAndSettle();

    expect(tester.widget<IconTile>(_tile('lucide:truck')).selected, isTrue);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(saved.single.$2, 'lucide:truck');
  });

  testWidgets('offers no removal unless asked to', (tester) async {
    await _pump(tester);
    expect(find.text('Remove favourite'), findsNothing);
  });

  testWidgets('removes when asked to offer it', (tester) async {
    var removed = 0;
    await _pump(tester, onDeleted: () => removed++);
    await tester.tap(find.text('Remove favourite'));
    await tester.pumpAndSettle();
    expect(removed, 1);
  });
}
