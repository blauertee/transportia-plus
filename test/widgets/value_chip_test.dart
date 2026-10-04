import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:transportia/models/quick_access_layout.dart';
import 'package:transportia/models/street_leg_choice.dart';
import 'package:transportia/models/transitous/enums.dart';
import 'package:transportia/widgets/options/icon_controls.dart';
import 'package:transportia/widgets/search/leg_panel.dart';
import 'package:transportia/widgets/search/street_leg_section.dart';

Future<void> _pumpLeg(
  WidgetTester tester, {
  required Duration budget,
  Duration maxBudget = const Duration(hours: 2),
  bool budgetOpen = false,
  ValueChanged<Duration>? onBudgetChanged,
}) {
  // Tall enough for the full view's six sections.
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(400, 1400)),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: 380,
            child: StreetLegSection(
              sections: QuickAccessLayout.defaults.streetSections,
              providerNames: const [],
              choice: const StreetLegChoice(
                modes: [TransitMode.walk],
                formFactors: [],
              ),
              budget: budget,
              maxBudget: maxBudget,
              tooltips: OptionTooltipController(),
              view: budgetOpen ? LegView.full : LegView.compact,
              onViewChanged: (_) {},
              onChanged: (_) {},
              onBudgetChanged: onBudgetChanged ?? (_) {},
              limitToMyProviders: false,
              onLimitToMyProvidersPressed: () {},
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('budget text', () {
    test('counts in minutes below an hour', () {
      expect(budgetSummaryText(const Duration(minutes: 15)), '15 min');
      expect(budgetSummaryText(const Duration(minutes: 45)), '45 min');
    });

    test('switches to hours past the first one', () {
      // A raw 90 beside a clock reads as a bug when the summary line above
      // it says an hour and a half.
      expect(budgetSummaryText(const Duration(minutes: 90)), '1 h 30');
      expect(budgetSummaryText(const Duration(minutes: 120)), '2 h');
    });
  });

  testWidgets('the chip carries the budget without opening anything', (
    tester,
  ) async {
    await _pumpLeg(tester, budget: const Duration(minutes: 90));

    expect(find.text('1 h 30'), findsOneWidget);
    // The slider is what you occasionally move; the number is what you read.
    expect(find.byType(OptionSlider), findsNothing);
  });

  testWidgets('the slider stops at the server ceiling', (tester) async {
    Duration? picked;
    await _pumpLeg(
      tester,
      budget: const Duration(minutes: 15),
      maxBudget: const Duration(minutes: 45),
      budgetOpen: true,
      onBudgetChanged: (value) => picked = value,
    );

    final slider = tester.widget<OptionSlider>(find.byType(OptionSlider));
    expect(slider.max, 45);
    expect(find.text('45 min'), findsOneWidget);

    slider.onChanged(43);
    // Snapped to the five-minute step rather than passed through raw.
    expect(picked, const Duration(minutes: 45));
  });

  testWidgets('a budget past the ceiling still renders', (tester) async {
    // Stored defaults outlive a backend change, so the slider has to cope
    // with a value the current server would clamp.
    await _pumpLeg(
      tester,
      budget: const Duration(minutes: 120),
      maxBudget: const Duration(minutes: 45),
      budgetOpen: true,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('2 h'), findsOneWidget);
  });
}
