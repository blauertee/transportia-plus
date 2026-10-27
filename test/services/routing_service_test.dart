import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/models/routing_options.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/models/transitous/enums.dart';
import 'package:transportia/services/routing_options_service.dart';
import 'package:transportia/services/routing_service.dart';

/// Captures the request RoutingService makes, without a network.
late Uri lastRequest;

TransitousClient _capturingClient() => TransitousClient(
  httpClient: MockClient((request) async {
    lastRequest = request.url;
    return http.Response(
      json.encode(const {'itineraries': <Object>[]}),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TransitousClient original;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    original = TransitousClient.instance;
    TransitousClient.instance = _capturingClient();
    RoutingOptionsService.invalidate();
  });

  tearDown(() => TransitousClient.instance = original);

  Future<Map<String, String>> plan({
    TimeSelection? timeSelection,
    RoutingOptions? options,
    String? pageCursor,
  }) async {
    await RoutingService.findRoutesPaginated(
      fromLat: 52.52,
      fromLon: 13.405,
      toLat: 53.5511,
      toLon: 9.9937,
      timeSelection: timeSelection,
      options: options,
      pageCursor: pageCursor,
    );
    return lastRequest.queryParameters;
  }

  test('targets the plan endpoint on the configured API version', () async {
    await plan();
    expect(lastRequest.host, 'api.transitous.org');
    expect(lastRequest.path, '/api/v6/plan');
  });

  test('sends endpoints as comma-separated coordinates', () async {
    final query = await plan();
    expect(query['fromPlace'], '52.520000,13.405000');
    expect(query['toPlace'], '53.551100,9.993700');
  });

  test('asks for fares and routed transfers', () async {
    final query = await plan();
    expect(query['withFares'], 'true');
    expect(query['useRoutedTransfers'], 'true');
  });

  test('omits the options left at their default', () async {
    final query = await plan();
    expect(query.containsKey('pedestrianSpeed'), isFalse);
    expect(query.containsKey('additionalTransferTime'), isFalse);
    expect(query.containsKey('transitModes'), isFalse);
    expect(query.containsKey('time'), isFalse);
  });

  test('converts the walking speed from km/h to m/s', () async {
    await RoutingOptionsService.save(
      const RoutingOptions(walkingSpeedKmh: 5.4),
    );

    final query = await plan();
    expect(double.parse(query['pedestrianSpeed']!), closeTo(1.5, 0.0001));
  });

  test('leaves the speeds out when they match the server default', () async {
    // Restating a default would pin it if the server ever changed it.
    await RoutingOptionsService.save(RoutingOptions.defaults);

    final query = await plan();
    expect(query.containsKey('pedestrianSpeed'), isFalse);
    expect(query.containsKey('cyclingSpeed'), isFalse);
  });

  test('sends the transfer buffer in minutes', () async {
    await RoutingOptionsService.save(
      const RoutingOptions(additionalTransferTime: Duration(minutes: 7)),
    );

    expect((await plan())['additionalTransferTime'], '7');
  });

  test('drops a zero transfer buffer rather than sending it', () async {
    await RoutingOptionsService.save(RoutingOptions.defaults);

    expect((await plan()).containsKey('additionalTransferTime'), isFalse);
  });

  test('sends the selected modes', () async {
    await RoutingOptionsService.save(
      const RoutingOptions(transitModes: [TransitMode.bus, TransitMode.rail]),
    );

    expect((await plan())['transitModes'], 'BUS,RAIL');
  });

  group('the options behind the Transitous options panel', () {
    test('all of them reach the plan request', () async {
      await RoutingOptionsService.save(
        const RoutingOptions(
          useRoutedTransfers: false,
          wheelchairAccessibleOnly: true,

          noCompulsoryReservation: true,
          via: [
            ViaStopOption(
              stopId: 'de-DELFI_de:11000:900100003',
              name: 'Alexanderplatz',
              minimumStay: Duration(minutes: 10),
            ),
          ],
          maxTransfers: 3,
          additionalTransferTime: Duration(minutes: 5),
          firstMileModes: [TransitMode.bike],
          maxFirstMileTime: Duration(minutes: 20),
          lastMileModes: [TransitMode.bike],
          maxLastMileTime: Duration(minutes: 10),
          lastMileSameAsFirst: false,
          walkingSpeedKmh: 5.4,
          cyclingSpeedKmh: 18.0,
          elevationCosts: ElevationCosts.high,
        ),
      );

      final query = await plan();
      expect(query['useRoutedTransfers'], 'false');
      expect(query['pedestrianProfile'], 'WHEELCHAIR');
      expect(query['requireBikeTransport'], 'true');
      expect(query['noCompulsoryReservation'], 'true');
      expect(query['via'], 'de-DELFI_de:11000:900100003');
      expect(query['viaMinimumStay'], '10');
      expect(query['maxTransfers'], '3');
      expect(query['additionalTransferTime'], '5');
      expect(query['preTransitModes'], 'BIKE');
      expect(query['maxPreTransitTime'], '1200');
      expect(query['postTransitModes'], 'BIKE');
      expect(query['maxPostTransitTime'], '600');
      expect(query['directModes'], 'WALK,BIKE');
      expect(query['maxDirectTime'], '1800');
      expect(query['elevationCosts'], 'HIGH');
      expect(double.parse(query['cyclingSpeed']!), closeTo(5.0, 0.01));
    });

    test('options left off are absent rather than sent as false', () async {
      await RoutingOptionsService.save(RoutingOptions.defaults);

      final query = await plan();
      expect(query.containsKey('pedestrianProfile'), isFalse);
      expect(query.containsKey('requireBikeTransport'), isFalse);
      expect(query.containsKey('requireCarTransport'), isFalse);
      expect(query.containsKey('noCompulsoryReservation'), isFalse);
      expect(query.containsKey('elevationCosts'), isFalse);
      expect(query.containsKey('via'), isFalse);
      expect(query.containsKey('maxTransfers'), isFalse);
    });
  });

  test('sends the chosen departure time', () async {
    final query = await plan(
      timeSelection: TimeSelection(
        dateTime: DateTime.utc(2026, 8, 10, 8),
        isArriveBy: false,
      ),
    );

    expect(query['time'], '2026-08-10T08:00:00.000Z');
    expect(query['arriveBy'], 'false');
  });

  test('sends arriveBy for an arrival time', () async {
    final query = await plan(
      timeSelection: TimeSelection(
        dateTime: DateTime.utc(2026, 8, 10, 8),
        isArriveBy: true,
      ),
    );

    expect(query['arriveBy'], 'true');
  });

  test('leaves the time out when departing now', () async {
    final query = await plan(timeSelection: TimeSelection.now());

    expect(query.containsKey('time'), isFalse);
    expect(query.containsKey('arriveBy'), isFalse);
  });

  group('per-search options', () {
    test('the options given win over the stored defaults', () async {
      await RoutingOptionsService.save(
        RoutingOptions.defaults.copyWith(maxTransfers: 4),
      );

      final query = await plan(
        options: RoutingOptions.defaults.copyWith(
          maxTransfers: 0,
          firstMileModes: [TransitMode.bike],
          lastMileModes: [TransitMode.bike],
        ),
      );

      expect(query['maxTransfers'], '0');
      expect(query['preTransitModes'], contains('BIKE'));
      // Derived rather than asked for: a bike at both ends is travelling.
      expect(query['requireBikeTransport'], 'true');
    });

    test(
      'falls back to the stored defaults for an unconfigured journey',
      () async {
        await RoutingOptionsService.save(
          RoutingOptions.defaults.copyWith(maxTransfers: 4),
        );

        // A deep link or a saved trip nobody configured a search for.
        final query = await plan();

        expect(query['maxTransfers'], '4');
      },
    );

    test('a later page is the same search as the first', () async {
      final options = RoutingOptions.defaults.copyWith(maxTransfers: 1);
      await plan(options: options);

      // The defaults change under it, as they would after Save as default.
      await RoutingOptionsService.save(
        RoutingOptions.defaults.copyWith(maxTransfers: 5),
      );
      final next = await plan(options: options, pageCursor: 'later|1');

      expect(next['maxTransfers'], '1');
      expect(next['pageCursor'], 'later|1');
    });
  });
}
