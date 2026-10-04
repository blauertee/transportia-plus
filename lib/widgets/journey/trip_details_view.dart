import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/itinerary.dart';
import '../../models/journey_stop.dart';
import '../../theme/app_colors.dart';
import '../../utils/color_utils.dart';
import '../../utils/duration_formatter.dart';
import '../../utils/journey_utils.dart';
import '../../utils/leg_helper.dart' show getLegIcon, getTransitModeName;
import '../../utils/vehicle_position.dart';
import '../alert_notice.dart';
import '../custom_card.dart';
import '../empty_state.dart';
import '../gtfs_fields_row.dart';
import '../info_chip.dart';
import 'trip_timeline.dart';
import '../../theme/app_text.dart';

/// Heading over one of the trip cards.
class _CardTitle extends StatelessWidget {
  const _CardTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: AppText.heading);
}

/// Everything there is to say about one vehicle's trip: what it is, what is
/// wrong with it, and every stop it calls at.
///
/// Shared by the Connection Info screen and the map's trip focus card, which
/// show the same trip through different chrome.
class TripDetailsView extends StatelessWidget {
  const TripDetailsView({
    super.key,
    required this.itinerary,
    required this.onRefresh,
    required this.onStopTap,
    this.headerTrailing,
    this.trailingSlivers = const [],
  });

  final Itinerary itinerary;
  final Future<void> Function() onRefresh;
  final StopTapCallback onStopTap;

  /// An action shown beside the route name, such as the map button.
  final Widget? headerTrailing;

  /// Slivers appended below the cards, such as a last-updated footer.
  final List<Widget> trailingSlivers;

  /// The leg the trip is about — the first that is actually ridden, since a
  /// trip fetched by id can be wrapped in walking legs.
  Leg get _leg => itinerary.legs.firstWhere(
    (leg) => leg.mode != 'WALK',
    orElse: () => itinerary.legs.first,
  );

  @override
  Widget build(BuildContext context) {
    final leg = _leg;
    final routeColor = parseHexColorOrAccent(context, leg.routeColor);
    final routeTextColor = parseHexColorOr(
      leg.routeTextColor,
      AppColors.solidWhite,
    );
    final stops = buildJourneyStops(leg);
    final alerts = collectTripAlerts(leg, stops);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(onRefresh: onRefresh),
        SliverPadding(
          padding: const EdgeInsets.only(bottom: 16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _TripHeaderCard(
                  leg: leg,
                  routeColor: routeColor,
                  routeTextColor: routeTextColor,
                  trailing: headerTrailing,
                ),
                if (alerts.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _TripAlertsCard(alerts: alerts),
                ],
                const SizedBox(height: 12),
                _TripInfoCard(leg: leg, fare: itinerary.fare),
                const SizedBox(height: 12),
                _TripJourneyCard(
                  stops: stops,
                  isLive: leg.realTime,
                  routeColor: routeColor,
                  routeTextColor: routeTextColor,
                  modeIcon: getLegIcon(leg.mode),
                  onStopTap: onStopTap,
                ),
              ],
            ),
          ),
        ),
        ...trailingSlivers,
      ],
    );
  }
}

class _TripHeaderCard extends StatelessWidget {
  const _TripHeaderCard({
    required this.leg,
    required this.routeColor,
    required this.routeTextColor,
    required this.trailing,
  });

  final Leg leg;
  final Color routeColor;
  final Color routeTextColor;
  final Widget? trailing;

  /// What the service calls itself, falling back through the names the feed
  /// might have given until something is left to print.
  String get _routeLabel {
    for (final candidate in [leg.displayName, leg.routeShortName]) {
      final trimmed = candidate?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return getTransitModeName(leg.mode);
  }

  String? get _headsign {
    final trimmed = leg.headsign?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final headsign = _headsign;
    return CustomCard(
      child: Row(
        children: [
          Icon(getLegIcon(leg.mode), size: 32, color: AppColors.black),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: routeColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _routeLabel,
                    style: TextStyle(
                      color: routeTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (headsign != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${getTransitModeName(leg.mode)} • $headsign',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.black,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _TripAlertsCard extends StatelessWidget {
  const _TripAlertsCard({required this.alerts});

  final List<Alert> alerts;

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Warnings'),
          const SizedBox(height: 12),
          for (final alert in alerts)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: AlertNotice(alert: alert),
            ),
        ],
      ),
    );
  }
}

class _TripInfoCard extends StatelessWidget {
  const _TripInfoCard({required this.leg, required this.fare});

  final Leg leg;
  final FareInfo? fare;

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _CardTitle('Information'),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: _buildChips()),
          GtfsFieldsRow(
            fields: {
              'trip': leg.tripId,
              'from stop': leg.fromStopId,
              'to stop': leg.toStopId,
            },
          ),
        ],
      ),
    );
  }

  List<Widget> _buildChips() {
    final distance = leg.distance;
    final agencyName = leg.agencyName;
    final routeLongName = leg.routeLongName;
    final fare = this.fare;
    return [
      if (leg.realTime)
        const InfoChip(icon: LucideIcons.radio, label: 'Real-time'),
      if (leg.cancelled)
        InfoChip(
          icon: LucideIcons.x,
          label: 'CANCELLED',
          tint: AppColors.cancelled,
        ),
      InfoChip(icon: LucideIcons.clock, label: formatDuration(leg.duration)),
      if (distance != null)
        InfoChip(
          icon: LucideIcons.ruler,
          label: formatDistanceKm(distance, decimals: 1),
        ),
      if (agencyName != null)
        InfoChip(icon: LucideIcons.building, label: agencyName),
      if (routeLongName != null && routeLongName.isNotEmpty)
        InfoChip(icon: LucideIcons.route, label: routeLongName),
      if (fare != null)
        InfoChip(
          icon: LucideIcons.coins,
          label: '${fare.amount.toStringAsFixed(2)} ${fare.currency}',
        ),
    ];
  }
}

class _TripJourneyCard extends StatelessWidget {
  const _TripJourneyCard({
    required this.stops,
    required this.routeColor,
    required this.routeTextColor,
    required this.modeIcon,
    required this.onStopTap,
    required this.isLive,
  });

  final List<JourneyStop> stops;
  final Color routeColor;
  final Color routeTextColor;
  final IconData modeIcon;
  final StopTapCallback onStopTap;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    return CustomCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardTitle('Journey'),
          const SizedBox(height: 16),
          if (stops.isEmpty)
            EmptyState(
              title: 'No stops available',
              padding: EdgeInsets.zero,
              titleStyle: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.black.withValues(alpha: 0.6),
              ),
            )
          else
            TripTimeline(
              stops: stops,
              position: estimateVehiclePosition(stops),
              routeColor: routeColor,
              routeTextColor: routeTextColor,
              modeIcon: modeIcon,
              onStopTap: onStopTap,
              isLive: isLive,
            ),
        ],
      ),
    );
  }
}
