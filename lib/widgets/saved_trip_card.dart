import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/itinerary.dart';
import '../models/saved_trip.dart';
import '../services/itinerary_refresh_service.dart';
import '../theme/app_colors.dart';
import '../utils/color_utils.dart';
import '../utils/duration_formatter.dart';
import '../utils/leg_helper.dart';
import '../utils/time_utils.dart';
import 'custom_card.dart';
import 'icon_badge.dart';
import 'route_badge_pill.dart';

/// One entry in a list of saved trips.
///
/// Shows where the trip goes, when it leaves and how long that is from now,
/// plus how much the app currently knows about it — a saved trip is always
/// a snapshot, so saying nothing about its freshness would be a claim in
/// itself.
class SavedTripCard extends StatefulWidget {
  const SavedTripCard({
    super.key,
    required this.trip,
    this.onTap,
    this.onLongPress,
    this.freshness,
    this.margin,
  });

  final SavedTrip trip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// What the last refresh established, when one has run. Null means the
  /// trip has not been checked yet, which is the normal state in a list.
  final ItineraryFreshness? freshness;

  final EdgeInsetsGeometry? margin;

  @override
  State<SavedTripCard> createState() => _SavedTripCardState();
}

class _SavedTripCardState extends State<SavedTripCard> {
  Timer? _countdownTicker;

  @override
  void initState() {
    super.initState();
    _countdownTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTicker?.cancel();
    super.dispose();
  }

  bool get _isCancelled =>
      widget.freshness == ItineraryFreshness.changed ||
      widget.trip.itinerary.legs.any((leg) => leg.cancelled);

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final accent = AppColors.accentOf(context);
    final isPast = trip.isPast;

    return Opacity(
      opacity: isPast ? 0.55 : 1.0,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: CustomCard.elevated(
          margin:
              widget.margin ??
              const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          padding: const EdgeInsets.all(14),
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBadge(
                    icon: LucideIcons.bookmark,
                    size: 36,
                    iconSize: 18,
                    backgroundColor: AppColors.accentWash(accent),
                    iconColor: accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _routeSummary(trip)),
                  _StatusDot(
                    freshness: widget.freshness,
                    isPast: isPast,
                    isCancelled: _isCancelled,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _metaRow(context, trip, isPast: isPast),
              if (trip.itinerary.legs.isNotEmpty) ...[
                const SizedBox(height: 10),
                _LegBadges(legs: trip.itinerary.legs),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _routeSummary(SavedTrip trip) {
    final label = trip.label?.trim();
    final hasCustomLabel = label != null && label.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasCustomLabel ? label : trip.fromName,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.black,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            if (!hasCustomLabel) ...[
              Icon(
                LucideIcons.chevronRight,
                size: 14,
                color: AppColors.black.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                hasCustomLabel
                    ? '${trip.fromName} → ${trip.toName}'
                    : trip.toName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.black.withValues(alpha: 0.6),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _metaRow(
    BuildContext context,
    SavedTrip trip, {
    required bool isPast,
  }) {
    final departure = trip.departureTime.toLocal();
    final when =
        '${formatRelativeDay(departure)} ${formatTime(departure)}'
        ' – ${formatTime(trip.arrivalTime)}';

    return Row(
      children: [
        Icon(
          LucideIcons.clock,
          size: 14,
          color: AppColors.black.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            when,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.black.withValues(alpha: 0.7),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _relativeLabel(context, trip, isPast: isPast),
      ],
    );
  }

  Widget _relativeLabel(
    BuildContext context,
    SavedTrip trip, {
    required bool isPast,
  }) {
    if (_isCancelled) {
      return Text(
        'Cancelled',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppColors.disrupted,
        ),
      );
    }

    if (isPast) {
      return Text(
        'Completed',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.black.withValues(alpha: 0.5),
        ),
      );
    }

    final secondsUntil = trip.departureTime
        .difference(DateTime.now())
        .inSeconds;
    final text = secondsUntil <= 0
        ? 'Departing'
        : secondsUntil < 60
        ? 'Departing now'
        : 'in ${formatDuration(secondsUntil)}';

    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppColors.accentOf(context),
      ),
    );
  }
}

/// A single dot conveying how current the card's information is.
class _StatusDot extends StatelessWidget {
  const _StatusDot({
    required this.freshness,
    required this.isPast,
    required this.isCancelled,
  });

  final ItineraryFreshness? freshness;
  final bool isPast;
  final bool isCancelled;

  @override
  Widget build(BuildContext context) {
    if (isPast) return const SizedBox.shrink();

    final Color color;
    if (isCancelled) {
      color = AppColors.disrupted;
    } else if (freshness == ItineraryFreshness.live) {
      color = AppColors.accentOf(context);
    } else {
      // Not checked, or checked and the feed had nothing: either way the
      // times shown are the planned ones.
      color = AppColors.black.withValues(alpha: 0.25);
    }

    return Container(
      width: 8,
      height: 8,
      margin: const EdgeInsets.only(top: 6, left: 8),
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// The route badges for a trip, matching the treatment used in search
/// results so a saved trip reads the same as the card it was saved from.
class _LegBadges extends StatelessWidget {
  const _LegBadges({required this.legs});

  final List<Leg> legs;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final leg in legs)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                getLegIcon(leg.mode),
                size: 14,
                color: AppColors.black.withValues(alpha: 0.5),
              ),
              if (leg.displayName != null && leg.displayName!.isNotEmpty) ...[
                const SizedBox(width: 4),
                _badge(context, leg),
              ],
            ],
          ),
      ],
    );
  }

  Widget _badge(BuildContext context, Leg leg) {
    final routeColor = parseHexColor(leg.routeColor);

    return RouteBadgePill(
      label: leg.displayName!,
      background: routeColor ?? AppColors.accentOf(context),
      foreground:
          parseHexColor(leg.routeTextColor) ??
          (routeColor == null ? AppColors.solidWhite : AppColors.black),
    );
  }
}
