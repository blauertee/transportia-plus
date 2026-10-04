import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'icon_catalogue.dart';
import 'place_icons.dart';

/// An icon the app saves by name: a favourite's, a quick-access section's.
///
/// Usually one glyph. A few the app composes itself, where Lucide has no
/// single glyph for the idea.
sealed class AppIcon {
  const AppIcon();
}

final class GlyphIcon extends AppIcon {
  const GlyphIcon(this.data);

  final IconData data;

  @override
  bool operator ==(Object other) => other is GlyphIcon && other.data == data;

  @override
  int get hashCode => data.hashCode;
}

/// A glyph with a smaller one at its lower right: a car with a key is a car
/// you borrow.
///
/// [badge] should be a heavier weight of its glyph: drawn at about half
/// size, a regular one would come out with half the stroke of [base].
final class BadgedIcon extends AppIcon {
  const BadgedIcon(this.base, this.badge);

  final IconData base;
  final IconData badge;

  @override
  bool operator ==(Object other) =>
      other is BadgedIcon && other.base == base && other.badge == badge;

  @override
  int get hashCode => Object.hash(base, badge);
}

/// Turns saved icon names into icons.
///
/// Names are Lucide's own (`train-front`) for anything from the catalogue.
/// The app's composed icons take a prefix Lucide never uses, so a future
/// Lucide icon cannot shadow one. Favourites saved before the catalogue used
/// names of their own; those still resolve, so nothing stored needs
/// rewriting.
abstract final class AppIcons {
  static const String _ownPrefix = 'transportia:';

  /// A shared car or moped.
  static const String carKeyName = '${_ownPrefix}car-key';
  static const AppIcon carKey = BadgedIcon(
    LucideIcons.car,
    LucideIcons.keyRound600,
  );

  /// What a name nothing knows resolves to.
  static const String fallbackName = 'map-pin';
  static const AppIcon fallback = GlyphIcon(LucideIcons.mapPin);

  static const Map<String, AppIcon> _composed = {carKeyName: carKey};

  /// The names favourites were saved with before the catalogue, including
  /// what a hearted stop is drawn as.
  static const Map<String, IconData> _legacy = {
    'mapPin': LucideIcons.mapPin,
    'home': LucideIcons.house,
    'briefcase': LucideIcons.briefcase,
    'school': LucideIcons.school,
    'shoppingBag': LucideIcons.shoppingBag,
    'coffee': LucideIcons.coffee,
    'utensils': LucideIcons.utensils,
    'dumbbell': LucideIcons.dumbbell,
    'heart': LucideIcons.heart,
    'star': LucideIcons.star,
    'music': LucideIcons.music,
    'plane': LucideIcons.plane,
    'train': LucideIcons.trainFront,
    'subway': LucideIcons.squareArrowDown,
    'tram': LucideIcons.tramFront,
    'ferry': LucideIcons.ship,
    'cableCar': LucideIcons.cableCar,
    'bus': LucideIcons.busFront,
    'coach': LucideIcons.bus,
    'stop': kUnknownStopIcon,
  };

  static AppIcon resolve(String name) =>
      _composed[name] ??
      _glyph(catalogueIcon(name)?.icon ?? _legacy[name]) ??
      fallback;

  /// Whether [name] resolves to something other than the fallback.
  static bool isKnown(String name) =>
      _composed.containsKey(name) ||
      catalogueIcon(name) != null ||
      _legacy.containsKey(name);

  static AppIcon? _glyph(IconData? data) =>
      data == null ? null : GlyphIcon(data);
}
