import 'dart:math' as math;

import '../models/itinerary.dart';

/// The shortest a ride is drawn, whatever the zoom: room for its line name.
const double _kMinRideHeight = 18;

/// The least room between getting off and getting on again in one column:
/// room for the station name hung under the first ride.
const double _kMinChangeHeight = 16;

/// Stretching under this many pixels goes unmarked on the axis: too little
/// to mislead anyone about a duration.
const double _kNoticeableStretch = 12;

/// Stretched gaps closer than this many pixels are marked as one span.
const double _kSpanMergeGap = 40;

/// Bounds for the fitted zoom, in pixels per minute.
const double _kMinPxPerMinute = 0.2;
const double _kMaxPxPerMinute = 12;

/// A station, as a change sees it: platforms of one station are one place.
class GraphStation {
  const GraphStation({required this.id, required this.name});

  /// The parent station's id when the feed gives one, else the stop's.
  /// Feed-prefixed, as a via stop has to be sent.
  final String id;
  final String name;

  /// [id] without its feed prefix. Two feeds can both cover a station —
  /// Südkreuz is `de-VBB_de:11000:900058101` to the S-Bahn and
  /// `de-DELFI_de:11000:900058101` to the ICE — and a change between them
  /// is still a change at one station.
  String get key {
    final feedEnd = id.indexOf('_');
    return feedEnd < 0 ? id : id.substring(feedEnd + 1);
  }

  factory GraphStation.of(Leg leg, {required bool arriving}) {
    final place = arriving ? leg.to : leg.from;
    return GraphStation(
      id: place.parentId ?? place.stopId ?? place.name,
      name: place.name,
    );
  }
}

/// One ride, drawn once however many results take it.
class GraphRide {
  GraphRide._(this.key, this.leg);

  /// Same trip between the same stops: the same ride.
  final String key;
  final Leg leg;

  /// Indexes into [JourneyGraph.itineraries] of the results that take it.
  final List<int> itineraries = [];

  /// Horizontal position in result columns. Fractional when shared: the
  /// ride sits centred under (or over) every result that takes it.
  double slot = 0;

  GraphStation get boarding => GraphStation.of(leg, arriving: false);
  GraphStation get alighting => GraphStation.of(leg, arriving: true);

  static String keyOf(Leg leg) =>
      '${leg.tripId}|${leg.from.stopId}|${leg.to.stopId}';
}

/// Getting off one ride and onto the next.
class GraphChange {
  const GraphChange(this.from, this.to);

  final GraphRide from;
  final GraphRide to;

  /// A walk to another station, rather than a change of platform.
  ///
  /// Matched by name as well as by id: where two feeds meet, one station
  /// can carry an unrelated id in each (Ulm Hbf from Bavaria and from
  /// Baden-Württemberg).
  bool get changesStation =>
      from.alighting.key != to.boarding.key &&
      from.alighting.name != to.boarding.name;
}

/// Where a result ends: under its last ride, at the time it reaches the
/// destination.
class GraphArrival {
  GraphArrival._(this.ride, this.time);

  final GraphRide ride;
  final DateTime time;

  /// Indexes into [JourneyGraph.itineraries] of the results ending here.
  final List<int> itineraries = [];
}

/// The results of one search as a single graph: every ride once, laid out
/// in result columns, joined by changes.
class JourneyGraph {
  JourneyGraph._(
    this.itineraries,
    this.rides,
    this.changes,
    this.arrivals,
    this.events,
  );

  /// Ordered by departure, earliest first: that is the column order.
  final List<Itinerary> itineraries;
  final List<GraphRide> rides;
  final List<GraphChange> changes;
  final List<GraphArrival> arrivals;

  /// Every departure and arrival, in order: where the scale may bend.
  final List<DateTime> events;

  int get columnCount => itineraries.length;
  DateTime get start => events.first;
  DateTime get end => events.last;

  /// When the first result to get there gets there.
  DateTime get firstArrival => itineraries
      .map((it) => it.endTime)
      .reduce((a, b) => a.isBefore(b) ? a : b);

  factory JourneyGraph.build(List<Itinerary> results) {
    final itineraries = results.where((it) => it.hasTransit).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final byKey = <String, GraphRide>{};
    final changes = <String, GraphChange>{};
    final arrivals = <String, GraphArrival>{};
    for (var i = 0; i < itineraries.length; i++) {
      GraphRide? previous;
      for (final leg in itineraries[i].legs.where((leg) => leg.isRide)) {
        final ride = byKey.putIfAbsent(
          GraphRide.keyOf(leg),
          () => GraphRide._(GraphRide.keyOf(leg), leg),
        );
        ride.itineraries.add(i);
        if (previous != null) {
          changes.putIfAbsent(
            '${previous.key}>${ride.key}',
            () => GraphChange(previous!, ride),
          );
        }
        previous = ride;
      }
      final last = previous!;
      final arrival = itineraries[i].endTime;
      arrivals
          .putIfAbsent(
            '${last.key}@${arrival.millisecondsSinceEpoch}',
            () => GraphArrival._(last, arrival),
          )
          .itineraries
          .add(i);
    }

    for (final ride in byKey.values) {
      final first = ride.itineraries.reduce(math.min);
      final last = ride.itineraries.reduce(math.max);
      ride.slot = (first + last) / 2;
    }

    final events = <DateTime>{
      for (final ride in byKey.values) ...[
        ride.leg.startTime,
        ride.leg.endTime,
      ],
      for (final arrival in arrivals.values) arrival.time,
    }.toList()..sort();

    return JourneyGraph._(
      itineraries,
      byKey.values.toList(),
      changes.values.toList(),
      arrivals.values.toList(),
      events,
    );
  }

  /// The zoom at which [until] lands [height] below the first departure.
  ///
  /// Found by bisection rather than solved: the stretching [GraphScale]
  /// adds does not shrink in proportion to the zoom.
  double fitPxPerMinute(DateTime until, double height) {
    var low = _kMinPxPerMinute, high = _kMaxPxPerMinute;
    for (var i = 0; i < 24; i++) {
      final mid = (low + high) / 2;
      if (GraphScale(this, mid).yOf(until) > height) {
        high = mid;
      } else {
        low = mid;
      }
    }
    return low;
  }
}

/// Time to height at one zoom: linear, except where text would not fit.
///
/// At [pxPerMinute] a four-minute hop can be a few pixels tall, too short for
/// its line name or for the station name under it. Rather than give up on a
/// linear axis, the scale stretches just those stretches of time, between
/// two consecutive events, by just enough; the rest stays to scale. A
/// stretched stretch is flagged so the axis can show it is not to scale.
class GraphScale {
  factory GraphScale(JourneyGraph graph, double pxPerMinute) {
    final index = {
      for (var i = 0; i < graph.events.length; i++) graph.events[i]: i,
    };
    // Each constraint: from one event to a later one, at least so much room.
    final needs = <int, List<(int, double)>>{};
    void need(DateTime from, DateTime to, double room) =>
        needs.putIfAbsent(index[to]!, () => []).add((index[from]!, room));
    for (final ride in graph.rides) {
      need(ride.leg.startTime, ride.leg.endTime, _kMinRideHeight);
    }
    for (final change in graph.changes) {
      // Only where the station name would run into the next ride: in the
      // same column, or close enough to overlap it.
      if ((change.from.slot - change.to.slot).abs() >= 1) continue;
      final room = change.changesStation
          ? 2 * _kMinChangeHeight
          : _kMinChangeHeight;
      need(change.from.leg.endTime, change.to.leg.startTime, room);
    }

    final ys = <double>[];
    final stretched = <double>[];
    for (var i = 0; i < graph.events.length; i++) {
      if (i == 0) {
        ys.add(0);
        stretched.add(0);
        continue;
      }
      final minutes =
          graph.events[i].difference(graph.events[i - 1]).inSeconds / 60;
      final linear = ys.last + minutes * pxPerMinute;
      var y = linear;
      for (final (from, room) in needs[i] ?? const <(int, double)>[]) {
        y = math.max(y, ys[from] + room);
      }
      ys.add(y);
      stretched.add(y - linear);
    }
    return GraphScale._(pxPerMinute, graph.events, ys, stretched);
  }

  GraphScale._(this.pxPerMinute, this._events, this._ys, this._stretched);

  final double pxPerMinute;
  final List<DateTime> _events;
  final List<double> _ys;

  /// How many pixels the gap ending at each event was stretched past linear.
  final List<double> _stretched;

  double get height => _ys.isEmpty ? 0 : _ys.last;

  /// Vertical position of [time], from 0 at the first departure.
  double yOf(DateTime time) {
    if (_events.isEmpty || !time.isAfter(_events.first)) return 0;
    if (!time.isBefore(_events.last)) {
      return _ys.last +
          time.difference(_events.last).inSeconds / 60 * pxPerMinute;
    }
    final hi = _events.indexWhere((event) => !event.isBefore(time));
    if (_events[hi] == time) return _ys[hi];
    final lo = hi - 1;
    final span = _events[hi].difference(_events[lo]).inSeconds;
    final into = time.difference(_events[lo]).inSeconds;
    return _ys[lo] + (_ys[hi] - _ys[lo]) * into / span;
  }

  /// The time drawn at [y]: the inverse of [yOf], for keeping the moment
  /// under the fingers still while zooming.
  DateTime timeAt(double y) {
    if (_events.isEmpty || y <= 0) return _events.first;
    if (y >= _ys.last) {
      final minutes = (y - _ys.last) / pxPerMinute;
      return _events.last.add(Duration(seconds: (minutes * 60).round()));
    }
    final hi = _ys.indexWhere((at) => at >= y);
    final lo = hi - 1;
    final fraction = (y - _ys[lo]) / (_ys[hi] - _ys[lo]);
    final span = _events[hi].difference(_events[lo]).inSeconds;
    return _events[lo].add(Duration(seconds: (span * fraction).round()));
  }

  /// The stretches drawn noticeably taller than their time, as (top,
  /// bottom) pairs: runs of stretched gaps merged, and runs that gained
  /// only a few pixels left out, so the axis is not marked all over.
  Iterable<(double, double)> get stretchedSpans sync* {
    (double, double)? run;
    for (var i = 1; i < _ys.length; i++) {
      if (_stretched[i] < _kNoticeableStretch) continue;
      final (top, bottom) = (_ys[i - 1], _ys[i]);
      if (run != null && top - run.$2 < _kSpanMergeGap) {
        run = (run.$1, bottom);
        continue;
      }
      if (run != null) yield run;
      run = (top, bottom);
    }
    if (run != null) yield run;
  }
}

/// What the user pinned on the graph: stations to pass through, and how far
/// the journey is fixed.
///
/// Stations become via stops of the next search (the planner takes up to
/// two). A locked ride fixes the journey up to where it gets off: the next
/// search starts from there, at its arrival, and its results are joined to
/// the fixed part. The planner cannot pin a ride in the middle of a search,
/// which is why a lock reaches back to the start. Until either search is
/// wired up, locks only filter what already came back.
class JourneyLocks {
  const JourneyLocks({this.stationKeys = const {}, this.rideKeys = const {}});

  /// [GraphStation.key]s.
  final Set<String> stationKeys;
  final Set<String> rideKeys;

  bool get isEmpty => stationKeys.isEmpty && rideKeys.isEmpty;

  JourneyLocks toggleStation(String key) =>
      JourneyLocks(stationKeys: _toggle(stationKeys, key), rideKeys: rideKeys);

  JourneyLocks toggleRide(String key) =>
      JourneyLocks(stationKeys: stationKeys, rideKeys: _toggle(rideKeys, key));

  /// Whether [itinerary] passes every locked station and takes every locked
  /// ride.
  bool admits(Itinerary itinerary) {
    final rides = itinerary.legs.where((leg) => leg.isRide).toList();
    final stations = {
      for (final leg in rides) ...[
        GraphStation.of(leg, arriving: false).key,
        GraphStation.of(leg, arriving: true).key,
      ],
    };
    final keys = {for (final leg in rides) GraphRide.keyOf(leg)};
    return stationKeys.every(stations.contains) &&
        rideKeys.every(keys.contains);
  }

  static Set<String> _toggle(Set<String> set, String value) =>
      set.contains(value) ? ({...set}..remove(value)) : {...set, value};
}

/// [locked] up to and including [upTo], followed by each of [continuations]:
/// the results of a search from where [upTo] gets off, at its arrival.
///
/// The joined itineraries were never planned as a whole, so they carry no
/// server id that could be refreshed or shared; wiring this up has to clear
/// it.
List<Itinerary> continueAfter(
  Itinerary locked,
  GraphRide upTo,
  List<Itinerary> continuations,
) {
  final end = locked.legs.indexWhere(
    (leg) => leg.isRide && GraphRide.keyOf(leg) == upTo.key,
  );
  if (end < 0) return const [];
  final prefix = locked.legs.sublist(0, end + 1);
  return [
    for (final continuation in continuations)
      locked.withLegs([...prefix, ...continuation.legs]),
  ];
}
