import 'dart:ui' show AppLifecycleState;

import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/utils/map_visibility.dart';

void main() {
  const shown = MapVisibility(
    isTabActive: true,
    isOnstage: true,
    isAppResumed: true,
  );

  test('is visible only on its tab, uncovered, in the foreground', () {
    expect(shown.isVisible, isTrue);
    expect(shown.withTabActive(false).isVisible, isFalse);
    expect(shown.withOnstage(false).isVisible, isFalse);
    expect(
      shown.withLifecycleState(AppLifecycleState.paused).isVisible,
      isFalse,
    );
  });

  test('every lifecycle state but resumed hides it', () {
    for (final state in AppLifecycleState.values) {
      expect(
        shown.withLifecycleState(state).isVisible,
        state == AppLifecycleState.resumed,
        reason: '$state',
      );
    }
  });

  test('coming back to the tab does not show it while backgrounded', () {
    final backgrounded = shown
        .withTabActive(false)
        .withLifecycleState(AppLifecycleState.hidden);
    expect(backgrounded.withTabActive(true).isVisible, isFalse);
    expect(
      backgrounded
          .withTabActive(true)
          .withLifecycleState(AppLifecycleState.resumed)
          .isVisible,
      isTrue,
    );
  });

  test('a map built before the first frame counts as in the foreground', () {
    final initial = MapVisibility.initial(
      isTabActive: true,
      isOnstage: true,
      lifecycleState: null,
    );
    expect(initial.isVisible, isTrue);
  });

  test('popping the page above it shows it again', () {
    final covered = shown.withOnstage(false);
    expect(covered.withOnstage(true).isVisible, isTrue);
  });

  test('a map built on a hidden tab starts hidden', () {
    final initial = MapVisibility.initial(
      isTabActive: false,
      isOnstage: true,
      lifecycleState: AppLifecycleState.resumed,
    );
    expect(initial.isVisible, isFalse);
  });
}
