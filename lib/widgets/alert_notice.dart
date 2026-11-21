import 'package:flutter/widgets.dart';

import '../models/transitous/alert.dart';
import 'warning_notice.dart';

/// One service alert, on the warning card every screen prints alerts on.
class AlertNotice extends StatelessWidget {
  const AlertNotice({super.key, required this.alert}) : compact = false;

  /// The tighter proportions the itinerary detail screen prints alerts at,
  /// where they sit inside a leg rather than in a card of their own.
  const AlertNotice.compact({super.key, required this.alert}) : compact = true;

  final Alert alert;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return WarningNotice.compact(
        title: alert.headerText,
        body: alert.descriptionText,
      );
    }
    return WarningNotice(title: alert.headerText, body: alert.descriptionText);
  }
}
