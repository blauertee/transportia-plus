import 'dart:async';

import '../api/endpoints/trip_endpoint.dart';
import '../models/itinerary.dart';
import '../models/routing_options.dart';
import '../models/time_selection.dart';
import '../models/transitous/itinerary_id.dart';
import '../utils/journey_graph.dart';
import 'rental_providers_service.dart';
import 'routing_options_service.dart';
import 'routing_service.dart';
import 'server_capabilities_service.dart';

/// The search the results screen was opened with, which the journey graph
/// searches again with whatever has been locked.
class JourneyQuery {
  const JourneyQuery({
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
    required this.time,
    this.options,
  });

  final double fromLat;
  final double fromLon;
  final double toLat;
  final double toLon;
  final TimeSelection time;

  /// Null for the stored defaults.
  final RoutingOptions? options;
}

/// One search for the graph: [query] again, through [via], and from where
/// [lock] gets off when the journey is fixed up to a ride.
class JourneyGraphSearch {
  const JourneyGraphSearch({
    required this.query,
    this.via = const [],
    this.lock,
    this.pageCursor,
  });

  final JourneyQuery query;

  /// At most [JourneyGraphService.maxVia]; none the fixed part already
  /// passes.
  final List<GraphStation> via;
  final RideLock? lock;

  /// The page before or after an earlier answer to the same search.
  final String? pageCursor;
}

/// What one search found, with the cursors to the pages around it.
class JourneyGraphPage {
  const JourneyGraphPage(this.itineraries, {this.earlier, this.later});

  final List<Itinerary> itineraries;

  /// Null when there is no page that way. A search on from a locked ride
  /// has none earlier: those would leave before the ride gets in.
  final String? earlier;
  final String? later;
}

typedef JourneyGraphSearcher =
    Future<JourneyGraphPage> Function(JourneyGraphSearch search);

/// Asks the planner for one journey by its legs.
typedef JoinedJourneyFetcher = Future<Itinerary> Function(ItineraryId id);

/// The searches behind the journey graph's locks.
///
/// A locked station is a via stop. A locked ride fixes the journey up to
/// where it gets off: the planner cannot pin a ride inside a search, so the
/// graph searches on from that station at that time and joins the results
/// to the fixed part.
class JourneyGraphService {
  const JourneyGraphService._();

  /// The planner takes no more via stops than this.
  static const int maxVia = 2;

  /// Time allowed between getting off the locked ride and boarding the next
  /// one. A search that starts at a station counts the traveller as already
  /// standing on the platform, so without it the first results are changes
  /// nobody could make.
  static const Duration changeMargin = Duration(minutes: 3);

  static Future<JourneyGraphPage> search(JourneyGraphSearch search) async {
    final query = search.query;
    final base = query.options ?? await RoutingOptionsService.load();
    final options = base.copyWith(
      via: [
        for (final station in search.via)
          ViaStopOption(stopId: station.id, name: station.name),
      ],
    );

    final lock = search.lock;
    if (lock == null) {
      final response = await RoutingService.findRoutesPaginated(
        fromLat: query.fromLat,
        fromLon: query.fromLon,
        toLat: query.toLat,
        toLon: query.toLon,
        timeSelection: query.time,
        options: options,
        pageCursor: search.pageCursor,
      );
      return JourneyGraphPage(
        response.itineraries,
        earlier: response.previousPageCursor,
        later: response.nextPageCursor,
      );
    }

    final getOff = lock.upTo.to;
    final response = await RoutingService.findRoutesPaginated(
      fromLat: getOff.lat,
      fromLon: getOff.lon,
      fromStopId: getOff.stopId,
      toLat: query.toLat,
      toLon: query.toLon,
      timeSelection: TimeSelection(
        dateTime: (getOff.arrival ?? lock.upTo.endTime).add(changeMargin),
        isArriveBy: false,
      ),
      options: options,
      pageCursor: search.pageCursor,
    );
    final joined = continueAfter(
      lock.itinerary,
      lock.upTo,
      response.itineraries,
    );
    final rentalGroups = await RentalProvidersService.activeGroupIds();
    Future<Itinerary> fetch(ItineraryId id) =>
        TripEndpoint.refreshItineraryById(
          id: id,
          options: options.toRefreshParams(
            serverLimit: ServerCapabilitiesService
                .capabilities
                .value
                .maxPrePostTransitTime,
            rentalProviderGroups: rentalGroups,
          ),
        );
    final [changing, staying] = await Future.wait([
      planJoined(joined, lock.upTo, fetch: fetch),
      // Only with the first page: the pages after it go on from there.
      if (search.pageCursor == null)
        stayingOn(
          lock,
          trip: (tripId) async => (await TripEndpoint.trip(
            tripId: tripId,
            detailedLegs: false,
          )).legs.firstWhere((leg) => leg.isRide),
          plan: (from, at) async => (await RoutingService.findRoutesPaginated(
            fromLat: from.lat,
            fromLon: from.lon,
            fromStopId: from.stopId,
            toLat: query.toLat,
            toLon: query.toLon,
            timeSelection: TimeSelection(dateTime: at, isArriveBy: false),
            options: options,
          )).itineraries,
          fetch: fetch,
        )
      else
        Future.value(const <Itinerary>[]),
    ]);
    return JourneyGraphPage(
      mergeOnward(changing, staying),
      later: response.nextPageCursor,
    );
  }

  /// [lock]'s journey staying on the locked ride one stop further, and on
  /// from there: what the search from where it gets off cannot offer, since
  /// it starts once the ride has left. Planned as one journey each, like
  /// [planJoined]; empty when there is no stop further or no search from
  /// it, which leaves the search from where it gets off to stand alone.
  static Future<List<Itinerary>> stayingOn(
    RideLock lock, {
    required Future<Leg> Function(String tripId) trip,
    required Future<List<Itinerary>> Function(TransitPlace from, DateTime at)
    plan,
    required JoinedJourneyFetcher fetch,
  }) async {
    final tripId = lock.upTo.tripId;
    if (tripId == null || tripId.isEmpty) return const [];
    try {
      final service = await trip(tripId);
      final next = stopAfter(service, lock.upTo);
      final at = next?.timeAtTerminus;
      if (next == null || at == null) return const [];
      final found = await plan(next, at);
      return Future.wait([
        for (final continuation in found)
          if (stayOn(lock, service, next, continuation, margin: changeMargin)
              case (final joined, final ride))
            _planJoined(joined, ride, fetch),
      ]);
    } catch (_) {
      return const [];
    }
  }

  /// The journeys changing where the locked ride gets off, and those
  /// staying on it, as one list by arrival; a journey both searches found
  /// is kept once.
  static List<Itinerary> mergeOnward(
    List<Itinerary> changing,
    List<Itinerary> staying,
  ) {
    if (staying.isEmpty) return changing;
    String ridesOf(Itinerary it) => [
      for (final leg in it.legs)
        if (leg.isRide) GraphRide.keyOf(leg),
    ].join(' ');
    final seen = {for (final it in changing) ridesOf(it)};
    return [
      ...changing,
      for (final it in staying)
        if (seen.add(ridesOf(it))) it,
    ]..sort((a, b) => a.endTime.compareTo(b.endTime));
  }

  /// [joined], each asked of the planner as one journey, so it comes back
  /// with an id to share it by and with the walk from the locked ride to
  /// the next. One that cannot be planned so, or comes back as other
  /// rides, stays as it was joined.
  static Future<List<Itinerary>> planJoined(
    List<Itinerary> joined,
    Leg upTo, {
    required JoinedJourneyFetcher fetch,
  }) => Future.wait([
    for (final journey in joined) _planJoined(journey, upTo, fetch),
  ]);

  static Future<Itinerary> _planJoined(
    Itinerary joined,
    Leg upTo,
    JoinedJourneyFetcher fetch,
  ) async {
    final id = joinedItineraryId(joined, upTo);
    if (id == null) return joined;
    try {
      final planned = await fetch(id);
      final hasId = planned.id?.isNotEmpty ?? false;
      return hasId && isSameJoinedJourney(joined, planned) ? planned : joined;
    } catch (_) {
      return joined;
    }
  }
}
