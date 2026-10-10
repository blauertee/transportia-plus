import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/stop_time.dart';
import 'package:transportia/models/transitous/enums.dart';
import 'package:transportia/models/transitous/place.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/screens/timetables_screen.dart';
import 'package:transportia/services/favorites_service.dart';
import 'package:transportia/services/transitous_map_service.dart';
import 'package:transportia/utils/place_icons.dart';
import 'package:transportia/widgets/nearby_departures_section.dart';

List<MapStop> _stops() => [
  for (final json
      in jsonDecode(
            File('test/fixtures/transitous/map_stops.json').readAsStringSync(),
          )
          as List)
    MapStop.fromPlace(TransitPlace.fromJson(json as Map<String, dynamic>)),
];

/// Only the subway trips of the capture, so the stop is not a railway station.
List<StopTime> _subwayDepartures() => [
  for (final departure in StopTimesResponse.fromJson(
    jsonDecode(
          File('test/fixtures/transitous/stoptimes.json').readAsStringSync(),
        )
        as Map<String, dynamic>,
  ).stopTimes)
    if (departure.mode == 'SUBWAY') departure,
];

/// How many times the list asked for stops near the rider.
int _lookups = 0;

NearbySectionBuilder _nearby(LatLng? center) =>
    (buildRow, buildMessage) => NearbyDeparturesSection(
      center: const LatLng(52.5155, 13.4039),
      buildRow: buildRow,
      buildMessage: buildMessage,
      fetchStops: (_) async {
        _lookups++;
        return [_stops().first];
      },
      fetchDepartures: (_, _) async => _subwayDepartures(),
      clock: () => DateTime.utc(2026, 8, 8, 9, 30),
    );

Future<void> _pump(
  WidgetTester tester, {
  bool isOpen = true,
  Map<String, Object> stored = const {},
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(stored);
  // No position to be had: the list is handed its own.
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    const MethodChannel('flutter.baseflow.com/permissions/methods'),
    (call) async => switch (call.method) {
      'checkPermissionStatus' => 0,
      'requestPermissions' => <int, int>{},
      _ => null,
    },
  );
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: CupertinoApp(
        home: TimetablesScreen(isOpen: isOpen, buildNearby: _nearby),
      ),
    ),
  );
  // The stored setting and the lists load before there is anything to see.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    _lookups = 0;
    FavoritesService.favoritesListenable.value = const [];
  });

  testWidgets('lists the stops near you between the other lists', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('NEAR YOU'), findsOne);
    expect(find.text(_stops().first.name), findsOne);
    expect(find.text('U2, U8'), findsOne);
  });

  testWidgets('draws a stop by what calls there', (tester) async {
    await _pump(tester);

    expect(find.byIcon(stopIcon([TransitMode.subway])), findsOne);
  });

  testWidgets('switched off, there is no section and nothing is asked', (
    tester,
  ) async {
    await _pump(tester, stored: {'show_nearby_departures': false});

    expect(find.text('NEAR YOU'), findsNothing);
    expect(_lookups, 0);
  });

  testWidgets('nothing is asked while another tab is showing', (tester) async {
    await _pump(tester, isOpen: false);

    expect(find.text('NEAR YOU'), findsNothing);
    expect(_lookups, 0);
  });

  testWidgets('each opening of the tab loads the list once', (tester) async {
    await _pump(tester, isOpen: false);

    Future<void> showTab(bool isOpen) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeProvider>(
          create: (_) => ThemeProvider(),
          child: CupertinoApp(
            home: TimetablesScreen(isOpen: isOpen, buildNearby: _nearby),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }

    await showTab(true);
    await tester.pump(const Duration(minutes: 5));
    expect(_lookups, 1);

    await showTab(false);
    await showTab(true);
    expect(_lookups, 2);
  });

  testWidgets('tapping a stop picks it, as any other stop', (tester) async {
    await _pump(tester);

    await tester.tap(find.text(_stops().first.name));
    await tester.pump();

    // The departure board's field now holds the stop; the list is gone.
    expect(find.text('NEAR YOU'), findsNothing);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is CupertinoTextField &&
            w.controller?.text == _stops().first.name,
      ),
      findsOne,
    );
  });
}
