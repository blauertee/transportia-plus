import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/transit_mode_group.dart';
import '../../theme/app_colors.dart';
import '../app_toggle_switch.dart';
import '../options/icon_controls.dart';
import '../options/selectable_tick.dart';

/// One way of travelling within a leg: switched as a whole by its mark, or
/// choice by choice underneath its heading.
class LegSection {
  const LegSection({
    required this.mark,
    required this.title,
    required this.state,
    required this.onToggle,
    this.choices = const [],
    this.inCompactRow = true,
  });

  /// An [Icon], coloured and sized by the panel.
  final Widget mark;
  final String title;
  final GroupState state;
  final VoidCallback onToggle;

  /// Empty for a section that is a single mode, such as walking.
  final List<LegChoice> choices;

  /// False for a section no one would switch as a whole, such as the odds
  /// and ends of a street leg: it is listed in the full view only.
  final bool inCompactRow;
}

/// One tick under a section's heading.
class LegChoice {
  const LegChoice({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;
}

/// A setting of the leg that is not a way of travelling: a switch, or a
/// value with a slider.
class LegOption {
  /// On or off, by its mark or its heading.
  const LegOption.toggle({
    required this.mark,
    required this.title,
    required bool this.on,
    required VoidCallback this.onToggle,
    this.inCompactRow = true,
  }) : icon = null,
       value = null,
       slider = null,
       subtitle = null;

  /// A number, set with the slider [slider] builds. [value] null means no
  /// limit, shown as the infinity sign.
  const LegOption.value({
    required IconData this.icon,
    required this.title,
    required this.value,
    required SliderBuilder this.slider,
  }) : mark = null,
       on = null,
       onToggle = null,
       subtitle = null,
       inCompactRow = true;

  /// On or off, with a line saying what it applies to: drawn as a sentence
  /// with a switch, so it cannot be read as one more section. Full view
  /// only.
  const LegOption.switchRow({
    required IconData this.icon,
    required this.title,
    required String this.subtitle,
    required bool this.on,
    required VoidCallback this.onToggle,
  }) : mark = null,
       value = null,
       slider = null,
       inCompactRow = false;

  final Widget? mark;
  final IconData? icon;
  final String title;
  final bool? on;
  final VoidCallback? onToggle;
  final String? value;
  final SliderBuilder? slider;
  final String? subtitle;

  /// False for an action rather than a switch, such as picking a stop to
  /// travel through: it lives in the full view only.
  final bool inCompactRow;

  bool get isValue => slider != null;
  bool get isSwitchRow => subtitle != null;
}

/// Builds a value option's slider. [onChangeEnd] is called when the rider
/// lets go, so a slider opened for one adjustment can close itself.
typedef SliderBuilder = Widget Function(VoidCallback? onChangeEnd);

/// What a [LegPanel] shows: the compact rows, the compact rows with one
/// value's slider open under them, or everything.
@immutable
class LegView {
  const LegView._({required this.isFull, this.revealed});

  static const LegView compact = LegView._(isFull: false);
  static const LegView full = LegView._(isFull: true);

  /// The compact rows with the slider of the value titled [title] open: a
  /// quick adjustment that should not cost the rider the rest of the card.
  const LegView.revealing(String title)
    : this._(isFull: false, revealed: title);

  final bool isFull;

  /// The title of the value option whose slider is open in the compact view.
  final String? revealed;

  @override
  bool operator ==(Object other) =>
      other is LegView && other.isFull == isFull && other.revealed == revealed;

  @override
  int get hashCode => Object.hash(isFull, revealed);
}

/// A leg's sections and options, in one of two views.
///
/// Compact: a row of section marks, a row of option marks, and a link to the
/// rest. Full: every section as a heading with its choices under it, then
/// every option as a heading with its slider open. The same lists feed both,
/// so the two views cannot offer different things.
class LegPanel extends StatelessWidget {
  const LegPanel({
    super.key,
    required this.sections,
    required this.options,
    required this.view,
    required this.onViewChanged,
    required this.tooltips,
  });

  final List<LegSection> sections;
  final List<LegOption> options;
  final LegView view;
  final ValueChanged<LegView> onViewChanged;
  final OptionTooltipController tooltips;

  @override
  Widget build(BuildContext context) {
    final full = view.isFull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (full) ..._full() else ..._compact(),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: _MoreLink(
            expanded: full,
            onPressed: () =>
                onViewChanged(full ? LegView.compact : LegView.full),
          ),
        ),
      ],
    );
  }

  /// Opens a value's slider under the compact rows, or closes it again when
  /// its chip is tapped a second time.
  void _toggleRevealed(LegOption option) => onViewChanged(
    view.revealed == option.title
        ? LegView.compact
        : LegView.revealing(option.title),
  );

  List<Widget> _compact() {
    final compactOptions = [
      for (final option in options)
        if (option.inCompactRow) option,
    ];
    final revealed = compactOptions
        .where((option) => option.isValue && option.title == view.revealed)
        .firstOrNull;
    return [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final section in sections)
            if (section.inCompactRow)
              SizedBox(
                width: 42,
                child: IconPick.glyph(
                  glyph: section.mark,
                  label: section.title,
                  selected: section.state == GroupState.all,
                  partial: section.state == GroupState.some,
                  tooltips: tooltips,
                  onPressed: section.onToggle,
                ),
              ),
        ],
      ),
      if (compactOptions.isNotEmpty) ...[
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final option in compactOptions)
              if (option.isValue)
                ValueChip(
                  icon: option.icon!,
                  label: option.title,
                  value: option.value,
                  valueIcon: option.value == null ? LucideIcons.infinity : null,
                  tooltips: tooltips,
                  expanded: option == revealed,
                  onPressed: () => _toggleRevealed(option),
                )
              else
                SizedBox(
                  width: 42,
                  child: IconPick.glyph(
                    glyph: option.mark!,
                    label: option.title,
                    selected: option.on!,
                    tooltips: tooltips,
                    onPressed: option.onToggle!,
                  ),
                ),
          ],
        ),
      ],
      if (revealed != null) ...[
        const SizedBox(height: 4),
        // Closes once the rider lets go: it was opened for one adjustment,
        // and the chip above already shows the value it was set to.
        revealed.slider!(() => onViewChanged(LegView.compact)),
      ],
    ];
  }

  List<Widget> _full() => [
    for (final (i, section) in sections.indexed) ...[
      if (i > 0) const SizedBox(height: 8),
      LegHeading(
        mark: section.mark,
        title: section.title,
        look: section.state == GroupState.none
            ? HeadingLook.off
            : HeadingLook.on,
        onPressed: section.onToggle,
      ),
      if (section.choices.isNotEmpty) ...[
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: LegHeading.textIndent),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final choice in section.choices)
                SelectableTick(
                  label: choice.label,
                  selected: choice.selected,
                  onPressed: choice.onPressed,
                ),
            ],
          ),
        ),
      ],
    ],
    if (options.isNotEmpty) ...[
      const SizedBox(height: 14),
      Container(height: 1, color: AppColors.hairline),
      const SizedBox(height: 8),
      for (final (i, option) in options.indexed) ...[
        if (i > 0) const SizedBox(height: 2),
        if (option.isValue) ...[
          LegHeading(
            mark: Icon(option.icon),
            title: option.title,
            look: HeadingLook.value,
            trailing: option.value == null
                ? const Icon(LucideIcons.infinity, size: 18)
                : Text(
                    option.value!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
          Padding(
            // The slider's own track is inset by its thumb; this lines the
            // track up with the heading's text rather than its box.
            padding: const EdgeInsets.only(
              left: LegHeading.textIndent - _sliderInset,
            ),
            child: option.slider!(null),
          ),
        ] else if (option.isSwitchRow)
          _SwitchRow(option)
        else
          LegHeading(
            mark: option.mark!,
            title: option.title,
            look: option.on! ? HeadingLook.on : HeadingLook.off,
            onPressed: option.onToggle,
          ),
      ],
    ],
  ];

  static const double _sliderInset = 16;
}

/// A [LegOption.switchRow]: the mark in the headings' column, then a
/// sentence and what it applies to, then the switch. The whole row toggles.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow(this.option);

  final LegOption option;

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.black.withValues(alpha: 0.55);
    return Semantics(
      button: true,
      toggled: option.on,
      label: '${option.title}. ${option.subtitle}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: option.onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              SizedBox(
                width: LegHeading.markColumn,
                child: Center(child: Icon(option.icon, size: 19, color: faint)),
              ),
              const SizedBox(width: LegHeading.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.title,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.black,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      option.subtitle!,
                      style: TextStyle(fontSize: 12.5, color: faint),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AppToggleSwitch(
                value: option.on!,
                onChanged: (_) => option.onToggle!(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// How a heading is coloured: a switch that is on or off, or a value, which
/// is neither and takes the text colour.
enum HeadingLook { on, off, value }

/// A section's or an option's heading: its mark and its name, one target.
///
/// No box: in the full view the heading is a title, and the choices under it
/// carry the detail. The colour says whether it is on.
class LegHeading extends StatelessWidget {
  const LegHeading({
    super.key,
    required this.mark,
    required this.title,
    required this.look,
    this.trailing,
    this.onPressed,
  });

  final Widget mark;
  final String title;
  final HeadingLook look;
  final Widget? trailing;

  /// The whole row, not only the mark. Null for a value, which is set with
  /// its slider.
  final VoidCallback? onPressed;

  /// The marks' column and the space after it, which rows that line up with
  /// the headings share.
  static const double markColumn = 26;
  static const double gap = 10;

  /// Where a heading's text starts, and so where anything under it starts.
  static const double textIndent = markColumn + gap;

  @override
  Widget build(BuildContext context) {
    final color = switch (look) {
      HeadingLook.on => AppColors.accentOf(context),
      HeadingLook.off => AppColors.black.withValues(alpha: 0.55),
      HeadingLook.value => AppColors.black.withValues(alpha: 0.8),
    };
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: markColumn,
            // Centred, not started: an icon fills its box and so centres
            // itself, but a letter such as the regional R is only as wide
            // as it is and would sit at the left, as if indented under the
            // heading above.
            child: Center(
              child: IconTheme(
                data: IconThemeData(size: 19, color: color),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: color),
                  child: mark,
                ),
              ),
            ),
          ),
          const SizedBox(width: gap),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: color,
              ),
            ),
          ),
          if (trailing case final trailing?)
            IconTheme(
              data: IconThemeData(color: AppColors.black),
              child: DefaultTextStyle.merge(
                style: TextStyle(color: AppColors.black),
                child: trailing,
              ),
            ),
        ],
      ),
    );
    final onPressed = this.onPressed;
    if (onPressed == null) return row;
    return Semantics(
      button: true,
      toggled: look == HeadingLook.on,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: row,
      ),
    );
  }
}

/// Opens or closes the full view.
///
/// A line of text with its own icon, not a pick: it must not be mistaken
/// for a way of travelling.
class _MoreLink extends StatelessWidget {
  const _MoreLink({required this.expanded, required this.onPressed});

  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Semantics(
      button: true,
      expanded: expanded,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.slidersHorizontal, size: 15, color: accent),
              const SizedBox(width: 6),
              Text(
                expanded ? 'Fewer options' : 'All options',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 14,
                color: accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "R" for regional only, set like a line badge: there is no icon for it
/// that riders would recognise across countries.
class RegionalGlyph extends StatelessWidget {
  const RegionalGlyph({super.key});

  @override
  Widget build(BuildContext context) => Text(
    'R',
    style: TextStyle(
      fontSize: IconTheme.of(context).size ?? 17,
      fontWeight: FontWeight.w900,
      height: 1,
      color: IconTheme.of(context).color,
    ),
  );
}
