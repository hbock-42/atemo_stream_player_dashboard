/// Buttons, with an explicit disabled state.
///
/// Disabled is load-bearing rather than decorative here: capability gating
/// means transport controls are routinely unavailable, and a control that
/// looks pressable but does nothing is worse than one that looks off.
library;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'app_icon.dart';
import 'app_text.dart';

class AppIconButton extends StatefulWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 28,
    this.emphasised = false,
    this.semanticLabel,
  });

  final AppIconData icon;

  /// Null means disabled.
  final VoidCallback? onPressed;
  final double size;

  /// The primary action, rendered as a filled circle.
  final bool emphasised;
  final String? semanticLabel;

  @override
  State<AppIconButton> createState() => _AppIconButtonState();
}

class _AppIconButtonState extends State<AppIconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.of(context).colors;
    final enabled = widget.onPressed != null;
    // 44pt minimum: used one-handed, across a room, in a hurry.
    final diameter = (widget.size * 2).clamp(44.0, 96.0).toDouble();

    final foreground = !enabled
        ? colors.textDisabled
        : widget.emphasised
            ? colors.background
            : colors.textPrimary;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedOpacity(
          opacity: _pressed ? 0.55 : 1.0,
          duration: const Duration(milliseconds: 90),
          child: Container(
            width: diameter,
            height: diameter,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.emphasised
                  ? (enabled ? colors.accent : colors.surfaceRaised)
                  : null,
            ),
            child: AppIcon(widget.icon, size: widget.size, color: foreground),
          ),
        ),
      ),
    );
  }
}

class AppTextButton extends StatefulWidget {
  const AppTextButton({super.key, required this.label, required this.onPressed, this.icon});

  final String label;
  final VoidCallback? onPressed;
  final AppIconData? icon;

  @override
  State<AppTextButton> createState() => _AppTextButtonState();
}

class _AppTextButtonState extends State<AppTextButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final enabled = widget.onPressed != null;
    final foreground = enabled ? theme.colors.textPrimary : theme.colors.textDisabled;

    return Semantics(
      button: true,
      enabled: enabled,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: _pressed ? theme.colors.surfaceRaised : theme.colors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: theme.colors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                AppIcon(widget.icon!, size: 17, color: foreground),
                const SizedBox(width: AppSpacing.sm),
              ],
              AppText(widget.label, style: AppTextStyleName.body, color: foreground),
            ],
          ),
        ),
      ),
    );
  }
}
