import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../models/itinerary.dart';
import '../providers/theme_provider.dart';
import '../services/trip_details_service.dart';
import '../theme/app_colors.dart';
import '../navigation/routes.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/journey/trip_details_view.dart';
import '../widgets/last_updated_footer.dart';
import '../widgets/skeletons/skeleton_card.dart';
import '../widgets/skeletons/skeleton_shimmer.dart';
import '../widgets/stop_departures_sheet.dart';
import 'itinerary_map_screen.dart';

/// How often the screen redraws so live times stay current.
const Duration _kLiveTimeTick = Duration(seconds: 5);

class ConnectionInfoScreen extends StatefulWidget {
  final String tripId;

  const ConnectionInfoScreen({super.key, required this.tripId});

  @override
  State<ConnectionInfoScreen> createState() => _ConnectionInfoScreenState();
}

class _ConnectionInfoScreenState extends State<ConnectionInfoScreen> {
  Itinerary? _itinerary;
  bool _isLoading = true;
  String? _error;
  Timer? _refreshTimer;
  DateTime? _lastUpdated;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _fetchTripDetails();
    _refreshTimer = Timer.periodic(_kLiveTimeTick, (_) {
      if (mounted && _itinerary != null) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchTripDetails() async {
    try {
      final details = await TripDetailsService.fetchTripDetails(
        tripId: widget.tripId,
      );
      if (mounted) {
        setState(() {
          _itinerary = details;
          _isLoading = false;
          _lastUpdated = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshTripDetails() async {
    if (_isRefreshing) return;
    _isRefreshing = true;
    try {
      final details = await TripDetailsService.fetchTripDetails(
        tripId: widget.tripId,
      );
      if (!mounted) return;
      setState(() {
        _itinerary = details;
        _error = null;
        _lastUpdated = DateTime.now();
      });
    } catch (_) {
      // Keep showing the previously loaded trip if the refresh fails.
    } finally {
      _isRefreshing = false;
    }
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

  void _openTripOnMap() {
    context.openScreen(
      ItineraryMapScreen(itinerary: _itinerary!, showCarousel: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return Container(
      color: AppColors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CustomAppBar(title: 'Connection Info'),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) return _buildLoadingSkeleton();
    if (_error != null) return _buildError();

    final itinerary = _itinerary;
    if (itinerary == null || itinerary.legs.isEmpty) return _buildEmpty();

    return TripDetailsView(
      itinerary: itinerary,
      onRefresh: _refreshTripDetails,
      onStopTap: _openStopSheet,
      headerTrailing: GestureDetector(
        onTap: _openTripOnMap,
        child: Container(
          padding: const EdgeInsets.all(8),
          child: Icon(
            LucideIcons.map,
            size: 20,
            color: AppColors.accentOf(context),
          ),
        ),
      ),
      trailingSlivers: [
        SliverToBoxAdapter(child: LastUpdatedFooter(lastUpdated: _lastUpdated)),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return SkeletonShimmer(
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          children: const [
            SkeletonCard(
              height: 120,
              borderRadius: BorderRadius.all(Radius.circular(14)),
              margin: EdgeInsets.all(12),
            ),
            SkeletonCard(
              height: 400,
              borderRadius: BorderRadius.all(Radius.circular(14)),
              margin: EdgeInsets.all(12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'Failed to load trip details',
          style: TextStyle(
            fontSize: 16,
            color: AppColors.black.withValues(alpha: 0.5),
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: EmptyState(
        title: 'No trip data available',
        titleStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppColors.black.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
