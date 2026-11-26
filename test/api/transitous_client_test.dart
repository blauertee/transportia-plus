import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transportia/api/transitous_api_exception.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/api/transitous_endpoint.dart';

TransitousClient _clientReturning(
  Future<http.Response> Function(http.Request request) handler, {
  Duration timeout = const Duration(seconds: 30),
}) {
  return TransitousClient(httpClient: MockClient(handler), timeout: timeout);
}

http.Response _json(Object body, {int status = 200}) => http.Response(
  json.encode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('uriFor', () {
    final client = _clientReturning((_) async => _json(const {}));

    test('builds /api/<version>/<path> against the configured host', () {
      final uri = client.uriFor(TransitousEndpoint.plan, const {});
      expect(uri.scheme, 'https');
      expect(uri.host, 'api.transitous.org');
      expect(uri.path, '/api/v6/plan');
    });

    test('uses the fixed version for endpoints pinned below the main one', () {
      expect(
        client.uriFor(TransitousEndpoint.geocode, const {}).path,
        '/api/v1/geocode',
      );
      expect(
        client.uriFor(TransitousEndpoint.mapRoutes, const {}).path,
        '/api/experimental/map/routes',
      );
    });

    test('drops null parameters instead of sending empty values', () {
      final uri = client.uriFor(TransitousEndpoint.plan, const {
        'fromPlace': '52.520000,13.405000',
        'arriveBy': null,
      });
      expect(uri.queryParameters, {'fromPlace': '52.520000,13.405000'});
      expect(uri.query, isNot(contains('arriveBy')));
    });
  });

  group('get', () {
    test('parses a successful response', () async {
      final client = _clientReturning(
        (_) async => _json(const {'itineraries': <Object>[]}),
      );
      final result = await client.get(
        TransitousEndpoint.plan,
        const {},
        (json) => (json as Map<String, dynamic>)['itineraries'] as List,
      );
      expect(result, isEmpty);
    });

    test('sends the app user agent and accept headers', () async {
      late http.Request seen;
      final client = _clientReturning((request) async {
        seen = request;
        return _json(const {});
      });
      await client.get(TransitousEndpoint.health, const {}, (json) => json);
      expect(seen.headers['accept'], 'application/json');
      expect(seen.headers['User-Agent'], contains('Transportia'));
    });

    test('surfaces the MOTIS error body rather than the status code', () async {
      final client = _clientReturning(
        (_) async => _json(const {
          'error': 'enum RealtimeModeEnum: unknown value FULL',
        }, status: 500),
      );
      await expectLater(
        client.get(TransitousEndpoint.plan, const {}, (json) => json),
        throwsA(
          isA<TransitousApiException>()
              .having(
                (e) => e.message,
                'message',
                'enum RealtimeModeEnum: unknown value FULL',
              )
              .having((e) => e.statusCode, 'statusCode', 500),
        ),
      );
    });

    test('falls back to the status code when the body has no error', () async {
      final client = _clientReturning((_) async => http.Response('nope', 503));
      await expectLater(
        client.get(TransitousEndpoint.plan, const {}, (json) => json),
        throwsA(
          isA<TransitousApiException>().having(
            (e) => e.message,
            'message',
            'Unexpected status 503',
          ),
        ),
      );
    });

    test('reports malformed JSON as such', () async {
      final client = _clientReturning((_) async => http.Response('{oops', 200));
      await expectLater(
        client.get(TransitousEndpoint.plan, const {}, (json) => json),
        throwsA(
          isA<TransitousApiException>().having(
            (e) => e.message,
            'message',
            'Response was not valid JSON',
          ),
        ),
      );
    });

    test('wraps parser failures instead of leaking a cast error', () async {
      final client = _clientReturning((_) async => _json(const []));
      await expectLater(
        client.get(
          TransitousEndpoint.plan,
          const {},
          (json) => (json as Map<String, dynamic>)['nope'],
        ),
        throwsA(
          isA<TransitousApiException>().having(
            (e) => e.message,
            'message',
            'Unexpected payload from API',
          ),
        ),
      );
    });

    test('times out rather than hanging forever', () async {
      final client = _clientReturning(
        (_) =>
            Future.delayed(const Duration(seconds: 5), () => _json(const {})),
        timeout: const Duration(milliseconds: 50),
      );
      await expectLater(
        client.get(TransitousEndpoint.plan, const {}, (json) => json),
        throwsA(
          isA<TransitousApiException>()
              .having((e) => e.isTimeout, 'isTimeout', isTrue)
              .having((e) => e.statusCode, 'statusCode', isNull),
        ),
      );
    });

    test('wraps transport failures', () async {
      final client = _clientReturning(
        (_) async => throw const SocketExceptionStub(),
      );
      await expectLater(
        client.get(TransitousEndpoint.plan, const {}, (json) => json),
        throwsA(
          isA<TransitousApiException>()
              .having((e) => e.message, 'message', contains('Could not reach'))
              .having((e) => e.isTimeout, 'isTimeout', isFalse),
        ),
      );
    });
  });

  group('post', () {
    test('sends a JSON body and parses the response', () async {
      late http.Request seen;
      final client = _clientReturning((request) async {
        seen = request;
        return _json(const {'transfers': 2});
      });

      final result = await client.post(
        TransitousEndpoint.refreshItinerary,
        const {'withFares': 'true'},
        const {'legs': <Object>[]},
        (json) => (json as Map<String, dynamic>)['transfers'] as int,
      );

      expect(result, 2);
      expect(seen.method, 'POST');
      expect(seen.headers['content-type'], contains('application/json'));
      expect(json.decode(seen.body), {'legs': <Object>[]});
      expect(seen.url.queryParameters, {'withFares': 'true'});
    });
  });

  group('a host that is no host', () {
    // Possible only from a value stored before hosts were checked, or a
    // caller passing one in; either way it must fail as a request does.
    test('fails the request rather than throwing at the caller', () async {
      var sent = false;
      final client = _clientReturning((_) async {
        sent = true;
        return _json(const {});
      });

      // Not thrown here, synchronously, where a caller awaiting a Future
      // has no handler.
      final request = client.get(
        TransitousEndpoint.plan,
        const {},
        (json) => json,
        host: 'https://motis.example.org',
      );

      await expectLater(request, throwsA(isA<TransitousApiException>()));
      expect(sent, isFalse);
    });
  });
}

/// Stands in for a transport-level failure without depending on `dart:io`,
/// which is unavailable on the web target.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
