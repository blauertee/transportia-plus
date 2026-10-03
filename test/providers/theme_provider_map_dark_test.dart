import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/providers/theme_provider.dart';

/// Literal, as a released build will have written it.
const String _mapStyle = 'map_style';

Future<ThemeProvider> _loadedWith(String? style) async {
  SharedPreferencesAsyncPlatform.instance = style == null
      ? InMemorySharedPreferencesAsync.empty()
      : InMemorySharedPreferencesAsync.withData({_mapStyle: style});
  final provider = ThemeProvider();
  while (!provider.isInitialized) {
    await Future<void>.delayed(Duration.zero);
  }
  return provider;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the default and light maps are light', () async {
    expect((await _loadedWith(null)).isMapDark, isFalse);
    expect((await _loadedWith('default')).isMapDark, isFalse);
    expect((await _loadedWith('light')).isMapDark, isFalse);
  });

  test('only the dark map is dark', () async {
    expect((await _loadedWith('dark')).isMapDark, isTrue);
  });
}
