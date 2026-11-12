import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import 'icon_badge.dart';

/// The title block at the top of a tab screen: a small accent badge beside
/// the screen's name and one line saying what it shows. Settings and
/// timetables use the same layout.
class AppScreenTitle extends StatelessWidget {
  const AppScreenTitle({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Row(
      children: [
        IconBadge(
          icon: icon,
          size: 48,
          iconSize: 24,
          backgroundColor: AppColors.accentWash(accent),
          iconColor: accent,
          borderRadius: BorderRadius.circular(14),
        ),
        const SizedBox(width: 16),
        // Expanded, or a long subtitle overflows the row on a narrow screen.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.black,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.black.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
