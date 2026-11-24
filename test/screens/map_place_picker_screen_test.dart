import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transportia/api/nominatim_client.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/providers/backend_provider.dart';

import 'package:oktoast/oktoast.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/transitous/match.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/map_place_picker/edge_tabs.dart';
import 'package:transportia/screens/map_place_picker/map_place_picker_screen.dart';
import 'package:transportia/services/transitous_geocode_service.dart';

/// Pushes [screen] over a home route and hands back what it pops with.
Future<List<Object?>> _pump(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  _leaveMapPending(tester);
  final popped = <Object?>[];
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      // Where the app's toasts are shown, as in app.dart.
      child: OKToast(
        child: WidgetsApp(
          color: const Color(0xFF000000),
          localizationsDelegates: const [
            DefaultWidgetsLocalizations.delegate,
            DefaultCupertinoLocalizations.delegate,
          ],
          onGenerateRoute: (settings) => PageRouteBuilder<void>(
            settings: settings,
            pageBuilder: (context, _, _) => _Opener(
              onOpen: () async {
                popped.add(
                  await Navigator.of(context).push<Object?>(
                    PageRouteBuilder(pageBuilder: (_, _, _) => screen),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return popped;
}

/// The map asks the platform for a native view, which a test cannot make.
/// Left pending, rather than refused, its area stays blank and nothing
/// throws once a test waits long enough for the request to settle.
void _leaveMapPending(WidgetTester tester) {
  const channel = SystemChannels.platform_views;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    channel,
    (call) => call.method == 'create'
        ? Completer<Object?>().future
        : Future<Object?>.value(),
  );
  addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
}

class _Opener extends StatelessWidget {
  const _Opener({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) =>
      GestureDetector(onTap: onOpen, child: const Text('open'));
}

/// Taps the map, as a finger would: the map is a platform view and takes
/// no taps in a test.
Future<void> _tapMap(WidgetTester tester, LatLng at) async {
  tester.widget<MapLibreMap>(find.byType(MapLibreMap)).onMapClick!(
    const math.Point(0, 0),
    at,
  );
  // Naming the point fails without a network and falls back to coordinates.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  await tester.pump();
}

/// A toast is registered with oktoast for a day and closes itself after a
/// few seconds; left open, it would also block the next test's, which shares
/// its static guard. Runs it out, as save_trip_button_test.dart does.
Future<void> _letToastsRunOut(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(days: 2));
  await tester.pumpAndSettle();
}

/// Holds a finger on the map.
Future<void> _holdMap(WidgetTester tester, LatLng at) async {
  tester.widget<MapLibreMap>(find.byType(MapLibreMap)).onMapLongClick!(
    const math.Point(0, 0),
    at,
  );
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  await tester.pump();
}

List<TransitousLocationSuggestion> _capture(String name) => [
  for (final m
      in jsonDecode(File('test/fixtures/transitous/$name').readAsStringSync())
          as List)
    TransitousLocationSuggestion.fromMatch(
      Match.fromJson(m as Map<String, dynamic>),
    ),
];

/// A pin tapped: the map takes no taps in a test.
Future<void> _tapResult(WidgetTester tester, int rank) async {
  (tester.state(find.byType(MapPlacePickerScreen)) as dynamic)
      .tapResultForTesting(rank);
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  await tester.pump();
}

List<TransitousLocationSuggestion> _paris() => [
  for (final m
      in jsonDecode(
            File(
              'test/fixtures/transitous/geocode_paris.json',
            ).readAsStringSync(),
          )
          as List)
    TransitousLocationSuggestion.fromMatch(
      Match.fromJson(m as Map<String, dynamic>),
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('picking a route end says what it is for', (tester) async {
    // It used to read "Add Favourite" whatever it was opened for.
    await _pump(
      tester,
      const MapPlacePickerScreen.pick(
        title: 'Select Origin',
        confirmLabel: 'Select',
      ),
    );

    expect(find.text('Select Origin'), findsOneWidget);
    expect(find.text('Add Favourite'), findsNothing);

    await _tapMap(tester, const LatLng(52.52, 13.405));

    expect(find.text('Select'), findsOneWidget);
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('keeping a favourite still says so', (tester) async {
    await _pump(tester, const MapPlacePickerScreen.favourite());

    expect(find.text('Add Favourite'), findsOneWidget);

    await _tapMap(tester, const LatLng(52.52, 13.405));

    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('a picked point comes back as a place at that point', (
    tester,
  ) async {
    final popped = await _pump(
      tester,
      const MapPlacePickerScreen.pick(
        title: 'Select Origin',
        confirmLabel: 'Select',
      ),
    );

    await _tapMap(tester, const LatLng(52.52, 13.405));
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();

    final place = popped.single! as TransitousLocationSuggestion;
    expect(place.lat, closeTo(52.52, 1e-9));
    expect(place.lon, closeTo(13.405, 1e-9));
    expect(place.type, 'PLACE');
    expect(place.stopId, isNull);
  });

  group('with results', () {
    testWidgets('opens framed on the search, not on the rider', (tester) async {
      await _pump(
        tester,
        MapPlacePickerScreen.pick(
          title: 'Results for “Paris”',
          confirmLabel: 'Select',
          results: _paris(),
        ),
      );

      final camera = tester
          .widget<MapLibreMap>(find.byType(MapLibreMap))
          .initialCameraPosition!;
      // Paris, France: the city and its two stations.
      expect(camera.target.latitude, closeTo(48.86, 0.1));
      expect(camera.target.longitude, closeTo(2.35, 0.1));
      // Close enough to tell the stations apart, not a street.
      expect(camera.zoom, inInclusiveRange(11, 12));
      expect(
        find.text(
          'Tap a result for details, or hold anywhere to pick that point',
        ),
        findsOne,
      );
    });

    testWidgets('points at the results off screen', (tester) async {
      await _pump(
        tester,
        MapPlacePickerScreen.pick(
          title: 'Results for “Paris”',
          confirmLabel: 'Select',
          results: _paris(),
        ),
      );

      final tabs = tester.widgetList<EdgeTab>(find.byType(EdgeTab)).toList();
      expect(tabs, isNotEmpty);
      // Eight towns in the US lie one way: one tab, stacked.
      expect(tabs.where((t) => t.several), isNotEmpty);
    });

    testWidgets('among results, a tap only puts away; a hold picks', (
      tester,
    ) async {
      final popped = await _pump(
        tester,
        MapPlacePickerScreen.pick(
          title: 'Results for “Paris”',
          confirmLabel: 'Select',
          results: _paris(),
        ),
      );

      await _tapMap(tester, const LatLng(48.9, 2.4));
      expect(find.text('Point on the map'), findsNothing);

      await _holdMap(tester, const LatLng(48.9, 2.4));
      expect(find.text('Point on the map'), findsOne);

      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();
      final place = popped.single! as TransitousLocationSuggestion;
      expect(place.lat, closeTo(48.9, 1e-9));
    });

    testWidgets('a timetable cannot hold for a point either', (tester) async {
      await _pump(
        tester,
        MapPlacePickerScreen.pick(
          title: 'Results for “Paris”',
          confirmLabel: 'Select',
          results: _paris(),
          allowsPoint: false,
        ),
      );

      await _holdMap(tester, const LatLng(48.9, 2.4));
      expect(find.text('Point on the map'), findsNothing);
    });

    testWidgets('tabs reach the foot of the map, under the button', (
      tester,
    ) async {
      await _pump(
        tester,
        MapPlacePickerScreen.pick(
          title: 'Results for “Paris”',
          confirmLabel: 'Select',
          results: _paris(),
          query: 'Paris',
        ),
      );

      final layer = find.byType(EdgeTabsLayer);
      final area = tester.widget<EdgeTabsLayer>(layer).area;
      expect(area.bottom, tester.getSize(layer).height);
      // Drawn after the tabs, so on top of them.
      final button = tester.getRect(find.text('Search in this area'));
      expect(button.bottom, lessThanOrEqualTo(tester.getRect(layer).bottom));
    });

    testWidgets('a timetable picks results, never a bare point', (
      tester,
    ) async {
      await _pump(
        tester,
        MapPlacePickerScreen.pick(
          title: 'Results for “Paris”',
          confirmLabel: 'Select',
          results: _paris(),
          allowsPoint: false,
        ),
      );

      expect(find.text('Tap a result for details'), findsOne);
      await _tapMap(tester, const LatLng(48.9, 2.4));

      expect(find.text('Selected Location'), findsNothing);
      expect(find.text('Select'), findsNothing);
    });
  });

  group('search in this area', () {
    late List<Uri> requests;
    void serve(String body) {
      requests = [];
      TransitousClient.instance = TransitousClient(
        httpClient: MockClient((request) async {
          requests.add(request.url);
          return http.Response(
            body,
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
    }

    tearDown(() => TransitousClient.instance = TransitousClient());

    Widget picker() => MapPlacePickerScreen.pick(
      title: 'Results for “Rewe”',
      confirmLabel: 'Select',
      results: _paris(),
      query: 'Rewe',
      type: 'PLACE',
    );

    testWidgets('stands where the hint was, only for a search', (tester) async {
      await _pump(tester, picker());
      expect(find.text('Search in this area'), findsOne);
      expect(find.textContaining('Tap a result'), findsNothing);
    });

    testWidgets('a picker for a point keeps its hint', (tester) async {
      await _pump(
        tester,
        const MapPlacePickerScreen.pick(
          title: 'Select Origin',
          confirmLabel: 'Select',
        ),
      );
      expect(find.text('Search in this area'), findsNothing);
      expect(find.text('Tap anywhere to pick that point'), findsOne);
    });

    testWidgets('asks again from the middle of the map, held there', (
      tester,
    ) async {
      serve(
        File('test/fixtures/transitous/geocode_rewe.json').readAsStringSync(),
      );
      await _pump(tester, picker());
      final centre = tester
          .widget<MapLibreMap>(find.byType(MapLibreMap))
          .initialCameraPosition!
          .target;

      await tester.tap(find.text('Search in this area'));
      await tester.pumpAndSettle();

      final query = requests.single.queryParameters;
      expect(query['text'], 'Rewe');
      expect(query['type'], 'PLACE');
      expect(query['placeBias'], '20');
      expect(
        query['place'],
        '${centre.latitude.toStringAsFixed(6)},'
        '${centre.longitude.toStringAsFixed(6)}',
      );
      // The twenty REWEs in Berlin replace the Paris results.
      final tabs = tester.widget<EdgeTabsLayer>(find.byType(EdgeTabsLayer));
      expect(tabs.targets, hasLength(20));
      await _letToastsRunOut(tester);
    });

    testWidgets('an empty answer says so and keeps what was shown', (
      tester,
    ) async {
      serve('[]');
      await _pump(tester, picker());
      final before = tester
          .widget<EdgeTabsLayer>(find.byType(EdgeTabsLayer))
          .targets
          .length;

      await tester.tap(find.text('Search in this area'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Nothing found for “Rewe”'), findsOne);
      expect(
        tester.widget<EdgeTabsLayer>(find.byType(EdgeTabsLayer)).targets,
        hasLength(before),
      );
      await _letToastsRunOut(tester);
    });

    testWidgets('nothing on screen says so, and the tabs point onwards', (
      tester,
    ) async {
      // What MOTIS really answers where nothing is near: matches from far
      // away. The map is on Paris; these are Springfields in the US.
      serve(
        File(
          'test/fixtures/transitous/geocode_springfield.json',
        ).readAsStringSync(),
      );
      await _pump(tester, picker());

      await tester.tap(find.text('Search in this area'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Nothing in this area; the arrows point to the nearest'),
        findsOne,
      );
      final layer = tester.widget<EdgeTabsLayer>(find.byType(EdgeTabsLayer));
      expect(layer.targets, hasLength(20));
      expect(find.byType(EdgeTab), findsWidgets);
      await _letToastsRunOut(tester);
    });

    testWidgets('results on screen need no word', (tester) async {
      // The Paris results again, from over Paris.
      serve(
        File('test/fixtures/transitous/geocode_paris.json').readAsStringSync(),
      );
      await _pump(tester, picker());

      await tester.tap(find.text('Search in this area'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing'), findsNothing);
    });
  });

  group('tapping a pin', () {
    late List<Uri> lookups;
    setUp(() {
      lookups = [];
      NominatimClient.instance = NominatimClient(
        httpClient: MockClient((request) async {
          lookups.add(request.url);
          return http.Response(
            File('test/fixtures/nominatim/lookup_rewe.json').readAsStringSync(),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
        wait: (_) async {},
      );
    });
    tearDown(() {
      NominatimClient.instance = NominatimClient();
      BackendProvider.instance?.dispose();
    });

    Widget rewePicker() => MapPlacePickerScreen.pick(
      title: 'Results for “Rewe”',
      confirmLabel: 'Select',
      results: _capture('geocode_rewe.json'),
      query: 'Rewe',
    );

    testWidgets('a place shows what OpenStreetMap knows of it', (tester) async {
      await _pump(tester, rewePicker());
      final rewe = _capture('geocode_rewe.json').first;

      await _tapResult(tester, 0);

      // Asked about the very element MOTIS named.
      expect(
        lookups.single.queryParameters['osm_ids'],
        'N${RegExp(r'\d+').firstMatch(rewe.match!.id)!.group(0)}',
      );
      expect(find.text('Mo–Sa 07:00–23:30'), findsOne);
      expect(find.text('Supermarket'), findsOne);
      expect(find.text('Details © OpenStreetMap contributors'), findsOne);
      expect(find.text('Search in this area'), findsNothing);
    });

    testWidgets('turned off, nothing is asked', (tester) async {
      final backend = BackendProvider();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await backend.setPlaceDetailsEnabled(false);
      await _pump(tester, rewePicker());

      await _tapResult(tester, 0);

      expect(lookups, isEmpty);
      expect(find.text('REWE'), findsWidgets);
      expect(find.textContaining('OpenStreetMap'), findsNothing);
    });

    testWidgets('a stop shows its next departures, not OpenStreetMap', (
      tester,
    ) async {
      TransitousClient.instance = TransitousClient(
        httpClient: MockClient(
          (_) async => http.Response(
            File('test/fixtures/transitous/stoptimes.json').readAsStringSync(),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(() => TransitousClient.instance = TransitousClient());
      final alex = _capture('geocode.json');
      final stop = alex.indexWhere((r) => r.stopId != null);
      await _pump(
        tester,
        MapPlacePickerScreen.pick(
          title: 'Results for “Alexanderplatz”',
          confirmLabel: 'Select',
          results: alex,
        ),
      );

      await _tapResult(tester, stop);

      expect(find.text('NEXT DEPARTURES'), findsOne);
      expect(lookups, isEmpty);
    });

    testWidgets('select hands back the result, stop id and all', (
      tester,
    ) async {
      final alex = _capture('geocode.json');
      final stop = alex.indexWhere((r) => r.stopId != null);
      final popped = await _pump(
        tester,
        MapPlacePickerScreen.pick(
          title: 'Results for “Alexanderplatz”',
          confirmLabel: 'Select',
          results: alex,
        ),
      );

      await _tapResult(tester, stop);
      await tester.tap(find.text('Select'));
      await tester.pumpAndSettle();

      final picked = popped.single! as TransitousLocationSuggestion;
      expect(picked.stopId, alex[stop].stopId);
    });

    testWidgets('cancel puts the sheet away', (tester) async {
      await _pump(tester, rewePicker());
      await _tapResult(tester, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(find.text('Search in this area'), findsOne);
    });
  });
}
