import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

part 'icon_catalogue.g.dart';

/// The groups the icon picker lists icons under, in its order.
///
/// Lucide's own categories, narrowed to the ones that fit places and ways of
/// travelling; `tool/generate_icon_catalogue.dart` keeps the same list.
enum IconCategory {
  transportation('Transport'),
  travel('Travel'),
  maps('Maps'),
  navigation('Navigation'),
  buildings('Buildings'),
  home('Home'),
  foodBeverage('Food & drink'),
  shopping('Shopping'),
  sports('Sports'),
  nature('Nature'),
  animals('Animals'),
  weather('Weather'),
  seasons('Seasons'),
  people('People'),
  emoji('Emoji'),
  medical('Health');

  const IconCategory(this.label);

  final String label;
}

/// One icon the picker offers: Lucide's name for it, the glyph, and what it
/// can be found by.
class CatalogueIcon {
  const CatalogueIcon(this.name, this.icon, this.categories, this.words);

  /// Lucide's own name, such as `train-front`; what a picked icon is saved
  /// as.
  final String name;
  final IconData icon;

  /// The first is the one it is listed under.
  final List<IconCategory> categories;

  /// Lucide's tags, plus a few words riders type that Lucide lacks.
  final List<String> words;
}

/// Every icon the picker offers, alphabetically by name.
const List<CatalogueIcon> iconCatalogue = _generatedIcons;

final Map<String, CatalogueIcon> _byName = {
  for (final icon in iconCatalogue) icon.name: icon,
};

/// The catalogue entry called [name], if there is one.
CatalogueIcon? catalogueIcon(String name) => _byName[name];

/// The icons listed under each category, in category order. An icon is
/// listed once, under its first category.
Map<IconCategory, List<CatalogueIcon>> iconsByCategory() {
  final grouped = {
    for (final category in IconCategory.values) category: <CatalogueIcon>[],
  };
  for (final icon in iconCatalogue) {
    grouped[icon.categories.first]!.add(icon);
  }
  return grouped;
}

/// How well an icon matches a single search word; lower is better.
enum _Match { exactName, namePrefix, nameWord, word, wordPart }

/// The icons matching every word of [query], best first.
///
/// A match on the name beats one on a tag, and the start of a word beats its
/// middle, so "car" puts `car` ahead of `caravan`, and both ahead of icons
/// merely tagged "vehicle".
List<CatalogueIcon> searchIcons(String query) {
  final terms = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((t) => t.isEmpty);
  if (terms.isEmpty) return const [];

  final scored = <(CatalogueIcon, int)>[];
  for (final icon in iconCatalogue) {
    var total = 0;
    var matchesAll = true;
    for (final term in terms) {
      final match = _bestMatch(icon, term);
      if (match == null) {
        matchesAll = false;
        break;
      }
      total += match.index;
    }
    if (matchesAll) scored.add((icon, total));
  }
  scored.sort((a, b) {
    final byScore = a.$2.compareTo(b.$2);
    return byScore != 0 ? byScore : a.$1.name.compareTo(b.$1.name);
  });
  return [for (final (icon, _) in scored) icon];
}

_Match? _bestMatch(CatalogueIcon icon, String term) {
  if (icon.name == term) return _Match.exactName;
  if (icon.name.startsWith(term)) return _Match.namePrefix;
  if (icon.name.split('-').any((w) => w.startsWith(term))) {
    return _Match.nameWord;
  }
  if (icon.words.any(
    (w) => w.split(RegExp(r'[\s-]')).any((part) => part.startsWith(term)),
  )) {
    return _Match.word;
  }
  if (icon.words.any((w) => w.contains(term))) return _Match.wordPart;
  return null;
}
