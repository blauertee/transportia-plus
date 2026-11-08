import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/api/motis_request_log.dart';
import 'package:transportia/providers/theme_provider.dart';

/// Literal, as a released build will have written it.
const String _logMotisRequests = 'log_motis_requests';

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
  tearDown(() => MotisRequestLog.enabled = false);

  test('requests are not logged unless asked for', () async {
    final provider = await _loaded();

    expect(provider.logMotisRequests, isFalse);
    expect(MotisRequestLog.enabled, isFalse);
  });

  test('a stored "on" turns the log on at start', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({_logMotisRequests: true});

    final provider = await _loaded();

    expect(provider.logMotisRequests, isTrue);
    expect(MotisRequestLog.enabled, isTrue);
  });

  test('turning it on is stored, announced and reaches the log', () async {
    final provider = await _loaded();
    var notified = 0;
    provider.addListener(() => notified++);

    await provider.setLogMotisRequests(true);

    expect(provider.logMotisRequests, isTrue);
    expect(MotisRequestLog.enabled, isTrue);
    expect(notified, 1);
    expect(await SharedPreferencesAsync().getBool(_logMotisRequests), isTrue);
  });
}
