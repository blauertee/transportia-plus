import '../api/endpoints/trip_endpoint.dart';
import '../models/itinerary.dart';
import '../models/routing_options.dart';
import '../models/transitous/itinerary_id.dart';
import 'rental_providers_service.dart';
import 'server_capabilities_service.dart';

/// How much the app actually knows about an itinerary's current state after
/// trying to refresh it.
enum ItineraryFreshness {
  /// No transit legs to re-check — walking directions never go stale.
  notRefreshable,

  /// Live data came back and has been merged in.
  live,

  /// The lookups ran but the feed returned nothing, so the times on screen
  /// are still the planned ones. Usually means the departure is beyond the
  /// real-time horizon, which is the normal case for a trip saved days or
  /// weeks ahead.
  scheduled,

  /// Live data came back and says the connection no longer works as
  /// planned — at least one leg is cancelled.
  changed,
}

/// The outcome of refreshing an itinerary.
class ItineraryRefreshResult {
  const ItineraryRefreshResult({
    required this.itinerary,
    required this.freshness,
  });

  final Itinerary itinerary;
  final ItineraryFreshness freshness;

  /// Whether live data actually arrived. Only then has anything been
  /// "updated" — callers use this to decide whether to move a
  /// last-updated timestamp, so that a failed lookup cannot masquerade as
  /// a successful refresh.
  bool get didRefresh =>
      freshness == ItineraryFreshness.live ||
      freshness == ItineraryFreshness.changed;
}

/// Signature of the per-trip lookup, so tests can supply
/// their own trip data without going over the network.
typedef TripDetailsFetcher =
    Future<Itinerary> Function({required String tripId});

/// Signature of the whole-itinerary refresh, so tests can supply their own
/// result without going over the network.
typedef ItineraryFetcher = Future<Itinerary> Function(Itinerary itinerary);

/// Re-fetches real-time data for the transit legs of an itinerary.
///
/// An itinerary is a snapshot of what the planner returned. Delays, track
/// changes and cancellations land afterwards, so any screen that shows an
/// itinerary it did not just fetch needs to re-check it.
class ItineraryRefreshService {
  const ItineraryRefreshService._();

  /// Re-checks [itinerary] against current real-time data.
  ///
  /// Prefers `/refresh-itinerary`, which re-plans the whole journey in one
  /// request. Falls back to a `/trip` lookup per distinct trip when that is
  /// unavailable — for an itinerary restored from an older saved trip, or
  /// when the endpoint fails.
  ///
  /// The returned itinerary is [itinerary] itself when nothing could be
  /// refreshed; read [ItineraryRefreshResult.freshness] to tell the cases
  /// apart rather than inferring it from the itinerary.
  static Future<ItineraryRefreshResult> refresh(
    Itinerary itinerary, {
    TripDetailsFetcher? fetchTripDetails,
    ItineraryFetcher? fetchItinerary,
    RoutingOptions? options,
  }) async {
    if (!itinerary.hasTransit) {
      return ItineraryRefreshResult(
        itinerary: itinerary,
        freshness: ItineraryFreshness.notRefreshable,
      );
    }

    // The single-request path. Skipped when a caller has pinned only the
    // per-trip fetcher, which is how the older tests drive this — pinning
    // both says "try the whole refresh, then fall back", which is what
    // production does and so the only way to test the fall-back.
    if (fetchTripDetails == null || fetchItinerary != null) {
      final refreshed = await _refreshWhole(
        itinerary,
        fetchItinerary ??
            (i) => _refreshViaApi(i, options ?? RoutingOptions.defaults),
      );
      if (refreshed != null) return refreshed;
    }

    return _refreshPerTrip(itinerary, fetchTripDetails ?? _fetchTripTimes);
  }

  /// `/trip` without the line's shape: the merge keeps the shape the leg
  /// already has, so downloading it again would only be thrown away.
  static Future<Itinerary> _fetchTripTimes({required String tripId}) =>
      TripEndpoint.trip(tripId: tripId, detailedLegs: false);

  /// Refreshes the itinerary in one request, or returns null so the caller
  /// falls back to the per-trip path.
  static Future<ItineraryRefreshResult?> _refreshWhole(
    Itinerary itinerary,
    ItineraryFetcher fetch,
  ) async {
    final Itinerary fresh;
    try {
      fresh = await fetch(itinerary);
    } catch (_) {
      return null;
    }
    if (!_isSameJourney(itinerary, fresh)) {
      // The server re-planned rather than refreshed, so the legs no longer
      // line up with what is on screen. Fall back rather than swap the
      // journey out from under the user — a substituted journey would show
      // up as "this connection has changed" for a connection that did not.
      return null;
    }

    final merged = itinerary.withLegs(_merge(itinerary, fresh));

    return ItineraryRefreshResult(
      itinerary: merged,
      freshness: merged.legs.any((leg) => leg.cancelled)
          ? ItineraryFreshness.changed
          : ItineraryFreshness.live,
    );
  }

  /// True when the refreshed legs are the same journey re-timed, rather than
  /// a different one that happens to be the same length.
  ///
  /// Leg count alone is not enough: walk legs carry no `tripId` for the
  /// server to pin them by, so they are exactly the ones it is free to
  /// re-plan into something else. So the rides and the changes between them
  /// must line up one for one. The first and last mile are found again from
  /// scratch and may come back in another shape — a shared vehicle is a
  /// walk, a ride and a walk, or one placeholder when none is in reach — so
  /// they only have to be there on both sides or on neither.
  static bool _isSameJourney(Itinerary before, Itinerary after) {
    if (before.firstMileLegs.isEmpty != after.firstMileLegs.isEmpty) {
      return false;
    }
    if (before.lastMileLegs.isEmpty != after.lastMileLegs.isEmpty) {
      return false;
    }
    final planned = before.rideLegs;
    final refreshed = after.rideLegs;
    if (planned.length != refreshed.length) return false;
    for (var i = 0; i < planned.length; i++) {
      if (!_isSameLeg(planned[i], refreshed[i])) return false;
    }
    return true;
  }

  /// The same ride, or the same change. A ride the server could not find
  /// again comes back as a cancelled placeholder without its trip id, which
  /// is news about this ride rather than a different one.
  static bool _isSameLeg(Leg planned, Leg refreshed) {
    if (planned.mode != refreshed.mode) return false;
    final plannedTrip = planned.tripId ?? '';
    final refreshedTrip = refreshed.tripId ?? '';
    if (plannedTrip == refreshedTrip) return true;
    return refreshed.cancelled && refreshedTrip.isEmpty;
  }

  /// Takes the refreshed times onto the planned journey, rather than the
  /// planned times onto a refreshed one.
  static List<Leg> _merge(Itinerary before, Itinerary after) => [
    ..._mergeStreetStretch(before.firstMileLegs, after.firstMileLegs),
    for (final (i, leg) in before.rideLegs.indexed)
      _mergeLeg(leg, after.rideLegs[i]),
    ..._mergeStreetStretch(before.lastMileLegs, after.lastMileLegs),
  ];

  /// `withRealTimeFrom` is the same merge the per-trip path uses, and it
  /// keeps what belongs to the itinerary rather than to the timetable —
  /// fare indices, turn-by-turn steps, and the leg's geometry. That last one
  /// is why this matters: a refresh answers without geometry, and a street
  /// leg with none is drawn as a straight line from origin to station, which
  /// is not where anybody walks.
  ///
  /// A stored leg that never had geometry has nothing to lend, so the fresh
  /// one is taken whole in case it brought some.
  static Leg _mergeLeg(Leg planned, Leg refreshed) =>
      (planned.legGeometry?.points.isNotEmpty ?? false)
      ? planned.withRealTimeFrom(refreshed)
      : refreshed;

  /// The way to the first station, or from the last, after the server has
  /// looked for it again.
  ///
  /// A shared vehicle is taken as the server now finds it: the planned one
  /// may be gone, and the one in its place stands somewhere else, reached
  /// another way, which is why the refresh fetched its shape. When none is in
  /// reach the placeholder stays, since that is news: the rider cannot leave
  /// the way the itinerary says.
  ///
  /// The rider's own feet, bike or car do not go anywhere. A placeholder for
  /// one only means the server could not find the stretch again within the
  /// limit it was given, so the planned stretch stays as it was. Found again,
  /// it takes the new times — the server moves it with a delayed ride — and
  /// keeps its shape.
  static List<Leg> _mergeStreetStretch(List<Leg> planned, List<Leg> fresh) {
    if (planned.any((leg) => leg.rental != null)) return fresh;
    final notFoundAgain = fresh.any((leg) => leg.cancelled);
    if (notFoundAgain || fresh.length != planned.length) return planned;
    return [for (final (i, leg) in planned.indexed) _mergeLeg(leg, fresh[i])];
  }

  static Future<Itinerary> _refreshViaApi(
    Itinerary itinerary,
    RoutingOptions options,
  ) async {
    final id = itinerary.id;
    final params = options.toRefreshParams(
      itinerary: itinerary,
      serverLimit:
          ServerCapabilitiesService.capabilities.value.maxPrePostTransitTime,
      rentalProviderGroups: await RentalProvidersService.activeGroupIds(),
    );
    // A saved trip parsed from a snapshot taken before the app read `id`
    // still has its legs, which is enough to rebuild the structured form.
    return id != null && id.isNotEmpty
        ? TripEndpoint.refreshItinerary(itineraryId: id, options: params)
        : TripEndpoint.refreshItineraryById(
            id: ItineraryId.fromItinerary(itinerary),
            options: params,
          );
  }

  static Future<ItineraryRefreshResult> _refreshPerTrip(
    Itinerary itinerary,
    TripDetailsFetcher fetch,
  ) async {
    final tripIds = itinerary.legs
        .map((leg) => leg.tripId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    final updates = <String, Leg>{};
    await Future.wait(
      tripIds.map((tripId) async {
        try {
          final details = await fetch(tripId: tripId);
          // Not blindly the first leg: a `/trip` response that leads with a
          // walk would otherwise lend its times and its cancellation to every
          // transit leg in the itinerary.
          for (final leg in details.legs) {
            if (leg.tripId == tripId) {
              updates[tripId] = leg;
              break;
            }
          }
        } catch (_) {}
      }),
    );

    // Every lookup failed or came back empty. The itinerary is untouched and
    // we know nothing new about it, so say so instead of reporting a refresh.
    if (updates.isEmpty) {
      return ItineraryRefreshResult(
        itinerary: itinerary,
        freshness: ItineraryFreshness.scheduled,
      );
    }

    final newLegs = itinerary.legs.map((leg) {
      final fresh = leg.tripId != null ? updates[leg.tripId] : null;
      if (fresh == null) return leg;
      // `/trip` answers with the whole service, so what came back covers the
      // line end to end rather than the part this journey rides. Cut it down
      // before merging, or the leg inherits every station on the line and the
      // line's own first departure. Only this path needs it —
      // `/refresh-itinerary` already answers leg by leg.
      return leg.withRealTimeFrom(fresh.sliceBetween(leg.from, leg.to));
    }).toList();

    return ItineraryRefreshResult(
      itinerary: itinerary.withLegs(newLegs),
      freshness: newLegs.any((leg) => leg.cancelled)
          ? ItineraryFreshness.changed
          : ItineraryFreshness.live,
    );
  }
}
