import 'dart:async';

import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:transportia/models/map_render_profile.dart';
import 'package:transportia/widgets/map/configured_map_platform.dart';

/// Runs before every test file: maps get the platform the app installs in
/// `main()`, which a map never created in a test can be disposed with.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  MapLibrePlatform.createInstance = () =>
      ConfiguredMapLibreChannel(MapRenderProfile.standard);
  await testMain();
}
