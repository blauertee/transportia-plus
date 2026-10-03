import 'package:flutter/foundation.dart';

/// The scheme a shared trip opens through: generic rather than Transportia's
/// own, so any MOTIS client can claim it. See #40.
const String kTripLinkScheme = 'motis';

/// Transportia's own scheme, accepted on the way in for the links it already
/// registered.
const String _kLegacyTripLinkScheme = 'transportia';

/// The path every trip link carries after the scheme: `motis://trip?…`.
const String _kTripLinkHost = 'trip';

/// A hostname, optionally with a port. A link is untrusted input, and the
/// host is where the app will send a request, so anything else — a path, a
/// scheme, credentials — makes the link invalid rather than being cleaned up.
final RegExp _kHostPattern = RegExp(
  r'^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*(:\d{1,5})?$',
);

/// One shared itinerary: the planner's opaque id for it, and the server that
/// can turn the id back into the journey.
@immutable
class TripLink {
  const TripLink({required this.itineraryId, this.host});

  /// MOTIS's `Itinerary.id`, as `/refresh-itinerary` takes it.
  final String itineraryId;

  /// The server the trip was planned on. Null for a link that does not say,
  /// which is read against the rider's own server.
  final String? host;

  /// The link for MOTIS apps: `motis://trip?itineraryId=…&host=…`.
  Uri get appLink => Uri(
    scheme: kTripLinkScheme,
    host: _kTripLinkHost,
    queryParameters: {'itineraryId': itineraryId, 'host': ?host},
  );

  /// The same trip in the web app every MOTIS server serves at its root, for
  /// someone without a MOTIS app. Null when the link names no server.
  Uri? get webLink =>
      host == null ? null : Uri.https(host!, '/', {'itineraryId': itineraryId});

  /// Reads a trip link, or null when [uri] is not one or is malformed.
  static TripLink? tryParse(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != kTripLinkScheme && scheme != _kLegacyTripLinkScheme) {
      return null;
    }
    if (uri.host.toLowerCase() != _kTripLinkHost) return null;

    // Base64 has no spaces, but `+` reads back as one when a messenger
    // unescapes `%2B` before the query is parsed.
    final id = uri.queryParameters['itineraryId']?.replaceAll(' ', '+');
    if (id == null || id.isEmpty) return null;

    final host = uri.queryParameters['host'];
    if (host == null || host.isEmpty) return TripLink(itineraryId: id);
    if (!_kHostPattern.hasMatch(host)) return null;
    return TripLink(itineraryId: id, host: host.toLowerCase());
  }
}
