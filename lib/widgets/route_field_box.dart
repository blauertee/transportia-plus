import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../utils/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/journey_metrics.dart';
import '../utils/journey_colors.dart';
import 'journey/spine_rail.dart';
import 'search/editable_value.dart';
import 'skeletons/skeleton_shimmer.dart';

/// The origin and destination of a search, stacked in travel order.
///
/// They read top to bottom rather than side by side because the search
/// options sit *between* them: the journey's stages only mean anything in
/// sequence, and a horizontal pair has no between to put them in.
class RouteFieldBox extends StatefulWidget {
  const RouteFieldBox({
    super.key,
    required this.fromController,
    required this.toController,
    required this.accentColor,
    required this.onSwapRequested,
    required this.layerLink,
    this.fromLoading = false,
    this.toLoading = false,
    this.middle,
    this.timeLine,
    this.footer,
    required this.onFromPressed,
    required this.onToPressed,
  });

  final TextEditingController fromController;
  final TextEditingController toController;
  final Color accentColor;
  final VoidCallback onSwapRequested;
  final LayerLink layerLink;
  final bool fromLoading;
  final bool toLoading;

  /// Sits between the two fields, sharing their gutter so the rail continues
  /// the line the two markers start and end.
  final Widget? middle;

  /// When the trip leaves or arrives, under where it starts.
  final Widget? timeLine;

  /// Closes the card — the Search button, so the action sits with the
  /// fields it acts on rather than in a bar of its own below them.
  final Widget? footer;

  /// Opens the place picker. The fields are not edited in place: picking a
  /// place is a search with favourites and recents of its own.
  final VoidCallback onFromPressed;
  final VoidCallback onToPressed;

  @override
  State<RouteFieldBox> createState() => _RouteFieldBoxState();
}

class _RouteFieldBoxState extends State<RouteFieldBox> {
  bool _swapPressed = false;

  @override
  void initState() {
    super.initState();
    widget.fromController.addListener(_onChanged);
    widget.toController.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(covariant RouteFieldBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fromController != widget.fromController) {
      oldWidget.fromController.removeListener(_onChanged);
      widget.fromController.addListener(_onChanged);
    }
    if (oldWidget.toController != widget.toController) {
      oldWidget.toController.removeListener(_onChanged);
      widget.toController.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    widget.fromController.removeListener(_onChanged);
    widget.toController.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: widget.layerLink,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.hairline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EndpointRow(
              railFrom: _EndpointRailFrom.marker,
              markerCenter: _EndpointRow.originMarkerCenter,
              marker: _EndpointDot(color: widget.accentColor, filled: false),
              trailing: _buildSwapButton(context),
              child: Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildOrigin(),
                    if (widget.timeLine case final timeLine?) ...[
                      const SizedBox(height: 2),
                      timeLine,
                    ],
                  ],
                ),
              ),
            ),
            if (widget.middle case final middle?)
              middle
            else
              Padding(
                padding: const EdgeInsets.only(
                  left: JourneyMetrics.gutter,
                  top: 2,
                  bottom: 2,
                ),
                child: Container(
                  height: 1,
                  color: AppColors.black.withValues(alpha: 0.08),
                ),
              ),
            _EndpointRow(
              railFrom: _EndpointRailFrom.top,
              markerCenter: _EndpointRow.prominentMarkerCenter,
              marker: _EndpointDot(
                color: widget.accentColor,
                filled: true,
                size: 11,
              ),
              child: SizedBox(
                height: _EndpointRow.prominentMarkerCenter * 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _shimmerWhile(
                    widget.toLoading,
                    EditableValue.destination(
                      label: widget.toController.text,
                      placeholder: 'Search destination',
                      semanticsLabel: 'Change destination',
                      onTap: widget.onToPressed,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.footer case final footer?) ...[
              const SizedBox(height: 10),
              footer,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOrigin() {
    final text = widget.fromController.text;
    final origin = EditableValue.origin(
      label: text.isEmpty ? 'From' : text,
      semanticsLabel: 'Change origin',
      onTap: widget.onFromPressed,
    );
    return _shimmerWhile(widget.fromLoading, origin);
  }

  /// Holds the value's place while a tapped map point is being named.
  Widget _shimmerWhile(bool loading, Widget child) {
    if (!loading) return child;
    return SkeletonShimmer(
      baseColor: const Color(0xFFE2E7EC),
      highlightColor: const Color(0xFFF7F9FC),
      period: const Duration(milliseconds: 1100),
      child: child,
    );
  }

  Widget _buildSwapButton(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onSwapRequested();
        Haptics.mediumTick();
      },
      onTapDown: (_) => setState(() => _swapPressed = true),
      onTapUp: (_) => setState(() => _swapPressed = false),
      onTapCancel: () => setState(() => _swapPressed = false),
      child: Semantics(
        button: true,
        label: 'Swap origin and destination',
        child: AnimatedScale(
          duration: const Duration(milliseconds: 100),
          scale: _swapPressed ? 0.92 : 1.0,
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: _swapPressed
                  ? AppColors.white.withValues(alpha: 0.92)
                  : AppColors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.hairline),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              LucideIcons.arrowUpDown,
              size: 16,
              color: widget.accentColor,
            ),
          ),
        ),
      ),
    );
  }
}

/// Which part of an endpoint row its stretch of line covers.
enum _EndpointRailFrom {
  /// The origin: the line leaves its marker and runs on to the first stage.
  marker,

  /// The destination: the line arrives from the last stage and stops there.
  top,
}

/// One endpoint: its marker in the shared gutter, its field, and whatever
/// sits at the trailing edge.
///
/// The gutter is the spine's, so the two markers, the three stage rings and
/// the line all sit on one centre line — the card reads as the top and bottom
/// of the same drawing rather than as a box with a diagram inside it.
class _EndpointRow extends StatelessWidget {
  const _EndpointRow({
    required this.marker,
    required this.child,
    required this.railFrom,
    this.trailing,
    this.markerCenter = _defaultMarkerCenter,
  });

  final Widget marker;
  final Widget child;
  final Widget? trailing;
  final _EndpointRailFrom railFrom;

  /// Half the height of a field row, which is where the marker sits.
  final double markerCenter;

  static const double _defaultMarkerCenter = 22;

  /// The destination's row: a little taller, as the one field every search
  /// has to fill.
  static const double prominentMarkerCenter = 26;

  /// The origin's row is two lines, place over time; the marker belongs to
  /// the place.
  static const double originMarkerCenter = 17;

  @override
  Widget build(BuildContext context) {
    final fromMarker = railFrom == _EndpointRailFrom.marker;

    return Stack(
      children: [
        Positioned(
          left: 0,
          width: JourneyMetrics.gutter,
          top: 0,
          bottom: 0,
          child: SpineRail(
            color: kStreetLegColor,
            dashed: true,
            topInset: fromMarker ? markerCenter : 0,
            bottomInset: fromMarker ? 0 : markerCenter,
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: JourneyMetrics.gutter,
              height: markerCenter * 2,
              child: Center(child: marker),
            ),
            // The same gap the spine's rows keep between the rail and their
            // text, so a field, a stage summary and the traveller controls
            // all begin on one edge instead of three.
            const SizedBox(width: JourneyMetrics.gap),
            Expanded(child: child),
            if (trailing case final trailing?) ...[
              const SizedBox(width: 8),
              SizedBox(
                height: markerCenter * 2,
                child: Center(child: trailing),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _EndpointDot extends StatelessWidget {
  const _EndpointDot({
    required this.color,
    required this.filled,
    this.size = 9,
  });

  final Color color;
  final double size;

  /// Hollow for where you start, solid for where you end — the convention
  /// every map app already taught people.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? color : AppColors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
    );
  }
}
