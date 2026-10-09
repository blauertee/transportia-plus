import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/stop_time.dart';
import '../services/stop_times_service.dart';
import '../services/transitous_map_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../utils/color_utils.dart';
import '../utils/geo_utils.dart';
import '../utils/nearby_stops.dart';
import '../utils/reported_time.dart';
import '../utils/stop_time_utils.dart';
import 'delayed_time.dart';
import 'gtfs_fields_row.dart';
import 'route_badge_pill.dart';
import 'skeletons/skeleton_shimmer.dart';

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

/// The next departures from the stops around [center], for the home screen.
///
/// [center] is the rider's position; without one there is nothing to be near,
/// and the section says so rather than guessing.
class NearbyDeparturesSection extends StatefulWidget {
  const NearbyDeparturesSection({
    super.key,
    required this.center,
    required this.onStopTap,
    this.fetchStops = _fetchStops,
    this.fetchDepartures = _fetchDepartures,
    this.clock = DateTime.now,
  });

  final LatLng? center;
  final ValueChanged<MapStop> onStopTap;
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
      return const _EmptyMessage(
        message: 'Allow location access to see departures near you.',
      );
    }
    if (_isLoading && _departuresByStopId.isEmpty) {
      return const _DeparturesSkeleton();
    }
    final stops = _listedStops;
    if (stops.isEmpty) {
      return const _EmptyMessage(message: 'No departures from stops nearby.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final stop in stops)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _StopDeparturesGroup(
              stop: stop,
              departures: _departuresByStopId[stop.stopId] ?? const [],
              onTap: () => widget.onStopTap(stop),
            ),
          ),
      ],
    );
  }
}

class _StopDeparturesGroup extends StatelessWidget {
  const _StopDeparturesGroup({
    required this.stop,
    required this.departures,
    required this.onTap,
  });

  final MapStop stop;
  final List<StopTime> departures;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Departures at ${stop.name}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.black.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.mapPin,
                    size: 16,
                    color: AppColors.accentOf(context),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      stop.name,
                      style: AppText.heading,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: AppColors.black.withValues(alpha: 0.3),
                  ),
                ],
              ),
              GtfsFieldsRow(fields: {'stop': stop.stopId}),
              const SizedBox(height: 10),
              for (var i = 0; i < departures.length; i++) ...[
                _DepartureRow(stopTime: departures[i]),
                if (i != departures.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DepartureRow extends StatelessWidget {
  const _DepartureRow({required this.stopTime});

  final StopTime stopTime;

  @override
  Widget build(BuildContext context) {
    final place = stopTime.place;
    final label = stopTime.displayName.isNotEmpty
        ? stopTime.displayName
        : stopTime.routeShortName;

    return Row(
      children: [
        RouteBadgePill(
          label: label,
          background: parseHexColorOrAccent(context, stopTime.routeColor),
          foreground: parseHexColorOr(
            stopTime.routeTextColor,
            AppColors.solidWhite,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          fontSize: 12,
          fontWeight: FontWeight.w700,
          minWidth: RouteBadgePill.stackedMinWidth,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            stopTime.headsign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.bodyStrong,
          ),
        ),
        const SizedBox(width: 8),
        DelayedTime.end(
          ReportedTime.from(
            place.departure ?? place.arrival,
            place.scheduledDeparture ?? place.scheduledArrival,
            isLive: stopTime.realTime,
          ),
        ),
      ],
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.accentWash(accent),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Icon(LucideIcons.clock, size: 24, color: accent),
          ),
          const SizedBox(height: 12),
          Text('No departures to show', style: AppText.heading),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center, style: AppText.subtitle),
        ],
      ),
    );
  }
}

class _DeparturesSkeleton extends StatelessWidget {
  const _DeparturesSkeleton();

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      child: Column(
        children: List.generate(
          2,
          (index) => Container(
            height: 84,
            margin: EdgeInsets.only(bottom: index == 1 ? 0 : 12),
            decoration: BoxDecoration(
              color: const Color(0x14000000),
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }
}
