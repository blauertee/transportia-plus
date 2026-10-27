import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/providers/theme_provider.dart';

/// Literal, as a released build will have written it.
const String _showGraphCopyButton = 'show_graph_copy_button';

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

  test('the graph has no copy button unless asked for', () async {
    final provider = await _loaded();

    expect(provider.showGraphCopyButton, isFalse);
  });

  test('a stored "on" is honoured', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({_showGraphCopyButton: true});

    final provider = await _loaded();

    expect(provider.showGraphCopyButton, isTrue);
  });

  test('turning it on is stored and announced', () async {
    final provider = await _loaded();
    var notified = 0;
    provider.addListener(() => notified++);

    await provider.setShowGraphCopyButton(true);

    expect(provider.showGraphCopyButton, isTrue);
    expect(notified, 1);
    expect(
      await SharedPreferencesAsync().getBool(_showGraphCopyButton),
      isTrue,
    );
  });
}
