import 'package:flutter/widgets.dart';
import 'package:timelines_plus/timelines_plus.dart';

import '../../models/journey_stop.dart';
import '../../theme/app_colors.dart';
import '../../utils/vehicle_position.dart';
import '../../utils/reported_time.dart';
import '../delayed_time.dart';
import '../gtfs_fields_row.dart';
import '../timeline_indicator_box.dart';

/// Called when a rider taps a stop with a known id.
typedef StopTapCallback =
    void Function({
      required String? stopId,
      required String stopName,
      required DateTime referenceTime,
    });

/// Diameter of the dot marking a first or last stop.
const double _kTerminalDotSize = 16;

/// Diameter of the dot marking an intermediate stop.
const double _kIntermediateDotSize = 12;

/// Diameter of the circle carrying the vehicle icon. Fills the indicator box
/// it sits in, so the two must agree.
const double _kVehicleMarkerSize = kTimelineIndicatorSize;

/// How far the accented line is dimmed once the vehicle has gone past.
const double _kPassedLineOpacity = 0.6;

/// How far a stop's own text is dimmed once the vehicle has gone past.
const double _kPassedTextOpacity = 0.5;

/// The stops of one trip, drawn as a timeline with the vehicle placed on it.
class TripTimeline extends StatelessWidget {
  const TripTimeline({
    super.key,
    required this.stops,
    required this.position,
    required this.routeColor,
    required this.routeTextColor,
    required this.modeIcon,
    required this.onStopTap,
    required this.isLive,
  });

  final List<JourneyStop> stops;
  final VehiclePosition position;
  final Color routeColor;
  final Color routeTextColor;
  final IconData modeIcon;
  final StopTapCallback onStopTap;

  /// Whether the operator is reporting this trip, so its times are
  /// observations. See [ReportedTime.isLive].
  final bool isLive;

  /// The stops with a vehicle entry spliced in where the vehicle is running
  /// between two of them.
  List<_TimelineEntry> get _entries => [
    for (int i = 0; i < stops.length; i++) ...[
      _TimelineEntry.stop(stops[i], i),
      if (position.sitsBetweenStops(i, stops.length)) _TimelineEntry.vehicle(),
    ],
  ];

  int get _lastServedStopIndex => position.lastServedStopIndex(stops.length);
  int get _upcomingStopIndex => position.upcomingStopIndex(stops.length);

  bool _isPassed(int stopIndex) => stopIndex <= _lastServedStopIndex;

  Color get _passedRouteColor =>
      routeColor.withValues(alpha: _kPassedLineOpacity);

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    return FixedTimeline.tileBuilder(
      theme: TimelineThemeData(
        nodePosition: 0.08,
        color: routeColor,
        indicatorTheme: const IndicatorThemeData(size: _kVehicleMarkerSize),
        connectorTheme: const ConnectorThemeData(thickness: 2.5),
      ),
      builder: TimelineTileBuilder.connected(
        itemCount: entries.length,
        connectionDirection: ConnectionDirection.before,
        contentsBuilder: (context, index) => _buildContents(entries[index]),
        indicatorBuilder: (context, index) => _buildIndicator(entries[index]),
        connectorBuilder: (context, index, connectorType) =>
            _buildConnector(entries, index),
      ),
    );
  }

  Widget _buildContents(_TimelineEntry entry) {
    if (entry.isVehicle) return const SizedBox.shrink();
    return _StopContents(
      stop: entry.stop!,
      stopIndex: entry.stopIndex,
      isTerminal: _isTerminal(entry.stopIndex),
      isPassed: _isPassed(entry.stopIndex),
      isUpcoming: entry.stopIndex == _upcomingStopIndex,
      routeColor: routeColor,
      isLive: isLive,
      onStopTap: onStopTap,
    );
  }

  Widget _buildIndicator(_TimelineEntry entry) {
    if (entry.isVehicle) return _buildRunningVehicleIndicator();

    final stopIndex = entry.stopIndex;
    final dotSize = _isTerminal(stopIndex)
        ? _kTerminalDotSize
        : _kIntermediateDotSize;
    final dotColor = _isPassed(stopIndex) ? _passedRouteColor : routeColor;
    final isVehicleHere = position.isAtStop && stopIndex == position.stopIndex;

    return TimelineIndicatorBox(
      lineColor: dotColor,
      centerGap: isVehicleHere ? _kVehicleMarkerSize : dotSize,
      cutTop: stopIndex == 0,
      cutBottom: stopIndex == stops.length - 1,
      child: isVehicleHere
          ? Stack(
              alignment: Alignment.center,
              children: [
                DotIndicator(color: dotColor, size: dotSize),
                _vehicleBadge(),
              ],
            )
          : Center(
              child: DotIndicator(color: dotColor, size: dotSize),
            ),
    );
  }

  /// The vehicle drawn on the line itself, between two stops.
  Widget _buildRunningVehicleIndicator() => TimelineIndicatorBox(
    lineColor: routeColor,
    child: DecoratedBox(
      decoration: BoxDecoration(color: routeColor, shape: BoxShape.circle),
      child: Center(child: Icon(modeIcon, size: 14, color: routeTextColor)),
    ),
  );

  Widget _vehicleBadge() => Container(
    width: _kVehicleMarkerSize,
    height: _kVehicleMarkerSize,
    decoration: BoxDecoration(color: routeColor, shape: BoxShape.circle),
    child: Icon(modeIcon, size: 14, color: routeTextColor),
  );

  Widget _buildConnector(List<_TimelineEntry> entries, int index) {
    final isPassed = index < entries.length && _isEntryPassed(entries[index]);
    return SolidLineConnector(color: isPassed ? _passedRouteColor : routeColor);
  }

  /// A vehicle entry only ever sits behind the vehicle, so the line up to it
  /// has been travelled.
  bool _isEntryPassed(_TimelineEntry entry) =>
      entry.isVehicle || _isPassed(entry.stopIndex);

  bool _isTerminal(int stopIndex) =>
      stopIndex == 0 || stopIndex == stops.length - 1;
}

/// One row of the timeline: either a stop, or the vehicle running between two.
class _TimelineEntry {
  const _TimelineEntry._(this.stop, this.stopIndex);

  _TimelineEntry.stop(JourneyStop stop, int index) : this._(stop, index);
  _TimelineEntry.vehicle() : this._(null, kNoStopIndex);

  final JourneyStop? stop;
  final int stopIndex;

  bool get isVehicle => stop == null;
}

class _StopContents extends StatelessWidget {
  const _StopContents({
    required this.stop,
    required this.stopIndex,
    required this.isTerminal,
    required this.isPassed,
    required this.isUpcoming,
    required this.routeColor,
    required this.isLive,
    required this.onStopTap,
  });

  final JourneyStop stop;
  final int stopIndex;
  final bool isTerminal;
  final bool isPassed;
  final bool isUpcoming;
  final Color routeColor;
  final bool isLive;
  final StopTapCallback onStopTap;

  /// A stop the vehicle has left fades with the rest of its text; its times
  /// keep their colours underneath.
  Widget _passable(Widget child) =>
      isPassed ? Opacity(opacity: _kPassedTextOpacity, child: child) : child;

  @override
  Widget build(BuildContext context) {
    final arrival = ReportedTime.from(
      stop.arrival,
      stop.scheduledArrival,
      isLive: isLive,
    );
    final departure = ReportedTime.from(
      stop.departure,
      stop.scheduledDeparture,
      isLive: isLive,
    );
    final arrivalRow = arrival == null
        ? null
        : _passable(
            DelayedTime.inline(
              arrival,
              label: 'Arr',
              isArrival: departure != null,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          );
    final departureRow = departure == null
        ? null
        : _passable(
            DelayedTime.inline(
              departure,
              label: 'Dep',
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          );

    return GestureDetector(
      onTap: stop.stopId == null ? null : _openStop,
      child: Padding(
        padding: const EdgeInsets.only(left: 12, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildNameRow(),
            if (arrivalRow != null || departureRow != null) ...[
              const SizedBox(height: 2),
              if (arrivalRow != null) arrivalRow,
              if (departureRow != null) ...[
                if (arrivalRow != null) const SizedBox(height: 2),
                departureRow,
              ],
            ],
            if (stop.track != null) ...[
              const SizedBox(height: 2),
              Text(
                'Track ${stop.track}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.black.withValues(
                    alpha: isPassed ? 0.4 : 0.5,
                  ),
                ),
              ),
            ],
            if (stop.cancelled) ...[
              const SizedBox(height: 2),
              Text(
                'CANCELLED',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.cancelled,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            GtfsFieldsRow(fields: {'stop': stop.stopId}),
          ],
        ),
      ),
    );
  }

  void _openStop() => onStopTap(
    stopId: stop.stopId,
    stopName: stop.name,
    referenceTime: stop.timeAtStop ?? DateTime.now().toUtc(),
  );

  Widget _buildNameRow() => Row(
    children: [
      Expanded(
        child: Text(
          stop.name,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isTerminal || isUpcoming
                ? FontWeight.w600
                : FontWeight.normal,
            color: isPassed
                ? AppColors.black.withValues(alpha: _kPassedTextOpacity)
                : AppColors.black,
          ),
        ),
      ),
      if (isUpcoming) ...[
        const SizedBox(width: 8),
        _UpcomingBadge(routeColor: routeColor),
      ],
    ],
  );
}

class _UpcomingBadge extends StatelessWidget {
  const _UpcomingBadge({required this.routeColor});

  final Color routeColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: routeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'Upcoming',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: routeColor,
        ),
      ),
    );
  }
}
