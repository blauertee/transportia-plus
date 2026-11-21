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

/// Asked once when the setting goes on while trips are already saved.
class AddSavedTripsDialog extends StatelessWidget {
  const AddSavedTripsDialog({
    super.key,
    required this.count,
    required this.calendar,
    required this.onAnswer,
  });

  /// Upcoming saved trips; past ones are never offered.
  final int count;
  final DeviceCalendar calendar;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    return OverlayDialogCard(
      children: [
        const OverlayDialogHeader(
          icon: LucideIcons.calendarPlus,
          title: 'Add saved trips?',
        ),
        const SizedBox(height: 16),
        Text(
          'You have ${_trips(count)} coming up. Add them to '
          '${calendar.name} as well, or only trips you save from now on?',
          style: AppText.bodyMuted,
        ),
        const SizedBox(height: 24),
        OverlayDialogActions(
          cancelLabel: 'Only new',
          confirmLabel: 'Add ${_trips(count)}',
          onCancel: () => onAnswer(false),
          onConfirm: () => onAnswer(true),
        ),
      ],
    );
  }
}

/// Asks whether to remove the events the app wrote, keeping them unless
/// the rider says otherwise.
///
/// The app's own calendar holds nothing but trips, so it goes as a whole;
/// in any other calendar each event is checked before it is removed.
class RemoveTripsDialog extends StatelessWidget {
  /// Asked when the setting goes off.
  RemoveTripsDialog.stopping({
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

  /// Asked when new saves move from the app's own calendar to another one.
  RemoveTripsDialog.leavingOwn({
    super.key,
    required int count,
    required DeviceCalendar from,
    required DeviceCalendar to,
    required this.onAnswer,
  }) : title = 'Remove the calendar?',
       subtitle = from.name,
       body =
           'Trips you save now go to ${to.name}. ${from.name} still holds '
           '${_trips(count)}. Remove it from your phone, or keep it.';

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
