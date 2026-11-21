import 'package:flutter/cupertino.dart';

import '../theme/app_colors.dart';

/// Side of the square holding a dialog's leading icon.
const double _kDialogIconBoxSize = 48.0;

/// The dimmed screen behind an overlay dialog.
const Color _kDialogBarrierColor = Color(0x80000000);

/// A card centred over a dimmed screen, dismissed by tapping outside it.
///
/// Used by the editing overlays, which are pushed as routes of their own
/// rather than shown by a dialog helper, so they draw their own barrier.
class OverlayDialogCard extends StatelessWidget {
  const OverlayDialogCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        color: _kDialogBarrierColor,
        child: Center(
          child: GestureDetector(
            // Swallows taps on the card so they do not dismiss it.
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x40000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The accented icon and title an overlay dialog opens with.
class OverlayDialogHeader extends StatelessWidget {
  const OverlayDialogHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final accent = AppColors.accentOf(context);
    final subtitle = this.subtitle;

    return Row(
      children: [
        Container(
          width: _kDialogIconBoxSize,
          height: _kDialogIconBoxSize,
          decoration: BoxDecoration(
            color: AppColors.accentWash(accent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 24, color: accent),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.black,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.black.withValues(alpha: 0.5),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A heading over one of a dialog's inputs.
class OverlayFieldLabel extends StatelessWidget {
  const OverlayFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: AppColors.black,
    ),
  );
}

/// The text input an overlay dialog edits a name through.
class OverlayTextField extends StatelessWidget {
  const OverlayTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String placeholder;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return CupertinoTextField(
      controller: controller,
      placeholder: placeholder,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.hairline),
      ),
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: AppColors.black,
      ),
      onSubmitted: onSubmitted,
    );
  }
}

/// The Cancel / Save pair an overlay dialog is confirmed through.
class OverlayDialogActions extends StatelessWidget {
  const OverlayDialogActions({
    super.key,
    required this.onCancel,
    required this.onConfirm,
    this.confirmLabel = 'Save',
    this.cancelLabel = 'Cancel',
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final String confirmLabel;
  final String cancelLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _OverlayDialogButton(
            label: cancelLabel,
            onTap: onCancel,
            background: AppColors.black.withValues(alpha: 0.03),
            border: AppColors.hairline,
            labelColor: AppColors.black,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _OverlayDialogButton(
            label: confirmLabel,
            onTap: onConfirm,
            background: AppColors.accentOf(context),
            labelColor: AppColors.solidWhite,
          ),
        ),
      ],
    );
  }
}

class _OverlayDialogButton extends StatelessWidget {
  const _OverlayDialogButton({
    required this.label,
    required this.onTap,
    required this.background,
    required this.labelColor,
    this.border,
  });

  final String label;
  final VoidCallback onTap;
  final Color background;
  final Color labelColor;
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
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: labelColor,
          ),
        ),
      ),
    );
  }
}
