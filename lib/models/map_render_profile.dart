/// Flutter's own renderer. Fixed for as long as the app runs.
enum FlutterRenderer { impeller, skia }

/// How the map's native view reaches the screen.
enum MapComposition {
  /// Copied into Flutter's picture as a texture.
  texture,

  /// Drawn by Android as a view of its own, with Flutter's layers around it.
  hybrid,
}

/// What MapLibre draws into.
enum MapSurface { textureView, surfaceView }

/// One way of drawing maps; `android/.../MapRendering.kt` holds the same
/// three choices under the same names.
class MapRenderProfile {
  const MapRenderProfile({
    required this.renderer,
    required this.composition,
    required this.surface,
  });

  /// What a phone with a working Vulkan driver gets, and every other
  /// platform: maplibre_gl's own defaults.
  static const MapRenderProfile standard = MapRenderProfile(
    renderer: FlutterRenderer.impeller,
    composition: MapComposition.texture,
    surface: MapSurface.textureView,
  );

  final FlutterRenderer renderer;
  final MapComposition composition;
  final MapSurface surface;

  /// The profile the platform side sent, or null when [wire] is not one.
  /// A name this build doesn't know falls back to [standard]'s choice.
  static MapRenderProfile? fromWire(Object? wire) {
    if (wire is! Map) return null;
    return MapRenderProfile(
      renderer:
          FlutterRenderer.values.asNameMap()[wire['renderer']] ??
          standard.renderer,
      composition:
          MapComposition.values.asNameMap()[wire['composition']] ??
          standard.composition,
      surface:
          MapSurface.values.asNameMap()[wire['surface']] ?? standard.surface,
    );
  }

  Map<String, String> toWire() => {
    'renderer': renderer.name,
    'composition': composition.name,
    'surface': surface.name,
  };

  MapRenderProfile copyWith({
    FlutterRenderer? renderer,
    MapComposition? composition,
    MapSurface? surface,
  }) => MapRenderProfile(
    renderer: renderer ?? this.renderer,
    composition: composition ?? this.composition,
    surface: surface ?? this.surface,
  );

  @override
  bool operator ==(Object other) =>
      other is MapRenderProfile &&
      other.renderer == renderer &&
      other.composition == composition &&
      other.surface == surface;

  @override
  int get hashCode => Object.hash(renderer, composition, surface);
}

/// What the app chose for this phone, what the rider set instead, and what
/// is running now.
class MapRenderState {
  const MapRenderState({
    required this.detected,
    required this.override,
    required this.rendererInUse,
  });

  /// Before the platform side has answered, and on platforms without one.
  static const MapRenderState fallback = MapRenderState(
    detected: MapRenderProfile.standard,
    override: null,
    rendererInUse: FlutterRenderer.impeller,
  );

  /// The app's own choice, from what the GPU offers.
  final MapRenderProfile detected;

  /// Set by hand in the advanced settings; null while the app chooses.
  final MapRenderProfile? override;

  /// The renderer the engine started with.
  final FlutterRenderer rendererInUse;

  static MapRenderState fromWire(Map<Object?, Object?> wire) => MapRenderState(
    detected: MapRenderProfile.fromWire(wire['detected']) ?? fallback.detected,
    override: MapRenderProfile.fromWire(wire['override']),
    rendererInUse:
        FlutterRenderer.values.asNameMap()[wire['rendererInUse']] ??
        fallback.rendererInUse,
  );

  bool get isAutomatic => override == null;

  /// Whether the app chose maplibre_gl's and Flutter's own defaults.
  bool get detectedStandard => detected == MapRenderProfile.standard;

  /// What maps opened from now on use; the renderer only from the next
  /// start, see [needsRestart].
  MapRenderProfile get effective => override ?? detected;

  /// Whether the chosen renderer differs from the one running.
  bool get needsRestart => effective.renderer != rendererInUse;

  MapRenderState withOverride(MapRenderProfile? override) => MapRenderState(
    detected: detected,
    override: override,
    rendererInUse: rendererInUse,
  );
}
