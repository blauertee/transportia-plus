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
/// Every name saved from now on has a namespace: `lucide:train-front` for a
/// catalogue icon, `transportia:car-key` for one the app composes.
/// Favourites saved before the catalogue used bare names of their own, and
/// one of them, `bus`, means a different glyph than Lucide's `bus`; the
/// namespace is what keeps those apart, so nothing stored needs rewriting.
abstract final class AppIcons {
  static const String _lucidePrefix = 'lucide:';
  static const String _ownPrefix = 'transportia:';

  /// The saved name of the Lucide icon called [name].
  static String lucide(String name) => '$_lucidePrefix$name';

  /// A shared car or moped.
  static const String carKeyName = '${_ownPrefix}car-key';
  static const AppIcon carKey = BadgedIcon(
    LucideIcons.car,
    LucideIcons.keyRound600,
  );

  /// What a name nothing knows resolves to.
  static const String fallbackName = '${_lucidePrefix}map-pin';
  static const AppIcon fallback = GlyphIcon(LucideIcons.mapPin);

  static const Map<String, AppIcon> _composed = {carKeyName: carKey};

  /// The names favourites were saved with before the catalogue, and the
  /// Lucide name each stands for.
  static const Map<String, String> _legacyNames = {
    'mapPin': 'map-pin',
    'home': 'house',
    'briefcase': 'briefcase',
    'school': 'school',
    'shoppingBag': 'shopping-bag',
    'coffee': 'coffee',
    'utensils': 'utensils',
    'dumbbell': 'dumbbell',
    'heart': 'heart',
    'star': 'star',
    'music': 'music',
    'plane': 'plane',
    'train': 'train-front',
    'subway': 'square-arrow-down',
    'tram': 'tram-front',
    'ferry': 'ship',
    'cableCar': 'cable-car',
    // Not Lucide's `bus`, which is the side view a coach is drawn with.
    'bus': 'bus-front',
    'coach': 'bus',
    'stop': 'signpost',
  };

  /// Glyphs a saved name can point to that the picker does not offer: what
  /// a hearted stop is drawn as, and what older favourites were saved with.
  static const Map<String, IconData> _unlisted = {
    'map-pin': LucideIcons.mapPin,
    'house': LucideIcons.house,
    'briefcase': LucideIcons.briefcase,
    'school': LucideIcons.school,
    'shopping-bag': LucideIcons.shoppingBag,
    'coffee': LucideIcons.coffee,
    'utensils': LucideIcons.utensils,
    'dumbbell': LucideIcons.dumbbell,
    'heart': LucideIcons.heart,
    'star': LucideIcons.star,
    'music': LucideIcons.music,
    'plane': LucideIcons.plane,
    'train-front': LucideIcons.trainFront,
    'square-arrow-down': LucideIcons.squareArrowDown,
    'tram-front': LucideIcons.tramFront,
    'ship': LucideIcons.ship,
    'cable-car': LucideIcons.cableCar,
    'bus-front': LucideIcons.busFront,
    'bus': LucideIcons.bus,
    'signpost': kUnknownStopIcon,
  };

  /// The name [name] is saved as from now on: an older favourite's bare
  /// name turns into its Lucide one; a namespaced name stays as it is.
  static String canonical(String name) {
    if (name.contains(':')) return name;
    final legacy = _legacyNames[name];
    return legacy == null ? name : lucide(legacy);
  }

  static AppIcon resolve(String name) => _lookUp(canonical(name)) ?? fallback;

  /// Whether [name] resolves to something other than the fallback.
  static bool isKnown(String name) => _lookUp(canonical(name)) != null;

  static AppIcon? _lookUp(String key) {
    if (key.startsWith(_lucidePrefix)) {
      final name = key.substring(_lucidePrefix.length);
      return _glyph(catalogueIcon(name)?.icon ?? _unlisted[name]);
    }
    return _composed[key];
  }

  static AppIcon? _glyph(IconData? data) =>
      data == null ? null : GlyphIcon(data);
}
