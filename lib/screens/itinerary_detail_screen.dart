import 'dart:async';

import 'package:transportia/widgets/load_more_button.dart';
import 'package:transportia/widgets/share_trip_sheet.dart';
import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/itinerary.dart';
import '../models/saved_trip.dart';
import '../models/time_selection.dart';
import '../providers/theme_provider.dart';
import '../services/itinerary_refresh_service.dart';
import '../services/plan_request.dart';
import '../services/saved_trips_service.dart';
import '../utils/haptics.dart';
import '../services/routing_options_service.dart';
import '../services/transitous_geocode_service.dart';
import '../theme/app_colors.dart';
import '../theme/journey_metrics.dart';
import '../utils/changeover.dart';
import '../utils/color_utils.dart';
import '../utils/custom_page_route.dart';
import '../utils/duration_formatter.dart';
import '../utils/itinerary_leg_utils.dart';
import '../utils/journey_colors.dart';
import '../utils/journey_progress.dart';
import '../utils/leg_helper.dart';
import '../utils/reported_time.dart';
import '../utils/time_utils.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/custom_card.dart';
import '../utils/leg_notices.dart';
import '../widgets/gtfs_fields_row.dart';
import '../widgets/journey/leg_notice_stack.dart';
import '../widgets/journey/spine_node.dart';
import '../widgets/journey/spine_row.dart';
import '../widgets/info_chip.dart';
import '../widgets/last_updated_footer.dart';
import '../widgets/pressable_highlight.dart';
import '../widgets/route_badge_pill.dart';
import '../widgets/save_trip_button.dart';
import '../widgets/stop_departures_sheet.dart';
import 'connection_info_screen.dart';
import 'itinerary_list_screen.dart';
import 'itinerary_map_screen.dart';
import '../theme/app_text.dart';

/// Opens the [StopDeparturesSheet] for a tapped stop. Passed down through
/// the leg widgets so they don't need to know how the sheet is presented.
typedef OpenStopSheet =
    void Function({
      required String? stopId,
      required String stopName,
      required DateTime referenceTime,
    });

/// The first line of a node's text, and the first line of a stop's.
///
/// Both carry an explicit `height` because [SpineRow] centres its columns on
/// the node using a line height the caller states — measuring the real one
/// would need an intrinsic pass, and the height of an expanding leg is
/// mid-animation exactly when that would run.
const double kSpineNameLineHeight = 20;
const double kSpineStopLineHeight = 18;

/// A delay sits on its own line under the time it belongs to. Explicit for
/// the same reason: [SpineTimes] has to know how tall its own stack is.
const double kSpineDelayLineHeight = 14;

/// Where a minor stop's dot sits, measured from the row's top. Tighter than a
/// node's, because a passed-through stop is a smaller mark and does not need
/// a ring's worth of room.
const double kSpineMinorNodeCenter = 11;

const TextStyle kSpineNameStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w700,
  height: kSpineNameLineHeight / 16,
);

const TextStyle kSpineStopStyle = TextStyle(
  fontSize: 15,
  fontWeight: FontWeight.w400,
  height: kSpineStopLineHeight / 15,
);

/// One point on the line: what gets here, and what leaves.
///
/// Both columns that flank the spine — the times and the platforms — are built
/// from the same point, so they agree on whether there is an arrival line at
/// all. Without that agreement a row with an arrival *time* but no arrival
/// *platform* would print its two columns one line out of step.
class SpinePoint {
  final ReportedTime? arrival;
  final ReportedTime? departure;

  const SpinePoint._(this.arrival, this.departure);

  factory SpinePoint({
    DateTime? arrival,
    DateTime? departure,
    DateTime? scheduledArrival,
    DateTime? scheduledDeparture,
    bool arrivalIsLive = false,
    bool departureIsLive = false,
  }) {
    final gotHere = ReportedTime.from(
      arrival,
      scheduledArrival,
      isLive: arrivalIsLive,
    );
    final leaves = ReportedTime.from(
      departure,
      scheduledDeparture,
      isLive: departureIsLive,
    );
    // Arriving and leaving at the same moment is passing through, not waiting;
    // printing the number twice would say nothing.
    //
    // Which of the two to keep is not arbitrary. At a change, a live and late
    // arrival lands on the same minute as the walk that follows it, and a walk
    // has no real-time at all — so keeping the departure threw away the one
    // reading that came from an observation, and the row printed a plain
    // black time over a train that was ten minutes down. The same moment
    // described twice keeps the description that was observed.
    if (gotHere != null && leaves != null && gotHere.shown == leaves.shown) {
      final observed = gotHere.isLive && !leaves.isLive ? gotHere : leaves;
      return SpinePoint._(null, observed);
    }
    // A point with only an arrival is an end of the line: that time takes the
    // anchor, because there is no departure to give it to.
    if (leaves == null) return SpinePoint._(null, gotHere);
    return SpinePoint._(gotHere, leaves);
  }

  /// True when something is printed above the anchor, and therefore when the
  /// row has to reserve room for it.
  bool get showsArrival => arrival != null;

  bool get isEmpty => arrival == null && departure == null;

  /// The delay worth naming under the station: the one you act on, which is
  /// the departure's whenever there is one.
  Duration? get delayToShow => departure?.delay ?? arrival?.delay;
}

/// Two lines that mirror each other down the row: what arrives, light and
/// above the anchor, and what leaves, on it.
///
/// [reserveAbove] keeps the upper slot empty rather than collapsing it, so a
/// column with nothing to say up there still lines up with one that has.
class SpineStack extends StatelessWidget {
  const SpineStack({
    super.key,
    required this.anchor,
    required this.lineHeight,
    this.above,
    this.reserveAbove = false,
  });

  final Widget anchor;
  final Widget? above;
  final bool reserveAbove;
  final double lineHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (above case final above?)
          above
        else if (reserveAbove)
          SizedBox(height: lineHeight),
        anchor,
      ],
    );
  }
}

/// When a service gets to a point on the line, and when it leaves again.
///
/// Both are the *real* times wherever the operator reports them; the planned
/// time is never printed beside them. Colour says which is which — see
/// [spineTimeColor].
class SpineTimes extends StatelessWidget {
  const SpineTimes({super.key, required this.point, this.compact = false});

  final SpinePoint point;

  /// The tighter type an intermediate stop gets.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (point.isEmpty) return const SizedBox.shrink();
    final lineHeight = compact ? kSpineStopLineHeight : kSpineNameLineHeight;

    return SpineStack(
      lineHeight: lineHeight,
      above: point.arrival == null
          ? null
          : _time(point.arrival!, isArrival: true, lineHeight: lineHeight),
      anchor: point.departure == null
          ? SizedBox(height: lineHeight)
          : _time(point.departure!, isArrival: false, lineHeight: lineHeight),
    );
  }

  Widget _time(
    ReportedTime time, {
    required bool isArrival,
    required double lineHeight,
  }) {
    final size = compact ? 13.0 : 14.0;
    return Text(
      formatTime(time.shown),
      // A time is one line. Half a clock reading over two would be worse than
      // a tight fit, and it would put the columns out of step.
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: size,
        fontWeight: isArrival ? FontWeight.w500 : FontWeight.w700,
        height: lineHeight / size,
        color: spineTimeColor(
          isLive: time.isLive,
          delay: time.delay,
          isArrival: isArrival,
        ),
      ),
    );
  }
}

/// How late the service is, under the name of the station it is late at, in
/// [delayNoteColor].
///
/// One line, and the departure's whenever there is one: a station with an
/// arrival delay, a departure delay and both of their times stacked against it
/// is four numbers where a rider wanted one.
Widget? buildSpineDelay(SpinePoint point, {bool compact = false}) {
  final delay = point.delayToShow;
  if (delay == null) return null;
  final size = compact ? 11.5 : 12.5;
  return Padding(
    padding: const EdgeInsets.only(top: 1),
    child: Text(
      formatDelay(delay),
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        height: kSpineDelayLineHeight / size,
        color: delayNoteColor(),
      ),
    ),
  );
}

/// The platforms, laid out to mirror [SpineTimes] line for line.
///
/// The one you arrive at sits above in grey, the one you leave from on the
/// anchor in black — the same shape as the times beside them, so the eye can
/// read across.
class SpineTracks extends StatelessWidget {
  const SpineTracks({
    super.key,
    this.arrival,
    this.departure,
    this.placeholderForDeparture = false,
    required this.reserveAbove,
    this.compact = false,
  });

  final String? arrival;
  final String? departure;

  /// Marks an absent departure platform on the modes that run to numbered
  /// ones, where not knowing is itself worth saying.
  final bool placeholderForDeparture;

  final bool reserveAbove;
  final bool compact;

  static String? _clean(String? track) {
    final trimmed = track?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final lineHeight = compact ? kSpineStopLineHeight : kSpineNameLineHeight;
    final departure = _clean(this.departure);
    // The platform walked to is the platform departed from, so a change put
    // the same number on both lines — "Track 11" over "Track 11", true twice
    // and useful once. Where they really differ, both stay.
    final arrival = _clean(this.arrival) == departure
        ? null
        : _clean(this.arrival);

    if (arrival == null && departure == null && !placeholderForDeparture) {
      return const SizedBox.shrink();
    }

    return SpineStack(
      lineHeight: lineHeight,
      reserveAbove: reserveAbove,
      above: arrival == null
          ? null
          : _track(
              arrival,
              lineHeight: lineHeight,
              alpha: 0.4,
              weight: FontWeight.w500,
            ),
      anchor: departure != null
          ? _track(
              departure,
              lineHeight: lineHeight,
              alpha: 0.8,
              weight: FontWeight.w700,
            )
          : _track(
              '—',
              lineHeight: lineHeight,
              alpha: 0.3,
              weight: FontWeight.w500,
            ),
    );
  }

  Widget _track(
    String track, {
    required double lineHeight,
    required double alpha,
    required FontWeight weight,
  }) {
    final size = compact ? 12.0 : 13.0;
    return Text(
      track == '—' ? 'Track —' : 'Track $track',
      maxLines: 1,
      softWrap: false,
      style: TextStyle(
        fontSize: size,
        fontWeight: weight,
        height: lineHeight / size,
        color: AppColors.black.withValues(alpha: alpha),
      ),
    );
  }
}

/// How often the "updated N ago" line and the progress fade are redrawn.
const Duration _kAgoTick = Duration(seconds: 30);

class ItineraryDetailScreen extends StatefulWidget {
  final Itinerary itinerary;

  /// Set when this screen is showing a stored connection rather than a
  /// result the user just searched for.
  ///
  /// A stored connection is stale by definition, so it is re-checked on
  /// open and the screen says what that check found.
  final SavedTrip? savedTrip;

  /// The places the user searched for, so saving from here names the trip
  /// the same way saving from the results list does.
  final String? fromName;
  final String? toName;

  const ItineraryDetailScreen({
    super.key,
    required this.itinerary,
    this.savedTrip,
    this.fromName,
    this.toName,
  });

  @override
  State<ItineraryDetailScreen> createState() => _ItineraryDetailScreenState();
}

class _ItineraryDetailScreenState extends State<ItineraryDetailScreen> {
  late Itinerary _itinerary;
  DateTime? _lastUpdated;
  bool _isRefreshing = false;
  Timer? _agoTicker;
  ItineraryFreshness? _freshness;

  @override
  void initState() {
    super.initState();
    _itinerary = widget.itinerary;

    // What the screen opens on, before the check below answers. A search
    // result was fetched moments ago; a saved trip carries whatever the last
    // live check folded into it, so it opens on those times and says how old
    // they are rather than showing the plan and claiming to know nothing.
    _lastUpdated = widget.savedTrip == null
        ? DateTime.now()
        : widget.savedTrip!.liveUpdatedAt;

    // Every open re-checks, not only a pull. Whether a change can still be
    // made is a claim about right now, and a screen that had been sat in
    // front of for twenty minutes was making it from whatever the list
    // screen had fetched. `_refreshRealTimeInfo` guards its own re-entry.
    unawaited(_refreshRealTimeInfo());

    _agoTicker = Timer.periodic(_kAgoTick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _agoTicker?.cancel();
    super.dispose();
  }

  void _openStopSheet({
    required String? stopId,
    required String stopName,
    required DateTime referenceTime,
  }) => showStopDeparturesSheet(
    context,
    stopId: stopId,
    stopName: stopName,
    referenceTime: referenceTime,
  );

  /// Opens the journey map on one leg.
  ///
  /// Walking, cycling and changing are the legs whose shape is the whole
  /// question — which side of the station, which exit, how far — and the
  /// answer is on the map rather than in the row. Transit legs keep their tap
  /// for expanding the stops they call at.
  void _showLegOnMap(int displayLegIndex) {
    Haptics.lightTick();
    Navigator.of(context).push(
      CustomPageRoute(
        child: ItineraryMapScreen(
          itinerary: _itinerary,
          initialLegIndex: displayLegIndex,
        ),
      ),
    );
  }

  Future<void> _refreshRealTimeInfo() async {
    if (_isRefreshing) return;

    _isRefreshing = true;
    // The refresh re-plans, so it needs the settings the journey was planned
    // under; without them the server answers with its own defaults and the
    // street legs come back unrouted.
    final result = await ItineraryRefreshService.refresh(
      _itinerary,
      options: await RoutingOptionsService.load(),
    );

    if (!mounted) {
      _isRefreshing = false;
      return;
    }

    // Only move the timestamp when live data actually arrived, so a pull
    // that reached nothing does not read as a successful refresh.
    final now = DateTime.now();
    setState(() {
      _freshness = result.freshness;
      if (result.didRefresh) {
        _itinerary = result.itinerary;
        _lastUpdated = now;
      }
    });

    // Keep what the check found, so a restart opens on it instead of on the
    // plan. The service decides whether this result may overwrite the stored
    // connection — a refresh that came back with a different one may not.
    final saved = widget.savedTrip;
    if (saved != null) {
      unawaited(
        SavedTripsService.storeLiveItinerary(
          id: saved.id,
          refreshed: result.itinerary,
          didRefresh: result.didRefresh,
          freshness: result.freshness,
          at: now,
        ),
      );
    }

    _isRefreshing = false;
  }

  /// Re-plans the same journey, so the user has somewhere to go when the
  /// stored connection no longer works.
  void _findAlternatives(SavedTrip trip, {required DateTime departAt}) {
    unawaited(
      ItineraryListScreen.openOverRoutingScreen(
        Navigator.of(context),
        from: TransitousLocationSuggestion(
          id: 'saved-from-${trip.id}',
          name: trip.fromName,
          lat: trip.fromLat,
          lon: trip.fromLon,
          type: 'PLACE',
        ),
        to: TransitousLocationSuggestion(
          id: 'saved-to-${trip.id}',
          name: trip.toName,
          lat: trip.toLat,
          lon: trip.toLon,
          type: 'PLACE',
        ),
        time: TimeSelection(dateTime: departAt, isArriveBy: false),
      ),
    );
  }

  /// Hands the routing screen a journey that still works, and stops there.
  ///
  /// Deliberately not a search. A rider whose connection has just broken is
  /// the last person to hand a fixed answer to — they may want a different
  /// destination, a later train, or to give up and walk. The fields arrive
  /// filled in and the Search button is theirs to press.
  void _replanFromHere() {
    final replan = replanFor(_itinerary.legs, DateTime.now());
    if (replan == null) return;

    PlanRequests.ask(
      PlanRequest(
        from: _suggestionFor(replan.from, 'replan-from'),
        to: _suggestionFor(replan.to, 'replan-to'),
        time: TimeSelection(dateTime: replan.departAt, isArriveBy: false),
      ),
    );
    // Back to the tabs, where the routing screen is waiting with it.
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// A place from the itinerary, in the shape the route fields take.
  ///
  /// The stop's own id where it has one, so the field reads as a station
  /// rather than a pair of coordinates.
  TransitousLocationSuggestion _suggestionFor(TransitPlace place, String tag) =>
      TransitousLocationSuggestion(
        id: place.stopId ?? '$tag-${place.lat},${place.lon}',
        name: place.name,
        lat: place.lat,
        lon: place.lon,
        type: place.isStop ? 'STOP' : 'PLACE',
      );

  /// The next time today or tomorrow that this trip's departure comes
  /// round, for repeating a journey already taken.
  DateTime _nextOccurrence(DateTime departure) {
    final local = departure.toLocal();
    final now = DateTime.now();
    final today = DateTime(
      now.year,
      now.month,
      now.day,
      local.hour,
      local.minute,
    );
    return today.isAfter(now) ? today : today.add(const Duration(days: 1));
  }

  /// The one thing worth saying about a saved trip's current state, or null
  /// when it is simply live and on time.
  Widget? _savedTripNotice() {
    final trip = widget.savedTrip;
    if (trip == null) return null;

    if (trip.isPast) {
      return _JourneyNotice(
        icon: LucideIcons.history,
        message: 'This trip has already happened.',
        actionLabel: 'Search again',
        onAction: () => _findAlternatives(
          trip,
          departAt: _nextOccurrence(trip.departureTime),
        ),
      );
    }

    final isCancelled =
        _freshness == ItineraryFreshness.changed ||
        _itinerary.legs.any((leg) => leg.cancelled);
    if (isCancelled) {
      return _JourneyNotice(
        icon: LucideIcons.triangleAlert,
        message: 'This connection has changed.',
        actionLabel: 'Find alternatives',
        tint: AppColors.disrupted,
        onAction: () => _findAlternatives(trip, departAt: trip.departureTime),
      );
    }

    if (_freshness == ItineraryFreshness.scheduled) {
      return _JourneyNotice(
        icon: LucideIcons.calendarClock,
        message: "Scheduled times — live data isn't available yet.",
      );
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    final displayLegs = buildDisplayLegs(_itinerary.legs);
    final changeovers = changeoversOf(displayLegs);
    final savedTripNotice = _savedTripNotice();
    // Read once per build so every row on screen agrees about where the
    // traveller is. `_agoTicker` already rebuilds twice a minute, which is
    // what makes the fade advance without any machinery of its own.
    final progress = JourneyProgress(DateTime.now());

    return Container(
      color: AppColors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomAppBar(
              title: 'Itinerary Details',
              onBackButtonPressed: () => Navigator.of(context).pop(),
              trailing: SaveTripButton(
                itinerary: _itinerary,
                fromName: widget.fromName ?? widget.savedTrip?.fromName,
                toName: widget.toName ?? widget.savedTrip?.toName,
              ),
            ),
            JourneyOverviewWidget(
              itinerary: _itinerary,
              changeovers: changeovers,
              onFindAlternatives: _replanFromHere,
            ),
            if (savedTripNotice != null) savedTripNotice,
            Expanded(
              child: _buildDetailList(displayLegs, changeovers, progress),
            ),
          ],
        ),
      ),
    );
  }

  /// The cards under the overview, in the order they are read.
  ///
  /// Each section is a builder rather than a widget so the list stays lazy,
  /// and the delegate indexes into it rather than reconstructing where each
  /// card falls from a running count.
  List<Widget Function()> _buildDetailSections(
    List<DisplayLegInfo> displayLegs,
    List<Changeover> changeovers,
    JourneyProgress progress,
  ) {
    return [
      if (_itinerary.hasTicketInfo)
        () => TicketInfoCard(ticketInfo: _itinerary.ticketInfo),
      if (displayLegs.isEmpty)
        _buildNoStepsMessage
      else
        for (int i = 0; i < displayLegs.length; i++)
          () => _buildLegCard(displayLegs, changeovers, progress, i),
      if (_itinerary.legs.isNotEmpty)
        () => FinishLegCard(
          leg: _itinerary.legs.last,
          arrivalTime: _itinerary.endTime,
          totalDuration: _itinerary.duration,
          openStopSheet: _openStopSheet,
          progress: progress,
        ),
      () => LoadMoreButton(
        onTap: _shareItinerary,
        isLoading: false,
        label: 'Share this trip',
        icon: LucideIcons.share2,
      ),
      () => LastUpdatedFooter(lastUpdated: _lastUpdated),
    ];
  }

  Widget _buildDetailList(
    List<DisplayLegInfo> displayLegs,
    List<Changeover> changeovers,
    JourneyProgress progress,
  ) {
    final sections = _buildDetailSections(displayLegs, changeovers, progress);
    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: _refreshRealTimeInfo),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => sections[index](),
              childCount: sections.length,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNoStepsMessage() => Padding(
    padding: const EdgeInsets.all(16),
    child: Center(
      child: Text(
        'No additional steps required for this journey.',
        style: AppText.bodyFaint,
      ),
    ),
  );

  Widget _buildLegCard(
    List<DisplayLegInfo> displayLegs,
    List<Changeover> changeovers,
    JourneyProgress progress,
    int legIndex,
  ) {
    final entry = displayLegs[legIndex];
    // A node belongs to the leg arriving at it as well as the one leaving it,
    // and where those times differ you waited there.
    final previous = legIndex > 0 ? displayLegs[legIndex - 1].leg : null;

    if (entry.isTransfer) {
      return TransferLegCard(
        leg: entry.leg,
        previousLeg: previous,
        changeover: changeovers
            .where((c) => identical(c.transfer, entry.leg))
            .firstOrNull,
        openStopSheet: _openStopSheet,
        onShowOnMap: () => _showLegOnMap(legIndex),
        progress: progress,
      );
    }
    return LegDetailsWidget(
      leg: entry.leg,
      previousLeg: previous,
      openStopSheet: _openStopSheet,
      onShowOnMap: () => _showLegOnMap(legIndex),
      progress: progress,
    );
  }

  void _shareItinerary() {
    if (_itinerary.legs.isEmpty) return;
    showShareTripSheet(
      context,
      itinerary: _itinerary,
      fromName: widget.fromName ?? widget.savedTrip?.fromName,
      toName: widget.toName ?? widget.savedTrip?.toName,
    );
  }
}

/// A short line about the journey's current state, with the one action that
/// makes sense for it: it has already happened, its connection has changed,
/// or a change on it can no longer be made.
class _JourneyNotice extends StatelessWidget {
  const _JourneyNotice({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.tint,
    this.margin = const EdgeInsets.fromLTRB(12, 0, 12, 8),
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? tint;

  /// Zero inside the overview, which supplies its own padding.
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    final color = tint ?? AppColors.accentOf(context);
    final actionLabel = this.actionLabel;

    return CustomCard.filled(
      margin: margin,
      padding: const EdgeInsets.all(12),
      backgroundColor: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.black.withValues(alpha: 0.8),
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(LucideIcons.chevronRight, size: 15, color: color),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class JourneyOverviewWidget extends StatelessWidget {
  final Itinerary itinerary;

  /// Every change in the journey, already judged.
  ///
  /// Passed in rather than worked out here, so the banner and the row it
  /// points at cannot end up disagreeing about which change is broken.
  final List<Changeover> changeovers;

  final VoidCallback? onFindAlternatives;

  const JourneyOverviewWidget({
    super.key,
    required this.itinerary,
    this.changeovers = const [],
    this.onFindAlternatives,
  });

  /// The heading over a journey that no longer connects.
  ///
  /// Names the first break, because that is the one you reach and the one the
  /// search below starts from; a count carries the rest without listing
  /// stations nobody has got to yet.
  static String missedChangeMessage(List<Changeover> missed) {
    final first = 'You will not make the change at ${missed.first.placeName}.';
    if (missed.length == 1) return first;
    final rest = missed.length - 1;
    return '$first ${rest == 1 ? '1 more change' : '$rest more changes'} '
        'after it will not be made either.';
  }

  @override
  Widget build(BuildContext context) {
    final showCalories = context.select<ThemeProvider, bool>(
      (theme) => theme.showCalories,
    );
    // No box. It is the head of the journey, not a notice about it, and the
    // spine below it is boxless too — a card here made the screen read as a
    // card followed by a drawing. A rule and some air separate it instead,
    // and its padding matches the rows' so the map icon lands on the same
    // right edge as every leg's.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        JourneyMetrics.screenPadding,
        4,
        JourneyMetrics.screenPadding,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Departure', style: AppText.caption),
                    const SizedBox(height: 4),
                    Text(
                      formatTime(itinerary.startTime),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.black,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    const Icon(LucideIcons.clock, size: 20),
                    const SizedBox(height: 4),
                    Text(
                      formatDuration(itinerary.duration),
                      style: AppText.bodyStrong,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Arrival', style: AppText.caption),
                    const SizedBox(height: 4),
                    Text(
                      formatTime(itinerary.endTime),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.black,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              // Given the row's width so it can wrap: sized by its chips, a
              // journey with transfers, calories, a fare and alerts ran off
              // the right edge of a narrow phone.
              Expanded(
                child: Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _buildStatChip(
                      LucideIcons.repeat,
                      '${itinerary.transfers}',
                      itinerary.transfers == 1 ? 'transfer' : 'transfers',
                    ),
                    if (showCalories && itinerary.walkingDistance > 0)
                      _buildStatChip(
                        LucideIcons.flame,
                        '${itinerary.calories}',
                        'cal',
                      ),
                    if (itinerary.fare != null && itinerary.fare!.amount > 0)
                      _buildStatChip(
                        LucideIcons.banknote,
                        '${itinerary.fare!.amount.toStringAsFixed(2)}',
                        itinerary.fare!.currency,
                      ),
                    // The blocks below, counted: an alert said on two stops is
                    // one block, and a missed change is one too.
                    if (journeyNotices(itinerary.legs).length case final count
                        when count > 0)
                      _buildStatChip(
                        LucideIcons.triangleAlert,
                        '$count',
                        count == 1 ? 'alert' : 'alerts',
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    CustomPageRoute(
                      child: ItineraryMapScreen(itinerary: itinerary),
                    ),
                  );
                },
                child: Semantics(
                  button: true,
                  label: 'Show the whole journey on the map',
                  child: Icon(
                    LucideIcons.map,
                    // The same size the legs use, on the same edge.
                    size: 16,
                    color: AppColors.accentOf(context),
                  ),
                ),
              ),
            ],
          ),
          // Above the rule, because it is a fact about this journey rather
          // than a note appended to it: whatever the times below say, they
          // stop being true here.
          if ([
                for (final c in changeovers)
                  if (c.isMissed) c,
              ]
              case final missed when missed.isNotEmpty) ...[
            const SizedBox(height: 14),
            _JourneyNotice(
              icon: LucideIcons.triangleAlert,
              message: missedChangeMessage(missed),
              tint: kMissedChangeColor,
              margin: EdgeInsets.zero,
              // The same words the cancelled-trip notice uses, since it is
              // the same offer.
              actionLabel: onFindAlternatives == null
                  ? null
                  : 'Find alternatives',
              onAction: onFindAlternatives,
            ),
          ],
          const SizedBox(height: 14),
          Container(height: 1, color: AppColors.black.withValues(alpha: 0.08)),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.black.withValues(alpha: 0.6)),
        const SizedBox(width: 4),
        Text(
          '$value $label',
          style: TextStyle(
            fontSize: 14,
            color: AppColors.black.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class TicketInfoCard extends StatefulWidget {
  final List<FareLegInfo> ticketInfo;

  const TicketInfoCard({super.key, required this.ticketInfo});

  @override
  State<TicketInfoCard> createState() => _TicketInfoCardState();
}

class _TicketInfoCardState extends State<TicketInfoCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => setState(() => _isExpanded = !_isExpanded),
      child: CustomCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  LucideIcons.ticket,
                  size: 18,
                  color: AppColors.accentOf(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Ticket information', style: AppText.bodyStrong),
                ),
                Icon(
                  _isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 16,
                  color: AppColors.accentOf(context),
                ),
              ],
            ),
            if (_isExpanded) ...[
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: SizedBox(
                  height: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Color(0x33000000)),
                  ),
                ),
              ),
              ...widget.ticketInfo.map(_buildFareLegOptions),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFareLegOptions(FareLegInfo legInfo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (legInfo.routeBadges.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    'Valid for',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.black.withValues(alpha: 0.5),
                    ),
                  ),
                  ...legInfo.routeBadges.map(_buildRouteBadge),
                ],
              ),
            ),
          ...legInfo.options.map(_buildFareOption),
          if (legInfo.ticketUrl != null || legInfo.fareUrl != null)
            _buildFareLink(legInfo),
        ],
      ),
    );
  }

  /// A direct ticket-purchase link where the agency gives one, and its
  /// general fare page otherwise; never both.
  Widget _buildFareLink(FareLegInfo legInfo) {
    final isTicketLink = legInfo.ticketUrl != null;
    final url = legInfo.ticketUrl ?? legInfo.fareUrl!;
    final accent = AppColors.accentOf(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: PressableHighlight(
        onPressed: () => unawaited(_openFareUrl(url)),
        borderRadius: BorderRadius.circular(8),
        enableHaptics: false,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isTicketLink ? LucideIcons.ticket : LucideIcons.info,
              size: 14,
              color: accent,
            ),
            const SizedBox(width: 6),
            Text(
              isTicketLink ? 'Buy tickets' : 'More info',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openFareUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // A link that will not open has nothing to fall back to.
    }
  }

  Widget _buildRouteBadge(RouteBadge badge) {
    final routeColor = parseHexColor(badge.routeColor);
    return RouteBadgePill(
      label: badge.name,
      background: routeColor ?? AppColors.accentOf(context),
      foreground:
          parseHexColor(badge.routeTextColor) ??
          (routeColor == null ? AppColors.solidWhite : AppColors.black),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      fontWeight: FontWeight.w700,
    );
  }

  Widget _buildFareOption(FareOption option) {
    final label = option.products.map((p) => p.name).join(' + ');
    final price = option.products
        .map((p) => '${p.amount.toStringAsFixed(2)} ${p.currency}')
        .join(' + ');
    final media = option.products
        .map((p) => p.fareMediaName)
        .whereType<String>()
        .where((m) => m.isNotEmpty)
        .toSet()
        .join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.black.withValues(alpha: 0.8),
                  ),
                ),
                if (media.isNotEmpty) Text(media, style: AppText.caption),
              ],
            ),
          ),
          Text(price, style: AppText.bodyStrong),
        ],
      ),
    );
  }
}

class LegDetailsWidget extends StatefulWidget {
  final Leg leg;
  final OpenStopSheet openStopSheet;

  /// Used by street legs, whose row cannot show which way they actually go.
  final VoidCallback? onShowOnMap;

  /// The leg that arrives at this one's node.
  ///
  /// A node belongs to two legs at once — one gets in, the other leaves — and
  /// where those times differ you waited there. Without this the row could
  /// only show the departure.
  final Leg? previousLeg;

  /// Where the clock says the traveller has got to, which decides how much of
  /// this leg's line is drawn as already ridden.
  final JourneyProgress progress;

  const LegDetailsWidget({
    super.key,
    required this.leg,
    required this.openStopSheet,
    this.onShowOnMap,
    this.previousLeg,
    this.progress = JourneyProgress.never,
  });

  @override
  State<LegDetailsWidget> createState() => _LegDetailsWidgetState();
}

class _LegDetailsWidgetState extends State<LegDetailsWidget> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isStreet = isStreetLeg(widget.leg.mode);
    final color = _legColor(context);
    final point = _point;
    final previous = widget.previousLeg;

    final progress = widget.progress;
    final boarded = progress.hasPassed(widget.leg.startTime);
    // Expanded, this row's line reaches only as far as the first stop; the
    // rest of the leg belongs to the stop rows below it.
    final railEndsAt = _isExpanded && !isStreet
        ? (widget.leg.intermediateStops.firstOrNull?.arrival ??
              widget.leg.endTime)
        : widget.leg.endTime;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SpineRow(
          // The ring is the node: it says what you board here, and the line
          // grows out of its underside in that service's colour.
          node: SpineNode(
            icon: getLegIcon(widget.leg.mode),
            color: boarded ? _faded(color) : color,
            semanticLabel: getTransitModeName(widget.leg.mode),
          ),
          railColor: color,
          railDashed: isStreet,
          railTravelled: progress.fractionBetween(
            widget.leg.startTime,
            railEndsAt,
          ),
          // Everything that got you to this ring is behind you once you are
          // standing at it.
          railAboveTravelled: boarded ? 1 : 0,
          // The leg owns the line from its own ring down to the next one; the
          // stretch above the ring belongs to whatever arrived here.
          aboveAnchor: point.showsArrival ? kSpineNameLineHeight : 0,
          railTopInset:
              (point.showsArrival ? kSpineNameLineHeight : 0) +
              JourneyMetrics.ring,
          railAboveColor: previous == null
              ? null
              : legSpineColor(
                  leg: previous,
                  background: AppColors.white,
                  accent: AppColors.accentOf(context),
                ),
          railAboveDashed: previous != null && isStreetLeg(previous.mode),
          firstLineHeight: kSpineNameLineHeight,
          time: SpineTimes(point: point),
          meta: _buildMeta(context, isStreet: isStreet, point: point),
          body: _buildBody(point: point),
          footer: _buildFooter(context, isStreet: isStreet),
          // A street leg has no stops to unfold, so its tap is free for the
          // map; a transit leg's tap unfolds the stops it calls at.
          onTap: isStreet
              ? widget.onShowOnMap
              : () => setState(() => _isExpanded = !_isExpanded),
        ),
        if (_isExpanded && !isStreet) ..._buildStopRows(color),
      ],
    );
  }

  Color _legColor(BuildContext context) => legSpineColor(
    leg: widget.leg,
    background: AppColors.white,
    accent: AppColors.accentOf(context),
  );

  /// A marker for somewhere already reached, in the same wash as the line
  /// behind the traveller.
  ///
  /// A stop row's line is drawn from the row's top, which is a little above
  /// its dot, so the fade there is a marker's height out for as long as you
  /// stand at that stop. A leg row is exact — its line starts at the ring.
  static Color _faded(Color color) =>
      color.withValues(alpha: color.a * kTravelledOpacity);

  /// When this leg leaves, and when the one before it got in.
  ///
  /// A node is shared between the leg arriving at it and the leg leaving it.
  /// Where the two differ you waited there, so both are printed.
  SpinePoint get _point => SpinePoint(
    arrival: widget.previousLeg?.endTime,
    scheduledArrival: widget.previousLeg?.scheduledEndTime,
    arrivalIsLive: widget.previousLeg?.realTime ?? false,
    departure: widget.leg.startTime,
    scheduledDeparture: widget.leg.scheduledStartTime,
    departureIsLive: widget.leg.realTime,
  );

  /// The right-hand column: the platforms, laid out to mirror the times, or
  /// the way to the map on a leg that has no platform to give.
  Widget? _buildMeta(
    BuildContext context, {
    required bool isStreet,
    required SpinePoint point,
  }) {
    if (isStreet) {
      // The whole row has always opened the map; nothing said so.
      if (widget.onShowOnMap == null) return null;
      return Semantics(
        button: true,
        label: 'Show this leg on the map',
        child: Icon(
          LucideIcons.map,
          size: 16,
          color: AppColors.accentOf(context),
        ),
      );
    }
    return SpineTracks(
      arrival: widget.previousLeg?.toTrack,
      departure: widget.leg.fromTrack,
      // Only for the modes that run to numbered platforms: an absent one
      // there is a gap in the data rather than a mode that simply has none,
      // and a permanent dash on every tram would say nothing.
      placeholderForDeparture: _expectsATrack,
      reserveAbove: point.showsArrival,
    );
  }

  Widget _buildBody({required SpinePoint point}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.openStopSheet(
            stopId: widget.leg.fromStopId,
            stopName: widget.leg.fromName,
            referenceTime: widget.leg.startTime,
          ),
          child: Text(
            widget.leg.fromName,
            style: kSpineNameStyle.copyWith(color: AppColors.black),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
        if (buildSpineDelay(point) case final delay?) delay,
        const SizedBox(height: 6),
        Row(
          children: [
            // The badge keeps its own width; the end station takes what is
            // left, so it sits a fixed margin after the line number.
            Flexible(child: _buildTitleWidget()),
            if (_buildSubtitle() case final subtitle?) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  subtitle,
                  style: AppText.bodyStrong,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _buildNoteLine(),
          style: AppText.footnote,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }

  /// Below the body and the platform column both, so the notices span the
  /// full width on a ride just as on a walk.
  Widget _buildFooter(BuildContext context, {required bool isStreet}) {
    final notices = legNotices(widget.leg);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A walk has nothing to unfold, so it can hold nothing back.
        if (isStreet || _isExpanded)
          LegNoticeStack(notices)
        else
          LegNoticeStack.folded(notices),
        if (!isStreet) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isExpanded ? 'Hide stops' : 'Show stops',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.accentOf(context),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                _isExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 14,
                color: AppColors.accentOf(context),
              ),
            ],
          ),
        ],
        if (_isExpanded) ...[
          const SizedBox(height: 8),
          _buildMetadataSection(),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  /// The quiet line under the service: how long, how far, how many stops, and
  /// once the leg is open, which class of vehicle it is.
  String _buildNoteLine() {
    final parts = <String>[formatDuration(widget.leg.duration)];

    if (_isExpanded) parts.add(getTransitModeName(widget.leg.mode));

    final distance = widget.leg.distance;
    if (distance != null && distance > 0) {
      parts.add(formatDistanceKm(distance));
    }

    final stops = widget.leg.intermediateStops.length;
    if (stops > 0) parts.add('$stops ${stops == 1 ? 'stop' : 'stops'}');

    return parts.join(' · ');
  }

  /// The line beside the service badge.
  ///
  /// Where it is going is what you check you are on the right one by. The
  /// class of vehicle rarely changes what you do, so it waits in the note
  /// line until the leg is opened.
  String? _buildSubtitle() {
    final headsign = widget.leg.headsign?.trim();
    if (headsign != null && headsign.isNotEmpty) return headsign;
    if (isStreetLeg(widget.leg.mode)) return null;
    return null;
  }

  bool get _expectsATrack =>
      TransitMode.fromWire(widget.leg.mode)?.runsToNumberedPlatforms ?? false;

  /// The stops the service calls at, dropped onto the line it already has.
  ///
  /// They are minor dots rather than rings: you change nothing there, so they
  /// must not compete with the nodes, which mark the places you act at. The
  /// leg's own first stop is not repeated — it is the ring above.
  List<Widget> _buildStopRows(Color color) {
    final stops = <_TimelineStop>[];

    for (final stop in widget.leg.intermediateStops) {
      stops.add(
        _TimelineStop(
          name: stop.name,
          stopId: stop.stopId,
          track: stop.track,
          arrival: stop.arrival,
          departure: stop.departure,
          scheduledArrival: stop.scheduledArrival,
          scheduledDeparture: stop.scheduledDeparture,
          cancelled: stop.cancelled,
        ),
      );
    }

    return [
      for (final (index, stop) in stops.indexed)
        if (SpinePoint(
              arrival: stop.arrival,
              scheduledArrival: stop.scheduledArrival,
              departure: stop.departure,
              scheduledDeparture: stop.scheduledDeparture,
              arrivalIsLive: widget.leg.realTime,
              departureIsLive: widget.leg.realTime,
            )
            case final point)
          SpineRow(
            node: SpineDot(
              color: widget.progress.hasPassed(stop.timeAtStop)
                  ? _faded(color)
                  : color,
            ),
            nodeCenter: kSpineMinorNodeCenter,
            railColor: color,
            // This dot's line runs to the next one, or off the end of the leg
            // when it is the last stop. Expanded, this is what gives the fade
            // its exact anchors: it lands between the two stops the clock
            // falls between.
            railTravelled: widget.progress.fractionBetween(
              stop.timeAtStop,
              index + 1 < stops.length
                  ? (stops[index + 1].arrival ?? stops[index + 1].departure)
                  : widget.leg.endTime,
            ),
            // A stop waited at reserves room for its arrival the same way a
            // leg's node does; the line through that room is this leg's, so
            // no separate colour is needed above it.
            aboveAnchor: point.showsArrival ? kSpineStopLineHeight : 0,
            firstLineHeight: kSpineStopLineHeight,
            time: SpineTimes(point: point, compact: true),
            meta: SpineTracks(
              departure: stop.track,
              reserveAbove: point.showsArrival,
              compact: true,
            ),
            body: _buildStopBody(stop, point),
            onTap: stop.stopId == null
                ? null
                : () => widget.openStopSheet(
                    stopId: stop.stopId,
                    stopName: stop.name,
                    referenceTime: stop.timeAtStop ?? widget.leg.startTime,
                  ),
          ),
    ];
  }

  Widget _buildStopBody(_TimelineStop stop, SpinePoint point) {
    return Padding(
      // Roomy enough that a stop's arrival and departure read as belonging to
      // the name above them rather than to the stop below.
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stop.name,
            style: kSpineStopStyle.copyWith(color: AppColors.black),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
          if (buildSpineDelay(point, compact: true) case final delay?) delay,
          if (stop.cancelled) ...[
            const SizedBox(height: 2),
            Text(
              'CANCELLED',
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFFD32F2F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          GtfsFieldsRow(fields: {'stop': stop.stopId}),
        ],
      ),
    );
  }

  Widget _buildMetadataSection() {
    final metadata = <Widget>[];

    // No cancelled or delayed chips: a cancellation is a notice above, and a
    // delay is already the red time and the grey minutes beside the station.

    // No track chip: the departure platform now sits on the card's own row
    // and again against the first stop of the timeline, so a chip here would
    // be the third copy of one number.

    if (widget.leg.realTime) {
      metadata.add(const InfoChip(icon: LucideIcons.radio, label: 'Real-time'));
    }

    if (widget.leg.distance != null && widget.leg.distance! > 0) {
      metadata.add(
        InfoChip(
          icon: LucideIcons.ruler,
          label: formatDistanceKm(widget.leg.distance!),
        ),
      );
    }

    if (widget.leg.agencyName != null) {
      metadata.add(
        InfoChip(icon: LucideIcons.building, label: widget.leg.agencyName!),
      );
    }

    if (widget.leg.routeLongName != null &&
        widget.leg.routeLongName!.isNotEmpty) {
      metadata.add(
        InfoChip(icon: LucideIcons.route, label: widget.leg.routeLongName!),
      );
    }

    if (widget.leg.interlineWithPreviousLeg) {
      metadata.add(const InfoChip(icon: LucideIcons.link, label: 'Interlined'));
    }

    final gtfsFields = GtfsFieldsRow(
      fields: {
        'trip': widget.leg.tripId,
        'from stop': widget.leg.fromStopId,
        'to stop': widget.leg.toStopId,
      },
    );

    if (metadata.isEmpty) return gtfsFields;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(spacing: 8, runSpacing: 8, children: metadata),
        gtfsFields,
      ],
    );
  }

  Widget _buildTitleWidget() {
    if (widget.leg.displayName != null) {
      final routeColor = parseHexColor(widget.leg.routeColor);
      final isWalkLeg = widget.leg.mode == 'WALK';
      final bg = routeColor ?? (isWalkLeg ? null : AppColors.accentOf(context));
      final txt =
          parseHexColor(widget.leg.routeTextColor) ??
          (routeColor == null && !isWalkLeg
              ? AppColors.solidWhite
              : AppColors.black);
      // Sized to its own text. An Align here would take the whole of the
      // width the Row offered it, which put every leg's end station at the
      // same x instead of a fixed margin after its own line number.
      final badge = RouteBadgePill(
        label: widget.leg.displayName!.isNotEmpty
            ? widget.leg.displayName!
            : getTransitModeName(widget.leg.mode),
        background: bg ?? const Color(0x00000000),
        foreground: txt,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        fontSize: 16,
        fontWeight: FontWeight.bold,
      );
      final tripId = widget.leg.tripId;
      if (isWalkLeg || tripId == null || tripId.isEmpty) return badge;
      return GestureDetector(
        onTap: () {
          Navigator.of(
            context,
          ).push(CustomPageRoute(child: ConnectionInfoScreen(tripId: tripId)));
        },
        child: badge,
      );
    }
    return Text(
      getTransitModeName(widget.leg.mode),
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.black,
      ),
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
    );
  }
}

/// Getting between two services, as its own stretch of the line.
///
/// Neutral and dotted, because a change belongs to no line: you are on foot
/// between two operators' services. What a rider needs here is how long they
/// have and which platform to end up on, so both lead.
class TransferLegCard extends StatelessWidget {
  final Leg leg;
  final OpenStopSheet openStopSheet;

  /// A change is a walk between platforms; where it goes is the question.
  final VoidCallback? onShowOnMap;

  /// The leg that arrives at this change. See [LegDetailsWidget.previousLeg].
  final Leg? previousLeg;

  /// What is known about whether this change can be made. Null on a change
  /// nobody is reporting on, which is most of them.
  final Changeover? changeover;

  /// See [LegDetailsWidget.progress].
  final JourneyProgress progress;

  const TransferLegCard({
    super.key,
    required this.leg,
    required this.openStopSheet,
    this.onShowOnMap,
    this.previousLeg,
    this.changeover,
    this.progress = JourneyProgress.never,
  });

  @override
  Widget build(BuildContext context) {
    // Both sides of this node come off the transfer leg's own `from` place,
    // which MOTIS fills with the arriving service's real times as well as the
    // walk's. The leg's `startTime` carries none of that — it is a walk, and
    // a walk is never late — so reading the arrival from it was how a train
    // ten minutes down came out looking punctual. It is the same source the
    // intermediate stops read, which is why they were right and this was not.
    final node = leg.from;
    final point = SpinePoint(
      arrival: node.arrival ?? previousLeg?.endTime,
      scheduledArrival: node.scheduledArrival ?? previousLeg?.scheduledEndTime,
      arrivalIsLive: previousLeg?.realTime ?? false,
      departure: node.departure ?? leg.startTime,
      scheduledDeparture: node.scheduledDeparture ?? leg.scheduledStartTime,
      departureIsLive: leg.realTime,
    );

    final missed = changeover?.isMissed ?? false;
    // A break has to be findable while scrolling, before a word is read.
    final changeColor = missed ? kMissedChangeColor : kStreetLegColor;
    // A change you have already made is behind you like any other stretch —
    // but a change you cannot make keeps its full red wherever you are, since
    // it is a warning rather than a piece of the route.
    final arrived = !missed && progress.hasPassed(point.departure?.shown);

    return SpineRow(
      node: SpineNode(
        // The problem notice's own shape, so node and notice read as one.
        icon: missed ? LucideIcons.octagonAlert : LucideIcons.arrowLeftRight,
        color: arrived
            ? changeColor.withValues(alpha: changeColor.a * kTravelledOpacity)
            : changeColor,
        semanticLabel: missed ? 'Change you will not make' : 'Change',
      ),
      railColor: changeColor,
      railDashed: true,
      railTravelled: missed
          ? 0
          : progress.fractionBetween(point.departure?.shown, leg.endTime),
      railAboveTravelled: arrived ? 1 : 0,
      aboveAnchor: point.showsArrival ? kSpineNameLineHeight : 0,
      railTopInset:
          (point.showsArrival ? kSpineNameLineHeight : 0) + JourneyMetrics.ring,
      railAboveColor: previousLeg == null
          ? null
          : legSpineColor(
              leg: previousLeg!,
              background: AppColors.white,
              accent: AppColors.accentOf(context),
            ),
      railAboveDashed: previousLeg != null && isStreetLeg(previousLeg!.mode),
      firstLineHeight: kSpineNameLineHeight,
      time: SpineTimes(point: point),
      meta: onShowOnMap == null
          ? null
          : Semantics(
              button: true,
              label: 'Show this change on the map',
              child: Icon(
                LucideIcons.map,
                size: 16,
                color: AppColors.accentOf(context),
              ),
            ),
      onTap: onShowOnMap,
      footer: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: LegNoticeStack(legNotices(leg, changeover: changeover)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openStopSheet(
              stopId: leg.fromStopId,
              stopName: leg.fromName,
              referenceTime: leg.startTime,
            ),
            child: Text(
              leg.fromName,
              style: kSpineNameStyle.copyWith(color: AppColors.black),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
          if (buildSpineDelay(point) case final delay?) delay,
          const SizedBox(height: 6),
          Text(
            'Change · ${formatDuration(leg.duration)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.black.withValues(alpha: 0.75),
            ),
          ),
          if (_platforms() case final platforms?) ...[
            const SizedBox(height: 3),
            Text(platforms, style: AppText.footnote),
          ],
          if (leg.distance != null && leg.distance! > 0) ...[
            const SizedBox(height: 3),
            Text(
              'Approx. ${formatDistanceKm(leg.distance!)} walk',
              style: AppText.footnote,
            ),
          ],
        ],
      ),
    );
  }

  /// Which platform to leave and which to end up on — the one thing a change
  /// is actually about, and only worth a line when the feed knows it.
  String? _platforms() {
    final from = leg.fromTrack?.trim();
    final to = leg.toTrack?.trim();
    final hasFrom = from != null && from.isNotEmpty;
    final hasTo = to != null && to.isNotEmpty;
    if (hasFrom && hasTo) return 'Track $from → Track $to';
    if (hasTo) return 'To Track $to';
    if (hasFrom) return 'From Track $from';
    return null;
  }
}

class FinishLegCard extends StatelessWidget {
  final Leg leg;
  final DateTime arrivalTime;
  final int totalDuration;
  final OpenStopSheet openStopSheet;

  /// See [LegDetailsWidget.progress].
  final JourneyProgress progress;

  const FinishLegCard({
    super.key,
    required this.leg,
    required this.arrivalTime,
    required this.totalDuration,
    required this.openStopSheet,
    this.progress = JourneyProgress.never,
  });

  @override
  Widget build(BuildContext context) {
    final color = legSpineColor(
      leg: leg,
      background: AppColors.white,
      accent: AppColors.accentOf(context),
    );
    // The end of the line: once it is behind you the whole journey is.
    final arrived = progress.hasPassed(arrivalTime);

    return SpineRow(
      node: SpineNode(
        icon: LucideIcons.flag,
        color: arrived
            ? color.withValues(alpha: color.a * kTravelledOpacity)
            : color,
        filled: true,
        semanticLabel: 'Journey end',
      ),
      firstLineHeight: kSpineNameLineHeight,
      // Nothing departs from the end of the line, so its arrival takes the
      // anchor rather than hanging above one.
      time: SpineTimes(
        point: SpinePoint(
          arrival: arrivalTime,
          scheduledArrival: leg.scheduledEndTime,
          arrivalIsLive: leg.realTime,
        ),
      ),
      meta: SpineTracks(departure: leg.toTrack, reserveAbove: false),
      onTap: () => openStopSheet(
        stopId: leg.toStopId,
        stopName: leg.toName,
        referenceTime: leg.endTime,
      ),
      body: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              leg.toName,
              style: kSpineNameStyle.copyWith(color: AppColors.black),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            const SizedBox(height: 4),
            Text(
              'Finish · ${formatDuration(totalDuration)} total',
              style: AppText.footnote,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineStop {
  final String name;
  final String? stopId;
  final String? track;
  final bool cancelled;

  /// Both times, kept apart.
  ///
  /// At a stop where the service waits, when it gets in and when it leaves
  /// again are different facts and the second is the one you can still catch.
  /// The first stop has only a departure and the last only an arrival.
  final DateTime? arrival;
  final DateTime? departure;
  final DateTime? scheduledArrival;
  final DateTime? scheduledDeparture;

  _TimelineStop({
    required this.name,
    this.stopId,
    this.track,
    this.cancelled = false,
    this.arrival,
    this.departure,
    this.scheduledArrival,
    this.scheduledDeparture,
  });

  /// The one time that matters at this stop: when the vehicle leaves, or
  /// when it arrives if it never leaves again.
  DateTime? get timeAtStop => departure ?? arrival;
}
