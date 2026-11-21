import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:transportia/utils/custom_page_route.dart';
import 'package:transportia/widgets/app_screen.dart';
import 'package:transportia/widgets/custom_app_bar.dart';

/// Taller than the screen, so a page has somewhere to scroll.
const double _kLongBody = 2000;

Future<void> _pump(WidgetTester tester, Widget screen) =>
    tester.pumpWidget(CupertinoApp(home: screen));

AppScreen _page() => const AppScreen.page(
  icon: LucideIcons.palette,
  title: 'Appearance',
  subtitle: 'Look and feel',
  body: SizedBox(height: _kLongBody),
);

/// How visible the bar's own copy of the title is.
double _barTitleOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byType(CustomAppBar),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

/// Runs [body] as if on [platform], restoring the real one even on failure.
Future<void> _on(TargetPlatform platform, Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('a tab shows its title and subtitle and no way back', (
    tester,
  ) async {
    await _pump(
      tester,
      const AppScreen.tab(
        icon: LucideIcons.settings,
        title: 'Settings',
        subtitle: 'User Preferences & Information',
        body: SizedBox.shrink(),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('User Preferences & Information'), findsOneWidget);
    expect(find.byType(CustomAppBar), findsNothing);
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('a page has no back bar on ${platform.name}, which has its '
        'own way back', (tester) async {
      await _on(platform, () async {
        await _pump(tester, _page());

        expect(find.byType(CustomAppBar), findsNothing);
        expect(find.text('Appearance'), findsOneWidget);
      });
    });
  }

  for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
    testWidgets('a page keeps a back bar on ${platform.name}', (tester) async {
      await _on(platform, () async {
        await _pump(tester, _page());

        expect(find.byType(CustomAppBar), findsOneWidget);
        expect(find.text('Back'), findsOneWidget);
      });
    });
  }

  testWidgets('the bar takes the name only once the title has scrolled past '
      'the threshold', (tester) async {
    await _on(TargetPlatform.linux, () async {
      await _pump(tester, _page());
      final position = tester
          .state<ScrollableState>(find.byType(Scrollable))
          .position;

      expect(_barTitleOpacity(tester), 0);

      position.jumpTo(36);
      await tester.pumpAndSettle();
      expect(_barTitleOpacity(tester), 0, reason: 'at the threshold');

      position.jumpTo(37);
      await tester.pumpAndSettle();
      expect(_barTitleOpacity(tester), 1, reason: 'past the threshold');

      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(_barTitleOpacity(tester), 0, reason: 'back at the top');
    });
  });

  testWidgets('a fixed title stays while a body that scrolls itself scrolls', (
    tester,
  ) async {
    await _pump(
      tester,
      AppScreen.tab(
        icon: LucideIcons.bookmark,
        title: 'Saved trips',
        scrollable: false,
        body: ListView(children: const [SizedBox(height: _kLongBody)]),
      ),
    );

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(find.text('Saved trips'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Saved trips')).dy, greaterThan(0));
  });

  testWidgets('ScreenIcon draws the icon of the screen it is in', (
    tester,
  ) async {
    await _pump(
      tester,
      const AppScreen.tab(
        icon: LucideIcons.bookmark,
        title: 'Saved trips',
        body: ScreenIcon(),
      ),
    );

    expect(find.byIcon(LucideIcons.bookmark), findsOneWidget);
  });

  testWidgets('ScreenIcon draws nothing outside a screen', (tester) async {
    await _pump(tester, const Center(child: ScreenIcon()));

    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('a pushed page is swiped back from the left edge', (
    tester,
  ) async {
    await _pump(tester, const Text('Home'));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(CustomPageRoute<void>(child: _page()));
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsNothing);

    // Past half the width, where the gesture commits to going back.
    await tester.dragFrom(const Offset(5, 300), const Offset(600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Appearance'), findsNothing);
  });
}
