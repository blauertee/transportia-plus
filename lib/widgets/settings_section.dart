import 'package:flutter/widgets.dart';
import '../theme/app_colors.dart';
import 'options/icon_controls.dart';

class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
    this.spacing = 0,
  });

  final String title;
  final List<Widget> children;
  final EdgeInsetsGeometry padding;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The same small caps as the search options' groups, aligned under
          // the page's title rather than centred.
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: OptionGroupHeading(title),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppColors.black.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.black.withValues(alpha: 0.04),
              ),
            ),
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: EdgeInsets.only(
                        left: 60,
                        bottom: spacing,
                        top: spacing,
                      ),
                      child: SizedBox(
                        height: 1,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.black.withValues(alpha: 0.04),
                          ),
                        ),
                      ),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
