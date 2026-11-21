import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/device_calendar.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import 'bottom_overlay_card.dart';
import 'settings_tile.dart';

/// Lists the calendars saved trips can go into: the app's own first, then
/// every other writable one, grouped by the account that syncs it.
class CalendarPickerSheet extends StatelessWidget {
  const CalendarPickerSheet({
    super.key,
    required this.calendars,
    required this.selectedId,
    required this.onPicked,
    required this.onDismiss,
  });

  static const String title = 'Choose a calendar';

  final List<DeviceCalendar> calendars;
  final int? selectedId;
  final ValueChanged<DeviceCalendar> onPicked;
  final VoidCallback onDismiss;

  /// The calendars in the order shown, each account's together, the app's
  /// own calendar and the phone's other local ones first.
  Map<String, List<DeviceCalendar>> get _groups {
    final groups = <String, List<DeviceCalendar>>{'On this phone': []};
    final sorted = [...calendars]
      ..sort((a, b) {
        if (a.isOwn != b.isOwn) return a.isOwn ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    for (final calendar in sorted) {
      final heading = calendar.isLocal
          ? 'On this phone'
          : [calendar.accountName, ?calendar.syncedBy].join(' · ');
      groups.putIfAbsent(heading, () => []).add(calendar);
    }
    return groups..removeWhere((_, calendars) => calendars.isEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return BottomOverlayCard(
      title: title,
      onDismiss: onDismiss,
      maxHeightFactor: 0.75,
      child: Flexible(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final MapEntry(key: heading, value: group)
                  in _groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
                  child: Text(
                    heading,
                    style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (final calendar in group)
                  SettingsTile(
                    icon: calendar.isLocal
                        ? LucideIcons.smartphone
                        : LucideIcons.cloud,
                    iconColor: Color(calendar.color),
                    title: calendar.name,
                    subtitle: calendar.isOwn
                        ? 'Maintained by Transportia+'
                        : null,
                    trailingIcon: null,
                    trailing: calendar.id == selectedId
                        ? Icon(LucideIcons.check, size: 20, color: accent)
                        : null,
                    onPressed: () => onPicked(calendar),
                  ),
              ],
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'Your upcoming saved trips move to the calendar you pick. '
                  'Past trips and events you edited stay where they are.',
                  style: AppText.footnote,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
