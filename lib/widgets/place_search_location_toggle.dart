import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/place_bias_service.dart';
import '../utils/place_bias.dart';
import 'toggle_card.dart';

/// A plain on/off for whether place search is given the rider's position,
/// for someone who just does not want it sent and has no use for a slider.
///
/// It is the slider's "Off" stop under another name, not a second setting:
/// both read and write [PlaceBiasService], so they cannot disagree. Switching
/// off stores [PlaceBias.off]; switching back on restores the strength that
/// was in use before, or [PlaceBias.defaultValue] where there was none.
class PlaceSearchLocationToggle extends StatefulWidget {
  const PlaceSearchLocationToggle({super.key});

  @override
  State<PlaceSearchLocationToggle> createState() =>
      _PlaceSearchLocationToggleState();
}

class _PlaceSearchLocationToggleState extends State<PlaceSearchLocationToggle> {
  /// The last strength that was not off, for switching back on to.
  double _lastOn = PlaceBias.defaultValue;

  @override
  void initState() {
    super.initState();
    unawaited(PlaceBiasService.load());
  }

  void _onChanged(bool on) {
    final current = PlaceBiasService.biasListenable.value;
    if (!PlaceBias.isOff(current)) _lastOn = current;
    unawaited(PlaceBiasService.save(on ? _lastOn : PlaceBias.off));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: PlaceBiasService.biasListenable,
      builder: (context, bias, _) {
        final on = !PlaceBias.isOff(bias);
        return ToggleCard(
          icon: on ? LucideIcons.locateFixed : LucideIcons.locateOff,
          title: 'Use my location for search',
          subtitle: on
              ? 'Places near you are ranked first, which sends your '
                    'position when you search for a place'
              : 'Your location is not sent when you search for a place; '
                    'results are ranked by name alone',
          value: on,
          onChanged: _onChanged,
        );
      },
    );
  }
}
