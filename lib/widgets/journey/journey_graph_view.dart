import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/cupertino.dart' show CupertinoActivityIndicator;
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

const double _kBarWidth = 36;
const double _kBarRadius = 6;

/// Station names are cut to this many characters, so the widest label is
/// known before laying out the columns.
const int _kMaxStationChars = 12;

/// Room kept between anything in one column and anything beside it at the
/// same time in the next: bars, station names, badges and arrivals.
const double _kSideMargin = 8;

/// Room kept between two durations in the header.
const double _kHeaderGap = 14;

/// Room right of the last column.
const double _kRightPad = 8;

/// The time hung under each result's last ride.
const double _kArrivalWidth = 40;
const double _kArrivalHeight = 32;

TextStyle get _durationStyle => TextStyle(
  fontSize: 11,
  fontWeight: FontWeight.w700,
  color: AppColors.black,
);

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

/// How far the graph has to be pulled past its left or right edge to load
/// the results before or after it.
const double _kPullToLoad = 64;

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
///
/// Time is linear and zooms vertically with two fingers. It opens at the
/// zoom where the first result to arrive fits the height it is given; where
/// a ride or a change is then too short for its text, the scale stretches
/// that stretch alone and the axis marks it as not to scale.
///
/// Pulled past its left edge it asks for earlier results with
/// [onLoadEarlier], and past its right edge for later ones with
/// [onLoadLater]. When they come, it keeps its zoom, and keeps what was on
/// screen where it was.
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
    this.onLoadEarlier,
    this.onLoadLater,
    this.loadingEarlier = false,
    this.loadingLater = false,
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

  /// Null when there are no results that way.
  final VoidCallback? onLoadEarlier;
  final VoidCallback? onLoadLater;
  final bool loadingEarlier;
  final bool loadingLater;

  @override
  State<JourneyGraphView> createState() => _JourneyGraphViewState();
}

class _JourneyGraphViewState extends State<JourneyGraphView> {
  final ScrollController _scroll = ScrollController();
  final ScrollController _across = ScrollController();

  /// How far the graph is pulled past an edge: negative past the left one.
  final ValueNotifier<double> _pull = ValueNotifier(0);

  /// Whether this drag has already asked for a page.
  bool _pulled = false;

  /// Null until fitted to the height available.
  double? _pxPerMinute;

  /// The zoom it was fitted at, which the columns are spaced for.
  double? _fittedPxPerMinute;
  late GraphScale _scale;

  /// Text widths, measured once per graph.
  final Map<String, double> _textWidths = {};

  /// The last spacing worked out, and what it was worked out for.
  (double, RideBadges, String)? _spacedFor;
  ({List<double> xs, double width}) _columns = (xs: const [], width: 0);

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
    _spacedFor = null;
    final before = old.graph.itineraries;
    final kept = before.isEmpty
        ? -1
        : widget.graph.itineraries.indexOf(before.first);
    if (kept < 0 || _pxPerMinute == null) {
      // New results: fit them afresh, from the top.
      _pxPerMinute = null;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      if (_across.hasClients) _across.jumpTo(0);
      return;
    }
    // A page more of the same results: keep the zoom, and keep the moment
    // at the top and the first result shown before where they were.
    final top = _scale.timeAt(
      _scroll.hasClients ? _scroll.offset - _kTopPad : 0,
    );
    final x = _columns.xs.isEmpty ? 0.0 : _columns.xs.first;
    final across = _across.hasClients ? _across.offset : 0.0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        final position = _scroll.position;
        _scroll.jumpTo(
          (_kTopPad + _scale.yOf(top)).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
      if (_across.hasClients && kept < _columns.xs.length) {
        final position = _across.position;
        _across.jumpTo(
          (across + _columns.xs[kept] - x).clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _across.dispose();
    _pull.dispose();
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
    final scale = GraphScale(graph, zoom, badges: _badges);
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
        final implicit = _implicitlyLocked;
        final badges = _badges;
        final zoom = _pxPerMinute ??= _fittedPxPerMinute = graph.fitPxPerMinute(
          graph.firstArrival,
          constraints.maxHeight - _kHeaderHeight - _kTopPad - _kBottomPad,
          badges: badges,
        );
        _scale = GraphScale(graph, zoom, badges: badges);
        final columns = _spaceColumns(context, badges);
        final geometry = _Geometry(graph, columns.xs, _scale);
        // Never narrower than the screen: the graph keeps to the left, and
        // the grid runs on to the edge.
        final width = math.max(columns.width, constraints.maxWidth);
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
              for (var i = 1; i < graph.columnCount; i++)
                _headerDivider(geometry, i),
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
                  ),
                ),
              ),
              for (final ride in graph.rides) _rideBar(geometry, ride, accent),
              ..._stationMarkers(geometry, accent, badges.keys),
              for (final ride in graph.rides)
                if (_lockOf(ride, implicit) case final lock?)
                  _lockBadge(geometry, ride, lock, accent),
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
        // Always scrollable across, however few results, so it can be
        // pulled past either edge for more.
        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _scrolledAcross,
              child: SingleChildScrollView(
                controller: _across,
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                child: body,
              ),
            ),
            _edgeHint(left: true),
            _edgeHint(left: false),
          ],
        );
      },
    );
  }

  /// Follows a pull past either edge, and asks for a page once per drag
  /// when it goes far enough.
  bool _scrolledAcross(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.horizontal) {
      return false;
    }
    final metrics = notification.metrics;
    final past = metrics.pixels < metrics.minScrollExtent
        ? metrics.pixels - metrics.minScrollExtent
        : metrics.pixels > metrics.maxScrollExtent
        ? metrics.pixels - metrics.maxScrollExtent
        : 0.0;
    _pull.value = past;
    if (notification is ScrollStartNotification) _pulled = false;
    final dragging =
        notification is ScrollUpdateNotification &&
        notification.dragDetails != null;
    if (dragging && !_pulled && past.abs() >= _kPullToLoad) {
      final load = past < 0 ? widget.onLoadEarlier : widget.onLoadLater;
      if (load != null) {
        _pulled = true;
        load();
      }
    }
    return false;
  }

  /// What pulling past an edge does, in the gap the pull opens: say so
  /// while pulling, and show the page loading once asked for.
  Widget _edgeHint({required bool left}) {
    final load = left ? widget.onLoadEarlier : widget.onLoadLater;
    final loading = left ? widget.loadingEarlier : widget.loadingLater;
    final muted = AppColors.black.withValues(alpha: 0.6);
    return Positioned(
      left: left ? 0 : null,
      right: left ? null : 0,
      top: 0,
      bottom: 0,
      width: _kPullToLoad,
      child: ValueListenableBuilder<double>(
        valueListenable: _pull,
        builder: (context, pull, _) {
          final shown = loading
              ? 1.0
              : load == null
              ? 0.0
              : ((left ? -pull : pull) / _kPullToLoad).clamp(0.0, 1.0);
          return IgnorePointer(
            child: Opacity(
              opacity: shown,
              child: Center(
                child: loading
                    ? Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          shape: BoxShape.circle,
                          boxShadow: const [
                            BoxShadow(color: Color(0x22000000), blurRadius: 6),
                          ],
                        ),
                        child: const CupertinoActivityIndicator(),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            left
                                ? LucideIcons.chevronsLeft
                                : LucideIcons.chevronsRight,
                            size: 18,
                            color: muted,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            left ? 'Earlier' : 'Later',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: muted,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }

  double _textWidth(BuildContext context, String text, TextStyle style) =>
      _textWidths.putIfAbsent(
        '${style.fontSize}|$text',
        () => (TextPainter(
          text: TextSpan(
            text: text,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: TextDirection.ltr,
        )..layout()).width,
      );

  double _stationWidth(BuildContext context, GraphStation station) =>
      _textWidth(
        context,
        stationLabel(station.name),
        _StationMarker.textStyle(AppColors.black),
      ) +
      _StationMarker.chrome(locked: locks.stationKeys.contains(station.key));

  /// Column centres, from the axis: each column only as far from the last
  /// as what sits beside it at the same time needs.
  ///
  /// Worked out at the zoom the graph opened at, and kept while zooming in,
  /// where things only move further apart; zooming out past it, where they
  /// can come side by side, spaces them again.
  ({List<double> xs, double width}) _spaceColumns(
    BuildContext context,
    RideBadges badges,
  ) {
    final zoom = math.min(_pxPerMinute!, _fittedPxPerMinute ?? _pxPerMinute!);
    // Locked stations, whose names grow a lock.
    final key = (zoom, badges, (locks.stationKeys.toList()..sort()).join('|'));
    if (_spacedFor == key) return _columns;
    final scale = zoom == _pxPerMinute
        ? _scale
        : GraphScale(graph, zoom, badges: badges);
    double y(DateTime time) => scale.yOf(time);

    final boxes = <GraphBox>[];
    for (final ride in graph.rides) {
      final top = y(ride.leg.startTime), bottom = y(ride.leg.endTime);
      boxes.add(
        GraphBox(
          ride,
          left: _kBarWidth / 2,
          right: _kBarWidth / 2,
          top: top,
          bottom: bottom,
        ),
      );
      if (badges.keys.contains(ride.key)) {
        const inside = _LockBadge.size - _LockBadge.overhang;
        boxes.add(
          GraphBox(
            ride,
            left: inside - _kBarWidth / 2,
            right: _kBarWidth / 2 + _LockBadge.overhang,
            top: bottom - inside,
            bottom: bottom + _LockBadge.overhang,
          ),
        );
      }
    }
    void label(GraphStation station, GraphRide ride, {required bool above}) {
      final half = _stationWidth(context, station) / 2;
      final at = above
          ? y(ride.leg.startTime) - _StationMarker.labelHeight - 1
          : y(ride.leg.endTime) +
                1 +
                (badges.keys.contains(ride.key) ? _LockBadge.overhang : 0);
      boxes.add(
        GraphBox(
          ride,
          left: half,
          right: half,
          top: at,
          bottom: at + _StationMarker.labelHeight,
        ),
      );
    }

    for (final change in graph.changes) {
      label(change.from.alighting, change.from, above: false);
      if (change.changesStation) {
        label(change.to.boarding, change.to, above: true);
      }
    }
    for (final arrival in graph.arrivals) {
      final at = y(arrival.ride.leg.endTime) + 2;
      boxes.add(
        GraphBox(
          arrival.ride,
          left: _kArrivalWidth / 2,
          right: _kArrivalWidth / 2,
          top: at,
          bottom: at + _kArrivalHeight,
        ),
      );
    }

    final durations = [
      for (final itinerary in graph.itineraries)
        _textWidth(context, formatDuration(itinerary.duration), _durationStyle),
    ];
    final xs = packColumns(
      graph.columnCount,
      boxes,
      minGaps: [
        0,
        for (var i = 1; i < graph.columnCount; i++)
          (durations[i - 1] + durations[i]) / 2 + _kHeaderGap,
      ],
      margin: _kSideMargin,
    );

    // Shifted so whatever reaches furthest left clears the axis.
    double centreOf(GraphRide ride) =>
        (xs[ride.firstColumn] + xs[ride.lastColumn]) / 2;
    var leftmost = 0.0, rightmost = 0.0;
    for (var i = 0; i < xs.length; i++) {
      leftmost = math.min(leftmost, xs[i] - durations[i] / 2);
      rightmost = math.max(rightmost, xs[i] + durations[i] / 2);
    }
    for (final box in boxes) {
      leftmost = math.min(leftmost, centreOf(box.ride) - box.left);
      rightmost = math.max(rightmost, centreOf(box.ride) + box.right);
    }
    final shift = _kAxisWidth + 4 - leftmost;
    _spacedFor = key;
    return _columns = (
      xs: [for (final x in xs) x + shift],
      width: rightmost + shift + _kRightPad,
    );
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
    // As wide as the room either side, for something to tap.
    final xs = g.columns;
    final room = [
      if (column > 0) xs[column] - xs[column - 1],
      if (column < xs.length - 1) xs[column + 1] - xs[column],
    ].fold(double.infinity, math.min);
    final width = room.isFinite ? room : 80.0;
    return Positioned(
      left: xs[column] - width / 2,
      top: 4,
      width: width,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(column),
        child: _fade(
          column == selected,
          Text(
            formatDuration(graph.itineraries[column].duration),
            textAlign: TextAlign.center,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: _durationStyle,
          ),
        ),
      ),
    );
  }

  /// A hairline between [column]'s duration and the one before it.
  Widget _headerDivider(_Geometry g, int column) {
    final xs = g.columns;
    return Positioned(
      left: (xs[column - 1] + xs[column]) / 2,
      top: 5,
      bottom: 5,
      width: 1,
      child: ColoredBox(color: AppColors.hairline),
    );
  }

  _Lock? _lockOf(GraphRide ride, Set<String> implicit) =>
      locks.rideKeys.contains(ride.key)
      ? _Lock.explicit
      : implicit.contains(ride.key)
      ? _Lock.implicit
      : null;

  /// Every locked ride carries a badge on its bottom corner, which the
  /// scale makes room for.
  RideBadges get _badges => RideBadges(
    keys: {...locks.rideKeys, ..._implicitlyLocked},
    rideHeight: _kLockedRideHeight,
    overhang: _LockBadge.overhang,
  );

  /// A circle on the bar's bottom right corner, mostly over the bar. The
  /// scale leaves room for it: the bar is tall enough to keep it clear of
  /// the name, and the station name below moves down past it.
  Widget _lockBadge(_Geometry g, GraphRide ride, _Lock lock, Color accent) {
    const inside = _LockBadge.size - _LockBadge.overhang;
    return Positioned(
      left: g.x(ride) + _kBarWidth / 2 - inside,
      top: g.y(ride.leg.endTime) - inside,
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
      left: g.x(ride) - _kBarWidth / 2,
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
  List<Widget> _stationMarkers(_Geometry g, Color accent, Set<String> badged) {
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
          center: Offset(
            g.x(ride),
            g.y(at) +
                (!above && badged.contains(ride.key) ? _LockBadge.overhang : 0),
          ),
          width: _stationWidth(context, station),
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
      left: g.x(arrival.ride) - _kArrivalWidth / 2,
      top: g.y(arrival.ride.leg.endTime) + 2,
      width: _kArrivalWidth,
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
  const _Geometry(this.graph, this.columns, this.scale);

  final JourneyGraph graph;

  /// The centre of each result's column.
  final List<double> columns;
  final GraphScale scale;

  /// The centre of [ride]'s bar: across every result that takes it.
  double x(GraphRide ride) =>
      (columns[ride.firstColumn] + columns[ride.lastColumn]) / 2;
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
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(_kBarRadius),
      ),
      padding: const EdgeInsets.only(top: _textTop),
      alignment: Alignment.topCenter,
      clipBehavior: Clip.hardEdge,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (text, style) in lines(ride, height, onColor))
            Text(text, maxLines: 1, style: style),
        ],
      ),
    );
  }

  static const double _textTop = 3;

  /// The name, the number under it when there is room, and the departure
  /// when there is more.
  static List<(String, TextStyle)> lines(
    GraphRide ride,
    double height, [
    Color color = AppColors.solidWhite,
  ]) {
    final (line, number) = _splitName(ride.leg);
    TextStyle style(double size, FontWeight weight) => TextStyle(
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: 1.15,
    );
    return [
      (line, style(12, FontWeight.w800)),
      if (number != null && height > 40) (number, style(10, FontWeight.w500)),
      if (height > 58)
        (formatTime(ride.leg.startTime), style(10, FontWeight.w500)),
    ];
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

  static const double labelHeight = 15;

  /// Width a label takes beyond its text: padding, and the lock icon a
  /// locked station shows.
  static double chrome({required bool locked}) => 6 + (locked ? 11 : 0);

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
    VoidCallback? onTap,
  }) {
    return Positioned(
      left: center.dx - width / 2,
      top: above ? center.dy - labelHeight - 1 : center.dy + 1,
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
      height: labelHeight,
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

/// A locked bar is at least this tall, so the badge on its bottom corner
/// stays clear of the name at its top.
const double _kLockedRideHeight = 32;

/// A circle on the bottom right corner of a locked bar, outlined in the
/// bar's colour with the lock in the same line. A lock that follows from a
/// later one is the same badge, fainter.
class _LockBadge extends StatelessWidget {
  const _LockBadge({required this.color, this.implicit = false});

  /// The colour of the bar it sits on.
  final Color color;
  final bool implicit;

  static const double size = 20;

  /// How far it reaches past the corner, right and down: as the first
  /// badges did, a little under half of it.
  static const double overhang = 9;

  /// The border, and the lock drawn in it with the same line.
  static const double _stroke = 1.5;

  @override
  Widget build(BuildContext context) {
    // Faded towards white rather than made see-through, so the bar does
    // not show through where the badge overlaps it.
    final ink = implicit
        ? Color.lerp(color, AppColors.solidWhite, 1 - _kImplicitLockOpacity)!
        : color;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.white,
        shape: BoxShape.circle,
        border: Border.all(color: ink, width: _stroke),
      ),
      alignment: Alignment.center,
      child: CustomPaint(
        size: const Size.square(12),
        painter: _LockGlyph(ink, _stroke),
      ),
    );
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
  });

  final _Geometry g;

  final DateTime now;
  final Color accent;
  final int selected;

  /// The ambient text style, for its font: a painter inherits none.
  final TextStyle textStyle;

  @override
  void paint(Canvas canvas, Size size) {
    _paintHours(canvas, size);
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
      final from = Offset(g.x(change.from), g.y(change.from.leg.endTime));
      final to = Offset(g.x(change.to), g.y(change.to.leg.startTime));
      final bend = (to.dy - from.dy) / 2;
      final path = Path()
        ..moveTo(from.dx, from.dy)
        ..cubicTo(from.dx, from.dy + bend, to.dx, to.dy - bend, to.dx, to.dy);
      canvas.drawPath(change.changesStation ? _dashed(path) : path, paint);
    }
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
      if (y - lastLabel >= _kMinLabelGap / 2) {
        final label = TextPainter(
          text: TextSpan(
            text: formatTime(tick),
            style: textStyle.copyWith(fontSize: 10, color: AppColors.black),
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
      !listEquals(old.g.columns, g.columns) ||
      old.now != now ||
      old.accent != accent ||
      old.selected != selected;
}
