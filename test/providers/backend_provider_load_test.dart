import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/api/endpoints/map_endpoint.dart';
import 'package:transportia/api/nominatim_client.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/api/transitous_endpoint.dart';
import 'package:transportia/providers/backend_provider.dart';

/// Records every request, answering it from the `/map/initial` capture.
List<Uri> _serve() {
  final body = File(
    'test/fixtures/transitous/map_initial.json',
  ).readAsStringSync();
  final requests = <Uri>[];
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
  return requests;
}

/// Storage as a released build leaves it for a rider on their own server.
/// Literal key names: these are what is on the phone.
void _storeOwnServer() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData({
        'transitous_host': 'motis.example.org',
        'transitous_api_version': 'v5',
        'transitous_api_version_endpoint_plan': 'v4',
        'place_details_enabled': false,
        'nominatim_host': 'nominatim.example.org',
      });
}

void main() {
  late List<Uri> requests;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    requests = _serve();
  });
  tearDown(() {
    BackendProvider.instance?.dispose();
    TransitousClient.instance = TransitousClient();
  });

  group('loading the stored settings', () {
    test('puts a stored host in place before the first request', () async {
      _storeOwnServer();

      await BackendProvider.load();
      // Straight away, as the first screen would, with nothing waited on.
      await MapEndpoint.initial();

      expect(requests.single.host, 'motis.example.org');
    });

    test('brings every stored setting with it', () async {
      _storeOwnServer();

      final backend = await BackendProvider.load();

      expect(backend.host, 'motis.example.org');
      expect(backend.apiVersion, 'v5');
      expect(backend.versionFor(TransitousEndpoint.plan), 'v4');
      expect(
        backend.versionFor(TransitousEndpoint.trip),
        backend.defaultVersionFor(TransitousEndpoint.trip),
      );
      expect(backend.placeDetailsEnabled, isFalse);
      expect(backend.nominatimHost, 'nominatim.example.org');
    });

    test('with nothing stored, keeps the defaults', () async {
      final backend = await BackendProvider.load();
      await MapEndpoint.initial();

      expect(backend.host, BackendProvider.defaultHost);
      expect(backend.isCustomApiVersion, isFalse);
      expect(backend.hasEndpointOverrides, isFalse);
      expect(backend.placeDetailsEnabled, isTrue);
      expect(backend.nominatimHost, NominatimClient.defaultHost);
      expect(requests.single.host, BackendProvider.defaultHost);
    });

    test('takes an empty stored value as unset', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'transitous_host': '',
            'transitous_api_version_endpoint_plan': '',
          });

      final backend = await BackendProvider.load();

      expect(backend.host, BackendProvider.defaultHost);
      expect(backend.hasEndpointOverrides, isFalse);
    });
  });

  test('the bare constructor reads nothing', () async {
    _storeOwnServer();

    final backend = BackendProvider();
    await Future<void>.delayed(Duration.zero);

    expect(backend.host, BackendProvider.defaultHost);
  });
}
