import 'package:flutter/widgets.dart';

import '../models/routing_options.dart';
import '../widgets/app_page_scaffold.dart';
import 'search_options/search_options_via_stops.dart';

/// Picks the stops a journey should pass through.
///
/// A screen rather than a control in the spine: choosing one means searching
/// for it, and a search field inside a section that is itself inside a search
/// card has nowhere to put its results.
///
/// Every change is handed over as it is made, so back is an ordinary back.
/// Only whole stops are changes: a half-typed name stays in the field.
class ViaStopsScreen extends StatefulWidget {
  const ViaStopsScreen({
    super.key,
    required this.options,
    required this.onChanged,
  });

  final RoutingOptions options;
  final ValueChanged<RoutingOptions> onChanged;

  @override
  State<ViaStopsScreen> createState() => _ViaStopsScreenState();
}

class _ViaStopsScreenState extends State<ViaStopsScreen> {
  late RoutingOptions _options = widget.options;

  void _onChanged(RoutingOptions next) {
    setState(() => _options = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: 'Travel through',
      scrollable: true,
      body: SearchOptionsViaStopsCard(options: _options, onChanged: _onChanged),
    );
  }
}
