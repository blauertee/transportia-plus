import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/map_render_profile.dart';
import 'package:transportia/widgets/map/configured_map_platform.dart';

const String _kViewType = 'plugins.flutter.io/maplibre_gl';

void main() {
  group('ConfiguredMapLibreChannel.buildView', () {
    /// The view [profile] builds, and the creation parameters it hands on.
    (Widget, Map<String, dynamic>) build(MapRenderProfile profile) {
      final params = <String, dynamic>{'options': <String, dynamic>{}};
      final view = ConfiguredMapLibreChannel(
        profile,
      ).buildView(params, (_) {}, null);
      return (view, params);
    }

    bool? drawsToTextureView(Map<String, dynamic> params) =>
        params['options']['useHybridComposition'] as bool?;

    setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('hybrid composition builds a platform view link', () {
      final (view, params) = build(
        MapRenderProfile.standard.copyWith(
          composition: MapComposition.hybridComposition,
          surface: MapSurface.textureView,
        ),
      );
      expect((view as PlatformViewLink).viewType, _kViewType);
      expect(drawsToTextureView(params), isTrue);
    });

    test('hybrid composition keeps a SurfaceView when asked to', () {
      final (view, params) = build(
        MapRenderProfile.standard.copyWith(
          composition: MapComposition.hybridComposition,
        ),
      );
      expect(view, isA<PlatformViewLink>());
      expect(drawsToTextureView(params), isFalse);
    });

    test('a TextureView drawn into Flutter\'s frame is an AndroidView', () {
      final (view, params) = build(
        MapRenderProfile.standard.copyWith(surface: MapSurface.textureView),
      );
      expect((view as AndroidView).viewType, _kViewType);
      expect(drawsToTextureView(params), isTrue);
    });

    test('the standard profile is the plugin\'s own view', () {
      final (view, params) = build(MapRenderProfile.standard);
      expect((view as AndroidView).viewType, _kViewType);
      expect(drawsToTextureView(params), isFalse);
    });
  });

  test('a map left before its view exists disposes cleanly', () {
    final platform = ConfiguredMapLibreChannel(MapRenderProfile.standard);
    expect(platform.dispose, returnsNormally);
  });
}
