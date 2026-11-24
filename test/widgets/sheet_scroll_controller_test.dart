import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/widgets/map/sheet_scroll_controller.dart';

const double _kTop = 30;
const double _kRest = 180;
const double _kDown = 560;
const double _kFling = 700;

/// A sheet over nothing, with a body scrolled by [SheetScrollController]: the
/// stops, the settling and the scroll, without the map screen around them.
class _SheetHost extends StatefulWidget {
  const _SheetHost({
    this.top = _kTop,
    this.contentHeight = 2000,
    this.withBody = true,
  });

  final double top;
  final double contentHeight;
  final bool withBody;

  @override
  State<_SheetHost> createState() => _SheetHostState();
}

class _SheetHostState extends State<_SheetHost>
    with SingleTickerProviderStateMixin {
  late double sheetTop = _kRest;
  final scroll = SheetScrollController();
  final List<double> settles = [];
  late final AnimationController _settle;

  @override
  void initState() {
    super.initState();
    _settle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  List<double> get _stops => {widget.top, _kRest, _kDown}.toList()..sort();

  bool _isOn(double stop) => (sheetTop - stop).abs() < 0.5;

  double _moveBy(double dy) {
    final next = (sheetTop + dy).clamp(widget.top, _kDown);
    final used = next - sheetTop;
    setState(() => sheetTop = next);
    return dy - used;
  }

  void _settleOnStop(double velocityDown) {
    settles.add(velocityDown);
    final from = sheetTop;
    final to = _stopFor(velocityDown);
    _settle
      ..stop()
      ..reset();
    final animation = Tween<double>(begin: from, end: to).animate(_settle);
    void follow() => setState(() => sheetTop = animation.value);
    animation.addListener(follow);
    _settle.forward().whenComplete(() => animation.removeListener(follow));
  }

  double _stopFor(double velocityDown) {
    if (velocityDown > _kFling) {
      return _stops.firstWhere((s) => s > sheetTop + 1, orElse: () => _kDown);
    }
    if (velocityDown < -_kFling) {
      return _stops.lastWhere(
        (s) => s < sheetTop - 1,
        orElse: () => widget.top,
      );
    }
    return _stops.reduce(
      (a, b) => (a - sheetTop).abs() <= (b - sheetTop).abs() ? a : b,
    );
  }

  @override
  void dispose() {
    _settle.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    scroll.body = widget.withBody
        ? SheetBodyDrag(
            isRaised: () => _isOn(widget.top),
            isResting: () => !_settle.isAnimating && _stops.any(_isOn),
            moveBy: _moveBy,
            onStart: _settle.stop,
            onEnd: _settleOnStop,
          )
        : null;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: sheetTop,
            bottom: 0,
            child: SingleChildScrollView(
              key: const Key('body'),
              controller: scroll,
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              child: SizedBox(height: widget.contentHeight),
            ),
          ),
        ],
      ),
    );
  }
}

Future<_SheetHostState> _pump(
  WidgetTester tester, {
  double top = _kTop,
  double contentHeight = 2000,
  bool withBody = true,
}) async {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    _SheetHost(top: top, contentHeight: contentHeight, withBody: withBody),
  );
  return tester.state<_SheetHostState>(find.byType(_SheetHost));
}

/// A slow drag on the body by [dy] (negative is up), held still before it is
/// let go so it ends without a fling.
Future<void> _slowDrag(WidgetTester tester, double dy) async {
  final body = tester.getRect(find.byKey(const Key('body')));
  final gesture = await tester.startGesture(
    body.topCenter + const Offset(0, 40),
  );
  const steps = 20;
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(Offset(0, dy / steps));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 200));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _flick(WidgetTester tester, double dy) async {
  final body = tester.getRect(find.byKey(const Key('body')));
  await tester.flingFrom(
    body.topCenter + const Offset(0, 300),
    Offset(0, dy),
    2500,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one drag up raises the sheet to the top, then scrolls on', (
    tester,
  ) async {
    final sheet = await _pump(tester);

    await _slowDrag(tester, -400);

    expect(sheet.sheetTop, _kTop, reason: 'the sheet goes all the way up');
    expect(
      (_kRest - _kTop) + sheet.scroll.offset,
      closeTo(400, 4),
      reason: 'what the sheet could not take scrolls the list',
    );
  });

  testWidgets('a drag up from where it rests moves the sheet, not the list', (
    tester,
  ) async {
    final sheet = await _pump(tester);

    await _slowDrag(tester, -40);

    expect(sheet.scroll.offset, 0);
    expect(sheet.settles, hasLength(1), reason: 'it settles back on a stop');
    expect(sheet.sheetTop, _kRest);
  });

  testWidgets('a drag down scrolls back to the start before it lowers', (
    tester,
  ) async {
    final sheet = await _pump(tester);
    await _slowDrag(tester, -400);
    final scrolled = sheet.scroll.offset;

    await _slowDrag(tester, scrolled + 100);

    expect(sheet.scroll.offset, 0);
    expect(sheet.sheetTop, isNot(_kTop), reason: 'the rest lowered the sheet');
    expect(sheet.sheetTop, _kRest, reason: 'and it settled on the next stop');
  });

  testWidgets('a drag that only scrolls leaves the sheet alone', (
    tester,
  ) async {
    final sheet = await _pump(tester);
    await _slowDrag(tester, -400);
    sheet.settles.clear();

    await _slowDrag(tester, -100);
    await _slowDrag(tester, 50);

    expect(sheet.settles, isEmpty, reason: 'no settle, so no snap and no tick');
    expect(sheet.sheetTop, _kTop);
  });

  testWidgets('a flick that raises the sheet does not fling the list on', (
    tester,
  ) async {
    final sheet = await _pump(tester);

    await _flick(tester, -300);

    expect(sheet.sheetTop, _kTop);
    expect(
      sheet.scroll.offset,
      lessThan(300),
      reason: 'the list moves only as far as the finger did past the stop',
    );
  });

  testWidgets('once the sheet is up, a flick flings the list', (tester) async {
    final sheet = await _pump(tester);
    await _flick(tester, -300);
    final before = sheet.scroll.offset;

    await _flick(tester, -300);

    expect(sheet.scroll.offset - before, greaterThan(300));
    expect(sheet.sheetTop, _kTop);
  });

  testWidgets('a flick down from where it rests goes one stop down', (
    tester,
  ) async {
    final sheet = await _pump(tester);

    await _flick(tester, 150);

    expect(sheet.sheetTop, _kDown);
  });

  testWidgets('the sheet settles once a drag, though its body resizes as it '
      'moves', (tester) async {
    // Every frame the sheet moves, its body changes height and Flutter calls
    // goBallistic(0) on the idle scroll. Taken for a drag's end, that settle
    // would restart itself on every frame of its own animation.
    final sheet = await _pump(tester);

    await _slowDrag(tester, -60);

    expect(sheet.settles, hasLength(1));
    expect(sheet.sheetTop, _kRest);
  });

  testWidgets('the body moves the sheet even when everything fits', (
    tester,
  ) async {
    final sheet = await _pump(tester, contentHeight: 100);

    await _slowDrag(tester, -300);

    expect(sheet.sheetTop, _kTop);
  });

  testWidgets('a sheet whose top stop is where it rests scrolls at once, and '
      'still lowers from the start of its list', (tester) async {
    final sheet = await _pump(tester, top: _kRest);

    await _slowDrag(tester, -200);
    expect(sheet.sheetTop, _kRest);
    expect(sheet.scroll.offset, closeTo(200, 4));

    await _flick(tester, 600);
    expect(sheet.scroll.offset, 0);
    expect(sheet.sheetTop, _kDown);
  });

  testWidgets('without a body it scrolls like any other controller', (
    tester,
  ) async {
    final sheet = await _pump(tester, withBody: false);

    await _slowDrag(tester, -200);

    expect(sheet.sheetTop, _kRest);
    expect(sheet.scroll.offset, closeTo(200, 4));
    expect(sheet.settles, isEmpty);
  });
}
