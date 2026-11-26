import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/api/nominatim_client.dart';
import 'package:transportia/providers/backend_provider.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });
  tearDown(() => BackendProvider.instance?.dispose());

  group('setting the routing host', () {
    test('keeps a pasted address as its host', () async {
      final backend = BackendProvider();

      expect(await backend.setHost('https://Motis.Example.org:8080/'), isTrue);

      expect(backend.host, 'motis.example.org:8080');
      expect(
        await SharedPreferencesAsync().getString('transitous_host'),
        'motis.example.org:8080',
      );
    });

    test('refuses what is not a host, changing and saving nothing', () async {
      final backend = BackendProvider();
      await backend.setHost('motis.example.org');
      var notified = false;
      backend.addListener(() => notified = true);

      expect(await backend.setHost('motis example/api'), isFalse);
      expect(await backend.setHost('http://motis.example.org'), isFalse);

      expect(backend.host, 'motis.example.org');
      expect(notified, isFalse);
      expect(
        await SharedPreferencesAsync().getString('transitous_host'),
        'motis.example.org',
      );
    });

    test('blank means the default', () async {
      final backend = BackendProvider();
      await backend.setHost('motis.example.org');

      expect(await backend.setHost('  '), isTrue);

      expect(backend.host, BackendProvider.defaultHost);
      expect(
        await SharedPreferencesAsync().getString('transitous_host'),
        isNull,
      );
    });
  });

  group('setting the Nominatim host', () {
    test('keeps a pasted address as its host', () async {
      final backend = BackendProvider();

      expect(
        await backend.setNominatimHost('https://nominatim.example.org/'),
        isTrue,
      );
      expect(backend.nominatimHost, 'nominatim.example.org');
    });

    test('refuses what is not a host', () async {
      final backend = BackendProvider();

      expect(await backend.setNominatimHost('nominatim/lookup'), isFalse);
      expect(backend.nominatimHost, NominatimClient.defaultHost);
      expect(
        await SharedPreferencesAsync().getString('nominatim_host'),
        isNull,
      );
    });
  });

  group('a stored host from before hosts were checked', () {
    void store(String routing, String nominatim) {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'transitous_host': routing,
            'nominatim_host': nominatim,
          });
    }

    test('that is no host falls back to the default', () async {
      store('motis example/api', 'https://nominatim.example.org/lookup');

      final backend = await BackendProvider.load();

      expect(backend.host, BackendProvider.defaultHost);
      expect(backend.nominatimHost, NominatimClient.defaultHost);
    });

    test('pasted as an address is read as its host', () async {
      store('https://Motis.Example.org/', 'https://nominatim.example.org');

      final backend = await BackendProvider.load();

      expect(backend.host, 'motis.example.org');
      expect(backend.nominatimHost, 'nominatim.example.org');
    });
  });
}
