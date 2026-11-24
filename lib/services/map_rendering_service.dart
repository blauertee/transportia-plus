import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../models/map_render_profile.dart';
import '../widgets/map/configured_map_platform.dart';

/// How maps are drawn on this phone (`android/.../MapRendering.kt` is the
/// other end, and decides). Some older GPUs leave the map blank, or crash,
/// with maplibre_gl's defaults; the advanced settings can override the
/// choice.
class MapRenderingService extends ChangeNotifier {
  MapRenderingService._(this._channel);

  static final MapRenderingService instance = MapRenderingService._(
    const MethodChannel('transportia/map_rendering'),
  );

  final MethodChannel _channel;

  MapRenderState _state = MapRenderState.fallback;
  MapRenderState get state => _state;

  /// Lets drafts and tests show a phone other than the one they run on.
  @visibleForTesting
  set debugState(MapRenderState state) {
    _state = state;
    notifyListeners();
  }

  /// The running Dart version, without its build details; it changes with
  /// every Flutter release.
  static String get _dartVersion => Platform.version.split(' ').first;

  /// Whether this platform has a choice at all: only Android does.
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Reads the choice and puts it in place for every map built afterwards.
  /// From `main()`, before the first map.
  Future<void> load() async {
    if (!isSupported) return;
    try {
      final wire = await _channel.invokeMapMethod<Object?, Object?>('state');
      if (wire != null) _state = MapRenderState.fromWire(wire);
      // The renderer for this run is already chosen; the next start is
      // automatic again.
      if (_state.overrideOutdatedFor(_dartVersion)) await setOverride(null);
    } on PlatformException catch (e) {
      debugPrint('Map rendering: keeping the defaults ($e)');
    } on MissingPluginException {
      return;
    }
    // Read at each map's creation, so a change applies to the next map.
    MapLibrePlatform.createInstance = () =>
        ConfiguredMapLibreChannel(_state.effective);
  }

  /// Sets the profile by hand, or with null lets the app choose again.
  Future<void> setOverride(MapRenderProfile? override) async {
    _state = _state.withOverride(override, dartVersion: _dartVersion);
    notifyListeners();
    await _channel.invokeMethod<void>(
      'setOverride',
      override == null
          ? null
          : {...override.toWire(), 'dartVersion': _dartVersion},
    );
  }
}
