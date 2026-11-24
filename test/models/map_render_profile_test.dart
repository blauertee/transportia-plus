import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/map_render_profile.dart';

const MapRenderProfile _compatible = MapRenderProfile(
  renderer: FlutterRenderer.skia,
  composition: MapComposition.hybrid,
  surface: MapSurface.surfaceView,
);

void main() {
  group('MapRenderProfile.fromWire', () {
    test('reads the names the platform side sends', () {
      expect(MapRenderProfile.fromWire(_compatible.toWire()), _compatible);
    });

    test('is null for anything but a map', () {
      expect(MapRenderProfile.fromWire(null), isNull);
      expect(MapRenderProfile.fromWire('skia'), isNull);
    });

    test('falls back to the standard choice for unknown names', () {
      final profile = MapRenderProfile.fromWire({
        'renderer': 'vulkan',
        'composition': 'hybrid',
      });
      expect(
        profile,
        MapRenderProfile.standard.copyWith(composition: MapComposition.hybrid),
      );
    });
  });

  group('MapRenderState', () {
    MapRenderState stateFrom(Map<Object?, Object?> wire) =>
        MapRenderState.fromWire(wire);

    test('uses the detected profile while automatic', () {
      final state = stateFrom({
        'detected': _compatible.toWire(),
        'override': null,
        'rendererInUse': 'skia',
      });
      expect(state.isAutomatic, isTrue);
      expect(state.effective, _compatible);
      expect(state.detectedStandard, isFalse);
      expect(state.needsRestart, isFalse);
    });

    test('an override wins over the detected profile', () {
      final state = stateFrom({
        'detected': _compatible.toWire(),
        'override': MapRenderProfile.standard.toWire(),
        'rendererInUse': 'skia',
      });
      expect(state.isAutomatic, isFalse);
      expect(state.effective, MapRenderProfile.standard);
    });

    test('needs a restart only when the renderer differs', () {
      final running = stateFrom({
        'detected': MapRenderProfile.standard.toWire(),
        'rendererInUse': 'impeller',
      });
      final otherComposition = running.withOverride(
        MapRenderProfile.standard.copyWith(composition: MapComposition.hybrid),
      );
      expect(otherComposition.needsRestart, isFalse);
      expect(running.withOverride(_compatible).needsRestart, isTrue);
      expect(running.withOverride(null).needsRestart, isFalse);
    });

    test('an empty answer is the standard phone', () {
      final state = stateFrom({});
      expect(state.effective, MapRenderProfile.standard);
      expect(state.rendererInUse, FlutterRenderer.impeller);
      expect(state.detectedStandard, isTrue);
    });
  });
}
