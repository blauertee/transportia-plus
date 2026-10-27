import 'dart:async';

import '../models/itinerary.dart';
import '../models/routing_options.dart';
import '../models/time_selection.dart';
import '../utils/journey_graph.dart';
import 'routing_options_service.dart';
import 'routing_service.dart';

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
  });

  final JourneyQuery query;

  /// At most [JourneyGraphService.maxVia]; none the fixed part already
  /// passes.
  final List<GraphStation> via;
  final RideLock? lock;
}

typedef JourneyGraphSearcher =
    Future<List<Itinerary>> Function(JourneyGraphSearch search);

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

  static Future<List<Itinerary>> search(JourneyGraphSearch search) async {
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
      );
      return response.itineraries;
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
    );
    return continueAfter(lock.itinerary, lock.upTo, response.itineraries);
  }
}
