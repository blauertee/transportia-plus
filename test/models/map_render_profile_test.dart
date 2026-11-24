import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/map_render_profile.dart';

const MapRenderProfile _compatible = MapRenderProfile(
  renderer: FlutterRenderer.skia,
  composition: MapComposition.hybridComposition,
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
        'composition': 'hybridComposition',
      });
      expect(
        profile,
        MapRenderProfile.standard.copyWith(
          composition: MapComposition.hybridComposition,
        ),
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
        MapRenderProfile.standard.copyWith(
          composition: MapComposition.hybridComposition,
        ),
        dartVersion: '3.10.0',
      );
      expect(otherComposition.needsRestart, isFalse);
      expect(
        running.withOverride(_compatible, dartVersion: '3.10.0').needsRestart,
        isTrue,
      );
      expect(
        running.withOverride(null, dartVersion: '3.10.0').needsRestart,
        isFalse,
      );
    });

    test('an override is outdated once the Flutter release changes', () {
      final state = stateFrom({
        'detected': MapRenderProfile.standard.toWire(),
        'override': _compatible.toWire(),
        'rendererInUse': 'skia',
        'overrideDartVersion': '3.10.0',
      });
      expect(state.overrideOutdatedFor('3.10.0'), isFalse);
      expect(state.overrideOutdatedFor('3.11.0'), isTrue);
    });

    test('an override without a version is outdated', () {
      final state = stateFrom({
        'detected': MapRenderProfile.standard.toWire(),
        'override': _compatible.toWire(),
        'rendererInUse': 'skia',
      });
      expect(state.overrideOutdatedFor('3.10.0'), isTrue);
    });

    test('automatic is never outdated', () {
      final state = stateFrom({
        'detected': _compatible.toWire(),
        'rendererInUse': 'impeller',
        'overrideDartVersion': '3.9.0',
      });
      expect(state.overrideOutdatedFor('3.10.0'), isFalse);
    });

    test('setting an override records the version, clearing forgets it', () {
      final running = stateFrom({
        'detected': MapRenderProfile.standard.toWire(),
        'rendererInUse': 'impeller',
      });
      final manual = running.withOverride(_compatible, dartVersion: '3.10.0');
      expect(manual.overrideDartVersion, '3.10.0');
      expect(manual.overrideOutdatedFor('3.10.0'), isFalse);
      final automatic = manual.withOverride(null, dartVersion: '3.10.0');
      expect(automatic.overrideDartVersion, isNull);
    });

    test('an empty answer is the standard phone', () {
      final state = stateFrom({});
      expect(state.effective, MapRenderProfile.standard);
      expect(state.rendererInUse, FlutterRenderer.impeller);
      expect(state.detectedStandard, isTrue);
    });
  });

  group('maps off', () {
    test('reads the switch the platform side sends', () {
      expect(MapRenderState.fromWire({'mapsOff': true}).mapsOff, isTrue);
      expect(MapRenderState.fromWire({}).mapsOff, isFalse);
    });

    test('survives a change of profile, and a profile survives it', () {
      final off = MapRenderState.fromWire({
        'detected': _compatible.toWire(),
        'rendererInUse': 'impeller',
      }).withMapsOff(true);
      final manual = off.withOverride(
        MapRenderProfile.standard,
        dartVersion: '3.10.0',
      );
      expect(manual.mapsOff, isTrue);
      expect(manual.withMapsOff(false).override, MapRenderProfile.standard);
    });
  });
}
