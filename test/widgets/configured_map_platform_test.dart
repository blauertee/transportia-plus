import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/map_render_profile.dart';
import 'package:transportia/widgets/map/configured_map_platform.dart';

/// Every part away from the standard profile.
const MapRenderProfile _compatible = MapRenderProfile(
  renderer: FlutterRenderer.skia,
  composition: MapComposition.hybrid,
  surface: MapSurface.surfaceView,
);

void main() {
  group('ConfiguredMapLibreChannel.buildView', () {
    Widget build(MapRenderProfile profile) =>
        ConfiguredMapLibreChannel(profile).buildView({}, (_) {}, null);

    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test('hybrid composition builds a platform view link', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final view = build(_compatible);
      expect(view, isA<PlatformViewLink>());
      expect(
        (view as PlatformViewLink).viewType,
        'transportia/maplibre_surface_view',
      );
    });

    test('a SurfaceView behind a texture uses the app\'s map factory', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final view = build(
        _compatible.copyWith(composition: MapComposition.texture),
      );
      expect(view, isA<AndroidView>());
      expect(
        (view as AndroidView).viewType,
        'transportia/maplibre_surface_view',
      );
    });

    test('hybrid composition with a TextureView uses the plugin\'s map', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final view = build(_compatible.copyWith(surface: MapSurface.textureView));
      expect(
        (view as PlatformViewLink).viewType,
        'plugins.flutter.io/maplibre_gl',
      );
    });

    test('the standard profile is the plugin\'s own view', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final view = build(MapRenderProfile.standard);
      expect(view, isA<AndroidView>());
      expect((view as AndroidView).viewType, 'plugins.flutter.io/maplibre_gl');
    });
  });
}
