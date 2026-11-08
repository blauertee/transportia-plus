import 'package:flutter/widgets.dart';

import '../providers/theme_provider.dart';
import '../theme/app_colors.dart';
import '../theme/dark_palette.dart';

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

/// A transit line's colour as it should be drawn on the current theme.
///
/// For a line's own colour (a badge or a stretch of the spine) — not for the
/// text printed on it, which keeps the feed's value.
Color? parseLineColor(String? hex) {
  final parsed = parseHexColor(hex);
  if (parsed == null) return null;
  if (!(ThemeProvider.instance?.isDark ?? false)) return parsed;
  return DarkPalette.capLine(parsed);
}

Color parseLineColorOrAccent(BuildContext context, String? hex) {
  return parseLineColor(hex) ?? AppColors.accentOf(context);
}
