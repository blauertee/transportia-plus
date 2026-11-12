import 'package:flutter/painting.dart';

/// The most saturated an accent may be on the dark theme.
const double _kDarkAccentMaxSaturation = 0.5;

/// The lightness every accent takes on the dark theme.
const double _kDarkAccentLightness = 0.64;

/// [picked] as it is drawn on the dark theme.
///
/// The accent swatches are chosen for a white screen; drawn unchanged on a
/// dark one they read as neon. The hue is kept so the rider's choice (blue,
/// green…) survives, and only saturation and lightness move.
Color darkThemeAccent(Color picked) {
  final hsl = HSLColor.fromColor(picked);
  return hsl
      .withSaturation(
        hsl.saturation.clamp(0.0, _kDarkAccentMaxSaturation).toDouble(),
      )
      .withLightness(_kDarkAccentLightness)
      .toColor();
}
