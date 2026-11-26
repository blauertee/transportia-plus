import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/api/nominatim_client.dart';
import 'package:transportia/providers/backend_provider.dart';

Future<BackendProvider> _loaded() => BackendProvider.load();

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('details are on, from the public server, until changed', () async {
    final backend = await _loaded();

    expect(backend.placeDetailsEnabled, isTrue);
    expect(backend.nominatimHost, NominatimClient.defaultHost);
    expect(backend.isCustomNominatimHost, isFalse);
  });

  test('turning details off is remembered', () async {
    final backend = await _loaded();
    await backend.setPlaceDetailsEnabled(false);

    expect(
      await SharedPreferencesAsync().getBool('place_details_enabled'),
      isFalse,
    );
    expect((await _loaded()).placeDetailsEnabled, isFalse);
  });

  test('turning them back on stores nothing', () async {
    final backend = await _loaded();
    await backend.setPlaceDetailsEnabled(false);
    await backend.setPlaceDetailsEnabled(true);

    expect(
      await SharedPreferencesAsync().getBool('place_details_enabled'),
      isNull,
    );
  });

  test(
    'another server is remembered, and blank goes back to the public one',
    () async {
      final backend = await _loaded();
      await backend.setNominatimHost(' nominatim.example.org ');

      expect(backend.nominatimHost, 'nominatim.example.org');
      expect((await _loaded()).nominatimHost, 'nominatim.example.org');

      await backend.setNominatimHost('');
      expect(backend.nominatimHost, NominatimClient.defaultHost);
      expect(
        await SharedPreferencesAsync().getString('nominatim_host'),
        isNull,
      );
    },
  );
}
