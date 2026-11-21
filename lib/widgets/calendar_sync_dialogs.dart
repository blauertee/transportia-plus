import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/device_calendar.dart';
import '../theme/app_text.dart';
import 'overlay_dialog.dart';

/// "no trips", "1 trip", "3 trips".
String _trips(int count) => switch (count) {
  0 => 'no trips',
  1 => '1 trip',
  _ => '$count trips',
};

/// Asked when the setting goes off: whether to remove the events the app
/// wrote, keeping them unless the rider says otherwise.
///
/// The app's own calendar holds nothing but trips, so it goes as a whole;
/// in any other calendar each event is checked before it is removed.
class RemoveTripsDialog extends StatelessWidget {
  RemoveTripsDialog({
    super.key,
    required int count,
    required DeviceCalendar calendar,
    required this.onAnswer,
  }) : title = calendar.isOwn ? 'Remove the calendar?' : 'Remove added trips?',
       subtitle = calendar.name,
       body = calendar.isOwn
           ? 'It holds ${_trips(count)}. Remove it from your phone, or keep '
                 'it with the trips in it.'
           : '${_trips(count)} ${count == 1 ? 'was' : 'were'} added to '
                 '${calendar.name}. Events you changed yourself stay either '
                 'way.';

  final String title;
  final String subtitle;
  final String body;

  /// True to remove them.
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    return OverlayDialogCard(
      children: [
        OverlayDialogHeader(
          icon: LucideIcons.calendarX,
          title: title,
          subtitle: subtitle,
        ),
        const SizedBox(height: 16),
        Text(body, style: AppText.bodyMuted),
        const SizedBox(height: 24),
        OverlayDialogActions(
          cancelLabel: 'Keep',
          confirmLabel: 'Remove',
          onCancel: () => onAnswer(false),
          onConfirm: () => onAnswer(true),
        ),
      ],
    );
  }
}
