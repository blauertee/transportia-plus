import 'package:flutter/widgets.dart';

import '../utils/app_icons.dart';

/// Draws an [AppIcon], sized and coloured by the surrounding [IconTheme]
/// unless told otherwise, so it can stand wherever an [Icon] does.
class AppIconView extends StatelessWidget {
  const AppIconView(this.icon, {super.key, this.size, this.color});

  final AppIcon icon;
  final double? size;
  final Color? color;

  /// The base glyph, shrunk and nudged up-left to make room for the badge.
  static const double _baseScale = 0.88;
  static const Offset _baseShift = Offset(-0.06, -0.08);

  /// The badge, past the box's lower right corner: it may overhang, as a
  /// badge on an app icon does, rather than squeeze the glyph further.
  static const double _badgeScale = 0.54;
  static const Offset _badgeOverhang = Offset(0.12, 0.1);

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final size = this.size ?? theme.size ?? 24;
    final color = this.color ?? theme.color;
    return switch (icon) {
      GlyphIcon(:final data) => Icon(data, size: size, color: color),
      BadgedIcon(:final base, :final badge) => SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: _baseShift.dx * size,
              top: _baseShift.dy * size,
              child: Icon(base, size: size * _baseScale, color: color),
            ),
            Positioned(
              right: -_badgeOverhang.dx * size,
              bottom: -_badgeOverhang.dy * size,
              child: Icon(badge, size: size * _badgeScale, color: color),
            ),
          ],
        ),
      ),
    };
  }
}
