import 'package:flutter/widgets.dart';

import 'routes.dart';

/// Something a screen can undo when back is pressed, before back leaves it:
/// a picked stop to clear, a field to unfocus, a card to close.
///
/// Steps are instant; leaving a screen is what slides (see [ScreenRoute]).
/// This is the only place back is caught: a raw [PopScope] would be asked
/// alongside every other one on the same route, tabs that are not showing
/// included, and each would act on the same press.
///
/// Steps nest. One press goes to the innermost step that is [enabled] and
/// [canStepBack], and to that one only: the Timetables tab clears its stop
/// before the tab shell around it goes back to the routing tab. With nothing
/// to undo, back leaves the screen.
class BackStep extends StatefulWidget {
  const BackStep({
    super.key,
    required this.canStepBack,
    required this.onStepBack,
    this.enabled = true,
    required this.child,
  });

  /// Whether there is something to undo now.
  final bool canStepBack;

  /// Undoes one thing; back is pressed again for the next.
  final VoidCallback onStepBack;

  /// False while this part of the screen is not showing, like a tab behind
  /// another: neither it nor any step inside it is asked.
  final bool enabled;

  final Widget child;

  @override
  State<BackStep> createState() => _BackStepState();
}

class _BackStepState extends State<BackStep> implements PopEntry<Object?> {
  ModalRoute<Object?>? _route;
  _BackStepState? _outer;
  final Set<_BackStepState> _inner = {};

  @override
  late final ValueNotifier<bool> canPopNotifier = ValueNotifier(!_blocksPop);

  bool get _isEnabled => widget.enabled && (_outer?._isEnabled ?? true);

  /// This step itself has something to undo. Every step tells the route on
  /// its own, so the route knows back is taken without asking the tree.
  bool get _blocksPop => _isEnabled && widget.canStepBack;

  /// This step or one inside it would take the next press.
  bool get _takesBack =>
      _isEnabled && (widget.canStepBack || _inner.any((s) => s._takesBack));

  void _refresh() => canPopNotifier.value = !_blocksPop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final outer = context
        .dependOnInheritedWidgetOfExactType<_BackStepScope>()
        ?.step;
    if (outer != _outer) {
      _outer?._inner.remove(this);
      _outer = outer;
      _outer?._inner.add(this);
    }
    final route = ModalRoute.of(context);
    if (route != _route) {
      _route?.unregisterPopEntry(this);
      _route = route;
      _route?.registerPopEntry(this);
    }
    _refresh();
  }

  @override
  void didUpdateWidget(BackStep oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refresh();
  }

  @override
  void dispose() {
    _outer?._inner.remove(this);
    _route?.unregisterPopEntry(this);
    canPopNotifier.dispose();
    super.dispose();
  }

  // Every step on the route hears the press. The outermost hands it down,
  // so it is acted on once.
  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (didPop || _outer != null) return;
    _stepBack();
  }

  @override
  void onPopInvoked(bool didPop) {}

  void _stepBack() {
    for (final inner in _inner) {
      if (inner._takesBack) return inner._stepBack();
    }
    if (_blocksPop) widget.onStepBack();
  }

  @override
  Widget build(BuildContext context) =>
      _BackStepScope(step: this, enabled: _isEnabled, child: widget.child);
}

/// Lets a step find the one around it, and tells it when that one is
/// switched off.
class _BackStepScope extends InheritedWidget {
  const _BackStepScope({
    required this.step,
    required this.enabled,
    required super.child,
  });

  final _BackStepState step;
  final bool enabled;

  @override
  bool updateShouldNotify(_BackStepScope oldWidget) =>
      step != oldWidget.step || enabled != oldWidget.enabled;
}
