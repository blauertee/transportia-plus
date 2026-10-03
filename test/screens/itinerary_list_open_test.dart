import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/models/routing_options.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/itinerary_list_screen.dart';
import 'package:transportia/services/plan_request.dart';
import 'package:transportia/services/transitous_geocode_service.dart';

final _to = TransitousLocationSuggestion(
  id: 'to',
  name: 'Alexanderplatz',
  lat: 52.521,
  lon: 13.413,
  type: 'STOP',
);

// Not null: My Location would ask the device for a fix, and there is no
// location plugin in a test.
final _from = TransitousLocationSuggestion(
  id: 'from',
  name: 'Hauptbahnhof',
  lat: 52.525,
  lon: 13.369,
  type: 'STOP',
);

/// Tabs underneath, a detail page on top: the shape of the app when
/// "Find alternatives" is tapped.
Future<NavigatorState> _pumpTabsWithDetail(WidgetTester tester) async {
  final navigatorKey = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: WidgetsApp(
        color: const Color(0xFF000000),
        navigatorKey: navigatorKey,
        localizationsDelegates: const [
          DefaultWidgetsLocalizations.delegate,
          DefaultCupertinoLocalizations.delegate,
        ],
        home: const Text('tabs'),
        pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, _) => builder(context),
        ),
      ),
    ),
  );
  unawaited(
    navigatorKey.currentState!.push(
      PageRouteBuilder<void>(pageBuilder: (_, _, _) => const Text('detail')),
    ),
  );
  await tester.pump();
  return navigatorKey.currentState!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    // Whatever the results screen asks for, the planner is not reachable.
    TransitousClient.instance = TransitousClient(
      httpClient: MockClient((_) async => http.Response('{}', 500)),
    );
  });

  tearDown(() {
    TransitousClient.instance = TransitousClient();
    PlanRequests.pending.value = null;
  });

  testWidgets('hands the routing screen the journey and the options', (
    tester,
  ) async {
    final navigator = await _pumpTabsWithDetail(tester);
    final time = TimeSelection(
      dateTime: DateTime(2026, 10, 2, 9, 30),
      isArriveBy: false,
    );

    await tester.runAsync(
      () => ItineraryListScreen.openOverRoutingScreen(
        navigator,
        from: _from,
        to: _to,
        time: time,
      ),
    );
    await tester.pump();

    final request = PlanRequests.pending.value!;
    expect(request.from, _from);
    expect(request.to, _to);
    expect(request.time, time);
    expect(request.options, RoutingOptions.defaults);
  });

  testWidgets('shows the results over the tabs, not over the page before', (
    tester,
  ) async {
    final navigator = await _pumpTabsWithDetail(tester);
    expect(find.byType(ItineraryListScreen), findsNothing);

    await tester.runAsync(
      () => ItineraryListScreen.openOverRoutingScreen(
        navigator,
        from: _from,
        to: _to,
        time: TimeSelection.now(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(ItineraryListScreen), findsOneWidget);
    expect(find.text('detail'), findsNothing);

    // Back: no detail page in between, so the tabs — and the routing screen
    // with the fields filled in — are what is there.
    navigator.pop();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ItineraryListScreen), findsNothing);
    expect(find.text('tabs'), findsOneWidget);
    expect(navigator.canPop(), isFalse);
  });
}
