import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/services/stored_list_store.dart';

const String _key = 'test_list';

StoredListStore<String> _store() => StoredListStore(
  key: _key,
  fromJson: (json) => json['v'] as String,
  toJson: (value) => {'v': value},
);

void _seed(String raw) {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData({_key: raw});
}

Future<String?> _raw() => SharedPreferencesAsync().getString(_key);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('changes made at once', () {
    test('all land, in the order they were asked for', () async {
      final store = _store();
      await Future.wait([
        for (final value in ['a', 'b', 'c'])
          store.update((list) => (list..add(value)).isNotEmpty),
      ]);

      expect(await store.read(), ['a', 'b', 'c']);
    });

    test('take turns across two stores on the same key', () async {
      await Future.wait([
        _store().update((list) => (list..add('a')).isNotEmpty),
        _store().update((list) => (list..add('b')).isNotEmpty),
      ]);

      expect(await _store().read(), ['a', 'b']);
    });

    test('a change that fails does not hold up the next', () async {
      final store = _store();
      final failing = store.update((_) => throw StateError('no'));
      final next = store.update((list) => (list..add('b')).isNotEmpty);

      await expectLater(failing, throwsStateError);
      await next;
      expect(await store.read(), ['b']);
    });

    test('a clear lands between the changes around it', () async {
      final store = _store();
      await Future.wait([
        store.update((list) => (list..add('a')).isNotEmpty),
        store.clear(),
        store.update((list) => (list..add('b')).isNotEmpty),
      ]);

      expect(await store.read(), ['b']);
    });
  });

  group('a change', () {
    test('that says so writes nothing', () async {
      _seed('[{"v":"a"}]');
      final written = await _store().update((list) {
        list.add('b');
        return false;
      });

      expect(written, isNull);
      expect(await _raw(), '[{"v":"a"}]');
    });

    test('returns the list as written', () async {
      final written = await _store().update(
        (list) => (list..add('a')).isNotEmpty,
      );
      expect(written, ['a']);
      expect(jsonDecode((await _raw())!), [
        {'v': 'a'},
      ]);
    });
  });

  group('a stored value this build cannot read', () {
    for (final (what, raw) in [
      ('text that is not JSON', '[{"v":"a"},'),
      ('JSON that is not a list', '{"v":"a"}'),
    ]) {
      test('as $what is refused a write, and kept', () async {
        _seed(raw);

        await expectLater(
          _store().update((list) => (list..add('b')).isNotEmpty),
          throwsA(isA<StoredListUnreadable>()),
        );
        expect(await _raw(), raw);
      });

      test('as $what shows as empty', () async {
        _seed(raw);
        expect(await _store().read(), isEmpty);
      });
    }

    test('does not hold up changes to other keys', () async {
      _seed('not json');
      final other = StoredListStore<String>(
        key: 'other_list',
        fromJson: (json) => json['v'] as String,
        toJson: (value) => {'v': value},
      );

      await expectLater(
        _store().update((list) => true),
        throwsA(isA<StoredListUnreadable>()),
      );
      expect(await other.update((list) => (list..add('a')).isNotEmpty), ['a']);
    });
  });
}
