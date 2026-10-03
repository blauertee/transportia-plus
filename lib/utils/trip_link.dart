import 'package:flutter/foundation.dart';

/// The scheme a shared trip opens through: generic rather than Transportia's
/// own, so any MOTIS client can claim it. See #40.
const String kTripLinkScheme = 'motis';

/// Transportia's own scheme, accepted on the way in for the links it already
/// registered.
const String _kLegacyTripLinkScheme = 'transportia';

/// The path every trip link carries after the scheme: `motis://trip?…`.
const String _kTripLinkHost = 'trip';

/// Where shared trips point on the web, so a messenger shows them as links.
///
/// Android opens these straight in Transportia once it has verified the
/// domain against `/.well-known/assetlinks.json` there. Anywhere else the page
/// at this path hands the trip on as `motis://trip`, to whichever MOTIS app
/// is installed, or to the MOTIS web app when none is.
const String kTripShareHost = 'blauertee.github.io';
const String kTripSharePath = '/fw/';

/// The paths that page answers on: GitHub Pages serves it at all three.
const Set<String> _kTripSharePaths = {'/fw', '/fw/', '/fw/index.html'};

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

  /// The link to share: an https link that opens in Transportia directly, or
  /// in any MOTIS app through the page it points to. See [kTripShareHost].
  Uri get shareLink => Uri.https(kTripShareHost, kTripSharePath, {
    'itineraryId': itineraryId,
    'host': ?host,
  });

  /// The same trip in the web app every MOTIS server serves at its root, for
  /// someone without a MOTIS app. Null when the link names no server.
  Uri? get webLink =>
      host == null ? null : Uri.https(host!, '/', {'itineraryId': itineraryId});

  /// Reads a trip link, or null when [uri] is not one or is malformed.
  static TripLink? tryParse(Uri uri) {
    if (!_isAppLink(uri) && !_isShareLink(uri)) return null;

    // Base64 has no spaces, but `+` reads back as one when a messenger
    // unescapes `%2B` before the query is parsed.
    final id = uri.queryParameters['itineraryId']?.replaceAll(' ', '+');
    if (id == null || id.isEmpty) return null;

    final host = uri.queryParameters['host'];
    if (host == null || host.isEmpty) return TripLink(itineraryId: id);
    if (!_kHostPattern.hasMatch(host)) return null;
    return TripLink(itineraryId: id, host: host.toLowerCase());
  }

  static bool _isAppLink(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    if (scheme != kTripLinkScheme && scheme != _kLegacyTripLinkScheme) {
      return false;
    }
    return uri.host.toLowerCase() == _kTripLinkHost;
  }

  /// Exactly the share page: https, that host, that path. Anything close —
  /// http, a lookalike domain, a neighbouring path — is not ours.
  static bool _isShareLink(Uri uri) =>
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.toLowerCase() == kTripShareHost &&
      !uri.hasPort &&
      _kTripSharePaths.contains(uri.path);
}
