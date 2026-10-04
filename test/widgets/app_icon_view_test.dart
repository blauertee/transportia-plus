import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:transportia/utils/app_icons.dart';
import 'package:transportia/widgets/app_icon_view.dart';

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
  Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: IconTheme(
        data: const IconThemeData(size: 20, color: Color(0xFF123456)),
        child: child,
      ),
    ),
  ),
);

void main() {
  testWidgets('a glyph takes the size and colour around it', (tester) async {
    await _pump(tester, const AppIconView(GlyphIcon(LucideIcons.car)));
    final icon = tester.widget<Icon>(find.byType(Icon));
    expect(icon.size, 20);
    expect(icon.color, const Color(0xFF123456));
  });

  testWidgets('a badged icon keeps the box of a single glyph', (tester) async {
    await _pump(tester, const AppIconView(AppIcons.carKey));
    expect(tester.getSize(find.byType(AppIconView)), const Size(20, 20));
    final icons = tester.widgetList<Icon>(find.byType(Icon)).toList();
    expect(icons.map((i) => i.icon), [
      LucideIcons.car,
      LucideIcons.keyRound600,
    ]);
    // The key is the smaller of the two, in the same colour.
    expect(icons.last.size, lessThan(icons.first.size!));
    expect(icons.last.color, icons.first.color);
  });

  testWidgets('an explicit size wins over the theme', (tester) async {
    await _pump(tester, const AppIconView(AppIcons.carKey, size: 30));
    expect(tester.getSize(find.byType(AppIconView)), const Size(30, 30));
  });
}
