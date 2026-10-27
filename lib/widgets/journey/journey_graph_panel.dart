import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/itinerary.dart';
import '../../providers/journey_locks_controller.dart';
import '../../theme/app_colors.dart';
import '../../utils/duration_formatter.dart';
import '../../utils/haptics.dart';
import '../../utils/journey_graph.dart';
import '../buttons/primary_button.dart';
import '../empty_state.dart';
import 'journey_graph_view.dart';

/// How often the "now" line moves.
const Duration _kClockTick = Duration(minutes: 1);

/// The results of a search as a [JourneyGraphView], with the locks set on
/// it and a button to open the selected result.
///
/// What is locked, and the searches that starts, live in [controller],
/// shared with the results list. Without locks it shows [results], the
/// screen's own.
class JourneyGraphPanel extends StatefulWidget {
  const JourneyGraphPanel({
    super.key,
    required this.controller,
    required this.results,
    required this.onOpen,
    this.now,
    this.onLoadEarlier,
    this.onLoadLater,
    this.loadingEarlier = false,
    this.loadingLater = false,
    this.showCopyData = false,
  });

  final JourneyLocksController controller;

  /// What the search found, before anything is locked.
  final List<Itinerary> results;

  final ValueChanged<Itinerary> onOpen;

  /// The clock, for drafts and tests; the real one when null.
  final DateTime Function()? now;

  /// Loads the results before or after [results], when there are any.
  /// While locked, the locks' own search pages instead.
  final VoidCallback? onLoadEarlier;
  final VoidCallback? onLoadLater;
  final bool loadingEarlier;
  final bool loadingLater;

  /// See [JourneyGraphView.showCopyData].
  final bool showCopyData;

  @override
  State<JourneyGraphPanel> createState() => _JourneyGraphPanelState();
}

class _JourneyGraphPanelState extends State<JourneyGraphPanel> {
  JourneyLocksController get _controller => widget.controller;

  /// What [_graph] was built from, to tell when to build it again.
  List<Itinerary>? _shown;
  late JourneyGraph _graph;
  int _selected = 0;
  late DateTime _now;
  Timer? _clock;

  DateTime _readClock() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _now = _readClock();
    _clock = Timer.periodic(_kClockTick, (_) {
      if (mounted) setState(() => _now = _readClock());
    });
    _controller.addListener(_changed);
    _rebuildGraph();
  }

  @override
  void didUpdateWidget(JourneyGraphPanel old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
    _rebuildGraph();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() => setState(_rebuildGraph);

  /// Rebuilt only when what is shown changes, so the view keeps its zoom
  /// and scroll across a change of selection.
  ///
  /// Not filtered by the locks: a via stop may be passed without stopping,
  /// and the planner has already kept to it.
  void _rebuildGraph() {
    final shown = _controller.results ?? widget.results;
    // The list grows a page at a time in place.
    if (identical(shown, _shown) && shown.length == _graph.itineraries.length) {
      return;
    }
    // A page more keeps the same result selected.
    final chosen = _shown == null ? null : _graph.itineraries[_selected];
    _shown = shown;
    _graph = JourneyGraph.build(shown);
    final kept = chosen == null ? -1 : _graph.itineraries.indexOf(chosen);
    _selected = kept < 0 ? 0 : kept;
  }

  void _tapRide(GraphRide ride) {
    Haptics.lightTick();
    if (_controller.locks.rideKeys.contains(ride.key)) {
      return _controller.unlockRide();
    }
    _controller.lockRide(_graph.itineraries[_selected], ride.leg);
  }

  void _tapStation(GraphStation station) {
    Haptics.lightTick();
    _controller.toggleStation(station);
  }

  @override
  Widget build(BuildContext context) {
    final graph = _graph;
    if (graph.itineraries.isEmpty) {
      return Center(child: EmptyState(title: 'No routes found.'));
    }
    final chosen = graph.itineraries[_selected];
    final controller = _controller;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.isLocked ||
            controller.searching ||
            controller.problem != null)
          _LockRow(
            chips: [
              if (controller.lock case final lock?)
                _LockChip(
                  label: 'Locked until ${shortStationName(lock.upTo.to.name)}',
                  onRemove: () {
                    Haptics.lightTick();
                    controller.unlockRide();
                  },
                ),
              for (final station in controller.stations)
                _LockChip(
                  label: 'Locked via ${shortStationName(station.name)}',
                  onRemove: () => _tapStation(station),
                ),
            ],
            searching: controller.searching,
            problem: controller.problem,
          ),
        Expanded(
          child: AnimatedOpacity(
            opacity: controller.searching ? 0.5 : 1,
            duration: const Duration(milliseconds: 150),
            child: JourneyGraphView(
              graph: graph,
              selected: _selected,
              onSelect: (i) => setState(() => _selected = i),
              locks: controller.locks,
              onStationTap: _tapStation,
              onRideTap: _tapRide,
              now: _now,
              onLoadEarlier: controller.isLocked
                  ? (controller.hasEarlier ? controller.loadEarlier : null)
                  : widget.onLoadEarlier,
              onLoadLater: controller.isLocked
                  ? (controller.hasLater ? controller.loadLater : null)
                  : widget.onLoadLater,
              loadingEarlier: controller.isLocked
                  ? controller.loadingEarlier
                  : widget.loadingEarlier,
              loadingLater: controller.isLocked
                  ? controller.loadingLater
                  : widget.loadingLater,
              showCopyData: widget.showCopyData,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: PrimaryButton(
            onTap: () => widget.onOpen(chosen),
            child: Text(
              'Open journey · ${formatDuration(chosen.duration)} · '
              '${chosen.transfers} '
              '${chosen.transfers == 1 ? 'change' : 'changes'}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.solidWhite,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LockRow extends StatelessWidget {
  const _LockRow({
    required this.chips,
    required this.searching,
    required this.problem,
  });

  final List<Widget> chips;
  final bool searching;
  final String? problem;

  @override
  Widget build(BuildContext context) {
    final problem = this.problem;
    final muted = AppColors.black.withValues(alpha: 0.6);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...chips,
          if (searching)
            Text('Searching…', style: TextStyle(fontSize: 12, color: muted))
          else if (problem != null)
            Text(
              problem,
              style: TextStyle(fontSize: 12, color: AppColors.disrupted),
            ),
        ],
      ),
    );
  }
}

class _LockChip extends StatelessWidget {
  const _LockChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onRemove,
      child: Semantics(
        button: true,
        label: '$label, tap to unlock',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.accentWash(accent),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: accent)),
              const SizedBox(width: 6),
              Icon(LucideIcons.x, size: 12, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}
