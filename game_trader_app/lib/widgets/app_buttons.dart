import 'package:flutter/material.dart';

import '../app_theme.dart';

class PrimaryButton extends StatefulWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  State<PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<PrimaryButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final radius = BorderRadius.circular(context.radii.lg);

    return AnimatedScale(
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      scale: _pressed && enabled ? 0.985 : 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: enabled ? AppTheme.primaryColor : AppTheme.goldDisabledBottom,
          borderRadius: radius,
          border: Border.all(
            color: enabled ? AppTheme.primaryColor : AppTheme.gameBorder,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onPressed,
            onHighlightChanged: (value) => setState(() => _pressed = value),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: 44,
                minWidth: widget.expanded ? double.infinity : 120,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.space.lg,
                  vertical: context.space.sm,
                ),
                child: widget.icon == null
                    ? Center(
                        child: Text(
                          widget.label,
                          style: context.type.bodyStrong.copyWith(
                            color: AppTheme.goldText.withValues(
                              alpha: enabled ? 1 : 0.65,
                            ),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      )
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.icon,
                            size: 18,
                            color: AppTheme.goldText.withValues(
                              alpha: enabled ? 1 : 0.65,
                            ),
                          ),
                          SizedBox(width: context.space.xs),
                          Flexible(
                            child: Text(
                              widget.label,
                              overflow: TextOverflow.ellipsis,
                              style: context.type.bodyStrong.copyWith(
                                color: AppTheme.goldText.withValues(
                                  alpha: enabled ? 1 : 0.65,
                                ),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SecondaryButton extends StatefulWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool expanded;

  @override
  State<SecondaryButton> createState() => _SecondaryButtonState();
}

class _SecondaryButtonState extends State<SecondaryButton> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || widget.onPressed == null) {
      return;
    }
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final button = widget.icon == null
        ? OutlinedButton(
            onPressed: widget.onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: Size(widget.expanded ? double.infinity : 0, 44),
              backgroundColor: context.colors.bgCard,
              foregroundColor: context.colors.textPrimary,
              side: BorderSide(color: context.colors.border),
              padding: EdgeInsets.symmetric(
                horizontal: context.space.lg,
                vertical: context.space.sm,
              ),
            ),
            child: Text(widget.label),
          )
        : OutlinedButton.icon(
            onPressed: widget.onPressed,
            icon: Icon(widget.icon, size: 18),
            label: Text(widget.label),
            style: OutlinedButton.styleFrom(
              minimumSize: Size(widget.expanded ? double.infinity : 0, 44),
              backgroundColor: context.colors.bgCard,
              foregroundColor: context.colors.textPrimary,
              side: BorderSide(color: context.colors.border),
              padding: EdgeInsets.symmetric(
                horizontal: context.space.lg,
                vertical: context.space.sm,
              ),
            ),
          );

    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        scale: _pressed ? 0.985 : 1,
        child: button,
      ),
    );
  }
}
