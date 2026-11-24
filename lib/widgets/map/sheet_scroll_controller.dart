import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// What a sheet's body may do to the sheet it scrolls inside.
class SheetBodyDrag {
  const SheetBodyDrag({
    required this.isRaised,
    required this.isResting,
    required this.moveBy,
    required this.onStart,
    required this.onEnd,
  });

  /// Whether the sheet is at its highest stop, where the body scrolls.
  final bool Function() isRaised;

  /// Whether the sheet is still on one of its stops.
  final bool Function() isResting;

  /// Moves the sheet by `dy` (positive is down) and returns the part of it
  /// the sheet could not take because it reached an end.
  final double Function(double dy) moveBy;

  final VoidCallback onStart;

  /// Lets the sheet settle on a stop, given the finger's speed downwards.
  final ValueChanged<double> onEnd;
}

/// Scrolls a sheet's body, spending each drag on the sheet first.
///
/// One recognizer, the scrollable's own, owns every drag on the body from
/// start to end, and only where each movement goes changes: up, it raises the
/// sheet until the sheet is at its highest stop and scrolls the rest; down, it
/// scrolls back to the start and lowers the sheet with the rest. A second
/// recognizer on the body for moving the sheet would have to win the gesture
/// arena outright, so the hand-over could never happen within one drag.
///
/// With no [body] it is a plain [ScrollController].
class SheetScrollController extends ScrollController {
  SheetScrollController();

  /// Updated by the owner on every build, since the sheet's stops move with
  /// the screen.
  SheetBodyDrag? body;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => _SheetScrollPosition(
    controller: this,
    physics: physics,
    context: context,
    oldPosition: oldPosition,
  );
}

class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition({
    required this.controller,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final SheetScrollController controller;

  /// Between a body drag's start and the ballistic call that ends it.
  ///
  /// Flutter also calls [goBallistic], with zero, whenever the viewport
  /// changes size, and it does on every frame the sheet moves. Only the end
  /// of a drag may settle the sheet, or each frame of the settle would start
  /// it again.
  bool _inDrag = false;

  /// Whether this drag has moved the sheet. If so its end settles the sheet
  /// and its fling is dropped, so a flick that raises the sheet does not send
  /// the list racing on once the sheet arrives.
  bool _movedSheet = false;

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    final body = controller.body;
    _inDrag = body != null;
    _movedSheet = false;
    body?.onStart();
    return super.drag(details, dragCancelCallback);
  }

  /// [delta] is the finger's movement this frame; negative is up.
  @override
  void applyUserOffset(double delta) {
    final body = controller.body;
    if (body == null || delta == 0) return super.applyUserOffset(delta);
    if (delta < 0) return _raise(body, delta);
    _lower(body, delta);
  }

  void _raise(SheetBodyDrag body, double delta) {
    if (body.isRaised()) return super.applyUserOffset(delta);
    _movedSheet = true;
    final left = body.moveBy(delta);
    if (left != 0) super.applyUserOffset(left);
  }

  void _lower(SheetBodyDrag body, double delta) {
    final scroll = math.min(delta, math.max(0.0, pixels - minScrollExtent));
    if (scroll > 0) super.applyUserOffset(scroll);
    final left = delta - scroll;
    if (left <= 0) return;
    _movedSheet = true;
    body.moveBy(left);
  }

  /// [velocity] is in scroll terms: positive scrolls on, so the finger is
  /// going up.
  @override
  void goBallistic(double velocity) {
    final body = controller.body;
    final endsDrag = _inDrag;
    final movedSheet = _movedSheet;
    _inDrag = false;
    _movedSheet = false;
    final settlesSheet =
        body != null && endsDrag && (movedSheet || !body.isResting());
    if (!settlesSheet) return super.goBallistic(velocity);
    body.onEnd(-velocity);
    goIdle();
  }
}
