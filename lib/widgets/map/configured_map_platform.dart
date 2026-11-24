import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../models/map_render_profile.dart';

/// maplibre_gl's own map view type.
const String _kPluginViewType = 'plugins.flutter.io/maplibre_gl';

/// `SurfaceViewMapFactory.kt`: the same map, drawn into a SurfaceView.
const String _kSurfaceViewType = 'transportia/maplibre_surface_view';

/// maplibre_gl's Android platform, with the map's view built as [profile]
/// says. The standard profile is left entirely to the plugin.
///
/// The plugin's own `useHybridComposition` switch is not used: it still
/// creates the view through `initAndroidView`, which is texture based.
class ConfiguredMapLibreChannel extends MapLibreMethodChannel {
  ConfiguredMapLibreChannel(this.profile);

  final MapRenderProfile profile;

  @override
  Widget buildView(
    Map<String, dynamic> creationParams,
    OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) {
    final usesPluginView =
        profile.composition == MapComposition.texture &&
        profile.surface == MapSurface.textureView;
    if (usesPluginView || defaultTargetPlatform != TargetPlatform.android) {
      return super.buildView(
        creationParams,
        onPlatformViewCreated,
        gestureRecognizers,
      );
    }

    final viewType = profile.surface == MapSurface.surfaceView
        ? _kSurfaceViewType
        : _kPluginViewType;
    if (profile.composition == MapComposition.texture) {
      return AndroidView(
        viewType: viewType,
        onPlatformViewCreated: onPlatformViewCreated,
        gestureRecognizers: gestureRecognizers,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return _hybridView(
      viewType,
      creationParams,
      onPlatformViewCreated,
      gestureRecognizers,
    );
  }

  Widget _hybridView(
    String viewType,
    Map<String, dynamic> creationParams,
    OnPlatformViewCreatedCallback onPlatformViewCreated,
    Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers,
  ) {
    return PlatformViewLink(
      viewType: viewType,
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
                viewType: viewType,
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
