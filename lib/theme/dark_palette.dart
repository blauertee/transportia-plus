import 'package:flutter/painting.dart';

/// How the dark theme looks: the surface, the text on it, and how a chosen
/// accent colour is toned down so it sits on that surface instead of glowing.
///
/// The accent swatches are picked for a white screen; drawn unchanged on a
/// near-black one they read as neon. A dark palette therefore remaps the
/// rider's accent rather than replacing it, so the choice (blue, green…)
/// survives and only its saturation and lightness move.
class DarkPalette {
  const DarkPalette({
    required this.name,
    required this.background,
    required this.text,
    this.maxSaturation,
    this.lightness,
  });

  final String name;
  final Color background;
  final Color text;

  /// Saturation ceiling for an accent on this palette; null leaves it alone.
  final double? maxSaturation;

  /// Lightness every accent is moved to; null leaves it alone.
  final double? lightness;

  /// The palette in use. Mutable only so drafts can render each option.
  static DarkPalette current = liftedMuted;

  /// Today's dark theme: near-black, pure white text, accents as picked.
  static const unchanged = DarkPalette(
    name: 'unchanged',
    background: Color(0xFF161616),
    text: Color(0xFFFFFFFF),
  );

  /// A: keep the surface, tone the accents down.
  static const mutedAccent = DarkPalette(
    name: 'a_muted_accent',
    background: Color(0xFF161616),
    text: Color(0xFFFFFFFF),
    maxSaturation: 0.5,
    lightness: 0.62,
  );

  /// B: a lifted charcoal surface, as in Android settings, plus muted accents.
  static const liftedMuted = DarkPalette(
    name: 'b_lifted_muted',
    background: Color(0xFF202124),
    text: Color(0xFFE8EAED),
    maxSaturation: 0.5,
    lightness: 0.64,
  );

  /// C: a lifted slate surface (GitHub dimmed) with pastel, tonal accents.
  static const slatePastel = DarkPalette(
    name: 'c_slate_pastel',
    background: Color(0xFF22272E),
    text: Color(0xFFD5DBE3),
    maxSaturation: 0.6,
    lightness: 0.74,
  );

  /// D: a lifted neutral surface with deeper, desaturated accents that stay
  /// closer to their light-theme weight.
  static const liftedDeep = DarkPalette(
    name: 'd_lifted_deep',
    background: Color(0xFF1C1C1E),
    text: Color(0xFFEDEDED),
    maxSaturation: 0.45,
    lightness: 0.56,
  );

  static const options = [mutedAccent, liftedMuted, slatePastel, liftedDeep];

  /// [accent] as it is drawn on this palette's surface.
  Color accentFor(Color accent) {
    final ceiling = maxSaturation;
    final target = lightness;
    if (ceiling == null && target == null) return accent;
    final hsl = HSLColor.fromColor(accent);
    return hsl
        .withSaturation(
          ceiling == null
              ? hsl.saturation
              : hsl.saturation.clamp(0.0, ceiling).toDouble(),
        )
        .withLightness(target ?? hsl.lightness)
        .toColor();
  }
}
