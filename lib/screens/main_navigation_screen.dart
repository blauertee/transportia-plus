import 'package:flutter/cupertino.dart';
import '../widgets/floating_nav_bar.dart';
import 'map_screen.dart';
import 'saved_trips_screen.dart';
import 'timetables_screen.dart';
import 'settings_screen.dart';
import '../services/plan_request.dart';
import '../services/transitous_geocode_service.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  TransitousLocationSuggestion? _pendingTimetableStop;
  final ValueNotifier<bool> _mapCollapsedNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double> _mapCollapseProgressNotifier =
      ValueNotifier<double>(0.0);
  final ValueNotifier<bool> _overlaysVisibleNotifier = ValueNotifier<bool>(
    false,
  );

  void _onNavIndexChanged(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
    }
  }

  void _handleTimetableRequested(TransitousLocationSuggestion stop) {
    setState(() {
      _pendingTimetableStop = stop;
      _currentIndex = _kTimetablesTabIndex;
    });
  }

  /// A screen elsewhere has asked for a journey to be planned, so the routing
  /// tab comes forward holding it. [MapScreen] clears the request once it has
  /// taken it.
  void _handlePlanRequested() {
    if (PlanRequests.pending.value == null) return;
    setState(() => _currentIndex = 0);
  }

  @override
  void initState() {
    super.initState();
    PlanRequests.pending.addListener(_handlePlanRequested);
  }

  /// Index of the map tab, the only one whose sheet can push the nav bar away.
  static const int _kMapTabIndex = 0;
  static const int _kTimetablesTabIndex = 1;

  /// How far the map sheet has to be collapsed before the nav bar starts to
  /// fade, and where it has finished fading. Between the two the bar is on its
  /// way out rather than gone, so a slow drag does not blink it away.
  static const double _kNavFadeStart = 0.6;
  static const double _kNavFadeEnd = 0.9;

  /// How present the floating nav bar should be, given how far the map sheet
  /// is collapsed and whether the map is showing an overlay over everything.
  double _navBarVisibility({
    required double progress,
    required bool overlaysVisible,
  }) {
    if (_currentIndex != _kMapTabIndex) return 1.0;
    if (overlaysVisible) return 0.0;
    if (progress <= _kNavFadeStart) return 1.0;
    if (progress >= _kNavFadeEnd) return 0.0;

    final fadeProgress =
        (progress - _kNavFadeStart) / (_kNavFadeEnd - _kNavFadeStart);
    return 1.0 - Curves.easeInOut.transform(fadeProgress);
  }

  bool _handleBackGesture() {
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return false;
    }
    return true;
  }

  @override
  void dispose() {
    PlanRequests.pending.removeListener(_handlePlanRequested);
    _mapCollapsedNotifier.dispose();
    _mapCollapseProgressNotifier.dispose();
    _overlaysVisibleNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBackGesture();
        }
      },
      child: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              MapScreen(
                onCollapseChanged: (isCollapsed) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _mapCollapsedNotifier.value = isCollapsed;
                  });
                },
                onCollapseProgressChanged: (progress) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _mapCollapseProgressNotifier.value = progress;
                  });
                },
                onOverlayVisibilityChanged: (overlaysVisible) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _overlaysVisibleNotifier.value = overlaysVisible;
                  });
                },
                onTabChangeRequested: _onNavIndexChanged,
                onTimetableRequested: _handleTimetableRequested,
              ),
              TimetablesScreen(
                initialStop: _pendingTimetableStop,
                isOpen: _currentIndex == _kTimetablesTabIndex,
              ),
              const SavedTripsScreen(),
              const SettingsScreen(),
            ],
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              child: ValueListenableBuilder<double>(
                valueListenable: _mapCollapseProgressNotifier,
                builder: (context, progress, child) {
                  return ValueListenableBuilder<bool>(
                    valueListenable: _overlaysVisibleNotifier,
                    builder: (context, overlaysVisible, child) {
                      return FloatingNavBar(
                        currentIndex: _currentIndex,
                        onIndexChanged: _onNavIndexChanged,
                        visibility: _navBarVisibility(
                          progress: progress,
                          overlaysVisible: overlaysVisible,
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
