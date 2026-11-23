import 'package:flutter/widgets.dart';

/// How long a screen takes to slide in, and to slide back out on a pop.
const Duration _kScreenSlideDuration = Duration(milliseconds: 300);

/// How long a sheet takes to fade in and out.
const Duration _kSheetFadeDuration = Duration(milliseconds: 180);

/// Fully transparent: a sheet floats over the screen it was opened from, and
/// its own card dims what is behind it where it wants to.
const Color _kSheetBarrierColor = Color(0x00000000);

/// The one way to put something on the navigator: [openScreen] for a screen,
/// [openSheet] for a sheet over the current screen.
///
/// Every screen opens and pops the same way, so back feels the same
/// everywhere. What a screen can undo before it is left belongs in a
/// [BackStep], not in a route of its own.
extension OpenOnNavigator on NavigatorState {
  /// Slides [screen] in from the right; back slides it out again.
  Future<T?> openScreen<T>(Widget screen) =>
      push<T>(ScreenRoute<T>(builder: (_) => screen));

  /// Opens [screen] in place of the current one, so back skips what it
  /// replaced: a loading screen, for one, that has nothing left to show.
  Future<T?> replaceScreen<T>(Widget screen) =>
      pushReplacement<T, Object?>(ScreenRoute<T>(builder: (_) => screen));

  /// Fades a sheet in over the current screen.
  ///
  /// [builder] is given the sheet's own context, which closes it with
  /// `Navigator.of(sheetContext).pop(result)`. A screen opened from inside
  /// the sheet goes on top of it, so back from that screen comes back to the
  /// sheet.
  ///
  /// [dismissible]: a tap outside the sheet closes it. Off for sheets whose
  /// outside is still meant to be used, or that close themselves.
  Future<T?> openSheet<T>({
    required String label,
    required WidgetBuilder builder,
    bool dismissible = true,
  }) => push<T>(
    RawDialogRoute<T>(
      barrierDismissible: dismissible,
      barrierLabel: label,
      barrierColor: _kSheetBarrierColor,
      transitionDuration: _kSheetFadeDuration,
      pageBuilder: (context, _, _) => builder(context),
      transitionBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// [OpenOnNavigator] from wherever a context is to hand.
extension OpenFromContext on BuildContext {
  /// See [OpenOnNavigator.openScreen].
  Future<T?> openScreen<T>(Widget screen) =>
      Navigator.of(this).openScreen<T>(screen);

  /// See [OpenOnNavigator.replaceScreen].
  Future<T?> replaceScreen<T>(Widget screen) =>
      Navigator.of(this).replaceScreen<T>(screen);

  /// See [OpenOnNavigator.openSheet].
  Future<T?> openSheet<T>({
    required String label,
    required WidgetBuilder builder,
    bool dismissible = true,
  }) => Navigator.of(
    this,
  ).openSheet<T>(label: label, builder: builder, dismissible: dismissible);
}

/// A screen sliding in from the right over the one it was opened from,
/// which stays where it is. Back slides it out the way it came.
///
/// Opened through [OpenOnNavigator.openScreen]; public only so the app's
/// first route can be one too.
class ScreenRoute<T> extends PageRoute<T> {
  ScreenRoute({required this.builder, super.settings});

  final WidgetBuilder builder;

  static final Animatable<Offset> _slideIn = Tween<Offset>(
    begin: const Offset(1, 0),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.ease));

  @override
  Duration get transitionDuration => _kScreenSlideDuration;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => builder(context);

  /// Clipped to the screen before it moves: a carousel's neighbouring cards
  /// hang off its edges, and would otherwise be drawn over the screen
  /// underneath while this one slides.
  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => SlideTransition(
    position: animation.drive(_slideIn),
    child: ClipRect(child: child),
  );

  /// A field still focused on the screen being left would keep the keyboard
  /// up over the one coming back.
  @override
  bool didPop(T? result) {
    FocusManager.instance.primaryFocus?.unfocus();
    return super.didPop(result);
  }
}
