import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';

/// The app's yellow warning card: an icon, a bold title, the explanation
/// under it, and, where there is something to do about it, an action.
class WarningNotice extends StatelessWidget {
  const WarningNotice({
    super.key,
    this.title,
    this.body,
    this.icon = LucideIcons.triangleAlert,
    this.action,
  }) : padding = const EdgeInsets.all(12),
       borderRadius = 8,
       titleFontSize = 14,
       bodyFontSize = 13;

  /// The tighter proportions used where the warning sits inside a leg of a
  /// trip rather than in a card of its own.
  const WarningNotice.compact({
    super.key,
    this.title,
    this.body,
    this.icon = LucideIcons.triangleAlert,
    this.action,
  }) : padding = const EdgeInsets.all(8),
       borderRadius = 4,
       titleFontSize = 13,
       bodyFontSize = 12;

  final String? title;
  final String? body;
  final IconData icon;

  /// Under the text, lined up with it: a link to where it can be fixed.
  final Widget? action;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double titleFontSize;
  final double bodyFontSize;

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final body = this.body;
    final action = this.action;
    final hasTitle = title != null && title.isNotEmpty;
    final hasBody = body != null && body.isNotEmpty;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.alertBackground,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.alertBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppColors.alertIcon),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasTitle)
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.bold,
                      color: AppColors.black,
                    ),
                  ),
                if (hasBody) ...[
                  if (hasTitle) const SizedBox(height: 2),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: bodyFontSize,
                      color: AppColors.black.withValues(alpha: 0.8),
                    ),
                  ),
                ],
                if (action != null) ...[const SizedBox(height: 8), action],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
