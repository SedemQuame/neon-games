import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'app_shell.dart';
import 'section_header.dart';

class PlaceholderPanel extends StatelessWidget {
  const PlaceholderPanel({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SurfaceCard(
        padding: EdgeInsets.all(context.space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: context.colors.primary.withValues(alpha: 0.12),
              child: Icon(icon, size: 28, color: context.colors.primary),
            ),
            SizedBox(height: context.space.md),
            SectionHeader(title: title),
            SizedBox(height: context.space.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: context.type.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            if (trailing != null) ...[
              SizedBox(height: context.space.md),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
