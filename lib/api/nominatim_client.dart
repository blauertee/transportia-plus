import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../environment.dart';
import '../models/place_details.dart';

/// Looks up what OpenStreetMap knows about a place, through Nominatim.
///
/// OpenStreetMap's own API is for editing and its policy rules out
/// read-only use; Nominatim's allows lookups a rider triggers in an app,
/// on its terms: an app-identifying User-Agent, at most one request a
/// second across every user, results cached, and a server the app can be
/// pointed away from without an update. This class keeps the first three;
/// the host is a setting.
class NominatimClient {
  NominatimClient({
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 5),
    this.minGap = const Duration(seconds: 1),
    Future<void> Function(Duration)? wait,
  }) : _http = httpClient ?? http.Client(),
       _wait = wait ?? ((d) => Future<void>.delayed(d));

  /// Swapped in tests for one serving fixtures.
  static NominatimClient instance = NominatimClient();

  static const String defaultHost = 'nominatim.openstreetmap.org';

  final http.Client _http;
  final Duration timeout;

  /// The time between two requests from this app; the policy's limit.
  final Duration minGap;
  final Future<void> Function(Duration) _wait;

  final Map<String, PlaceDetails?> _cache = {};

  /// Requests run one after another, each waiting out [minGap].
  Future<void> _queue = Future.value();
  DateTime? _lastSent;

  /// What [host] knows about [ref]; null when it knows nothing, or cannot
  /// be reached. A place asked about twice is asked once.
  Future<PlaceDetails?> lookup(
    OsmRef ref, {
    String host = defaultHost,
    DateTime Function() now = DateTime.now,
  }) {
    final key = '$host/${ref.lookupId}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    final result = _queue.then((_) => _send(ref, host, now));
    // One failure must not stop the requests queued behind it.
    _queue = result.then((_) {}, onError: (_) {});
    return result.then((details) {
      _cache[key] = details;
      return details;
    });
  }

  Future<PlaceDetails?> _send(
    OsmRef ref,
    String host,
    DateTime Function() now,
  ) async {
    final last = _lastSent;
    if (last != null) {
      final remaining = minGap - now().difference(last);
      if (remaining > Duration.zero) await _wait(remaining);
    }
    _lastSent = now();
    try {
      // Inside the try: a host that is no host throws here, and is one more
      // way of not having the details.
      final uri = Uri.https(host, '/lookup', {
        'osm_ids': ref.lookupId,
        'format': 'jsonv2',
        'extratags': '1',
        'addressdetails': '1',
      });
      final response = await _http
          .get(uri, headers: Environment.transitousHeaders())
          .timeout(timeout);
      if (response.statusCode != 200) {
        developer.log(
          'lookup ${ref.lookupId}: HTTP ${response.statusCode}',
          name: 'NominatimClient',
        );
        return null;
      }
      final json = jsonDecode(utf8.decode(response.bodyBytes));
      if (json is! List || json.isEmpty || json.first is! Map) return null;
      final details = PlaceDetails.fromNominatim(
        (json.first as Map).cast<String, dynamic>(),
      );
      return details.isEmpty ? null : details;
    } on Object catch (e) {
      developer.log('lookup ${ref.lookupId}: $e', name: 'NominatimClient');
      return null;
    }
  }
}
