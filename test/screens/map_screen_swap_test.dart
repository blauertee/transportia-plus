import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/my_location.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/map_screen.dart';
import 'package:transportia/services/plan_request.dart';
import 'package:transportia/services/transitous_geocode_service.dart';
import 'package:transportia/widgets/route_field_box.dart';

/// Literal, as a released build will have written it.
const String _searchMapEnabled = 'search_map_enabled';

final _alex = TransitousLocationSuggestion(
  id: 'alex',
  name: 'Alexanderplatz',
  lat: 52.521,
  lon: 13.413,
  type: 'STOP',
);

/// The two fields, origin first.
List<String> _fields(WidgetTester tester) {
  final box = tester.widget<RouteFieldBox>(find.byType(RouteFieldBox));
  return [box.fromController.text, box.toController.text];
}

Future<void> _swap(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('Swap origin and destination'));
  await tester.pump();
}

Future<void> _pumpWith(WidgetTester tester, PlanRequest request) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  // The map is a platform view and draws nothing here; the card is the point.
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData({_searchMapEnabled: false});
  // Waiting before the screen is built, as a deep link leaves it.
  PlanRequests.ask(request);
  addTearDown(() => PlanRequests.pending.value = null);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: WidgetsApp(
        color: const Color(0xFF000000),
        localizationsDelegates: const [
          DefaultWidgetsLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
        ],
        onGenerateRoute: (settings) => PageRouteBuilder<void>(
          settings: settings,
          // Deferred, so the screen does not ask for the location on its own.
          pageBuilder: (_, _, _) => const MapScreen(deferInit: true),
        ),
      ),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('My Location swaps like any other place', (tester) async {
    await _pumpWith(
      tester,
      PlanRequest(
        from: myLocationSuggestion,
        to: _alex,
        time: TimeSelection.now(),
      ),
    );
    expect(_fields(tester), [myLocationName, 'Alexanderplatz']);

    await _swap(tester);
    expect(_fields(tester), ['Alexanderplatz', myLocationName]);

    await _swap(tester);
    expect(_fields(tester), [myLocationName, 'Alexanderplatz']);
  });

  testWidgets('swapping is a plain exchange, asked nothing', (tester) async {
    await _pumpWith(
      tester,
      PlanRequest(
        from: myLocationSuggestion,
        to: _alex,
        time: TimeSelection.now(),
      ),
    );

    // Swap is a plain exchange, so swapping twice is where it started, and
    // nothing in between asked what the fields held.
    await _swap(tester);
    await _swap(tester);
    await _swap(tester);
    expect(_fields(tester), ['Alexanderplatz', myLocationName]);
    expect(find.textContaining('Supply at least'), findsNothing);
  });
}
