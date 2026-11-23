import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../models/time_selection.dart';
import '../navigation/routes.dart';
import '../theme/app_colors.dart';
import '../utils/time_utils.dart';
import 'bottom_overlay_card.dart';

/// How many days past today the calendar reaches.
const int _kSelectableDaysAhead = 365;

/// Any Monday, to name the calendar's weekday columns from.
final DateTime _kAnyMonday = DateTime(2024, 1, 1);

/// Shortcuts from the current time, offered under the wheels.
const List<Duration> _kQuickOffsets = [
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(hours: 1),
];

/// Row height of the time wheels; the highlight band behind them must match.
const double _kWheelItemExtent = 44;

/// Rows of the wheel visible at once: the selected one and two either side.
const int _kWheelVisibleRows = 5;

/// Days offered as one-tap tiles, starting today; the calendar reaches the rest.
const int _kQuickDayCount = 4;

/// How long a wheel takes to travel to a value set by a
/// shortcut rather than by the finger.
const Duration _kJumpDuration = Duration(milliseconds: 280);

/// Shows [TimeSelectionOverlay] over the current screen, resolving once it has
/// closed however it was dismissed.
///
/// Not barrier-dismissible: the overlay has its own dismiss action, and a tap
/// outside it lands on the map or the field behind it.
Future<void> showTimeSelectionOverlay(
  BuildContext context, {
  required TimeSelection currentSelection,
  required ValueChanged<TimeSelection> onSelectionChanged,
  required VoidCallback onDismiss,
  bool showDepartArriveToggle = true,
}) {
  return context.openSheet<void>(
    label: 'Time selection',
    dismissible: false,
    builder: (_) => TimeSelectionOverlay(
      currentSelection: currentSelection,
      onSelectionChanged: onSelectionChanged,
      onDismiss: onDismiss,
      showDepartArriveToggle: showDepartArriveToggle,
    ),
  );
}

class TimeSelectionOverlay extends StatefulWidget {
  const TimeSelectionOverlay({
    super.key,
    required this.currentSelection,
    required this.onSelectionChanged,
    required this.onDismiss,
    this.showDepartArriveToggle = true,
    this.now,
  });

  final TimeSelection currentSelection;
  final void Function(TimeSelection) onSelectionChanged;
  final VoidCallback onDismiss;
  final bool showDepartArriveToggle;

  /// The current time; read from the clock when null.
  final DateTime? now;

  @override
  State<TimeSelectionOverlay> createState() => _TimeSelectionOverlayState();
}

class _TimeSelectionOverlayState extends State<TimeSelectionOverlay> {
  late DateTime _selectedDate;
  late int _selectedHour;
  late int _selectedMinute;
  late bool _isArriveBy;
  bool _isCalendarOpen = false;
  late final FixedExtentScrollController _hourController;
  late final FixedExtentScrollController _minuteController;

  DateTime _now() => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    // A "now" selection carries the moment it was made, which may be long
    // past; the wheels should open on the clock as it reads today.
    final initial = widget.currentSelection.isNow
        ? _now()
        : widget.currentSelection.dateTime;
    _selectedDate = DateTime(initial.year, initial.month, initial.day);
    _selectedHour = initial.hour;
    _selectedMinute = initial.minute;
    _isArriveBy = widget.currentSelection.isArriveBy;
    _hourController = FixedExtentScrollController(initialItem: _selectedHour);
    _minuteController = FixedExtentScrollController(
      initialItem: _selectedMinute,
    );
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  DateTime get _selectedDateTime {
    return DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedHour,
      _selectedMinute,
    );
  }

  DateTime get _today {
    final now = _now();
    return DateTime(now.year, now.month, now.day);
  }

  /// [_kSelectableDaysAhead] past today, or the selection when that already
  /// lies further out.
  DateTime get _lastSelectableDay {
    final today = _today;
    final lastDay = DateTime(
      today.year,
      today.month,
      today.day + _kSelectableDaysAhead,
    );
    return _selectedDate.isAfter(lastDay) ? _selectedDate : lastDay;
  }

  /// Today, or the selection when that already lies in the past.
  DateTime get _firstSelectableDay {
    final today = _today;
    return _selectedDate.isBefore(today) ? _selectedDate : today;
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _isCalendarOpen = false;
    });
  }

  void _jumpTo(DateTime target) {
    setState(() {
      _selectedDate = DateTime(target.year, target.month, target.day);
      _selectedHour = target.hour;
      _selectedMinute = target.minute;
    });
    _spinWheel(_hourController, target.hour, Duration.hoursPerDay);
    _spinWheel(_minuteController, target.minute, Duration.minutesPerHour);
  }

  /// Turns a looping wheel to [value] the short way round.
  void _spinWheel(
    FixedExtentScrollController controller,
    int value,
    int valueCount,
  ) {
    if (!controller.hasClients) return;
    final current = controller.selectedItem;
    var steps = (value - current) % valueCount;
    if (steps > valueCount ~/ 2) steps -= valueCount;
    if (steps == 0) return;
    controller.animateToItem(
      current + steps,
      duration: _kJumpDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _handleConfirm() {
    final selection = TimeSelection(
      dateTime: _selectedDateTime,
      isArriveBy: _isArriveBy,
      isDefaultNow: false,
    );
    widget.onSelectionChanged(selection);
    widget.onDismiss();
  }

  void _handleSetNow() {
    widget.onSelectionChanged(TimeSelection.now());
    widget.onDismiss();
  }

  /// The wheels are kept out of the tree while the calendar shows, so they
  /// are rebuilt from the controllers, which hold their place meanwhile.
  Widget _buildTimeControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TimeWheels(
          hourController: _hourController,
          minuteController: _minuteController,
          onHourChanged: (hour) => setState(() => _selectedHour = hour),
          onMinuteChanged: (minute) => setState(() => _selectedMinute = minute),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (final offset in _kQuickOffsets) ...[
              if (offset != _kQuickOffsets.first) const SizedBox(width: 8),
              Expanded(
                child: _QuickOffsetChip(
                  offset: offset,
                  onTap: () => _jumpTo(_now().add(offset)),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final today = _today;
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.showDepartArriveToggle) ...[
          _DepartArriveToggle(
            isArriveBy: _isArriveBy,
            onChanged: (isArriveBy) => setState(() => _isArriveBy = isArriveBy),
          ),
          const SizedBox(height: 12),
        ],
        _DayRow(
          quickDays: calendarDays(
            today,
            DateTime(today.year, today.month, today.day + _kQuickDayCount - 1),
          ),
          today: today,
          selectedDate: _selectedDate,
          isCalendarOpen: _isCalendarOpen,
          onChanged: _selectDate,
          onCalendarTap: () =>
              setState(() => _isCalendarOpen = !_isCalendarOpen),
        ),
        const SizedBox(height: 12),
        AnimatedSize(
          duration: _kJumpDuration,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _isCalendarOpen
              ? _MonthCalendar(
                  firstDay: _firstSelectableDay,
                  lastDay: _lastSelectableDay,
                  today: today,
                  selectedDate: _selectedDate,
                  onChanged: _selectDate,
                )
              : _buildTimeControls(),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ActionButton.secondary(
                label: 'Now',
                onTap: _handleSetNow,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ActionButton.primary(
                label: 'Confirm',
                onTap: _handleConfirm,
              ),
            ),
          ],
        ),
      ],
    );

    return BottomOverlayCard(
      title: 'Set time',
      maxHeightFactor: 0.8,
      padding: const EdgeInsets.all(16),
      onDismiss: widget.onDismiss,
      child: content,
    );
  }
}

/// Faint fill behind the overlay's controls, readable in either theme.
Color _controlFill() => AppColors.black.withValues(alpha: 0.06);

class _DepartArriveToggle extends StatelessWidget {
  const _DepartArriveToggle({
    required this.isArriveBy,
    required this.onChanged,
  });

  final bool isArriveBy;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _controlFill(),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ToggleSegment(
              label: 'Depart at',
              isSelected: !isArriveBy,
              onTap: () => onChanged(false),
            ),
          ),
          Expanded(
            child: _ToggleSegment(
              label: 'Arrive by',
              isSelected: isArriveBy,
              onTap: () => onChanged(true),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleSegment extends StatelessWidget {
  const _ToggleSegment({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.accentOf(context)
              : const Color(0x00000000),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected ? AppColors.solidWhite : AppColors.black,
            ),
          ),
        ),
      ),
    );
  }
}

/// The next few days as equal tiles, then a calendar tile for any other day.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.quickDays,
    required this.today,
    required this.selectedDate,
    required this.isCalendarOpen,
    required this.onChanged,
    required this.onCalendarTap,
  });

  final List<DateTime> quickDays;
  final DateTime today;
  final DateTime selectedDate;
  final bool isCalendarOpen;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onCalendarTap;

  @override
  Widget build(BuildContext context) {
    final isSelectionQuick = quickDays.contains(selectedDate);
    final tiles = <Widget>[
      for (final day in quickDays)
        _DayTile(
          day: day,
          today: today,
          isSelected: day == selectedDate,
          onTap: () => onChanged(day),
        ),
      _CalendarTile(
        isOpen: isCalendarOpen,
        otherDay: isSelectionQuick ? null : selectedDate,
        onTap: onCalendarTap,
      ),
    ];
    return SizedBox(
      height: 58,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(child: tiles[i]),
          ],
        ],
      ),
    );
  }
}

/// The shape every tile in the day row shares: a rounded box, filled with the
/// accent when chosen, holding a label over a smaller line.
class _DayRowTileFrame extends StatelessWidget {
  const _DayRowTileFrame({
    required this.isHighlighted,
    required this.onTap,
    required this.top,
    this.bottom,
  });

  final bool isHighlighted;
  final VoidCallback onTap;
  final Widget Function(Color foreground) top;
  final String? bottom;

  @override
  Widget build(BuildContext context) {
    final foreground = isHighlighted ? AppColors.solidWhite : AppColors.black;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: isHighlighted ? AppColors.accentOf(context) : _controlFill(),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              top(foreground),
              if (bottom != null) ...[
                const SizedBox(height: 2),
                Text(
                  bottom!,
                  style: TextStyle(
                    fontSize: 12,
                    color: foreground.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.today,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final DateTime today;
  final bool isSelected;
  final VoidCallback onTap;

  bool get _isTomorrow =>
      day == DateTime(today.year, today.month, today.day + 1);

  /// Short enough that all five tiles fit a narrow phone at one font size;
  /// 'Tomorrow' spelt out would not.
  String get _dayName {
    if (day == today) return 'Today';
    if (_isTomorrow) return 'Tmrw';
    return formatWeekday(day);
  }

  @override
  Widget build(BuildContext context) {
    return _DayRowTileFrame(
      isHighlighted: isSelected,
      onTap: onTap,
      top: (foreground) => Text(
        _dayName,
        semanticsLabel: _isTomorrow ? 'Tomorrow' : null,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
      bottom: formatDayMonth(day),
    );
  }
}

class _CalendarTile extends StatelessWidget {
  const _CalendarTile({
    required this.isOpen,
    required this.otherDay,
    required this.onTap,
  });

  final bool isOpen;

  /// The selected day when none of the day tiles holds it; the calendar tile
  /// then stands for it, so the selection is always visible in the row.
  final DateTime? otherDay;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: isOpen ? 'Close calendar' : 'Open calendar',
      child: _DayRowTileFrame(
        isHighlighted: isOpen || otherDay != null,
        onTap: onTap,
        top: (foreground) => Icon(
          isOpen ? LucideIcons.clock : LucideIcons.calendarDays,
          size: 20,
          color: foreground,
        ),
        bottom: otherDay == null ? null : formatDayMonth(otherDay!),
      ),
    );
  }
}

/// A month at a time, for reaching days beyond the day tiles.
class _MonthCalendar extends StatefulWidget {
  const _MonthCalendar({
    required this.firstDay,
    required this.lastDay,
    required this.today,
    required this.selectedDate,
    required this.onChanged,
  });

  final DateTime firstDay;
  final DateTime lastDay;
  final DateTime today;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;

  @override
  State<_MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<_MonthCalendar> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.selectedDate.year, widget.selectedDate.month);
  }

  bool get _hasPreviousMonth =>
      _month.isAfter(DateTime(widget.firstDay.year, widget.firstDay.month));

  bool get _hasNextMonth =>
      _month.isBefore(DateTime(widget.lastDay.year, widget.lastDay.month));

  void _turnMonth(int months) {
    setState(() => _month = DateTime(_month.year, _month.month + months));
  }

  bool _isSelectable(DateTime day) =>
      !day.isBefore(widget.firstDay) && !day.isAfter(widget.lastDay);

  @override
  Widget build(BuildContext context) {
    final cells = monthGrid(_month);
    return Column(
      key: const ValueKey('monthCalendar'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            _MonthArrow(
              icon: LucideIcons.chevronLeft,
              label: 'Previous month',
              onTap: _hasPreviousMonth ? () => _turnMonth(-1) : null,
            ),
            Expanded(
              child: Text(
                formatMonthYear(_month),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.black,
                ),
              ),
            ),
            _MonthArrow(
              icon: LucideIcons.chevronRight,
              label: 'Next month',
              onTap: _hasNextMonth ? () => _turnMonth(1) : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < DateTime.daysPerWeek; i++)
              Expanded(
                child: Text(
                  formatWeekday(_kAnyMonday.add(Duration(days: i))),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.black.withValues(alpha: 0.5),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (
          var weekStart = 0;
          weekStart < cells.length;
          weekStart += DateTime.daysPerWeek
        )
          Row(
            children: [
              for (final day in cells.sublist(
                weekStart,
                weekStart + DateTime.daysPerWeek,
              ))
                Expanded(
                  child: day == null
                      ? const SizedBox(height: 40)
                      : _CalendarDay(
                          day: day,
                          isToday: day == widget.today,
                          isSelected: day == widget.selectedDate,
                          onTap: _isSelectable(day)
                              ? () => widget.onChanged(day)
                              : null,
                        ),
                ),
            ],
          ),
      ],
    );
  }
}

class _MonthArrow extends StatelessWidget {
  const _MonthArrow({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;

  /// Null past the last month the calendar reaches.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(
            icon,
            size: 20,
            color: AppColors.black.withValues(alpha: onTap == null ? 0.2 : 0.7),
          ),
        ),
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;

  /// Null for a day outside the range the overlay offers.
  final VoidCallback? onTap;

  Color _textColor(BuildContext context) {
    if (isSelected) return AppColors.solidWhite;
    if (onTap == null) return AppColors.black.withValues(alpha: 0.25);
    if (isToday) return AppColors.accentOf(context);
    return AppColors.black;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 40,
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isSelected ? AppColors.accentOf(context) : null,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isToday || isSelected
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: _textColor(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hour and minute wheels side by side over a band marking the chosen row.
class _TimeWheels extends StatelessWidget {
  const _TimeWheels({
    required this.hourController,
    required this.minuteController,
    required this.onHourChanged,
    required this.onMinuteChanged,
  });

  final FixedExtentScrollController hourController;
  final FixedExtentScrollController minuteController;
  final ValueChanged<int> onHourChanged;
  final ValueChanged<int> onMinuteChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kWheelItemExtent * _kWheelVisibleRows,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            height: _kWheelItemExtent,
            decoration: BoxDecoration(
              color: _controlFill(),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _TimeWheel(
                key: const ValueKey('hourWheel'),
                controller: hourController,
                valueCount: Duration.hoursPerDay,
                onChanged: onHourChanged,
              ),
              Text(
                ':',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black,
                ),
              ),
              _TimeWheel(
                key: const ValueKey('minuteWheel'),
                controller: minuteController,
                valueCount: Duration.minutesPerHour,
                onChanged: onMinuteChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A looping wheel of two-digit values from 0 to [valueCount] - 1, so 59
/// runs straight on to 00 without winding back through the whole hour.
class _TimeWheel extends StatelessWidget {
  const _TimeWheel({
    super.key,
    required this.controller,
    required this.valueCount,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final int valueCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: ListWheelScrollView.useDelegate(
        controller: controller,
        itemExtent: _kWheelItemExtent,
        physics: const FixedExtentScrollPhysics(),
        diameterRatio: 1.6,
        overAndUnderCenterOpacity: 0.4,
        onSelectedItemChanged: (index) => onChanged(index % valueCount),
        childDelegate: ListWheelChildLoopingListDelegate(
          children: [
            for (var value = 0; value < valueCount; value++)
              Center(
                child: Text(
                  value.toString().padLeft(2, '0'),
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: AppColors.black,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _QuickOffsetChip extends StatelessWidget {
  const _QuickOffsetChip({required this.offset, required this.onTap});

  final Duration offset;
  final VoidCallback onTap;

  String get _label {
    if (offset.inMinutes < Duration.minutesPerHour) {
      return 'In ${offset.inMinutes} min';
    }
    return 'In ${offset.inHours} h';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: _controlFill(),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(
            _label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.black,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton.primary({required this.label, required this.onTap})
    : isPrimary = true;

  const _ActionButton.secondary({required this.label, required this.onTap})
    : isPrimary = false;

  final String label;
  final bool isPrimary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.accentOf(context) : _controlFill(),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isPrimary ? AppColors.solidWhite : AppColors.black,
            ),
          ),
        ),
      ),
    );
  }
}
