import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:transportia/models/itinerary.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/utils/color_utils.dart';
import 'package:transportia/utils/journey_colors.dart';

const Color _white = Color(0xFFFFFFFF);
const Color _dark = Color(0xFF161616);
const Color _accent = Color(0xFF007185);

Leg _leg({String mode = 'REGIONAL_RAIL', String? routeColor}) => Leg.fromJson({
  'mode': mode,
  'startTime': '2026-01-01T08:00:00Z',
  'endTime': '2026-01-01T09:00:00Z',
  'duration': 3600,
  if (routeColor != null) 'routeColor': routeColor,
  'from': {'name': 'A', 'lat': 0.0, 'lon': 0.0},
  'to': {'name': 'B', 'lat': 0.0, 'lon': 0.0},
});

void main() {
  group('ensureContrast', () {
    test('a colour that already reads is left alone', () {
      // Touching it would drift the operator's colour for no gain.
      const deepBlue = Color(0xFF1A3D8F);
      expect(ensureContrast(deepBlue, _white), deepBlue);
    });

    test('a pale colour is darkened until it reads on white', () {
      // Feeds ship these: a 2px line in pale yellow is not a line.
      const paleYellow = Color(0xFFF5E97A);
      final fixed = ensureContrast(paleYellow, _white);

      expect(contrastRatio(paleYellow, _white), lessThan(3.0));
      expect(contrastRatio(fixed, _white), greaterThanOrEqualTo(3.0));
    });

    test(
      'a near-black colour is lightened until it reads on the dark theme',
      () {
        const nearBlack = Color(0xFF1B1B22);
        final fixed = ensureContrast(nearBlack, _dark);

        expect(contrastRatio(nearBlack, _dark), lessThan(3.0));
        expect(contrastRatio(fixed, _dark), greaterThanOrEqualTo(3.0));
      },
    );

    test('the operator is still recognisable: only lightness moves', () {
      const paleYellow = Color(0xFFF5E97A);
      final fixed = ensureContrast(paleYellow, _white);

      final before = HSLColor.fromColor(paleYellow);
      final after = HSLColor.fromColor(fixed);
      expect(after.hue, closeTo(before.hue, 1.0));
      expect(after.saturation, closeTo(before.saturation, 0.05));
      expect(after.lightness, lessThan(before.lightness));
    });

    test('the same colour is fixed for whichever theme it fails against', () {
      // Mid grey fails on both, and has to move in opposite directions.
      const midGrey = Color(0xFF8A8A8A);
      expect(
        contrastRatio(ensureContrast(midGrey, _white), _white),
        greaterThanOrEqualTo(3.0),
      );
      expect(
        contrastRatio(ensureContrast(midGrey, _dark), _dark),
        greaterThanOrEqualTo(3.0),
      );
    });
  });

  group('legSpineColor', () {
    test('a street leg is neutral however the feed colours it', () {
      // A walk belongs to no line, so it borrows no line's colour.
      final color = legSpineColor(
        leg: _leg(mode: 'WALK', routeColor: '#FF0000'),
        background: _white,
        accent: _accent,
      );
      expect(color, kStreetLegColor);
    });

    test('a change between services is neutral too', () {
      final color = legSpineColor(
        leg: _leg(routeColor: '#FF0000'),
        background: _white,
        accent: _accent,
        isTransfer: true,
      );
      expect(color, kStreetLegColor);
    });

    test('a ride takes its route colour', () {
      final color = legSpineColor(
        leg: _leg(routeColor: '#1A3D8F'),
        background: _white,
        accent: _accent,
      );
      expect(color, const Color(0xFF1A3D8F));
    });

    test('a ride with an unreadable route colour still reads', () {
      final color = legSpineColor(
        leg: _leg(routeColor: '#F5E97A'),
        background: _white,
        accent: _accent,
      );
      expect(contrastRatio(color, _white), greaterThanOrEqualTo(3.0));
    });

    test('a ride the feed gave no colour falls back to the accent', () {
      // Not to the street neutral: grey now means "not a service".
      final color = legSpineColor(
        leg: _leg(),
        background: _white,
        accent: _accent,
      );
      expect(color, _accent);
    });
  });

  group('spineTimeColor', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
    });

    test('late and reported is red, on time and reported is green', () {
      const late = Duration(minutes: 3);
      expect(
        spineTimeColor(isLive: true, delay: late, isArrival: false),
        kLateDeparture,
      );
      expect(
        spineTimeColor(isLive: true, delay: null, isArrival: false),
        kOnTimeDeparture,
      );
      expect(
        spineTimeColor(isLive: true, delay: late, isArrival: true),
        kLateArrival,
      );
    });

    test(
      'a planned time follows the text colour into the dark theme',
      () async {
        // Fixed black here vanished on the dark background.
        TestWidgetsFlutterBinding.ensureInitialized();
        final provider = ThemeProvider();
        addTearDown(provider.dispose);
        while (!provider.isInitialized) {
          await Future<void>.delayed(Duration.zero);
        }
        await provider.setAppThemeMode(AppThemeMode.dark);

        final planned = spineTimeColor(
          isLive: false,
          delay: null,
          isArrival: false,
        );
        expect(
          planned.withValues(alpha: 1),
          provider.textColor.withValues(alpha: 1),
        );
        expect(
          contrastRatio(planned.withValues(alpha: 1), provider.backgroundColor),
          greaterThan(4.5),
        );
      },
    );
  });

  group('lineColor', () {
    test('is the feed colour, unadjusted', () {
      expect(lineColor('#0A1F5C'), const Color(0xFF0A1F5C));
      expect(lineColor(' #FFF59D '), const Color(0xFFFFF59D));
    });

    test('is null without a usable colour', () {
      expect(lineColor(null), isNull);
      expect(lineColor('nope'), isNull);
    });
  });

  group('onLineColor', () {
    test('keeps the feed text colour while it reads', () {
      expect(
        onLineColor(const Color(0xFF0057B8), '#FFFFFF'),
        const Color(0xFFFFFFFF),
      );
    });

    test('swaps white text for black once the fill went light', () {
      expect(
        onLineColor(const Color(0xFFF5E050), '#FFFFFF'),
        const Color(0xFF000000),
      );
    });

    test('keeps white on a mid orange, as operators pair them', () {
      expect(
        onLineColor(const Color(0xFFFF6A00), '#FFFFFF'),
        const Color(0xFFFFFFFF),
      );
    });

    test('picks the better of black and white without a feed colour', () {
      expect(
        onLineColor(const Color(0xFF101830), null),
        const Color(0xFFFFFFFF),
      );
    });
  });
}
