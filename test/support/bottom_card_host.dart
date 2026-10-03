import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'package:transportia/models/routing_options.dart';
import 'package:transportia/models/saved_trip.dart';
import 'package:transportia/models/time_selection.dart';
import 'package:transportia/models/transitous/server_config.dart';
import 'package:transportia/providers/theme_provider.dart';
import 'package:transportia/widgets/map/bottom_sheet_chrome.dart';
import 'package:transportia/widgets/route_bottom_card.dart';

/// A [BottomCard] with every callback stubbed, for tests that care about one
/// or two of them.
class BottomCardHost extends StatefulWidget {
  const BottomCardHost({
    super.key,
    this.from = '',
    this.to = '',
    this.timeSelection,
    this.recentTrips = const [],
    this.onRecentTripTap,
    this.onDragStart,
    this.onDragEnd,
    this.onFromPressed,
    this.onToPressed,
    this.onTimeSelectionTap,
    this.onSearch,
    this.onSwapRequested,
    this.asPage = false,
  });

  /// The card as the whole page, the way it shows with the map turned off.
  final bool asPage;

  final String from;
  final String to;
  final TimeSelection? timeSelection;
  final List<SavedTrip> recentTrips;
  final ValueChanged<SavedTrip>? onRecentTripTap;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final VoidCallback? onFromPressed;
  final VoidCallback? onToPressed;
  final VoidCallback? onTimeSelectionTap;
  final ValueChanged<TimeSelection>? onSearch;
  final VoidCallback? onSwapRequested;

  @override
  State<BottomCardHost> createState() => BottomCardHostState();
}

class BottomCardHostState extends State<BottomCardHost> {
  late final fromCtrl = TextEditingController(text: widget.from);
  late final toCtrl = TextEditingController(text: widget.to);

  @override
  void dispose() {
    fromCtrl.dispose();
    toCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ThemeProvider>(
      create: (_) => ThemeProvider(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(size: Size(400, 900)),
          child: BottomCard(
            isCollapsed: false,
            drag: widget.asPage
                ? null
                : SheetDrag(
                    onTap: () {},
                    onStart: widget.onDragStart ?? () {},
                    onUpdate: (_) {},
                    onEnd: (_) => widget.onDragEnd?.call(),
                  ),
            fromCtrl: fromCtrl,
            toCtrl: toCtrl,
            onUnfocus: () {},
            onSwapRequested: widget.onSwapRequested ?? () {},
            options: RoutingOptions.defaults,
            storedOptions: RoutingOptions.defaults,
            capabilities: ServerConfig.fallback,
            onOptionsChanged: (_) {},
            onResetOptions: () {},
            onSaveOptionsAsDefault: () {},
            onAddViaStop: () {},
            onFromPressed: widget.onFromPressed ?? () {},
            onToPressed: widget.onToPressed ?? () {},
            routeFieldLink: LayerLink(),
            fromLoading: false,
            toLoading: false,
            onSearch: widget.onSearch ?? (_) {},
            timeSelectionLayerLink: LayerLink(),
            onTimeSelectionTap: widget.onTimeSelectionTap ?? () {},
            timeSelection: widget.timeSelection ?? TimeSelection.now(),
            recentTrips: widget.recentTrips,
            onRecentTripTap: widget.onRecentTripTap ?? (_) {},
          ),
        ),
      ),
    );
  }
}
