import 'package:flutter/widgets.dart';

import '../../services/map_rendering_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';

/// A map, or a blank in its place while maps are turned off in the advanced
/// settings. The map widget is only built when shown, so a blank one draws
/// nothing and fetches no tiles.
class SwitchableMap extends StatelessWidget {
  const SwitchableMap({super.key, required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final service = MapRenderingService.instance;
    return ListenableBuilder(
      listenable: service,
      builder: (context, _) {
        if (!service.state.mapsOff) return builder(context);
        return ColoredBox(
          color: AppColors.black.withValues(alpha: 0.04),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Maps are turned off in Settings › Advanced',
                textAlign: TextAlign.center,
                style: AppText.bodyFaint,
              ),
            ),
          ),
        );
      },
    );
  }
}
