import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/models/itinerary_response.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/itinerary_list_screen.dart';
import 'package:transportia/services/transitous_geocode_service.dart';
import 'package:transportia/utils/journey_graph.dart';

String _fixture(String name) =>
    File('test/fixtures/transitous/$name.json').readAsStringSync();

void main() {
  final plan = _fixture('plan_journey_graph');
  final onward = _fixture('plan_journey_graph_onward');
  // Parsed here for the lock; the screen gets its own from the client.
  final results = ItineraryResponse.fromJson(
    jsonDecode(plan) as Map<String, dynamic>,
  ).itineraries;
  final viaIngolstadt = results.firstWhere(
    (it) => it.legs.any((leg) => leg.displayName == 'ICE 1009'),
  );
  final ice1009 = viaIngolstadt.legs.firstWhere(
    (leg) => leg.displayName == 'ICE 1009',
  );

  /// The `fromPlace` of every search the screen sent.
  late List<String> from;

  setUp(() {
    from = [];
    // A search from a stop is the one going on from a locked ride.
    TransitousClient.instance = TransitousClient(
      httpClient: MockClient((request) async {
        if (!request.url.path.endsWith('/plan')) {
          return http.Response('{}', 500);
        }
        final place = request.url.queryParameters['fromPlace']!;
        from.add(place);
        final fromStop = !place.contains(',');
        return http.Response.bytes(
          utf8.encode(fromStop ? onward : plan),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  });

  tearDown(() => TransitousClient.instance = TransitousClient());

  /// Lets the planner's answers land. Not pumpAndSettle: a live result
  /// pulses its radio icon for as long as it is on screen.
  Future<void> answer(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> pumpLocked(WidgetTester tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view.physicalSize = const Size(400, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final origin = viaIngolstadt.legs.first.from;
    final destination = viaIngolstadt.legs.last.to;
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: CupertinoApp(
          home: ItineraryListScreen(
            fromLat: origin.lat,
            fromLon: origin.lon,
            toLat: destination.lat,
            toLon: destination.lon,
            timeSelection: TimeSelection(
              dateTime: viaIngolstadt.startTime,
              isArriveBy: false,
            ),
            fromSelection: TransitousLocationSuggestion(
              id: 'from',
              name: 'Wildau',
              lat: origin.lat,
              lon: origin.lon,
              type: 'PLACE',
            ),
            lockedUpTo: RideLock(viaIngolstadt, ice1009),
          ),
        ),
      ),
    );
    await answer(tester);
  }

  testWidgets('a journey locked in advance lists what goes on from there', (
    tester,
  ) async {
    await pumpLocked(tester);

    expect(find.text('Only journeys fixed up to Ingolstadt Hbf.'), findsOne);
    expect(find.text('Search from Wildau'), findsOne);
    expect(from.where((place) => !place.contains(',')), isNotEmpty);
    // Every result listed starts with the fixed part.
    expect(find.text('ICE 1009'), findsWidgets);
    expect(find.text('ICE 1507'), findsNothing);
  });

  testWidgets('searching from the start drops the lock', (tester) async {
    await pumpLocked(tester);

    await tester.tap(find.text('Search from Wildau'));
    await answer(tester);

    expect(find.textContaining('Only journeys'), findsNothing);
    expect(find.text('ICE 1507'), findsWidgets);
  });

  testWidgets('the graph shows the same lock', (tester) async {
    await pumpLocked(tester);

    await tester.tap(find.text('Graph'));
    await answer(tester);

    expect(find.text('up to Ingolstadt Hbf'), findsOne);
    expect(find.textContaining('Only journeys'), findsNothing);
  });
}
