import 'package:flutter/cupertino.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme/app_colors.dart';
import '../utils/app_icons.dart';
import 'icon_picker.dart';
import 'overlay_dialog.dart';

/// A name and an icon to set together: a favourite's, a search-card
/// section's.
///
/// The caller decides what it is called, which icons come first, how the
/// full picker behind them is labelled, and whether the thing can be
/// removed from here at all.
class NameIconDialog extends StatefulWidget {
  const NameIconDialog({
    super.key,
    required this.title,
    required this.name,
    required this.iconName,
    required this.suggestions,
    required this.pickerTitle,
    required this.onSaved,
    this.namePlaceholder = 'Enter name',
    this.pickerConfirmLabel = 'Use icon',
    this.deleteLabel,
    this.onDeleted,
  }) : assert(
         (deleteLabel == null) == (onDeleted == null),
         'A removable thing needs both the label and the action.',
       );

  final String title;
  final String name;
  final String iconName;

  /// Offered as tiles; the full picker is one tap further.
  final List<String> suggestions;

  final String pickerTitle;
  final String pickerConfirmLabel;
  final String namePlaceholder;

  /// Given the trimmed name and the picked icon's name, already in the form
  /// it is saved in.
  final void Function(String name, String iconName) onSaved;

  /// Both null for something that cannot be removed.
  final String? deleteLabel;
  final VoidCallback? onDeleted;

  @override
  State<NameIconDialog> createState() => _NameIconDialogState();
}

class _NameIconDialogState extends State<NameIconDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late String _icon = AppIcons.canonical(widget.iconName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The suggestions, with the current icon first when it is not one of
  /// them, so what is picked is always on show.
  List<String> get _tiles {
    final suggested = [
      for (final name in widget.suggestions) AppIcons.canonical(name),
    ];
    return suggested.contains(_icon) ? suggested : [_icon, ...suggested];
  }

  Future<void> _openPicker() async {
    final picked = await IconPickerScreen.open(
      context,
      title: widget.pickerTitle,
      confirmLabel: widget.pickerConfirmLabel,
      selected: _icon,
      suggestions: widget.suggestions,
    );
    if (picked != null && mounted) setState(() => _icon = picked);
  }

  void _save() {
    widget.onSaved(_name.text.trim(), _icon);
    Navigator.of(context).pop();
  }

  void _delete() {
    widget.onDeleted!();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayDialogCard(
      children: [
        OverlayDialogHeader(icon: LucideIcons.pen, title: widget.title),
        const SizedBox(height: 24),
        const OverlayFieldLabel('Name'),
        const SizedBox(height: 8),
        OverlayTextField(
          controller: _name,
          placeholder: widget.namePlaceholder,
        ),
        const SizedBox(height: 24),
        const OverlayFieldLabel('Icon'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final name in _tiles)
              IconTile(
                icon: AppIcons.resolve(name),
                selected: name == _icon,
                semanticLabel: name,
                onTap: () => setState(() => _icon = name),
              ),
            IconTile.more(onTap: _openPicker),
          ],
        ),
        const SizedBox(height: 24),
        if (widget.deleteLabel case final label?) ...[
          GestureDetector(
            onTap: _delete,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.disrupted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        OverlayDialogActions(
          onCancel: () => Navigator.of(context).pop(),
          onConfirm: _save,
        ),
      ],
    );
  }
}
