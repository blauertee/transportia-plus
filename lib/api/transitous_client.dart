import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../environment.dart';
import '../models/motis_request_record.dart';
import 'motis_request_log.dart';
import 'transitous_api_exception.dart';
import 'transitous_endpoint.dart';

/// Decodes a successful response body into a model.
typedef ResponseParser<T> = T Function(dynamic json);

/// The single place in the app that performs MOTIS HTTP requests.
///
/// Centralising this buys three things the previous per-service `http.get`
/// calls did not have: a request timeout, MOTIS's `{"error": "..."}` body
/// surfaced instead of a bare status code, and an injectable [http.Client] so
/// endpoints can be tested without a network.
class TransitousClient {
  TransitousClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
  }) : _http = httpClient ?? http.Client();

  /// Client used by the app. Tests replace this with one wrapping a
  /// `MockClient` and restore it afterwards.
  static TransitousClient instance = TransitousClient();

  final http.Client _http;
  final Duration timeout;

  /// [host] sends this one request somewhere other than the rider's server:
  /// a shared trip has to be read back on the server that planned it.
  Future<T> get<T>(
    TransitousEndpoint endpoint,
    Map<String, String?> query,
    ResponseParser<T> parse, {
    String? host,
  }) {
    final uri = uriFor(endpoint, query, host: host);
    final headers = Environment.transitousHeaders();
    return _send(
      endpoint,
      uri,
      parse,
      () => _http.get(uri, headers: headers),
      method: 'GET',
      headers: headers,
    );
  }

  /// POST variant, needed where a parameter is too large for a URL.
  ///
  /// `/refresh-itinerary` is the real case: its `itineraryId` runs to roughly
  /// 1.3 KB, which overflows common URL limits once other parameters are added.
  Future<T> post<T>(
    TransitousEndpoint endpoint,
    Map<String, String?> query,
    Object body,
    ResponseParser<T> parse,
  ) {
    final uri = uriFor(endpoint, query);
    final headers = {
      ...Environment.transitousHeaders(),
      'content-type': 'application/json',
    };
    final encoded = json.encode(body);
    return _send(
      endpoint,
      uri,
      parse,
      () => _http.post(uri, headers: headers, body: encoded),
      method: 'POST',
      headers: headers,
      body: encoded,
    );
  }

  /// Builds the request URI, dropping null parameters so an unset option is
  /// absent rather than sent as an empty string.
  Uri uriFor(
    TransitousEndpoint endpoint,
    Map<String, String?> query, {
    String? host,
  }) {
    final params = <String, String>{
      for (final entry in query.entries)
        if (entry.value != null) entry.key: entry.value!,
    };
    return Uri.https(
      host ?? Environment.transitousHost,
      Environment.pathFor(endpoint),
      params.isEmpty ? null : params,
    );
  }

  /// Sends the request, recording it in the [MotisRequestLog] while that
  /// is on: as pending at once, then with what came back.
  Future<T> _send<T>(
    TransitousEndpoint endpoint,
    Uri uri,
    ResponseParser<T> parse,
    Future<http.Response> Function() send, {
    required String method,
    required Map<String, String> headers,
    String? body,
  }) async {
    final pending = MotisRequestRecord(
      endpoint: endpoint,
      method: method,
      uri: uri,
      headers: headers,
      body: body,
      sentAt: DateTime.now(),
    );
    final logged = MotisRequestLog.add(pending);
    final stopwatch = Stopwatch()..start();
    int? statusCode;
    try {
      final result = await _exchange(endpoint, uri, parse, send, (status) {
        statusCode = status;
      });
      if (logged) {
        MotisRequestLog.replace(
          pending,
          pending.finished(duration: stopwatch.elapsed, statusCode: statusCode),
        );
      }
      return result;
    } on TransitousApiException catch (e) {
      if (logged) {
        MotisRequestLog.replace(
          pending,
          pending.finished(
            duration: stopwatch.elapsed,
            statusCode: e.statusCode,
            error: e.message,
          ),
        );
      }
      rethrow;
    }
  }

  Future<T> _exchange<T>(
    TransitousEndpoint endpoint,
    Uri uri,
    ResponseParser<T> parse,
    Future<http.Response> Function() send,
    void Function(int statusCode) onStatus,
  ) async {
    final http.Response response;
    try {
      response = await send().timeout(
        timeout,
        onTimeout: () => throw TransitousTimeoutException(timeout),
      );
    } on TransitousTimeoutException catch (e) {
      throw TransitousApiException(
        'Request timed out after ${timeout.inSeconds}s',
        uri: uri,
        cause: e,
      );
    } catch (e, stackTrace) {
      developer.log(
        'Request failed: ${endpoint.name}',
        name: 'TransitousClient',
        error: e,
        stackTrace: stackTrace,
      );
      throw TransitousApiException(
        'Could not reach ${uri.authority}',
        uri: uri,
        cause: e,
      );
    }

    onStatus(response.statusCode);
    if (response.statusCode != 200) {
      final message = _errorMessage(response);
      developer.log(
        '${endpoint.name} -> ${response.statusCode}: $message',
        name: 'TransitousClient',
      );
      throw TransitousApiException(
        message,
        statusCode: response.statusCode,
        uri: uri,
      );
    }

    final dynamic decoded;
    try {
      decoded = json.decode(response.body);
    } catch (e) {
      throw TransitousApiException(
        'Response was not valid JSON',
        statusCode: response.statusCode,
        uri: uri,
        cause: e,
      );
    }

    try {
      return parse(decoded);
    } catch (e, stackTrace) {
      developer.log(
        'Could not parse ${endpoint.name} response',
        name: 'TransitousClient',
        error: e,
        stackTrace: stackTrace,
      );
      throw TransitousApiException(
        'Unexpected payload from API',
        statusCode: response.statusCode,
        uri: uri,
        cause: e,
      );
    }
  }

  /// MOTIS reports failures as `{"error": "..."}`; those messages name the
  /// actual problem, so prefer them over the status code.
  String _errorMessage(http.Response response) {
    try {
      final decoded = json.decode(response.body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.isNotEmpty) return error;
      }
    } catch (_) {
      // Fall through to the generic message below.
    }
    return 'Unexpected status ${response.statusCode}';
  }

  void close() => _http.close();
}
