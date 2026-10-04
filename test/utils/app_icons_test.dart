import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:transportia/utils/app_icons.dart';
import 'package:transportia/utils/place_icons.dart';

void main() {
  test('a catalogue name is its glyph', () {
    expect(
      AppIcons.resolve('lucide:train-front'),
      const GlyphIcon(LucideIcons.trainFront),
    );
    expect(AppIcons.lucide('train-front'), 'lucide:train-front');
    expect(AppIcons.isKnown('lucide:train-front'), isTrue);
  });

  test('names favourites were saved with before still resolve', () {
    // Literal names, as released builds wrote them.
    expect(AppIcons.resolve('home'), const GlyphIcon(LucideIcons.house));
    expect(AppIcons.resolve('mapPin'), const GlyphIcon(LucideIcons.mapPin));
    expect(
      AppIcons.resolve('briefcase'),
      const GlyphIcon(LucideIcons.briefcase),
    );
    expect(
      AppIcons.resolve('subway'),
      const GlyphIcon(LucideIcons.squareArrowDown),
    );
    expect(AppIcons.resolve('stop'), const GlyphIcon(kUnknownStopIcon));
  });

  test('an old "bus" keeps its meaning, apart from Lucide\'s "bus"', () {
    expect(AppIcons.resolve('bus'), const GlyphIcon(LucideIcons.busFront));
    expect(AppIcons.resolve('coach'), const GlyphIcon(LucideIcons.bus));
    expect(AppIcons.resolve('lucide:bus'), const GlyphIcon(LucideIcons.bus));
  });

  test('old names turn into the namespaced ones on the next save', () {
    expect(AppIcons.canonical('home'), 'lucide:house');
    expect(AppIcons.canonical('bus'), 'lucide:bus-front');
    expect(AppIcons.canonical('lucide:bus'), 'lucide:bus');
    expect(AppIcons.canonical(AppIcons.carKeyName), AppIcons.carKeyName);
  });

  test('the car and key is composed, in a namespace of its own', () {
    expect(AppIcons.resolve(AppIcons.carKeyName), AppIcons.carKey);
    expect(AppIcons.carKeyName, startsWith('transportia:'));
    expect(AppIcons.carKey, isA<BadgedIcon>());
  });

  test('an unknown or empty name falls back to the map pin', () {
    expect(AppIcons.resolve('no-such-icon'), AppIcons.fallback);
    expect(AppIcons.resolve('lucide:no-such-icon'), AppIcons.fallback);
    expect(AppIcons.resolve('transportia:nothing'), AppIcons.fallback);
    expect(AppIcons.resolve(''), AppIcons.fallback);
    expect(AppIcons.isKnown('no-such-icon'), isFalse);
    expect(AppIcons.resolve(AppIcons.fallbackName), AppIcons.fallback);
  });
}
