import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/transitous_endpoint.dart';
import '../providers/backend_provider.dart';
import 'rental_providers_service.dart';
import 'server_capabilities_service.dart';

/// Reloads what the app holds from the routing server when the rider points
/// it at another one, or asks for another API version.
///
/// Without this, answers from the old server outlive the switch: its limits
/// keep bounding the sliders and its vehicles stay on the map until a
/// restart. The Nominatim host is not watched; its answers are cached by
/// host already, and only fetched when a place is tapped.
class BackendReloadService {
  const BackendReloadService._();

  /// Bumped once per switch. Screens showing server data listen to it and
  /// fetch again.
  static final ValueNotifier<int> generation = ValueNotifier<int>(0);

  static BackendProvider? _watched;
  static String? _signature;

  /// Starts watching [backend], whose settings as they are now count as the
  /// server already in use. Only a change after this reloads.
  static void watch(BackendProvider backend) {
    _watched?.removeListener(_onBackendChanged);
    _watched = backend;
    _signature = signatureOf(backend);
    backend.addListener(_onBackendChanged);
  }

  /// Everything about the backend that changes what the server answers: the
  /// host, and the version each endpoint is asked on.
  @visibleForTesting
  static String signatureOf(BackendProvider backend) => [
    backend.host,
    for (final endpoint in TransitousEndpoint.values)
      backend.versionFor(endpoint),
  ].join('|');

  static void _onBackendChanged() {
    final backend = _watched;
    if (backend == null) return;
    final signature = signatureOf(backend);
    if (signature == _signature) return;
    _signature = signature;
    unawaited(ServerCapabilitiesService.refresh());
    RentalProvidersService.forgetServer();
    unawaited(RentalProvidersService.ensureCatalogue());
    generation.value++;
  }

  @visibleForTesting
  static void stopWatching() {
    _watched?.removeListener(_onBackendChanged);
    _watched = null;
    _signature = null;
  }
}
