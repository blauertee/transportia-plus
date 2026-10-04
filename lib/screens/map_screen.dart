import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:transportia/widgets/time_selection_overlay.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../animations/curves.dart';
import '../constants/prefs_keys.dart';
import '../providers/theme_provider.dart';
import '../models/route_field_kind.dart';
import '../models/routing_options.dart';
import '../models/transitous/server_config.dart';
import '../models/itinerary.dart';
import '../models/my_location.dart';
import '../models/saved_place.dart';
import '../models/stop_time.dart';
import '../models/time_selection.dart';
import '../models/saved_trip.dart';
import '../screens/itinerary_detail_screen.dart';
import '../screens/itinerary_list_screen.dart';
import '../screens/location_settings_screen.dart';
import '../screens/timetables_screen.dart';
import '../screens/location_search_screen.dart';
import '../screens/via_stops_screen.dart';
import '../services/location_service.dart';
import '../services/plan_request.dart';
import '../services/recent_trips_service.dart';
import '../services/backend_reload_service.dart';
import '../services/quick_access_service.dart';
import '../services/rental_providers_service.dart';
import '../services/routing_options_service.dart';
import '../services/saved_places_service.dart';
import '../services/server_capabilities_service.dart';
import '../services/stop_times_service.dart';
import '../services/transitous_map_service.dart';
import '../services/transitous_geocode_service.dart';
import '../services/trip_details_service.dart';
import '../theme/app_colors.dart';
import '../theme/system_bars.dart';
import '../utils/color_utils.dart';
import '../utils/geo_utils.dart';
import '../utils/map_framing.dart';
import '../utils/haptics.dart';
import '../utils/custom_page_route.dart';
import '../utils/leg_helper.dart';
import '../utils/map_marker_utils.dart';
import '../utils/polyline_utils.dart';
import '../utils/stop_time_utils.dart';
import '../widgets/custom_card.dart';
import '../widgets/error_notice.dart';
import '../widgets/app_toggle_switch.dart';
import '../widgets/pressable_highlight.dart';
import '../widgets/quick_button_picker_sheet.dart';
import '../widgets/route_bottom_card.dart';
import '../widgets/validation_toast.dart';
import '../widgets/buttons/pill_button.dart';
import '../widgets/selectable_icon_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeletons/skeleton_card.dart';
import '../widgets/skeletons/skeleton_shimmer.dart';
import '../widgets/last_updated_footer.dart';
import '../widgets/stop_departures_sheet.dart';
import '../widgets/journey/trip_details_view.dart';
import '../widgets/journey/trip_timeline.dart' show StopTapCallback;
import '../widgets/map/bottom_sheet_chrome.dart';
import '../widgets/map/long_press_selection_modal.dart';
import '../widgets/map/stop_selection_modal.dart';
import '../theme/app_text.dart';

part 'map_screen/map_screen_models.dart';
part 'map_screen/map_screen_controls.dart';
part 'map_screen/map_screen_trip_focus.dart';
part 'map_screen/map_screen_quick_settings.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.deferInit = false,
    this.activateOnShow,
    this.onCollapseChanged,
    this.onCollapseProgressChanged,
    this.onOverlayVisibilityChanged,
    this.onTabChangeRequested,
    this.onTimetableRequested,
  });

  final bool deferInit;
  final ValueListenable<bool>? activateOnShow;
  final ValueChanged<bool>? onCollapseChanged;
  final ValueChanged<double>? onCollapseProgressChanged;
  final ValueChanged<bool>? onOverlayVisibilityChanged;
  final ValueChanged<int>? onTabChangeRequested;
  final ValueChanged<TransitousLocationSuggestion>? onTimetableRequested;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  static const CameraPosition _initCam = CameraPosition(
    target: LatLng(kFallbackMapLat, kFallbackMapLon),
    zoom: kFallbackMapZoom,
    tilt: 0.0,
    bearing: 0.0,
  );

  MapLibreMapController? _controller;
  bool _hasLocationPermission = false;
  CameraPosition _startCam = _initCam;
  CameraPosition _lastCam = _initCam;
  StreamSubscription<Position>? _posSub;
  LatLng? _lastUserLatLng;
  bool _didAutoCenter = false;
  bool _isSheetCollapsed = false;
  double? _sheetTop;
  static const double _collapsedMapFraction = 0.25;
  static const double _bottomBarHeight = 116.0;
  static const double _tripFocusBottomBarHeight = 200.0;
  static const List<String> _mapStyleCycle = ['default', 'light', 'dark'];
  final _fromCtrl = TextEditingController();
  final _toCtrl = TextEditingController();
  late final AnimationController _snapCtrl;
  Animation<double>? _snapAnim;
  double? _snapTarget;
  bool _hasVibrator = false;
  bool _hasCustomVibration = false;
  Timer? _dragVibeTimer;
  Timer? _dragVibeDeadline;
  bool _didInitLocation = false;
  VoidCallback? _activateListener;
  TransitousLocationSuggestion? _fromSelection;
  TransitousLocationSuggestion? _toSelection;
  List<SavedPlace> _savedSearchPlaces = [];
  bool _suppressFromListener = false;
  bool _suppressToListener = false;
  final LayerLink _routeFieldLink = LayerLink();
  final LayerLink _timeSelectionLayerLink = LayerLink();
  Symbol? _fromSymbol;
  Symbol? _toSymbol;
  int _markerRefreshToken = 0;
  bool _didAddMarkerImages = false;
  LatLng? _longPressLatLng;
  final Map<RouteFieldKind, String> _pendingReverseGeocodeKeys = {};
  final Set<RouteFieldKind> _reverseGeocodeLoading = <RouteFieldKind>{};
  bool _showTimeSelectionOverlay = false;
  bool _isLongPressClosing = false;
  bool _suppressTimeSelectionReopen = false;
  TimeSelection _timeSelection = TimeSelection.now();

  /// Options for the next search only. Seeded from the stored defaults and
  /// never written back unless the user asks for it: whether you have a bike
  /// today should not rewrite what every future search does.
  RoutingOptions _options = RoutingOptions.defaults;
  RoutingOptions _storedOptions = RoutingOptions.defaults;
  bool _optionsTouched = false;
  ServerConfig _capabilities = ServerCapabilitiesService.capabilities.value;
  List<SavedTrip> _recentTrips = [];
  bool _isSearching = false;
  bool _isMapReady = false;

  /// Whether the map is built at all. Starts false: see
  /// [ThemeProvider.showsSearchMap] for why it waits for the setting.
  bool _showsMap = false;
  Timer? _tripRefreshTimer;
  Timer? _tripRefreshDebounce;
  Timer? _stopRefreshDebounce;
  Timer? _vehicleAnimationTimer;
  int _tripRequestId = 0;
  int _stopRequestId = 0;
  int _stopTimesRequestId = 0;
  final Map<String, _VehicleMarker> _vehicles = {};
  final Map<String, MapStop> _visibleStops = {};
  final Set<String> _vehicleMarkerImages = {};
  bool _showStops = true;
  final Set<String> _stopMarkerImages = {};
  String? _stopMarkerImageId;
  Color? _stopAccentColor;
  bool _didAddStopsLayer = false;
  bool _didAddVehiclesLayer = false;
  bool _didAddFocusedVehiclesLayer = false;
  bool _didAddFocusedStopsLayer = false;
  bool _didAddFocusedRouteLayer = false;
  Future<void>? _vehicleLayerInit;
  Future<void>? _stopsLayerInit;
  Future<void>? _focusedVehiclesLayerInit;
  Future<void>? _focusedStopsLayerInit;
  Future<void>? _focusedRouteLayerInit;
  Color? _focusedStopsColor;
  bool _isTripFocus = false;
  bool _isQuickSettings = false;
  bool _isTripFocusLoading = false;
  String? _tripFocusError;
  String? _focusedTripId;
  Itinerary? _focusedItinerary;
  DateTime? _tripFocusLastUpdated;
  bool _showStopsBeforeFocus = true;
  int _focusedTripRequestId = 0;
  final Map<String, _VehicleMarker> _focusedVehicles = {};
  final Map<String, MapStop> _focusedStops = {};
  final Set<String> _focusedRouteKeys = {};
  final Set<String> _focusedRouteColors = {};
  final Set<String> _focusedTripIds = {};
  MapStop? _selectedStop;
  bool _isStopOverlayClosing = false;
  bool _isStopTimesLoading = false;
  String? _stopTimesError;
  List<StopTime> _stopTimesPreview = [];
  bool _showVehicles = true;
  bool _hideNonRealtimeVehicles = false;
  bool _autoCenterEnabled = true;
  _QuickButtonAction _quickButtonAction = _QuickButtonAction.toggleRealtimeOnly;
  final Map<_VehicleModeGroup, bool> _vehicleModeVisibility = {
    _VehicleModeGroup.train: true,
    _VehicleModeGroup.metro: true,
    _VehicleModeGroup.tram: true,
    _VehicleModeGroup.bus: true,
    _VehicleModeGroup.ferry: true,
    _VehicleModeGroup.lift: true,
    _VehicleModeGroup.other: true,
  };

  static const Duration _tripWindowPast = Duration(minutes: 2);
  static const Duration _tripWindowFuture = Duration(minutes: 10);
  static const int _maxVehicleCount = 180;
  static const int _maxStopCount = 280;
  static const double _focusedTransferZoomLevel = 16.5;
  static const double _focusedTransferDistanceThresholdMeters = 80.0;
  static const Duration _mapRefreshDebounce = Duration(milliseconds: 250);

  /// How often vehicle markers are moved along their shapes. Roughly 12fps —
  /// smooth enough to read as movement, cheap enough to run all the time.
  static const Duration _vehicleAnimationFrame = Duration(milliseconds: 80);

  /// How often focused-trip times are re-checked against the clock.
  static const Duration _tripRefreshTick = Duration(seconds: 5);

  /// Gap between pulses of the rumble felt while dragging the sheet.
  static const Duration _dragRumbleInterval = Duration(milliseconds: 90);
  static const String _kShowStopsPrefKey = PrefsKeys.mapShowStops;
  static const String _kQuickButtonPrefKey = PrefsKeys.mapQuickButton;
  static const String _kShowVehiclesPrefKey = PrefsKeys.mapShowVehicles;
  static const String _kHideNonRtPrefKey = PrefsKeys.mapHideNonRtVehicles;
  static const String _kAutoCenterPrefKey = PrefsKeys.mapAutoCenter;
  static const String _kShowTrainPrefKey = PrefsKeys.mapShowTrain;
  static const String _kShowMetroPrefKey = PrefsKeys.mapShowMetro;
  static const String _kShowTramPrefKey = PrefsKeys.mapShowTram;
  static const String _kShowBusPrefKey = PrefsKeys.mapShowBus;
  static const String _kShowFerryPrefKey = PrefsKeys.mapShowFerry;
  static const String _kShowLiftPrefKey = PrefsKeys.mapShowLift;
  static const String _kShowOtherPrefKey = PrefsKeys.mapShowOther;
  String? _lastTripsRequestKey;
  String? _lastStopsRequestKey;

  @override
  void initState() {
    super.initState();
    unawaited(_initStartup());
    PlanRequests.pending.addListener(_applyPlanRequest);
    // One may already be waiting: the shell brings this tab forward in the
    // same frame the request is made, so the listener can miss it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyPlanRequest());
    ServerCapabilitiesService.capabilities.addListener(_onCapabilitiesChanged);
    RoutingOptionsService.optionsListenable.addListener(
      _onStoredOptionsChanged,
    );
    BackendReloadService.generation.addListener(_onBackendSwitched);
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _snapCtrl.addListener(() {
      final anim = _snapAnim;
      if (anim == null) return;
      final v = anim.value;
      if (_sheetTop != v) {
        setState(() => _sheetTop = v);
      }
    });
    _snapCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed ||
          status == AnimationStatus.dismissed) {
        _isBottomBarResizeAnimating = false;
      }
      if (status == AnimationStatus.completed && _snapTarget != null) {
        final target = _snapTarget!;
        final collapsed =
            (target - ((_lastComputedCollapsedTop ?? target))).abs() < 1.0;
        if (collapsed != _isSheetCollapsed) {
          setState(() => _isSheetCollapsed = collapsed);
          widget.onCollapseChanged?.call(collapsed);
          if (!collapsed) _dismissLongPressOverlay(animated: false);
        }
        if (_isSheetCollapsed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_selectionLatLngs().isNotEmpty) {
              if (_autoCenterEnabled) {
                unawaited(_fitSelectionBounds());
              }
              _skipAutoCenterOnSnap = false;
              return;
            }
            if (_skipAutoCenterOnSnap) {
              _skipAutoCenterOnSnap = false;
              return;
            }
            if (!_autoCenterEnabled) {
              return;
            } else {
              _centerToUserKeepZoom();
            }
          });
        } else if (_skipAutoCenterOnSnap) {
          _skipAutoCenterOnSnap = false;
        }
        _hapticSnap();
        _snapTarget = null;
      }
    });
    _initHapticCaps();
    _fromCtrl.addListener(_handleFromTextChanged);
    _toCtrl.addListener(_handleToTextChanged);
    unawaited(_loadRecentTrips());
  }

  Future<void> _initStartup() async {
    unawaited(_loadRoutingOptions());
    unawaited(RentalProvidersService.loadPrefs());
    unawaited(QuickAccessService.load());
    unawaited(ServerCapabilitiesService.ensureLoaded());
    await _loadShowStopsPreference();
    await _loadQuickSettingsPreferences();
    await _loadSavedSearchPlaces();
    if (!mounted) return;
    if (!widget.deferInit) {
      _ensureLocationReady();
      _didInitLocation = true;
    } else {
      _maybeAttachActivateListener();
    }
  }

  void _onCapabilitiesChanged() {
    if (!mounted) return;
    setState(
      () => _capabilities = ServerCapabilitiesService.capabilities.value,
    );
  }

  /// Seeds this search from the stored defaults, unless the user has already
  /// changed something — the slower read must not undo their edit.
  Future<void> _loadRoutingOptions() async {
    final stored = await RoutingOptionsService.load();
    if (!mounted) return;
    setState(() {
      _storedOptions = stored;
      // A plan request can arrive before this read, and judges "touched"
      // against the placeholder; matching what was stored is not an edit.
      if (!_optionsTouched || _options == stored) {
        _options = stored;
        _optionsTouched = false;
      }
    });
  }

  /// Follows defaults changed elsewhere — the settings screen, while this
  /// one stays alive behind the navigation bar.
  ///
  /// An untouched search takes them whole. A touched one keeps the rider's
  /// changes and takes only what the search screen cannot change.
  void _onStoredOptionsChanged() {
    if (!mounted) return;
    final stored = RoutingOptionsService.optionsListenable.value;
    if (stored == _storedOptions) return;
    setState(() {
      _storedOptions = stored;
      _options = _optionsTouched ? _options.withSettingsFrom(stored) : stored;
    });
  }

  /// Another server, or another API version: what the map shows came from
  /// the old one, so it is cleared and fetched again rather than left until
  /// the camera next moves.
  void _onBackendSwitched() {
    if (!mounted) return;
    _lastTripsRequestKey = null;
    _lastStopsRequestKey = null;
    _dismissStopOverlay();
    unawaited(_reloadMapData());
  }

  Future<void> _reloadMapData() async {
    await _clearVehicleMarkers();
    await _clearStopMarkers();
    if (!mounted) return;
    unawaited(_refreshStops());
    unawaited(_refreshTrips(force: true));
  }

  /// Via stops need a search of their own, so they get a screen.
  Future<void> _openViaStopPicker() async {
    _unfocusInputs();
    final updated = await Navigator.of(context).push<RoutingOptions>(
      CustomPageRoute(child: ViaStopsScreen(options: _options)),
    );
    if (!mounted || updated == null || updated == _options) return;
    _onOptionsChanged(updated);
  }

  void _onOptionsChanged(RoutingOptions options) {
    setState(() {
      _options = options;
      _optionsTouched = true;
    });
  }

  void _resetOptions() {
    setState(() {
      _options = _storedOptions;
      _optionsTouched = false;
    });
  }

  Future<void> _saveOptionsAsDefault() async {
    final options = _options;
    await RoutingOptionsService.save(options);
    if (!mounted) return;
    setState(() {
      _storedOptions = options;
      _optionsTouched = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _followMapSetting();
    final accent = AppColors.accentOf(context);
    if (_stopAccentColor?.toARGB32() == accent.toARGB32()) return;
    _stopAccentColor = accent;
    if (_isMapReady) {
      unawaited(_applyStopAccentColor());
    }
  }

  @override
  void dispose() {
    PlanRequests.pending.removeListener(_applyPlanRequest);
    RoutingOptionsService.optionsListenable.removeListener(
      _onStoredOptionsChanged,
    );
    BackendReloadService.generation.removeListener(_onBackendSwitched);
    ServerCapabilitiesService.capabilities.removeListener(
      _onCapabilitiesChanged,
    );
    _posSub?.cancel();
    _fromCtrl.removeListener(_handleFromTextChanged);
    _toCtrl.removeListener(_handleToTextChanged);
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _stopDragRumble();
    _activateListener?.call();
    _activateListener = null;
    _stopMapTimers();
    _controller?.onFeatureTapped.remove(_handleFeatureTapped);
    unawaited(_clearVehicleMarkers());
    unawaited(_clearStopMarkers());
    unawaited(_clearFocusedRoute());
    unawaited(_clearFocusedVehicles());
    unawaited(_clearFocusedStops());
    unawaited(_removeRouteSymbols());
    super.dispose();
    _snapCtrl.dispose();
  }

  void _maybeAttachActivateListener() {
    final listenable = widget.activateOnShow;
    _activateListener?.call();
    if (listenable != null) {
      void listener() {
        if (listenable.value) _activateIfNeeded();
      }

      listenable.addListener(listener);
      _activateListener = () => listenable.removeListener(listener);
      if (listenable.value) _activateIfNeeded();
    }
  }

  void _activateIfNeeded() {
    if (_didInitLocation) return;
    _didInitLocation = true;
    _ensureLocationReady();
  }

  @override
  void didUpdateWidget(covariant MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activateOnShow != widget.activateOnShow) {
      _activateListener?.call();
      _activateListener = null;
      if (widget.deferInit) {
        _maybeAttachActivateListener();
      }
    }
  }

  Future<void> _ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final granted = await LocationService.ensurePermission();
    if (!mounted) return;
    setState(() => _hasLocationPermission = granted);

    if (granted) {
      _defaultOriginToMyLocation();
      unawaited(_applyPersistedLastLocation());
      unawaited(_applyDeviceLastKnown());
      if (serviceEnabled) _startPositionStream();
    } else {
      await _posSub?.cancel();
      _posSub = null;
      _lastUserLatLng = null;
    }
  }

  /// A new search starts from where the rider is, once the app may know it.
  ///
  /// Only an empty origin is filled, never one already picked or handed over
  /// by a plan request.
  void _defaultOriginToMyLocation() {
    if (_fromSelection != null || _fromCtrl.text.isNotEmpty) return;
    _setControllerText(RouteFieldKind.from, myLocationName);
    _setSelection(RouteFieldKind.from, myLocationSuggestion, notify: true);
  }

  Future<void> _applyPersistedLastLocation() async {
    if (!_autoCenterEnabled) return;
    final last = await LocationService.loadLastLatLng();
    if (last == null) return;
    final cam = CameraPosition(
      target: last,
      zoom: _initCam.zoom,
      tilt: 0.0,
      bearing: 0.0,
    );
    if (!mounted) return;
    setState(() => _startCam = cam);
    if (_controller != null && !_didAutoCenter) {
      _lastCam = _startCam;
      await _controller!.moveCamera(CameraUpdate.newCameraPosition(_startCam));
    }
  }

  Future<void> _applyDeviceLastKnown() async {
    if (!_autoCenterEnabled) return;
    final last = await LocationService.lastKnownPosition();
    if (last == null) return;
    final cam = CameraPosition(
      target: LatLng(last.latitude, last.longitude),
      zoom: _initCam.zoom,
      tilt: 0.0,
      bearing: 0.0,
    );
    if (!mounted) return;
    setState(() => _startCam = cam);
    if (_controller != null && !_didAutoCenter) {
      _lastCam = _startCam;
      await _controller!.moveCamera(CameraUpdate.newCameraPosition(_startCam));
    }
  }

  void _startPositionStream() {
    _posSub?.cancel();
    _posSub =
        LocationService.positionStream(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ).listen((p) {
          final firstFix = _lastUserLatLng == null;
          _lastUserLatLng = LatLng(p.latitude, p.longitude);
          unawaited(LocationService.saveLastLatLng(_lastUserLatLng!));
          if (firstFix && !_didAutoCenter && _autoCenterEnabled) {
            _didAutoCenter = true;
            unawaited(_centerToUserKeepZoom());
          }
        }, onError: (_) {});
  }

  Future<bool> _ensurePermissionOnDemand() async {
    final ok = await LocationService.ensurePermission();
    if (!mounted) return ok;
    setState(() => _hasLocationPermission = ok);
    if (ok && _posSub == null) _startPositionStream();
    return ok;
  }

  void _followMapSetting() {
    final showsMap = Provider.of<ThemeProvider>(context).showsSearchMap;
    if (showsMap == _showsMap) return;
    _showsMap = showsMap;
    if (!showsMap) _releaseMap();
  }

  /// Lets go of everything the map held once it is turned off. Its timers
  /// would otherwise go on fetching vehicles for a map that is gone, which is
  /// the data the setting is there to save.
  void _releaseMap() {
    _stopMapTimers();
    _controller?.onFeatureTapped.remove(_handleFeatureTapped);
    _controller = null;
    _isMapReady = false;
    _isTripFocus = false;
    _isQuickSettings = false;
    _selectedStop = null;
    _isStopOverlayClosing = false;
    _longPressLatLng = null;
    _isLongPressClosing = false;
  }

  void _stopMapTimers() {
    _tripRefreshTimer?.cancel();
    _tripRefreshDebounce?.cancel();
    _stopRefreshDebounce?.cancel();
    _vehicleAnimationTimer?.cancel();
  }

  Future<void> _onMapCreated(MapLibreMapController controller) async {
    _controller = controller;
    controller.onFeatureTapped.add(_handleFeatureTapped);
    if (_startCam.target != _initCam.target && !_didAutoCenter) {
      _lastCam = _startCam;
      await _controller?.moveCamera(CameraUpdate.newCameraPosition(_startCam));
      if (mounted) setState(() {});
    }
  }

  void _onStyleLoaded() {
    _isMapReady = true;
    _didAddMarkerImages = false;
    _stopMarkerImages.clear();
    _stopMarkerImageId = null;
    _didAddStopsLayer = false;
    _didAddVehiclesLayer = false;
    _didAddFocusedVehiclesLayer = false;
    _didAddFocusedStopsLayer = false;
    _didAddFocusedRouteLayer = false;
    _vehicleLayerInit = null;
    _stopsLayerInit = null;
    _focusedVehiclesLayerInit = null;
    _focusedStopsLayerInit = null;
    _focusedRouteLayerInit = null;
    _focusedStopsColor = null;
    _vehicleMarkerImages.clear();
    _focusedVehicles.clear();
    _focusedStops.clear();
    _focusedRouteKeys.clear();
    _focusedRouteColors.clear();
    _focusedTripIds.clear();
    _focusedTripId = null;
    _focusedItinerary = null;
    _tripFocusLastUpdated = null;
    _isTripFocus = false;
    _isQuickSettings = false;
    _isTripFocusLoading = false;
    _tripFocusError = null;
    _lastTripsRequestKey = null;
    _lastStopsRequestKey = null;
    _tripRefreshTimer?.cancel();
    unawaited(_clearVehicleMarkers());
    unawaited(_clearStopMarkers());
    unawaited(_ensureMarkerImages());
    unawaited(_applyStopAccentColor());
    unawaited(_ensureStopsLayer());
    unawaited(_ensureVehicleLayer());
    unawaited(_refreshRouteMarkers());
    _vehicleAnimationTimer?.cancel();
    _vehicleAnimationTimer = Timer.periodic(
      _vehicleAnimationFrame,
      (_) => _updateVehiclePositions(),
    );
    _tripRefreshTimer = Timer.periodic(
      _tripRefreshTick,
      (_) => _handleTripRefreshTick(),
    );
    _scheduleTripRefresh();
    _scheduleStopRefresh();
    unawaited(_applySymbolOverlapSettings());
  }

  Future<void> _applySymbolOverlapSettings() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.setSymbolIconAllowOverlap(true);
    } catch (_) {}
    try {
      await controller.setSymbolTextAllowOverlap(true);
    } catch (_) {}
  }

  void _scheduleTripRefresh() {
    if (_isTripFocus || !_showVehicles) return;
    _tripRefreshDebounce?.cancel();
    _tripRefreshDebounce = Timer(_mapRefreshDebounce, () {
      unawaited(_refreshTrips());
    });
  }

  void _scheduleStopRefresh() {
    if (_isTripFocus) return;
    _stopRefreshDebounce?.cancel();
    _stopRefreshDebounce = Timer(_mapRefreshDebounce, () {
      unawaited(_refreshStops());
    });
  }

  Future<void> _centerOnUser2D() async {
    _didAutoCenter = true;
    final ok = await _ensurePermissionOnDemand();
    if (!ok) {
      final status = await Permission.locationWhenInUse.status;
      if (!mounted) return;
      if (status.isPermanentlyDenied) {
        Navigator.of(
          context,
        ).push(CustomPageRoute(child: const LocationSettingsScreen()));
      }
      return;
    }
    LatLng target = _lastUserLatLng ?? _startCam.target;
    if (_lastUserLatLng == null) {
      final pos = await LocationService.currentPosition(
        accuracy: LocationAccuracy.best,
      );
      target = LatLng(pos.latitude, pos.longitude);
      unawaited(LocationService.saveLastLatLng(target));
    }
    _lastCam = CameraPosition(
      target: target,
      zoom: 16.0,
      tilt: 0.0,
      bearing: 0.0,
    );
    await _controller?.animateCamera(CameraUpdate.newCameraPosition(_lastCam));
    if (mounted) setState(() {});
  }

  void _toggleStops() {
    _setShowStops(!_showStops);
  }

  void _toggleVehicles() {
    _setShowVehicles(!_showVehicles);
  }

  void _toggleRealtimeOnly() {
    _setHideNonRealtimeVehicles(!_hideNonRealtimeVehicles);
  }

  void _toggleAutoCenter() {
    _setAutoCenterEnabled(!_autoCenterEnabled);
  }

  void _changeMapStyle() {
    unawaited(_cycleMapStyle());
  }

  Future<void> _cycleMapStyle() async {
    if (!mounted) return;
    final themeProvider = context.read<ThemeProvider>();
    final current = themeProvider.mapStyle;
    final index = _mapStyleCycle.indexOf(current);
    final nextIndex = (index + 1) % _mapStyleCycle.length;
    await themeProvider.setMapStyle(_mapStyleCycle[nextIndex]);
  }

  void _setShowStops(bool value, {bool persist = true}) {
    if (_showStops == value) return;
    _stopRequestId++;
    _stopRefreshDebounce?.cancel();
    setState(() => _showStops = value);
    if (persist) {
      unawaited(_persistShowStopsPreference(_showStops));
    }
    _applyStopsLayerVisibility();
    if (_showStops) {
      _lastStopsRequestKey = null;
      _scheduleStopRefresh();
    } else {
      _dismissStopOverlay();
    }
  }

  void _onCameraMove(CameraPosition pos) {
    _lastCam = pos;
  }

  Future<void> _loadShowStopsPreference() async {
    final prefs = SharedPreferencesAsync();
    final stored = await prefs.getBool(_kShowStopsPrefKey);
    if (stored == null || !mounted) return;
    _setShowStops(stored, persist: false);
  }

  Future<void> _persistShowStopsPreference(bool value) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setBool(_kShowStopsPrefKey, value);
  }

  Future<void> _loadQuickSettingsPreferences() async {
    final prefs = SharedPreferencesAsync();
    final quickButtonKey = await prefs.getString(_kQuickButtonPrefKey);
    final showVehicles = await prefs.getBool(_kShowVehiclesPrefKey);
    final hideNonRt = await prefs.getBool(_kHideNonRtPrefKey);
    final autoCenter = await prefs.getBool(_kAutoCenterPrefKey);
    final train = await prefs.getBool(_kShowTrainPrefKey);
    final metro = await prefs.getBool(_kShowMetroPrefKey);
    final tram = await prefs.getBool(_kShowTramPrefKey);
    final bus = await prefs.getBool(_kShowBusPrefKey);
    final ferry = await prefs.getBool(_kShowFerryPrefKey);
    final lift = await prefs.getBool(_kShowLiftPrefKey);
    final other = await prefs.getBool(_kShowOtherPrefKey);
    if (!mounted) return;
    setState(() {
      _quickButtonAction = _quickButtonActionFromKey(quickButtonKey);
      if (showVehicles != null) {
        _showVehicles = showVehicles;
      }
      if (hideNonRt != null) {
        _hideNonRealtimeVehicles = hideNonRt;
      }
      if (autoCenter != null) {
        _autoCenterEnabled = autoCenter;
      }
      if (train != null) {
        _vehicleModeVisibility[_VehicleModeGroup.train] = train;
      }
      if (metro != null) {
        _vehicleModeVisibility[_VehicleModeGroup.metro] = metro;
      }
      if (tram != null) {
        _vehicleModeVisibility[_VehicleModeGroup.tram] = tram;
      }
      if (bus != null) {
        _vehicleModeVisibility[_VehicleModeGroup.bus] = bus;
      }
      if (ferry != null) {
        _vehicleModeVisibility[_VehicleModeGroup.ferry] = ferry;
      }
      if (lift != null) {
        _vehicleModeVisibility[_VehicleModeGroup.lift] = lift;
      }
      if (other != null) {
        _vehicleModeVisibility[_VehicleModeGroup.other] = other;
      }
    });
    _applyVehiclesLayerVisibility();
    if (!_showVehicles) {
      unawaited(_clearVehicleMarkers());
    }
  }

  Future<void> _persistQuickButtonPreference(_QuickButtonAction action) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setString(_kQuickButtonPrefKey, _quickButtonActionKey(action));
  }

  Future<void> _persistShowVehiclesPreference(bool value) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setBool(_kShowVehiclesPrefKey, value);
  }

  Future<void> _persistHideNonRtPreference(bool value) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setBool(_kHideNonRtPrefKey, value);
  }

  Future<void> _persistAutoCenterPreference(bool value) async {
    final prefs = SharedPreferencesAsync();
    await prefs.setBool(_kAutoCenterPrefKey, value);
  }

  Future<void> _persistVehicleModePreference(
    _VehicleModeGroup mode,
    bool value,
  ) async {
    final prefs = SharedPreferencesAsync();
    final key = switch (mode) {
      _VehicleModeGroup.train => _kShowTrainPrefKey,
      _VehicleModeGroup.metro => _kShowMetroPrefKey,
      _VehicleModeGroup.tram => _kShowTramPrefKey,
      _VehicleModeGroup.bus => _kShowBusPrefKey,
      _VehicleModeGroup.ferry => _kShowFerryPrefKey,
      _VehicleModeGroup.lift => _kShowLiftPrefKey,
      _VehicleModeGroup.other => _kShowOtherPrefKey,
    };
    await prefs.setBool(key, value);
  }

  void _setQuickButtonAction(_QuickButtonAction action) {
    if (_quickButtonAction == action) return;
    setState(() => _quickButtonAction = action);
    unawaited(_persistQuickButtonPreference(action));
  }

  void _setShowVehicles(bool value) {
    if (_showVehicles == value) return;
    setState(() => _showVehicles = value);
    unawaited(_persistShowVehiclesPreference(value));
    _applyVehiclesLayerVisibility();
    if (!_showVehicles) {
      _tripRefreshDebounce?.cancel();
      _lastTripsRequestKey = null;
      unawaited(_clearVehicleMarkers());
      return;
    }
    _lastTripsRequestKey = null;
    _scheduleTripRefresh();
  }

  void _setHideNonRealtimeVehicles(bool value) {
    if (_hideNonRealtimeVehicles == value) return;
    setState(() => _hideNonRealtimeVehicles = value);
    unawaited(_persistHideNonRtPreference(value));
    if (_isTripFocus) {
      unawaited(_refreshFocusedTripVehicles(force: true));
    } else {
      unawaited(_refreshTrips(force: true));
    }
  }

  void _setAutoCenterEnabled(bool value) {
    if (_autoCenterEnabled == value) return;
    setState(() => _autoCenterEnabled = value);
    unawaited(_persistAutoCenterPreference(value));
  }

  void _setVehicleModeVisibility(_VehicleModeGroup mode, bool value) {
    if (_vehicleModeVisibility[mode] == value) return;
    setState(() => _vehicleModeVisibility[mode] = value);
    unawaited(_persistVehicleModePreference(mode, value));
    if (_isTripFocus) {
      unawaited(_refreshFocusedTripVehicles(force: true));
    } else {
      unawaited(_refreshTrips(force: true));
    }
  }

  String _quickButtonActionKey(_QuickButtonAction action) {
    return switch (action) {
      _QuickButtonAction.toggleStops => 'toggle_stops',
      _QuickButtonAction.toggleVehicles => 'toggle_vehicles',
      _QuickButtonAction.toggleRealtimeOnly => 'toggle_rt',
      _QuickButtonAction.toggleAutoCenter => 'toggle_auto_center',
      _QuickButtonAction.changeMapStyle => 'change_map',
    };
  }

  _QuickButtonAction _quickButtonActionFromKey(String? value) {
    return switch (value) {
      'toggle_vehicles' => _QuickButtonAction.toggleVehicles,
      'toggle_rt' => _QuickButtonAction.toggleRealtimeOnly,
      'toggle_auto_center' => _QuickButtonAction.toggleAutoCenter,
      'change_map' => _QuickButtonAction.changeMapStyle,
      _ => _QuickButtonAction.toggleRealtimeOnly,
    };
  }

  List<_QuickButtonOption> _quickButtonOptions() {
    return const [
      _QuickButtonOption(
        action: _QuickButtonAction.toggleStops,
        label: 'Toggle stops',
        icon: LucideIcons.mapPin,
        subtitle: 'Show or hide stops',
        enabled: true,
      ),
      _QuickButtonOption(
        action: _QuickButtonAction.toggleVehicles,
        label: 'Toggle vehicles',
        icon: LucideIcons.busFront,
        subtitle: 'Show or hide vehicles',
        enabled: true,
      ),
      _QuickButtonOption(
        action: _QuickButtonAction.toggleRealtimeOnly,
        label: 'Toggle Only RT',
        icon: LucideIcons.radio,
        subtitle: 'Show only real-time data',
        enabled: true,
      ),
      _QuickButtonOption(
        action: _QuickButtonAction.toggleAutoCenter,
        label: 'Auto-center',
        icon: LucideIcons.compass,
        subtitle: 'Enable or disable auto-centering',
        enabled: true,
      ),
      _QuickButtonOption(
        action: _QuickButtonAction.changeMapStyle,
        label: 'Change map',
        icon: LucideIcons.map,
        subtitle: 'Cycle map style',
        enabled: true,
      ),
    ];
  }

  _QuickButtonConfig _quickButtonConfig(BuildContext context) {
    switch (_quickButtonAction) {
      case _QuickButtonAction.toggleStops:
        final color = _showStops
            ? AppColors.accentOf(context)
            : AppColors.black;
        return _QuickButtonConfig(
          label: _showStops ? 'Hide Stops' : 'Show Stops',
          icon: _showStops ? LucideIcons.mapPinOff : LucideIcons.mapPin,
          color: color,
          onTap: _toggleStops,
        );
      case _QuickButtonAction.toggleVehicles:
        final color = _showVehicles
            ? AppColors.accentOf(context)
            : AppColors.black;
        return _QuickButtonConfig(
          label: _showVehicles ? 'Hide Transit' : 'Show Transit',
          icon: LucideIcons.busFront,
          color: color,
          onTap: _toggleVehicles,
        );
      case _QuickButtonAction.toggleRealtimeOnly:
        final color = _hideNonRealtimeVehicles
            ? AppColors.accentOf(context)
            : AppColors.black;
        return _QuickButtonConfig(
          label: _hideNonRealtimeVehicles ? 'RT Only' : 'All Data',
          icon: LucideIcons.radio,
          color: color,
          onTap: _toggleRealtimeOnly,
        );
      case _QuickButtonAction.toggleAutoCenter:
        final color = _autoCenterEnabled
            ? AppColors.accentOf(context)
            : AppColors.black;
        return _QuickButtonConfig(
          label: _autoCenterEnabled ? 'Auto-center' : 'No centering',
          icon: LucideIcons.compass,
          color: color,
          onTap: _toggleAutoCenter,
        );
      case _QuickButtonAction.changeMapStyle:
        return _QuickButtonConfig(
          label: 'Switch Map',
          icon: LucideIcons.map,
          color: AppColors.black,
          onTap: _changeMapStyle,
        );
    }
  }

  void _onCameraIdle() {
    final controller = _controller;
    final cameraPosition = controller?.cameraPosition;
    if (cameraPosition != null) {
      _lastCam = cameraPosition;
    }
    _scheduleTripRefresh();
    _scheduleStopRefresh();
  }

  Future<void> _refreshTrips({bool force = false}) async {
    final controller = _controller;
    if (controller == null || !_isMapReady || _isTripFocus) return;
    if (!_showVehicles) {
      _applyVehiclesLayerVisibility();
      return;
    }
    if (controller.isCameraMoving) return;
    final token = ++_tripRequestId;
    LatLngBounds bounds;
    try {
      bounds = await controller.getVisibleRegion();
    } catch (_) {
      return;
    }
    final viewKey = _viewKey(bounds, _lastCam.zoom);
    if (!force && viewKey == _lastTripsRequestKey) return;
    final now = DateTime.now().toUtc();
    final startTime = now.subtract(_tripWindowPast);
    final endTime = now.add(_tripWindowFuture);
    List<MapTripSegment> segments;
    try {
      segments = await TransitousMapService.fetchTripSegments(
        zoom: _lastCam.zoom,
        bounds: bounds,
        startTime: startTime,
        endTime: endTime,
      );
    } catch (_) {
      return;
    }
    if (!mounted || token != _tripRequestId) return;
    _lastTripsRequestKey = viewKey;
    await _updateVehiclesFromSegments(segments, now, token);
  }

  void _handleTripRefreshTick() {
    if (_isTripFocus) {
      unawaited(_refreshFocusedTripVehicles(force: true));
      if (mounted) {
        setState(() {});
      }
    } else {
      if (_showVehicles) {
        unawaited(_refreshTrips(force: true));
      }
    }
  }

  Future<void> _refreshFocusedTripVehicles({bool force = false}) async {
    if (!_isTripFocus) return;
    final tripId = _focusedTripId;
    if (tripId == null || tripId.isEmpty) return;
    final controller = _controller;
    if (controller == null || !_isMapReady) return;
    if (controller.isCameraMoving) return;
    final token = ++_tripRequestId;
    LatLngBounds bounds;
    try {
      bounds = await controller.getVisibleRegion();
    } catch (_) {
      return;
    }
    if (!force) {
      final viewKey = _viewKey(bounds, _lastCam.zoom);
      if (viewKey == _lastTripsRequestKey) return;
    }
    final now = DateTime.now().toUtc();
    final startTime = now.subtract(_tripWindowPast);
    final endTime = now.add(_tripWindowFuture);
    List<MapTripSegment> segments;
    try {
      segments = await TransitousMapService.fetchTripSegments(
        zoom: _lastCam.zoom,
        bounds: bounds,
        startTime: startTime,
        endTime: endTime,
      );
    } catch (_) {
      return;
    }
    if (!mounted || token != _tripRequestId) return;
    await _ensureFocusedVehiclesLayer();
    _lastTripsRequestKey = _viewKey(bounds, _lastCam.zoom);

    final chosen = <String, _SelectedSegment>{};
    final closestDelta = <String, Duration>{};
    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (!_matchesFocusedSegment(segment, tripId)) continue;
      if (!_passesVehicleFilters(segment)) continue;
      final dep = segment.departure?.toUtc();
      final arr = segment.arrival?.toUtc();
      if (dep == null || arr == null) continue;
      final key = segment.tripId;
      final segmentDelta = now.isBefore(dep)
          ? dep.difference(now)
          : now.isAfter(arr)
          ? now.difference(arr)
          : Duration.zero;
      final existing = chosen[key];
      final existingDelta = closestDelta[key];
      if (existing == null ||
          existingDelta == null ||
          segmentDelta < existingDelta ||
          (segmentDelta == existingDelta && arr.isBefore(existing.arrival))) {
        chosen[key] = _SelectedSegment(
          segment: segment,
          colorIndex: i,
          arrival: arr,
        );
        closestDelta[key] = segmentDelta;
      }
    }

    final seenTripIds = chosen.keys.toSet();
    for (final entry in chosen.entries) {
      final segData = _buildTripSegmentData(
        entry.value.segment,
        entry.value.colorIndex,
      );
      if (segData == null) continue;
      final visual = _vehicleMarkerVisual(segData);
      final imageId = await _ensureVehicleMarkerImage(visual, segData.color);
      if (imageId == null) continue;
      final existing = _focusedVehicles[entry.key];
      if (existing == null) {
        _focusedVehicles[entry.key] = _VehicleMarker(
          segmentData: segData,
          imageId: imageId,
        )..lastPosition = _positionAlongSegment(segData, now);
      } else {
        existing.segmentData = segData;
        existing.imageId = imageId;
      }
    }

    for (final entry in _focusedVehicles.entries.toList()) {
      if (!seenTripIds.contains(entry.key)) {
        _focusedVehicles.remove(entry.key);
      }
    }

    if (!mounted || token != _tripRequestId) return;
    unawaited(_pushFocusedVehicleSource(now));
  }

  bool _matchesFocusedSegment(MapTripSegment segment, String tripId) {
    return segment.tripId == tripId;
  }

  bool _passesVehicleFilters(MapTripSegment segment) {
    if (_hideNonRealtimeVehicles && !segment.realTime) return false;
    final group = _vehicleModeGroupFor(segment.mode);
    return _vehicleModeVisibility[group] ?? true;
  }

  _VehicleModeGroup _vehicleModeGroupFor(String? mode) {
    final value = (mode ?? '').toUpperCase();
    if (value.contains('RAIL') || value == 'TRAIN') {
      return _VehicleModeGroup.train;
    }
    if (value == 'SUBWAY' || value == 'METRO') {
      return _VehicleModeGroup.metro;
    }
    if (value == 'TRAM' || value == 'STREETCAR') {
      return _VehicleModeGroup.tram;
    }
    if (value.contains('BUS') || value == 'COACH') {
      return _VehicleModeGroup.bus;
    }
    if (value == 'FERRY') {
      return _VehicleModeGroup.ferry;
    }
    if (value == 'GONDOLA' ||
        value == 'CABLE_CAR' ||
        value == 'FUNICULAR' ||
        value == 'LIFT') {
      return _VehicleModeGroup.lift;
    }
    return _VehicleModeGroup.other;
  }

  Future<void> _updateVehiclesFromSegments(
    List<MapTripSegment> segments,
    DateTime now,
    int token,
  ) async {
    final controller = _controller;
    if (controller == null) return;
    await _ensureVehicleLayer();
    final chosen = <String, _SelectedSegment>{};
    final maxVehicles = _maxVehiclesForZoom(_lastCam.zoom);
    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (!_passesVehicleFilters(segment)) continue;
      final dep = segment.departure?.toUtc();
      final arr = segment.arrival?.toUtc();
      if (dep == null || arr == null) continue;
      if (now.isBefore(dep) || now.isAfter(arr)) continue;
      final tripId = segment.tripId;
      final existing = chosen[tripId];
      if (existing == null || arr.isBefore(existing.arrival)) {
        chosen[tripId] = _SelectedSegment(
          segment: segment,
          colorIndex: i,
          arrival: arr,
        );
      }
      if (chosen.length >= maxVehicles) break;
    }

    final seenTripIds = chosen.keys.toSet();
    for (final entry in chosen.entries) {
      final tripId = entry.key;
      final selected = entry.value;
      final segData = _buildTripSegmentData(
        selected.segment,
        selected.colorIndex,
      );
      if (segData == null) continue;
      final visual = _vehicleMarkerVisual(segData);
      final imageId = await _ensureVehicleMarkerImage(visual, segData.color);
      if (imageId == null) continue;
      final existing = _vehicles[tripId];
      if (existing == null) {
        _vehicles[tripId] = _VehicleMarker(
          segmentData: segData,
          imageId: imageId,
        )..lastPosition = _positionAlongSegment(segData, now);
      } else {
        existing.segmentData = segData;
        existing.imageId = imageId;
      }
    }

    for (final entry in _vehicles.entries.toList()) {
      if (!seenTripIds.contains(entry.key)) {
        _vehicles.remove(entry.key);
      }
    }
    if (!mounted || token != _tripRequestId) return;
    unawaited(_pushVehicleSource(now));
  }

  void _updateVehiclePositions() {
    if (_isTripFocus) {
      _updateVehiclePositionsFor(_focusedVehicles, _pushFocusedVehicleSource);
    } else {
      if (!_showVehicles) return;
      _updateVehiclePositionsFor(_vehicles, _pushVehicleSource);
    }
  }

  void _updateVehiclePositionsFor(
    Map<String, _VehicleMarker> markers,
    Future<void> Function(DateTime) push,
  ) {
    final controller = _controller;
    if (controller == null || markers.isEmpty) return;
    final now = DateTime.now().toUtc();
    final nowMs = now.millisecondsSinceEpoch;
    var anyChange = false;
    for (final entry in markers.values) {
      final segData = entry.segmentData;
      final target = _positionAlongSegment(segData, now);
      final lastPosition = entry.lastPosition;
      if (lastPosition == null) {
        entry.lastPosition = target;
        entry.lastUpdateMs = nowMs;
        anyChange = true;
        continue;
      }

      final delta = coordinateDistanceInMeters(
        lastPosition.latitude,
        lastPosition.longitude,
        target.latitude,
        target.longitude,
      );
      if (delta < 0.7) continue;

      final lastUpdateMs = entry.lastUpdateMs ?? nowMs;
      final dtMs = (nowMs - lastUpdateMs).clamp(16, 500);
      final alpha = 1.0 - math.exp(-dtMs / 160.0);
      final smoothing = delta > 140 ? 1.0 : alpha.clamp(0.35, 0.9);
      entry.lastPosition = LatLng(
        lastPosition.latitude +
            (target.latitude - lastPosition.latitude) * smoothing,
        lastPosition.longitude +
            (target.longitude - lastPosition.longitude) * smoothing,
      );
      entry.lastUpdateMs = nowMs;
      anyChange = true;
    }
    if (anyChange) {
      unawaited(push(now));
    }
  }

  Future<void> _refreshStops() async {
    final controller = _controller;
    if (controller == null || !_isMapReady || _isTripFocus) return;
    if (!_showStops) {
      _applyStopsLayerVisibility();
      return;
    }
    if (_lastCam.zoom < 10.0) {
      _lastStopsRequestKey = null;
      _dismissStopOverlay();
      await _clearStopMarkers();
      return;
    }
    final token = ++_stopRequestId;
    LatLngBounds bounds;
    try {
      bounds = await controller.getVisibleRegion();
    } catch (_) {
      return;
    }
    final viewKey = _viewKey(bounds, _lastCam.zoom);
    if (viewKey == _lastStopsRequestKey) return;
    List<MapStop> stops;
    try {
      stops = await TransitousMapService.fetchStops(bounds: bounds);
    } catch (_) {
      return;
    }
    if (!mounted || token != _stopRequestId || !_showStops) return;
    _lastStopsRequestKey = viewKey;

    final maxStops = _maxStopsForZoom(_lastCam.zoom);
    if (stops.length > maxStops * 5) {
      stops = stops.take(maxStops * 5).toList();
    }
    stops = _selectStopsForView(stops, bounds, _lastCam.zoom);
    if (stops.length > maxStops) {
      stops = stops.take(maxStops).toList();
    }

    final nextStops = <String, MapStop>{
      for (final stop in stops) stop.id: stop,
    };
    final sameStops =
        nextStops.length == _visibleStops.length &&
        nextStops.keys.every(_visibleStops.containsKey);
    if (sameStops) return;
    _visibleStops
      ..clear()
      ..addAll(nextStops);
    await _ensureStopsLayer();
    if (token != _stopRequestId || !_showStops) return;
    await _setStopsSource(nextStops.values.toList());
    _applyStopsLayerVisibility();
  }

  Future<void> _clearStopMarkers() async {
    final controller = _controller;
    if (controller == null) return;
    _visibleStops.clear();
    if (!_didAddStopsLayer) return;
    try {
      await controller.setGeoJsonSource(
        _kStopsSourceId,
        _emptyFeatureCollection(),
      );
    } catch (_) {}
  }

  Future<void> _clearVehicleMarkers() async {
    final controller = _controller;
    if (controller == null) return;
    _vehicles.clear();
    if (!_didAddVehiclesLayer) return;
    try {
      await controller.setGeoJsonSource(
        _kVehiclesSourceId,
        _emptyFeatureCollection(),
      );
    } catch (_) {}
  }

  _TripSegmentData? _buildTripSegmentData(
    MapTripSegment segment,
    int colorIndex,
  ) {
    final dep = segment.departure?.toUtc();
    final arr = segment.arrival?.toUtc();
    if (dep == null || arr == null || !arr.isAfter(dep)) return null;
    final polyline = segment.polyline;
    if (polyline == null || polyline.isEmpty) return null;
    List<LatLng> points;
    try {
      points = decodePolyline(polyline, 5);
    } catch (_) {
      return null;
    }
    if (points.length < 2) return null;
    final cumulative = List<double>.filled(points.length, 0);
    double total = 0;
    for (int i = 1; i < points.length; i++) {
      total += coordinateDistanceInMeters(
        points[i - 1].latitude,
        points[i - 1].longitude,
        points[i].latitude,
        points[i].longitude,
      );
      cumulative[i] = total;
    }
    if (total <= 0) return null;
    return _TripSegmentData(
      tripId: segment.tripId,
      label: _vehicleLabelForSegment(segment),
      mode: segment.mode ?? 'TRANSIT',
      departure: dep,
      arrival: arr,
      points: points,
      cumulative: cumulative,
      totalDistance: total,
      color: _segmentColorForIndex(segment, colorIndex),
    );
  }

  LatLng _positionAlongSegment(_TripSegmentData data, DateTime now) {
    final durationMs =
        data.arrival.millisecondsSinceEpoch -
        data.departure.millisecondsSinceEpoch;
    if (durationMs <= 0) return data.points.first;
    final t =
        (now.millisecondsSinceEpoch - data.departure.millisecondsSinceEpoch) /
        durationMs;
    final clamped = t.clamp(0.0, 1.0);
    final distance = clamped * data.totalDistance;
    return _pointAlong(data, distance);
  }

  LatLng _pointAlong(_TripSegmentData data, double targetMeters) {
    final points = data.points;
    final cumulative = data.cumulative;
    if (targetMeters <= 0) return points.first;
    if (targetMeters >= data.totalDistance) return points.last;
    var lo = 0;
    var hi = cumulative.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (cumulative[mid] < targetMeters) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    final i = math.max(1, lo);
    final d0 = cumulative[i - 1];
    final d1 = cumulative[i];
    final f = (d1 == d0) ? 0.0 : (targetMeters - d0) / (d1 - d0);
    final p0 = points[i - 1];
    final p1 = points[i];
    return LatLng(
      p0.latitude + (p1.latitude - p0.latitude) * f,
      p0.longitude + (p1.longitude - p0.longitude) * f,
    );
  }

  Color _segmentColorForIndex(MapTripSegment segment, int _) {
    final parsed = parseHexColor(segment.routeColor?.trim());
    return parsed ?? _currentAccentColor();
  }

  Color _focusedRouteColor(Itinerary itinerary) {
    for (final leg in itinerary.legs) {
      if (leg.mode == 'WALK') continue;
      final parsed = parseHexColor(leg.routeColor);
      if (parsed != null) return parsed;
    }
    return _currentAccentColor();
  }

  Set<String> _buildFocusedRouteKeys(Itinerary itinerary) {
    final keys = <String>{};
    for (final leg in itinerary.legs) {
      if (leg.mode == 'WALK') continue;
      final display = leg.displayName?.trim();
      if (display != null && display.isNotEmpty) {
        keys.add(display);
      }
      final shortName = leg.routeShortName?.trim();
      if (shortName != null && shortName.isNotEmpty) {
        keys.add(shortName);
      }
      final longName = leg.routeLongName?.trim();
      if (longName != null && longName.isNotEmpty) {
        keys.add(longName);
      }
    }
    return keys;
  }

  Set<String> _buildFocusedRouteColors(Itinerary itinerary) {
    final colors = <String>{};
    for (final leg in itinerary.legs) {
      if (leg.routeColor == null) continue;
      final color = leg.routeColor!.trim();
      if (color.isNotEmpty) {
        colors.add(color.toUpperCase());
      }
    }
    return colors;
  }

  Set<String> _buildFocusedTripIds(Itinerary itinerary) {
    final tripIds = <String>{};
    for (final leg in itinerary.legs) {
      final id = leg.tripId?.trim();
      if (id != null && id.isNotEmpty) {
        tripIds.add(id);
      }
    }
    return tripIds;
  }

  String _vehicleLabelForSegment(MapTripSegment segment) {
    final display = segment.displayName?.trim();
    if (display != null && display.isNotEmpty) return display;
    final shortName = segment.routeShortName?.trim();
    if (shortName != null && shortName.isNotEmpty) return shortName;
    return segment.tripId;
  }

  String _viewKey(LatLngBounds bounds, double zoom) {
    final south = math.min(
      bounds.southwest.latitude,
      bounds.northeast.latitude,
    );
    final north = math.max(
      bounds.southwest.latitude,
      bounds.northeast.latitude,
    );
    final west = math.min(
      bounds.southwest.longitude,
      bounds.northeast.longitude,
    );
    final east = math.max(
      bounds.southwest.longitude,
      bounds.northeast.longitude,
    );
    return [
      zoom.toStringAsFixed(2),
      south.toStringAsFixed(5),
      west.toStringAsFixed(5),
      north.toStringAsFixed(5),
      east.toStringAsFixed(5),
    ].join('|');
  }

  int _maxVehiclesForZoom(double zoom) {
    if (zoom >= 15.5) return _maxVehicleCount;
    if (zoom >= 14.0) return 150;
    if (zoom >= 12.5) return 120;
    return 90;
  }

  int _maxStopsForZoom(double zoom) {
    if (zoom >= 16.0) return _maxStopCount;
    if (zoom >= 14.5) return 230;
    if (zoom >= 13.0) return 190;
    if (zoom >= 12.0) return 150;
    return 120;
  }

  List<MapStop> _selectStopsForView(
    List<MapStop> stops,
    LatLngBounds bounds,
    double zoom,
  ) {
    if (stops.isEmpty) return stops;
    final deduped = <String, MapStop>{};
    for (final stop in stops) {
      final key =
          '${stop.lat.toStringAsFixed(6)}:${stop.lon.toStringAsFixed(6)}';
      final existing = deduped[key];
      if (existing == null) {
        deduped[key] = stop;
        continue;
      }
      final existingScore = existing.importance ?? 0.0;
      final candidateScore = stop.importance ?? 0.0;
      if (candidateScore > existingScore) {
        deduped[key] = stop;
      }
    }
    return deduped.values.toList();
  }

  Color _currentAccentColor() {
    return ThemeProvider.instance?.accentColor ?? AppColors.accent;
  }

  void _onTimeSelectionChanged(TimeSelection newSelection) {
    setState(() {
      _timeSelection = newSelection;
    });
  }

  void _notifyOverlayVisibility({bool overlaysVisible = false}) {
    widget.onOverlayVisibilityChanged?.call(overlaysVisible);
  }

  void _openTimeSelectionOverlay() {
    if (_showTimeSelectionOverlay) return;
    _unfocusInputs();
    setState(() {
      _showTimeSelectionOverlay = true;
    });
    _notifyOverlayVisibility();
    showTimeSelectionOverlay(
      context,
      currentSelection: _timeSelection,
      onSelectionChanged: _onTimeSelectionChanged,
      onDismiss: _closeTimeSelectionOverlay,
    ).then((_) {
      if (!mounted) return;
      if (_showTimeSelectionOverlay) {
        setState(() => _showTimeSelectionOverlay = false);
        _notifyOverlayVisibility();
      }
    });
  }

  void _closeTimeSelectionOverlay() {
    if (!_showTimeSelectionOverlay) return;
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  void _toggleTimeSelectionOverlay() {
    if (_showTimeSelectionOverlay) {
      _closeTimeSelectionOverlay();
    } else {
      _openTimeSelectionOverlay();
    }
  }

  void _handleTimeSelectionTapDown() {
    if (_showTimeSelectionOverlay) {
      _suppressTimeSelectionReopen = true;
      _closeTimeSelectionOverlay();
    }
  }

  void _handleTimeSelectionTapCancel() {
    _suppressTimeSelectionReopen = false;
  }

  void _handleTimeSelectionTap() {
    if (_suppressTimeSelectionReopen) {
      _suppressTimeSelectionReopen = false;
      return;
    }
    _toggleTimeSelectionOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stepBack();
      },
      child: _showsMap
          ? AnnotatedRegion<SystemUiOverlayStyle>(
              value: systemBarsOverMap(
                appIsDark: theme.isDark,
                mapIsDark: theme.isMapDark,
              ),
              child: _buildSplitLayout(),
            )
          : _buildPageLayout(),
    );
  }

  bool get _canPop =>
      !_isTripFocus &&
      !_isQuickSettings &&
      !_isSheetCollapsed &&
      !_showTimeSelectionOverlay &&
      _selectedStop == null &&
      _longPressLatLng == null;

  /// Back closes whatever is open over the search, innermost first, and
  /// finally raises a card left down over the map.
  void _stepBack() {
    if (_isTripFocus) return _exitTripFocus();
    if (_isQuickSettings) return _closeQuickSettings();
    if (_selectedStop != null) return _dismissStopOverlay();
    if (_longPressLatLng != null) return _dismissLongPressOverlay();
    if (_showTimeSelectionOverlay) return _closeTimeSelectionOverlay();
    _expandSheetToCard();
    _stopDragRumble();
  }

  /// Without the map the search is the page: the same card, nothing under it
  /// to uncover, so it never collapses.
  Widget _buildPageLayout() {
    _reportSheetPosition(collapsed: false, progress: 0);
    return _buildRouteCard();
  }

  /// The map, with the search as a sheet that can be dragged down off it.
  Widget _buildSplitLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sheet = _layoutSheet(constraints.maxHeight);
        return Stack(
          children: [
            Positioned.fill(child: RepaintBoundary(child: _buildMap())),
            if (!_isTripFocus && !_isQuickSettings)
              _buildControlPills(sheet.progress),
            ..._buildMapOverlays(),
            Positioned(
              left: 0,
              right: 0,
              top: _sheetTop!,
              bottom: 0,
              child: RepaintBoundary(child: _buildSheet(sheet)),
            ),
          ],
        );
      },
    );
  }

  /// Places the sheet for a screen [totalHeight] tall and reports where it
  /// ended up.
  _SheetLayout _layoutSheet(double totalHeight) {
    final bottomBarHeight = _isTripFocus
        ? _tripFocusBottomBarHeight
        : _bottomBarHeight;
    final collapsedTop = math.max(0.0, totalHeight - bottomBarHeight);
    final expandedTop = (totalHeight * _collapsedMapFraction).clamp(
      0.0,
      collapsedTop,
    );
    _lastComputedCollapsedTop = collapsedTop;
    _lastComputedExpandedTop = expandedTop;
    _lastBottomBarHeight = bottomBarHeight;

    _sheetTop ??= expandedTop;
    _sheetTop = _isBottomBarResizeAnimating
        ? math.max(_sheetTop!, expandedTop)
        : _sheetTop!.clamp(expandedTop, collapsedTop);

    final travel = collapsedTop - expandedTop;
    final progress = travel <= 0.0
        ? 1.0
        : ((_sheetTop! - expandedTop) / travel).clamp(0.0, 1.0);
    _reportSheetPosition(
      collapsed: (_sheetTop! - collapsedTop).abs() < 1.0,
      progress: progress,
    );

    return _SheetLayout(
      drag: SheetDrag(
        onTap: () => _toggleSheet(expandedTop, collapsedTop),
        onStart: _onSheetDragStart,
        onUpdate: (dy) => _onSheetDragUpdate(dy, expandedTop, collapsedTop),
        onEnd: (velocity) =>
            _onSheetDragEnd(velocity, expandedTop, collapsedTop),
      ),
      bottomBarHeight: bottomBarHeight,
      progress: progress,
    );
  }

  /// Tells the shell where the sheet is, so the nav bar can follow it.
  void _reportSheetPosition({
    required bool collapsed,
    required double progress,
  }) {
    if (collapsed != _isSheetCollapsed) {
      _isSheetCollapsed = collapsed;
      widget.onCollapseChanged?.call(collapsed);
    }
    widget.onCollapseProgressChanged?.call(progress);
  }

  /// The only map on the search screen, and the only one the app builds
  /// without being asked to: tiles, stops and vehicles are all fetched from
  /// its callbacks, so not building it is what keeps them off the network.
  Widget _buildMap() {
    return MapLibreMap(
      onMapCreated: _onMapCreated,
      onStyleLoadedCallback: _onStyleLoaded,
      styleString: context.watch<ThemeProvider>().mapStyleUrl,
      myLocationEnabled: _hasLocationPermission,
      myLocationRenderMode: _hasLocationPermission
          ? MyLocationRenderMode.compass
          : MyLocationRenderMode.normal,
      myLocationTrackingMode: MyLocationTrackingMode.none,
      trackCameraPosition: true,
      rotateGesturesEnabled: true,
      tiltGesturesEnabled: false,
      initialCameraPosition: _startCam,
      compassEnabled: false,
      onCameraMove: _onCameraMove,
      onCameraIdle: _onCameraIdle,
      onMapClick: _onMapTap,
      onMapLongClick: _onMapLongClick,
      annotationConsumeTapEvents: const [AnnotationType.symbol],
    );
  }

  /// Locate and settings, fading in as the sheet goes down and there is map
  /// to act on.
  Widget _buildControlPills(double sheetProgress) {
    const double revealStart = 0.7;
    final visibility = Curves.easeOutCubic.transform(
      ((sheetProgress - revealStart) / (1 - revealStart)).clamp(0.0, 1.0),
    );
    return Positioned(
      left: 0,
      right: 0,
      top: math.max(0.0, _sheetTop! - 46),
      child: IgnorePointer(
        ignoring: visibility < 0.05,
        child: Opacity(
          opacity: visibility,
          child: Transform.translate(
            offset: Offset(0, (1 - visibility) * 32),
            child: _MapControlPills(
              quickButton: _quickButtonConfig(context),
              onLocate: _centerOnUser2D,
              onSettings: _openQuickSettings,
            ),
          ),
        ),
      ),
    );
  }

  /// What a press on the map opens: a point, or a stop.
  List<Widget> _buildMapOverlays() {
    final point = _longPressLatLng;
    final stop = _selectedStop;
    return [
      if (point != null)
        Positioned.fill(
          child: LongPressSelectionModal(
            key: ValueKey(point),
            latLng: point,
            isClosing: _isLongPressClosing,
            onSelectFrom: () => _onLongPressChoice(RouteFieldKind.from),
            onSelectTo: () => _onLongPressChoice(RouteFieldKind.to),
            onDismissRequested: _dismissLongPressOverlay,
            onClosed: _handleLongPressOverlayClosed,
          ),
        ),
      if (stop != null)
        Positioned.fill(
          child: StopSelectionModal(
            key: ValueKey(stop.id),
            stop: stop,
            stopTimes: _stopTimesPreview,
            isLoading: _isStopTimesLoading,
            errorMessage: _stopTimesError,
            isClosing: _isStopOverlayClosing,
            onSelectFrom: () => _onStopChoice(RouteFieldKind.from, stop),
            onSelectTo: () => _onStopChoice(RouteFieldKind.to, stop),
            onStopTimeTap: _onStopTimeSelected,
            onViewTimetable: () => _openStopTimetable(stop),
            onDismissRequested: _dismissStopOverlay,
            onClosed: _handleStopOverlayClosed,
          ),
        ),
    ];
  }

  /// The sheet over the map: a vehicle's trip, the map's own settings, or
  /// the search.
  Widget _buildSheet(_SheetLayout sheet) {
    if (_isTripFocus) {
      return _TripFocusBottomCard(
        drag: sheet.drag,
        onBack: _exitTripFocus,
        itinerary: _focusedItinerary,
        isLoading: _isTripFocusLoading,
        errorMessage: _tripFocusError,
        bottomSpacer: sheet.bottomBarHeight,
        onStopTap: _openStopDeparturesSheet,
        onRefresh: _refreshTripFocus,
        lastUpdated: _tripFocusLastUpdated,
      );
    }
    if (_isQuickSettings) {
      return _QuickSettingsBottomCard(
        drag: sheet.drag,
        onBack: _closeQuickSettings,
        bottomSpacer: sheet.bottomBarHeight,
        quickButtonAction: _quickButtonAction,
        quickButtonOptions: _quickButtonOptions(),
        showVehicles: _showVehicles,
        hideNonRealtime: _hideNonRealtimeVehicles,
        showStops: _showStops,
        vehicleModeVisibility: _vehicleModeVisibility,
        onQuickButtonChanged: _setQuickButtonAction,
        onShowVehiclesChanged: _setShowVehicles,
        onHideNonRealtimeChanged: _setHideNonRealtimeVehicles,
        onVehicleModeChanged: _setVehicleModeVisibility,
        onShowStopsChanged: _setShowStops,
        onOpenAllSettings: _openAllSettings,
      );
    }
    return _buildRouteCard(drag: sheet.drag);
  }

  /// The search, in both layouts. [drag] is how it moves over the map, and
  /// is left out where there is none.
  Widget _buildRouteCard({SheetDrag? drag}) {
    return BottomCard(
      drag: drag,
      isCollapsed: _isSheetCollapsed,
      fromCtrl: _fromCtrl,
      toCtrl: _toCtrl,
      onUnfocus: _unfocusInputs,
      onSwapRequested: _handleSwapRequested,
      options: _options,
      storedOptions: _storedOptions,
      capabilities: _capabilities,
      onOptionsChanged: _onOptionsChanged,
      onResetOptions: _resetOptions,
      onSaveOptionsAsDefault: () => unawaited(_saveOptionsAsDefault()),
      onAddViaStop: _openViaStopPicker,
      onFromPressed: () => unawaited(_openLocationSearch(RouteFieldKind.from)),
      onToPressed: () => unawaited(_openLocationSearch(RouteFieldKind.to)),
      routeFieldLink: _routeFieldLink,
      fromLoading: _isReverseGeocodeLoading(RouteFieldKind.from),
      toLoading: _isReverseGeocodeLoading(RouteFieldKind.to),
      onSearch: _search,
      timeSelectionLayerLink: _timeSelectionLayerLink,
      onTimeSelectionTap: _handleTimeSelectionTap,
      onTimeSelectionTapDown: _handleTimeSelectionTapDown,
      onTimeSelectionTapCancel: _handleTimeSelectionTapCancel,
      timeSelection: _timeSelection,
      recentTrips: _recentTrips,
      onRecentTripTap: _onRecentTripTap,
    );
  }

  Future<void> _search(TimeSelection timeSelection) async {
    if (_isSearching) return;

    _unfocusInputs();
    final fromText = _fromCtrl.text.trim();
    final toText = _toCtrl.text.trim();
    if (fromText.isEmpty || toText.isEmpty) {
      final msg = fromText.isEmpty && toText.isEmpty
          ? 'Please enter both locations'
          : fromText.isEmpty
          ? 'Please enter a starting point'
          : 'Please enter a destination';
      showValidationToast(context, msg);
      return;
    }

    setState(() => _isSearching = true);
    Haptics.mediumTick();

    TransitousLocationSuggestion? resolvedFrom = _fromSelection;
    TransitousLocationSuggestion? resolvedTo = _toSelection;

    if (resolvedFrom == null && fromText.length >= 3) {
      resolvedFrom = await _resolveSelectionFromQuery(RouteFieldKind.from);
    }

    if (resolvedTo == null && toText.length >= 3) {
      resolvedTo = await _resolveSelectionFromQuery(RouteFieldKind.to);
    }

    if (!mounted) return;
    if (resolvedFrom == null) {
      showValidationToast(context, 'Please select a starting point');
      setState(() => _isSearching = false);
      return;
    }

    if (resolvedTo == null) {
      showValidationToast(context, 'Please select a destination');
      setState(() => _isSearching = false);
      return;
    }

    LatLng? here;
    if (resolvedFrom.isMyLocation || resolvedTo.isMyLocation) {
      here = await _myLocationForSearch();
      if (!mounted) return;
      if (here == null) {
        setState(() => _isSearching = false);
        return;
      }
    }
    final from = resolvedFrom.isMyLocation ? here! : resolvedFrom.latLng;
    final to = resolvedTo.isMyLocation ? here! : resolvedTo.latLng;

    Navigator.of(context)
        .push(
          CupertinoPageRoute(
            builder: (_) => ItineraryListScreen(
              fromLat: from.latitude,
              fromLon: from.longitude,
              toLat: to.latitude,
              toLon: to.longitude,
              timeSelection: timeSelection,
              options: _options,
              // Not My Location: a trip saved from these results is reopened
              // from somewhere else, where it would name the wrong place.
              fromSelection: resolvedFrom.isMyLocation ? null : resolvedFrom,
              toSelection: resolvedTo.isMyLocation ? null : resolvedTo,
            ),
          ),
        )
        .then((_) {
          _unfocusInputs();
          setState(() => _isSearching = false);
          unawaited(_loadRecentTrips());
        });
  }

  /// Where the rider is, for a search with My Location at either end, or
  /// null — having said why — when there is nothing to plan from.
  ///
  /// The live fix, or a fresh one: the OS's cached position can be hours old,
  /// and a trip planned from there is planned from the wrong place.
  Future<LatLng?> _myLocationForSearch() async {
    if (!await _ensurePermissionOnDemand()) {
      if (mounted) {
        showValidationToast(
          context,
          'Location permission required to use My Location',
        );
      }
      return null;
    }
    final live = _lastUserLatLng;
    if (live != null) return live;
    try {
      final fresh = await LocationService.currentPosition();
      return LatLng(fresh.latitude, fresh.longitude);
    } catch (_) {
      if (mounted) showValidationToast(context, "Couldn't find where you are");
      return null;
    }
  }

  Future<TransitousLocationSuggestion?> _resolveSelectionFromQuery(
    RouteFieldKind kind,
  ) async {
    final current = _selectionFor(kind);
    if (current != null) return current;
    final query = _controllerFor(kind).text.trim();
    final coord = TransitousGeocodeService.tryParseLatLon(query);
    if (coord != null) {
      final suggestion = TransitousLocationSuggestion.fromLatLon(coord);
      if (!mounted) return suggestion;
      _setControllerText(kind, suggestion.name);
      _setSelection(kind, suggestion, notify: true);
      return suggestion;
    }
    if (query.length < 3) return null;

    try {
      final placeBias = _placeBiasLatLng();
      final results = await TransitousGeocodeService.fetchSuggestions(
        text: query,
        placeBias: placeBias,
      );
      final ordered = results;
      if (ordered.isEmpty) return null;
      final suggestion = ordered.first;
      if (!mounted) return suggestion;
      _setControllerText(kind, suggestion.name);
      _setSelection(kind, suggestion, notify: true);
      unawaited(_recordSavedPlace(suggestion));
      return suggestion;
    } catch (_) {
      return null;
    }
  }

  Future<void> _centerToUserKeepZoom() async {
    if (!_autoCenterEnabled) return;
    if (_controller == null || _lastUserLatLng == null) return;
    final cam = _lastCam;
    _lastCam = CameraPosition(
      target: _lastUserLatLng!,
      zoom: cam.zoom,
      tilt: 0.0,
      bearing: cam.bearing,
    );
    await _controller!.moveCamera(CameraUpdate.newCameraPosition(_lastCam));
  }

  double? _lastComputedCollapsedTop;
  double? _lastComputedExpandedTop;
  double? _lastBottomBarHeight;
  bool _isBottomBarResizeAnimating = false;
  bool _skipAutoCenterOnSnap = false;

  /// Above this drag speed (logical pixels per second) the sheet is being
  /// flung rather than placed, and follows the flick instead of the finger.
  static const double _kSheetFlingVelocity = 700.0;

  /// How far from a stop still counts as being on it, so a fling from a stop
  /// moves off it rather than snapping back.
  static const double _kSheetStopTolerance = 1.0;

  /// Where a drag should settle, given the stops this card has.
  ///
  /// A flick past the velocity threshold moves one stop in that direction, so
  /// a hard swipe from the middle does not skip the end; anything gentler
  /// settles on whichever stop is nearest.
  double _snapStopFor(double velocityDy, List<double> stops) {
    final sorted = [...stops]..sort();
    final current = _sheetTop ?? sorted.first;

    if (velocityDy.abs() > _kSheetFlingVelocity) {
      return _nextStopInFlingDirection(sorted, current, velocityDy > 0);
    }
    return _nearestStop(sorted, current);
  }

  /// The first stop past [current] in the flung direction, or the far end when
  /// there is none.
  double _nextStopInFlingDirection(
    List<double> sorted,
    double current,
    bool downwards,
  ) {
    if (downwards) {
      for (final stop in sorted) {
        if (stop > current + _kSheetStopTolerance) return stop;
      }
      return sorted.last;
    }
    for (final stop in sorted.reversed) {
      if (stop < current - _kSheetStopTolerance) return stop;
    }
    return sorted.first;
  }

  double _nearestStop(List<double> sorted, double current) {
    var best = sorted.first;
    for (final stop in sorted) {
      if ((stop - current).abs() < (best - current).abs()) best = stop;
    }
    return best;
  }

  /// Sends the sheet to whichever of its two stops it is not already at.
  void _toggleSheet(double expandedTop, double collapsedTop) {
    _unfocusInputs();
    _animateTo(_isSheetCollapsed ? expandedTop : collapsedTop, collapsedTop);
    _stopDragRumble();
  }

  void _onSheetDragStart() {
    _unfocusInputs();
    _snapCtrl.stop();
    _startDragRumble();
  }

  void _onSheetDragUpdate(double dy, double topStop, double collapsedTop) {
    setState(() => _sheetTop = (_sheetTop! + dy).clamp(topStop, collapsedTop));
  }

  void _onSheetDragEnd(
    double velocityDy,
    double expandedTop,
    double collapsedTop,
  ) {
    _animateTo(
      _snapStopFor(velocityDy, [expandedTop, collapsedTop]),
      collapsedTop,
    );
    _stopDragRumble();
  }

  void _animateTo(double target, double collapsedTop) {
    final begin = _sheetTop ?? target;
    _snapAnim = Tween<double>(begin: begin, end: target).animate(
      CurvedAnimation(parent: _snapCtrl, curve: SmallBackOutCurve(0.6)),
    );
    _snapCtrl
      ..stop()
      ..reset()
      ..forward();
    _snapTarget = target;
  }

  void _animateCollapsedHeightChange(
    double newBottomBarHeight, {
    bool suppressAutoCenter = false,
  }) {
    final lastTop = _lastComputedCollapsedTop;
    final lastHeight = _lastBottomBarHeight;
    if (lastTop == null || lastHeight == null) return;
    final currentTop = _sheetTop ?? lastTop;
    final isNearCollapsed =
        _isSheetCollapsed || (currentTop - lastTop).abs() < 8.0;
    if (!isNearCollapsed) return;
    final delta = newBottomBarHeight - lastHeight;
    if (delta.abs() < 0.5) return;
    if (suppressAutoCenter) {
      _skipAutoCenterOnSnap = true;
    }
    final target = lastTop - delta;
    _isBottomBarResizeAnimating = true;
    _animateTo(target, target);
  }

  Future<void> _initHapticCaps() async {
    _hasVibrator = await Haptics.hasVibrator();
    _hasCustomVibration = await Haptics.hasCustomVibrationsSupport();
    if (!mounted) return;
    setState(() {});
  }

  /// Longer than any real drag, and short enough that a missed stop is a
  /// blip rather than a phone that will not settle.
  ///
  /// The loop bounds itself rather than trusting every call site to remember
  /// to stop it.
  static const Duration _maxDragRumble = Duration(seconds: 4);

  void _startDragRumble() {
    _stopDragRumble();
    if (!_hasCustomVibration || !Haptics.isEnabled) return;
    _dragVibeTimer = Timer.periodic(_dragRumbleInterval, (_) {
      Haptics.dragRumblePulse();
    });
    _dragVibeDeadline = Timer(_maxDragRumble, _stopDragRumble);
  }

  void _stopDragRumble() {
    _dragVibeTimer?.cancel();
    _dragVibeTimer = null;
    _dragVibeDeadline?.cancel();
    _dragVibeDeadline = null;
  }

  void _handleFromTextChanged() => _handleTextChanged(RouteFieldKind.from);
  void _handleToTextChanged() => _handleTextChanged(RouteFieldKind.to);

  void _handleTextChanged(RouteFieldKind kind) {
    final isSuppressed = kind == RouteFieldKind.from
        ? _suppressFromListener
        : _suppressToListener;
    if (isSuppressed) return;
    final controller = _controllerFor(kind);
    final trimmed = controller.text.trim();
    final selection = _selectionFor(kind);
    if (selection != null && selection.name != trimmed) {
      _setSelection(kind, null, notify: true);
    }
  }

  void _setSelection(
    RouteFieldKind kind,
    TransitousLocationSuggestion? value, {
    bool notify = false,
  }) {
    final current = kind == RouteFieldKind.from ? _fromSelection : _toSelection;
    if (identical(current, value)) {
      if (notify && mounted) setState(() {});
      return;
    }
    if (kind == RouteFieldKind.from) {
      _fromSelection = value;
    } else {
      _toSelection = value;
    }
    if (notify && mounted) setState(() {});
    unawaited(_refreshRouteMarkers());
  }

  TransitousLocationSuggestion? _selectionFor(RouteFieldKind kind) {
    return kind == RouteFieldKind.from ? _fromSelection : _toSelection;
  }

  TextEditingController _controllerFor(RouteFieldKind kind) {
    return kind == RouteFieldKind.from ? _fromCtrl : _toCtrl;
  }

  LatLng? _placeBiasLatLng() {
    if (!_hasLocationPermission) return null;
    if (_lastUserLatLng != null) return _lastUserLatLng;
    if (_startCam.target != _initCam.target) return _startCam.target;
    return null;
  }

  /// Opens the place picker for one of the two fields.
  ///
  /// A screen rather than a dropdown: it has favourites, recents and results
  /// to show, and it can give each of them the room to be read.
  Future<void> _openLocationSearch(RouteFieldKind field) async {
    _unfocusInputs();
    _notifyOverlayVisibility(overlaysVisible: true);
    final picked = await Navigator.of(context)
        .push<TransitousLocationSuggestion>(
          CustomPageRoute(
            child: LocationSearchScreen(
              title: field == RouteFieldKind.from ? 'Origin' : 'Destination',
              bucket: SavedPlacesBucket.search,
              initialQuery: _controllerFor(field).text,
              placeBias: _placeBiasLatLng(),
              // Offered on both endpoints, and whether or not location has
              // been permitted yet: the row is how a rider finds out the app
              // can do this, and tapping it is what asks.
              showMyLocation: true,
            ),
          ),
        );
    if (!mounted) return;
    _notifyOverlayVisibility();
    if (picked == null) return;
    await _onSuggestionSelected(field, picked);
  }

  Future<void> _onSuggestionSelected(
    RouteFieldKind field,
    TransitousLocationSuggestion suggestion,
  ) async {
    if (suggestion.id == myLocationSuggestion.id) {
      await _applyMyLocation(field);
      return;
    }
    unawaited(_recordSavedPlace(suggestion));
    _setControllerText(field, suggestion.name);
    _setSelection(field, suggestion, notify: true);
    _openDestinationIfStillEmpty(field);
  }

  /// Puts My Location into [field], asking for the location permission it
  /// will need first.
  ///
  /// Not recorded as a recent place: a recent is replayed by its coordinates,
  /// and My Location has none of its own.
  Future<void> _applyMyLocation(RouteFieldKind field) async {
    if (!await _ensurePermissionOnDemand()) {
      if (!mounted) return;
      showValidationToast(
        context,
        'Location permission required to use My Location',
      );
      return;
    }
    if (!mounted) return;
    _setControllerText(field, myLocationName);
    _setSelection(field, myLocationSuggestion, notify: true);
    _openDestinationIfStillEmpty(field);
  }

  /// Picking an origin first is the common order, so the destination picker
  /// follows on rather than making the rider tap the field themselves.
  void _openDestinationIfStillEmpty(RouteFieldKind field) {
    if (field != RouteFieldKind.from) return;
    if (_toCtrl.text.trim().isNotEmpty) return;
    unawaited(_openLocationSearch(RouteFieldKind.to));
  }

  /// Fills the route fields with a journey another screen asked for.
  ///
  /// The search is not fired. Whoever sent this — an itinerary whose
  /// connection has just broken — knows where the rider is, not what they now
  /// want: a later train, a different destination, or to give up and walk.
  /// The fields arrive ready and the Search button stays theirs.
  void _applyPlanRequest() {
    // Read only when there is somewhere to put it: taking it first would
    // consume the request and drop it on the floor.
    if (!mounted || PlanRequests.pending.value == null) return;
    final request = PlanRequests.take()!;

    _setControllerText(RouteFieldKind.from, request.from.name);
    _setControllerText(RouteFieldKind.to, request.to.name);
    _setSelection(RouteFieldKind.from, request.from);
    _setSelection(RouteFieldKind.to, request.to);
    setState(() {
      _timeSelection = request.time;
      final options = request.options;
      if (options != null) {
        _options = options;
        _optionsTouched = options != _storedOptions;
      }
    });
    // Fields nobody can see are not filled in as far as the rider is
    // concerned, and the card may have been left down over the map.
    _expandSheetToCard();
  }

  /// Raises the route card, so fields filled from elsewhere are seen.
  void _expandSheetToCard() {
    final expandedTop = _lastComputedExpandedTop;
    final collapsedTop = _lastComputedCollapsedTop;
    if (expandedTop == null || collapsedTop == null) return;
    _animateTo(expandedTop, collapsedTop);
  }

  void _setControllerText(RouteFieldKind kind, String value) {
    if (kind == RouteFieldKind.from) {
      _suppressFromListener = true;
      _fromCtrl
        ..text = value
        ..selection = TextSelection.collapsed(offset: value.length);
      _suppressFromListener = false;
    } else {
      _suppressToListener = true;
      _toCtrl
        ..text = value
        ..selection = TextSelection.collapsed(offset: value.length);
      _suppressToListener = false;
    }
  }

  void _handleSwapRequested() {
    final fromText = _fromCtrl.text;
    _setControllerText(RouteFieldKind.from, _toCtrl.text);
    _setControllerText(RouteFieldKind.to, fromText);
    setState(() {
      final from = _fromSelection;
      _fromSelection = _toSelection;
      _toSelection = from;
    });
    unawaited(_refreshRouteMarkers());
    _maybeFitSelectionsOnCollapsed();
  }

  List<LatLng> _selectionLatLngs() => [
    for (final selection in [_fromSelection, _toSelection])
      if (_pointOf(selection) case final point?) point,
  ];

  /// Where a field's selection is on the map: My Location is wherever the
  /// rider is now, and nowhere until that is known.
  LatLng? _pointOf(TransitousLocationSuggestion? selection) {
    if (selection == null) return null;
    if (selection.isMyLocation) return _lastUserLatLng;
    return selection.latLng;
  }

  void _maybeFitSelectionsOnCollapsed() {
    if (!_isSheetCollapsed) return;
    if (_isTripFocus) return;
    if (!_autoCenterEnabled) return;
    unawaited(_fitSelectionBounds());
  }

  Future<void> _fitSelectionBounds() async {
    if (_isTripFocus) return;
    final controller = _controller;
    if (controller == null) return;
    final points = _selectionLatLngs();
    if (points.isEmpty) return;
    if (points.length == 1) {
      await controller.animateCamera(CameraUpdate.newLatLng(points.first));
      return;
    }
    final bounds = boundsOf(points)!;
    final double bottomPadding = _isSheetCollapsed
        ? (_bottomBarHeight + 64.0)
        : 48.0;
    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        bounds,
        left: 48,
        top: 48,
        right: 48,
        bottom: bottomPadding,
      ),
    );
  }

  Future<void> _removeRouteSymbols() async {
    final controller = _controller;
    if (controller == null) return;
    final symbols = [_fromSymbol, _toSymbol];
    _fromSymbol = null;
    _toSymbol = null;
    for (final symbol in symbols) {
      if (symbol == null) continue;
      try {
        await controller.removeSymbol(symbol);
      } catch (_) {}
    }
  }

  Future<void> _refreshRouteMarkers({bool allowFit = true}) async {
    final controller = _controller;
    if (controller == null) return;
    if (_isTripFocus) {
      await _removeRouteSymbols();
      return;
    }
    await _ensureMarkerImages();
    final token = ++_markerRefreshToken;

    Future<void> removeSymbol(Symbol? symbol) async {
      if (symbol == null) return;
      try {
        await controller.removeSymbol(symbol);
      } catch (_) {}
    }

    final prevFrom = _fromSymbol;
    final prevTo = _toSymbol;
    _fromSymbol = null;
    _toSymbol = null;
    await removeSymbol(prevFrom);
    await removeSymbol(prevTo);
    if (_isTripFocus) return;

    Future<Symbol?> addSymbol(
      TransitousLocationSuggestion? selection,
      String imageId,
    ) async {
      // The location dot already marks My Location.
      if (selection == null || selection.isMyLocation) return null;
      try {
        return await controller.addSymbol(
          SymbolOptions(
            geometry: selection.latLng,
            iconImage: imageId,
            iconSize: 1.0,
            iconAnchor: 'bottom',
          ),
        );
      } catch (_) {
        return null;
      }
    }

    final newFrom = await addSymbol(_fromSelection, _kFromMarkerId);
    final newTo = await addSymbol(_toSelection, _kToMarkerId);

    if (_markerRefreshToken != token) {
      await removeSymbol(newFrom);
      await removeSymbol(newTo);
      return;
    }

    _fromSymbol = newFrom;
    _toSymbol = newTo;
    if (allowFit) {
      _maybeFitSelectionsOnCollapsed();
    }
  }

  static const String _kFromMarkerId = 'route-marker-from';
  static const String _kToMarkerId = 'route-marker-to';
  static const String _kStopsSourceId = 'map-stops-source';
  static const String _kStopsLayerId = 'map-stops-layer';
  static const String _kVehiclesSourceId = 'map-vehicles-source';
  static const String _kVehiclesLayerId = 'map-vehicles-layer';
  static const String _kFocusedVehiclesSourceId = 'map-focused-vehicles-source';
  static const String _kFocusedVehiclesLayerId = 'map-focused-vehicles-layer';
  static const String _kFocusedStopsSourceId = 'map-focused-stops-source';
  static const String _kFocusedStopsLayerId = 'map-focused-stops-layer';
  static const String _kFocusedRouteSourceId = 'map-focused-route-source';
  static const String _kFocusedRouteLayerId = 'map-focused-route-layer';

  Future<void> _ensureMarkerImages() async {
    if (_didAddMarkerImages) return;
    final controller = _controller;
    if (controller == null) return;
    Future<void> addMarker(String id, Color color, IconData icon) async {
      final image = await buildBubbleMarkerImage(color, icon);
      await controller.addImage(id, image);
    }

    try {
      await addMarker(
        _kFromMarkerId,
        const Color(0xFF0B8F96),
        LucideIcons.mapPin,
      );
      await addMarker(_kToMarkerId, const Color(0xFFD04E37), LucideIcons.flag);
      _didAddMarkerImages = true;
    } catch (_) {
      _didAddMarkerImages = false;
    }
  }

  String _stopMarkerImageIdForColor(Color color) {
    final colorHex = colorToHex(color).replaceAll('#', '');
    return 'map-stop-marker-$colorHex';
  }

  Future<String?> _ensureStopMarkerImageForColor(Color color) async {
    final controller = _controller;
    if (controller == null || !_isMapReady) return null;
    final imageId = _stopMarkerImageIdForColor(color);
    if (_stopMarkerImages.contains(imageId)) {
      _stopMarkerImageId = imageId;
      return imageId;
    }
    try {
      final image = await buildStopMarkerImage(color);
      await controller.addImage(imageId, image);
      _stopMarkerImages.add(imageId);
      _stopMarkerImageId = imageId;
      return imageId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _applyStopAccentColor() async {
    final color = _stopAccentColor ?? AppColors.accentOf(context);
    final imageId = await _ensureStopMarkerImageForColor(color);
    if (imageId == null) return;
    if (_didAddStopsLayer && _visibleStops.isNotEmpty) {
      await _setStopsSource(_visibleStops.values.toList());
    }
    if (_didAddFocusedStopsLayer && _focusedStops.isNotEmpty) {
      await _setFocusedStopsSource(_focusedStops.values.toList());
    }
  }

  _VehicleMarkerVisual _vehicleMarkerVisual(_TripSegmentData data) {
    final trimmed = data.label.trim();
    final condensed = trimmed.replaceAll(RegExp(r'\s+'), '');
    if (condensed.isNotEmpty && condensed.length <= 4) {
      return _VehicleMarkerVisual.text(condensed);
    }
    return _VehicleMarkerVisual.icon(getLegIcon(data.mode));
  }

  String _vehicleMarkerImageId(_VehicleMarkerVisual visual, Color color) {
    final colorHex = colorToHex(color).replaceAll('#', '');
    final rawKey = visual.text ?? 'icon-${visual.icon?.codePoint ?? 0}';
    final key = rawKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    return 'vehicle-$colorHex-$key';
  }

  Future<String?> _ensureVehicleMarkerImage(
    _VehicleMarkerVisual visual,
    Color color,
  ) async {
    final controller = _controller;
    if (controller == null || !_isMapReady) return null;
    final imageId = _vehicleMarkerImageId(visual, color);
    if (_vehicleMarkerImages.contains(imageId)) return imageId;
    try {
      final image = await _buildVehicleMarkerImage(visual, color);
      await controller.addImage(imageId, image);
      _vehicleMarkerImages.add(imageId);
      return imageId;
    } catch (_) {
      return null;
    }
  }

  Future<Uint8List> _buildVehicleMarkerImage(
    _VehicleMarkerVisual visual,
    Color color,
  ) async {
    const double size = 44;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);

    final fillPaint = Paint()..color = color;
    canvas.drawCircle(center, size / 2 - 2, fillPaint);

    final strokePaint = Paint()
      ..color = AppColors.solidWhite
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, size / 2 - 3, strokePaint);

    if (visual.text != null) {
      final text = visual.text!.toUpperCase();
      final fontSize = text.length <= 2 ? 16.5 : 14.0;
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
            color: AppColors.solidWhite,
          ),
        ),
      )..layout();
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
    } else if (visual.icon != null) {
      final icon = visual.icon!;
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: 22,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: AppColors.solidWhite,
          ),
        ),
      )..layout();
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
    }

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  List<Object> _vehicleIconSizeExpression() {
    return [
      Expressions.interpolate,
      ['linear'],
      [Expressions.zoom],
      12.0,
      1.0,
      14.0,
      1.25,
      16.0,
      1.6,
      18.0,
      2.05,
      20.0,
      2.45,
    ];
  }

  List<Object> _stopIconSizeExpression() {
    return [
      Expressions.interpolate,
      ['linear'],
      [Expressions.zoom],
      11.0,
      0.55,
      13.0,
      0.7,
      15.0,
      0.85,
      17.0,
      1.0,
    ];
  }

  Map<String, dynamic> _emptyFeatureCollection() {
    return const {'type': 'FeatureCollection', 'features': []};
  }

  Map<String, dynamic> _stopFeature(MapStop stop, String iconId) {
    return {
      'type': 'Feature',
      'id': stop.id,
      'properties': {
        'id': stop.id,
        'importance': stop.importance ?? 0.0,
        'iconId': iconId,
      },
      'geometry': {
        'type': 'Point',
        'coordinates': [stop.lon, stop.lat],
      },
    };
  }

  Map<String, dynamic> _vehicleFeature(
    String tripId,
    _VehicleMarker marker,
    LatLng position,
  ) {
    return {
      'type': 'Feature',
      'id': tripId,
      'properties': {'id': tripId, 'iconId': marker.imageId},
      'geometry': {
        'type': 'Point',
        'coordinates': [position.longitude, position.latitude],
      },
    };
  }

  Future<void> _ensureStopsLayer() async {
    if (_didAddStopsLayer) return;
    final inFlight = _stopsLayerInit;
    if (inFlight != null) return inFlight;
    final completer = Completer<void>();
    _stopsLayerInit = completer.future;
    final controller = _controller;
    try {
      if (controller == null || !_isMapReady) return;
      await _ensureVehicleLayer();
      final color = _stopAccentColor ?? AppColors.accentOf(context);
      final imageId = await _ensureStopMarkerImageForColor(color);
      if (imageId == null) return;
      Set<String> sourceIds;
      Set<String> layerIds;
      try {
        sourceIds = (await controller.getSourceIds()).cast<String>().toSet();
        layerIds = (await controller.getLayerIds()).cast<String>().toSet();
      } catch (_) {
        return;
      }
      final hasSource = sourceIds.contains(_kStopsSourceId);
      final hasLayer = layerIds.contains(_kStopsLayerId);
      if (hasSource && hasLayer) {
        _didAddStopsLayer = true;
        _applyStopsLayerVisibility();
        return;
      }
      if (!hasSource) {
        await controller.addGeoJsonSource(
          _kStopsSourceId,
          _emptyFeatureCollection(),
          promoteId: 'id',
        );
      }
      if (hasLayer) {
        _didAddStopsLayer = true;
        _applyStopsLayerVisibility();
        return;
      }
      await controller.addSymbolLayer(
        _kStopsSourceId,
        _kStopsLayerId,
        SymbolLayerProperties(
          iconImage: [Expressions.get, 'iconId'],
          iconSize: _stopIconSizeExpression(),
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconAnchor: 'center',
          symbolSortKey: [Expressions.get, 'importance'],
        ),
        belowLayerId: _didAddVehiclesLayer ? _kVehiclesLayerId : null,
        enableInteraction: true,
      );
      _didAddStopsLayer = true;
      _applyStopsLayerVisibility();
    } catch (_) {
      _didAddStopsLayer = false;
    } finally {
      _stopsLayerInit = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> _ensureVehicleLayer() async {
    if (_didAddVehiclesLayer) return;
    final inFlight = _vehicleLayerInit;
    if (inFlight != null) return inFlight;
    final completer = Completer<void>();
    _vehicleLayerInit = completer.future;
    final controller = _controller;
    try {
      if (controller == null || !_isMapReady) return;
      Set<String> sourceIds;
      Set<String> layerIds;
      try {
        sourceIds = (await controller.getSourceIds()).cast<String>().toSet();
        layerIds = (await controller.getLayerIds()).cast<String>().toSet();
      } catch (_) {
        return;
      }
      final hasSource = sourceIds.contains(_kVehiclesSourceId);
      final hasLayer = layerIds.contains(_kVehiclesLayerId);
      if (hasSource && hasLayer) {
        _didAddVehiclesLayer = true;
        _applyVehiclesLayerVisibility();
        return;
      }
      if (!hasSource) {
        await controller.addGeoJsonSource(
          _kVehiclesSourceId,
          _emptyFeatureCollection(),
          promoteId: 'id',
        );
      }
      if (hasLayer) {
        _didAddVehiclesLayer = true;
        _applyVehiclesLayerVisibility();
        return;
      }
      await controller.addSymbolLayer(
        _kVehiclesSourceId,
        _kVehiclesLayerId,
        SymbolLayerProperties(
          iconImage: [Expressions.get, 'iconId'],
          iconSize: _vehicleIconSizeExpression(),
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconAnchor: 'center',
          symbolSortKey: 1000,
        ),
        enableInteraction: true,
      );
      _didAddVehiclesLayer = true;
      _applyVehiclesLayerVisibility();
    } catch (_) {
      _didAddVehiclesLayer = false;
    } finally {
      _vehicleLayerInit = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> _ensureFocusedVehiclesLayer() async {
    if (_didAddFocusedVehiclesLayer) return;
    final inFlight = _focusedVehiclesLayerInit;
    if (inFlight != null) return inFlight;
    final completer = Completer<void>();
    _focusedVehiclesLayerInit = completer.future;
    final controller = _controller;
    try {
      if (controller == null || !_isMapReady) return;
      Set<String> sourceIds;
      Set<String> layerIds;
      try {
        sourceIds = (await controller.getSourceIds()).cast<String>().toSet();
        layerIds = (await controller.getLayerIds()).cast<String>().toSet();
      } catch (_) {
        return;
      }
      final hasSource = sourceIds.contains(_kFocusedVehiclesSourceId);
      final hasLayer = layerIds.contains(_kFocusedVehiclesLayerId);
      if (hasSource && hasLayer) {
        _didAddFocusedVehiclesLayer = true;
        _applyFocusedVehiclesLayerVisibility();
        return;
      }
      if (!hasSource) {
        await controller.addGeoJsonSource(
          _kFocusedVehiclesSourceId,
          _emptyFeatureCollection(),
          promoteId: 'id',
        );
      }
      if (hasLayer) {
        _didAddFocusedVehiclesLayer = true;
        _applyFocusedVehiclesLayerVisibility();
        return;
      }
      await controller.addSymbolLayer(
        _kFocusedVehiclesSourceId,
        _kFocusedVehiclesLayerId,
        SymbolLayerProperties(
          iconImage: [Expressions.get, 'iconId'],
          iconSize: _vehicleIconSizeExpression(),
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconAnchor: 'center',
          symbolSortKey: 1200,
        ),
        enableInteraction: true,
      );
      _didAddFocusedVehiclesLayer = true;
      _applyFocusedVehiclesLayerVisibility();
    } catch (_) {
      _didAddFocusedVehiclesLayer = false;
    } finally {
      _focusedVehiclesLayerInit = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> _ensureFocusedStopsLayer() async {
    if (_didAddFocusedStopsLayer) return;
    final inFlight = _focusedStopsLayerInit;
    if (inFlight != null) return inFlight;
    final completer = Completer<void>();
    _focusedStopsLayerInit = completer.future;
    final controller = _controller;
    try {
      if (controller == null || !_isMapReady) return;
      await _ensureFocusedVehiclesLayer();
      final color = _stopAccentColor ?? AppColors.accentOf(context);
      final imageId = await _ensureStopMarkerImageForColor(color);
      if (imageId == null) return;
      Set<String> sourceIds;
      Set<String> layerIds;
      try {
        sourceIds = (await controller.getSourceIds()).cast<String>().toSet();
        layerIds = (await controller.getLayerIds()).cast<String>().toSet();
      } catch (_) {
        return;
      }
      final hasSource = sourceIds.contains(_kFocusedStopsSourceId);
      final hasLayer = layerIds.contains(_kFocusedStopsLayerId);
      if (hasSource && hasLayer) {
        _didAddFocusedStopsLayer = true;
        _applyFocusedStopsLayerVisibility();
        return;
      }
      if (!hasSource) {
        await controller.addGeoJsonSource(
          _kFocusedStopsSourceId,
          _emptyFeatureCollection(),
          promoteId: 'id',
        );
      }
      if (hasLayer) {
        _didAddFocusedStopsLayer = true;
        _applyFocusedStopsLayerVisibility();
        return;
      }
      await controller.addSymbolLayer(
        _kFocusedStopsSourceId,
        _kFocusedStopsLayerId,
        SymbolLayerProperties(
          iconImage: [Expressions.get, 'iconId'],
          iconSize: _stopIconSizeExpression(),
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          iconAnchor: 'center',
          symbolSortKey: [Expressions.get, 'importance'],
        ),
        belowLayerId: _kFocusedVehiclesLayerId,
        enableInteraction: false,
      );
      _didAddFocusedStopsLayer = true;
      _applyFocusedStopsLayerVisibility();
    } catch (_) {
      _didAddFocusedStopsLayer = false;
    } finally {
      _focusedStopsLayerInit = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<void> _ensureFocusedRouteLayer() async {
    if (_didAddFocusedRouteLayer) return;
    final inFlight = _focusedRouteLayerInit;
    if (inFlight != null) return inFlight;
    final completer = Completer<void>();
    _focusedRouteLayerInit = completer.future;
    final controller = _controller;
    try {
      if (controller == null || !_isMapReady) return;
      await _ensureFocusedStopsLayer();
      Set<String> sourceIds;
      Set<String> layerIds;
      try {
        sourceIds = (await controller.getSourceIds()).cast<String>().toSet();
        layerIds = (await controller.getLayerIds()).cast<String>().toSet();
      } catch (_) {
        return;
      }
      final hasSource = sourceIds.contains(_kFocusedRouteSourceId);
      final hasLayer = layerIds.contains(_kFocusedRouteLayerId);
      if (hasSource && hasLayer) {
        _didAddFocusedRouteLayer = true;
        _applyFocusedRouteVisibility();
        return;
      }
      if (!hasSource) {
        await controller.addGeoJsonSource(
          _kFocusedRouteSourceId,
          _emptyFeatureCollection(),
          promoteId: 'id',
        );
      }
      if (hasLayer) {
        _didAddFocusedRouteLayer = true;
        _applyFocusedRouteVisibility();
        return;
      }
      await controller.addLineLayer(
        _kFocusedRouteSourceId,
        _kFocusedRouteLayerId,
        LineLayerProperties(
          lineColor: [Expressions.get, 'color'],
          lineWidth: [
            Expressions.interpolate,
            ['linear'],
            [Expressions.zoom],
            11.0,
            2.2,
            14.0,
            3.4,
            17.0,
            4.6,
            20.0,
            6.0,
          ],
          lineJoin: 'round',
          lineCap: 'round',
        ),
        belowLayerId: _kFocusedStopsLayerId,
        enableInteraction: false,
      );
      _didAddFocusedRouteLayer = true;
      _applyFocusedRouteVisibility();
    } catch (_) {
      _didAddFocusedRouteLayer = false;
    } finally {
      _focusedRouteLayerInit = null;
      if (!completer.isCompleted) completer.complete();
    }
  }

  void _applyStopsLayerVisibility() {
    final controller = _controller;
    if (controller == null || !_didAddStopsLayer) return;
    unawaited(controller.setLayerVisibility(_kStopsLayerId, _showStops));
  }

  void _applyVehiclesLayerVisibility() {
    final controller = _controller;
    if (controller == null || !_didAddVehiclesLayer) return;
    unawaited(
      controller.setLayerVisibility(
        _kVehiclesLayerId,
        !_isTripFocus && _showVehicles,
      ),
    );
  }

  void _applyFocusedVehiclesLayerVisibility() {
    final controller = _controller;
    if (controller == null || !_didAddFocusedVehiclesLayer) return;
    unawaited(
      controller.setLayerVisibility(_kFocusedVehiclesLayerId, _isTripFocus),
    );
  }

  void _applyFocusedStopsLayerVisibility() {
    final controller = _controller;
    if (controller == null || !_didAddFocusedStopsLayer) return;
    unawaited(
      controller.setLayerVisibility(_kFocusedStopsLayerId, _isTripFocus),
    );
  }

  void _applyFocusedRouteVisibility() {
    final controller = _controller;
    if (controller == null || !_didAddFocusedRouteLayer) return;
    unawaited(
      controller.setLayerVisibility(_kFocusedRouteLayerId, _isTripFocus),
    );
  }

  Future<void> _setStopsSource(List<MapStop> stops) async {
    final controller = _controller;
    if (controller == null || !_didAddStopsLayer) return;
    final color = _stopAccentColor ?? AppColors.accentOf(context);
    final desiredId = _stopMarkerImageIdForColor(color);
    final imageId = _stopMarkerImageId == desiredId
        ? _stopMarkerImageId
        : await _ensureStopMarkerImageForColor(color);
    if (imageId == null) return;
    final features = stops.map((stop) => _stopFeature(stop, imageId)).toList();
    try {
      await controller.setGeoJsonSource(_kStopsSourceId, {
        'type': 'FeatureCollection',
        'features': features,
      });
    } catch (_) {}
  }

  Future<void> _setFocusedStopsSource(List<MapStop> stops) async {
    final controller = _controller;
    if (controller == null || !_didAddFocusedStopsLayer) return;
    final color =
        _focusedStopsColor ?? _stopAccentColor ?? AppColors.accentOf(context);
    final desiredId = _stopMarkerImageIdForColor(color);
    final imageId = _stopMarkerImageId == desiredId
        ? _stopMarkerImageId
        : await _ensureStopMarkerImageForColor(color);
    if (imageId == null) return;
    final features = stops.map((stop) => _stopFeature(stop, imageId)).toList();
    try {
      await controller.setGeoJsonSource(_kFocusedStopsSourceId, {
        'type': 'FeatureCollection',
        'features': features,
      });
    } catch (_) {}
  }

  Future<void> _setFocusedRoute(Itinerary itinerary) async {
    final controller = _controller;
    if (controller == null || !_isMapReady) return;
    await _ensureFocusedRouteLayer();
    if (!_didAddFocusedRouteLayer) return;
    final features = <Map<String, dynamic>>[];
    for (int i = 0; i < itinerary.legs.length; i++) {
      final leg = itinerary.legs[i];
      final legColor =
          parseHexColor(leg.routeColor?.trim()) ?? _currentAccentColor();
      final colorHex = colorToHex(legColor);
      final geometry = leg.legGeometry;
      List<LatLng> points = [];
      if (geometry != null && geometry.points.isNotEmpty) {
        try {
          points = decodePolyline(geometry.points, geometry.precision);
        } catch (_) {
          points = [];
        }
      }
      if (points.length < 2) {
        if (leg.fromLat != 0.0 ||
            leg.fromLon != 0.0 ||
            leg.toLat != 0.0 ||
            leg.toLon != 0.0) {
          points = [
            LatLng(leg.fromLat, leg.fromLon),
            LatLng(leg.toLat, leg.toLon),
          ];
        }
      }
      if (points.length < 2) continue;
      features.add({
        'type': 'Feature',
        'id': 'route-$i',
        'properties': {'color': colorHex},
        'geometry': {
          'type': 'LineString',
          'coordinates': [
            for (final p in points) [p.longitude, p.latitude],
          ],
        },
      });
    }
    try {
      await controller.setGeoJsonSource(_kFocusedRouteSourceId, {
        'type': 'FeatureCollection',
        'features': features,
      });
    } catch (_) {}
  }

  Future<void> _setFocusedStops(Itinerary itinerary) async {
    final controller = _controller;
    if (controller == null || !_isMapReady) return;
    await _ensureFocusedStopsLayer();
    if (!_didAddFocusedStopsLayer) return;
    final stops = _buildFocusedStops(itinerary);
    _focusedStops
      ..clear()
      ..addAll(stops);
    if (_focusedStops.isEmpty) return;
    await _setFocusedStopsSource(_focusedStops.values.toList());
  }

  Map<String, MapStop> _buildFocusedStops(Itinerary itinerary) {
    final deduped = <String, MapStop>{};

    void addStop(String name, double lat, double lon, String? stopId) {
      if (name.trim().isEmpty) return;
      if (lat == 0.0 && lon == 0.0) return;
      final key = (stopId != null && stopId.isNotEmpty)
          ? stopId
          : '${lat.toStringAsFixed(6)}:${lon.toStringAsFixed(6)}';
      if (deduped.containsKey(key)) return;
      deduped[key] = MapStop(
        id: key,
        name: name,
        lat: lat,
        lon: lon,
        stopId: stopId,
      );
    }

    for (final leg in itinerary.legs) {
      addStop(leg.fromName, leg.fromLat, leg.fromLon, null);
      for (final stop in leg.intermediateStops) {
        addStop(stop.name, stop.lat, stop.lon, stop.stopId);
      }
      addStop(leg.toName, leg.toLat, leg.toLon, null);
    }
    return deduped;
  }

  Future<void> _fitCameraToFocusedItinerary(Itinerary itinerary) async {
    final controller = _controller;
    if (controller == null || !_isMapReady) return;
    final points = <LatLng>[];
    for (final leg in itinerary.legs) {
      final geometry = leg.legGeometry;
      if (geometry != null && geometry.points.isNotEmpty) {
        try {
          points.addAll(decodePolyline(geometry.points, geometry.precision));
          continue;
        } catch (_) {}
      }
      if (leg.fromLat != 0.0 || leg.fromLon != 0.0) {
        points.add(LatLng(leg.fromLat, leg.fromLon));
      }
      if (leg.toLat != 0.0 || leg.toLon != 0.0) {
        points.add(LatLng(leg.toLat, leg.toLon));
      }
    }
    final bounds = boundsOf(points);
    if (bounds == null) return;
    final center = boundsCenter(bounds);
    if (points.length == 1) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(center, _focusedTransferZoomLevel),
      );
      return;
    }

    final approxDistance = coordinateDistanceInMeters(
      points.first.latitude,
      points.first.longitude,
      points.last.latitude,
      points.last.longitude,
    );
    if (approxDistance <= _focusedTransferDistanceThresholdMeters) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(center, _focusedTransferZoomLevel),
      );
      return;
    }

    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngBounds(
          bounds,
          left: 48,
          top: 64,
          right: 48,
          bottom: 220,
        ),
      );
    } catch (_) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(center, _focusedTransferZoomLevel),
      );
    }
  }

  Future<void> _clearFocusedRoute() async {
    final controller = _controller;
    if (controller == null || !_didAddFocusedRouteLayer) return;
    try {
      await controller.setGeoJsonSource(
        _kFocusedRouteSourceId,
        _emptyFeatureCollection(),
      );
    } catch (_) {}
  }

  Future<void> _clearFocusedVehicles() async {
    final controller = _controller;
    if (controller == null) return;
    _focusedVehicles.clear();
    if (!_didAddFocusedVehiclesLayer) return;
    try {
      await controller.setGeoJsonSource(
        _kFocusedVehiclesSourceId,
        _emptyFeatureCollection(),
      );
    } catch (_) {}
  }

  Future<void> _clearFocusedStops() async {
    final controller = _controller;
    if (controller == null) return;
    _focusedStops.clear();
    if (!_didAddFocusedStopsLayer) return;
    try {
      await controller.setGeoJsonSource(
        _kFocusedStopsSourceId,
        _emptyFeatureCollection(),
      );
    } catch (_) {}
  }

  Future<void> _pushVehicleSource(DateTime now) async {
    final controller = _controller;
    if (controller == null || !_didAddVehiclesLayer || _isTripFocus) return;
    if (_vehicles.isEmpty) {
      try {
        await controller.setGeoJsonSource(
          _kVehiclesSourceId,
          _emptyFeatureCollection(),
        );
      } catch (_) {}
      return;
    }

    final features = <Map<String, dynamic>>[];
    for (final entry in _vehicles.entries) {
      final marker = entry.value;
      final position =
          marker.lastPosition ?? _positionAlongSegment(marker.segmentData, now);
      features.add(_vehicleFeature(entry.key, marker, position));
    }
    try {
      await controller.setGeoJsonSource(_kVehiclesSourceId, {
        'type': 'FeatureCollection',
        'features': features,
      });
    } catch (_) {}
  }

  void _onMapLongClick(math.Point<double> point, LatLng coordinate) {
    if (!_isSheetCollapsed) return;
    Haptics.mediumTick();
    _dismissStopOverlay();
    setState(() {
      _longPressLatLng = coordinate;
      _isLongPressClosing = false;
      _pendingReverseGeocodeKeys.clear();
    });
  }

  void _dismissLongPressOverlay({bool animated = true}) {
    if (_longPressLatLng == null) return;
    if (!animated) {
      setState(() {
        _longPressLatLng = null;
        _isLongPressClosing = false;
      });
      return;
    }
    if (_isLongPressClosing) return;
    setState(() => _isLongPressClosing = true);
  }

  void _handleLongPressOverlayClosed() {
    setState(() {
      _isLongPressClosing = false;
      _longPressLatLng = null;
    });
  }

  void _onLongPressChoice(RouteFieldKind kind) {
    final latLng = _longPressLatLng;
    if (latLng == null) return;
    Haptics.lightTick();
    _setReverseGeocodeLoading(kind, true);
    _dismissLongPressOverlay();
    _pendingReverseGeocodeKeys[kind] = _latLngKey(latLng);
    unawaited(_applyLongPressSelection(kind, latLng));
  }

  Future<void> _applyLongPressSelection(
    RouteFieldKind kind,
    LatLng latLng,
  ) async {
    TransitousLocationSuggestion? suggestion;
    try {
      suggestion = await TransitousGeocodeService.reverseGeocode(place: latLng);
    } catch (_) {
      suggestion = null;
    }
    if (!mounted) return;

    final pendingKey = _pendingReverseGeocodeKeys[kind];
    final thisKey = _latLngKey(latLng);
    if (pendingKey != thisKey) {
      if (pendingKey == null) {
        _setReverseGeocodeLoading(kind, false);
      }
      return;
    }
    _pendingReverseGeocodeKeys.remove(kind);

    suggestion ??= TransitousLocationSuggestion(
      id: 'reverse-${latLng.latitude.toStringAsFixed(6)}-${latLng.longitude.toStringAsFixed(6)}',
      name: _formatLatLngLabel(latLng),
      lat: latLng.latitude,
      lon: latLng.longitude,
      type: 'PLACE',
    );

    _setControllerText(kind, suggestion.name);
    _setSelection(kind, suggestion, notify: true);
    _maybeFitSelectionsOnCollapsed();
    _setReverseGeocodeLoading(kind, false);
  }

  void _handleFeatureTapped(
    math.Point<double> point,
    LatLng coordinate,
    String id,
    String layerId,
    Annotation? annotation,
  ) {
    if (layerId == _kVehiclesLayerId || layerId == _kFocusedVehiclesLayerId) {
      if (_isTripFocus) return;
      Haptics.lightTick();
      _enterTripFocus(id);
      return;
    }
    if (layerId != _kStopsLayerId) return;
    if (!_isSheetCollapsed) return;
    final stop = _visibleStops[id];
    if (stop == null) return;
    Haptics.lightTick();
    _dismissLongPressOverlay();
    setState(() {
      _selectedStop = stop;
      _isStopOverlayClosing = false;
      _stopTimesPreview = [];
      _stopTimesError = null;
      _isStopTimesLoading = true;
    });
    unawaited(_loadStopTimesPreview(stop));
  }

  void _enterTripFocus(String tripId) {
    if (tripId.isEmpty) return;
    _showStopsBeforeFocus = _showStops;
    _animateCollapsedHeightChange(_tripFocusBottomBarHeight);
    setState(() {
      _isTripFocus = true;
      _isQuickSettings = false;
      _isTripFocusLoading = true;
      _tripFocusError = null;
      _focusedTripId = tripId;
      _focusedItinerary = null;
      _tripFocusLastUpdated = null;
      _focusedStopsColor = null;
      _showStops = false;
    });
    _unfocusInputs();
    _closeTimeSelectionOverlay();
    _dismissStopOverlay(animated: false);
    _dismissLongPressOverlay(animated: false);
    unawaited(_removeRouteSymbols());
    _applyStopsLayerVisibility();
    _applyVehiclesLayerVisibility();
    _applyFocusedVehiclesLayerVisibility();
    _applyFocusedStopsLayerVisibility();
    _applyFocusedRouteVisibility();
    unawaited(_clearFocusedRoute());
    unawaited(_clearFocusedVehicles());
    unawaited(_clearFocusedStops());
    _focusedRouteKeys.clear();
    _focusedRouteColors.clear();
    _focusedTripIds.clear();
    _lastTripsRequestKey = null;
    _lastStopsRequestKey = null;
    unawaited(_loadFocusedTripDetails(tripId));
    unawaited(_refreshFocusedTripVehicles(force: true));
  }

  void _exitTripFocus() {
    _animateCollapsedHeightChange(_bottomBarHeight, suppressAutoCenter: true);
    setState(() {
      _isTripFocus = false;
      _isTripFocusLoading = false;
      _tripFocusError = null;
      _focusedTripId = null;
      _focusedItinerary = null;
      _tripFocusLastUpdated = null;
      _focusedStopsColor = null;
      _showStops = _showStopsBeforeFocus;
    });
    _lastTripsRequestKey = null;
    _lastStopsRequestKey = null;
    unawaited(_clearFocusedRoute());
    unawaited(_clearFocusedVehicles());
    unawaited(_clearFocusedStops());
    _focusedRouteKeys.clear();
    _focusedRouteColors.clear();
    _focusedTripIds.clear();
    _applyStopsLayerVisibility();
    _applyVehiclesLayerVisibility();
    _applyFocusedVehiclesLayerVisibility();
    _applyFocusedStopsLayerVisibility();
    _applyFocusedRouteVisibility();
    unawaited(_refreshRouteMarkers(allowFit: false));
    _scheduleTripRefresh();
    _scheduleStopRefresh();
  }

  void _openStopDeparturesSheet({
    required String? stopId,
    required String stopName,
    required DateTime referenceTime,
  }) => showStopDeparturesSheet(
    context,
    stopId: stopId,
    stopName: stopName,
    referenceTime: referenceTime,
  );

  void _openQuickSettings() {
    if (_isQuickSettings) return;
    _unfocusInputs();
    _closeTimeSelectionOverlay();
    _dismissStopOverlay(animated: false);
    _dismissLongPressOverlay(animated: false);
    setState(() => _isQuickSettings = true);
    final expandedTop = _lastComputedExpandedTop;
    final collapsedTop = _lastComputedCollapsedTop;
    if (expandedTop != null && collapsedTop != null) {
      _animateTo(expandedTop, collapsedTop);
      _stopDragRumble();
    }
  }

  void _closeQuickSettings() {
    if (!_isQuickSettings) return;
    _animateCollapsedHeightChange(_bottomBarHeight);
    setState(() => _isQuickSettings = false);
  }

  Future<void> _loadFocusedTripDetails(String tripId) async {
    final requestId = ++_focusedTripRequestId;
    try {
      final itinerary = await TripDetailsService.fetchTripDetails(
        tripId: tripId,
      );
      if (!mounted || requestId != _focusedTripRequestId) return;
      setState(() {
        _focusedItinerary = itinerary;
        _isTripFocusLoading = false;
        _tripFocusLastUpdated = DateTime.now();
      });
      _focusedStopsColor = _focusedRouteColor(itinerary);
      _focusedRouteKeys
        ..clear()
        ..addAll(_buildFocusedRouteKeys(itinerary));
      _focusedRouteColors
        ..clear()
        ..addAll(_buildFocusedRouteColors(itinerary));
      _focusedTripIds
        ..clear()
        ..addAll(_buildFocusedTripIds(itinerary));
      unawaited(_setFocusedRoute(itinerary));
      unawaited(_setFocusedStops(itinerary));
      unawaited(_refreshFocusedTripVehicles(force: true));
      _applyFocusedStopsLayerVisibility();
      _applyFocusedRouteVisibility();
      unawaited(_fitCameraToFocusedItinerary(itinerary));
    } catch (e) {
      if (!mounted || requestId != _focusedTripRequestId) return;
      setState(() {
        _isTripFocusLoading = false;
        // Keep showing the previously loaded trip if this was a refresh.
        if (_focusedItinerary == null) {
          _tripFocusError = 'Failed to load trip.';
        }
      });
    }
  }

  Future<void> _refreshTripFocus() async {
    final tripId = _focusedTripId;
    if (tripId == null) return;
    await _loadFocusedTripDetails(tripId);
  }

  Future<void> _pushFocusedVehicleSource(DateTime now) async {
    final controller = _controller;
    if (controller == null || !_didAddFocusedVehiclesLayer) return;
    if (_focusedVehicles.isEmpty) {
      try {
        await controller.setGeoJsonSource(
          _kFocusedVehiclesSourceId,
          _emptyFeatureCollection(),
        );
      } catch (_) {}
      return;
    }

    final features = <Map<String, dynamic>>[];
    for (final entry in _focusedVehicles.entries) {
      final marker = entry.value;
      final position =
          marker.lastPosition ?? _positionAlongSegment(marker.segmentData, now);
      features.add(_vehicleFeature(entry.key, marker, position));
    }
    try {
      await controller.setGeoJsonSource(_kFocusedVehiclesSourceId, {
        'type': 'FeatureCollection',
        'features': features,
      });
    } catch (_) {}
  }

  void _dismissStopOverlay({bool animated = true}) {
    if (_selectedStop == null) return;
    if (!animated) {
      _stopTimesRequestId++;
      setState(() {
        _selectedStop = null;
        _isStopOverlayClosing = false;
      });
      return;
    }
    if (_isStopOverlayClosing) return;
    _stopTimesRequestId++;
    setState(() => _isStopOverlayClosing = true);
  }

  void _handleStopOverlayClosed() {
    setState(() {
      _isStopOverlayClosing = false;
      _selectedStop = null;
      _stopTimesPreview = [];
      _stopTimesError = null;
      _isStopTimesLoading = false;
    });
  }

  void _onStopChoice(RouteFieldKind kind, MapStop stop) {
    Haptics.lightTick();
    final suggestion = _suggestionFromStop(stop);
    unawaited(_recordSavedPlace(suggestion));
    _setControllerText(kind, suggestion.name);
    _setSelection(kind, suggestion, notify: true);
    _dismissStopOverlay();
    _maybeFitSelectionsOnCollapsed();
  }

  void _onStopTimeSelected(StopTime stopTime) {
    if (stopTime.tripId.isEmpty) return;
    Haptics.lightTick();
    _enterTripFocus(stopTime.tripId);
  }

  void _openStopTimetable(MapStop stop) {
    final stopId = stop.stopId;
    if (stopId == null || stopId.isEmpty) {
      showValidationToast(context, 'Timetable not available for this stop');
      return;
    }
    final suggestion = _suggestionFromStop(stop);
    unawaited(_recordSavedPlace(suggestion));
    _dismissStopOverlay();
    if (widget.onTimetableRequested != null) {
      widget.onTimetableRequested!(suggestion);
      widget.onTabChangeRequested?.call(1);
      return;
    }
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => TimetablesScreen(initialStop: suggestion),
      ),
    );
  }

  void _openAllSettings() {
    if (_isQuickSettings) {
      _closeQuickSettings();
    }
    widget.onTabChangeRequested?.call(3);
  }

  Future<void> _loadStopTimesPreview(MapStop stop) async {
    final stopId = stop.stopId;
    if (stopId == null || stopId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _stopTimesPreview = [];
        _stopTimesError = 'Stop timetable unavailable.';
        _isStopTimesLoading = false;
      });
      return;
    }
    final requestId = ++_stopTimesRequestId;
    try {
      final response = await StopTimesService.fetchStopTimes(
        stopId: stopId,
        n: 3,
        startTime: DateTime.now(),
      );
      if (!mounted || requestId != _stopTimesRequestId) return;
      final deduped = deduplicateStopTimes(response.stopTimes);
      final now = DateTime.now();
      final filtered =
          deduped.where((entry) => _stopTimeKey(entry) != null).where((entry) {
            final time = _stopTimeKey(entry)!;
            return time.isAfter(now.subtract(const Duration(minutes: 1)));
          }).toList()..sort((a, b) {
            final ta = _stopTimeKey(a)!;
            final tb = _stopTimeKey(b)!;
            return ta.compareTo(tb);
          });
      setState(() {
        _stopTimesPreview = filtered.take(3).toList();
        _stopTimesError = null;
        _isStopTimesLoading = false;
      });
    } catch (_) {
      if (!mounted || requestId != _stopTimesRequestId) return;
      setState(() {
        _stopTimesPreview = [];
        _stopTimesError = 'Unable to load stop times.';
        _isStopTimesLoading = false;
      });
    }
  }

  DateTime? _stopTimeKey(StopTime stopTime) {
    return stopTime.place.departure ??
        stopTime.place.scheduledDeparture ??
        stopTime.place.arrival ??
        stopTime.place.scheduledArrival;
  }

  TransitousLocationSuggestion _suggestionFromStop(MapStop stop) {
    return TransitousLocationSuggestion(
      id: stop.stopId ?? stop.id,
      stopId: stop.stopId,
      name: stop.name,
      lat: stop.lat,
      lon: stop.lon,
      type: 'STOP',
    );
  }

  String _latLngKey(LatLng latLng) =>
      '${latLng.latitude.toStringAsFixed(6)},${latLng.longitude.toStringAsFixed(6)}';

  String _formatLatLngLabel(LatLng latLng) =>
      '${latLng.latitude.toStringAsFixed(4)}, ${latLng.longitude.toStringAsFixed(4)}';

  void _setReverseGeocodeLoading(RouteFieldKind kind, bool isLoading) {
    if (!mounted) return;
    final hasKind = _reverseGeocodeLoading.contains(kind);
    if (isLoading && hasKind) return;
    if (!isLoading && !hasKind) return;
    setState(() {
      if (isLoading) {
        _reverseGeocodeLoading.add(kind);
      } else {
        _reverseGeocodeLoading.remove(kind);
      }
    });
  }

  bool _isReverseGeocodeLoading(RouteFieldKind kind) =>
      _reverseGeocodeLoading.contains(kind);

  void _onMapTap(math.Point<double> point, LatLng coordinate) {
    _dismissStopOverlay();
    _dismissLongPressOverlay();
    if (_isSheetCollapsed) return;
    _unfocusInputs();
    _stopDragRumble();
    final colTop = _lastComputedCollapsedTop;
    final expTop = _lastComputedExpandedTop;
    if (colTop != null && expTop != null) {
      _animateTo(colTop, colTop);
    }
  }

  void _hapticSnap() {
    if (!_hasVibrator) return;
    Haptics.snap(useCustomAmplitude: _hasCustomVibration);
  }

  void _unfocusInputs() {
    FocusScope.of(context).unfocus(disposition: UnfocusDisposition.scope);
    _dismissStopOverlay();
    _dismissLongPressOverlay();
  }

  Future<void> _loadSavedSearchPlaces() async {
    final places = await SavedPlacesService.loadPlaces(
      bucket: SavedPlacesBucket.search,
    );
    if (!mounted) return;
    setState(() {
      _savedSearchPlaces = places;
    });
  }

  Future<void> _recordSavedPlace(
    TransitousLocationSuggestion suggestion,
  ) async {
    final updated = SavedPlacesService.recordSelection(
      bucket: SavedPlacesBucket.search,
      places: _savedSearchPlaces,
      suggestion: suggestion,
    );
    if (!mounted) return;
    setState(() {
      _savedSearchPlaces = updated;
    });
  }

  Future<void> _loadRecentTrips() async {
    final trips = await RecentTripsService.getRecentTrips();
    if (!mounted) return;
    setState(() {
      _recentTrips = trips;
    });
  }

  /// Reopens the connection itself, not a new search between its two ends:
  /// the detail screen re-checks it, and says so when it has already run.
  void _onRecentTripTap(SavedTrip trip) {
    Haptics.lightTick();
    _unfocusInputs();
    Navigator.of(context).push(
      CustomPageRoute(
        child: ItineraryDetailScreen(
          itinerary: trip.itinerary,
          savedTrip: trip,
        ),
      ),
    );
  }
}

/// Where the sheet sits for one layout pass, and how it is moved.
class _SheetLayout {
  const _SheetLayout({
    required this.drag,
    required this.bottomBarHeight,
    required this.progress,
  });

  final SheetDrag drag;

  /// How much of the sheet still shows when it is down.
  final double bottomBarHeight;

  /// 0 raised, 1 down over the map.
  final double progress;
}
