import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';

Color? parseHexColor(String? hex) {
  if (hex == null || hex.isEmpty) return null;

  var cleaned = hex.replaceAll('#', '');

  if (cleaned.length == 6) {
    cleaned = 'FF$cleaned';
  }

  if (cleaned.length != 8) return null;

  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;

  return Color(value);
}

Color parseHexColorOr(String? hex, Color fallback) {
  return parseHexColor(hex) ?? fallback;
}

Color parseHexColorOrAccent(BuildContext context, String? hex) {
  return parseHexColor(hex) ?? AppColors.accentOf(context);
}

String colorToHex(Color color) {
  final r = (color.r * 255.0).round();
  final g = (color.g * 255.0).round();
  final b = (color.b * 255.0).round();
  return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
}

/// Contrast ratio between two opaque colours, per WCAG.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Above this luminance a background counts as light, and colours have to be
/// darkened rather than lightened to stand out against it.
const double _kMidLuminance = 0.5;

/// How far each attempt moves the colour's lightness: fine enough that the
/// result still looks like the feed's colour, coarse enough to settle in a
/// few dozen iterations.
const double _kContrastStep = 0.02;

/// Enough steps to cross the whole lightness range at [_kContrastStep].
const int _kMaxContrastSteps = 50;

/// Pushes [color] away from [background] until it clears [minRatio].
///
/// Hue and saturation are kept, so the line still reads as the operator's —
/// only lightness moves. Feeds ship pale yellows that vanish on white and
/// near-blacks that vanish on the dark theme, and a 2px line has less room to
/// survive that than a block of colour does. 3:1 is the WCAG threshold for
/// non-text graphics, which is what this is.
///
/// Returns [color] untouched when it already passes.
Color ensureContrast(Color color, Color background, {double minRatio = 3.0}) {
  if (contrastRatio(color, background) >= minRatio) return color;

  // On a light background darken, on a dark one lighten — moving the other
  // way would have to cross the background to find contrast on the far side.
  final darken = background.computeLuminance() > _kMidLuminance;
  final hsl = HSLColor.fromColor(color);

  for (var step = 1; step <= _kMaxContrastSteps; step++) {
    final shift = step * _kContrastStep;
    final lightness = (darken ? hsl.lightness - shift : hsl.lightness + shift)
        .clamp(0.0, 1.0);
    final candidate = hsl.withLightness(lightness).toColor();
    if (contrastRatio(candidate, background) >= minRatio) return candidate;
    if (lightness == 0.0 || lightness == 1.0) break;
  }

  // Saturated hues can run out of lightness before they clear the bar — a
  // mid-blue on black, say. Black or white always clears it.
  return darken ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
}

/// Below this contrast the feed's text colour on its own line colour is
/// swapped for black or white. Deliberately lax: operators pair white with
/// mid oranges and reds (about 2.9:1) and those badges read fine; only a
/// pairing that really fails, white on a yellow, is overridden.
const double _kMinLineTextContrast = 2.0;

/// A transit line's colour: the feed's `routeColor`, as the operator gave it.
///
/// The one way the app reads a line colour, for badges and the lines on the
/// map alike. Deliberately not adjusted to the background: a badge stays
/// legible through [onLineColor], and shifting the operator's colour made it
/// look worse than a pale badge did.
Color? lineColor(String? hex) => parseHexColor(hex?.trim());

/// [lineColor], or the accent when the feed gave no colour.
Color lineColorOrAccent(BuildContext context, String? hex) =>
    lineColor(hex) ?? AppColors.accentOf(context);

/// The text colour for a badge filled with [fill].
///
/// The feed's own text colour when it reads on [fill], otherwise black or
/// white, whichever reads better. [fallback] stands in when the feed gave
/// none.
Color onLineColor(Color fill, String? textHex, {Color? fallback}) {
  final feed = parseHexColor(textHex?.trim()) ?? fallback;
  if (feed != null && contrastRatio(feed, fill) >= _kMinLineTextContrast) {
    return feed;
  }
  const black = AppColors.solidBlack;
  const white = AppColors.solidWhite;
  return contrastRatio(black, fill) >= contrastRatio(white, fill)
      ? black
      : white;
}
