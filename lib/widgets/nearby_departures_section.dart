import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/stop_time.dart';
import '../services/stop_times_service.dart';
import '../services/transitous_map_service.dart';
import '../utils/geo_utils.dart';
import '../utils/nearby_stops.dart';
import '../utils/stop_time_utils.dart';

/// Builds the nearby list with the rows and note of the list it sits in.
typedef NearbySectionBuilder =
    Widget Function(
      Widget Function(MapStop stop, List<String> departures) buildRow,
      Widget Function(String message) buildMessage,
    );

/// Looks up the stops in a box. Injected so tests need no network.
typedef NearbyStopsFetcher =
    Future<List<MapStop>> Function(LatLngBounds bounds);

/// Looks up the next departures at one stop.
typedef NearbyDeparturesFetcher =
    Future<List<StopTime>> Function(String stopId, DateTime now);

Future<List<MapStop>> _fetchStops(LatLngBounds bounds) =>
    TransitousMapService.fetchStops(bounds: bounds);

Future<List<StopTime>> _fetchDepartures(String stopId, DateTime now) async {
  final response = await StopTimesService.fetchStopTimes(
    stopId: stopId,
    n: _kDeparturesPerStop,
    startTime: now,
  );
  return response.stopTimes;
}

/// Departures listed per stop.
const int _kDeparturesPerStop = 3;

/// How often the lists are fetched again while on screen.
const Duration _kRefreshInterval = Duration(seconds: 30);

/// How far the rider has to move before the stops are looked up again.
const double _kRelookupMetres = 150;

/// A departure this recently gone is still shown, since the clocks on a
/// platform and in a feed are not exactly the same.
const Duration _kDepartureGrace = Duration(minutes: 1);

/// The next departures from the stops around [center], for the timetable
/// search.
///
/// [center] is the rider's position; without one there is nothing to be near,
/// and the section says so rather than guessing.
class NearbyDeparturesSection extends StatefulWidget {
  const NearbyDeparturesSection({
    super.key,
    required this.center,
    required this.buildRow,
    required this.buildMessage,
    this.fetchStops = _fetchStops,
    this.fetchDepartures = _fetchDepartures,
    this.clock = DateTime.now,
  });

  final LatLng? center;

  /// Draws one stop, given its next departures as lines of text, so the list
  /// looks like the rows around it.
  final Widget Function(MapStop stop, List<String> departures) buildRow;

  /// Draws a one-line note where there is nothing to list.
  final Widget Function(String message) buildMessage;
  final NearbyStopsFetcher fetchStops;
  final NearbyDeparturesFetcher fetchDepartures;

  /// What "now" is, which decides which departures have already gone.
  final DateTime Function() clock;

  @override
  State<NearbyDeparturesSection> createState() =>
      _NearbyDeparturesSectionState();
}

class _NearbyDeparturesSectionState extends State<NearbyDeparturesSection> {
  Timer? _refreshTimer;
  int _requestId = 0;
  bool _isLoading = true;
  List<MapStop> _stops = const [];
  Map<String, List<StopTime>> _departuresByStopId = const {};

  @override
  void initState() {
    super.initState();
    // Nothing to load without a position, so nothing to wait for either.
    _isLoading = widget.center != null;
    unawaited(_load(lookUpStops: true));
    _refreshTimer = Timer.periodic(
      _kRefreshInterval,
      (_) => unawaited(_load(lookUpStops: false)),
    );
  }

  @override
  void didUpdateWidget(covariant NearbyDeparturesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_hasMovedFar(oldWidget.center, widget.center)) {
      unawaited(_load(lookUpStops: true));
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  static bool _hasMovedFar(LatLng? from, LatLng? to) {
    if (from == null || to == null) return from != to;
    return coordinateDistanceInMeters(
          from.latitude,
          from.longitude,
          to.latitude,
          to.longitude,
        ) >
        _kRelookupMetres;
  }

  Future<void> _load({required bool lookUpStops}) async {
    final center = widget.center;
    final requestId = ++_requestId;

    if (center == null) {
      if (_stops.isNotEmpty || _isLoading) {
        setState(() {
          _stops = const [];
          _departuresByStopId = const {};
          _isLoading = false;
        });
      }
      return;
    }

    if (lookUpStops && _stops.isEmpty && !_isLoading) {
      setState(() => _isLoading = true);
    }

    var stops = _stops;
    if (lookUpStops || stops.isEmpty) {
      try {
        stops = nearestStops(
          await widget.fetchStops(nearbyStopsBounds(center)),
          center,
        );
      } catch (_) {
        stops = const [];
      }
      if (!mounted || requestId != _requestId) return;
    }

    final now = widget.clock();
    final results = await Future.wait([
      for (final stop in stops) _departuresOf(stop, now),
    ]);
    if (!mounted || requestId != _requestId) return;

    setState(() {
      _stops = stops;
      _departuresByStopId = {
        for (var i = 0; i < stops.length; i++)
          if (results[i].isNotEmpty) stops[i].stopId!: results[i],
      };
      _isLoading = false;
    });
  }

  Future<List<StopTime>> _departuresOf(MapStop stop, DateTime now) async {
    try {
      final departures = await widget.fetchDepartures(stop.stopId!, now);
      final cutoff = now.subtract(_kDepartureGrace);
      final upcoming = [
        for (final entry in deduplicateStopTimes(departures))
          if (departureKey(entry)?.isAfter(cutoff) ?? false) entry,
      ]..sort((a, b) => departureKey(a)!.compareTo(departureKey(b)!));
      return upcoming.take(_kDeparturesPerStop).toList();
    } catch (_) {
      return const [];
    }
  }

  /// The stops worth listing: those with departures, each physical stop once.
  List<MapStop> get _listedStops {
    final seen = <String>{};
    return [
      for (final stop in _stops)
        if (_departuresByStopId[stop.stopId] case final departures?)
          if (seen.add(departuresSignature(stop.name, departures))) stop,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (widget.center == null) {
      return widget.buildMessage('Allow location access to see departures.');
    }
    if (_isLoading && _departuresByStopId.isEmpty) {
      return widget.buildMessage('Looking for departures…');
    }
    final stops = _listedStops;
    if (stops.isEmpty) return widget.buildMessage('No departures nearby.');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final stop in stops)
          widget.buildRow(stop, [
            for (final departure in _departuresByStopId[stop.stopId]!)
              departureLine(departure),
          ]),
      ],
    );
  }
}
