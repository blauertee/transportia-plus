import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../environment.dart';
import '../providers/theme_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/app_icon_header.dart';
import '../widgets/app_page_scaffold.dart';
import '../widgets/custom_card.dart';
import '../widgets/validation_toast.dart';
import '../widgets/icon_badge.dart';
import '../theme/app_text.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (context.mounted) {
        showValidationToast(context, "Unable to open link.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<ThemeProvider>();

    DateTime now = DateTime.now();
    int year = now.year;

    return AppPageScaffold(
      title: 'Legal',
      scrollable: true,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const AppIconHeader(
            icon: LucideIcons.scale,
            title: 'Legal Information',
            subtitle: 'Om nom nom nom 🍪',
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 32),
              _buildLegalCard(
                context: context,
                icon: LucideIcons.fileText,
                title: 'Terms of Service',
                description:
                    'The terms and conditions for using ${Environment.appName}',
                onTap: () => _openUrl(context, Environment.termsUrl),
              ),
              const SizedBox(height: 12),
              _buildLegalCard(
                context: context,
                icon: LucideIcons.shieldCheck,
                title: 'Privacy Policy',
                description: 'What the app does and does not do with your data',
                onTap: () => _openUrl(context, Environment.privacyUrl),
              ),
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.black.withValues(alpha: 0.02),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.black.withValues(alpha: 0.04),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          LucideIcons.database,
                          size: 20,
                          color: AppColors.accentOf(context),
                        ),
                        const SizedBox(width: 8),
                        Text('Data Collected', style: AppText.heading),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildDataItem(
                      'None at all, that\'s the best part!',
                      context,
                    ),
                    _buildDataItem(
                      'Third-party services may collect data as per their policies',
                      context,
                    ),
                    _buildDataItem(
                      'Tapping a search result on the map asks OpenStreetMap\'s '
                      'Nominatim which place it is, unless turned off under '
                      'Location',
                      context,
                    ),
                    _buildDataItem(
                      'For more details, see the Privacy Policy',
                      context,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your data is never sold to third parties.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: Column(
                  children: [
                    Text(
                      '© $year Wafler.one and blauertee',
                      style: AppText.subtitle,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Free software under the GPL-3.0',
                      style: AppText.subtitle,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegalCard({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String description,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: CustomCard(
        margin: EdgeInsets.zero,
        padding: const EdgeInsets.all(16),
        borderRadius: BorderRadius.circular(12),
        borderColor: AppColors.hairline,
        child: Row(
          children: [
            IconBadge(
              icon: icon,
              size: 48,
              iconSize: 24,
              backgroundColor: AppColors.accentOf(
                context,
              ).withValues(alpha: 0.12),
              iconColor: AppColors.accentOf(context),
              borderRadius: BorderRadius.circular(12),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.heading),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.black.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              LucideIcons.externalLink,
              size: 20,
              color: AppColors.accentOf(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataItem(String text, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '• ',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          Expanded(child: Text(text, style: AppText.bodyMuted)),
        ],
      ),
    );
  }
}
