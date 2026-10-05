import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transportia/api/nominatim_client.dart';
import 'package:transportia/models/place_details.dart';

const _rewe = OsmRef('N', 318349843);
const _kadewe = OsmRef('W', 60541581);

/// A client over [handler], recording what it asked and how long it waited.
({NominatimClient client, List<http.Request> requests, List<Duration> waits})
_client(Future<http.Response> Function(http.Request) handler) {
  final requests = <http.Request>[];
  final waits = <Duration>[];
  final client = NominatimClient(
    httpClient: MockClient((request) {
      requests.add(request);
      return handler(request);
    }),
    wait: (d) async => waits.add(d),
  );
  return (client: client, requests: requests, waits: waits);
}

http.Response _fixture(String name) => http.Response(
  File('test/fixtures/nominatim/$name').readAsStringSync(),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('asks for the element with its address and tags', () async {
    final c = _client((_) async => _fixture('lookup_rewe.json'));

    final details = await c.client.lookup(_rewe);

    final url = c.requests.single.url;
    expect(url.host, 'nominatim.openstreetmap.org');
    expect(url.path, '/lookup');
    expect(url.queryParameters, {
      'osm_ids': 'N318349843',
      'format': 'jsonv2',
      'extratags': '1',
      'addressdetails': '1',
    });
    expect(details?.openingHours, 'Mo-Sa 07:00-23:30');
  });

  test('says which app is asking', () async {
    final c = _client((_) async => _fixture('lookup_rewe.json'));

    await c.client.lookup(_rewe);

    // Nominatim's policy blocks stock library User-Agents.
    expect(
      c.requests.single.headers['User-Agent'],
      startsWith('Transportia+/'),
    );
  });

  test('asks the configured server', () async {
    final c = _client((_) async => _fixture('lookup_rewe.json'));

    await c.client.lookup(_rewe, host: 'nominatim.example.org');

    expect(c.requests.single.url.host, 'nominatim.example.org');
  });

  test('a place asked about twice is asked once', () async {
    final c = _client((_) async => _fixture('lookup_rewe.json'));

    await c.client.lookup(_rewe);
    final again = await c.client.lookup(_rewe);

    expect(c.requests, hasLength(1));
    expect(again?.phone, '+49 30 44342306');
  });

  test('a different server is a different answer', () async {
    final c = _client((_) async => _fixture('lookup_rewe.json'));

    await c.client.lookup(_rewe);
    await c.client.lookup(_rewe, host: 'nominatim.example.org');

    expect(c.requests, hasLength(2));
  });

  test('waits out a second between requests', () async {
    final c = _client(
      (r) async => _fixture(
        r.url.queryParameters['osm_ids'] == 'N318349843'
            ? 'lookup_rewe.json'
            : 'lookup_kadewe.json',
      ),
    );
    var clock = DateTime.utc(2026, 9, 28, 12);
    DateTime now() => clock;

    await c.client.lookup(_rewe, now: now);
    clock = clock.add(const Duration(milliseconds: 300));
    await c.client.lookup(_kadewe, now: now);

    expect(c.waits, [const Duration(milliseconds: 700)]);
  });

  test('no wait when a second has passed', () async {
    final c = _client((_) async => _fixture('lookup_rewe.json'));
    var clock = DateTime.utc(2026, 9, 28, 12);
    DateTime now() => clock;

    await c.client.lookup(_rewe, now: now);
    clock = clock.add(const Duration(seconds: 2));
    await c.client.lookup(_kadewe, now: now);

    expect(c.waits, isEmpty);
  });

  test('a server error is no details, not a crash', () async {
    final c = _client((_) async => http.Response('busy', 503));

    expect(await c.client.lookup(_rewe), isNull);
  });

  test('a failure does not stop what is queued behind it', () async {
    var calls = 0;
    final c = _client((_) async {
      calls++;
      if (calls == 1) throw const SocketException('offline');
      return _fixture('lookup_kadewe.json');
    });

    final first = c.client.lookup(_rewe);
    final second = c.client.lookup(_kadewe);

    expect(await first, isNull);
    expect((await second)?.street, 'Tauentzienstraße 21-24');
  });

  test('an element Nominatim does not know is no details', () async {
    final c = _client((_) async => http.Response('[]', 200));

    expect(await c.client.lookup(_rewe), isNull);
  });

  test('an element with nothing worth showing is no details', () async {
    final c = _client(
      (_) async => http.Response('[{"address":{},"extratags":{}}]', 200),
    );

    expect(await c.client.lookup(_rewe), isNull);
  });

  test('a garbled answer is no details', () async {
    final c = _client((_) async => http.Response('<html>', 200));

    expect(await c.client.lookup(_rewe), isNull);
  });
}
