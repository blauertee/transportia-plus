import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/place_details.dart';
import '../../models/stop_time.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text.dart';
import '../../utils/color_utils.dart';
import '../../utils/time_utils.dart';
import '../route_badge_pill.dart';
import '../skeletons/skeleton_shimmer.dart';

/// What the rider tapped on the map, and the button that takes it.
///
/// One sheet for three things tapped: a place, which OpenStreetMap may know
/// more about; a stop, which has departures; and a bare point. Each is its
/// own constructor, since each says different things below the header.
class PlaceDetailsSheet extends StatelessWidget {
  /// A place the search found. [details] are what OpenStreetMap knows,
  /// null while [isLoading] or when it knows nothing or was not asked.
  PlaceDetailsSheet.place({
    super.key,
    required this.icon,
    required this.title,
    required this.caption,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    String? category,
    PlaceDetails? details,
    bool isLoading = false,
  }) : chip = category,
       isTitleLoading = false,
       body = [
         if (isLoading) const _LoadingRows(),
         if (!isLoading && details != null) ..._facts(details),
       ],
       footnote = !isLoading && details != null ? const _OsmCredit() : null;

  /// A stop the search found, with its next departures: null while
  /// [isLoading], empty when none are due or they could not be had.
  PlaceDetailsSheet.stop({
    super.key,
    required this.icon,
    required this.title,
    required this.caption,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    String? modes,
    List<StopTime>? departures,
    bool isLoading = false,
  }) : chip = modes,
       isTitleLoading = false,
       footnote = null,
       body = [
         if (isLoading) const _LoadingRows(),
         if (!isLoading && departures != null && departures.isNotEmpty) ...[
           const _Heading('Next departures'),
           for (final d in departures) _DepartureRow(d),
         ],
       ];

  /// A point tapped on the map, named by the nearest address once
  /// [isLoading] is over.
  const PlaceDetailsSheet.point({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onCancel,
    this.caption,
    bool isLoading = false,
  }) : icon = LucideIcons.mapPin,
       chip = 'Point on the map',
       isTitleLoading = isLoading,
       body = const [],
       footnote = null;

  final IconData icon;
  final String title;
  final String? caption;
  final String? chip;
  final bool isTitleLoading;
  final List<Widget> body;
  final Widget? footnote;
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  static List<Widget> _facts(PlaceDetails d) => [
    if (d.street != null || d.locality != null)
      _Fact(
        LucideIcons.mapPin,
        [d.street, d.locality].whereType<String>().join(', '),
      ),
    if (d.openingHours case final hours?)
      _Fact(LucideIcons.clock, hours.replaceAll('-', '–')),
    if (d.phone case final phone?)
      _Fact(
        LucideIcons.phone,
        phone,
        onTap: () => _open(Uri(scheme: 'tel', path: phone)),
      ),
    if (d.website case final website?)
      _Fact(
        LucideIcons.globe,
        _displayHost(website),
        onTap: () => _open(_webUri(website)),
      ),
    if (_wheelchairText(d.wheelchair) case final text?)
      _Fact(LucideIcons.accessibility, text),
    if (_levelText(d.level) case final text?) _Fact(LucideIcons.layers, text),
  ];

  static String? _wheelchairText(String? value) => switch (value) {
    'yes' => 'Wheelchair accessible',
    'limited' => 'Partly wheelchair accessible',
    'no' => 'Not wheelchair accessible',
    _ => null,
  };

  static String? _levelText(String? level) => switch (level) {
    null => null,
    '0' => 'Ground floor',
    final l => 'Floor $l',
  };

  /// Mappers write sites with and without a scheme; both must open.
  static Uri _webUri(String site) =>
      Uri.parse(site.contains('://') ? site : 'https://$site');

  /// "rewe.de", not the whole address of one market's page.
  static String _displayHost(String site) {
    final host = _webUri(site).host;
    return host.startsWith('www.') ? host.substring(4) : host;
  }

  static Future<void> _open(Uri uri) async {
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 24,
            offset: Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            icon: icon,
            title: title,
            caption: caption,
            isTitleLoading: isTitleLoading,
          ),
          if (chip case final text?) ...[
            const SizedBox(height: 12),
            Align(alignment: Alignment.centerLeft, child: _Chip(text)),
          ],
          if (body.isNotEmpty) ...[
            const SizedBox(height: 8),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: body,
                ),
              ),
            ),
          ],
          if (footnote case final note?) ...[const SizedBox(height: 8), note],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SheetButton(
                  label: 'Cancel',
                  onTap: onCancel,
                  background: AppColors.black.withValues(alpha: 0.03),
                  foreground: AppColors.black,
                  border: AppColors.hairline,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SheetButton(
                  label: confirmLabel,
                  onTap: isTitleLoading ? null : onConfirm,
                  background: isTitleLoading ? AppColors.hairline : accent,
                  foreground: AppColors.solidWhite,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.icon,
    required this.title,
    required this.caption,
    required this.isTitleLoading,
  });

  final IconData icon;
  final String title;
  final String? caption;
  final bool isTitleLoading;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 24, color: accent),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              isTitleLoading
                  ? const _ShimmerBar(width: double.infinity)
                  : Text(
                      title,
                      style: AppText.heading,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
              if (caption case final text? when text.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.black.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: AppColors.black.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.7,
          color: AppColors.black.withValues(alpha: 0.45),
        ),
      ),
    );
  }
}

/// One thing OpenStreetMap knows, with an icon saying what kind of thing.
class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text, {this.onTap});

  final IconData icon;
  final String text;

  /// Set for what opens elsewhere: a number to call, a site to visit.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.black.withValues(alpha: 0.45)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14.5,
                color: onTap == null
                    ? AppColors.black
                    : AppColors.accentOf(context),
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      link: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

class _DepartureRow extends StatelessWidget {
  const _DepartureRow(this.stopTime);

  final StopTime stopTime;

  @override
  Widget build(BuildContext context) {
    final departs =
        stopTime.place.departure ?? stopTime.place.scheduledDeparture;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          RouteBadgePill(
            label: stopTime.displayName,
            background: parseHexColorOrAccent(context, stopTime.routeColor),
            foreground: parseHexColorOr(
              stopTime.routeTextColor,
              AppColors.solidWhite,
            ),
            minWidth: RouteBadgePill.stackedMinWidth,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              stopTime.headsign,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14.5, color: AppColors.black),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatTime(departs),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: stopTime.cancelled ? AppColors.cancelled : AppColors.black,
              decoration: stopTime.cancelled
                  ? TextDecoration.lineThrough
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// ODbL attribution: the data is OpenStreetMap's, and the licence one tap
/// away.
class _OsmCredit extends StatelessWidget {
  const _OsmCredit();

  static final Uri _copyright = Uri.parse(
    'https://www.openstreetmap.org/copyright',
  );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      link: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => PlaceDetailsSheet._open(_copyright),
        child: Text(
          'Details © OpenStreetMap contributors',
          style: AppText.bodyFaint.copyWith(
            fontSize: 11,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
  }
}

class _LoadingRows extends StatelessWidget {
  const _LoadingRows();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ShimmerBar(width: 220),
          SizedBox(height: 12),
          _ShimmerBar(width: 160),
          SizedBox(height: 12),
          _ShimmerBar(width: 190),
        ],
      ),
    );
  }
}

class _ShimmerBar extends StatelessWidget {
  const _ShimmerBar({required this.width});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SkeletonShimmer(
      baseColor: const Color(0xFFE2E7EC),
      highlightColor: const Color(0xFFF7F9FC),
      period: const Duration(milliseconds: 1100),
      child: Container(
        width: width,
        height: 16,
        decoration: BoxDecoration(
          color: const Color(0xFFE2E7EC),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.onTap,
    required this.background,
    required this.foreground,
    this.border,
  });

  final String label;
  final VoidCallback? onTap;
  final Color background;
  final Color foreground;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
          border: border == null ? null : Border.all(color: border!),
        ),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }
}
