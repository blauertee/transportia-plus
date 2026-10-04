import 'package:flutter/widgets.dart';

import '../models/transitous/enums.dart';
import 'app_icons.dart';
import 'place_icons.dart';

/// The icons the favourite editor offers first; the picker behind it has
/// the rest.
const List<String> favoriteIconSuggestions = [
  'lucide:map-pin',
  'lucide:house',
  'lucide:briefcase',
  'lucide:school',
  'lucide:shopping-bag',
  'lucide:coffee',
  'lucide:utensils',
  'lucide:dumbbell',
  'lucide:heart',
  'lucide:star',
  'lucide:music',
  'lucide:plane',
];

/// The glyph a favourite is drawn with. Favourites only ever pick single
/// glyphs, but a composed icon would still give its main one.
IconData iconForFavorite(String iconName) =>
    switch (AppIcons.resolve(iconName)) {
      GlyphIcon(:final data) => data,
      BadgedIcon(:final base) => base,
    };

/// The icon a stop is kept with: the one the lists draw it with, from what
/// serves it.
String favoriteIconNameForStop(Iterable<TransitMode> modes) =>
    switch (headlineMode(modes)) {
      TransitMode.airplane => 'lucide:plane',
      TransitMode.rail => 'lucide:train-front',
      TransitMode.subway => 'lucide:square-arrow-down',
      TransitMode.tram => 'lucide:tram-front',
      TransitMode.ferry => 'lucide:ship',
      TransitMode.aerialLift => 'lucide:cable-car',
      TransitMode.bus => 'lucide:bus-front',
      TransitMode.coach => 'lucide:bus',
      _ => 'lucide:signpost',
    };
