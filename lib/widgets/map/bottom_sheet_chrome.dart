import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_colors.dart';
import '../pressable_highlight.dart';

/// Corner radius of the sheet where it meets the map.
const double _kSheetCornerRadius = 16;

/// The grab handle's own size.
const double _kHandleWidth = 48;
const double _kHandleHeight = 6;

/// Space above the handle, between the sheet's top edge and the bar.
const double _kHandleTopGap = 18;

/// The card the map's bottom sheets are all drawn on: rounded at the top,
/// lifted off the map by a shadow, and inset for the home indicator.
class BottomSheetSurface extends StatelessWidget {
  const BottomSheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(_kSheetCornerRadius),
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 14,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(top: false, child: child),
    );
  }
}

/// What a sheet does with its handle: toggle on a tap, follow a drag.
class SheetDrag {
  const SheetDrag({
    required this.onTap,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final VoidCallback onTap;
  final VoidCallback onStart;
  final ValueChanged<double> onUpdate;
  final ValueChanged<double> onEnd;
}

/// The bar at the top of a bottom sheet, which both drags the sheet and
/// toggles it on a tap.
class BottomSheetHandle extends StatelessWidget {
  const BottomSheetHandle({super.key, required this.drag, this.bottomGap = 12});

  final SheetDrag drag;

  /// Space below the bar, before the sheet's own content.
  final double bottomGap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: drag.onTap,
      onVerticalDragStart: (_) => drag.onStart(),
      onVerticalDragUpdate: (d) => drag.onUpdate(d.delta.dy),
      onVerticalDragEnd: (d) => drag.onEnd(d.velocity.pixelsPerSecond.dy),
      // A drag that loses the arena after starting reports no end; without
      // one the card would be left between its stops.
      onVerticalDragCancel: () => drag.onEnd(0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: _kHandleTopGap),
          Container(
            width: _kHandleWidth,
            height: _kHandleHeight,
            decoration: BoxDecoration(
              color: AppColors.black.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(_kHandleHeight / 2),
            ),
          ),
          SizedBox(height: bottomGap),
        ],
      ),
    );
  }
}

/// Leaves a sheet that took the map over — trip focus, quick settings — for
/// the one the map opens with.
class BottomSheetBackButton extends StatelessWidget {
  const BottomSheetBackButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: PressableHighlight(
          onPressed: onPressed,
          borderRadius: BorderRadius.circular(14),
          highlightColor: accent,
          enableHaptics: false,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.chevronLeft, size: 18, color: accent),
              const SizedBox(width: 6),
              Text(
                'Back',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
