import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_colors.dart';
import '../models/time_selection.dart';
import '../models/stop_time.dart';
import '../screens/connection_info_screen.dart';
import '../services/location_service.dart';
import '../services/favorites_service.dart';
import '../services/saved_places_service.dart';
import '../services/stop_times_service.dart';
import '../screens/location_search_screen.dart';
import '../services/transitous_geocode_service.dart';
import '../utils/color_utils.dart';
import '../utils/custom_page_route.dart';
import '../utils/leg_helper.dart' show getLegIcon;
import '../utils/reported_time.dart';
import '../utils/stop_time_utils.dart';
import '../widgets/buttons/pill_button.dart';
import '../widgets/delayed_time.dart';
import '../widgets/error_notice.dart';
import '../widgets/gtfs_fields_row.dart';
import '../widgets/nearby_departures_section.dart';
import '../widgets/route_badge_pill.dart';
import '../widgets/buttons/primary_button.dart';
import '../widgets/skeletons/skeleton_list.dart';
import '../widgets/bidirectional_paged_list.dart';
import '../widgets/time_selection_overlay.dart';
import '../widgets/validation_toast.dart';
import '../theme/app_text.dart';

class TimetablesScreen extends StatefulWidget {
  const TimetablesScreen({
    super.key,
    this.initialStop,
    this.buildNearby = _buildNearby,
  });

  final TransitousLocationSuggestion? initialStop;

  /// Builds the Near you list around a position; swapped in drafts and
  /// tests, which have no position and no network.
  final NearbyBuilder buildNearby;

  static NearbySectionBuilder _buildNearby(LatLng? center) =>
      (buildRow, buildMessage) => NearbyDeparturesSection(
        center: center,
        buildRow: buildRow,
        buildMessage: buildMessage,
      );

  @override
  State<TimetablesScreen> createState() => _TimetablesScreenState();
}

typedef NearbyBuilder = NearbySectionBuilder Function(LatLng? center);

class _TimetablesScreenState extends State<TimetablesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final LayerLink _searchFieldLink = LayerLink();
  final LayerLink _timeSelectionLayerLink = LayerLink();

  TimeSelection _timeSelection = TimeSelection.now();
  bool _showTimeSelectionOverlay = false;
  bool _suppressTimeSelectionReopen = false;
  LatLng? _lastUserLatLng;
  TransitousLocationSuggestion? _selectedStop;
  List<StopTime>? _stopTimes;
  int _centerIndex = 0;
  bool _isLoadingStopTimes = false;

  /// Why the last load failed, or null. Held rather than toasted so the body
  /// has something to show instead of falling back to the stop picker.
  String? _stopTimesError;

  String? _nextPageCursor;
  bool _isLoadingMore = false;
  String? _previousPageCursor;
  bool _isLoadingPrevious = false;
  late final ScrollController _resultsScrollController;
  bool _appliedInitialPreviousOffset = false;
  static const Key _centerKey = ValueKey('stop-times-center');

  /// Gutter the result cards sit inside.
  static const double _kResultsHorizontalPadding = 20.0;

  /// Clearance under the last result for the floating nav bar.
  static const double _kResultsBottomSpacing = 96.0;

  bool get _hasPreviousPage => _previousPageCursor?.isNotEmpty ?? false;
  bool get _hasNextPage => _nextPageCursor?.isNotEmpty ?? false;
  DateTime? get _startTimeParam =>
      _timeSelection.isNow ? null : _timeSelection.dateTime;

  String? _normalizeCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) return null;
    return cursor;
  }

  @override
  void initState() {
    super.initState();
    _resultsScrollController = ScrollController();
    _searchController.addListener(_onSearchTextChanged);
    _searchFocus.addListener(_onFocusChanged);
    _checkLocationPermission();
    unawaited(FavoritesService.getFavorites());
    _applyInitialStop(widget.initialStop);
  }

  @override
  void didUpdateWidget(covariant TimetablesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialStop?.id != oldWidget.initialStop?.id) {
      _applyInitialStop(widget.initialStop);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _resultsScrollController.dispose();
    super.dispose();
  }

  Future<void> _checkLocationPermission() async {
    final granted = await LocationService.ensurePermission();
    if (!mounted) return;

    if (granted) {
      try {
        final pos = await LocationService.currentPosition();
        if (mounted) {
          setState(() {
            _lastUserLatLng = LatLng(pos.latitude, pos.longitude);
          });
        }
      } catch (_) {}
    }
  }

  /// Before a stop is chosen, this screen *is* the stop search.
  ///
  /// The picker's own body is rendered here rather than pushed, and the
  /// keyboard stays down, because the favourites and recents are what you
  /// came for.
  Widget _buildStopSearch() {
    return LocationSearchBody(
      bucket: SavedPlacesBucket.timetable,
      type: 'STOP',
      autofocus: false,
      onPicked: _onSuggestionSelected,
      // Off, the section is not there at all, and nothing near the rider is
      // asked for.
      nearby: context.read<ThemeProvider>().showNearbyDepartures
          ? widget.buildNearby(_lastUserLatLng)
          : null,
    );
  }

  /// Remembers a stop resolved from typed text, which never went through the
  /// search's list and so was not remembered there.
  ///
  /// Read fresh rather than kept: the search records its own picks, and a
  /// copy taken when this screen opened would write over them.
  Future<void> _recordSavedPlace(
    TransitousLocationSuggestion suggestion,
  ) async {
    final places = await SavedPlacesService.loadPlaces(
      bucket: SavedPlacesBucket.timetable,
    );
    SavedPlacesService.recordSelection(
      bucket: SavedPlacesBucket.timetable,
      places: places,
      suggestion: suggestion,
    );
  }

  void _onFocusChanged() {
    setState(() {});
    if (_searchFocus.hasFocus) {
      _onSearchTextChanged();
    }
  }

  void _onTimeSelectionChanged(TimeSelection newSelection) {
    setState(() {
      _timeSelection = newSelection;
    });
  }

  void _toggleTimeSelectionOverlay() {
    if (_showTimeSelectionOverlay) {
      _closeTimeSelectionOverlay();
    } else {
      _openTimeSelectionOverlay();
    }
  }

  void _openTimeSelectionOverlay() {
    if (_showTimeSelectionOverlay) return;
    _searchFocus.unfocus();
    setState(() {
      _showTimeSelectionOverlay = true;
    });
    showTimeSelectionOverlay(
      context,
      currentSelection: _timeSelection,
      onSelectionChanged: _onTimeSelectionChanged,
      onDismiss: _closeTimeSelectionOverlay,
      // Timetables ask "departures from when", never "arrivals by when".
      showDepartArriveToggle: false,
    ).then((_) {
      if (!mounted) return;
      if (_showTimeSelectionOverlay) {
        setState(() => _showTimeSelectionOverlay = false);
      }
    });
  }

  void _closeTimeSelectionOverlay() {
    if (!_showTimeSelectionOverlay) return;
    Navigator.of(context, rootNavigator: true).maybePop();
  }

  void _handleTimeButtonTapDown() {
    if (_showTimeSelectionOverlay) {
      _suppressTimeSelectionReopen = true;
      _closeTimeSelectionOverlay();
    }
  }

  void _handleTimeButtonTapCancel() {
    _suppressTimeSelectionReopen = false;
  }

  void _handleTimeButtonTap() {
    if (_suppressTimeSelectionReopen) {
      _suppressTimeSelectionReopen = false;
      return;
    }
    _toggleTimeSelectionOverlay();
  }

  void _onSearchTextChanged() => setState(() {});

  void _applyInitialStop(TransitousLocationSuggestion? initialStop) {
    if (initialStop == null) return;
    _selectedStop = initialStop;
    _searchController.text = initialStop.name;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _onSearch();
    });
  }

  /// Puts the screen back to being the stop search.
  ///
  /// Everything the chosen stop brought with it goes: the field, the stop
  /// itself, its departures and the paging through them.
  void _clearStop() {
    _searchFocus.unfocus();
    setState(() {
      _searchController.clear();
      _selectedStop = null;
      _stopTimes = null;
      _stopTimesError = null;
      _nextPageCursor = null;
      _previousPageCursor = null;
      _isLoadingStopTimes = false;
      _isLoadingMore = false;
      _isLoadingPrevious = false;
    });
  }

  /// Picking a stop is the whole question this screen asks, so answering it
  /// opens the departure board rather than filling a field and waiting.
  ///
  /// The search has already remembered the pick.
  void _onSuggestionSelected(TransitousLocationSuggestion suggestion) {
    setState(() {
      _searchController.text = suggestion.name;
      _selectedStop = suggestion;
      _searchFocus.unfocus();
    });
    unawaited(_onSearch());
  }

  Future<void> _onSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      showValidationToast(context, 'Please enter a stop name');
      return;
    }

    var selectedStop = _selectedStop;
    if (selectedStop?.stopId == null && query.length >= 3) {
      selectedStop = await _resolveStopFromQuery(query);
    }

    final stopId = selectedStop?.stopId;
    if (stopId == null) {
      showValidationToast(context, 'Please select a stop from the list');
      return;
    }

    _searchFocus.unfocus();

    setState(() {
      _isLoadingStopTimes = true;
      _stopTimesError = null;
      _stopTimes = null;
      _nextPageCursor = null;
      _previousPageCursor = null;
      _isLoadingMore = false;
      _isLoadingPrevious = false;
      _appliedInitialPreviousOffset = false;
    });
    if (_resultsScrollController.hasClients) {
      _resultsScrollController.jumpTo(0);
    }

    try {
      final response = await StopTimesService.fetchStopTimes(
        stopId: stopId,
        n: 20,
        startTime: _startTimeParam,
        arriveBy: _timeSelection.isArriveBy,
      );

      // The stop can have been cleared or swapped while this was in flight,
      // and a late answer would put the departures back over a screen the
      // rider has already left.
      if (!mounted || _selectedStop?.stopId != stopId) return;

      // The board says what calls here, which a stop picked from the recents
      // list, or remembered before modes were, has no other way to learn.
      if (response.place?.modes case final modes?) {
        unawaited(
          SavedPlacesService.recordModes(
            bucket: SavedPlacesBucket.timetable,
            stopId: stopId,
            modes: modes,
          ),
        );
      }

      setState(() {
        _stopTimes = deduplicateStopTimes(response.stopTimes);
        _centerIndex = 0;
        _nextPageCursor = _normalizeCursor(response.nextPageCursor);
        _previousPageCursor = _normalizeCursor(response.previousPageCursor);
        _isLoadingStopTimes = false;
      });
      _maybeApplyInitialPreviousOffset();
    } catch (e) {
      if (!mounted || _selectedStop?.stopId != stopId) return;

      // Recorded rather than toasted: a toast leaves the body with no
      // departures and nothing to say, so it falls back to the picker and the
      // rider sees a second search field under the stop they just chose.
      setState(() {
        _isLoadingStopTimes = false;
        _stopTimesError = 'Failed to load stop times';
        _previousPageCursor = null;
        _isLoadingPrevious = false;
      });
    }
  }

  Future<TransitousLocationSuggestion?> _resolveStopFromQuery(
    String query,
  ) async {
    if (query.trim().length < 3) return null;
    try {
      final results = await TransitousGeocodeService.fetchSuggestions(
        text: query,
        type: 'STOP',
        placeBias: _lastUserLatLng,
      );
      if (results.isEmpty) return null;
      final suggestion = results.first;
      if (!mounted) return suggestion;
      unawaited(_recordSavedPlace(suggestion));
      setState(() {
        _searchController.text = suggestion.name;
        _selectedStop = suggestion;
        _searchFocus.unfocus();
      });
      return suggestion;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore ||
        _nextPageCursor == null ||
        _selectedStop?.id == null) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final response = await StopTimesService.fetchStopTimes(
        stopId: _selectedStop?.id ?? '',
        n: StopTimesService.defaultPageSize,
        pageCursor: _nextPageCursor,
        startTime: _startTimeParam,
        arriveBy: _timeSelection.isArriveBy,
      );

      if (!mounted) return;

      setState(() {
        _stopTimes = deduplicateStopTimes([
          ...?_stopTimes,
          ...response.stopTimes,
        ]);
        _nextPageCursor = _normalizeCursor(response.nextPageCursor);
        _previousPageCursor = _normalizeCursor(
          response.previousPageCursor ?? _previousPageCursor,
        );
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingMore = false;
      });

      showValidationToast(context, 'Failed to load more stop times');
    }
  }

  Future<void> _loadPrevious() async {
    if (_isLoadingPrevious || !_hasPreviousPage || _selectedStop?.id == null) {
      return;
    }

    setState(() {
      _isLoadingPrevious = true;
    });

    try {
      final response = await StopTimesService.fetchStopTimes(
        stopId: _selectedStop?.id ?? '',
        n: StopTimesService.defaultPageSize,
        pageCursor: _previousPageCursor,
        startTime: _startTimeParam,
        arriveBy: _timeSelection.isArriveBy,
      );

      if (!mounted) return;

      final oldLength = _stopTimes?.length ?? 0;
      final combined = deduplicateStopTimes([
        ...response.stopTimes,
        ...?_stopTimes,
      ]);
      final addedCount = combined.length - oldLength;

      setState(() {
        _stopTimes = combined;
        _centerIndex += addedCount;
        _previousPageCursor = _normalizeCursor(response.previousPageCursor);
        _isLoadingPrevious = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoadingPrevious = false;
      });

      showValidationToast(context, 'Failed to load previous stop times');
    }
  }

  void _maybeApplyInitialPreviousOffset() {
    if (_appliedInitialPreviousOffset) return;
    if (!_hasPreviousPage) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scrollPastSeePrevious(_resultsScrollController);
      _appliedInitialPreviousOffset = true;
    });
  }

  /// The screen's title block: what this screen is, above what it shows.
  Widget _buildHeader(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.accentOf(context).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            LucideIcons.clock,
            size: 24,
            color: AppColors.accentOf(context),
          ),
        ),
        const SizedBox(width: 16),
        // Flexible, or the title and its subtitle claim their natural width
        // and overflow the row on a narrow screen.
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Timetables',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: AppColors.black,
                  height: 1.1,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Stop departures & arrivals',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: AppColors.black.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// The chosen stop's search field, the time picker and the search action.
  ///
  /// Only once a stop is chosen. Before that this screen is the stop search
  /// itself, and a second field above the first would be a duplicate of it.
  Widget _buildStopControls(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CompositedTransformTarget(
          link: _searchFieldLink,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.hairline),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    LucideIcons.search,
                    size: 20,
                    color: AppColors.black.withValues(alpha: 0.4),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: CupertinoTextField(
                      controller: _searchController,
                      focusNode: _searchFocus,
                      // Opens the picker rather than
                      // typing here: favourites and recents
                      // need more room than a dropdown.
                      readOnly: true,
                      showCursor: false,
                      onTap: () => _searchFocus.unfocus(),
                      placeholder: 'Search for a stop...',
                      placeholderStyle: TextStyle(
                        color: AppColors.black.withValues(alpha: 0.4),
                        fontSize: 16,
                      ),
                      style: TextStyle(color: AppColors.black, fontSize: 16),
                      decoration: null,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      cursorColor: AppColors.accentOf(context),
                      maxLines: 1,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _onSearch(),
                    ),
                  ),
                  if (_searchController.text.isNotEmpty)
                    GestureDetector(
                      onTap: _clearStop,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(
                          LucideIcons.x,
                          size: 20,
                          color: AppColors.black.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            CompositedTransformTarget(
              link: _timeSelectionLayerLink,
              child: PillButton(
                onTapDown: _handleTimeButtonTapDown,
                onTapCancel: _handleTimeButtonTapCancel,
                onTap: _handleTimeButtonTap,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.clock, size: 16, color: AppColors.black),
                    const SizedBox(width: 8),
                    Text(
                      _timeSelection.toDisplayString(),
                      style: TextStyle(
                        color: AppColors.black,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Spacer(),
            PrimaryButton(
              onTap: _onSearch,
              child: const Text(
                'Search',
                style: TextStyle(
                  color: AppColors.solidWhite,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Shown in place of the departures when a load failed, so the chosen stop
  /// stays chosen and the failure is something the rider can act on.
  Widget _buildStopTimesError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ErrorNotice(message: _stopTimesError!, onRetry: _onSearch),
      ),
    );
  }

  Widget _buildStopTimeTile(StopTime stopTime) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          CustomPageRoute(child: ConnectionInfoScreen(tripId: stopTime.tripId)),
        );
      },
      child: _StopTimeCard(stopTime: stopTime),
    );
  }

  Widget _buildLoadingSkeleton() {
    return const SkeletonList(
      itemCount: 8,
      itemHeight: 80,
      listPadding: EdgeInsets.only(left: 20, right: 20, top: 12, bottom: 96),
      itemMargin: EdgeInsets.only(bottom: 12),
      borderRadius: BorderRadius.all(Radius.circular(14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();

    return PopScope(
      canPop: !_searchFocus.hasFocus && !_showTimeSelectionOverlay,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_showTimeSelectionOverlay) {
            _closeTimeSelectionOverlay();
          } else if (_searchFocus.hasFocus) {
            _searchFocus.unfocus();
          }
        }
      },
      child: GestureDetector(
        onTap: () {
          _searchFocus.unfocus();
        },
        child: Container(
          color: AppColors.white,
          child: SafeArea(
            child: Stack(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildHeader(context),
                          const SizedBox(height: 24),
                          if (_selectedStop != null)
                            _buildStopControls(context),
                        ],
                      ),
                    ),

                    Expanded(
                      child: _isLoadingStopTimes
                          ? _buildLoadingSkeleton()
                          : _stopTimesError != null
                          ? _buildStopTimesError()
                          : _stopTimes != null
                          ? BidirectionalPagedList<StopTime>(
                              controller: _resultsScrollController,
                              centerKey: _centerKey,
                              items: _stopTimes!,
                              centerIndex: _centerIndex,
                              itemBuilder: _buildStopTimeTile,
                              hasPrevious: _hasPreviousPage,
                              hasNext: _hasNextPage,
                              isLoadingPrevious: _isLoadingPrevious,
                              isLoadingNext: _isLoadingMore,
                              onLoadPrevious: _loadPrevious,
                              onLoadNext: _loadMore,
                              padding: const EdgeInsets.symmetric(
                                horizontal: _kResultsHorizontalPadding,
                              ),
                              trailingExtent: _kResultsBottomSpacing,
                            )
                          : _buildStopSearch(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StopTimeCard extends StatelessWidget {
  const _StopTimeCard({required this.stopTime});

  final StopTime stopTime;

  @override
  Widget build(BuildContext context) {
    final routeColor = parseHexColorOrAccent(context, stopTime.routeColor);
    final routeTextColor = parseHexColorOr(
      stopTime.routeTextColor,
      AppColors.solidWhite,
    );

    final modeIcon = getLegIcon(stopTime.mode);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.hairline),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              modeIcon,
              size: 24,
              color: AppColors.black.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  RouteBadgePill(
                    label: stopTime.displayName,
                    background: routeColor,
                    foreground: routeTextColor,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    minWidth: RouteBadgePill.stackedMinWidth,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    stopTime.headsign,
                    style: AppText.listTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  GtfsFieldsRow(
                    fields: {
                      'trip': stopTime.tripId,
                      'stop': stopTime.place.stopId,
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DelayedTime.end(
                  ReportedTime.from(
                    stopTime.place.arrival,
                    stopTime.place.scheduledArrival,
                    isLive: stopTime.realTime,
                  ),
                  label: 'Arr',
                  isArrival: true,
                ),
                const SizedBox(height: 4),
                DelayedTime.end(
                  ReportedTime.from(
                    stopTime.place.departure,
                    stopTime.place.scheduledDeparture,
                    isLive: stopTime.realTime,
                  ),
                  label: 'Dep',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
