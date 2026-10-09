import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/stop_time.dart';
import 'package:transportia/models/transitous/enums.dart';
import 'package:transportia/models/transitous/place.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/services/transitous_map_service.dart';
import 'package:transportia/widgets/nearby_departures_section.dart';

List<MapStop> _berlinStops() => [
  for (final json
      in jsonDecode(
            File('test/fixtures/transitous/map_stops.json').readAsStringSync(),
          )
          as List)
    MapStop.fromPlace(TransitPlace.fromJson(json as Map<String, dynamic>)),
];

List<StopTime> _departures() => StopTimesResponse.fromJson(
  jsonDecode(File('test/fixtures/transitous/stoptimes.json').readAsStringSync())
      as Map<String, dynamic>,
).stopTimes;

Widget _row(MapStop stop, List<String> lines, List<TransitMode> _) =>
    Column(children: [Text(stop.name), Text(lines.join(', '))]);

const LatLng _centre = LatLng(52.5155, 13.4039);

/// A few minutes before the capture's first departure.
final DateTime _now = DateTime.utc(2026, 8, 8, 9, 30);

Future<void> _pump(
  WidgetTester tester, {
  LatLng? center = _centre,
  NearbyStopsFetcher? fetchStops,
  NearbyDeparturesFetcher? fetchDepartures,
  NearbyRowBuilder buildRow = _row,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(900, 1600)),
          child: SingleChildScrollView(
            child: NearbyDeparturesSection(
              center: center,
              buildRow: buildRow,
              buildMessage: Text.new,
              fetchStops: fetchStops ?? (_) async => _berlinStops(),
              fetchDepartures: fetchDepartures ?? (_, _) async => _departures(),
              clock: () => _now,
            ),
          ),
        ),
      ),
    ),
  );
  // Past the skeleton, to the answer.
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('says why when there is no position', (tester) async {
    await _pump(tester, center: null);

    expect(find.textContaining('Allow location access'), findsOneWidget);
  });

  testWidgets('lists the departures of each stop nearby', (tester) async {
    await _pump(tester);

    expect(find.text('Neumannsgasse (Berlin)'), findsOneWidget);
    expect(find.textContaining('S3, S5'), findsWidgets);
  });

  testWidgets('lists a stop split into several ids only once', (tester) async {
    // The capture has two stops called Neumannsgasse; given the same
    // departures they are one place to the rider.
    await _pump(tester);

    expect(find.text('Neumannsgasse (Berlin)'), findsOneWidget);
  });

  testWidgets('names each line once', (tester) async {
    await _pump(
      tester,
      fetchStops: (_) async => [_berlinStops().first],
      fetchDepartures: (_, _) async => _departures(),
    );

    // The capture runs several trips of each line; the row names a line once.
    final lines = tester
        .widget<Text>(find.textContaining('S3, '))
        .data!
        .split(', ');
    expect(lines.toSet().length, lines.length);
  });

  testWidgets('leaves out departures that have already gone', (tester) async {
    final later = DateTime.utc(2026, 8, 8, 12);
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeProvider>(
        create: (_) => ThemeProvider(),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: NearbyDeparturesSection(
            center: _centre,
            buildRow: _row,
            buildMessage: Text.new,
            fetchStops: (_) async => _berlinStops(),
            fetchDepartures: (_, _) async => _departures(),
            clock: () => later,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('No departures nearby.'), findsOneWidget);
  });

  testWidgets('says so when no stop has anything leaving', (tester) async {
    await _pump(tester, fetchDepartures: (_, _) async => const []);

    expect(find.text('No departures nearby.'), findsOneWidget);
  });

  testWidgets('survives the lookups failing', (tester) async {
    await _pump(tester, fetchStops: (_) async => throw Exception('offline'));

    expect(find.text('No departures nearby.'), findsOneWidget);
  });

  testWidgets('loads once when shown, never on a timer', (tester) async {
    var stopLookups = 0;
    var departureLookups = 0;
    await _pump(
      tester,
      fetchStops: (_) async {
        stopLookups++;
        return [_berlinStops().first];
      },
      fetchDepartures: (_, _) async {
        departureLookups++;
        return _departures();
      },
    );

    // Each load sends where the rider is; sitting on the screen sends nothing.
    await tester.pump(const Duration(minutes: 5));

    expect(stopLookups, 1);
    expect(departureLookups, 1);
  });

  testWidgets('hands each row the modes that call there', (tester) async {
    final modesByStop = <String, List<TransitMode>>{};
    await _pump(
      tester,
      fetchStops: (_) async => [_berlinStops().first],
      fetchDepartures: (_, _) async => [
        for (final departure in _departures())
          if (departure.mode == 'SUBWAY') departure,
      ],
      buildRow: (stop, lines, modes) {
        modesByStop[stop.name] = modes;
        return Text(stop.name);
      },
    );

    expect(modesByStop.values.single, [TransitMode.subway]);
  });
}
