import 'package:flutter/material.dart';

import '../app_theme.dart';

class CasinoTopNav extends StatelessWidget implements PreferredSizeWidget {
  const CasinoTopNav({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.centerTitle = false,
    this.onBack,
    this.showBackButton = false,
  });

  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final VoidCallback? onBack;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppTheme.navBackground,
      foregroundColor: AppTheme.navForeground,
      titleSpacing: context.space.md,
      title: title == null
          ? null
          : Text(
              title!,
              style: const TextStyle(
                color: AppTheme.navForeground,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
      centerTitle: centerTitle,
      leading:
          leading ??
          (showBackButton
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 18),
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                )
              : null),
      actions: actions,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          color: AppTheme.navBackground,
          border: Border(bottom: BorderSide(color: AppTheme.gameBorder)),
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
