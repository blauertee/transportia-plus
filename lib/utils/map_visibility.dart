import 'dart:ui' show AppLifecycleState;

/// Whether anyone can see the search map: its tab is the one on show, no other
/// page covers it, and the app is in the foreground. The map stays alive
/// behind the shell's other tabs, under pushed pages and while the app is
/// backgrounded, so being built is not being seen.
class MapVisibility {
  const MapVisibility({
    required this.isTabActive,
    required this.isOnstage,
    required this.isAppResumed,
  });

  /// Starting state for a map built while the app is in [lifecycleState].
  MapVisibility.initial({
    required bool isTabActive,
    required bool isOnstage,
    required AppLifecycleState? lifecycleState,
  }) : this(
         isTabActive: isTabActive,
         isOnstage: isOnstage,
         isAppResumed: isResumed(lifecycleState),
       );

  /// Whether the navigation shell shows the map's tab.
  final bool isTabActive;

  /// Whether no opaque page has been pushed over the map. Flutter turns
  /// tickers off for a page that is covered, which is how this is read.
  final bool isOnstage;

  final bool isAppResumed;

  bool get isVisible => isTabActive && isOnstage && isAppResumed;

  MapVisibility withTabActive(bool value) => MapVisibility(
    isTabActive: value,
    isOnstage: isOnstage,
    isAppResumed: isAppResumed,
  );

  MapVisibility withOnstage(bool value) => MapVisibility(
    isTabActive: isTabActive,
    isOnstage: value,
    isAppResumed: isAppResumed,
  );

  MapVisibility withLifecycleState(AppLifecycleState state) => MapVisibility(
    isTabActive: isTabActive,
    isOnstage: isOnstage,
    isAppResumed: isResumed(state),
  );

  /// Only [AppLifecycleState.resumed] counts as seen: `inactive` already
  /// covers the app switcher and the notification shade. A missing state
  /// means the first frame has not been drawn, which happens in the
  /// foreground.
  static bool isResumed(AppLifecycleState? state) =>
      (state ?? AppLifecycleState.resumed) == AppLifecycleState.resumed;
}
