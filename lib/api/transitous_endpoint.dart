/// How an endpoint's `/api/<version>/` segment is chosen.
enum ApiVersionKind {
  /// Follows the user-configurable main API version (`BackendProvider.apiVersion`).
  ///
  /// These endpoints are versioned together upstream: MOTIS bumps them all in
  /// lockstep, so pinning them individually is only ever a debugging aid.
  main,

  /// Pinned to [TransitousEndpoint.fixedVersion] regardless of the main version.
  ///
  /// Some endpoints never left `v1`, and the experimental/debug families are
  /// not versioned at all.
  fixed,
}

/// Every endpoint the MOTIS API exposes, with the path and version segment
/// needed to build its URL.
///
/// [prefKey] doubles as the SharedPreferences suffix for a per-endpoint version
/// override, so the values for the six endpoints that existed before this enum
/// (`plan`, `trip`, `stoptimes`, `mapTrips`, `mapStops`, `geocode`) must not
/// change — users already have overrides stored under them.
enum TransitousEndpoint {
  plan(prefKey: 'plan', path: 'plan', label: 'Plan'),
  trip(prefKey: 'trip', path: 'trip', label: 'Trip'),
  refreshItinerary(
    prefKey: 'refreshItinerary',
    path: 'refresh-itinerary',
    label: 'Refresh itinerary',
  ),
  stopTimes(prefKey: 'stoptimes', path: 'stoptimes', label: 'Stop times'),
  stop(prefKey: 'stop', path: 'stop', label: 'Stop'),
  mapTrips(prefKey: 'mapTrips', path: 'map/trips', label: 'Map vehicles'),
  mapStops(prefKey: 'mapStops', path: 'map/stops', label: 'Map stops'),
  oneToAll(prefKey: 'oneToAll', path: 'one-to-all', label: 'One to all'),

  geocode(
    prefKey: 'geocode',
    path: 'geocode',
    label: 'Geocode',
    versionKind: ApiVersionKind.fixed,
    fixedVersion: 'v1',
  ),
  reverseGeocode(
    prefKey: 'reverseGeocode',
    path: 'reverse-geocode',
    label: 'Reverse geocode',
    versionKind: ApiVersionKind.fixed,
    fixedVersion: 'v1',
  ),
  oneToMany(
    prefKey: 'oneToMany',
    path: 'one-to-many',
    label: 'One to many',
    versionKind: ApiVersionKind.fixed,
    fixedVersion: 'v1',
  ),
  mapInitial(
    prefKey: 'mapInitial',
    path: 'map/initial',
    label: 'Map initial',
    versionKind: ApiVersionKind.fixed,
    fixedVersion: 'v1',
  ),
  mapLevels(
    prefKey: 'mapLevels',
    path: 'map/levels',
    label: 'Map levels',
    versionKind: ApiVersionKind.fixed,
    fixedVersion: 'v1',
  ),
  rentals(
    prefKey: 'rentals',
    path: 'rentals',
    label: 'Rentals',
    versionKind: ApiVersionKind.fixed,
    fixedVersion: 'v1',
  ),
  health(
    prefKey: 'health',
    path: 'health',
    label: 'Health',
    versionKind: ApiVersionKind.fixed,
    fixedVersion: 'v1',
  ),

  oneToManyIntermodal(
    prefKey: 'oneToManyIntermodal',
    path: 'one-to-many-intermodal',
    label: 'One to many (intermodal)',
    versionKind: ApiVersionKind.fixed,
    fixedVersion: 'experimental',
  ),
  mapRoutes(
    prefKey: 'mapRoutes',
    path: 'map/routes',
    label: 'Map routes',
    versionKind: ApiVersionKind.fixed,
    fixedVersion: 'experimental',
  ),
  mapRouteDetails(
    prefKey: 'mapRouteDetails',
    path: 'map/route-details',
    label: 'Map route details',
    versionKind: ApiVersionKind.fixed,
    fixedVersion: 'experimental',
  ),

  debugTransfers(
    prefKey: 'debugTransfers',
    path: 'transfers',
    label: 'Transfers (debug)',
    versionKind: ApiVersionKind.fixed,
    fixedVersion: 'debug',
  );

  const TransitousEndpoint({
    required this.prefKey,
    required this.path,
    required this.label,
    this.versionKind = ApiVersionKind.main,
    this.fixedVersion,
  }) : assert(
         versionKind == ApiVersionKind.main || fixedVersion != null,
         'a fixed-version endpoint must declare its version',
       );

  /// Stable key for the per-endpoint version override in SharedPreferences.
  final String prefKey;

  /// Path below `/api/<version>/`, without a leading slash.
  final String path;

  /// Human-readable name for the backend settings UI.
  final String label;

  final ApiVersionKind versionKind;

  /// Version segment for [ApiVersionKind.fixed] endpoints; null otherwise.
  final String? fixedVersion;

  /// Version this endpoint uses when no override is set, given the resolved
  /// main API version.
  String defaultVersion(String mainApiVersion) =>
      versionKind == ApiVersionKind.main ? mainApiVersion : fixedVersion!;

  /// Full request path, e.g. `/api/v6/map/trips`.
  String requestPath(String version) => '/api/$version/$path';
}
