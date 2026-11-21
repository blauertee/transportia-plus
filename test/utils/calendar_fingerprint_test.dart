import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/utils/calendar_fingerprint.dart';

String _print({
  String title = 'Home → Airport',
  String description = '16:25  RE7',
  int start = 1000,
  int end = 2000,
}) => calendarEventFingerprint(
  title: title,
  description: description,
  startMillis: start,
  endMillis: end,
);

void main() {
  test('the same event gives the same fingerprint', () {
    expect(_print(), _print());
  });

  test('any change to what was written changes it', () {
    final original = _print();

    expect(_print(title: 'Home → Airport!'), isNot(original));
    expect(_print(description: '16:25  RE7\nPassport'), isNot(original));
    expect(_print(start: 1001), isNot(original));
    expect(_print(end: 2001), isNot(original));
  });

  test('text moved from one field into the next changes it', () {
    expect(
      _print(title: 'ab', description: 'c'),
      isNot(_print(title: 'a', description: 'bc')),
    );
  });

  test('empty fields still fingerprint', () {
    expect(_print(title: '', description: ''), isNotEmpty);
  });
}
