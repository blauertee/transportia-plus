import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:transportia/utils/app_icons.dart';
import 'package:transportia/utils/place_icons.dart';

void main() {
  test('a catalogue name is its glyph', () {
    expect(
      AppIcons.resolve('train-front'),
      const GlyphIcon(LucideIcons.trainFront),
    );
    expect(AppIcons.isKnown('train-front'), isTrue);
  });

  test('names favourites were saved with before still resolve', () {
    // Literal names, as released builds wrote them.
    expect(AppIcons.resolve('home'), const GlyphIcon(LucideIcons.house));
    expect(AppIcons.resolve('mapPin'), const GlyphIcon(LucideIcons.mapPin));
    expect(
      AppIcons.resolve('subway'),
      const GlyphIcon(LucideIcons.squareArrowDown),
    );
    expect(AppIcons.resolve('stop'), const GlyphIcon(kUnknownStopIcon));
  });

  test('the car and key is composed, under a name Lucide cannot take', () {
    expect(AppIcons.resolve(AppIcons.carKeyName), AppIcons.carKey);
    expect(AppIcons.carKeyName, contains(':'));
    expect(AppIcons.carKey, isA<BadgedIcon>());
  });

  test('an unknown or empty name falls back to the map pin', () {
    expect(AppIcons.resolve('no-such-icon'), AppIcons.fallback);
    expect(AppIcons.resolve(''), AppIcons.fallback);
    expect(AppIcons.isKnown('no-such-icon'), isFalse);
    expect(AppIcons.resolve(AppIcons.fallbackName), AppIcons.fallback);
  });
}
