import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';

import '../../api/nominatim_client.dart';
import '../../models/place_details.dart';
import '../../models/stop_time.dart';
import '../../models/transit_mode_group.dart';
import '../../providers/backend_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/favorites_service.dart';
import '../../services/location_service.dart';
import '../../services/stop_times_service.dart';
import '../../services/transitous_geocode_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../utils/geo_utils.dart';
import '../../utils/map_framing.dart';
import '../../utils/haptics.dart';
import '../../utils/map_marker_utils.dart';
import '../../utils/place_caption.dart';
import '../../widgets/custom_app_bar.dart';
import '../../widgets/map/place_details_sheet.dart';
import '../../widgets/validation_toast.dart';
import 'edge_tabs.dart';
import 'result_pins.dart';

/// Points at a place on the map, or picks one of a search's results there.
///
/// Used both to keep a favourite and to answer a location search, because
/// some places are easier to point at than to name. The two say different
/// things about the same gesture, so each is its own constructor.
class MapPlacePickerScreen extends StatefulWidget {
  /// Keeps the place as a favourite, then closes with `true`.
  const MapPlacePickerScreen.favourite({super.key})
    : title = 'Add Favourite',
      confirmLabel = 'Save',
      results = const [],
      origin = null,
      query = null,
      type = null,
      allowsPoint = true,
      _savesFavourite = true;

  /// Hands the place back to the caller as a [TransitousLocationSuggestion],
  /// with the caller naming what it is for: a route's origin is not saved
  /// anywhere, so "Save" would be a false promise.
  ///
  /// With [results], they are pins on the map, framed as the search found
  /// them, and those off screen are pointed at from the edge.
  const MapPlacePickerScreen.pick({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.results = const [],
    this.origin,
    this.query,
    this.type,
    this.allowsPoint = true,
  }) : _savesFavourite = false;

  final String title;

  /// The button that takes the place pointed at.
  final String confirmLabel;

  /// A search's results in its order; empty to only point.
  final List<TransitousLocationSuggestion> results;

  /// Where the rider is, for how far each result is.
  final LatLng? origin;

  /// What [results] were searched for: asked again, from the map's centre,
  /// by "Search in this area". Null when there is nothing to ask again.
  final String? query;

  /// The geocoder type the search was limited to, e.g. `STOP`.
  final String? type;

  /// Whether any point may be picked, or only a result: a timetable needs a
  /// stop, and a point is not one.
  final bool allowsPoint;

  final bool _savesFavourite;

  @override
  State<MapPlacePickerScreen> createState() => _MapPlacePickerScreenState();
}

class _MapPlacePickerScreenState extends State<MapPlacePickerScreen> {
  static const String _kPinsSourceId = 'picker-results-source';
  static const String _kPinsLayerId = 'picker-results-layer';
  static const String _kPointSourceId = 'picker-point-source';
  static const String _kPointLayerId = 'picker-point-layer';
  static const String _kPointImageId = 'picker-point-marker';

  /// MapLibre may report one tap on a pin both as a feature tap and as a map
  /// tap; a map tap this soon after a pin's is that same tap.
  static const Duration _kSameTap = Duration(milliseconds: 400);

  /// No closer than this for a city, whose point is only its centre.
  static const double _kSettlementZoom = 12;

  /// No closer than this for a shop, a stop or an address.
  static const double _kPlaceZoom = 16;

  /// Room left around what a frame shows, for the pins drawn at its edges
  /// and the tabs pointing past them.
  static const EdgeInsets _kFramePadding = EdgeInsets.fromLTRB(48, 48, 48, 96);

  /// The sheet may take this share of the map; its facts scroll beyond it.
  static const double _kSheetMaxShare = 0.62;

  /// Departures a stop's sheet lists: the next few, not a timetable.
  static const int _kSheetDepartures = 5;

  static const double _kPinSize = 36;

  static const Duration _kFlyDuration = Duration(milliseconds: 600);

  MapLibreMapController? _controller;
  bool _didInitialCenter = false;
  bool _pinsReady = false;
  bool _pointLayerReady = false;
  DateTime? _lastPinTap;

  /// Where the map opened, framed on the first results. Fixed once: the map
  /// stays there until moved, whatever a search in this area brings.
  CameraPosition? _openingCamera;

  /// Where the map looks, as last reported; the tabs are placed from it.
  CameraPosition? _camera;
  Size? _mapSize;

  int? _selectedResult;
  LatLng? _point;
  String? _pointName;
  bool _isLoadingName = false;

  PlaceDetails? _details;
  List<StopTime>? _departures;
  bool _isLoadingExtras = false;

  /// Guards against an earlier, slower lookup filling a later selection.
  int _selectionToken = 0;

  /// The details sheet's height, once laid out: the tabs stop above it,
  /// and a selection is centred in what it leaves.
  double _sheetHeight = 0;

  /// The results on the map: the search's, until one is made here.
  late List<TransitousLocationSuggestion> _results = widget.results;
  bool _isSearchingArea = false;

  /// Pin images already on the map, by id: a search here may bring icons
  /// the first did not.
  final Set<String> _pinImages = {};
  bool get _hasSelection => _selectedResult != null || _point != null;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.white,
      child: SafeArea(
        child: Column(
          children: [
            CustomAppBar(title: widget.title),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => _buildMap(context, box.biggest),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMap(BuildContext context, Size size) {
    _mapSize = size;
    final initial = _openingCamera ??= _initialCamera(size);
    final camera = _camera ?? initial;
    return Stack(
      children: [
        MapLibreMap(
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: _onStyleLoaded,
          styleString: context.watch<ThemeProvider>().mapStyleUrl,
          initialCameraPosition: initial,
          myLocationEnabled: true,
          rotateGesturesEnabled: true,
          tiltGesturesEnabled: false,
          compassEnabled: false,
          trackCameraPosition: true,
          onCameraMove: (position) => setState(() => _camera = position),
          onMapClick: _onMapTap,
          onMapLongClick: _onMapLongPress,
        ),
        if (_results.isNotEmpty)
          Positioned.fill(
            child: EdgeTabsLayer(
              view: MapView(
                center: camera.target,
                zoom: camera.zoom,
                size: size,
                bearing: camera.bearing,
              ),
              targets: [for (final r in _results) r.latLng],
              area: Rect.fromLTRB(
                0,
                0,
                size.width,
                // Down to the foot of the map: the hint or the area search
                // button sits over the tabs there, as over the map. A sheet
                // covers the map, so the tabs stop above it.
                size.height - (_hasSelection ? _sheetHeight : 0),
              ),
              taken: _pinRects(camera, size),
              onTap: _showMembers,
            ),
          ),
        if (_hasSelection)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: size.height * _kSheetMaxShare,
              ),
              child: _ReportsHeight(
                onHeight: _onSheetHeight,
                child: _buildSheet(),
              ),
            ),
          )
        else
          Positioned(
            left: 20,
            right: 20,
            bottom: 20,
            child: widget.query == null ? _buildHint() : _buildAreaSearch(),
          ),
      ],
    );
  }

  /// Where the results' pins and names are drawn, for the tabs' labels to
  /// keep clear of. Estimated as the map lays them out: the pin centred on
  /// the place, its name below.
  List<Rect> _pinRects(CameraPosition camera, Size size) {
    const nameCharWidth = 7.0;
    const nameHeight = 16.0;
    final view = MapView(
      center: camera.target,
      zoom: camera.zoom,
      size: size,
      bearing: camera.bearing,
    );
    final visible = Offset.zero & size;
    return [
      for (final r in _results)
        if (view.project(r.latLng) case final p when visible.contains(p)) ...[
          Rect.fromCenter(center: p, width: _kPinSize, height: _kPinSize),
          Rect.fromCenter(
            center: p + const Offset(0, _kPinSize / 2 + nameHeight / 2),
            width: nameCharWidth * r.name.length,
            height: nameHeight,
          ),
        ],
    ];
  }

  /// The results framed as the search found them, or the fallback until
  /// the rider's position is known.
  CameraPosition _initialCamera(Size size) {
    final frame = frameResults(
      [for (final r in _results) r.latLng],
      size,
      maxZoom: _closestZoomFor(_results.isEmpty ? null : _results.first),
      padding: _kFramePadding,
    );
    if (frame == null) {
      return const CameraPosition(
        target: LatLng(kFallbackMapLat, kFallbackMapLon),
        zoom: kFallbackMapZoom,
      );
    }
    return CameraPosition(target: frame.center, zoom: frame.zoom);
  }

  double _closestZoomFor(TransitousLocationSuggestion? result) =>
      (result?.match?.isSettlement ?? false) ? _kSettlementZoom : _kPlaceZoom;

  @override
  void dispose() {
    _controller?.onFeatureTapped.remove(_onFeatureTapped);
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) async {
    _controller = controller;
    // A pin is an interactive feature: a tap on it arrives here, not as a
    // map tap, which only a long press would otherwise have reached.
    controller.onFeatureTapped.add(_onFeatureTapped);
    if (_results.isNotEmpty) return;
    await _centerOnUserIfPossible();
  }

  Future<void> _onStyleLoaded() async {
    final controller = _controller;
    if (controller == null) return;
    final accent = AppColors.accentOf(context);
    await _addPins(controller, accent);
    await _addPointLayer(controller, accent);
  }

  Future<void> _ensurePinImages(
    MapLibreMapController controller,
    Color accent,
  ) async {
    for (final icon in {for (final r in _results) resultPinIcon(r)}) {
      final id = resultPinImageId(icon);
      if (_pinImages.contains(id)) continue;
      await controller.addImage(id, await buildResultPinImage(accent, icon));
      _pinImages.add(id);
    }
  }

  Future<void> _addPins(MapLibreMapController controller, Color accent) async {
    if (_results.isEmpty) return;
    try {
      await _ensurePinImages(controller, accent);
      await controller.addGeoJsonSource(
        _kPinsSourceId,
        resultPinFeatures(_results, selected: _selectedResult),
      );
      await controller.addSymbolLayer(
        _kPinsSourceId,
        _kPinsLayerId,
        SymbolLayerProperties(
          iconImage: [Expressions.get, 'icon'],
          iconSize: [
            Expressions.caseExpression,
            [Expressions.get, 'selected'],
            1.3,
            1.0,
          ],
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
          symbolSortKey: [Expressions.get, 'sortKey'],
          // Names only where there is room; the pins always show.
          textField: [Expressions.get, 'name'],
          textFont: const ['Noto Sans Bold'],
          textSize: 12,
          textAnchor: 'top',
          textOffset: const [0, 1.4],
          textOptional: true,
          textColor: '#000000',
          textHaloColor: '#ffffff',
          textHaloWidth: 1.5,
        ),
      );
      _pinsReady = true;
    } catch (_) {
      _pinsReady = false;
    }
  }

  /// The marker for a point picked by hand, above the pins: it is what the
  /// sheet is about.
  Future<void> _addPointLayer(
    MapLibreMapController controller,
    Color accent,
  ) async {
    try {
      await controller.addImage(
        _kPointImageId,
        await buildBubbleMarkerImage(accent, LucideIcons.mapPin),
      );
      await controller.addGeoJsonSource(_kPointSourceId, _pointFeatures());
      await controller.addSymbolLayer(
        _kPointSourceId,
        _kPointLayerId,
        const SymbolLayerProperties(
          iconImage: _kPointImageId,
          iconAnchor: 'bottom',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
        enableInteraction: false,
      );
      _pointLayerReady = true;
    } catch (_) {
      _pointLayerReady = false;
    }
  }

  Map<String, dynamic> _pointFeatures() => {
    'type': 'FeatureCollection',
    'features': [
      if (_point case final p?)
        {
          'type': 'Feature',
          'properties': const <String, dynamic>{},
          'geometry': {
            'type': 'Point',
            'coordinates': [p.longitude, p.latitude],
          },
        },
    ],
  };

  Future<void> _refreshPoint() async {
    final controller = _controller;
    if (controller == null || !_pointLayerReady) return;
    try {
      await controller.setGeoJsonSource(_kPointSourceId, _pointFeatures());
    } catch (_) {}
  }

  Future<void> _refreshPins() async {
    final controller = _controller;
    if (controller == null || !_pinsReady) return;
    try {
      await controller.setGeoJsonSource(
        _kPinsSourceId,
        resultPinFeatures(_results, selected: _selectedResult),
      );
    } catch (_) {}
  }

  void _onFeatureTapped(
    math.Point<double> point,
    LatLng coordinates,
    String id,
    String layerId,
    Annotation? annotation,
  ) {
    if (layerId.isNotEmpty && layerId != _kPinsLayerId) return;
    final rank = resultRankOf(id, _results.length);
    if (rank == null) return;
    _lastPinTap = DateTime.now();
    _selectResult(rank);
  }

  bool get _wasJustAPinTap {
    final last = _lastPinTap;
    return last != null && DateTime.now().difference(last) < _kSameTap;
  }

  /// A pin picks its result. Among results, a tap elsewhere puts the sheet
  /// away, and picking a point takes a hold; with none to tap, a tap picks
  /// the point.
  Future<void> _onMapTap(math.Point<double> point, LatLng coordinates) async {
    final rank = await _resultAt(point);
    if (!mounted) return;
    if (rank != null) {
      if (rank != _selectedResult) _selectResult(rank);
      return;
    }
    if (_wasJustAPinTap) return;
    if (_results.isNotEmpty || !widget.allowsPoint) {
      _clearSelection();
      return;
    }
    _selectPoint(coordinates);
  }

  Future<void> _onMapLongPress(
    math.Point<double> point,
    LatLng coordinates,
  ) async {
    final rank = await _resultAt(point);
    if (!mounted) return;
    if (rank != null) {
      if (rank != _selectedResult) _selectResult(rank);
      return;
    }
    if (!widget.allowsPoint) return;
    unawaited(Haptics.lightTick());
    _selectPoint(coordinates);
  }

  Future<int?> _resultAt(math.Point<double> point) async {
    final controller = _controller;
    if (controller == null || !_pinsReady) return null;
    try {
      final features = await controller.queryRenderedFeatures(point, [
        _kPinsLayerId,
      ], null);
      for (final feature in features) {
        final properties = (feature as Map)['properties'];
        if (properties is! Map) continue;
        final rank = properties['rank'];
        if (rank is num) return rank.toInt();
      }
    } catch (_) {}
    return null;
  }

  /// What a tap on the pin for result [rank] does. The map is a platform
  /// view and takes no taps in a test, so the sheet's loading is reached
  /// through here.
  @visibleForTesting
  void tapResultForTesting(int rank) => _selectResult(rank);

  void _selectResult(int rank) {
    final result = _results[rank];
    final token = ++_selectionToken;
    setState(() {
      _selectedResult = rank;
      _point = null;
      _details = null;
      _departures = null;
      _isLoadingExtras = true;
    });
    unawaited(_refreshPins());
    unawaited(_refreshPoint());
    unawaited(_loadExtras(result, token));
    _centreOnceSheetIsUp(result.latLng);
  }

  void _selectPoint(LatLng coordinates) {
    ++_selectionToken;
    setState(() {
      _selectedResult = null;
      _point = coordinates;
      _pointName = null;
      _isLoadingName = true;
    });
    unawaited(_refreshPins());
    unawaited(_refreshPoint());
    unawaited(_fetchPointName(coordinates));
    _centreOnceSheetIsUp(coordinates);
  }

  void _clearSelection() {
    ++_selectionToken;
    setState(() {
      _selectedResult = null;
      _point = null;
      _sheetHeight = 0;
    });
    unawaited(_refreshPins());
    unawaited(_refreshPoint());
  }

  /// A stop's next departures, or what OpenStreetMap knows of a place.
  Future<void> _loadExtras(
    TransitousLocationSuggestion result,
    int token,
  ) async {
    PlaceDetails? details;
    List<StopTime>? departures;
    final stopId = result.stopId;
    if (stopId != null) {
      try {
        departures = (await StopTimesService.fetchStopTimes(
          stopId: stopId,
          n: _kSheetDepartures,
        )).stopTimes;
      } catch (_) {
        departures = const [];
      }
    } else {
      final backend = BackendProvider.instance;
      final ref = OsmRef.parse(result.match?.id ?? '');
      if (ref != null && (backend?.placeDetailsEnabled ?? true)) {
        details = await NominatimClient.instance.lookup(
          ref,
          host: backend?.nominatimHost ?? NominatimClient.defaultHost,
        );
      }
    }
    if (!mounted || token != _selectionToken) return;
    setState(() {
      _details = details;
      _departures = departures;
      _isLoadingExtras = false;
    });
  }

  void _onSheetHeight(double height) {
    if (!mounted || height == _sheetHeight) return;
    setState(() => _sheetHeight = height);
  }

  /// Pans [p] to the middle of the map the sheet leaves, after the sheet
  /// has been laid out and its height is known.
  void _centreOnceSheetIsUp(LatLng p) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _controller;
      final camera = _camera ?? _openingCamera!;
      if (!mounted || controller == null) return;
      final centre = centerPlacing(
        p,
        offset: Offset(0, -_sheetHeight / 2),
        zoom: camera.zoom,
        bearing: camera.bearing,
      );
      unawaited(
        controller.animateCamera(
          CameraUpdate.newLatLng(centre),
          duration: _kFlyDuration,
        ),
      );
    });
  }

  /// Moves the map to show every result a tab stands for: the rider asked
  /// to see them, so none is left to a further tab.
  Future<void> _showMembers(List<int> members) async {
    final controller = _controller;
    final size = _mapSize;
    if (controller == null || size == null || members.isEmpty) return;
    final frame = fitAll(
      [for (final i in members) _results[i].latLng],
      size,
      maxZoom: _closestZoomFor(_results[members.first]),
      padding: _kFramePadding,
    );
    if (frame == null) return;
    await controller.animateCamera(
      CameraUpdate.newLatLngZoom(frame.center, frame.zoom),
      duration: _kFlyDuration,
    );
  }

  Future<void> _fetchPointName(LatLng coordinates) async {
    String? name;
    try {
      final suggestion = await TransitousGeocodeService.reverseGeocode(
        place: coordinates,
      );
      name = suggestion?.name;
    } catch (_) {}
    if (!mounted || _point != coordinates) return;
    setState(() {
      _pointName = name ?? _coordinateName(coordinates);
      _isLoadingName = false;
    });
  }

  static String _coordinateName(LatLng p) =>
      coordLabel(p.latitude, p.longitude);

  Future<void> _centerOnUserIfPossible() async {
    if (_didInitialCenter) return;
    final controller = _controller;
    if (controller == null) return;
    _didInitialCenter = true;

    LatLng? target;
    bool shouldPersist = false;

    try {
      target = await LocationService.loadLastLatLng();
    } catch (_) {}

    bool hasPermission = false;
    try {
      hasPermission = await LocationService.ensurePermission();
    } catch (_) {
      hasPermission = false;
    }

    if (hasPermission) {
      target ??= await _lastKnownLatLng();
      if (target == null) {
        final current = await _currentLatLng();
        if (current != null) {
          target = current;
          shouldPersist = true;
        }
      }
    }

    target ??= const LatLng(kFallbackMapLat, kFallbackMapLon);

    await controller.moveCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: 14.0),
      ),
    );

    if (shouldPersist && mounted) {
      await LocationService.saveLastLatLng(target);
    }
  }

  Future<LatLng?> _lastKnownLatLng() async {
    try {
      final pos = await LocationService.lastKnownPosition();
      if (pos == null) return null;
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<LatLng?> _currentLatLng() async {
    try {
      final pos = await LocationService.currentPosition();
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _confirm() async {
    final rank = _selectedResult;
    if (rank != null) {
      Navigator.of(context).pop(_results[rank]);
      return;
    }
    final point = _point;
    if (point == null) return;
    final name = _pointName ?? _coordinateName(point);

    if (!widget._savesFavourite) {
      Navigator.of(context).pop(
        TransitousLocationSuggestion(
          id: 'map-${point.latitude}-${point.longitude}',
          name: name,
          lat: point.latitude,
          lon: point.longitude,
          type: 'PLACE',
        ),
      );
      return;
    }

    try {
      await FavoritesService.saveFavorite(
        FavoritePlace(
          id: 'fav_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          lat: point.latitude,
          lon: point.longitude,
          addedAt: DateTime.now(),
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        showValidationToast(context, "Failed to add favourite");
      }
    }
  }

  /// Asks the search again from the middle of the map, held there hard:
  /// for "that shop, but here", after panning to here.
  Future<void> _searchThisArea() async {
    final query = widget.query;
    if (query == null || _isSearchingArea) return;
    final centre = (_camera ?? _openingCamera!).target;
    setState(() => _isSearchingArea = true);
    try {
      final page = await TransitousGeocodeService.fetchSuggestionPage(
        text: query,
        placeBias: centre,
        type: widget.type,
        biasStrength: TransitousGeocodeService.areaPlaceBias,
      );
      if (!mounted) return;
      // MOTIS answers something for any name, however far: a bias ranks,
      // it does not restrict. So "nothing here" is nothing on screen.
      if (page.suggestions.isEmpty) {
        showValidationToast(context, 'Nothing found for “$query”');
        return;
      }
      ++_selectionToken;
      setState(() {
        _results = page.suggestions;
        _selectedResult = null;
        _point = null;
        _sheetHeight = 0;
      });
      await _showNewPins();
      if (!mounted) return;
      if (!_anyOnScreen(page.suggestions)) {
        showValidationToast(
          context,
          'Nothing in this area; the arrows point to the nearest',
        );
      }
    } catch (_) {
      if (mounted) showValidationToast(context, 'Search failed, try again');
    } finally {
      if (mounted) setState(() => _isSearchingArea = false);
    }
  }

  bool _anyOnScreen(List<TransitousLocationSuggestion> results) {
    final size = _mapSize;
    if (size == null) return true;
    final camera = _camera ?? _openingCamera!;
    final view = MapView(
      center: camera.target,
      zoom: camera.zoom,
      size: size,
      bearing: camera.bearing,
    );
    final visible = Offset.zero & size;
    return results.any((r) => visible.contains(view.project(r.latLng)));
  }

  Future<void> _showNewPins() async {
    final controller = _controller;
    if (controller == null) return;
    final accent = AppColors.accentOf(context);
    if (!_pinsReady) return _addPins(controller, accent);
    try {
      await _ensurePinImages(controller, accent);
    } catch (_) {}
    await _refreshPins();
    await _refreshPoint();
  }

  Widget _buildAreaSearch() {
    final accent = AppColors.accentOf(context);
    return Center(
      child: Semantics(
        button: true,
        child: GestureDetector(
          onTap: _isSearchingArea ? null : _searchThisArea,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.search, size: 18, color: accent),
                const SizedBox(width: 8),
                Text(
                  _isSearchingArea ? 'Searching…' : 'Search in this area',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHint() {
    final text = switch ((_results.isNotEmpty, widget.allowsPoint)) {
      (true, true) =>
        'Tap a result for details, or hold anywhere to pick that point',
      (true, false) => 'Tap a result for details',
      (false, _) => 'Tap anywhere to pick that point',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Text(text, textAlign: TextAlign.center, style: AppText.bodyMuted),
    );
  }

  Widget _buildSheet() {
    final rank = _selectedResult;
    final homeCountry = View.of(context).platformDispatcher.locale.countryCode;
    if (rank == null) {
      final point = _point!;
      final origin = widget.origin;
      return PlaceDetailsSheet.point(
        title: _pointName ?? _coordinateName(point),
        caption: origin == null
            ? null
            : formatPlaceDistance(
                coordinateDistanceInMeters(
                  origin.latitude,
                  origin.longitude,
                  point.latitude,
                  point.longitude,
                ),
              ),
        isLoading: _isLoadingName,
        confirmLabel: widget.confirmLabel,
        onConfirm: _confirm,
        onCancel: _clearSelection,
      );
    }
    final result = _results[rank];
    final caption = result.caption(
      from: widget.origin,
      homeCountry: homeCountry,
    );
    if (result.stopId != null) {
      return PlaceDetailsSheet.stop(
        icon: resultPinIcon(result),
        title: result.name,
        caption: caption,
        modes: result.modes.isEmpty
            ? null
            : {
                for (final m in result.modes) TransitModeGroup.modeLabel(m),
              }.join(' · '),
        departures: _departures,
        isLoading: _isLoadingExtras,
        confirmLabel: widget.confirmLabel,
        onConfirm: _confirm,
        onCancel: _clearSelection,
      );
    }
    return PlaceDetailsSheet.place(
      icon: resultPinIcon(result),
      title: result.name,
      caption: caption,
      category: categoryLabel(result.match?.category),
      details: _details,
      isLoading: _isLoadingExtras,
      confirmLabel: widget.confirmLabel,
      onConfirm: _confirm,
      onCancel: _clearSelection,
    );
  }
}

/// Tells [onHeight] how tall its child was laid out, after the frame.
class _ReportsHeight extends SingleChildRenderObjectWidget {
  const _ReportsHeight({required this.onHeight, super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportsHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReportsHeight renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderReportsHeight extends RenderProxyBox {
  _RenderReportsHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (height == _reported) return;
    _reported = height;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
