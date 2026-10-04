import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/utils/app_icons.dart';
import 'package:transportia/widgets/icon_picker.dart';

import '../support/app_shell.dart';

/// Opens the picker from a page and records what it hands back.
class _Opener extends StatelessWidget {
  const _Opener(this.results, {this.suggestions = const []});

  final List<String?> results;
  final List<String> suggestions;

  @override
  Widget build(BuildContext context) => Center(
    child: GestureDetector(
      onTap: () async => results.add(
        await IconPickerScreen.open(
          context,
          title: 'Section icon',
          confirmLabel: 'Use icon',
          selected: 'lucide:car',
          suggestions: suggestions,
        ),
      ),
      child: const Text('open'),
    ),
  );
}

Finder _tile(String name) =>
    find.byWidgetPredicate((w) => w is IconTile && w.semanticLabel == name);

Future<List<String?>> _open(
  WidgetTester tester, {
  List<String> suggestions = const [],
}) async {
  final results = <String?>[];
  await pumpInAppShell(tester, _Opener(results, suggestions: suggestions));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return results;
}

void main() {
  testWidgets('is titled and labelled by whoever opens it', (tester) async {
    await _open(tester);
    expect(find.text('Section icon'), findsOneWidget);
    expect(find.text('Use icon'), findsOneWidget);
  });

  testWidgets('lists the suggestions first, the current one picked', (
    tester,
  ) async {
    await _open(tester, suggestions: [AppIcons.carKeyName, 'lucide:car']);
    expect(find.text('SUGGESTED'), findsOneWidget);
    expect(find.text('TRANSPORT'), findsOneWidget);
    final car = tester.widget<IconTile>(_tile('lucide:car').first);
    expect(car.selected, isTrue);
    expect(_tile(AppIcons.carKeyName), findsOneWidget);
  });

  testWidgets('hands back the icon picked', (tester) async {
    final results = await _open(tester);
    await tester.tap(_tile('lucide:bike').first);
    await tester.pump();
    await tester.tap(find.text('Use icon'));
    await tester.pumpAndSettle();
    expect(results, ['lucide:bike']);
  });

  testWidgets('hands back nothing when left without picking', (tester) async {
    final results = await _open(tester);
    await tester.tap(_tile('lucide:bike').first);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(results, [null]);
  });

  testWidgets('search narrows the list, and says when nothing matches', (
    tester,
  ) async {
    await _open(tester);
    await tester.enterText(find.byType(EditableText), 'lorry');
    await tester.pump();
    expect(find.textContaining('MATCH'), findsOneWidget);
    expect(_tile('lucide:truck'), findsOneWidget);
    expect(find.text('TRANSPORT'), findsNothing);

    await tester.enterText(find.byType(EditableText), 'qwxzv');
    await tester.pump();
    expect(find.text('NO ICONS MATCH “QWXZV”'), findsOneWidget);
  });
}
