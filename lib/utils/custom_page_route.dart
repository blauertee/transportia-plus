import 'package:flutter/cupertino.dart';

/// How every screen is pushed: sliding in from the side, and swiped back from
/// the left edge on every platform, so iOS — which has no system back of its
/// own — needs no back button either.
class CustomPageRoute<T> extends PageRoute<T>
    with CupertinoRouteTransitionMixin<T> {
  CustomPageRoute({required this.child});

  final Widget child;

  @override
  Widget buildContent(BuildContext context) => child;

  @override
  String? get title => null;

  @override
  bool get maintainState => true;
}
