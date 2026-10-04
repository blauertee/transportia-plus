import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/utils/icon_catalogue.dart';

void main() {
  group('the catalogue', () {
    test('has one entry per name, in name order', () {
      final names = [for (final icon in iconCatalogue) icon.name];
      expect(names.toSet(), hasLength(names.length));
      expect(names, [...names]..sort());
    });

    test('lists every icon under a category it has', () {
      for (final icon in iconCatalogue) {
        expect(icon.categories, isNotEmpty, reason: icon.name);
      }
      final grouped = iconsByCategory();
      expect(
        grouped.values.fold<int>(0, (sum, list) => sum + list.length),
        iconCatalogue.length,
      );
    });

    test('offers what travel needs', () {
      for (final name in ['car', 'bike', 'train-front', 'house', 'key-round']) {
        expect(catalogueIcon(name), isNotNull, reason: name);
      }
    });

    test('knows nothing of a name it does not have', () {
      expect(catalogueIcon('no-such-icon'), isNull);
    });
  });

  group('search', () {
    test('puts the exact name first, then names that start with it', () {
      final results = [for (final icon in searchIcons('car')) icon.name];
      expect(results.first, 'car');
      expect(
        results.indexOf('car-front'),
        lessThan(results.indexOf('caravan')),
      );
    });

    test('finds icons by the words riders use', () {
      expect(searchIcons('lorry').map((i) => i.name), contains('truck'));
      expect(searchIcons('home').map((i) => i.name), contains('house'));
    });

    test('every word has to match', () {
      final results = searchIcons('train tunnel').map((i) => i.name);
      expect(results, contains('train-front-tunnel'));
      expect(results, isNot(contains('train-front')));
    });

    test('ignores case and extra spaces', () {
      expect(
        searchIcons('  CAR ').map((i) => i.name),
        searchIcons('car').map((i) => i.name),
      );
    });

    test('an empty query or no match gives nothing', () {
      expect(searchIcons(''), isEmpty);
      expect(searchIcons('   '), isEmpty);
      expect(searchIcons('qwxzv'), isEmpty);
    });
  });
}
