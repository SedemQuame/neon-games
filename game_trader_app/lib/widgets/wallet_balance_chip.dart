import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/session_manager.dart';
import '../utils/format.dart';

class WalletBalanceChip extends StatelessWidget {
  const WalletBalanceChip({
    super.key,
    this.margin,
    this.backgroundColor,
    this.borderColor,
    this.iconColor = const Color(0xFF94a3b8),
    this.textColor = Colors.white,
  });

  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color iconColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: borderColor ?? AppTheme.borderDark),
      ),
      child: Consumer<SessionManager>(
        builder: (context, session, _) {
          final balance = session.cachedBalance?.availableUsd;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.account_balance_wallet,
                size: 14,
                color: iconColor,
              ),
              const SizedBox(width: 8),
              Text(
                formatCurrency(balance),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: textColor,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
