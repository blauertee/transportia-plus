import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/stop_time.dart';
import '../../services/transitous_map_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/color_utils.dart';
import '../../utils/time_utils.dart';
import '../error_notice.dart';
import '../route_badge_pill.dart';
import '../skeletons/skeleton_shimmer.dart';
import 'map_selection_modal.dart';
import '../../theme/app_text.dart';

/// How far the stop card starts scaled up, gentler than the long-press card
/// because this one carries a list that would otherwise seem to lurch.
const double _kStopModalEntryScale = 1.06;

/// Rows of departures shown while the real ones load.
const int _kStopTimesSkeletonRows = 3;

/// Offers a tapped map stop as an origin or destination, over a preview of
/// what is leaving from it.
class StopSelectionModal extends StatelessWidget {
  const StopSelectionModal({
    super.key,
    required this.stop,
    required this.stopTimes,
    required this.isLoading,
    required this.errorMessage,
    required this.onSelectFrom,
    required this.onSelectTo,
    required this.onStopTimeTap,
    required this.onViewTimetable,
    required this.onDismissRequested,
    required this.onClosed,
    required this.isClosing,
  });

  final MapStop stop;
  final List<StopTime> stopTimes;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback onSelectFrom;
  final VoidCallback onSelectTo;
  final ValueChanged<StopTime> onStopTimeTap;
  final VoidCallback onViewTimetable;
  final VoidCallback onDismissRequested;
  final VoidCallback onClosed;
  final bool isClosing;

  @override
  Widget build(BuildContext context) {
    return MapSelectionModal(
      identity: stop.id,
      isClosing: isClosing,
      onClosed: onClosed,
      onDismissRequested: onDismissRequested,
      horizontalPadding: 28,
      maxCardWidth: 360,
      cardPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      entryScale: _kStopModalEntryScale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MapModalHeader(
            icon: LucideIcons.mapPin,
            title: stop.name,
            subtitle: stop.stopId ?? 'Transit stop',
            clipText: true,
          ),
          const SizedBox(height: 20),
          _label('Departures & arrivals', weight: FontWeight.w600, alpha: 0.7),
          const SizedBox(height: 12),
          _StopTimesPreview(
            stopTimes: stopTimes,
            isLoading: isLoading,
            errorMessage: errorMessage,
            onStopTimeTap: onStopTimeTap,
          ),
          const SizedBox(height: 16),
          MapModalTextAction(
            icon: LucideIcons.clock,
            label: 'View full timetable',
            onPressed: onViewTimetable,
            fontWeight: FontWeight.w600,
          ),
          const SizedBox(height: 18),
          _label('Use this stop as:', weight: FontWeight.w500, alpha: 0.6),
          const SizedBox(height: 12),
          OriginDestinationPicker(
            onSelectFrom: onSelectFrom,
            onSelectTo: onSelectTo,
          ),
          const SizedBox(height: 18),
          MapModalTextAction(
            icon: LucideIcons.x,
            label: 'Dismiss',
            onPressed: onDismissRequested,
          ),
        ],
      ),
    );
  }

  Widget _label(
    String text, {
    required FontWeight weight,
    required double alpha,
  }) => Text(
    text,
    style: TextStyle(
      fontWeight: weight,
      fontSize: 14,
      color: AppColors.black.withValues(alpha: alpha),
    ),
  );
}

class _StopTimesPreview extends StatelessWidget {
  const _StopTimesPreview({
    required this.stopTimes,
    required this.isLoading,
    required this.errorMessage,
    required this.onStopTimeTap,
  });

  final List<StopTime> stopTimes;
  final bool isLoading;
  final String? errorMessage;
  final ValueChanged<StopTime> onStopTimeTap;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const _StopTimesSkeleton();
    }
    if (errorMessage != null) {
      return ErrorNotice(message: errorMessage!, compact: true);
    }
    if (stopTimes.isEmpty) {
      return Text(
        'No upcoming departures.',
        style: TextStyle(
          color: AppColors.black.withValues(alpha: 0.6),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      );
    }
    return Column(
      children: [
        for (int i = 0; i < stopTimes.length; i++) ...[
          _StopTimePreviewRow(
            stopTime: stopTimes[i],
            onTap: () => onStopTimeTap(stopTimes[i]),
          ),
          if (i != stopTimes.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _StopTimesSkeleton extends StatelessWidget {
  const _StopTimesSkeleton();

  @override
  Widget build(BuildContext context) {
    final baseColor = AppColors.black.withValues(alpha: 0.08);
    final highlightColor = AppColors.black.withValues(alpha: 0.04);
    return SkeletonShimmer(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: Column(
        children: List.generate(
          _kStopTimesSkeletonRows,
          (index) => Padding(
            padding: EdgeInsets.only(
              bottom: index == _kStopTimesSkeletonRows - 1 ? 0 : 12,
            ),
            child: const _StopTimesSkeletonRow(),
          ),
        ),
      ),
    );
  }
}

class _StopTimesSkeletonRow extends StatelessWidget {
  const _StopTimesSkeletonRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.black.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 10,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 6),
              Container(
                height: 10,
                width: 140,
                decoration: BoxDecoration(
                  color: AppColors.black.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              height: 10,
              width: 48,
              decoration: BoxDecoration(
                color: AppColors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Container(
              height: 10,
              width: 48,
              decoration: BoxDecoration(
                color: AppColors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StopTimePreviewRow extends StatelessWidget {
  const _StopTimePreviewRow({required this.stopTime, this.onTap});

  final StopTime stopTime;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final routeColor = parseHexColorOrAccent(context, stopTime.routeColor);
    final routeTextColor = parseHexColorOr(
      stopTime.routeTextColor,
      AppColors.solidWhite,
    );
    final arrival = formatTime(
      stopTime.place.arrival ?? stopTime.place.scheduledArrival,
    );
    final departure = formatTime(
      stopTime.place.departure ?? stopTime.place.scheduledDeparture,
    );
    final label = stopTime.displayName.isNotEmpty
        ? stopTime.displayName
        : stopTime.routeShortName;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        RouteBadgePill(
          label: label,
          background: routeColor,
          foreground: routeTextColor,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          fontSize: 13,
          fontWeight: FontWeight.w700,
          minWidth: RouteBadgePill.stackedMinWidth,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            stopTime.headsign,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppText.bodyStrong,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Arr $arrival',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.black,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Dep $departure',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.black.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ],
    );
    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}
