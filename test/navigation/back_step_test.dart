import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/navigation/back_step.dart';
import 'package:transportia/navigation/routes.dart';
import 'package:transportia/widgets/custom_app_bar.dart';

/// A screen with steps nested two deep, like the tab shell around a tab.
class _Steps extends StatefulWidget {
  const _Steps({this.innerEnabled = true, this.withBar = false});

  final bool innerEnabled;
  final bool withBar;

  @override
  State<_Steps> createState() => _StepsState();
}

class _StepsState extends State<_Steps> {
  bool outerOpen = true;
  bool innerOpen = true;
  final List<String> stepped = [];

  @override
  Widget build(BuildContext context) => BackStep(
    canStepBack: outerOpen,
    onStepBack: () => setState(() {
      outerOpen = false;
      stepped.add('outer');
    }),
    child: BackStep(
      enabled: widget.innerEnabled,
      canStepBack: innerOpen,
      onStepBack: () => setState(() {
        innerOpen = false;
        stepped.add('inner');
      }),
      child: Column(
        children: [
          if (widget.withBar) const CustomAppBar(title: 'Steps'),
          Text('outer ${outerOpen ? 'open' : 'closed'}'),
          Text('inner ${innerOpen ? 'open' : 'closed'}'),
        ],
      ),
    ),
  );
}

/// Opens [screen] over a home screen, so there is somewhere to go back to.
Future<void> _open(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(const CupertinoApp(home: Text('Home')));
  tester.state<NavigatorState>(find.byType(Navigator)).openScreen<void>(screen);
  await tester.pumpAndSettle();
}

Future<void> _back(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

_StepsState _steps(WidgetTester tester) =>
    tester.state<_StepsState>(find.byType(_Steps));

void main() {
  testWidgets('back undoes the innermost step first, one per press', (
    tester,
  ) async {
    await _open(tester, const _Steps());

    await _back(tester);
    expect(_steps(tester).stepped, ['inner']);

    await _back(tester);
    expect(_steps(tester).stepped, ['inner', 'outer']);
    expect(find.text('Home'), findsNothing, reason: 'still on the screen');
  });

  testWidgets('with nothing left to undo, back leaves the screen', (
    tester,
  ) async {
    await _open(tester, const _Steps());

    await _back(tester);
    await _back(tester);
    await _back(tester);

    expect(find.byType(_Steps), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('a step that is switched off is passed over', (tester) async {
    await _open(tester, const _Steps(innerEnabled: false));

    await _back(tester);

    expect(_steps(tester).stepped, ['outer']);
    expect(find.text('inner open'), findsOneWidget);
  });

  testWidgets('a step is instant', (tester) async {
    await _open(tester, const _Steps());

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.text('inner closed'), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('the back button takes the same steps as the system back', (
    tester,
  ) async {
    await _open(tester, const _Steps(withBar: true));

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();

    expect(_steps(tester).stepped, ['inner']);
    expect(find.byType(_Steps), findsOneWidget);
  });
}
