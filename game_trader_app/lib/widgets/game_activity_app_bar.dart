import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'wallet_balance_chip.dart';

class GameActivityAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const GameActivityAppBar({super.key, required this.title, this.actions});

  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new,
          color: AppTheme.navForeground,
          size: 20,
        ),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        title,
        style: const TextStyle(
          color: AppTheme.navForeground,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      actions:
          actions ??
          const [
            WalletBalanceChip(
              margin: EdgeInsets.only(right: 12, top: 8, bottom: 8),
            ),
          ],
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          color: AppTheme.navBackground,
          border: Border(bottom: BorderSide(color: AppTheme.gameBorder)),
        ),
      ),
    );
  }
}
