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

/// How far two boxes may reach into each other's height and still count as
/// one above the other.
const double _kBoxSlack = 3;

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

  /// The first and last of [itineraries], the columns it is centred across.
  int get firstColumn => itineraries.reduce(math.min);
  int get lastColumn => itineraries.reduce(math.max);

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
    final itineraries = _byDeparture(
      results.where((it) => it.hasTransit).toList(),
    );

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
      ride.slot = (ride.firstColumn + ride.lastColumn) / 2;
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

  /// [results] ordered by departure. Results leaving at the same time go
  /// next to the ones they share rides with: a shared ride is drawn across
  /// the columns that take it, and a column between them that does not
  /// would have its own rides drawn through it.
  static List<Itinerary> _byDeparture(List<Itinerary> results) {
    Set<String> rides(Itinerary it) => {
      for (final leg in it.legs)
        if (leg.isRide) GraphRide.keyOf(leg),
    };
    final left = [...results]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
    final ordered = <Itinerary>[];
    while (left.isNotEmpty) {
      final start = left.first.startTime;
      final tied = left.takeWhile((it) => it.startTime == start).toList();
      final next = ordered.isEmpty
          ? tied.first
          : tied.reduce((best, it) {
              final previous = rides(ordered.last);
              int shared(Itinerary x) => rides(x).intersection(previous).length;
              return shared(it) > shared(best) ? it : best;
            });
      ordered.add(next);
      left.remove(next);
    }
    return ordered;
  }

  /// The zoom at which [until] lands [height] below the first departure.
  ///
  /// Found by bisection rather than solved: the stretching [GraphScale]
  /// adds does not shrink in proportion to the zoom.
  double fitPxPerMinute(
    DateTime until,
    double height, {
    RideBadges badges = const RideBadges(),
  }) {
    var low = _kMinPxPerMinute, high = _kMaxPxPerMinute;
    for (var i = 0; i < 24; i++) {
      final mid = (low + high) / 2;
      if (GraphScale(this, mid, badges: badges).yOf(until) > height) {
        high = mid;
      } else {
        low = mid;
      }
    }
    return low;
  }
}

/// Something drawn on a ride, for spacing the columns: [left] and [right]
/// of the ride's centre line, [top] to [bottom] down the graph, in pixels.
class GraphBox {
  const GraphBox(
    this.ride, {
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  });

  final GraphRide ride;
  final double left;
  final double right;
  final double top;
  final double bottom;

  /// Whether the two reach the same height, by more than a sliver: the
  /// rounded ends of bars and the padding round names can touch.
  bool overlapsInTime(GraphBox other) =>
      top < other.bottom - _kBoxSlack && other.top < bottom - _kBoxSlack;
}

/// Where each column's centre goes, from 0 for the first.
///
/// Each column sits as close to the one before as [minGaps] allows (an
/// entry per column, the first unused), and then as far further right as
/// it takes to keep [margin] between any two [boxes] that sit side by side:
/// columns are only as wide as what is beside them at the same time, not
/// as the widest thing anywhere.
///
/// One pass, left to right. A ride shared by several results is centred
/// across them, so it moves with the last of them, and is settled with it.
List<double> packColumns(
  int count,
  List<GraphBox> boxes, {
  required List<double> minGaps,
  required double margin,
}) {
  if (count == 0) return const [];
  final byLast = <int, List<GraphBox>>{};
  for (final box in boxes) {
    byLast.putIfAbsent(box.ride.lastColumn, () => []).add(box);
  }
  final xs = <double>[0];
  // A box's centre as a * x + c, where x is the column being placed.
  (double, double) centre(GraphBox box, int column) {
    final first = box.ride.firstColumn, last = box.ride.lastColumn;
    if (last < column) return (0, (xs[first] + xs[last]) / 2);
    if (first == column) return (1, 0);
    return (0.5, xs[first] / 2);
  }

  final settled = <GraphBox>[];
  for (var column = 1; column < count; column++) {
    var x = xs[column - 1] + minGaps[column];
    final placing = byLast[column] ?? const <GraphBox>[];
    settled.addAll(byLast[column - 1] ?? const <GraphBox>[]);
    for (final box in placing) {
      for (final other in [...settled, ...placing]) {
        if (other.ride == box.ride ||
            other.ride.slot == box.ride.slot ||
            !box.overlapsInTime(other)) {
          continue;
        }
        final (left, right) = other.ride.slot < box.ride.slot
            ? (other, box)
            : (box, other);
        final (aLeft, cLeft) = centre(left, column);
        final (aRight, cRight) = centre(right, column);
        // Moving this column right only helps when it moves the right box
        // further than the left one; a ride shared across a column it
        // does not take cannot be helped by it.
        if (aRight <= aLeft) continue;
        final room = left.right + right.left + margin;
        x = math.max(x, (room - (cRight - cLeft)) / (aRight - aLeft));
      }
    }
    xs.add(x);
  }
  return xs;
}

/// Rides with a badge on the bottom corner of their bar, which the scale
/// makes room for: a bar tall enough to hold the badge clear of its name,
/// and the badge's [overhang] below the bar before the station name there.
class RideBadges {
  const RideBadges({
    this.keys = const {},
    this.rideHeight = 0,
    this.overhang = 0,
  });

  final Set<String> keys;
  final double rideHeight;
  final double overhang;

  @override
  bool operator ==(Object other) =>
      other is RideBadges &&
      other.rideHeight == rideHeight &&
      other.overhang == overhang &&
      other.keys.length == keys.length &&
      other.keys.containsAll(keys);

  @override
  int get hashCode => Object.hash(rideHeight, overhang, keys.length);
}

/// Time to height at one zoom: linear, except where text would not fit.
///
/// At [pxPerMinute] a four-minute hop can be a few pixels tall, too short for
/// its line name or for the station name under it. Rather than give up on a
/// linear axis, the scale stretches just those stretches of time, between
/// two consecutive events, by just enough; the rest stays to scale. A
/// stretched stretch is flagged so the axis can show it is not to scale.
class GraphScale {
  factory GraphScale(
    JourneyGraph graph,
    double pxPerMinute, {
    RideBadges badges = const RideBadges(),
  }) {
    final index = {
      for (var i = 0; i < graph.events.length; i++) graph.events[i]: i,
    };
    // Each constraint: from one event to a later one, at least so much room.
    final needs = <int, List<(int, double)>>{};
    void need(DateTime from, DateTime to, double room) {
      // A change that cannot be made boards before the ride into it gets
      // in; there is no gap to make room in.
      if (index[from]! >= index[to]!) return;
      needs.putIfAbsent(index[to]!, () => []).add((index[from]!, room));
    }

    for (final ride in graph.rides) {
      need(
        ride.leg.startTime,
        ride.leg.endTime,
        badges.keys.contains(ride.key) ? badges.rideHeight : _kMinRideHeight,
      );
    }
    for (final change in graph.changes) {
      // Only where the station name would run into the next ride: in the
      // same column, or close enough to overlap it.
      if ((change.from.slot - change.to.slot).abs() >= 1) continue;
      final room =
          (change.changesStation ? 2 * _kMinChangeHeight : _kMinChangeHeight) +
          (badges.keys.contains(change.from.key) ? badges.overhang : 0);
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
/// which is why a lock reaches back to the start, and why only one ride is
/// locked at a time; see [RideLock].
class JourneyLocks {
  const JourneyLocks({this.stationKeys = const {}, this.rideKeys = const {}});

  /// [GraphStation.key]s.
  final Set<String> stationKeys;

  /// [GraphRide.key]s.
  final Set<String> rideKeys;

  bool get isEmpty => stationKeys.isEmpty && rideKeys.isEmpty;

  JourneyLocks toggleStation(String key) => JourneyLocks(
    stationKeys: stationKeys.contains(key)
        ? ({...stationKeys}..remove(key))
        : {...stationKeys, key},
    rideKeys: rideKeys,
  );
}

/// A journey fixed up to and including the ride [upTo] on [itinerary]:
/// what the graph searches onward from.
class RideLock {
  const RideLock(this.itinerary, this.upTo);

  final Itinerary itinerary;
  final Leg upTo;

  String get key => GraphRide.keyOf(upTo);

  /// Every ride up to and including [upTo].
  List<Leg> get rides {
    final end = _endOf(itinerary, upTo);
    if (end < 0) return const [];
    return [
      for (final leg in itinerary.legs.sublist(0, end + 1))
        if (leg.isRide) leg,
    ];
  }

  /// Whether the fixed part passes [stationKey], so a via stop there is
  /// already met and must not be sent onward.
  bool passes(String stationKey) => rides.any(
    (leg) =>
        GraphStation.of(leg, arriving: false).key == stationKey ||
        GraphStation.of(leg, arriving: true).key == stationKey,
  );
}

int _endOf(Itinerary itinerary, Leg upTo) {
  final key = GraphRide.keyOf(upTo);
  return itinerary.legs.indexWhere(
    (leg) => leg.isRide && GraphRide.keyOf(leg) == key,
  );
}

/// [locked] up to and including [upTo], followed by each of [continuations]:
/// the results of a search from where [upTo] gets off, at its arrival.
///
/// The joined itineraries were never planned as a whole, so they carry no
/// server id to refresh them by and no fare, which covered only one of the
/// halves. Their snapshot is the two halves' legs joined, so a joined
/// journey can still be saved.
List<Itinerary> continueAfter(
  Itinerary locked,
  Leg upTo,
  List<Itinerary> continuations,
) {
  final end = _endOf(locked, upTo);
  if (end < 0) return const [];
  return [
    for (final continuation in continuations) _join(locked, end, continuation),
  ];
}

Itinerary _join(Itinerary locked, int end, Itinerary continuation) {
  final legs = [...locked.legs.sublist(0, end + 1), ...continuation.legs];
  final rides = legs.where((leg) => !leg.isStreet).length;
  final transfers = rides > 0 ? rides - 1 : 0;
  final duration = legs.last.endTime.difference(legs.first.startTime);
  return Itinerary(
    duration: duration.inSeconds,
    startTime: legs.first.startTime,
    endTime: legs.last.endTime,
    transfers: transfers,
    legs: legs,
    sourceJson: _joinedSnapshot(locked, end, continuation, transfers),
  );
}

/// The planner's own JSON for the joined legs, or null when either half
/// has none to give.
Map<String, dynamic>? _joinedSnapshot(
  Itinerary locked,
  int end,
  Itinerary continuation,
  int transfers,
) {
  final head = locked.sourceJson?['legs'];
  final tail = continuation.sourceJson?['legs'];
  if (head is! List || tail is! List || tail.isEmpty) return null;
  // Legs and snapshot have to line up for the cut to land in the same
  // place in both.
  if (head.length != locked.legs.length) return null;
  final legs = [...head.sublist(0, end + 1), ...tail];
  final start = (legs.first as Map)['startTime'] as String;
  final finish = (legs.last as Map)['endTime'] as String;
  return {
    'duration': DateTime.parse(
      finish,
    ).difference(DateTime.parse(start)).inSeconds,
    'startTime': start,
    'endTime': finish,
    'transfers': transfers,
    'legs': legs,
  };
}
