import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/quick_access_layout.dart';
import 'package:transportia/services/quick_access_service.dart';

/// Literal, as a released build will have written it.
const String _key = 'quick_access_layout';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    QuickAccessService.invalidate();
  });

  test('the defaults until something is saved', () async {
    final layout = await QuickAccessService.load();
    expect(layout.toJson(), QuickAccessLayout.defaults.toJson());
  });

  test('a saved layout is announced and read back', () async {
    final renamed = QuickAccessLayout.defaults.withStreetGroup(
      QuickAccessLayout.defaults.street.first.copyWith(title: 'On foot'),
    );
    await QuickAccessService.save(renamed);
    expect(
      QuickAccessService.layoutListenable.value.street.first.title,
      'On foot',
    );

    QuickAccessService.invalidate();
    final read = await QuickAccessService.load();
    expect(read.street.first.title, 'On foot');
  });

  test('reset forgets the stored layout', () async {
    await QuickAccessService.save(
      QuickAccessLayout.defaults.moveTransit(
        QuickAccessLayout.defaults.transit.first.items.first,
        QuickAccessLayout.otherId,
      ),
    );
    await QuickAccessService.reset();
    expect(await SharedPreferencesAsync().getString(_key), isNull);
    expect(
      QuickAccessService.layoutListenable.value.toJson(),
      QuickAccessLayout.defaults.toJson(),
    );
  });

  test('unreadable storage is the defaults, not an error', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({_key: '{not json'});
    final layout = await QuickAccessService.load();
    expect(layout.toJson(), QuickAccessLayout.defaults.toJson());
  });
}
