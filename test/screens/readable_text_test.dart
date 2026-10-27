import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/models/itinerary_response.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/itinerary_detail_screen.dart';
import 'package:transportia/screens/itinerary_list_screen.dart';
import 'package:transportia/services/transitous_geocode_service.dart';
import 'package:transportia/utils/journey_graph.dart';

import '../support/bottom_card_host.dart';
import '../support/readable_text.dart';

String _fixture(String name) =>
    File('test/fixtures/transitous/$name.json').readAsStringSync();

/// No text anywhere in the app smaller than [kMinFontSize]: every size
/// written into the code, and every text drawn on the main screens, where
/// sizes also come from themes and from code that works them out.
void main() {
  final plan = _fixture('plan_journey_graph');
  final onward = _fixture('plan_journey_graph_onward');
  final results = ItineraryResponse.fromJson(
    jsonDecode(plan) as Map<String, dynamic>,
  ).itineraries;
  final viaIngolstadt = results.firstWhere(
    (it) => it.legs.any((leg) => leg.displayName == 'ICE 1009'),
  );
  final ice1009 = viaIngolstadt.legs.firstWhere(
    (leg) => leg.displayName == 'ICE 1009',
  );

  test('no font size written into the app is below the minimum', () {
    final size = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)\b');
    final small = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final match in size.allMatches(lines[i])) {
          if (double.parse(match[1]!) < kMinFontSize) {
            small.add('${file.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }

    expect(small, isEmpty);
  });

  group('drawn on screen', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      // A search from a stop is the one going on from a locked ride.
      TransitousClient.instance = TransitousClient(
        httpClient: MockClient((request) async {
          if (!request.url.path.endsWith('/plan')) {
            return http.Response('{}', 500);
          }
          final from = request.url.queryParameters['fromPlace']!;
          return http.Response.bytes(
            utf8.encode(from.contains(',') ? plan : onward),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
    });

    tearDown(() => TransitousClient.instance = TransitousClient());

    Future<void> pump(
      WidgetTester tester,
      Widget home, {
      Size size = const Size(400, 860),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: CupertinoApp(home: home),
        ),
      );
      await answer(tester);
    }

    ItineraryListScreen resultsScreen({RideLock? lock}) {
      final origin = viaIngolstadt.legs.first.from;
      final destination = viaIngolstadt.legs.last.to;
      return ItineraryListScreen(
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
        lockedUpTo: lock,
      );
    }

    testWidgets('the search card', (tester) async {
      await pump(
        tester,
        const BottomCardHost(asPage: true),
        size: const Size(400, 1400),
      );

      expectReadableText(tester);
    });

    testWidgets('search results, as a list and as a graph', (tester) async {
      await pump(tester, resultsScreen());
      expectReadableText(tester);

      await tester.tap(find.text('Graph'));
      await answer(tester);
      expectReadableText(tester);
    });

    testWidgets('a journey locked part way, as a list and as a graph', (
      tester,
    ) async {
      await pump(tester, resultsScreen(lock: RideLock(viaIngolstadt, ice1009)));
      expectReadableText(tester);

      await tester.tap(find.text('Graph'));
      await answer(tester);
      expectReadableText(tester);
    });

    testWidgets('a journey, step by step', (tester) async {
      await pump(
        tester,
        ItineraryDetailScreen(
          itinerary: viaIngolstadt,
          fromName: 'Wildau',
          toName: 'Lindau Insel',
        ),
        size: const Size(400, 3000),
      );

      expectReadableText(tester);
    });
  });
}

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
