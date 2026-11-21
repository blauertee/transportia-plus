import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_colors.dart';
import 'custom_app_bar.dart';

/// Whether the title block draws the screen's icon beside its name. Off: the
/// rows beneath carry icons of their own, and a badge in the title read as
/// one more of them. Every screen still names its icon, so turning this on
/// brings them all back at once.
const bool _kShowIconInTitle = false;

/// Platforms whose system already offers a way back: Android's back gesture
/// or button, and the edge swipe [CustomPageRoute] gives iOS. Elsewhere a
/// pushed screen keeps a back button.
const Set<TargetPlatform> _kPlatformsWithSystemBack = {
  TargetPlatform.android,
  TargetPlatform.iOS,
};

/// How far a pushed screen scrolls before its name moves into the bar, where
/// there is one: about the height of the title, so the name is never gone
/// from both.
const double _kTitleCollapseOffset = 36;

/// The padding round the title block; the body follows straight under it.
const EdgeInsets _kTitlePadding = EdgeInsets.fromLTRB(20, 20, 20, 12);

/// The body's padding when a screen gives none.
const EdgeInsets _kDefaultBodyPadding = EdgeInsets.fromLTRB(20, 16, 20, 24);

/// A screen that opens on its name: the tabs, and the settings and
/// information pages pushed from them. Every such screen is laid out here,
/// so a change to how screens open is made once.
///
/// Tool screens — a search field, a map, a list with actions in its bar —
/// use [AppPageScaffold] instead.
class AppScreen extends StatelessWidget {
  /// A tab of the main navigation: nothing to go back to.
  const AppScreen.tab({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.body,
    this.scrollable = true,
    this.padding = _kDefaultBodyPadding,
  }) : _isPushed = false;

  /// A page pushed from a tab or from another page. Always scrolls.
  const AppScreen.page({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.body,
    this.padding = _kDefaultBodyPadding,
  }) : scrollable = true,
       _isPushed = true;

  /// What the screen is about. Shown in the title only while
  /// [_kShowIconInTitle] is on, and to anything inside the screen through
  /// [ScreenIcon], such as an empty list's placeholder.
  final IconData icon;
  final String title;

  /// One line under the title saying what the screen holds.
  final String? subtitle;
  final Widget body;

  /// True: the title scrolls away with the body. False: the title stays and
  /// the body fills the rest of the screen, for a body that scrolls itself.
  final bool scrollable;
  final EdgeInsetsGeometry padding;

  final bool _isPushed;

  /// The icon of the screen [context] is in, or null outside one.
  static IconData? iconOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AppScreenScope>()?.icon;

  static bool get _hasSystemBack =>
      !kIsWeb && _kPlatformsWithSystemBack.contains(defaultTargetPlatform);

  @override
  Widget build(BuildContext context) {
    final hasBackBar = _isPushed && !_hasSystemBack;
    final titleBlock = Padding(
      // A back bar already spaces the title from the top.
      padding: hasBackBar ? _kTitlePadding.copyWith(top: 0) : _kTitlePadding,
      child: _ScreenTitle(icon: icon, title: title, subtitle: subtitle),
    );
    final paddedBody = Padding(padding: padding, child: body);

    final Widget content;
    if (hasBackBar) {
      content = _WithBackBar(
        title: title,
        titleBlock: titleBlock,
        body: paddedBody,
      );
    } else if (scrollable) {
      content = SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [titleBlock, paddedBody],
        ),
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          titleBlock,
          Expanded(child: paddedBody),
        ],
      );
    }

    return _AppScreenScope(
      icon: icon,
      child: ColoredBox(
        color: AppColors.white,
        child: SafeArea(child: content),
      ),
    );
  }
}

/// A screen's icon on its accent badge, sized for where it stands.
class ScreenIcon extends StatelessWidget {
  /// The size for an empty screen's placeholder.
  const ScreenIcon({super.key}) : size = 56;

  /// The size beside a screen's title.
  const ScreenIcon._title() : size = 48;

  final double size;

  @override
  Widget build(BuildContext context) {
    final icon = AppScreen.iconOf(context);
    if (icon == null) return const SizedBox.shrink();
    final accent = AppColors.accentOf(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.accentWash(accent),
        borderRadius: BorderRadius.circular(size * 0.29),
      ),
      child: Icon(icon, size: size / 2, color: accent),
    );
  }
}

class _AppScreenScope extends InheritedWidget {
  const _AppScreenScope({required this.icon, required super.child});

  final IconData icon;

  @override
  bool updateShouldNotify(_AppScreenScope oldWidget) => icon != oldWidget.icon;
}

/// The screen's name in large type, with its subtitle under it.
class _ScreenTitle extends StatelessWidget {
  const _ScreenTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: AppColors.black,
            height: 1.1,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.black.withValues(alpha: 0.4),
            ),
          ),
        ],
      ],
    );
    if (!_kShowIconInTitle) return text;
    return Row(
      children: [
        const ScreenIcon._title(),
        const SizedBox(width: 16),
        // Expanded, or a long subtitle overflows the row on a narrow screen.
        Expanded(child: text),
      ],
    );
  }
}

/// A pushed screen on a platform with no system back: a bar with the back
/// button above the title, taking the screen's name once the title has
/// scrolled away.
class _WithBackBar extends StatefulWidget {
  const _WithBackBar({
    required this.title,
    required this.titleBlock,
    required this.body,
  });

  final String title;
  final Widget titleBlock;
  final Widget body;

  @override
  State<_WithBackBar> createState() => _WithBackBarState();
}

class _WithBackBarState extends State<_WithBackBar> {
  bool _isTitleScrolledAway = false;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final scrolledAway = notification.metrics.pixels > _kTitleCollapseOffset;
    if (scrolledAway != _isTitleScrolledAway) {
      setState(() => _isTitleScrolledAway = scrolledAway);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CustomAppBar(title: widget.title, titleVisible: _isTitleScrolledAway),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [widget.titleBlock, widget.body],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
