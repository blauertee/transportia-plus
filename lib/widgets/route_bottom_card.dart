import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../models/rental_provider_prefs.dart';
import '../providers/theme_provider.dart';
import '../models/routing_options.dart';
import '../models/time_selection.dart';
import '../models/transitous/server_config.dart';
import '../models/saved_trip.dart';
import '../services/rental_providers_service.dart';
import '../utils/time_utils.dart';
import '../widgets/route_field_box.dart';
import '../theme/app_colors.dart';
import 'map/bottom_sheet_chrome.dart';
import 'floating_nav_bar.dart';
import 'buttons/primary_button.dart';
import 'search/journey_spine.dart';
import 'search/save_default_row.dart';
import 'search/editable_value.dart';
import '../theme/app_text.dart';

class BottomCard extends StatefulWidget {
  const BottomCard({
    super.key,
    required this.isCollapsed,
    this.drag,
    required this.fromCtrl,
    required this.toCtrl,
    required this.onUnfocus,
    required this.onSwapRequested,
    required this.options,
    required this.storedOptions,
    required this.capabilities,
    required this.onOptionsChanged,
    required this.onResetOptions,
    required this.onSaveOptionsAsDefault,
    required this.onAddViaStop,
    required this.onFromPressed,
    required this.onToPressed,
    required this.routeFieldLink,
    required this.fromLoading,
    required this.toLoading,
    required this.onSearch,
    required this.timeSelectionLayerLink,
    required this.onTimeSelectionTap,
    this.onTimeSelectionTapDown,
    this.onTimeSelectionTapCancel,
    required this.timeSelection,
    required this.recentTrips,
    required this.onRecentTripTap,
  });

  final bool isCollapsed;

  /// How the card moves as a sheet over the map. Null when there is no map
  /// and the card is the whole page: nothing to drag it off.
  final SheetDrag? drag;
  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final VoidCallback onUnfocus;
  final VoidCallback onSwapRequested;

  /// The options for the next search, which last only for it.
  final RoutingOptions options;

  /// What a new search starts from, so the card can say when this one differs.
  final RoutingOptions storedOptions;

  /// Bounds the budget sliders to what the connected server will honour.
  final ServerConfig capabilities;

  final ValueChanged<RoutingOptions> onOptionsChanged;
  final VoidCallback onResetOptions;
  final VoidCallback onSaveOptionsAsDefault;
  final VoidCallback onAddViaStop;

  /// Opens the place picker for one end or the other.
  final VoidCallback onFromPressed;
  final VoidCallback onToPressed;

  final LayerLink routeFieldLink;
  final bool fromLoading;
  final bool toLoading;
  final ValueChanged<TimeSelection> onSearch;
  final LayerLink timeSelectionLayerLink;
  final VoidCallback onTimeSelectionTap;
  final VoidCallback? onTimeSelectionTapDown;
  final VoidCallback? onTimeSelectionTapCancel;
  final TimeSelection timeSelection;
  final List<SavedTrip> recentTrips;
  final ValueChanged<SavedTrip> onRecentTripTap;

  @override
  State<BottomCard> createState() => _BottomCardState();
}

class _BottomCardState extends State<BottomCard> {
  /// Holds the row open just long enough to confirm the save, since saving
  /// makes the difference it was reporting disappear.
  bool _savedAsDefault = false;
  Timer? _savedTimer;

  @override
  void didUpdateWidget(covariant BottomCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A further edit is a new difference from the stored defaults, so the
    // confirmation stops applying to it.
    if (oldWidget.options != widget.options) {
      _savedTimer?.cancel();
      _savedAsDefault = false;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _savedTimer?.cancel();
    super.dispose();
  }

  /// How long the row confirms the save for, before going back to reporting
  /// the difference from the stored defaults.
  static const Duration _savedConfirmationFor = Duration(milliseconds: 1800);

  void _saveOptionsAsDefault() {
    widget.onSaveOptionsAsDefault();
    setState(() => _savedAsDefault = true);
    _savedTimer?.cancel();
    _savedTimer = Timer(_savedConfirmationFor, () {
      if (mounted) setState(() => _savedAsDefault = false);
    });
  }

  final ScrollController _scroll = ScrollController();

  /// The journey stages. Collapsed, the card is just a search box.
  Widget? _buildSpine() {
    if (widget.isCollapsed) return null;
    // The provider limit is app-wide, not part of this search's options:
    // it is saved the moment it changes, so it is read straight from the
    // service rather than handed down with them.
    return ValueListenableBuilder<RentalProviderPrefs>(
      valueListenable: RentalProvidersService.prefsListenable,
      builder: (context, providers, _) => JourneySpine(
        options: widget.options,
        capabilities: widget.capabilities,
        onChanged: widget.onOptionsChanged,
        onAddViaStop: widget.onAddViaStop,
        limitToMyProviders: providers.isActive,
        rentalProviderNames: [for (final group in providers.groups) group.name],
        onLimitToMyProvidersChanged: RentalProvidersService.setLimit,
        opening: context.select<ThemeProvider, SearchOptionsOpening>(
          (theme) => theme.searchOptionsOpening,
        ),
      ),
    );
  }

  /// Everything between the handle and the action bar, as one scroll.
  ///
  /// The fields, the journey stages and the trip lists share a single
  /// scrollable so that expanding a stage pushes the rest down rather than
  /// stranding it: collapsing a section to reach the one below it is the
  /// wrong way round.
  Widget _buildScrollableBody(
    BuildContext context, {
    required List<Widget> above,
    required List<Widget> below,
  }) {
    return SingleChildScrollView(
      controller: _scroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...above,
          if (!widget.isCollapsed) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: below,
              ),
            ),
            // Clears the pinned action bar's shadow.
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = _buildContent(context);
    if (widget.drag == null) {
      return ColoredBox(
        color: AppColors.white,
        child: SafeArea(child: content),
      );
    }
    return BottomSheetSurface(child: content);
  }

  Widget _buildContent(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onUnfocus,
      child: Listener(
        onPointerDown: (_) => widget.onUnfocus(),
        child: SizedBox.expand(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTop(),

              Expanded(
                child: _buildScrollableBody(
                  context,
                  above: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      child: Listener(
                        onPointerDown: (_) {},
                        behavior: HitTestBehavior.opaque,
                        child: GestureDetector(
                          onTap: () {},
                          behavior: HitTestBehavior.opaque,
                          child: RouteFieldBox(
                            fromController: widget.fromCtrl,
                            toController: widget.toCtrl,
                            accentColor: AppColors.accentOf(context),
                            onSwapRequested: widget.onSwapRequested,
                            layerLink: widget.routeFieldLink,
                            fromLoading: widget.fromLoading,
                            toLoading: widget.toLoading,
                            middle: _buildSpine(),
                            timeLine: _buildTimeLine(),
                            footer: _buildSearchButton(),
                            onFromPressed: widget.onFromPressed,
                            onToPressed: widget.onToPressed,
                          ),
                        ),
                      ),
                    ),

                    // Always offered, not only once something differs:
                    // the row is where the routing options are managed
                    // from, and hunting for a button that appears and
                    // disappears is worse than one that is simply there.
                    if (!widget.isCollapsed)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                        child: SaveDefaultRow(
                          saved: _savedAsDefault,
                          differsFromStored:
                              widget.options != widget.storedOptions,
                          onReset: widget.onResetOptions,
                          onSaveAsDefault: _saveOptionsAsDefault,
                        ),
                      ),
                  ],
                  below: [
                    GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: widget.onUnfocus,
                      child: _RecentTrips(
                        trips: widget.recentTrips,
                        onTap: widget.onRecentTripTap,
                      ),
                    ),
                    // Clears the floating nav bar, which is a sibling
                    // painted over this card rather than beside it.
                    const SizedBox(height: FloatingNavBar.reservedHeight),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The grab bar over the map; on its own page the card just starts.
  Widget _buildTop() {
    final drag = widget.drag;
    if (drag == null) return const SizedBox(height: 16);
    return BottomSheetHandle(drag: drag, bottomGap: 18);
  }

  Widget _buildTimeLine() {
    final time = widget.timeSelection;
    return CompositedTransformTarget(
      link: widget.timeSelectionLayerLink,
      child: EditableValue.time(
        label: time.toSearchLabel(),
        semanticsLabel: 'Change departure or arrival time',
        onTap: widget.onTimeSelectionTap,
        onTapDown: widget.onTimeSelectionTapDown,
        onTapCancel: widget.onTimeSelectionTapCancel,
      ),
    );
  }

  Widget _buildSearchButton() {
    return PrimaryButton(
      onTap: () => widget.onSearch(widget.timeSelection),
      child: const Center(
        child: Text(
          'Search',
          style: TextStyle(
            color: AppColors.solidWhite,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// The connections most recently opened, each reopened as itself.
class _RecentTrips extends StatelessWidget {
  const _RecentTrips({required this.trips, required this.onTap});

  final List<SavedTrip> trips;
  final ValueChanged<SavedTrip> onTap;

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text('Recent trips', style: AppText.heading),
        const SizedBox(height: 12),
        for (final trip in trips)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _RecentTripTile(trip: trip, onTap: () => onTap(trip)),
          ),
      ],
    );
  }
}

class _RecentTripTile extends StatelessWidget {
  const _RecentTripTile({required this.trip, required this.onTap});

  final SavedTrip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.black.withValues(alpha: 0.6);
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.black.withValues(alpha: 0.07),
                ),
              ),
              alignment: Alignment.center,
              child: Icon(LucideIcons.route, size: 18, color: AppColors.black),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.fromName,
                    style: AppText.listTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(LucideIcons.chevronRight, size: 14, color: muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          trip.toName,
                          style: TextStyle(
                            color: muted,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Which departure it was: the same two places can be in the list
            // more than once, and a trip is that one journey.
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatTime(trip.departureTime), style: AppText.bodyStrong),
                const SizedBox(height: 2),
                Text(
                  formatRelativeDay(trip.departureTime),
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
