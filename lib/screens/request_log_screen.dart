import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../api/transitous_endpoint.dart';
import '../models/motis_request_record.dart';
import '../providers/theme_provider.dart';
import '../api/motis_request_log.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../utils/custom_page_route.dart';
import '../utils/motis_request_summary.dart';
import '../widgets/custom_app_bar.dart';
import '../widgets/empty_state.dart';
import '../widgets/pressable_highlight.dart';

/// Raw request text: URLs, parameters and bodies are read character by
/// character, so they are set in a fixed-width face.
TextStyle _mono({double size = 12, Color? color}) => TextStyle(
  fontSize: size,
  fontFamily: 'monospace',
  height: 1.35,
  color: color ?? AppColors.black.withValues(alpha: 0.75),
);

String _clock(DateTime time) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
}

String _took(Duration duration) => duration.inMilliseconds < 1000
    ? '${duration.inMilliseconds} ms'
    : '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s';

/// The MOTIS requests the app sent while logging was on, newest first.
class RequestLogScreen extends StatefulWidget {
  const RequestLogScreen({super.key});

  @override
  State<RequestLogScreen> createState() => _RequestLogScreenState();
}

class _RequestLogScreenState extends State<RequestLogScreen> {
  /// Null shows every endpoint.
  TransitousEndpoint? _filter;

  @override
  Widget build(BuildContext context) {
    final logging = context.select<ThemeProvider, bool>(
      (theme) => theme.logMotisRequests,
    );
    return ValueListenableBuilder<List<MotisRequestRecord>>(
      valueListenable: MotisRequestLog.records,
      builder: (context, records, _) {
        // A filter for an endpoint that has since been cleared out would
        // show an empty list with no chip left to undo it.
        final filter = records.any((r) => r.endpoint == _filter)
            ? _filter
            : null;
        final shown = filter == null
            ? records
            : records.where((r) => r.endpoint == filter).toList();
        return ColoredBox(
          color: AppColors.white,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CustomAppBar(
                  title: 'Request Log',
                  trailing: records.isEmpty ? null : _clearButton(),
                ),
                if (!logging) const _LoggingOffNotice(),
                if (records.isNotEmpty)
                  _EndpointFilter(
                    records: records,
                    selected: filter,
                    onSelected: (endpoint) =>
                        setState(() => _filter = endpoint),
                  ),
                Expanded(
                  child: records.isEmpty
                      ? _empty(logging)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: shown.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) => _RequestCard(
                            record: shown[i],
                            onPressed: () => Navigator.of(context).push(
                              CustomPageRoute(
                                child: RequestDetailScreen(record: shown[i]),
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _clearButton() {
    final accent = AppColors.accentOf(context);
    return PressableHighlight(
      onPressed: MotisRequestLog.clear,
      enableHaptics: false,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.trash2, size: 18, color: accent),
            const SizedBox(width: 4),
            Text(
              'Clear',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(bool logging) {
    return Center(
      child: EmptyState(
        padding: const EdgeInsets.all(32),
        icon: Icon(
          LucideIcons.scrollText,
          size: 40,
          color: AppColors.black.withValues(alpha: 0.25),
        ),
        title: 'No requests logged',
        subtitle: logging
            ? 'Requests appear here as the app makes them'
            : 'Turn on "Log MOTIS requests" to record them',
      ),
    );
  }
}

/// Said once at the top rather than by an empty list: what is here stays
/// readable, but nothing new is being added.
class _LoggingOffNotice extends StatelessWidget {
  const _LoggingOffNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.alertBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.alertBorder),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.circleAlert, size: 18, color: AppColors.alertIcon),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Logging is off. New requests are not recorded.',
              style: TextStyle(fontSize: 13, color: AppColors.black),
            ),
          ),
        ],
      ),
    );
  }
}

/// One chip per endpoint in the log, with how many requests it has.
class _EndpointFilter extends StatelessWidget {
  const _EndpointFilter({
    required this.records,
    required this.selected,
    required this.onSelected,
  });

  final List<MotisRequestRecord> records;
  final TransitousEndpoint? selected;
  final ValueChanged<TransitousEndpoint?> onSelected;

  @override
  Widget build(BuildContext context) {
    final counts = <TransitousEndpoint, int>{};
    for (final record in records) {
      counts.update(record.endpoint, (n) => n + 1, ifAbsent: () => 1);
    }
    final endpoints = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          _FilterChip(
            label: 'All',
            count: records.length,
            selected: selected == null,
            onPressed: () => onSelected(null),
          ),
          for (final endpoint in endpoints) ...[
            const SizedBox(width: 8),
            _FilterChip(
              label: endpoint.label,
              count: counts[endpoint]!,
              selected: selected == endpoint,
              onPressed: () => onSelected(endpoint),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final color = selected ? accent : AppColors.black.withValues(alpha: 0.7);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accentWash(accent) : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? accent : AppColors.hairline),
        ),
        child: Text(
          '$label  $count',
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.record, required this.onPressed});

  final MotisRequestRecord record;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final summary = motisRequestSummary(record.endpoint, record.uri);
    final meta = [
      _clock(record.sentAt),
      if (record.duration case final took?) _took(took),
      record.uri.path,
    ].join(' · ');
    // Not PressableHighlight: its own padding would inset the card from the
    // filter row above it.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: record.isFailure
                ? AppColors.cancelled.withValues(alpha: 0.5)
                : AppColors.hairline,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _MethodTag(method: record.method),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(record.endpoint.label, style: AppText.bodyStrong),
                ),
                _StatusTag(record: record),
              ],
            ),
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _mono(),
              ),
            ],
            const SizedBox(height: 6),
            Text(meta, style: AppText.caption),
          ],
        ),
      ),
    );
  }
}

class _MethodTag extends StatelessWidget {
  const _MethodTag({required this.method});

  final String method;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        method,
        style: _mono(size: 11, color: AppColors.black.withValues(alpha: 0.6)),
      ),
    );
  }
}

class _StatusTag extends StatelessWidget {
  const _StatusTag({required this.record});

  final MotisRequestRecord record;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (record) {
      MotisRequestRecord(isPending: true) => (
        'Pending',
        AppColors.black.withValues(alpha: 0.45),
      ),
      MotisRequestRecord(isFailure: true, statusCode: final code?) => (
        '$code',
        AppColors.cancelled,
      ),
      MotisRequestRecord(isFailure: true) => ('Failed', AppColors.cancelled),
      MotisRequestRecord(statusCode: final code) => (
        '${code ?? ''}',
        AppColors.accentOf(context),
      ),
    };
    return Text(
      label,
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
    );
  }
}

/// Everything about one request, with a button that copies it whole.
class RequestDetailScreen extends StatefulWidget {
  const RequestDetailScreen({super.key, required this.record});

  final MotisRequestRecord record;

  @override
  State<RequestDetailScreen> createState() => _RequestDetailScreenState();
}

class _RequestDetailScreenState extends State<RequestDetailScreen> {
  static const Duration _copiedFor = Duration(seconds: 2);

  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.record.copyText));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(_copiedFor);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final record = widget.record;
    final params = record.uri.queryParameters;
    final body = record.prettyBody;
    final error = record.error;
    return ColoredBox(
      color: AppColors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CustomAppBar(title: 'Request'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  _header(record),
                  const SizedBox(height: 16),
                  _copyButton(),
                  if (error != null)
                    _Section(
                      title: 'Error',
                      child: Text(
                        error,
                        style: _mono(color: AppColors.cancelled),
                      ),
                    ),
                  _Section(
                    title: 'URL',
                    child: Text(record.uri.toString(), style: _mono()),
                  ),
                  if (params.isNotEmpty)
                    _Section(title: 'Parameters', child: _KeyValues(params)),
                  if (record.headers.isNotEmpty)
                    _Section(
                      title: 'Headers',
                      child: _KeyValues(record.headers),
                    ),
                  if (body != null)
                    _Section(
                      title: 'Body',
                      child: Text(body, style: _mono()),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(MotisRequestRecord record) {
    final meta = [
      _clock(record.sentAt),
      if (record.duration case final took?) _took(took),
      record.uri.host,
    ].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _MethodTag(method: record.method),
            const SizedBox(width: 8),
            Expanded(
              child: Text(record.endpoint.label, style: AppText.heading),
            ),
            _StatusTag(record: record),
          ],
        ),
        const SizedBox(height: 4),
        Text(meta, style: AppText.bodyFaint),
      ],
    );
  }

  Widget _copyButton() {
    final accent = AppColors.accentOf(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _copy,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _copied ? LucideIcons.check : LucideIcons.copy,
              size: 18,
              color: AppColors.solidWhite,
            ),
            const SizedBox(width: 8),
            Text(
              _copied ? 'Copied' : 'Copy request',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.solidWhite,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppText.listTitle),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.hairline),
            ),
            child: child,
          ),
        ],
      ),
    );
  }
}

class _KeyValues extends StatelessWidget {
  const _KeyValues(this.values);

  final Map<String, String> values;

  @override
  Widget build(BuildContext context) {
    final entries = values.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < entries.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${entries[i].key}  ',
                    style: _mono(
                      color: AppColors.black,
                    ).copyWith(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: entries[i].value, style: _mono()),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
