import 'package:flutter/widgets.dart';

/// The small rounded chip a route's short name is drawn in — the line number
/// on a departure row, on a leg, or on a saved trip.
///
/// Named `…Pill` because [RouteBadge] is already a model type.
///
/// Colours arrive resolved. What a feed supplies means different things in
/// different places: a badge sitting among body text reads better dark on the
/// feed's colour, a chip in a departure list reads better light on it, and a
/// walking leg has no colour at all. That choice stays at the call site;
/// `lineColorOrAccent` and `onLineColor` make it one line, and keep the badge
/// legible on the theme's background.
class RouteBadgePill extends StatelessWidget {
  const RouteBadgePill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    this.fontSize = 12,
    this.fontWeight = FontWeight.w600,
    this.minWidth,
  });

  static const double cornerRadius = 4;

  /// [minWidth] for badges stacked in a column, where a one-character line
  /// number would otherwise collapse to a sliver next to a four-character one.
  static const double stackedMinWidth = 30;

  final String label;
  final Color background;
  final Color foreground;
  final EdgeInsetsGeometry padding;
  final double fontSize;
  final FontWeight fontWeight;

  /// See [stackedMinWidth]. Null lets the badge size to its own text.
  final double? minWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: minWidth == null
          ? null
          : BoxConstraints(minWidth: minWidth!),
      padding: padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(cornerRadius),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: foreground,
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
