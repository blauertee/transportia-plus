import 'dart:ui' show PathMetric;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/itinerary.dart';
import '../../theme/app_colors.dart';
import '../../utils/journey_colors.dart';
import '../../utils/journey_graph.dart';
import '../../utils/time_utils.dart';

/// Room left of the first column for the hour labels.
const double _kAxisWidth = 44;

/// Column width bounds: narrower and a two-line ride name stops fitting,
/// wider and a handful of results spreads into a sparse grid.
const double _kMinColumn = 40;
const double _kMaxColumn = 72;

const double _kBarWidth = 30;

/// Space above the first departure and below the last arrival, for the
/// labels that hang off either end.
const double _kTopPad = 16;
const double _kBottomPad = 44;

/// Every change is drawn in this one colour: a change is no service, and a
/// spline in a line's colour would read as more of that line.
const Color _kChangeColor = kStreetLegColor;

/// The results of one search as a graph: a column per result, ordered by
/// departure, time running down. A ride several results share is drawn once,
/// centred across their columns, and changes are splines between rides.
///
/// Tapping a station or a ride locks it; what a lock does is up to the
/// caller.
class JourneyGraphView extends StatelessWidget {
  const JourneyGraphView({
    super.key,
    required this.graph,
    this.locks = const JourneyLocks(),
    this.onStationTap,
    this.onRideTap,
  });

  final JourneyGraph graph;
  final JourneyLocks locks;
  final ValueChanged<GraphStation>? onStationTap;
  final ValueChanged<GraphRide>? onRideTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final column =
            ((constraints.maxWidth - _kAxisWidth - 8) / graph.columnCount)
                .clamp(_kMinColumn, _kMaxColumn);
        final geometry = _Geometry(graph, column);
        final width = _kAxisWidth + column * graph.columnCount + 8;
        final canvas = SizedBox(
          width: width,
          height: _kTopPad + graph.height + _kBottomPad,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GraphPainter(
                    geometry,
                    DefaultTextStyle.of(context).style,
                  ),
                ),
              ),
              for (final ride in graph.rides) _rideBar(geometry, ride, accent),
              ..._stationMarkers(geometry, accent),
              for (final arrival in graph.arrivals)
                _arrivalLabel(geometry, arrival),
            ],
          ),
        );
        if (width <= constraints.maxWidth) return canvas;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: canvas,
        );
      },
    );
  }

  Widget _rideBar(_Geometry g, GraphRide ride, Color accent) {
    final top = g.y(ride.leg.startTime);
    final height = g.y(ride.leg.endTime) - top;
    final color = legSpineColor(
      leg: ride.leg,
      background: AppColors.white,
      accent: accent,
    );
    final locked = locks.rideKeys.contains(ride.key);
    return Positioned(
      left: g.x(ride.slot) - _kBarWidth / 2,
      top: top,
      width: _kBarWidth,
      height: height,
      child: GestureDetector(
        onTap: onRideTap == null ? null : () => onRideTap!(ride),
        child: _RideBar(
          ride: ride,
          color: color,
          height: height,
          locked: locked,
          lockColor: accent,
        ),
      ),
    );
  }

  /// A marker where each change gets off, and another where it gets on when
  /// that is a different station.
  List<Widget> _stationMarkers(_Geometry g, Color accent) {
    final seen = <String>{};
    final markers = <Widget>[];
    void add(GraphStation station, double slot, DateTime at, bool above) {
      if (!seen.add('${station.key}@$slot@${at.millisecondsSinceEpoch}')) {
        return;
      }
      markers.add(
        _StationMarker.positioned(
          station: station,
          center: Offset(g.x(slot), g.y(at)),
          width: g.column + 24,
          above: above,
          locked: locks.stationKeys.contains(station.key),
          accent: accent,
          onTap: onStationTap == null ? null : () => onStationTap!(station),
        ),
      );
    }

    for (final change in graph.changes) {
      add(
        change.from.alighting,
        change.from.slot,
        change.from.leg.endTime,
        false,
      );
      if (change.changesStation) {
        add(change.to.boarding, change.to.slot, change.to.leg.startTime, true);
      }
    }
    return markers;
  }

  Widget _arrivalLabel(_Geometry g, GraphArrival arrival) {
    return Positioned(
      left: g.x(arrival.ride.slot) - 30,
      top: g.y(arrival.ride.leg.endTime) + 2,
      width: 60,
      child: Column(
        children: [
          Icon(LucideIcons.chevronDown, size: 14, color: AppColors.black),
          Text(
            formatTime(arrival.time),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.black,
            ),
          ),
        ],
      ),
    );
  }
}

/// Where things go: columns across, the graph's compressed time down.
class _Geometry {
  const _Geometry(this.graph, this.column);

  final JourneyGraph graph;
  final double column;

  double x(double slot) => _kAxisWidth + (slot + 0.5) * column;
  double y(DateTime time) => _kTopPad + graph.yOf(time);
}

class _RideBar extends StatelessWidget {
  const _RideBar({
    required this.ride,
    required this.color,
    required this.height,
    required this.locked,
    required this.lockColor,
  });

  final GraphRide ride;
  final Color color;
  final double height;
  final bool locked;
  final Color lockColor;

  @override
  Widget build(BuildContext context) {
    final onColor = color.computeLuminance() > 0.5
        ? AppColors.solidBlack
        : AppColors.solidWhite;
    final (line, number) = _splitName(ride.leg);
    TextStyle style(double size, FontWeight weight) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: onColor,
      height: 1.15,
    );
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: locked
                ? Border.all(color: AppColors.black, width: 2.5)
                : null,
          ),
          padding: const EdgeInsets.only(top: 3),
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(line, maxLines: 1, style: style(10, FontWeight.w800)),
              if (number != null && height > 36)
                Text(number, maxLines: 1, style: style(8.5, FontWeight.w500)),
              if (height > 50)
                Text(
                  formatTime(ride.leg.startTime),
                  maxLines: 1,
                  style: style(8.5, FontWeight.w500),
                ),
            ],
          ),
        ),
        if (locked)
          Positioned(right: -7, top: -7, child: _LockBadge(color: lockColor)),
      ],
    );
  }

  /// "ICE 1507" → ICE over 1507; "RB15 (84284)" → RB15 alone.
  static (String, String?) _splitName(Leg leg) {
    final raw = leg.displayName ?? leg.routeShortName ?? '';
    final name = raw.split(' (').first.trim();
    final space = name.indexOf(' ');
    if (space < 0) return (name, null);
    return (name.substring(0, space), name.substring(space + 1));
  }
}

class _StationMarker extends StatelessWidget {
  const _StationMarker({
    required this.station,
    required this.above,
    required this.locked,
    required this.accent,
    this.onTap,
  });

  final GraphStation station;
  final bool above;
  final bool locked;
  final Color accent;
  final VoidCallback? onTap;

  static const double _dot = 9;
  static const double _labelHeight = 15;

  /// Positioned so the dot sits on [center], the label hanging below it, or
  /// above it for a station walked to.
  static Widget positioned({
    required GraphStation station,
    required Offset center,
    required double width,
    required bool above,
    required bool locked,
    required Color accent,
    VoidCallback? onTap,
  }) {
    return Positioned(
      left: center.dx - width / 2,
      top: above ? center.dy - _dot / 2 - _labelHeight : center.dy - _dot / 2,
      width: width,
      child: _StationMarker(
        station: station,
        above: above,
        locked: locked,
        accent: accent,
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = locked ? accent : AppColors.black;
    final dot = Container(
      width: _dot,
      height: _dot,
      decoration: BoxDecoration(
        color: locked ? accent : AppColors.white,
        shape: BoxShape.circle,
        border: Border.all(color: ink, width: 1.8),
      ),
    );
    final label = Container(
      height: _labelHeight,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked) ...[
            Icon(LucideIcons.lock, size: 9, color: ink),
            const SizedBox(width: 2),
          ],
          Flexible(
            child: Text(
              shortStationName(station.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: ink,
              ),
            ),
          ),
        ],
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: above ? [label, dot] : [dot, label],
      ),
    );
  }
}

class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.white, width: 1.5),
      ),
      alignment: Alignment.center,
      child: const Icon(LucideIcons.lock, size: 9, color: AppColors.solidWhite),
    );
  }
}

/// A station name short enough for one column: "S Südkreuz Bhf (Berlin)"
/// becomes "Südkreuz".
String shortStationName(String name) {
  var short = name
      .replaceFirst(RegExp(r'^(S\+U|S|U)\s+'), '')
      .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
      .replaceAll(RegExp(r'\s+(Bhf|Bahnhof)$'), '')
      .replaceAll('Hauptbahnhof', 'Hbf');
  if (short.contains(', ')) short = short.split(', ').last;
  return short.trim();
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(this.g, this.textStyle);

  final _Geometry g;

  /// The ambient text style, for its font: a painter inherits none.
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    _paintHours(canvas, size);
    final paint = Paint()
      ..color = _kChangeColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final change in g.graph.changes) {
      final from = Offset(g.x(change.from.slot), g.y(change.from.leg.endTime));
      final to = Offset(g.x(change.to.slot), g.y(change.to.leg.startTime));
      final bend = (to.dy - from.dy) / 2;
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..cubicTo(from.dx, from.dy + bend, to.dx, to.dy - bend, to.dx, to.dy);
      canvas.drawPath(change.changesStation ? _dashed(path) : path, paint);
    }
  }

  void _paintHours(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    final start = g.graph.start.toLocal();
    var hour = DateTime(start.year, start.month, start.day, start.hour + 1);
    while (hour.isBefore(g.graph.end)) {
      final y = g.y(hour);
      canvas.drawLine(Offset(_kAxisWidth - 4, y), Offset(size.width, y), line);
      final label = TextPainter(
        text: TextSpan(
          text: formatTime(hour),
          style: textStyle.copyWith(
            fontSize: 10,
            color: AppColors.black.withValues(alpha: 0.45),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, Offset(_kAxisWidth - 8 - label.width, y - 6));
      hour = hour.add(const Duration(hours: 1));
    }
  }

  static Path _dashed(Path source) {
    const dash = 4.0, gap = 4.0;
    final out = Path();
    for (final PathMetric metric in source.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += dash + gap) {
        out.addPath(metric.extractPath(d, d + dash), Offset.zero);
      }
    }
    return out;
  }

  @override
  bool shouldRepaint(_GraphPainter old) =>
      old.g.graph != g.graph || old.g.column != g.column;
}
