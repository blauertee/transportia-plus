import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../models/map_render_profile.dart';

/// maplibre_gl's map view type.
const String _kViewType = 'plugins.flutter.io/maplibre_gl';

/// maplibre_gl's Android platform, with the map's view built as [profile]
/// says. The standard profile is left entirely to the plugin.
///
/// The plugin's own `useHybridComposition` switch ties two things together:
/// it draws into a TextureView, and it composes through `initAndroidView`,
/// which is texture based too. Here the two are set apart, and hybrid
/// composition is the real one (`initExpensiveAndroidView`).
class ConfiguredMapLibreChannel extends MapLibreMethodChannel {
  ConfiguredMapLibreChannel(this.profile);

  final MapRenderProfile profile;

  /// Whether the map's native view exists and its channel is set up.
  bool _isCreated = false;

  @override
  Future<void> initPlatform(int id) {
    _isCreated = true;
    return super.initPlatform(id);
  }

  /// maplibre_gl 0.27 also disposes the platform of a map whose native view
  /// was never created, such as one left before it loaded, and its channel
  /// is unset until then; there is nothing on the channel to let go of yet.
  @override
  void dispose() {
    if (_isCreated) super.dispose();
  }

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) {
    final usesPluginView =
        profile.composition == MapComposition.flutter &&
        profile.surface == MapSurface.surfaceView;
    if (usesPluginView || defaultTargetPlatform != TargetPlatform.android) {
      return super.buildView(
        creationParams,
        onPlatformViewCreated,
        gestureRecognizers,
      );
    }

    // The plugin's native side reads this option as "draw into a
    // TextureView", whatever the name says.
    creationParams['options']?['useHybridComposition'] =
        profile.surface == MapSurface.textureView;
    if (profile.composition == MapComposition.flutter) {
      return AndroidView(
        viewType: _kViewType,
        onPlatformViewCreated: onPlatformViewCreated,
        gestureRecognizers: gestureRecognizers,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return _hybridView(
      creationParams,
      onPlatformViewCreated,
      gestureRecognizers,
    );
  }

  Widget _hybridView(
    Map<String, dynamic> creationParams,
    OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) {
    return PlatformViewLink(
      viewType: _kViewType,
      surfaceFactory: (context, controller) => AndroidViewSurface(
        controller: controller as AndroidViewController,
        gestureRecognizers:
            gestureRecognizers ??
            const <Factory<OneSequenceGestureRecognizer>>{},
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      ),
      onCreatePlatformView: (params) {
        final controller =
            PlatformViewsService.initExpensiveAndroidView(
                id: params.id,
                viewType: _kViewType,
                layoutDirection: TextDirection.ltr,
                creationParams: creationParams,
                creationParamsCodec: const StandardMessageCodec(),
                onFocus: () => params.onFocusChanged(true),
              )
              ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
              ..addOnPlatformViewCreatedListener(onPlatformViewCreated);
        unawaited(controller.create());
        return controller;
      },
    );
  }
}
