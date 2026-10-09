import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/providers/theme_provider.dart';

/// Literal, as a released build will have written it.
const String _showNearbyDepartures = 'show_nearby_departures';

Future<ThemeProvider> _loaded() async {
  final provider = ThemeProvider();
  while (!provider.isInitialized) {
    await Future<void>.delayed(Duration.zero);
  }
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('departures near you are listed unless switched off', () async {
    final provider = await _loaded();

    expect(provider.showNearbyDepartures, isTrue);
  });

  test('a stored "off" is honoured', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({_showNearbyDepartures: false});

    final provider = await _loaded();

    expect(provider.showNearbyDepartures, isFalse);
  });

  test('switching it off is stored and announced', () async {
    final provider = await _loaded();
    var notified = 0;
    provider.addListener(() => notified++);

    await provider.setShowNearbyDepartures(false);

    expect(provider.showNearbyDepartures, isFalse);
    expect(notified, 1);
    expect(
      await SharedPreferencesAsync().getBool(_showNearbyDepartures),
      isFalse,
    );
  });

  test('setting the same value again does nothing', () async {
    final provider = await _loaded();
    var notified = 0;
    provider.addListener(() => notified++);

    await provider.setShowNearbyDepartures(true);

    expect(notified, 0);
  });
}
