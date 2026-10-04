import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../theme/app_text.dart';
import '../utils/app_icons.dart';
import '../utils/custom_page_route.dart';
import '../utils/icon_catalogue.dart';
import 'app_icon_view.dart';
import 'app_page_scaffold.dart';
import 'buttons/primary_button.dart';
import 'overlay_dialog.dart';

/// One icon to pick: a square tile, filled when it is the one picked.
class IconTile extends StatelessWidget {
  const IconTile({
    super.key,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.semanticLabel,
  }) : _isMore = false;

  /// The tile that opens the full picker: a magnifier in the accent.
  const IconTile.more({super.key, required this.onTap})
    : icon = const GlyphIcon(LucideIcons.search),
      selected = false,
      semanticLabel = 'More icons',
      _isMore = true;

  final AppIcon icon;
  final bool selected;
  final VoidCallback onTap;
  final String? semanticLabel;
  final bool _isMore;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent : AppColors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : AppColors.hairline,
              width: selected ? 2 : 1,
            ),
          ),
          child: AppIconView(
            icon,
            size: 22,
            color: selected
                ? AppColors.solidWhite
                : _isMore
                ? accent
                : AppColors.black.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}

/// The full, searchable icon picker.
///
/// Whoever opens it names it and its button, and offers its own suggestions
/// first: a favourite and a search-card section want different ones. It
/// returns the picked icon's name, or null when left without picking.
class IconPickerScreen extends StatefulWidget {
  const IconPickerScreen({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.selected,
    this.suggestions = const [],
  });

  final String title;
  final String confirmLabel;

  /// The name picked when the screen opens.
  final String selected;

  /// Names listed above the categories; may include the app's composed
  /// icons, which the catalogue does not.
  final List<String> suggestions;

  static Future<String?> open(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    required String selected,
    List<String> suggestions = const [],
  }) => Navigator.of(context).push<String>(
    CustomPageRoute(
      child: IconPickerScreen(
        title: title,
        confirmLabel: confirmLabel,
        selected: selected,
        suggestions: suggestions,
      ),
    ),
  );

  @override
  State<IconPickerScreen> createState() => _IconPickerScreenState();
}

class _IconPickerScreenState extends State<IconPickerScreen> {
  final TextEditingController _query = TextEditingController();
  late String _selected = AppIcons.canonical(widget.selected);

  /// Built once: the catalogue does not change while the screen is up.
  final Map<IconCategory, List<CatalogueIcon>> _byCategory = iconsByCategory();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Widget _grid(Iterable<String> names) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final name in names)
        IconTile(
          icon: AppIcons.resolve(name),
          selected: name == _selected,
          semanticLabel: name,
          onTap: () => setState(() => _selected = name),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim();
    final sections = <Widget>[
      if (query.isNotEmpty)
        ..._results(query)
      else ...[
        if (widget.suggestions.isNotEmpty) ...[
          const _Heading('Suggested'),
          _grid(widget.suggestions.map(AppIcons.canonical)),
        ],
        for (final MapEntry(key: category, value: icons) in _byCategory.entries)
          if (icons.isNotEmpty) ...[
            _Heading(category.label),
            _grid(icons.map((icon) => AppIcons.lucide(icon.name))),
          ],
      ],
    ];
    return AppPageScaffold(
      title: widget.title,
      footer: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: PrimaryButton(
          onTap: () => Navigator.of(context).pop(_selected),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              widget.confirmLabel,
              textAlign: TextAlign.center,
              style: AppText.bodyStrong.copyWith(color: AppColors.solidWhite),
            ),
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OverlayTextField(
              controller: _query,
              placeholder: 'Search icons',
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: sections,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _results(String query) {
    final found = searchIcons(query);
    if (found.isEmpty) return [_Heading('No icons match “$query”')];
    return [
      _Heading(
        '${found.length} ${found.length == 1 ? 'icon matches' : 'icons match'} '
        '“$query”',
      ),
      _grid(found.map((icon) => AppIcons.lucide(icon.name))),
    ];
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 18, 0, 10),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.7,
        color: AppColors.black.withValues(alpha: 0.5),
      ),
    ),
  );
}
