import 'dart:ui' show PathMetric;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/itinerary.dart';
import '../../theme/app_colors.dart';
import '../../utils/duration_formatter.dart';
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

/// The row of journey durations above the columns.
const double _kHeaderHeight = 24;

/// Space above the first departure and below the last arrival, for the
/// labels that hang off either end.
const double _kTopPad = 14;
const double _kBottomPad = 44;

/// How far everything off the selected result fades: still readable, so the
/// other options stay one tap away, but clearly behind the selected one.
const double _kUnselectedOpacity = 0.35;

/// Every change is drawn in this one colour: a change is no service, and a
/// spline in a line's colour would read as more of that line.
const Color _kChangeColor = kStreetLegColor;

/// The results of one search as a graph: a column per result, ordered by
/// departure, time running down. A ride several results share is drawn once,
/// centred across their columns, and changes are splines between rides.
///
/// One result is always [selected]; everything else fades. Tapping anything
/// off the selected result selects a result through it. Tapping a station or
/// a ride on the selected result locks it; what a lock does is up to the
/// caller.
class JourneyGraphView extends StatelessWidget {
  const JourneyGraphView({
    super.key,
    required this.graph,
    required this.selected,
    required this.onSelect,
    this.locks = const JourneyLocks(),
    this.onStationTap,
    this.onRideTap,
  });

  final JourneyGraph graph;

  /// Index into [JourneyGraph.itineraries].
  final int selected;
  final ValueChanged<int> onSelect;
  final JourneyLocks locks;
  final ValueChanged<GraphStation>? onStationTap;
  final ValueChanged<GraphRide>? onRideTap;

  /// What a tap on something [through] those results does: [lock] it when
  /// the selected result is among them, else select the first of them.
  VoidCallback _tap(List<int> through, VoidCallback? lock) {
    if (through.contains(selected)) return lock ?? () {};
    return () => onSelect(through.first);
  }

  Widget _fade(bool onSelected, Widget child) =>
      onSelected ? child : Opacity(opacity: _kUnselectedOpacity, child: child);

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
          height: _kHeaderHeight + _kTopPad + graph.height + _kBottomPad,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GraphPainter(
                    geometry,
                    DefaultTextStyle.of(context).style,
                    lockedUpTo: _lockPoint?.leg.endTime,
                    accent: accent,
                    selected: selected,
                  ),
                ),
              ),
              for (var i = 0; i < graph.columnCount; i++)
                _durationLabel(geometry, i),
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

  /// The latest locked ride: everything up to where it gets off is fixed,
  /// and the next search starts there.
  GraphRide? get _lockPoint {
    GraphRide? latest;
    for (final ride in graph.rides) {
      if (!locks.rideKeys.contains(ride.key)) continue;
      if (latest == null || ride.leg.endTime.isAfter(latest.leg.endTime)) {
        latest = ride;
      }
    }
    return latest;
  }

  Widget _durationLabel(_Geometry g, int column) {
    return Positioned(
      left: g.x(column.toDouble()) - g.column / 2,
      top: 4,
      width: g.column,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(column),
        child: _fade(
          column == selected,
          Text(
            formatDuration(graph.itineraries[column].duration),
            textAlign: TextAlign.center,
            maxLines: 1,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.black,
            ),
          ),
        ),
      ),
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
        onTap: _tap(
          ride.itineraries,
          onRideTap == null ? null : () => onRideTap!(ride),
        ),
        child: _fade(
          ride.itineraries.contains(selected),
          _RideBar(
            ride: ride,
            color: color,
            height: height,
            locked: locked,
            lockColor: accent,
          ),
        ),
      ),
    );
  }

  /// A marker where each change gets off, and another where it gets on when
  /// that is a different station.
  List<Widget> _stationMarkers(_Geometry g, Color accent) {
    final seen = <String>{};
    final markers = <Widget>[];
    void add(
      GraphStation station,
      GraphRide ride,
      DateTime at, {
      required bool above,
    }) {
      final slot = ride.slot;
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
          onSelected: ride.itineraries.contains(selected),
          onTap: _tap(
            ride.itineraries,
            onStationTap == null ? null : () => onStationTap!(station),
          ),
        ),
      );
    }

    for (final change in graph.changes) {
      add(
        change.from.alighting,
        change.from,
        change.from.leg.endTime,
        above: false,
      );
      if (change.changesStation) {
        add(
          change.to.boarding,
          change.to,
          change.to.leg.startTime,
          above: true,
        );
      }
    }
    return markers;
  }

  Widget _arrivalLabel(_Geometry g, GraphArrival arrival) {
    return Positioned(
      left: g.x(arrival.ride.slot) - 30,
      top: g.y(arrival.ride.leg.endTime) + 2,
      width: 60,
      child: _fade(
        arrival.itineraries.contains(selected),
        Column(
          children: [
            Icon(LucideIcons.chevronDown, size: 14, color: AppColors.black),
            Text(
              formatTime(arrival.time),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.black,
              ),
            ),
          ],
        ),
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
  double y(DateTime time) => _kHeaderHeight + _kTopPad + graph.yOf(time);
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
    required this.locked,
    required this.accent,
    required this.onSelected,
    this.onTap,
  });

  final GraphStation station;
  final bool locked;
  final bool onSelected;
  final Color accent;
  final VoidCallback? onTap;

  static const double _labelHeight = 15;

  /// Positioned so the label hangs below [center], the end of a ride, or
  /// sits above it, the start of a ride walked to.
  static Widget positioned({
    required GraphStation station,
    required Offset center,
    required double width,
    required bool above,
    required bool locked,
    required Color accent,
    required bool onSelected,
    VoidCallback? onTap,
  }) {
    return Positioned(
      left: center.dx - width / 2,
      top: above ? center.dy - _labelHeight - 1 : center.dy + 1,
      width: width,
      child: _StationMarker(
        station: station,
        locked: locked,
        accent: accent,
        onSelected: onSelected,
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = locked ? accent : AppColors.black;
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
                fontSize: 10,
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
      child: Center(
        child: onSelected
            ? label
            : Opacity(opacity: _kUnselectedOpacity, child: label),
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
  _GraphPainter(
    this.g,
    this.textStyle, {
    required this.lockedUpTo,
    required this.accent,
    required this.selected,
  });

  final _Geometry g;

  /// Where the locked part of the journey ends, if anything is locked.
  final DateTime? lockedUpTo;
  final Color accent;
  final int selected;

  /// The ambient text style, for its font: a painter inherits none.
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    _paintHours(canvas, size);
    _paintLockLine(canvas, size);
    for (final change in g.graph.changes) {
      final onSelected =
          change.from.itineraries.contains(selected) &&
          change.to.itineraries.contains(selected);
      final paint = Paint()
        ..color = onSelected
            ? _kChangeColor
            : _kChangeColor.withValues(alpha: _kUnselectedOpacity)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final from = Offset(g.x(change.from.slot), g.y(change.from.leg.endTime));
      final to = Offset(g.x(change.to.slot), g.y(change.to.leg.startTime));
      final bend = (to.dy - from.dy) / 2;
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..cubicTo(from.dx, from.dy + bend, to.dx, to.dy - bend, to.dx, to.dy);
      canvas.drawPath(change.changesStation ? _dashed(path) : path, paint);
    }
  }

  /// A dashed accent rule where the locked part ends, with a lock on its
  /// right end: above it is fixed, below it is what a new search finds.
  void _paintLockLine(Canvas canvas, Size size) {
    final at = lockedUpTo;
    if (at == null) return;
    final y = g.y(at);
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawPath(
      _dashed(
        Path()
          ..moveTo(_kAxisWidth - 4, y)
          ..lineTo(size.width, y),
      ),
      paint,
    );
    final icon = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(LucideIcons.lock.codePoint),
        style: TextStyle(
          fontSize: 12,
          fontFamily: LucideIcons.lock.fontFamily,
          package: LucideIcons.lock.fontPackage,
          color: accent,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    icon.paint(
      canvas,
      Offset(size.width - icon.width - 4, y - icon.height - 2),
    );
  }

  void _paintHours(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(_kAxisWidth, _kHeaderHeight),
      Offset(size.width, _kHeaderHeight),
      line,
    );
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
      old.g.graph != g.graph ||
      old.g.column != g.column ||
      old.lockedUpTo != lockedUpTo ||
      old.accent != accent ||
      old.selected != selected;
}
