import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/api/transitous_endpoint.dart';
import 'package:transportia/models/transitous/rentals_response.dart';
import 'package:transportia/providers/backend_provider.dart';
import 'package:transportia/services/backend_reload_service.dart';
import 'package:transportia/services/rental_providers_service.dart';
import 'package:transportia/services/server_capabilities_service.dart';

final _mapInitial = File(
  'test/fixtures/transitous/map_initial.json',
).readAsStringSync();

/// Records every request, answering /map/initial from the capture.
List<Uri> _serve() {
  final requests = <Uri>[];
  TransitousClient.instance = TransitousClient(
    httpClient: MockClient((request) async {
      requests.add(request.url);
      return http.Response(
        request.url.path.endsWith('/map/initial') ? _mapInitial : '{}',
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  return requests;
}

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// A provider that has finished reading storage, being watched.
Future<BackendProvider> _watched() async {
  final backend = await BackendProvider.load();
  BackendReloadService.watch(backend);
  return backend;
}

void main() {
  late List<Uri> requests;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    ServerCapabilitiesService.invalidate();
    RentalProvidersService.invalidate();
    requests = _serve();
  });
  tearDown(() {
    BackendReloadService.stopWatching();
    TransitousClient.instance = TransitousClient();
  });

  test('another host reloads the server limits and the map', () async {
    final backend = await _watched();
    final before = BackendReloadService.generation.value;

    await backend.setHost('motis.example.org');
    await _settle();

    expect(BackendReloadService.generation.value, before + 1);
    expect(
      requests.where((u) => u.path.endsWith('/map/initial')),
      hasLength(1),
    );
  });

  test('another host drops the old provider list', () async {
    final backend = await _watched();
    RentalProvidersService.catalogueListenable.value = const [
      RentalProviderGroup(id: 'Old', name: 'Old'),
    ];

    await backend.setHost('motis.example.org');

    expect(RentalProvidersService.catalogueListenable.value, isNull);
  });

  test('another API version reloads too', () async {
    final backend = await _watched();
    final before = BackendReloadService.generation.value;

    await backend.setApiVersion('v5');
    await backend.setEndpointVersion(TransitousEndpoint.stopTimes, 'v4');

    expect(BackendReloadService.generation.value, before + 2);
  });

  test('settings that change nothing reload nothing', () async {
    final backend = await _watched();
    final before = BackendReloadService.generation.value;

    // What a text field does when it loses focus unchanged.
    await backend.setHost(backend.host);
    await backend.setApiVersion('');
    // Place details come from another server, cached by host already.
    await backend.setNominatimHost('nominatim.example.org');
    await _settle();

    expect(BackendReloadService.generation.value, before);
    expect(requests, isEmpty);
  });

  test('stored settings read at start-up are no switch', () async {
    // They are in place before anything is watched or asked, so there is
    // nothing from another server to reload.
    await SharedPreferencesAsync().setString(
      'transitous_host',
      'motis.example.org',
    );
    final before = BackendReloadService.generation.value;
    final backend = await _watched();

    await _settle();

    expect(backend.host, 'motis.example.org');
    expect(BackendReloadService.generation.value, before);
    expect(requests, isEmpty);
  });
}
