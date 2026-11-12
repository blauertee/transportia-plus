import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../models/saved_trip.dart';
import '../providers/theme_provider.dart';
import '../services/saved_trips_service.dart';
import '../theme/app_colors.dart';
import '../utils/custom_page_route.dart';
import '../widgets/app_screen_title.dart';
import '../widgets/edit_saved_trip_overlay.dart';
import '../widgets/empty_state.dart';
import '../widgets/saved_trip_card.dart';
import 'itinerary_detail_screen.dart';
import '../theme/app_text.dart';
import '../widgets/icon_badge.dart';

/// The full list of kept connections, split into what is still ahead and
/// what has already happened.
///
/// Past trips are not hidden outright: seeing the trip you took last week
/// is how you find it again, and it is the fastest route to re-running the
/// same journey.
class SavedTripsScreen extends StatefulWidget {
  const SavedTripsScreen({super.key});

  @override
  State<SavedTripsScreen> createState() => _SavedTripsScreenState();
}

class _SavedTripsScreenState extends State<SavedTripsScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    // Clear out anything long finished before showing the list, so the
    // pruning is invisible rather than something the user has to do.
    await SavedTripsService.pruneExpired();
    await SavedTripsService.getSavedTrips();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _openTrip(SavedTrip trip) {
    Navigator.of(context).push(
      CustomPageRoute(
        child: ItineraryDetailScreen(
          itinerary: trip.itinerary,
          savedTrip: trip,
        ),
      ),
    );
  }

  Future<void> _editTrip(SavedTrip trip) async {
    await showCupertinoDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => EditSavedTripOverlay(
        trip: trip,
        onRename: (label) =>
            unawaited(SavedTripsService.renameTrip(trip.id, label)),
        onDelete: () => unawaited(SavedTripsService.removeTrip(trip.id)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();

    return ColoredBox(
      color: AppColors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: AppScreenTitle(
                icon: LucideIcons.bookmark,
                title: 'Saved trips',
                subtitle: 'Rechecked for delays when you open them',
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _isLoading
                    ? const Center(
                        child: CupertinoActivityIndicator(radius: 14),
                      )
                    : ValueListenableBuilder<List<SavedTrip>>(
                        valueListenable: SavedTripsService.savedTripsListenable,
                        builder: (context, trips, _) {
                          if (trips.isEmpty) return _emptyState(context);
                          return _tripList(trips);
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tripList(List<SavedTrip> trips) {
    final upcoming = trips.where((t) => !t.isPast).toList();
    // Most recently finished first — the useful end of the history.
    final past = trips.where((t) => t.isPast).toList().reversed.toList();

    return ListView(
      // Clears the floating navigation bar, as the timetables tab does.
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (upcoming.isNotEmpty) ...[
          _sectionLabel('Upcoming'),
          for (final trip in upcoming) _card(trip),
        ],
        if (past.isNotEmpty) ...[
          _sectionLabel('Past'),
          for (final trip in past) _card(trip),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            'Tap a trip to open it. Long press to rename or remove.',
            textAlign: TextAlign.center,
            style: AppText.subtitle,
          ),
        ),
      ],
    );
  }

  Widget _card(SavedTrip trip) {
    return SavedTripCard(
      trip: trip,
      onTap: () => _openTrip(trip),
      onLongPress: () => unawaited(_editTrip(trip)),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.black.withValues(alpha: 0.5),
        ),
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Center(
      child: EmptyState(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        icon: IconBadge(
          icon: LucideIcons.bookmark,
          size: 56,
          iconSize: 28,
          backgroundColor: AppColors.accentWash(accent),
          iconColor: accent,
          borderRadius: BorderRadius.circular(16),
        ),
        title: 'No saved trips yet',
        subtitle:
            'Search for a journey, then tap the bookmark on the connection '
            'you want to keep.',
      ),
    );
  }
}
