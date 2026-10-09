class PrefsKeys {
  const PrefsKeys._();

  /// App version that last wrote this storage. Absent on a 1.0.3 install and on
  /// a fresh one; `lib/migrations/` tells the two apart.
  static const String storageVersion = 'storage_version';

  static const String welcomeSeen = 'welcome_seen';

  static const String accentColor = 'accent_color';
  static const String mapStyle = 'map_style';
  static const String appTheme = 'app_theme';
  static const String vibrationsEnabled = 'vibrations_enabled';
  static const String searchMapEnabled = 'search_map_enabled';
  static const String searchOptionsOpening = 'search_options_opening';
  static const String showCalories = 'show_calories';

  /// Whether raw GTFS trip and stop ids are printed on trip and departure
  /// screens. Absent means off.
  static const String showGtfsFields = 'show_gtfs_fields';

  /// Whether the timetable search lists departures near the rider, which
  /// sends their position. Absent means on.
  static const String showNearbyDepartures = 'show_nearby_departures';

  static const String mapShowStops = 'map_show_stops';
  static const String mapQuickButton = 'map_quick_button';
  static const String mapShowVehicles = 'map_show_vehicles';
  static const String mapHideNonRtVehicles = 'map_hide_non_rt_vehicles';
  static const String mapAutoCenter = 'map_auto_center';
  static const String mapShowTrain = 'map_show_train';
  static const String mapShowMetro = 'map_show_metro';
  static const String mapShowTram = 'map_show_tram';
  static const String mapShowBus = 'map_show_bus';
  static const String mapShowFerry = 'map_show_ferry';
  static const String mapShowLift = 'map_show_lift';
  static const String mapShowOther = 'map_show_other';

  static const String lastGpsLat = 'last_gps_lat';
  static const String lastGpsLng = 'last_gps_lng';

  static const String favoritePlaces = 'favorite_places';
  static const String recentTrips = 'recent_trips';
  static const String savedTrips = 'saved_trips';
  static const String savedPlacesSearch = 'saved_places_search';
  static const String savedPlacesTimetable = 'saved_places_timetable';

  static const String transitousHost = 'transitous_host';
  static const String transitousApiVersion = 'transitous_api_version';

  /// Whether a tapped result's details are looked up on OpenStreetMap.
  /// Absent means on.
  static const String placeDetailsEnabled = 'place_details_enabled';

  /// The Nominatim server those details come from. Absent means the
  /// public one.
  static const String nominatimHost = 'nominatim_host';

  /// All routing preferences, JSON-encoded.
  static const String routingOptions = 'routing_options';

  /// How strongly place search leans towards the rider, as a number; 0 means
  /// their position is not sent. Absent means the default.
  static const String placeBias = 'place_bias';

  /// The rental provider groups the rider has an account with, and whether
  /// searches keep to them, JSON-encoded.
  static const String rentalProviders = 'rental_providers';

  /// How the search card groups the modes into sections, JSON-encoded.
  /// Absent means the default sections.
  static const String quickAccessLayout = 'quick_access_layout';

  /// The server's list of rental provider groups, with the host and time it
  /// was fetched, JSON-encoded. A cache; safe to delete.
  static const String rentalCatalogue = 'rental_catalogue';

  /// How 1.0.3 stored the same settings. Read once by the 1.0.3 migration, then
  /// removed; nothing else touches them.
  static const String transitWalkingSpeed = 'transit_walking_speed';
  static const String transitTransferBuffer = 'transit_transfer_buffer';
  static const String transitSelectedModes = 'transit_selected_modes';
}
