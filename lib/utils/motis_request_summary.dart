import '../api/transitous_endpoint.dart';

/// The parameters that tell one request to an endpoint from the next, as a
/// short line: where a plan went from and to, which stop a timetable is for.
///
/// Falls back to the first few parameters for endpoints with nothing more
/// telling, so every row still says something.
String motisRequestSummary(TransitousEndpoint endpoint, Uri uri) {
  final q = uri.queryParameters;
  String? pick(String key) {
    final value = q[key];
    return value == null || value.isEmpty ? null : value;
  }

  final parts = switch (endpoint) {
    TransitousEndpoint.plan => [
      if (pick('fromPlace') case final from?)
        if (pick('toPlace') case final to?) '$from → $to',
      pick('time'),
      if (pick('pageCursor') != null) 'next page',
    ],
    TransitousEndpoint.stopTimes => [
      pick('stopId') ?? pick('center'),
      pick('time'),
      if (pick('direction') case final direction?) direction,
    ],
    TransitousEndpoint.trip => [pick('tripId')],
    TransitousEndpoint.stop => [pick('stopId')],
    TransitousEndpoint.geocode => [
      if (pick('text') case final text?) '"$text"',
      pick('place'),
    ],
    TransitousEndpoint.reverseGeocode => [pick('place')],
    TransitousEndpoint.mapTrips || TransitousEndpoint.mapStops => [
      if (pick('min') case final min?)
        if (pick('max') case final max?) '$min … $max',
      if (pick('zoom') case final zoom?) 'zoom $zoom',
    ],
    _ => [
      for (final entry in q.entries.take(_kFallbackParams))
        '${entry.key}=${entry.value}',
    ],
  };
  return parts.whereType<String>().join(' · ');
}

const int _kFallbackParams = 2;
