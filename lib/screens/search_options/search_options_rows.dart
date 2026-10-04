import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/app_colors.dart';
import '../../widgets/custom_card.dart';
import '../../widgets/options/icon_controls.dart';

/// One titled group of the options screen: a small heading over a card whose
/// rows are split by hairlines.
///
/// Built to the search screen's scale rather than the settings list's, so
/// the whole screen reads in a scroll or two instead of one control per
/// screenful.
class OptionsGroup extends StatelessWidget {
  const OptionsGroup({
    super.key,
    required this.title,
    required this.children,
    this.footnote,
  });

  final String title;
  final List<Widget> children;

  /// A line under the card, for what applies to the group as a whole.
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: OptionGroupHeading(title),
        ),
        CustomCard(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          margin: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0)
                  Container(
                    height: 1,
                    color: AppColors.black.withValues(alpha: 0.06),
                  ),
                children[i],
              ],
            ],
          ),
        ),
        if (footnote != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: OptionsNote(footnote!),
          ),
      ],
    );
  }
}

/// A row of an [OptionsGroup]: icon, label, and what it is set to, with the
/// control that changes it underneath when it needs more room than a
/// trailing value.
class OptionsRow extends StatelessWidget {
  const OptionsRow({
    super.key,
    required this.icon,
    required this.label,
    this.value,
    this.trailing,
    this.description,
    this.below,
    this.muted = false,
    this.onTap,
  });

  final IconData icon;
  final String label;

  /// The current setting, in the accent, at the end of the row.
  final String? value;

  /// A control at the end of the row, in place of [value].
  final Widget? trailing;
  final String? description;
  final Widget? below;

  /// Greys the icon and value, for a setting that is switched off.
  final bool muted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final quiet = AppColors.black.withValues(alpha: 0.45);
    final row = Row(
      children: [
        Icon(icon, size: 16, color: muted ? quiet : accent),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 14.5, color: AppColors.black),
          ),
        ),
        if (value != null)
          Text(
            value!,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: muted ? quiet : accent,
            ),
          ),
        ?trailing,
      ],
    );

    final head = Padding(
      padding: EdgeInsets.only(top: 11, bottom: below == null ? 11 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row,
          if (description != null)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 3),
              child: OptionsNote(description!),
            ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The row, its description and the space around them are one
        // target: a rider taps the card, not the arrow at its end. What is
        // [below] is left out, since it holds controls of its own.
        if (onTap case final onTap?)
          Semantics(
            button: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: head,
            ),
          )
        else
          head,
        if (below != null)
          Padding(
            padding: const EdgeInsets.only(left: 26, top: 8, bottom: 11),
            child: below,
          ),
      ],
    );
  }
}

/// A labelled one-line text field inside an [OptionsGroup], for hosts and
/// version strings.
///
/// The placeholder is the value in use when the field is left empty, and
/// the reset icon appears only once something else has been typed.
class OptionsTextRow extends StatelessWidget {
  const OptionsTextRow({
    super.key,
    required this.label,
    required this.controller,
    required this.placeholder,
    required this.onSubmitted,
    required this.isCustom,
    required this.onReset,
    this.focusNode,
    this.keyboardType,
    this.labelWidth = 92,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String placeholder;
  final ValueChanged<String> onSubmitted;
  final bool isCustom;
  final VoidCallback onReset;
  final TextInputType? keyboardType;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.black.withValues(alpha: 0.65),
              ),
            ),
          ),
          Expanded(
            child: CupertinoTextField.borderless(
              controller: controller,
              focusNode: focusNode,
              placeholder: placeholder,
              style: TextStyle(fontSize: 14.5, color: AppColors.black),
              placeholderStyle: TextStyle(
                fontSize: 14.5,
                color: AppColors.black.withValues(alpha: 0.3),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
              autocorrect: false,
              keyboardType: keyboardType,
              textInputAction: TextInputAction.done,
              onSubmitted: onSubmitted,
            ),
          ),
          if (isCustom)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onReset,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  LucideIcons.rotateCcw,
                  size: 14,
                  color: AppColors.black.withValues(alpha: 0.35),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small print under a row or a group.
class OptionsNote extends StatelessWidget {
  const OptionsNote(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      height: 1.3,
      color: AppColors.black.withValues(alpha: 0.45),
    ),
  );
}
