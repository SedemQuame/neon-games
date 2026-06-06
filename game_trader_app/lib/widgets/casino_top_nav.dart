import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import 'wallet_nav_display.dart';

class CasinoTopNav extends StatelessWidget implements PreferredSizeWidget {
  const CasinoTopNav({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.centerTitle = false,
    this.onBack,
    this.showBackButton = false,
    this.showWallets = true,
  });

  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final bool centerTitle;
  final VoidCallback? onBack;
  final bool showBackButton;
  final bool showWallets;

  Future<void> _openExternal(String url) async {
    try {
      if (!await launchUrl(Uri.parse(url))) {
        debugPrint('Could not launch $url');
      }
    } catch (e) {
      debugPrint('Error launching url: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: 72,
      backgroundColor: AppTheme.navBackground,
      foregroundColor: AppTheme.navForeground,
      titleSpacing: context.space.md,
      title: title == null
          ? null
          : Text(
              title!,
              style: const TextStyle(
                color: AppTheme.navForeground,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
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
      actions: [
        if (showWallets) const WalletNavDisplay(),
        ...?actions,
      ],
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
  Size get preferredSize => const Size.fromHeight(72);
}
