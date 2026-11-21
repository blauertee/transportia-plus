import 'package:transportia/widgets/pressable_highlight.dart';
import 'package:flutter/widgets.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../theme/app_colors.dart';

/// How long the bar's title takes to fade in or out.
const Duration _kTitleFade = Duration(milliseconds: 150);

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onBackButtonPressed;

  /// Optional action pinned to the right of the bar, opposite the back
  /// button.
  final Widget? trailing;

  /// False for a screen presented as a tab, which has nothing to go back to.
  final bool showBack;

  /// False while the page's own large title is in view, so the name is not
  /// shown twice; it fades in once that title scrolls away.
  final bool titleVisible;

  const CustomAppBar({
    super.key,
    required this.title,
    this.onBackButtonPressed,
    this.trailing,
    this.showBack = true,
    this.titleVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12.0),
      child: SizedBox(
        height: preferredSize.height,
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (showBack)
              Align(
                alignment: Alignment.centerLeft,
                child: PressableHighlight(
                  onPressed:
                      onBackButtonPressed ?? () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(22),
                  enableHaptics: false,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        LucideIcons.chevronLeft,
                        size: 20,
                        color: AppColors.accentOf(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Back',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: AppColors.accentOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Center(
              child: AnimatedOpacity(
                opacity: titleVisible ? 1 : 0,
                duration: _kTitleFade,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.black,
                  ),
                ),
              ),
            ),
            if (trailing != null)
              Align(alignment: Alignment.centerRight, child: trailing),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56.0);
}
