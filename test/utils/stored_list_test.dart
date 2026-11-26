import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/utils/stored_list.dart';

/// Reads `{"n": <int>}`; throws on anything else, and skips negatives by
/// returning null — both ways a real parser turns an entry down.
int? _parse(Map<String, dynamic> json) {
  final n = json['n'] as int;
  return n < 0 ? null : n;
}

void main() {
  group('decodeStoredList', () {
    test('nothing stored is an empty list', () {
      expect(decodeStoredList(null, _parse), isEmpty);
      expect(decodeStoredList('', _parse), isEmpty);
    });

    test('reads every entry in order', () {
      expect(decodeStoredList('[{"n":1},{"n":2},{"n":3}]', _parse), [1, 2, 3]);
    });

    test('an entry the parser throws on costs only that entry', () {
      expect(decodeStoredList('[{"n":1},{"n":"two"},{"n":3}]', _parse), [1, 3]);
    });

    test('an entry the parser turns down costs only that entry', () {
      expect(decodeStoredList('[{"n":1},{"n":-2},{"n":3}]', _parse), [1, 3]);
    });

    test('an entry that is not an object is skipped', () {
      expect(decodeStoredList('[{"n":1},null,"x",[2],{"n":3}]', _parse), [
        1,
        3,
      ]);
    });

    test('every entry unreadable is an empty list', () {
      expect(decodeStoredList('[{"n":"a"},{}]', _parse), isEmpty);
    });

    test('a value that is not JSON reads as empty rather than throwing', () {
      expect(decodeStoredList('[{"n":1},', _parse), isEmpty);
    });

    test('JSON that is not an array reads as empty', () {
      expect(decodeStoredList('{"n":1}', _parse), isEmpty);
      expect(decodeStoredList('42', _parse), isEmpty);
    });

    test('the list can be changed and written back', () {
      final list = decodeStoredList('[{"n":1}]', _parse)..add(2);
      expect(list, [1, 2]);
    });
  });
}
