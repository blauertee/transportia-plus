import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/utils/host_input.dart';

void main() {
  test('a pasted address really would break a request', () {
    // Why hosts are checked at all: `Uri.https` throws on the address a
    // rider is most likely to paste.
    expect(
      () => Uri.https('https://motis.example.org', '/'),
      throwsFormatException,
    );
    expect(() => Uri.https('motis.example.org/', '/'), throwsFormatException);
  });

  group('isValidHost', () {
    for (final host in [
      'api.transitous.org',
      'localhost',
      'motis-1.example.org',
      'motis.example.org:8080',
      'x:1',
      'x:65535',
      '192.168.1.10:8080',
    ]) {
      test('takes $host', () => expect(isValidHost(host), isTrue));
    }

    for (final host in [
      '',
      'https://motis.example.org',
      'motis.example.org/',
      'motis.example.org/api',
      'motis example.org',
      'user@motis.example.org',
      '-motis.example.org',
      'motis-.example.org',
      'motis..example.org',
      'motis.example.org:',
      'motis.example.org:0',
      'motis.example.org:65536',
      'motis.example.org:123456',
      '[::1]',
    ]) {
      test('refuses "$host"', () => expect(isValidHost(host), isFalse));
    }
  });

  group('normalizeHost', () {
    test('keeps a bare host as it is', () {
      expect(normalizeHost('motis.example.org'), 'motis.example.org');
    });

    test('takes a pasted https address down to its host and port', () {
      expect(
        normalizeHost('  HTTPS://Motis.Example.org:8080/ '),
        'motis.example.org:8080',
      );
      expect(normalizeHost('https://motis.example.org'), 'motis.example.org');
      expect(normalizeHost('motis.example.org/'), 'motis.example.org');
    });

    test('refuses plain http rather than quietly asking over https', () {
      expect(normalizeHost('http://motis.example.org'), isNull);
      expect(isPlainHttpAddress(' HTTP://motis.example.org'), isTrue);
      expect(isPlainHttpAddress('https://motis.example.org'), isFalse);
    });

    test('refuses an address with a path, not cutting it off', () {
      expect(normalizeHost('https://motis.example.org/api/'), isNull);
    });

    test('refuses what is empty once trimmed', () {
      expect(normalizeHost(''), isNull);
      expect(normalizeHost('   '), isNull);
      expect(normalizeHost('https://'), isNull);
      expect(normalizeHost('/'), isNull);
    });
  });
}
