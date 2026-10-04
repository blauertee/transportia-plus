import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/routing_options.dart';
import '../../models/transitous/enums.dart';
import '../../theme/app_colors.dart';
import '../../utils/haptics.dart';
import '../options/icon_controls.dart';

/// Who is travelling, as opposed to how the journey is put together.
///
/// Step-free keeps its name on screen: it changes from day to day and it is
/// an accessibility need, so it should not take a press to find. Pace is one
/// icon, since it is set rarely and reveals two sliders when it is.
class TravellerStrip extends StatelessWidget {
  const TravellerStrip({
    super.key,
    required this.options,
    required this.tooltips,
    required this.paceOpen,
    required this.onChanged,
    required this.onPacePressed,
  });

  final RoutingOptions options;
  final OptionTooltipController tooltips;
  final bool paceOpen;
  final ValueChanged<RoutingOptions> onChanged;
  final VoidCallback onPacePressed;

  /// A speed only matters when something in the journey travels at it.
  bool get _showsCyclingPace => [
    ...options.firstMileModes,
    ...options.lastMileModesInUse,
  ].any((mode) => mode == TransitMode.bike || mode == TransitMode.rental);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _StepFreeChip(
              enabled: options.wheelchairAccessibleOnly,
              onPressed: () => onChanged(
                options.copyWith(
                  wheelchairAccessibleOnly: !options.wheelchairAccessibleOnly,
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 36,
              child: IconPick.compact(
                icon: LucideIcons.gauge,
                label: 'Pace',
                selected: paceOpen,
                size: 15,
                tooltips: tooltips,
                onPressed: onPacePressed,
              ),
            ),
          ],
        ),
        if (paceOpen) ...[
          const SizedBox(height: 10),
          _PaceRow(
            label: 'Walking',
            valueKmh: options.walkingSpeedKmh,
            min: 2,
            max: 7,
            onChanged: (value) =>
                onChanged(options.copyWith(walkingSpeedKmh: value)),
          ),
          if (_showsCyclingPace) ...[
            const SizedBox(height: 6),
            _PaceRow(
              label: 'Cycling',
              valueKmh: options.cyclingSpeedKmh,
              min: 5,
              max: 35,
              onChanged: (value) =>
                  onChanged(options.copyWith(cyclingSpeedKmh: value)),
            ),
          ],
        ],
      ],
    );
  }
}

class _StepFreeChip extends StatelessWidget {
  const _StepFreeChip({required this.enabled, required this.onPressed});

  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Semantics(
      button: true,
      toggled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Haptics.lightTick();
          onPressed();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          // Matches the compact pace button beside it.
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 11),
          decoration: BoxDecoration(
            color: enabled
                ? accent.withValues(alpha: 0.14)
                : const Color(0x00000000),
            // The pace button beside it, and the spine's other controls, are
            // all 10: a pill here made the two neighbours look unrelated.
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: enabled ? accent : AppColors.black.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                LucideIcons.accessibility,
                size: 13,
                color: enabled ? accent : AppColors.black,
              ),
              const SizedBox(width: 6),
              Text(
                'Step-free',
                style: TextStyle(
                  fontSize: 12.5,
                  color: enabled ? accent : AppColors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaceRow extends StatelessWidget {
  const _PaceRow({
    required this.label,
    required this.valueKmh,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double valueKmh;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 58,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: AppColors.black.withValues(alpha: 0.5),
            ),
          ),
        ),
        Expanded(
          child: OptionSlider(
            value: valueKmh,
            min: min,
            max: max,
            divisions: ((max - min) * 10).round(),
            semanticLabel: '$label pace',
            onChanged: (value) =>
                onChanged(double.parse(value.toStringAsFixed(1))),
          ),
        ),
        SizedBox(
          width: 62,
          child: Text(
            '${valueKmh.toStringAsFixed(1)} km/h',
            textAlign: TextAlign.right,
            style: TextStyle(fontSize: 12, color: AppColors.black),
          ),
        ),
      ],
    );
  }
}
