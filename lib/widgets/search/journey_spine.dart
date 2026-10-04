import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../models/routing_options.dart';
import '../../models/street_leg_choice.dart';
import '../../models/transit_mode_group.dart';
import '../../theme/app_colors.dart';
import '../../utils/journey_colors.dart';
import '../journey/spine_row.dart';
import '../../models/transitous/server_config.dart';
import '../../providers/theme_provider.dart';
import '../options/icon_controls.dart';
import '../../utils/stage_summary.dart';
import 'journey_segment.dart';
import 'leg_panel.dart';
import 'street_leg_section.dart';
import 'transit_section.dart';
import 'traveller_strip.dart';

/// Which stage of the journey is expanded, if any.
enum _Stage { toStation, transport, fromStation }

/// The options for one search, laid out in the order the journey happens.
///
/// Sits between the origin and destination fields, so the three stages read
/// as the journey rather than as a settings list: what gets you to the first
/// stop, what you ride, and what gets you from the last one.
class JourneySpine extends StatefulWidget {
  const JourneySpine({
    super.key,
    required this.options,
    required this.capabilities,
    required this.onChanged,
    required this.onAddViaStop,
    required this.limitToMyProviders,
    required this.hasRentalProviders,
    required this.onLimitToMyProvidersChanged,
    this.opening = SearchOptionsOpening.closed,
  });

  final RoutingOptions options;

  /// Bounds the budget sliders, so they cannot offer what the server clamps.
  final ServerConfig capabilities;

  final ValueChanged<RoutingOptions> onChanged;

  /// Opens the stop picker; via stops need a search of their own.
  final VoidCallback onAddViaStop;

  /// The app-wide "rent only from my providers" setting. Not part of
  /// [options]: it is saved the moment it changes, rather than with the
  /// search.
  final bool limitToMyProviders;

  /// Whether any provider has been named in the settings. Without one the
  /// limit has nothing to keep to, so turning it on is refused with a hint.
  final bool hasRentalProviders;

  final ValueChanged<bool> onLimitToMyProvidersChanged;

  /// How far the stages are open when the card appears, and what a stage
  /// shows each time it is opened again.
  final SearchOptionsOpening opening;

  @override
  State<JourneySpine> createState() => _JourneySpineState();
}

class _JourneySpineState extends State<JourneySpine> {
  final OptionTooltipController _tooltips = OptionTooltipController();

  final Set<_Stage> _open = {};
  bool _paceOpen = false;

  /// What each open stage shows, where the rider has changed it from
  /// [_defaultView]. Forgotten when the stage closes: opening it again starts
  /// from the setting, not from wherever the last visit left it.
  final Map<_Stage, LegView> _views = {};

  /// Whether the rider has opened or closed anything yet. Until then the
  /// stages follow the setting, which may arrive after the card is built.
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _applyOpening();
  }

  @override
  void didUpdateWidget(JourneySpine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.opening != oldWidget.opening && !_touched) _applyOpening();
  }

  void _applyOpening() {
    _open
      ..clear()
      ..addAll(
        widget.opening == SearchOptionsOpening.closed ? {} : _Stage.values,
      );
    _views.clear();
  }

  LegView get _defaultView => widget.opening == SearchOptionsOpening.everything
      ? LegView.full
      : LegView.compact;

  LegView _viewOf(_Stage stage) => _views[stage] ?? _defaultView;

  OptionAnnouncement? _announcement;
  Timer? _announcementTimer;

  @override
  void dispose() {
    _announcementTimer?.cancel();
    _tooltips.dispose();
    super.dispose();
  }

  /// Says what a tap just did, since an icon alone cannot.
  ///
  /// Held as a timer rather than a delayed future so a quick second tap
  /// replaces the first message instead of having it time out on top of the
  /// new one, and so nothing is left running once the card is gone.
  void _announce(String text, {IconData? icon}) {
    _announcementTimer?.cancel();
    setState(() => _announcement = OptionAnnouncement(text, icon: icon));
    _announcementTimer = Timer(const Duration(milliseconds: 1900), () {
      if (!mounted) return;
      setState(() => _announcement = null);
    });
  }

  /// Any change can move a control out from under the finger, and a tooltip
  /// left behind would never be dismissed.
  void _apply(RoutingOptions options) {
    _tooltips.hide();
    widget.onChanged(options);
  }

  void _toggleStage(_Stage stage) {
    _tooltips.hide();
    setState(() {
      _touched = true;
      if (_open.remove(stage)) {
        _views.remove(stage);
      } else {
        _open.add(stage);
      }
    });
  }

  void _toggleProviderLimit() {
    _tooltips.hide();
    if (!widget.hasRentalProviders) {
      _announce(
        'No providers set. Add yours in Search and routing options',
        icon: LucideIcons.circleAlert,
      );
      return;
    }
    final next = !widget.limitToMyProviders;
    widget.onLimitToMyProvidersChanged(next);
    _announce(
      next ? 'Only your providers' : 'Any provider',
      icon: LucideIcons.scooter,
    );
  }

  Duration get _mileCeiling => widget.capabilities.maxPrePostTransitTime;

  @override
  Widget build(BuildContext context) {
    final options = widget.options;

    return OptionOverlayHost(
      controller: _tooltips,
      announcement: _announcement,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // On the spine, with no node of its own: who is travelling is not a
          // stage of the journey, but the line still has to run past it. Left
          // off the spine, the dotted rail from the origin marker stopped
          // short of the first stage's ring by the height of this strip.
          SpineRow(
            timeColumn: 0,
            padding: EdgeInsets.zero,
            node: const SizedBox.shrink(),
            nodeCenter: 0,
            railColor: kStreetLegColor,
            railDashed: true,
            firstLineHeight: 0,
            body: Padding(
              // Inside the row, because a gap between rows is a gap in the
              // line.
              padding: const EdgeInsets.only(bottom: 16),
              child: TravellerStrip(
                options: options,
                tooltips: _tooltips,
                paceOpen: _paceOpen,
                onPacePressed: () {
                  _tooltips.hide();
                  setState(() => _paceOpen = !_paceOpen);
                },
                onChanged: (next) {
                  _apply(next);
                  if (next.wheelchairAccessibleOnly !=
                      options.wheelchairAccessibleOnly) {
                    _announce(
                      next.wheelchairAccessibleOnly
                          ? 'Step-free only'
                          : 'Step-free off',
                      icon: LucideIcons.accessibility,
                    );
                  }
                },
              ),
            ),
          ),
          _buildStages(options),
        ],
      ),
    );
  }

  /// Links the way from the station to the way there, or sets it apart.
  ///
  /// Linking closes the stage: there is nothing of its own left to set.
  /// Unlinking opens it, since setting it apart is why anyone would.
  void _toggleLastMileLink(RoutingOptions options) {
    final linking = !options.lastMileSameAsFirst;
    _tooltips.hide();
    setState(() {
      _touched = true;
      _views.remove(_Stage.fromStation);
      if (linking) {
        _open.remove(_Stage.fromStation);
      } else {
        _open.add(_Stage.fromStation);
      }
    });
    widget.onChanged(options.withLastMileSameAsFirst(linking));
    _announce(
      linking
          ? 'From the station: same as to the station'
          : 'From the station: set separately',
      icon: LucideIcons.link2,
    );
  }

  void _setView(_Stage stage, LegView view) {
    _tooltips.hide();
    setState(() {
      _touched = true;
      _views[stage] = view;
    });
  }

  Widget _buildStages(RoutingOptions options) {
    // The street stages take the same neutral the itinerary gives a walk, and
    // the ride takes the accent: the search is a picture of the trip's shape
    // before there is a route to colour it with.
    final accent = AppColors.accentOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _streetStage(
          stage: _Stage.toStation,
          headline: 'To the station',
          where: 'to the station',
          choice: StreetLegChoice(
            modes: options.firstMileModes,
            formFactors: options.firstMileRentalFormFactors,
          ),
          budget: options.maxFirstMileTime,
          onChanged: (choice) => options.copyWith(
            firstMileModes: choice.modes,
            firstMileRentalFormFactors: choice.formFactors,
          ),
          onBudgetChanged: (budget) =>
              options.copyWith(maxFirstMileTime: budget),
        ),
        JourneySegment(
          color: accent,
          icon: LucideIcons.trainFront,
          headline: 'Public transport',
          summary: stageSummary(
            options.transitSelection.summary(),
            _changesText(options.maxTransfers),
          ),
          isOpen: _open.contains(_Stage.transport),
          onToggle: () => _toggleStage(_Stage.transport),
          child: TransitSection(
            options: options,
            tooltips: _tooltips,
            view: _viewOf(_Stage.transport),
            onViewChanged: (view) => _setView(_Stage.transport, view),
            onViaPressed: widget.onAddViaStop,
            onChanged: (next) {
              _apply(next);
              _announceTransitChange(options, next);
            },
          ),
        ),
        _streetStage(
          stage: _Stage.fromStation,
          headline: 'From the station',
          where: 'from the station',
          choice: StreetLegChoice(
            modes: options.lastMileModesInUse,
            formFactors: options.lastMileRentalFormFactorsInUse,
          ),
          budget: options.maxLastMileTimeInUse,
          onChanged: (choice) => options.copyWith(
            lastMileModes: choice.modes,
            lastMileRentalFormFactors: choice.formFactors,
          ),
          onBudgetChanged: (budget) =>
              options.copyWith(maxLastMileTime: budget),
          link: StageLink(
            linked: options.lastMileSameAsFirst,
            label: 'Same as to the station',
            onPressed: () => _toggleLastMileLink(options),
          ),
        ),
      ],
    );
  }

  /// A street stage: the two differ only in which half of the options they
  /// read and write, and in that the way from the station can be [link]ed to
  /// the way there.
  Widget _streetStage({
    required _Stage stage,
    required String headline,
    required String where,
    required StreetLegChoice choice,
    required Duration budget,
    required RoutingOptions Function(StreetLegChoice) onChanged,
    required RoutingOptions Function(Duration) onBudgetChanged,
    StageLink? link,
  }) {
    final linked = link?.linked ?? false;
    return JourneySegment(
      color: kStreetLegColor,
      dashed: true,
      // Linked, [choice] is the way there, so the ring shows how the rider
      // will actually travel.
      icon: streetLegIcon(choice),
      headline: headline,
      summary: linked
          ? link!.label
          : stageSummary(choice.summary, budgetSummaryText(budget)),
      // A linked stage stays closed whatever the opening setting says.
      isOpen: !linked && _open.contains(stage),
      onToggle: () => _toggleStage(stage),
      link: link,
      child: StreetLegSection(
        choice: choice,
        budget: budget,
        maxBudget: _mileCeiling,
        tooltips: _tooltips,
        view: _viewOf(stage),
        onViewChanged: (view) => _setView(stage, view),
        onChanged: (next) {
          _apply(onChanged(next));
          _announceStreetChange(choice, next, where);
        },
        onBudgetChanged: (next) => _apply(onBudgetChanged(next)),
        limitToMyProviders: widget.limitToMyProviders,
        onLimitToMyProvidersPressed: _toggleProviderLimit,
      ),
    );
  }

  /// Names the section that was just switched on or off, since its icon
  /// alone cannot say which of the two happened.
  void _announceStreetChange(
    StreetLegChoice before,
    StreetLegChoice after,
    String where,
  ) {
    for (final section in StreetSection.values) {
      final wasOn = before.stateOf(section) != GroupState.none;
      if (wasOn == (after.stateOf(section) != GroupState.none)) continue;
      _announce(
        wasOn
            ? 'No ${section.title.toLowerCase()} $where'
            : '${section.title} $where',
        icon: streetSectionIcons[section],
      );
      return;
    }
  }

  /// Names whichever transport-section control changed, so an icon-only tap
  /// still says what it did.
  void _announceTransitChange(RoutingOptions before, RoutingOptions after) {
    if (after.requireBikeTransport != before.requireBikeTransport) {
      _announce(
        after.requireBikeTransport
            ? 'Bike carried on board'
            : 'Bike not carried',
        icon: LucideIcons.bike,
      );
      return;
    }
    if (after.requireCarTransport != before.requireCarTransport) {
      _announce(
        after.requireCarTransport ? 'Car carried on board' : 'Car not carried',
        icon: LucideIcons.car,
      );
      return;
    }
    if (after.noCompulsoryReservation != before.noCompulsoryReservation) {
      _announce(
        after.noCompulsoryReservation
            ? 'Reservation-free only'
            : 'Reservations allowed',
        icon: LucideIcons.ticketX,
      );
      return;
    }
    if (after.transitSelection.isRegionalOnly !=
        before.transitSelection.isRegionalOnly) {
      _announce(
        after.transitSelection.isRegionalOnly
            ? 'Regional only'
            : 'Long-distance too',
      );
      return;
    }
    if (after.maxTransfers != before.maxTransfers) {
      _announce(
        _changesText(
          after.maxTransfers,
        ).replaceRange(0, 1, _changesText(after.maxTransfers)[0].toUpperCase()),
        icon: after.maxTransfers == null
            ? LucideIcons.infinity
            : LucideIcons.waypoints,
      );
      return;
    }
    if (after.transitSelection != before.transitSelection) {
      _announce(after.transitSelection.summary());
    }
  }

  static String _changesText(int? maxTransfers) {
    if (maxTransfers == null) return 'unlimited changes';
    if (maxTransfers == 0) return 'no changes';
    return 'max $maxTransfers ${maxTransfers == 1 ? "change" : "changes"}';
  }
}
