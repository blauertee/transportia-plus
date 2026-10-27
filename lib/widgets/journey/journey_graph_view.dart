import 'dart:math' as math;
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

const double _kBarWidth = 30;
const double _kBarRadius = 6;

/// Station names are cut to this many characters, so the widest label is
/// known before laying out the columns.
const int _kMaxStationChars = 12;

/// Room kept between a station label and the bar in the next column.
const double _kLabelClearance = 8;

/// The narrowest column, for results that only pass short station names.
const double _kMinColumn = 48;

/// The row of journey durations above the columns.
const double _kHeaderHeight = 24;

/// Space above the first departure and below the last arrival, for the
/// labels that hang off either end.
const double _kTopPad = 14;
const double _kBottomPad = 44;

/// Zoom bounds, in pixels per minute: from a whole day on one screen to a
/// few minutes filling it.
const double _kMinZoom = 0.2;
const double _kMaxZoom = 12;

/// Below this, two fingers count as side by side, and their vertical
/// distance says nothing about zoom.
const double _kMinPinchSpan = 24;

/// The least room between two time labels on the axis.
const double _kMinLabelGap = 28;

/// The steps the axis may label, finest first.
const List<int> _kLabelMinutes = [10, 15, 30, 60, 120, 180, 360];

/// How far everything off the selected result fades: still readable, so the
/// other options stay one tap away, but clearly behind the selected one.
const double _kUnselectedOpacity = 0.35;

/// Every change is drawn in this one colour: a change is no service, and a
/// spline in a line's colour would read as more of that line.
const Color _kChangeColor = kStreetLegColor;

/// Ways to show a locked ride, side by side while the design is open. In
/// all but [tab], the station where the lock ends carries the lock icon in
/// its label, and the rides themselves carry no icon.
enum LockStyle {
  /// A tab off the right side of each locked bar.
  tab,

  /// A thin accent rail alongside each locked bar.
  rail,

  /// A soft accent band behind the locked part of the journey.
  band,

  /// The time axis turns accent up to the lock point.
  axis,

  /// Nothing on the rides: only the station where the lock ends.
  label,
}

/// The results of one search as a graph: a column per result, ordered by
/// departure, time running down. A ride several results share is drawn once,
/// centred across their columns, and changes are splines between rides.
///
/// One result is always [selected]; everything else fades. Tapping anything
/// off the selected result selects a result through it. Tapping a station or
/// a ride on the selected result locks it; what a lock does is up to the
/// caller.
///
/// Time is linear and zooms vertically with two fingers. It opens at the
/// zoom where the first result to arrive fits the height it is given; where
/// a ride or a change is then too short for its text, the scale stretches
/// that stretch alone and the axis marks it as not to scale.
class JourneyGraphView extends StatefulWidget {
  const JourneyGraphView({
    super.key,
    required this.graph,
    required this.selected,
    required this.onSelect,
    this.locks = const JourneyLocks(),
    this.onStationTap,
    this.onRideTap,
    this.now,
    this.lockStyle = LockStyle.rail,
  });

  final JourneyGraph graph;

  /// Index into [JourneyGraph.itineraries].
  final int selected;
  final ValueChanged<int> onSelect;
  final JourneyLocks locks;
  final ValueChanged<GraphStation>? onStationTap;
  final ValueChanged<GraphRide>? onRideTap;

  /// Where the "now" line goes; the clock when null. Drawn only while the
  /// results are under way.
  final DateTime? now;

  final LockStyle lockStyle;

  @override
  State<JourneyGraphView> createState() => _JourneyGraphViewState();
}

class _JourneyGraphViewState extends State<JourneyGraphView> {
  final ScrollController _scroll = ScrollController();

  /// Null until fitted to the height available.
  double? _pxPerMinute;
  late GraphScale _scale;

  final Map<int, Offset> _pointers = {};
  double? _pinchStartSpan;
  double _pinchStartZoom = 1;
  DateTime? _pinchTime;
  double _pinchFocus = 0;

  JourneyGraph get graph => widget.graph;
  int get selected => widget.selected;
  ValueChanged<int> get onSelect => widget.onSelect;
  JourneyLocks get locks => widget.locks;
  ValueChanged<GraphStation>? get onStationTap => widget.onStationTap;
  ValueChanged<GraphRide>? get onRideTap => widget.onRideTap;

  @override
  void didUpdateWidget(JourneyGraphView old) {
    super.didUpdateWidget(old);
    if (old.graph == widget.graph) return;
    // New results: fit them afresh, from the top.
    _pxPerMinute = null;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _pinching => _pinchStartSpan != null;

  void _pointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length == 2) _startPinch();
  }

  void _pointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;
    if (_pinching) _updatePinch();
  }

  void _pointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    if (_pinching && _pointers.length < 2) {
      setState(() => _pinchStartSpan = null);
    }
  }

  void _startPinch() {
    final [a, b] = _pointers.values.toList();
    _pinchFocus = (a.dy + b.dy) / 2;
    setState(() {
      _pinchStartSpan = math.max((a.dy - b.dy).abs(), _kMinPinchSpan);
      _pinchStartZoom = _pxPerMinute!;
      // The moment under the fingers, which has to stay under them.
      _pinchTime = _scale.timeAt(_scroll.offset + _pinchFocus - _kTopPad);
    });
  }

  void _updatePinch() {
    final [a, b] = _pointers.values.toList();
    final span = math.max((a.dy - b.dy).abs(), _kMinPinchSpan);
    final zoom = (_pinchStartZoom * span / _pinchStartSpan!).clamp(
      _kMinZoom,
      _kMaxZoom,
    );
    final scale = GraphScale(graph, zoom);
    final offset = _kTopPad + scale.yOf(_pinchTime!) - _pinchFocus;
    setState(() => _pxPerMinute = zoom);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      _scroll.jumpTo(
        offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      );
    });
  }

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
        final column = math.max(
          (constraints.maxWidth - _kAxisWidth - 8) / graph.columnCount,
          _columnFor(context),
        );
        final zoom = _pxPerMinute ??= graph.fitPxPerMinute(
          graph.firstArrival,
          constraints.maxHeight - _kHeaderHeight - _kTopPad - _kBottomPad,
        );
        _scale = GraphScale(graph, zoom);
        final implicit = _implicitlyLocked;
        final geometry = _Geometry(graph, column, _scale);
        final width = _kAxisWidth + column * graph.columnCount + 8;
        final header = Container(
          width: width,
          height: _kHeaderHeight,
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.hairline)),
          ),
          child: Stack(
            children: [
              for (var i = 0; i < graph.columnCount; i++)
                _durationLabel(geometry, i),
            ],
          ),
        );
        final canvas = SizedBox(
          width: width,
          height: _kTopPad + _scale.height + _kBottomPad,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GraphPainter(
                    geometry,
                    DefaultTextStyle.of(context).style,
                    now: widget.now ?? DateTime.now(),
                    accent: accent,
                    selected: selected,
                    lockStyle: widget.lockStyle,
                    locked: [
                      for (final ride in graph.rides)
                        if (_lockOf(ride, implicit) != null) ride,
                    ],
                    lockEnd: _lockPoint?.leg.endTime,
                  ),
                ),
              ),
              for (final ride in graph.rides) _rideBar(geometry, ride, accent),
              ..._stationMarkers(geometry, accent),
              for (final ride in graph.rides)
                if (_lockOf(ride, implicit) case final lock?)
                  if (widget.lockStyle == LockStyle.tab)
                    _lockBadge(geometry, ride, lock, accent)
                  else if (widget.lockStyle == LockStyle.rail)
                    _lockRail(geometry, ride, lock, accent),
              for (final arrival in graph.arrivals)
                _arrivalLabel(geometry, arrival),
            ],
          ),
        );
        final body = SizedBox(
          width: width,
          height: constraints.maxHeight,
          child: Column(
            children: [
              header,
              Expanded(
                child: Listener(
                  onPointerDown: _pointerDown,
                  onPointerMove: _pointerMove,
                  onPointerUp: _pointerUp,
                  onPointerCancel: _pointerUp,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    physics: _pinching
                        ? const NeverScrollableScrollPhysics()
                        : null,
                    child: canvas,
                  ),
                ),
              ),
            ],
          ),
        );
        if (width <= constraints.maxWidth) return body;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: body,
        );
      },
    );
  }

  /// Wide enough that the longest station label, centred on its column,
  /// stops short of the bar in the next one.
  double _columnFor(BuildContext context) {
    final style = DefaultTextStyle.of(
      context,
    ).style.merge(_StationMarker.textStyle(AppColors.black));
    var widest = 0.0;
    for (final ride in graph.rides) {
      for (final station in [ride.boarding, ride.alighting]) {
        final label = TextPainter(
          text: TextSpan(text: stationLabel(station.name), style: style),
          textDirection: TextDirection.ltr,
        )..layout();
        widest = math.max(widest, label.width);
      }
    }
    final label = widest + _StationMarker.chrome;
    return math.max(_kMinColumn, label / 2 + _kBarWidth / 2 + _kLabelClearance);
  }

  /// Rides fixed because a later ride on the same results is locked: the
  /// journey is locked up to that point, so everything before it is too.
  Set<String> get _implicitlyLocked {
    final implicit = <String>{};
    for (final locked in graph.rides) {
      if (!locks.rideKeys.contains(locked.key)) continue;
      for (final ride in graph.rides) {
        if (ride.key == locked.key ||
            locks.rideKeys.contains(ride.key) ||
            ride.leg.endTime.isAfter(locked.leg.startTime)) {
          continue;
        }
        if (locked.itineraries.every(ride.itineraries.contains)) {
          implicit.add(ride.key);
        }
      }
    }
    return implicit;
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

  /// The latest locked ride: everything up to where it gets off is fixed.
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

  /// A thin rail beside the bar, as long as it: off to the side, where
  /// no label reaches.
  Widget _lockRail(_Geometry g, GraphRide ride, _Lock lock, Color accent) {
    final top = g.y(ride.leg.startTime);
    return Positioned(
      left: g.x(ride.slot) + _kBarWidth / 2 + 3,
      top: top + 2,
      width: 3,
      height: g.y(ride.leg.endTime) - top - 4,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: lock == _Lock.implicit
                ? accent.withValues(alpha: _kImplicitLockOpacity)
                : accent,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      ),
    );
  }

  _Lock? _lockOf(GraphRide ride, Set<String> implicit) =>
      locks.rideKeys.contains(ride.key)
      ? _Lock.explicit
      : implicit.contains(ride.key)
      ? _Lock.implicit
      : null;

  /// A tab off the right side of the bar, where its straight edge starts
  /// below the rounded corner: a bar has little height to spare but room
  /// to either side. Centred instead on a bar too short for that.
  Widget _lockBadge(_Geometry g, GraphRide ride, _Lock lock, Color accent) {
    final top = g.y(ride.leg.startTime);
    final height = g.y(ride.leg.endTime) - top;
    final inset = math.min(
      _kBarRadius,
      math.max(0.0, (height - _LockBadge.height) / 2),
    );
    return Positioned(
      left: g.x(ride.slot) + _kBarWidth / 2,
      top: top + inset,
      child: IgnorePointer(
        child: _LockBadge(
          color: legSpineColor(
            leg: ride.leg,
            background: AppColors.white,
            accent: accent,
          ),
          implicit: lock == _Lock.implicit,
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
          _RideBar(ride: ride, color: color, height: height),
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
          width: g.column * 2,
          above: above,
          locked: locks.stationKeys.contains(station.key),
          lockEnd:
              widget.lockStyle != LockStyle.tab &&
              !above &&
              locks.rideKeys.contains(ride.key),
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

/// Where things go: columns across, time down at the current zoom.
class _Geometry {
  const _Geometry(this.graph, this.column, this.scale);

  final JourneyGraph graph;
  final double column;
  final GraphScale scale;

  double x(double slot) => _kAxisWidth + (slot + 0.5) * column;
  double y(DateTime time) => _kTopPad + scale.yOf(time);
}

class _RideBar extends StatelessWidget {
  const _RideBar({
    required this.ride,
    required this.color,
    required this.height,
  });

  final GraphRide ride;
  final Color color;
  final double height;

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
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(_kBarRadius),
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
    this.lockEnd = false,
    this.onTap,
  });

  final GraphStation station;
  final bool locked;

  /// Where a locked ride gets off: the journey is fixed up to here.
  final bool lockEnd;
  final bool onSelected;
  final Color accent;
  final VoidCallback? onTap;

  static const double _labelHeight = 15;

  /// Width a label takes beyond its text: padding, and the lock icon a
  /// locked station shows.
  static const double chrome = 6 + 11;

  static TextStyle textStyle(Color color) =>
      TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color);

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
    bool lockEnd = false,
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
        lockEnd: lockEnd,
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
        color: lockEnd
            ? AppColors.accentWash(accent)
            : AppColors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (locked || lockEnd) ...[
            Icon(LucideIcons.lock, size: 9, color: locked ? ink : accent),
            const SizedBox(width: 2),
          ],
          Flexible(
            child: Text(
              stationLabel(station.name),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: textStyle(ink),
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

/// A ride locked by a tap, or fixed because a later one on the same
/// results was.
enum _Lock { explicit, implicit }

/// How much a lock that follows from another fades.
const double _kImplicitLockOpacity = 0.4;

/// A small tab joined to the right side of a locked bar: outlined in the
/// bar's colour, open where it meets the bar, round at its free end. A
/// lock that follows from a later one is the same tab, fainter.
class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.color, this.implicit = false});

  /// The colour of the bar it hangs off.
  final Color color;
  final bool implicit;

  static const double height = 24;

  /// The border, and the lock drawn in it with the same line.
  static const double _stroke = 1.5;

  @override
  Widget build(BuildContext context) {
    final edge = BorderSide(color: color, width: _stroke);
    final tab = Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(6, 0, 9, 0),
      decoration: BoxDecoration(
        border: Border(top: edge, right: edge, bottom: edge),
        borderRadius: const BorderRadius.horizontal(
          right: Radius.circular(height / 2),
        ),
      ),
      alignment: Alignment.center,
      child: CustomPaint(
        size: const Size.square(12),
        painter: _LockGlyph(color, _stroke),
      ),
    );
    return implicit ? Opacity(opacity: _kImplicitLockOpacity, child: tab) : tab;
  }
}

/// Lucide's lock, drawn rather than set from the icon font, so its line
/// can match the tab's border at any size.
class _LockGlyph extends CustomPainter {
  const _LockGlyph(this.color, this.stroke);

  final Color color;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    // Lucide draws on a 24 unit grid with the line inside it.
    final unit = size.width / 24;
    canvas.scale(unit);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke / unit
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromLTRBR(3, 11, 21, 22, const Radius.circular(2)),
      paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(7, 11)
        ..lineTo(7, 7)
        ..arcToPoint(const Offset(17, 7), radius: const Radius.circular(5))
        ..lineTo(17, 11),
      paint,
    );
  }

  @override
  bool shouldRepaint(_LockGlyph old) =>
      old.color != color || old.stroke != stroke;
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

/// [shortStationName], cut to [_kMaxStationChars] with an ellipsis.
String stationLabel(String name) {
  final short = shortStationName(name);
  if (short.length <= _kMaxStationChars) return short;
  return '${short.substring(0, _kMaxStationChars - 1).trimRight()}…';
}

class _GraphPainter extends CustomPainter {
  _GraphPainter(
    this.g,
    this.textStyle, {
    required this.now,
    required this.accent,
    required this.selected,
    required this.lockStyle,
    required this.locked,
    required this.lockEnd,
  });

  final LockStyle lockStyle;

  /// Every locked ride, set or implied.
  final List<GraphRide> locked;

  /// Where the locked part ends, if anything is locked.
  final DateTime? lockEnd;

  final _Geometry g;

  final DateTime now;
  final Color accent;
  final int selected;

  /// The ambient text style, for its font: a painter inherits none.
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (lockStyle == LockStyle.band) _paintLockBand(canvas);
    _paintHours(canvas, size);
    if (lockStyle == LockStyle.axis) _paintLockAxis(canvas);
    _paintNow(canvas, size);
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

  /// A soft accent band around the locked rides and the label where the
  /// lock ends.
  void _paintLockBand(Canvas canvas) {
    if (locked.isEmpty) return;
    final top = locked.map((r) => g.y(r.leg.startTime)).reduce(math.min);
    final bottom = g.y(lockEnd!) + 18;
    final left = locked.map((r) => g.x(r.slot)).reduce(math.min);
    final right = locked.map((r) => g.x(r.slot)).reduce(math.max);
    // Wide enough for the label where the lock ends.
    final inset = g.column / 2 + 4;
    canvas.drawRRect(
      RRect.fromLTRBR(
        left - inset,
        top - 6,
        right + inset,
        bottom,
        const Radius.circular(10),
      ),
      Paint()..color = AppColors.accentWash(accent),
    );
  }

  /// The axis turns accent from the first locked departure to the lock
  /// point, ending in a lock where an hour label would otherwise go.
  void _paintLockAxis(Canvas canvas) {
    if (locked.isEmpty) return;
    const x = _kAxisWidth - 2;
    final top = locked.map((r) => g.y(r.leg.startTime)).reduce(math.min);
    final end = g.y(lockEnd!);
    canvas.drawLine(
      Offset(x, top),
      Offset(x, end),
      Paint()
        ..color = accent
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(Offset(x, end), 9, Paint()..color = accent);
    canvas.save();
    canvas.translate(x - 5.5, end - 6);
    _LockGlyph(AppColors.solidWhite, 1.5).paint(canvas, const Size.square(11));
    canvas.restore();
  }

  /// An accent rule at the current time, with a dot on the axis, once the
  /// first result has left and until the last has arrived.
  void _paintNow(Canvas canvas, Size size) {
    if (now.isBefore(g.graph.start) || now.isAfter(g.graph.end)) return;
    final y = g.y(now);
    final paint = Paint()
      ..color = accent
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(_kAxisWidth - 2, y), Offset(size.width, y), paint);
    canvas.drawCircle(Offset(_kAxisWidth - 2, y), 4, paint);
  }

  /// Grid lines at the finest step that leaves room for their labels, and
  /// a break mark wherever the scale was stretched.
  void _paintHours(Canvas canvas, Size size) {
    final line = Paint()
      ..color = AppColors.hairline
      ..strokeWidth = 1;
    final step = _kLabelMinutes.firstWhere(
      (minutes) => minutes * g.scale.pxPerMinute >= _kMinLabelGap,
      orElse: () => _kLabelMinutes.last,
    );
    final start = g.graph.start.toLocal();
    final midnight = DateTime(start.year, start.month, start.day);
    var tick = midnight.add(
      Duration(
        minutes: (start.difference(midnight).inMinutes ~/ step + 1) * step,
      ),
    );
    var lastLabel = double.negativeInfinity;
    while (tick.isBefore(g.graph.end)) {
      final y = g.y(tick);
      canvas.drawLine(Offset(_kAxisWidth - 4, y), Offset(size.width, y), line);
      // A stretch can push two ticks together; skip a label that would
      // overlap the one above.
      final nearLock =
          lockStyle == LockStyle.axis &&
          lockEnd != null &&
          (y - g.y(lockEnd!)).abs() < 14;
      if (y - lastLabel >= _kMinLabelGap / 2 && !nearLock) {
        final label = TextPainter(
          text: TextSpan(
            text: formatTime(tick),
            style: textStyle.copyWith(
              fontSize: 10,
              color: AppColors.black.withValues(alpha: 0.45),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        label.paint(canvas, Offset(_kAxisWidth - 8 - label.width, y - 6));
        lastLabel = y;
      }
      tick = tick.add(Duration(minutes: step));
    }

    // The axis is solid where time is to scale and dotted where it was
    // stretched to fit labels.
    final axis = Paint()
      ..color = AppColors.black.withValues(alpha: 0.3)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const x = _kAxisWidth - 2;
    var y = _kTopPad;
    final bottom = _kTopPad + g.scale.height;
    for (final (from, to) in g.scale.stretchedSpans) {
      canvas.drawLine(Offset(x, y), Offset(x, _kTopPad + from), axis);
      canvas.drawPath(
        _dashed(
          Path()
            ..moveTo(x, _kTopPad + from)
            ..lineTo(x, _kTopPad + to),
          dash: 1.5,
          gap: 3,
        ),
        axis,
      );
      y = _kTopPad + to;
    }
    canvas.drawLine(Offset(x, y), Offset(x, bottom), axis);
  }

  static Path _dashed(Path source, {double dash = 4, double gap = 4}) {
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
      old.g.scale != g.scale ||
      old.g.column != g.column ||
      old.now != now ||
      old.lockStyle != lockStyle ||
      old.lockEnd != lockEnd ||
      old.accent != accent ||
      old.selected != selected;
}
