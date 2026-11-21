import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import 'settings_tile.dart';

/// A setting that holds one of several choices, on the page's faint card:
/// the setting's name, the choice it holds under it, and a tap to pick
/// another.
///
/// The down chevron says "choose one", where a settings tile's right chevron
/// says "open a screen". The sibling of [ToggleCard] for settings that are
/// more than on or off.
class SelectCard extends StatelessWidget {
  const SelectCard({
    super.key,
    required this.label,
    required this.icon,
    required this.value,
    this.detail,
    this.iconColor,
    required this.onPressed,
  });

  /// What the setting is.
  final String label;

  /// The chosen option's icon.
  final IconData icon;

  /// The chosen option's name.
  final String value;

  /// A line about the chosen option, under its name.
  final String? detail;

  /// The chosen option's own colour, where it has one; the accent otherwise.
  final Color? iconColor;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final detail = this.detail;
    return Semantics(
      button: true,
      label: label,
      value: value,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.black.withValues(alpha: 0.04)),
        ),
        child: SettingsTile(
          icon: icon,
          iconColor: iconColor,
          title: label,
          subtitle: detail == null ? value : '$value\n$detail',
          trailingIcon: LucideIcons.chevronDown,
          onPressed: onPressed,
        ),
      ),
    );
  }
}
