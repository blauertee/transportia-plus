import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/providers/backend_provider.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/location_settings_screen.dart';
import 'package:transportia/widgets/app_toggle_switch.dart';

Future<ThemeProvider> _pump(WidgetTester tester) async {
  // Wide: the test font's square glyphs overflow the Location screen's
  // "Open settings | Refresh status" row at phone width.
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final theme = ThemeProvider();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<BackendProvider>(
          create: (_) => BackendProvider(),
        ),
      ],
      child: const CupertinoApp(home: LocationSettingsScreen()),
    ),
  );
  // Location status comes from plugins a test does not have; the screen
  // shows its settings once asking has failed, which takes real time.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
  return theme;
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('Location offers departures near you, on to begin with', (
    tester,
  ) async {
    final theme = await _pump(tester);

    expect(find.text('Departures near you'), findsOne);
    expect(find.textContaining('sends your position'), findsWidgets);
    expect(theme.showNearbyDepartures, isTrue);
  });

  testWidgets('turning it off there sticks and says so', (tester) async {
    final theme = await _pump(tester);

    final toggle = find.descendant(
      of: find.ancestor(
        of: find.text('Departures near you'),
        matching: find.byType(Row),
      ),
      matching: find.byType(AppToggleSwitch),
    );
    await tester.ensureVisible(toggle.first);
    await tester.tap(toggle.first);
    await tester.pumpAndSettle();

    expect(theme.showNearbyDepartures, isFalse);
    expect(
      await SharedPreferencesAsync().getBool('show_nearby_departures'),
      isFalse,
    );
    expect(
      find.text('Your location is not sent when you open Timetables'),
      findsOne,
    );
  });
}
