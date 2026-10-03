import 'dart:async';

import 'package:transportia/services/transitous_geocode_service.dart';
import 'package:transportia/utils/custom_page_route.dart';
import 'package:transportia/utils/leg_helper.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import '../models/time_selection.dart';
import '../widgets/custom_card.dart';
import '../widgets/empty_state.dart';
import '../models/itinerary.dart';
import '../models/my_location.dart';
import '../models/routing_options.dart';
import '../providers/theme_provider.dart';
import '../services/location_service.dart';
import '../services/plan_request.dart';
import '../services/recent_trips_service.dart';
import '../services/routing_options_service.dart';
import '../services/routing_service.dart';
import '../theme/app_colors.dart';
import '../widgets/custom_app_bar.dart';
import '../utils/leg_notices.dart';
import '../utils/color_utils.dart';
import '../utils/duration_formatter.dart';
import '../utils/time_utils.dart';
import 'itinerary_detail_screen.dart';
import '../widgets/bidirectional_paged_list.dart';
import '../widgets/route_badge_pill.dart';
import '../widgets/save_trip_button.dart';
import '../widgets/skeletons/skeleton_list.dart';
import '../theme/app_text.dart';

/// How often each result's "departs in" countdown is redrawn. A minute is
/// the resolution the countdown itself is printed at.
const Duration _kDepartsInTick = Duration(minutes: 1);

class ItineraryListScreen extends StatefulWidget {
  final FutureOr<double> fromLat;
  final FutureOr<double> fromLon;
  final double toLat;
  final double toLon;
  final TimeSelection timeSelection;
  final TransitousLocationSuggestion? fromSelection;
  final TransitousLocationSuggestion? toSelection;

  /// The options this search was configured with.
  ///
  /// Null for journeys nobody configured — a deep link, or a second opinion
  /// on a saved trip — which fall back to the stored defaults. Either way the
  /// value is resolved once and reused for every page, so a later edit to the
  /// defaults cannot make the next page a different search from the first.
  final RoutingOptions? options;

  const ItineraryListScreen({
    super.key,
    required this.fromLat,
    required this.fromLon,
    required this.toLat,
    required this.toLon,
    required this.timeSelection,
    this.options,
    this.fromSelection,
    this.toSelection,
  });

  /// Shows results for a journey the routing screen did not search for, with
  /// the routing screen underneath holding the same journey — so Back lands
  /// where the search can be changed, not on whatever was open before.
  ///
  /// A [from] of My Location is resolved to the rider's position here.
  static Future<void> openOverRoutingScreen(
    NavigatorState navigator, {
    required TransitousLocationSuggestion from,
    required TransitousLocationSuggestion to,
    required TimeSelection time,
  }) async {
    // Resolved once and handed to both, so the fields and the results
    // describe the same search.
    final options = await RoutingOptionsService.load();
    if (!navigator.mounted) return;

    // Asked before the tabs are uncovered: the shell brings the routing tab
    // forward for it and the routing screen takes it from there.
    PlanRequests.ask(
      PlanRequest(from: from, to: to, time: time, options: options),
    );
    navigator.popUntil((route) => route.isFirst);

    final FutureOr<double> fromLat;
    final FutureOr<double> fromLon;
    if (from.isMyLocation) {
      final position = LocationService.currentPosition();
      fromLat = position.then((p) => p.latitude);
      fromLon = position.then((p) => p.longitude);
    } else {
      fromLat = from.lat;
      fromLon = from.lon;
    }
    unawaited(
      navigator.push(
        CupertinoPageRoute(
          builder: (_) => ItineraryListScreen(
            fromLat: fromLat,
            fromLon: fromLon,
            toLat: to.lat,
            toLon: to.lon,
            timeSelection: time,
            options: options,
            fromSelection: from.isMyLocation ? null : from,
            toSelection: to,
          ),
        ),
      ),
    );
  }

  @override
  State<ItineraryListScreen> createState() => _ItineraryListScreenState();
}

class _ItineraryListScreenState extends State<ItineraryListScreen> {
  List<Itinerary> _itineraries = [];
  int _centerIndex = 0;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _nextPageCursor;
  String? _previousPageCursor;
  bool _isLoadingPrevious = false;
  double? _fromLat;
  double? _fromLon;
  RoutingOptions? _options;
  late final ScrollController _scrollController;
  bool _appliedInitialPreviousOffset = false;
  static const Key _centerKey = ValueKey('itineraries-center');

  /// Breathing room under the last result.
  static const double _kListBottomSpacing = 16.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _isLoading = true);
    try {
      final fromLat = await Future<double>.value(widget.fromLat);
      final fromLon = await Future<double>.value(widget.fromLon);
      final options = widget.options ?? await RoutingOptionsService.load();
      _options = options;
      final response = await RoutingService.findRoutesPaginated(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: widget.toLat,
        toLon: widget.toLon,
        timeSelection: widget.timeSelection,
        options: options,
      );
      // The rider can go back before the planner answers.
      if (!mounted) return;
      setState(() {
        _fromLat = fromLat;
        _fromLon = fromLon;
        _itineraries = response.itineraries;
        _centerIndex = 0;
        _nextPageCursor = response.nextPageCursor;
        _previousPageCursor = response.previousPageCursor;
        _isLoading = false;
      });
      _maybeApplyInitialPreviousOffset();
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _nextPageCursor == null) return;
    setState(() => _isLoadingMore = true);
    try {
      final fromLat = _fromLat ?? await Future<double>.value(widget.fromLat);
      final fromLon = _fromLon ?? await Future<double>.value(widget.fromLon);
      final response = await RoutingService.findRoutesPaginated(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: widget.toLat,
        toLon: widget.toLon,
        timeSelection: widget.timeSelection,
        options: _options,
        pageCursor: _nextPageCursor,
      );
      setState(() {
        _fromLat = fromLat;
        _fromLon = fromLon;
        _itineraries.addAll(response.itineraries);
        _nextPageCursor = response.nextPageCursor;
        _previousPageCursor =
            response.previousPageCursor ?? _previousPageCursor;
        _isLoadingMore = false;
      });
    } catch (_) {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _loadPrevious() async {
    if (_isLoadingPrevious || _previousPageCursor == null) return;
    setState(() => _isLoadingPrevious = true);
    try {
      final fromLat = _fromLat ?? await Future<double>.value(widget.fromLat);
      final fromLon = _fromLon ?? await Future<double>.value(widget.fromLon);
      final response = await RoutingService.findRoutesPaginated(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: widget.toLat,
        toLon: widget.toLon,
        timeSelection: widget.timeSelection,
        options: _options,
        pageCursor: _previousPageCursor,
      );

      setState(() {
        _fromLat = fromLat;
        _fromLon = fromLon;
        _itineraries = [...response.itineraries, ..._itineraries];
        _centerIndex += response.itineraries.length;
        _previousPageCursor = response.previousPageCursor;
      });
    } catch (_) {
    } finally {
      setState(() => _isLoadingPrevious = false);
    }
  }

  void _maybeApplyInitialPreviousOffset() {
    if (_appliedInitialPreviousOffset) return;
    if (_previousPageCursor == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scrollPastSeePrevious(_scrollController);
      _appliedInitialPreviousOffset = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          FocusScope.of(context).unfocus();
        }
      },
      child: Container(
        color: AppColors.white,
        child: SafeArea(
          child: Column(
            children: [
              CustomAppBar(
                title: 'Search Results',
                onBackButtonPressed: () {
                  FocusScope.of(context).unfocus();
                  Navigator.of(context).pop();
                },
              ),
              Expanded(
                child: _isLoading
                    ? _buildLoadingSkeleton()
                    : _itineraries.isEmpty
                    ? Center(
                        child: EmptyState(
                          title: 'No routes found.',
                          titleStyle: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.black.withValues(alpha: 0.5),
                          ),
                        ),
                      )
                    : BidirectionalPagedList<Itinerary>(
                        controller: _scrollController,
                        centerKey: _centerKey,
                        items: _itineraries,
                        centerIndex: _centerIndex,
                        itemBuilder: _buildItineraryTile,
                        hasPrevious: _previousPageCursor != null,
                        hasNext: _nextPageCursor != null,
                        isLoadingPrevious: _isLoadingPrevious,
                        isLoadingNext: _isLoadingMore,
                        onLoadPrevious: _loadPrevious,
                        onLoadNext: _loadMore,
                        trailingExtent: _kListBottomSpacing,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItineraryTile(Itinerary itinerary) {
    return GestureDetector(
      onTap: () {
        // Named as the save button names it, so the recent entry and a
        // saved copy of the same connection share an id.
        unawaited(
          RecentTripsService.record(
            itinerary,
            fromName: widget.fromSelection?.name,
            toName: widget.toSelection?.name,
          ),
        );
        Navigator.of(context).push(
          CustomPageRoute(
            child: ItineraryDetailScreen(
              itinerary: itinerary,
              fromName: widget.fromSelection?.name,
              toName: widget.toSelection?.name,
            ),
          ),
        );
      },
      child: ItineraryCard(
        itinerary: itinerary,
        fromName: widget.fromSelection?.name,
        toName: widget.toSelection?.name,
      ),
    );
  }

  Widget _buildLoadingSkeleton() {
    return const SkeletonList(
      itemCount: 5,
      itemHeight: 100,
      itemMargin: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    );
  }
}

class ItineraryCard extends StatefulWidget {
  final Itinerary itinerary;

  /// Passed through to the save action so a kept trip is named after the
  /// places the user searched for.
  final String? fromName;
  final String? toName;

  const ItineraryCard({
    super.key,
    required this.itinerary,
    this.fromName,
    this.toName,
  });

  @override
  State<ItineraryCard> createState() => _ItineraryCardState();
}

class _ItineraryCardState extends State<ItineraryCard>
    with SingleTickerProviderStateMixin {
  late final Timer _departInTimer;
  late final AnimationController _realTimeIconController;

  @override
  void initState() {
    super.initState();
    _departInTimer = Timer.periodic(_kDepartsInTick, (_) {
      if (mounted) setState(() {});
    });
    _realTimeIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _departInTimer.cancel();
    _realTimeIconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itinerary = widget.itinerary;
    final showCalories = context.select<ThemeProvider, bool>(
      (theme) => theme.showCalories,
    );
    final delaySummary = _delaySummaryLabel();
    final hasDeparted = _hasDeparted();
    final departureText = _departureText();
    final firstNonWalkingLeg = itinerary.legs
        .where((leg) => leg.mode != 'WALK')
        .firstOrNull;
    final hasFirstLegRealTime = firstNonWalkingLeg?.realTime ?? false;
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      formatDuration(itinerary.duration),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.black,
                      ),
                    ),
                    Text(
                      departureText,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: hasDeparted
                            ? AppColors.disrupted
                            : AppColors.black.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (itinerary.isDirect) ...[
                    Text(
                      'Direct',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentOf(context),
                      ),
                    ),
                    if (hasFirstLegRealTime) const SizedBox(width: 8),
                  ],
                  if (hasFirstLegRealTime)
                    FadeTransition(
                      opacity: Tween<double>(
                        begin: 1.0,
                        end: 0.4,
                      ).animate(_realTimeIconController),
                      child: Icon(
                        LucideIcons.radio,
                        size: 14,
                        color: AppColors.accentOf(context),
                      ),
                    ),
                  SaveTripButton(
                    itinerary: itinerary,
                    fromName: widget.fromName,
                    toName: widget.toName,
                    size: 18,
                    padding: const EdgeInsets.only(left: 10),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${formatTime(itinerary.startTime)} - ${formatTime(itinerary.endTime)}',
            style: AppText.bodyMuted,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8.0,
            runSpacing: 4.0,
            children: itinerary.legs.map((leg) => LegWidget(leg: leg)).toList(),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 12.0,
              vertical: 10.0,
            ),
            child: SizedBox(
              height: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.black.withValues(alpha: 0.2),
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    LucideIcons.repeat,
                    size: 16,
                    color: AppColors.black.withValues(alpha: 0.6),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${itinerary.transfers}',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.black.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  if (showCalories && itinerary.walkingDistance > 0) ...[
                    Icon(
                      LucideIcons.flame,
                      size: 16,
                      color: AppColors.black.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${itinerary.calories}',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.black.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (delaySummary != null) ...[
                    Icon(
                      LucideIcons.clock,
                      size: 16,
                      color: AppColors.black.withValues(alpha: 0.5),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      delaySummary,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.black.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  // The same count the itinerary's header gives.
                  if (journeyNotices(itinerary.legs).length case final count
                      when count > 0) ...[
                    Icon(
                      LucideIcons.triangleAlert,
                      size: 16,
                      color: AppColors.black.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.black.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (itinerary.hasTicketInfo)
                    Icon(
                      LucideIcons.ticket,
                      size: 16,
                      color: AppColors.black.withValues(alpha: 0.6),
                    ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'More',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentOf(context),
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    LucideIcons.chevronRight,
                    size: 16,
                    color: AppColors.accentOf(context),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _delaySummaryLabel() {
    int affected = 0;
    bool hasPositive(Duration? d) => d != null && d.inMinutes > 0;
    bool hasNegative(Duration? d) => d != null && d.inMinutes < 0;

    for (final leg in widget.itinerary.legs) {
      final depDelay = computeDelay(leg.scheduledStartTime, leg.startTime);
      final arrDelay = computeDelay(leg.scheduledEndTime, leg.endTime);
      if (hasPositive(depDelay) ||
          hasPositive(arrDelay) ||
          hasNegative(depDelay) ||
          hasNegative(arrDelay)) {
        affected++;
      }
    }

    if (affected == 0) return null;
    return '$affected';
  }

  int _secondsUntilDeparture() {
    return widget.itinerary.startTime.difference(DateTime.now()).inSeconds;
  }

  bool _hasDeparted() => _secondsUntilDeparture() <= 0;

  String _departureText() {
    final secondsUntil = _secondsUntilDeparture();
    if (secondsUntil <= 0) return 'Departed';
    if (secondsUntil < 60) return 'Depart now';
    return 'Depart in ${formatDuration(secondsUntil)}';
  }
}

class LegWidget extends StatelessWidget {
  final Leg leg;

  const LegWidget({super.key, required this.leg});

  @override
  Widget build(BuildContext context) {
    IconData icon = getLegIcon(leg.mode);
    final routeColor = parseHexColor(leg.routeColor);
    final badgeColor =
        routeColor ??
        (leg.mode == 'WALK'
            ? const Color(0x00000000)
            : AppColors.accentOf(context));
    final labelColor =
        parseHexColor(leg.routeTextColor) ??
        (routeColor == null && leg.mode != 'WALK'
            ? AppColors.solidWhite
            : AppColors.black);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 18,
          child: Center(
            child: Icon(
              icon,
              size: 16,
              color: AppColors.black.withValues(alpha: 0.5),
            ),
          ),
        ),
        const SizedBox(width: 4),
        if (leg.displayName != null)
          RouteBadgePill(
            label: leg.displayName!.isNotEmpty
                ? leg.displayName!
                : getTransitModeName(leg.mode),
            background: badgeColor,
            foreground: labelColor,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            fontSize: 14,
          ),
      ],
    );
  }
}
