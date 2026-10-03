import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../environment.dart';
import '../models/itinerary.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../utils/itinerary_text.dart';
import '../utils/trip_link.dart';
import 'bottom_overlay_card.dart';
import 'pressable_highlight.dart';

/// How long the sheet takes to fade in and out.
const Duration _kShareSheetFadeDuration = Duration(milliseconds: 180);

/// Hands [text] to the system share sheet. A parameter so tests can see what
/// would have been shared.
typedef ShareText = Future<void> Function(String text, {String? subject});

Future<void> _shareWithSystem(String text, {String? subject}) =>
    SharePlus.instance.share(ShareParams(text: text, subject: subject));

/// Asks how to share [itinerary], then shares it that way.
void showShareTripSheet(
  BuildContext context, {
  required Itinerary itinerary,
  String? fromName,
  String? toName,
  ShareText share = _shareWithSystem,
}) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Share this trip',
    barrierColor: const Color(0x00000000),
    transitionDuration: _kShareSheetFadeDuration,
    pageBuilder: (context, _, _) => ShareTripSheet(
      itinerary: itinerary,
      fromName: fromName,
      toName: toName,
      share: share,
      onDismiss: () => Navigator.of(context, rootNavigator: true).pop(),
    ),
    transitionBuilder: (context, animation, _, child) =>
        FadeTransition(opacity: animation, child: child),
  );
}

/// Three ways to share a trip, one at a time: they suit different people,
/// and a message holding all three is mostly a two-kilobyte link.
class ShareTripSheet extends StatelessWidget {
  const ShareTripSheet({
    super.key,
    required this.itinerary,
    required this.onDismiss,
    required this.share,
    this.fromName,
    this.toName,
  });

  final Itinerary itinerary;
  final String? fromName;
  final String? toName;
  final VoidCallback onDismiss;
  final ShareText share;

  /// The link for this trip, or null when the planner gave it no id — a trip
  /// saved before the app kept ids, or one rebuilt from its legs.
  TripLink? get _link {
    final id = itinerary.id;
    if (id == null || id.isEmpty) return null;
    return TripLink(itineraryId: id, host: Environment.transitousHost);
  }

  String get _subject {
    final text = itineraryAsText(itinerary, fromName: fromName, toName: toName);
    return text.substring(0, text.indexOf('\n'));
  }

  void _send(String text) {
    onDismiss();
    share(text, subject: _subject);
  }

  @override
  Widget build(BuildContext context) {
    final link = _link;
    const unavailable = 'Not available for this trip';
    return BottomOverlayCard(
      title: 'Share this trip',
      onDismiss: onDismiss,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ShareOption(
            icon: LucideIcons.smartphone,
            title: 'App link',
            subtitle: link == null
                ? unavailable
                : 'Opens in Transportia or another MOTIS app',
            onTap: link == null ? null : () => _send(link.appLink.toString()),
          ),
          _ShareOption(
            icon: LucideIcons.globe,
            title: 'Web link',
            subtitle: link == null
                ? unavailable
                : 'Opens in a browser, on ${link.host}',
            onTap: link == null ? null : () => _send(link.webLink.toString()),
          ),
          _ShareOption(
            icon: LucideIcons.listOrdered,
            title: 'Text',
            subtitle: 'The trip written out, step by step',
            onTap: () => _send(
              itineraryAsText(itinerary, fromName: fromName, toName: toName),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  const _ShareOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  /// Null when this way of sharing does not work for the trip.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final row = Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.accentWash(accent),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppText.bodyStrong),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppText.bodyMuted),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      button: true,
      enabled: onTap != null,
      // Inside the highlight even when it cannot be tapped, so every row
      // takes the same padding and they line up.
      child: IgnorePointer(
        ignoring: onTap == null,
        child: PressableHighlight(
          onPressed: onTap ?? () {},
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          child: row,
        ),
      ),
    );
  }
}
