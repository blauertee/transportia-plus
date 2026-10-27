import 'dart:math' as math;

import '../models/itinerary.dart';

/// Vertical room every gap between two events gets, however short, so a
/// two-minute change still has space for a station name.
const double _kMinGap = 14;

/// How fast a gap grows with its length. Mostly with the square root of the
/// minutes, so a four-hour ride stays on screen and a four-minute hop stays
/// readable; partly linear, so a long ride still looks long when only a
/// couple of results are left and few events break it up.
const double _kGapPerRootMinute = 4.5;
const double _kGapPerMinute = 0.35;

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
  const GraphArrival(this.ride, this.time);

  final GraphRide ride;
  final DateTime time;
}

/// The results of one search as a single graph: every ride once, laid out
/// in result columns, joined by changes.
class JourneyGraph {
  JourneyGraph._(
    this.itineraries,
    this.rides,
    this.changes,
    this.arrivals,
    this._events,
    this._ys,
  );

  /// Ordered by departure, earliest first: that is the column order.
  final List<Itinerary> itineraries;
  final List<GraphRide> rides;
  final List<GraphChange> changes;
  final List<GraphArrival> arrivals;
  final List<DateTime> _events;
  final List<double> _ys;

  int get columnCount => itineraries.length;
  double get height => _ys.isEmpty ? 0 : _ys.last;
  DateTime get start => _events.first;
  DateTime get end => _events.last;

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
      arrivals.putIfAbsent(
        '${last.key}@${arrival.millisecondsSinceEpoch}',
        () => GraphArrival(last, arrival),
      );
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
    final ys = <double>[];
    for (var i = 0; i < events.length; i++) {
      if (i == 0) {
        ys.add(0);
        continue;
      }
      final minutes = events[i].difference(events[i - 1]).inSeconds / 60;
      ys.add(
        ys.last +
            _kMinGap +
            _kGapPerRootMinute * math.sqrt(minutes) +
            _kGapPerMinute * minutes,
      );
    }

    return JourneyGraph._(
      itineraries,
      byKey.values.toList(),
      changes.values.toList(),
      arrivals.values.toList(),
      events,
      ys,
    );
  }

  /// Vertical position of [time], from 0 at the first departure.
  ///
  /// Linear between two events and compressed across the whole: see
  /// [_kGapPerRootMinute] and [_kGapPerMinute].
  double yOf(DateTime time) {
    if (_events.isEmpty || !time.isAfter(_events.first)) return 0;
    if (!time.isBefore(_events.last)) return _ys.last;
    var hi = _events.indexWhere((event) => !event.isBefore(time));
    if (_events[hi] == time) return _ys[hi];
    final lo = hi - 1;
    final span = _events[hi].difference(_events[lo]).inSeconds;
    final into = time.difference(_events[lo]).inSeconds;
    return _ys[lo] + (_ys[hi] - _ys[lo]) * into / span;
  }
}

/// What the user pinned on the graph: stations to pass through and rides to
/// take.
///
/// Stations become via stops of the next search. Rides have no server-side
/// counterpart yet, so for now they only filter what came back.
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
