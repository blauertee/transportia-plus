import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/utils/trip_link.dart';

/// Shaped like a real id: base64 with every character that needs escaping.
const _id = 'CmEh+w/UoXI9CSkA=';

void main() {
  group('building', () {
    const link = TripLink(itineraryId: _id, host: 'api.transitous.org');

    test('the app link carries the id and the server', () {
      final uri = link.appLink;
      expect(uri.scheme, 'motis');
      expect(uri.host, 'trip');
      expect(uri.queryParameters['itineraryId'], _id);
      expect(uri.queryParameters['host'], 'api.transitous.org');
      // Escaped, so a messenger cannot cut the link at a `/` or `=`.
      expect(uri.toString(), isNot(contains('+')));
    });

    test('the web link opens the server\'s own web app', () {
      final uri = link.webLink!;
      expect(uri.scheme, 'https');
      expect(uri.host, 'api.transitous.org');
      expect(uri.path, '/');
      expect(uri.queryParameters['itineraryId'], _id);
    });

    test('the share link is https, on the share page', () {
      final uri = link.shareLink;
      expect(uri.scheme, 'https');
      expect(uri.host, 'blauertee.github.io');
      expect(uri.path, '/fw/');
      expect(uri.queryParameters['itineraryId'], _id);
      expect(uri.queryParameters['host'], 'api.transitous.org');
      expect(uri.toString(), isNot(contains('+')));
    });

    test('a link without a server has no web link', () {
      const bare = TripLink(itineraryId: _id);
      expect(bare.webLink, isNull);
      expect(bare.appLink.queryParameters.containsKey('host'), isFalse);
    });
  });

  group('reading', () {
    test('reads back what it built', () {
      const link = TripLink(itineraryId: _id, host: 'api.transitous.org');
      final read = TripLink.tryParse(Uri.parse(link.appLink.toString()))!;
      expect(read.itineraryId, _id);
      expect(read.host, 'api.transitous.org');
    });

    test('a + that came back as a space is a + again', () {
      final uri = Uri.parse('motis://trip?itineraryId=CmEh+w/UoXI9CSkA=');
      expect(TripLink.tryParse(uri)!.itineraryId, _id);
    });

    test('reads back the share link it built', () {
      const link = TripLink(itineraryId: _id, host: 'api.transitous.org');
      final read = TripLink.tryParse(Uri.parse(link.shareLink.toString()))!;
      expect(read.itineraryId, _id);
      expect(read.host, 'api.transitous.org');
    });

    for (final path in ['/fw', '/fw/', '/fw/index.html']) {
      test('reads the share page at $path', () {
        final uri = Uri.parse(
          'https://blauertee.github.io$path?itineraryId=abc&host=api.transitous.org',
        );
        expect(TripLink.tryParse(uri)!.itineraryId, 'abc');
      });
    }

    test('a + that came back as a space is a + on the share page too', () {
      final uri = Uri.parse(
        'https://blauertee.github.io/fw/?itineraryId=CmEh+w/UoXI9CSkA=',
      );
      expect(TripLink.tryParse(uri)!.itineraryId, _id);
    });

    test('Transportia\'s own scheme is still read', () {
      final uri = Uri.parse('transportia://trip?itineraryId=abc');
      expect(TripLink.tryParse(uri)!.itineraryId, 'abc');
    });

    test('a server with a port is kept, lower-cased', () {
      final uri = Uri.parse(
        'motis://trip?itineraryId=abc&host=MOTIS.Example:8080',
      );
      expect(TripLink.tryParse(uri)!.host, 'motis.example:8080');
    });

    test('no server means the rider\'s own', () {
      final uri = Uri.parse('motis://trip?itineraryId=abc');
      expect(TripLink.tryParse(uri)!.host, isNull);
    });

    for (final (why, link) in [
      ('another scheme', 'https://trip?itineraryId=abc'),
      ('another path', 'motis://stop?itineraryId=abc'),
      ('no id', 'motis://trip?host=api.transitous.org'),
      ('an empty id', 'motis://trip?itineraryId='),
      (
        'a server with a path',
        'motis://trip?itineraryId=a&host=evil.example/x',
      ),
      (
        'a server with credentials',
        'motis://trip?itineraryId=a&host=u@evil.example',
      ),
      (
        'a server with a scheme',
        'motis://trip?itineraryId=a&host=http://evil.example',
      ),
      (
        'the share page over http',
        'http://blauertee.github.io/fw/?itineraryId=a',
      ),
      ('a neighbouring path', 'https://blauertee.github.io/fwx?itineraryId=a'),
      (
        'another page on the domain',
        'https://blauertee.github.io/other/?itineraryId=a',
      ),
      (
        'a lookalike domain',
        'https://blauertee.github.io.evil.example/fw/?itineraryId=a',
      ),
      ('the path on another domain', 'https://evil.example/fw/?itineraryId=a'),
      ('another port', 'https://blauertee.github.io:8443/fw/?itineraryId=a'),
      (
        'no id on the share page',
        'https://blauertee.github.io/fw/?host=api.transitous.org',
      ),
    ]) {
      test('is refused with $why', () {
        expect(TripLink.tryParse(Uri.parse(link)), isNull);
      });
    }
  });
}
