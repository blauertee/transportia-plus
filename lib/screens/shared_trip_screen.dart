import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../api/endpoints/trip_endpoint.dart';
import '../api/transitous_api_exception.dart';
import '../environment.dart';
import '../providers/theme_provider.dart';
import '../services/rental_providers_service.dart';
import '../services/routing_options_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../utils/trip_link.dart';
import '../widgets/buttons/pill_button.dart';
import '../widgets/buttons/primary_button.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/skeletons/skeleton_card.dart';
import '../widgets/skeletons/skeleton_shimmer.dart';
import 'itinerary_detail_screen.dart';

enum _Stage { askServer, loading, failed }

/// Opens a trip someone shared as a link, then gives way to the trip itself.
///
/// The link names the server the trip was planned on. The id only means
/// something to that server's timetables, so a link from another one is read
/// there — but only once the rider agrees, since the link is untrusted and
/// the app would be sending a request wherever it points.
class SharedTripScreen extends StatefulWidget {
  const SharedTripScreen({super.key, required this.link});

  final TripLink link;

  @override
  State<SharedTripScreen> createState() => _SharedTripScreenState();
}

class _SharedTripScreenState extends State<SharedTripScreen> {
  late _Stage _stage;
  late String _host;
  String? _error;

  String get _ownHost => Environment.transitousHost;

  bool get _isForeign {
    final host = widget.link.host;
    return host != null && host != _ownHost.toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _host = _ownHost;
    if (_isForeign) {
      _stage = _Stage.askServer;
    } else {
      _stage = _Stage.loading;
      unawaited(_load());
    }
  }

  void _openWith(String host) {
    setState(() {
      _host = host;
      _stage = _Stage.loading;
    });
    unawaited(_load());
  }

  Future<void> _load() async {
    final isOwn = _host == _ownHost;
    try {
      final options = await RoutingOptionsService.load();
      final params = options.toRefreshParams(
        // Provider groups are the rider's server's; another has its own.
        rentalProviderGroups: isOwn
            ? await RentalProvidersService.activeGroupIds()
            : const [],
      );
      final itinerary = await TripEndpoint.refreshItinerary(
        itineraryId: widget.link.itineraryId,
        options: params,
        host: isOwn ? null : _host,
      );
      if (!mounted) return;
      unawaited(
        Navigator.of(context).pushReplacement(
          CupertinoPageRoute(
            builder: (_) => ItineraryDetailScreen(itinerary: itinerary),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final unreadable =
          error is TransitousApiException && error.statusCode == 400;
      setState(() {
        _stage = _Stage.failed;
        _error = unreadable
            ? "This link doesn't hold a trip $_host can read."
            : "Couldn't load the trip from $_host.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();
    return Container(
      color: AppColors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CustomAppBar(
              title: 'Shared trip',
              onBackButtonPressed: () => Navigator.of(context).pop(),
            ),
            Expanded(
              child: switch (_stage) {
                _Stage.askServer => _buildServerQuestion(),
                _Stage.loading => _buildLoading(),
                _Stage.failed => _buildFailure(),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServerQuestion() {
    final foreign = widget.link.host!;
    return _Prompt(
      icon: LucideIcons.server,
      title: 'This trip is from $foreign',
      subtitle:
          'Your app uses $_ownHost. Open the trip using $foreign? '
          'Only this trip is loaded from there; your settings stay as '
          'they are.',
      primaryLabel: 'Open with $foreign',
      onPrimary: () => _openWith(foreign),
      secondaryLabel: 'Try $_ownHost instead',
      onSecondary: () => _openWith(_ownHost),
    );
  }

  Widget _buildFailure() {
    final foreign = widget.link.host;
    final canTryOther = _isForeign && _host == _ownHost;
    return _Prompt(
      icon: LucideIcons.circleAlert,
      title: _error ?? "Couldn't load the trip.",
      subtitle: canTryOther
          ? 'It was planned on $foreign, which may know it.'
          : null,
      primaryLabel: 'Try again',
      onPrimary: () => _openWith(_host),
      secondaryLabel: canTryOther ? 'Open with $foreign' : null,
      onSecondary: canTryOther ? () => _openWith(foreign!) : null,
    );
  }

  Widget _buildLoading() {
    return const SkeletonShimmer(
      child: Column(
        children: [
          SkeletonCard(
            height: 120,
            borderRadius: BorderRadius.all(Radius.circular(14)),
            margin: EdgeInsets.all(12),
          ),
          SkeletonCard(
            height: 320,
            borderRadius: BorderRadius.all(Radius.circular(14)),
            margin: EdgeInsets.all(12),
          ),
        ],
      ),
    );
  }
}

/// A message with up to two ways forward.
class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.icon,
    required this.title,
    required this.primaryLabel,
    required this.onPrimary,
    this.subtitle,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            EmptyState(
              icon: Icon(icon, size: 40, color: accent),
              title: title,
              subtitle: subtitle,
            ),
            const SizedBox(height: 28),
            PrimaryButton(
              onTap: onPrimary,
              child: Text(
                primaryLabel,
                textAlign: TextAlign.center,
                style: AppText.bodyStrong.copyWith(color: AppColors.solidWhite),
              ),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 10),
              PillButton(
                onTap: onSecondary!,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Text(
                  secondaryLabel!,
                  textAlign: TextAlign.center,
                  style: AppText.bodyStrong.copyWith(color: accent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
