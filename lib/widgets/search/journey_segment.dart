import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_colors.dart';
import '../../theme/journey_metrics.dart';
import '../../utils/app_icons.dart';
import '../../utils/haptics.dart';
import '../journey/spine_node.dart';
import '../journey/spine_row.dart';

/// The first line of a stage's text, stated so [SpineRow] can centre it.
const double kStageLineHeight = 16;

/// A stage that can follow another one instead of being set on its own.
class StageLink {
  const StageLink({
    required this.linked,
    required this.label,
    required this.onPressed,
  });

  /// Whether the stage follows the other one. A linked stage cannot be
  /// opened: there is nothing of its own to set.
  final bool linked;

  /// What linking means, for screen readers: "Same as to the station".
  final String label;

  final VoidCallback onPressed;
}

/// One stage of the journey being planned, as a node on the same spine the
/// itinerary is drawn with.
///
/// The rail runs unbroken through all three stages, with each stage's own mode
/// in a ring and street stages dotted, so the search reads as the shape of the
/// trip being asked for rather than as a settings list with a line beside
/// it.
class JourneySegment extends StatelessWidget {
  const JourneySegment({
    super.key,
    required this.icon,
    required this.headline,
    required this.summary,
    required this.isOpen,
    required this.onToggle,
    required this.child,
    required this.color,
    this.dashed = false,
    this.link,
  });

  /// Reflects the current choice, e.g. a bike once a bike is picked.
  final AppIcon icon;

  /// Names the stage: "To the station", "Public transport".
  final String headline;

  /// The current state in one line, readable without expanding.
  final String summary;

  final bool isOpen;
  final VoidCallback onToggle;

  /// Controls shown once the stage is expanded.
  final Widget child;

  /// The stage's stretch of the line.
  final Color color;

  /// Street stages are dotted: you are not on rails.
  final bool dashed;

  /// Offered beside the chevron, open or closed, when the stage can follow
  /// another one.
  final StageLink? link;

  bool get _linked => link?.linked ?? false;

  @override
  Widget build(BuildContext context) {
    return SpineRow(
      timeColumn: 0,
      padding: EdgeInsets.zero,
      node: SpineNode.app(icon: icon, color: color, semanticLabel: headline),
      railColor: color,
      railDashed: dashed,
      railTopInset: JourneyMetrics.ring,
      firstLineHeight: kStageLineHeight,
      meta: _meta(),
      // The whole row toggles — the ring, the summary, the chevron and the
      // space between them — so nothing in it looks pressable and isn't. A
      // linked stage has nothing to open.
      onTap: _linked
          ? null
          : () {
              Haptics.lightTick();
              onToggle();
            },
      body: Semantics(
        button: !_linked,
        expanded: _linked ? null : isOpen,
        label: '$headline. $summary',
        child: Padding(
          // The gap between stages lives inside the row, so the rails of
          // adjacent stages touch and the line stays unbroken.
          padding: const EdgeInsets.only(bottom: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                headline.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  height: kStageLineHeight / 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: color,
                ),
              ),
              const SizedBox(height: 1),
              // Two lines rather than one cut short: with many sections on,
              // each of them is worth reading.
              Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: AppColors.black),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 180),
                crossFadeState: isOpen
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  // Swallows taps that land in the controls' own area without
                  // hitting one. The controls sit deeper and take their taps
                  // first; this only stops a miss between two of them from
                  // folding the stage away mid-adjustment.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta() {
    final chevron = AnimatedRotation(
      turns: isOpen ? 0.25 : 0,
      duration: const Duration(milliseconds: 180),
      child: Icon(
        LucideIcons.chevronRight,
        size: 14,
        color: AppColors.black.withValues(alpha: 0.45),
      ),
    );
    final link = this.link;
    if (link == null) return chevron;
    return _LinkedMeta(
      link: link,
      // Linked, the chevron goes but keeps its room, so the link does not
      // move out from under the finger that just tapped it.
      chevron: Visibility(
        visible: !link.linked,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: chevron,
      ),
    );
  }
}

/// The link and the chevron, centred together on the stage's first line.
class _LinkedMeta extends StatelessWidget {
  const _LinkedMeta({required this.link, required this.chevron});

  final StageLink link;
  final Widget chevron;

  /// A finger's worth around the glyph, which is only a ring's icon wide.
  static const double _target = 40;

  @override
  Widget build(BuildContext context) {
    final color = link.linked
        ? AppColors.accentOf(context)
        : AppColors.black.withValues(alpha: 0.45);
    // Laid out at full height, then lifted so its middle sits on the first
    // line, which is also the ring's middle. A transform moves the hit area
    // with the paint; clipping it to the line instead would leave a target
    // as short as the text.
    return Transform.translate(
      offset: const Offset(0, -(_target - kStageLineHeight) / 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            toggled: link.linked,
            label: link.label,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.lightTick();
                link.onPressed();
              },
              child: SizedBox.square(
                dimension: _target,
                child: Center(
                  // Upright: the stages above and below are chained.
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Icon(
                      LucideIcons.link2,
                      size: JourneyMetrics.iconSize,
                      color: color,
                    ),
                  ),
                ),
              ),
            ),
          ),
          chevron,
        ],
      ),
    );
  }
}
