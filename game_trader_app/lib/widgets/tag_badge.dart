import 'package:flutter/material.dart';

import '../app_theme.dart';

class TagBadge extends StatelessWidget {
  const TagBadge({
    super.key,
    required this.label,
    this.backgroundColor,
    this.foregroundColor,
  });

  final String label;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final useDefaultGold = backgroundColor == null && foregroundColor == null;
    final bg = backgroundColor ?? AppTheme.gameSurface;
    final fg = foregroundColor ?? AppTheme.primaryColor;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.space.sm,
        vertical: context.space.xxs,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(context.radii.pill),
        border: Border.all(
          color: useDefaultGold
              ? AppTheme.primaryColor.withValues(alpha: 0.42)
              : fg.withValues(alpha: 0.24),
        ),
      ),
      child: Text(
        label,
        style: context.type.label.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}
