import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../models/device_calendar.dart';
import '../providers/theme_provider.dart';
import '../services/calendar_sync_service.dart';
import '../services/saved_trips_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../widgets/app_screen.dart';
import '../widgets/calendar_picker_sheet.dart';
import '../widgets/calendar_sync_dialogs.dart';
import '../widgets/pressable_highlight.dart';
import '../widgets/section_title.dart';
import '../widgets/select_card.dart';
import '../widgets/toggle_card.dart';
import '../widgets/validation_toast.dart';
import '../widgets/warning_notice.dart';

/// The side padding [PressableHighlight] puts round its child.
const double _kHighlightInset = 10;

/// Whether the app may read and write the device's calendars.
enum CalendarAccess { granted, denied, permanentlyDenied }

/// How long the picker sheet takes to fade in and out.
const Duration _kSheetFadeDuration = Duration(milliseconds: 180);

/// Asks Android about the calendar permission. Replaced in tests.
class CalendarPermission {
  const CalendarPermission();

  Future<CalendarAccess> status() async =>
      _access(await Permission.calendarFullAccess.status);

  Future<CalendarAccess> request() async =>
      _access(await Permission.calendarFullAccess.request());

  Future<void> openSettings() => openAppSettings();

  static CalendarAccess _access(PermissionStatus status) {
    if (status.isGranted || status.isLimited) return CalendarAccess.granted;
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CalendarAccess.permanentlyDenied;
    }
    return CalendarAccess.denied;
  }
}

/// Where the rider turns on adding saved trips to a calendar, and picks it.
class CalendarSettingsScreen extends StatefulWidget {
  const CalendarSettingsScreen({
    super.key,
    this.permission = const CalendarPermission(),
  });

  /// The screen's title, and the label of the settings tile that opens it.
  static const String title = 'Calendar';

  final CalendarPermission permission;

  @override
  State<CalendarSettingsScreen> createState() => _CalendarSettingsScreenState();
}

class _CalendarSettingsScreenState extends State<CalendarSettingsScreen> {
  bool _isLoading = true;

  /// A change to the calendar is under way; taps wait for it.
  bool _isBusy = false;
  bool _wanted = false;
  CalendarAccess _access = CalendarAccess.denied;
  DeviceCalendar? _calendar;

  /// Reloads on coming back from Android's settings, where the permission
  /// may have changed.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_load()));
    unawaited(_load());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final wanted = await CalendarSyncService.isWanted();
    final access = await widget.permission.status();
    final calendar = wanted && access == CalendarAccess.granted
        ? await CalendarSyncService.currentCalendar()
        : null;
    if (!mounted) return;
    setState(() {
      _wanted = wanted;
      _access = access;
      _calendar = calendar;
      _isLoading = false;
    });
  }

  /// Runs [change] unless another is under way.
  Future<void> _whileBusy(Future<void> Function() change) async {
    if (_isBusy) return;
    setState(() => _isBusy = true);
    try {
      await change();
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  void _onWantedChanged(bool on) =>
      unawaited(_whileBusy(on ? _switchOn : _switchOff));

  Future<void> _switchOn() async {
    final access = await widget.permission.request();
    if (!mounted) return;
    setState(() => _access = access);
    if (access != CalendarAccess.granted) {
      if (access == CalendarAccess.denied) {
        showValidationToast(context, 'Calendar access was not allowed');
      }
      return;
    }

    final DeviceCalendar calendar;
    try {
      calendar = await CalendarSyncService.enable();
    } catch (_) {
      await CalendarSyncService.disable(remove: false);
      if (mounted) showValidationToast(context, 'Could not set up a calendar');
      return;
    }
    if (!mounted) return;
    setState(() {
      _wanted = true;
      _calendar = calendar;
    });
    await _offerSavedTrips(calendar);
  }

  /// Offers once to add the trips already saved, if any are still to come.
  Future<void> _offerSavedTrips(DeviceCalendar calendar) async {
    final trips = await SavedTripsService.getSavedTrips();
    final upcoming = await CalendarSyncService.upcomingWithoutEvent(trips);
    if (upcoming.isEmpty || !mounted) return;
    final add = await _ask(
      (answer) => AddSavedTripsDialog(
        count: upcoming.length,
        calendar: calendar,
        onAnswer: answer,
      ),
    );
    if (add == true) await CalendarSyncService.addAll(upcoming);
  }

  Future<void> _switchOff() async {
    final calendar = _calendar;
    var remove = false;
    if (calendar != null) {
      final count = await CalendarSyncService.countIn(calendar.id);
      if (calendar.isOwn || count > 0) {
        final answer = await _ask(
          (answer) => RemoveTripsDialog.stopping(
            count: count,
            calendar: calendar,
            onAnswer: answer,
          ),
        );
        // Dismissed: the rider changed their mind, so it stays on.
        if (answer == null) return;
        remove = answer;
      }
    }
    await CalendarSyncService.disable(remove: remove);
    if (!mounted) return;
    setState(() {
      _wanted = false;
      _calendar = null;
    });
  }

  void _onChooseCalendar() => unawaited(_whileBusy(_chooseCalendar));

  Future<void> _chooseCalendar() async {
    final List<DeviceCalendar> calendars;
    try {
      calendars = await CalendarSyncService.calendars();
    } catch (_) {
      if (mounted) showValidationToast(context, 'Could not read calendars');
      return;
    }
    if (!mounted) return;

    DeviceCalendar? picked;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: CalendarPickerSheet.title,
      barrierColor: const Color(0x00000000),
      transitionDuration: _kSheetFadeDuration,
      pageBuilder: (sheetContext, _, _) => CalendarPickerSheet(
        calendars: calendars,
        selectedId: _calendar?.id,
        onPicked: (calendar) {
          picked = calendar;
          Navigator.of(sheetContext).pop();
        },
        onDismiss: () => Navigator.of(sheetContext).pop(),
      ),
      transitionBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    );
    final choice = picked;
    if (choice != null) await _switchTo(choice);
  }

  Future<void> _switchTo(DeviceCalendar choice) async {
    final previous = _calendar;
    if (choice.id == previous?.id) return;

    final DeviceCalendar now;
    try {
      now = await CalendarSyncService.choose(choice);
    } catch (_) {
      if (mounted) showValidationToast(context, 'Could not use that calendar');
      return;
    }
    if (!mounted) return;
    setState(() => _calendar = now);

    if (previous == null || !previous.isOwn || now.isOwn) return;
    final count = await CalendarSyncService.countIn(previous.id);
    final remove = await _ask(
      (answer) => RemoveTripsDialog.leavingOwn(
        count: count,
        from: previous,
        to: now,
        onAnswer: answer,
      ),
    );
    if (remove == true) await CalendarSyncService.removeOwnCalendar();
  }

  /// Shows the dialog [build] makes, and returns its answer; null when it
  /// was dismissed without one.
  Future<bool?> _ask(Widget Function(ValueChanged<bool> answer) build) {
    return showCupertinoDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) =>
          build((answer) => Navigator.of(dialogContext).pop(answer)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AppScreen.page(
        icon: LucideIcons.calendarSync,
        title: CalendarSettingsScreen.title,
        subtitle: 'Checking calendar access…',
        body: SizedBox.shrink(),
      );
    }
    return CalendarSettingsView(
      wanted: _wanted,
      access: _access,
      calendar: _calendar,
      onWantedChanged: _onWantedChanged,
      onChooseCalendar: _onChooseCalendar,
      onOpenAppSettings: () => unawaited(widget.permission.openSettings()),
    );
  }
}

/// The calendar settings as they stand, with what each control does passed
/// in, so every state can be shown without a calendar behind it.
class CalendarSettingsView extends StatelessWidget {
  const CalendarSettingsView({
    super.key,
    required this.wanted,
    required this.access,
    required this.calendar,
    required this.onWantedChanged,
    required this.onChooseCalendar,
    required this.onOpenAppSettings,
  });

  /// Whether the rider switched the setting on. It only takes effect while
  /// [access] is granted.
  final bool wanted;
  final CalendarAccess access;

  /// Where new saves go; null until one is set up.
  final DeviceCalendar? calendar;
  final ValueChanged<bool> onWantedChanged;
  final VoidCallback onChooseCalendar;
  final VoidCallback onOpenAppSettings;

  bool get _isOn =>
      wanted && access == CalendarAccess.granted && calendar != null;

  /// The rider wants it on but Android won't let it, either because access
  /// was revoked or because asking again would not show the prompt.
  bool get _isBlocked =>
      access == CalendarAccess.permanentlyDenied ||
      (wanted && access != CalendarAccess.granted);

  /// Where trips end up, on the phone or synced, with the other way
  /// greyed out as how to get there.
  List<_Rule> _whereRules() {
    final calendar = this.calendar;
    final synced = _isOn && !calendar!.isLocal;
    const local = 'Trips stay on this phone, in a calendar of their own.';
    const toLocal =
        'To keep trips on this phone only, pick Transportia+ above.';
    // The picker only shows while the setting is on.
    final toSynced =
        'To have trips on your other devices, make a calendar in your online '
        'account and pick it ${_isOn ? 'above' : 'here once this is on'}.';
    if (!synced) {
      return [
        const _Rule(icon: LucideIcons.smartphone, text: local),
        _Rule.hint(icon: LucideIcons.cloud, text: toSynced),
      ];
    }
    return [
      const _Rule.hint(icon: LucideIcons.smartphone, text: toLocal),
      _Rule(
        icon: LucideIcons.cloud,
        text:
            '${calendar.syncedBy ?? 'Its account'} syncs this calendar to '
            'your other devices.',
      ),
    ];
  }

  /// Whether saved trips go to a calendar, under the page's title.
  String get _statusLine {
    if (_isOn) return 'On, saved trips go to ${calendar!.name}';
    if (_isBlocked) return 'Off: calendar access is turned off';
    return 'Off: saved trips stay in the app';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final calendar = this.calendar;
    return AppScreen.page(
      icon: LucideIcons.calendarSync,
      title: CalendarSettingsScreen.title,
      subtitle: _statusLine,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ToggleCard(
            icon: LucideIcons.calendarPlus,
            title: 'Add saved trips to calendar',
            subtitle: 'Creates an event for each trip you save',
            value: _isOn,
            onChanged: onWantedChanged,
          ),
          if (_isBlocked) ...[
            const SizedBox(height: 12),
            WarningNotice(
              icon: LucideIcons.lock,
              title: 'Calendar access is off',
              body:
                  'Allow Transportia+ to use your calendar in Android '
                  'settings, then switch this on again.',
              action: _OpenSettingsLink(onPressed: onOpenAppSettings),
            ),
          ],
          if (_isOn) ...[
            const SizedBox(height: 12),
            SelectCard(
              label: 'Saved trips go to',
              icon: calendar!.isLocal
                  ? LucideIcons.smartphone
                  : LucideIcons.cloud,
              iconColor: Color(calendar.color),
              value: calendar.name,
              detail: calendar.whereabouts,
              onPressed: onChooseCalendar,
            ),
          ],
          const SizedBox(height: 32),
          const SectionTitle(text: 'How it works'),
          const SizedBox(height: 16),
          ..._whereRules(),
          const _Rule(
            icon: LucideIcons.bookmark,
            text: 'Only trips you save. Recent trips and searches never.',
          ),
          const _Rule(
            icon: LucideIcons.clock,
            text: 'Planned times. Delays and live changes stay in the app.',
          ),
          const _Rule(
            icon: LucideIcons.pencil,
            text:
                'Renaming or removing a saved trip changes its event, '
                'unless you edited the event yourself.',
          ),
          const _Rule(
            icon: LucideIcons.history,
            text: 'Past trips stay in the calendar when the app clears them.',
          ),
        ],
      ),
    );
  }
}

/// The way to Android's settings for this app, under the access warning.
class _OpenSettingsLink extends StatelessWidget {
  const _OpenSettingsLink({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    // The highlight pads its child; shifted back by that much so the words
    // line up with the warning's text above them.
    return Transform.translate(
      offset: const Offset(-_kHighlightInset, 0),
      child: PressableHighlight(
        onPressed: onPressed,
        enableHaptics: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Open settings',
              style: TextStyle(fontSize: 15, color: accent),
            ),
            const SizedBox(width: 6),
            Icon(LucideIcons.settings, size: 18, color: accent),
          ],
        ),
      ),
    );
  }
}

/// One line of what the sync does and doesn't do.
class _Rule extends StatelessWidget {
  const _Rule({required this.icon, required this.text}) : isHint = false;

  /// A way it could work instead, greyed out next to the way it does.
  const _Rule.hint({required this.icon, required this.text}) : isHint = true;

  final IconData icon;
  final String text;
  final bool isHint;

  @override
  Widget build(BuildContext context) {
    final iconColor = isHint
        ? AppColors.black.withValues(alpha: 0.3)
        : AppColors.accentOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: AppText.bodyMuted)),
        ],
      ),
    );
  }
}
