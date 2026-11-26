import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/providers/backend_provider.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/legal_screen.dart';
import 'package:transportia/screens/location_settings_screen.dart';
import 'package:transportia/screens/search_options/search_options_backend.dart';
import 'package:transportia/widgets/app_toggle_switch.dart';

Future<BackendProvider> _pump(WidgetTester tester, Widget screen) async {
  // Wide: the test font's square glyphs overflow the Location screen's
  // "Open settings | Refresh status" row at phone width.
  tester.view.physicalSize = const Size(900, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final backend = BackendProvider();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<BackendProvider>.value(value: backend),
      ],
      child: CupertinoApp(home: screen),
    ),
  );
  // Location status comes from plugins a test does not have; the screen
  // shows its settings once asking has failed, which takes real time.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle();
  return backend;
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('Location offers the OpenStreetMap lookup, on to begin with', (
    tester,
  ) async {
    final backend = await _pump(tester, const LocationSettingsScreen());

    expect(find.text('Details from OpenStreetMap'), findsOne);
    expect(
      find.text('Your location is never sent, only which place you tapped.'),
      findsOne,
    );
    expect(backend.placeDetailsEnabled, isTrue);
  });

  testWidgets('turning it off there sticks', (tester) async {
    final backend = await _pump(tester, const LocationSettingsScreen());

    final toggle = find.descendant(
      of: find.ancestor(
        of: find.text('Details from OpenStreetMap'),
        matching: find.byType(Row),
      ),
      matching: find.byType(AppToggleSwitch),
    );
    await tester.tap(toggle.first);
    await tester.pumpAndSettle();

    expect(backend.placeDetailsEnabled, isFalse);
    expect(
      await SharedPreferencesAsync().getBool('place_details_enabled'),
      isFalse,
    );
    expect(find.textContaining('Off: a tapped result'), findsOne);
  });

  testWidgets('another Nominatim server can be set under Advanced', (
    tester,
  ) async {
    final backend = await _pump(
      tester,
      const CupertinoPageScaffold(
        child: SingleChildScrollView(child: SearchOptionsBackendGroups()),
      ),
    );

    expect(
      find.text('Place details server · Nominatim'.toUpperCase()),
      findsOne,
    );

    final field = find.byWidgetPredicate(
      (w) =>
          w is CupertinoTextField &&
          w.placeholder == 'nominatim.openstreetmap.org',
    );
    await tester.enterText(field, 'nominatim.example.org');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(backend.nominatimHost, 'nominatim.example.org');
  });

  group('a host typed into the backend card', () {
    Future<BackendProvider> pumpCard(WidgetTester tester) => _pump(
      tester,
      const CupertinoPageScaffold(
        child: SingleChildScrollView(child: SearchOptionsBackendGroups()),
      ),
    );

    Finder field(String placeholder) => find.byWidgetPredicate(
      (w) => w is CupertinoTextField && w.placeholder == placeholder,
    );

    Future<void> submit(WidgetTester tester, Finder at, String text) async {
      await tester.enterText(at, text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    testWidgets('that is no host is refused there, and not kept', (
      tester,
    ) async {
      final backend = await pumpCard(tester);
      final host = field(BackendProvider.defaultHost);

      await submit(tester, host, 'motis example/api');

      expect(find.textContaining('not a host name'), findsOne);
      expect(backend.host, BackendProvider.defaultHost);
      expect(
        await SharedPreferencesAsync().getString('transitous_host'),
        isNull,
      );

      // Put right, it is kept and the complaint goes.
      await submit(tester, host, 'https://Motis.Example.org/');

      expect(find.textContaining('not a host name'), findsNothing);
      expect(backend.host, 'motis.example.org');
      expect(
        tester.widget<CupertinoTextField>(host).controller!.text,
        'motis.example.org',
      );
    });

    testWidgets('on plain http is refused with why', (tester) async {
      final backend = await pumpCard(tester);

      await submit(
        tester,
        field(BackendProvider.defaultHost),
        'http://motis.example.org',
      );

      expect(find.textContaining('only https:// servers'), findsOne);
      expect(backend.host, BackendProvider.defaultHost);
    });

    testWidgets('for Nominatim is checked the same way', (tester) async {
      final backend = await pumpCard(tester);

      await submit(
        tester,
        field('nominatim.openstreetmap.org'),
        'nominatim/lookup',
      );

      expect(find.textContaining('not a host name'), findsOne);
      expect(backend.nominatimHost, 'nominatim.openstreetmap.org');
    });
  });

  testWidgets('the legal page says what the lookup sends', (tester) async {
    await _pump(tester, const LegalScreen());

    expect(find.textContaining('Nominatim'), findsOne);
  });
}
