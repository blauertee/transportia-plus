import 'dart:convert';

import '../api/transitous_endpoint.dart';

/// One request the app sent to the MOTIS server, as it went out, with what
/// came back. Kept for the request log in the advanced settings.
class MotisRequestRecord {
  const MotisRequestRecord({
    required this.endpoint,
    required this.method,
    required this.uri,
    required this.sentAt,
    this.headers = const {},
    this.body,
    this.duration,
    this.statusCode,
    this.error,
  });

  final TransitousEndpoint endpoint;
  final String method;
  final Uri uri;
  final Map<String, String> headers;

  /// The JSON body of a POST, as sent. Null for a GET.
  final String? body;

  final DateTime sentAt;

  /// Null while the request is still in flight.
  final Duration? duration;

  /// Null when no response arrived: a timeout, or no connection.
  final int? statusCode;

  /// What went wrong, in the words the app showed the rider.
  final String? error;

  bool get isPending => duration == null;

  /// This request with its outcome filled in.
  MotisRequestRecord finished({
    required Duration duration,
    int? statusCode,
    String? error,
  }) => MotisRequestRecord(
    endpoint: endpoint,
    method: method,
    uri: uri,
    headers: headers,
    body: body,
    sentAt: sentAt,
    duration: duration,
    statusCode: statusCode,
    error: error,
  );
  bool get isFailure => error != null;

  /// The whole request as plain text: method and URL, headers, then the body
  /// if there is one. What the copy button puts on the clipboard.
  String get copyText {
    final lines = [
      '$method $uri',
      for (final header in headers.entries) '${header.key}: ${header.value}',
    ];
    final payload = body;
    if (payload != null) lines.addAll(['', _prettyJson(payload)]);
    return lines.join('\n');
  }

  /// [body] indented for reading, or as sent when it is not JSON.
  String? get prettyBody => body == null ? null : _prettyJson(body!);

  static String _prettyJson(String raw) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(raw));
    } catch (_) {
      return raw;
    }
  }
}
