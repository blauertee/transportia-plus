import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/navigation/routes.dart';

/// Half of the slide: long enough to have started, short of the end.
const Duration _kMidSlide = Duration(milliseconds: 150);

class _Screen extends StatelessWidget {
  const _Screen(this.name, {this.child});

  final String name;
  final Widget? child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFFFFFFF),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [Text(name), ?child],
      ),
    ),
  );
}

Future<NavigatorState> _pumpHome(WidgetTester tester) async {
  await tester.pumpWidget(const CupertinoApp(home: _Screen('Home')));
  return tester.state<NavigatorState>(find.byType(Navigator));
}

double _left(WidgetTester tester, String name) =>
    tester.getTopLeft(find.text(name)).dx;

void main() {
  testWidgets('a screen slides in over one that stays where it is', (
    tester,
  ) async {
    final navigator = await _pumpHome(tester);
    final homeLeft = _left(tester, 'Home');

    navigator.openScreen<void>(const _Screen('Next'));
    await tester.pump();
    await tester.pump(_kMidSlide);

    expect(_left(tester, 'Home'), homeLeft, reason: 'underneath, unmoved');
    expect(_left(tester, 'Next'), greaterThan(homeLeft), reason: 'on its way');

    await tester.pumpAndSettle();
    expect(_left(tester, 'Next'), homeLeft);
  });

  testWidgets('back slides the screen out the way it came', (tester) async {
    final navigator = await _pumpHome(tester);
    navigator.openScreen<void>(const _Screen('Next'));
    await tester.pumpAndSettle();
    final restingLeft = _left(tester, 'Next');

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump(_kMidSlide);

    expect(find.text('Next'), findsOneWidget, reason: 'still sliding');
    expect(_left(tester, 'Next'), greaterThan(restingLeft));

    await tester.pumpAndSettle();
    expect(find.text('Next'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('a screen is clipped to its own bounds while it moves', (
    tester,
  ) async {
    final navigator = await _pumpHome(tester);
    navigator.openScreen<void>(const _Screen('Next'));
    await tester.pump();
    await tester.pump(_kMidSlide);

    // Inside the slide, so what hangs off the screen's edge moves with the
    // clip instead of being drawn over the screen underneath.
    final clipsInsideSlide = find
        .descendant(
          of: find.byType(SlideTransition),
          matching: find.byType(ClipRect),
        )
        .evaluate()
        .toSet();
    final clipsAroundScreen = find
        .ancestor(of: find.text('Next'), matching: find.byType(ClipRect))
        .evaluate()
        .toSet();
    expect(clipsInsideSlide.intersection(clipsAroundScreen), isNotEmpty);
  });

  testWidgets('leaving a screen puts its keyboard away', (tester) async {
    final navigator = await _pumpHome(tester);
    navigator.openScreen<void>(
      const _Screen(
        'Search',
        child: SizedBox(width: 200, child: CupertinoTextField(autofocus: true)),
      ),
    );
    await tester.pumpAndSettle();
    final field = tester.state<EditableTextState>(find.byType(EditableText));
    expect(field.widget.focusNode.hasFocus, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(field.widget.focusNode.hasFocus, isFalse);
  });

  testWidgets('replacing a screen leaves nothing of it to go back to', (
    tester,
  ) async {
    final navigator = await _pumpHome(tester);
    navigator.openScreen<void>(const _Screen('Loading'));
    await tester.pumpAndSettle();

    navigator.replaceScreen<void>(const _Screen('Trip'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Loading'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('a screen opened from a sheet goes back to the sheet', (
    tester,
  ) async {
    final navigator = await _pumpHome(tester);
    navigator.openSheet<void>(
      label: 'Stop departures',
      builder: (sheetContext) => Center(
        child: CupertinoButton(
          onPressed: () =>
              sheetContext.openScreen<void>(const _Screen('Connection')),
          child: const Text('Departure'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Departure'));
    await tester.pumpAndSettle();
    expect(find.text('Connection'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('Connection'), findsNothing);
    expect(find.text('Departure'), findsOneWidget);
  });

  testWidgets('a sheet hands back what was picked in it', (tester) async {
    final navigator = await _pumpHome(tester);
    final picked = navigator.openSheet<String>(
      label: 'Calendar',
      builder: (sheetContext) => Center(
        child: CupertinoButton(
          onPressed: () => Navigator.of(sheetContext).pop('Trips'),
          child: const Text('Trips'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trips'));
    await tester.pumpAndSettle();

    expect(await picked, 'Trips');
  });

  testWidgets('a tap outside a dismissible sheet closes it', (tester) async {
    final navigator = await _pumpHome(tester);
    navigator.openSheet<void>(
      label: 'Share',
      builder: (_) =>
          const Align(alignment: Alignment.bottomCenter, child: Text('Sheet')),
    );
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Sheet'), findsNothing);
  });
}
