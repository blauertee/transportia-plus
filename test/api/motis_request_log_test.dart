import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:transportia/api/motis_request_log.dart';
import 'package:transportia/api/transitous_api_exception.dart';
import 'package:transportia/api/transitous_client.dart';
import 'package:transportia/api/transitous_endpoint.dart';
import 'package:transportia/models/motis_request_record.dart';

TransitousClient _client(
  Future<http.Response> Function(http.Request request) handler,
) => TransitousClient(httpClient: MockClient(handler));

http.Response _json(Object body, {int status = 200}) => http.Response(
  json.encode(body),
  status,
  headers: {'content-type': 'application/json'},
);

MotisRequestRecord _record(int i) => MotisRequestRecord(
  endpoint: TransitousEndpoint.plan,
  method: 'GET',
  uri: Uri.parse('https://example.org/$i'),
  sentAt: DateTime.utc(2026, 11, 8),
);

void main() {
  setUp(() {
    MotisRequestLog.enabled = true;
    MotisRequestLog.clear();
  });
  tearDown(() {
    MotisRequestLog.enabled = false;
    MotisRequestLog.clear();
  });

  group('TransitousClient', () {
    test('logs a GET with its URL, headers and status', () async {
      final client = _client((_) async => _json(const {'ok': true}));

      await client.get(TransitousEndpoint.plan, const {
        'fromPlace': '52.5,13.4',
      }, (json) => json);

      final [record] = MotisRequestLog.records.value;
      expect(record.endpoint, TransitousEndpoint.plan);
      expect(record.method, 'GET');
      expect(record.uri.queryParameters, {'fromPlace': '52.5,13.4'});
      expect(record.headers['accept'], 'application/json');
      expect(record.body, isNull);
      expect(record.statusCode, 200);
      expect(record.isPending, isFalse);
      expect(record.isFailure, isFalse);
    });

    test('shows a request as pending until the response is in', () async {
      late MotisRequestRecord whileSending;
      final client = _client((_) async {
        whileSending = MotisRequestLog.records.value.single;
        return _json(const {});
      });

      await client.get(TransitousEndpoint.trip, const {}, (json) => json);

      expect(whileSending.isPending, isTrue);
      expect(MotisRequestLog.records.value.single.isPending, isFalse);
    });

    test('logs the body of a POST as it was sent', () async {
      final client = _client((_) async => _json(const {}));

      await client.post(TransitousEndpoint.refreshItinerary, const {}, const {
        'itineraryId': 'abc',
      }, (json) => json);

      final record = MotisRequestLog.records.value.single;
      expect(record.method, 'POST');
      expect(record.body, '{"itineraryId":"abc"}');
    });

    test('logs a server error with its status and message', () async {
      final client = _client(
        (_) async => _json(const {'error': 'unknown stop'}, status: 400),
      );

      await expectLater(
        client.get(TransitousEndpoint.plan, const {}, (json) => json),
        throwsA(isA<TransitousApiException>()),
      );

      final record = MotisRequestLog.records.value.single;
      expect(record.statusCode, 400);
      expect(record.error, 'unknown stop');
      expect(record.isFailure, isTrue);
    });

    test('logs a request that never got a response', () async {
      final client = _client((_) async => throw http.ClientException('down'));

      await expectLater(
        client.get(TransitousEndpoint.stopTimes, const {}, (json) => json),
        throwsA(isA<TransitousApiException>()),
      );

      final record = MotisRequestLog.records.value.single;
      expect(record.statusCode, isNull);
      expect(record.isFailure, isTrue);
    });

    test('logs nothing while logging is off', () async {
      MotisRequestLog.enabled = false;
      final client = _client((_) async => _json(const {}));

      await client.get(TransitousEndpoint.plan, const {}, (json) => json);

      expect(MotisRequestLog.records.value, isEmpty);
    });
  });

  group('MotisRequestLog', () {
    test('keeps the newest requests up to its capacity', () {
      for (var i = 0; i <= MotisRequestLog.capacity; i++) {
        MotisRequestLog.add(_record(i));
      }

      final records = MotisRequestLog.records.value;
      expect(records, hasLength(MotisRequestLog.capacity));
      expect(records.first.uri.path, '/${MotisRequestLog.capacity}');
      expect(records.last.uri.path, '/1');
    });

    test('drops a finished request that was cleared while in flight', () {
      final pending = _record(0);
      MotisRequestLog.add(pending);
      MotisRequestLog.clear();

      MotisRequestLog.replace(
        pending,
        pending.finished(duration: Duration.zero, statusCode: 200),
      );

      expect(MotisRequestLog.records.value, isEmpty);
    });
  });

  group('copyText', () {
    test('is the method and URL, then the headers', () {
      final record = MotisRequestRecord(
        endpoint: TransitousEndpoint.plan,
        method: 'GET',
        uri: Uri.parse('https://api.transitous.org/api/v5/plan?a=1'),
        headers: const {'accept': 'application/json'},
        sentAt: DateTime.utc(2026, 11, 8),
      );

      expect(
        record.copyText,
        'GET https://api.transitous.org/api/v5/plan?a=1\n'
        'accept: application/json',
      );
    });

    test('ends with the body, indented, after a blank line', () {
      final record = MotisRequestRecord(
        endpoint: TransitousEndpoint.refreshItinerary,
        method: 'POST',
        uri: Uri.parse('https://api.transitous.org/api/v5/refresh-itinerary'),
        body: '{"itineraryId":"abc"}',
        sentAt: DateTime.utc(2026, 11, 8),
      );

      expect(
        record.copyText,
        'POST https://api.transitous.org/api/v5/refresh-itinerary\n'
        '\n'
        '{\n  "itineraryId": "abc"\n}',
      );
    });
  });
}
