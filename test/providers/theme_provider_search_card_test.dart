import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/providers/theme_provider.dart';

/// Literal, as a released build will have written them.
const String _searchOptionsOpening = 'search_options_opening';
const String _showCalories = 'show_calories';

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

  group('search options opening', () {
    test('closed unless chosen otherwise', () async {
      final provider = await _loaded();
      expect(provider.searchOptionsOpening, SearchOptionsOpening.closed);
    });

    test('a stored choice is honoured', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            _searchOptionsOpening: 'everything',
          });
      final provider = await _loaded();
      expect(provider.searchOptionsOpening, SearchOptionsOpening.everything);
    });

    test('a name this build does not know falls back to closed', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            _searchOptionsOpening: 'halfway',
          });
      final provider = await _loaded();
      expect(provider.searchOptionsOpening, SearchOptionsOpening.closed);
    });

    test('a new choice is stored and announced', () async {
      final provider = await _loaded();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setSearchOptionsOpening(SearchOptionsOpening.stagesOpen);
      await provider.setSearchOptionsOpening(SearchOptionsOpening.stagesOpen);

      expect(notified, 1);
      expect(
        await SharedPreferencesAsync().getString(_searchOptionsOpening),
        'stagesOpen',
      );
    });
  });

  group('calories', () {
    test('hidden unless turned on', () async {
      final provider = await _loaded();
      expect(provider.showCalories, isFalse);
    });

    test('a stored "on" is honoured', () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({_showCalories: true});
      final provider = await _loaded();
      expect(provider.showCalories, isTrue);
    });

    test('turning them on is stored and announced', () async {
      final provider = await _loaded();
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.setShowCalories(true);

      expect(notified, 1);
      expect(await SharedPreferencesAsync().getBool(_showCalories), isTrue);
    });
  });
}
