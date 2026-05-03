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
    this.iconColor,
    this.textColor,
  });

  final EdgeInsetsGeometry? margin;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? iconColor;
  final Color? textColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final useDefaultGold =
        backgroundColor == null &&
        borderColor == null &&
        iconColor == null &&
        textColor == null;

    return Container(
      margin: margin ?? EdgeInsets.only(right: context.space.md),
      padding: EdgeInsets.symmetric(
        horizontal: context.space.md,
        vertical: context.space.xs,
      ),
      decoration: BoxDecoration(
        color: useDefaultGold
            ? AppTheme.primaryColor
            : (backgroundColor ?? colors.bgCard),
        borderRadius: BorderRadius.circular(context.radii.pill),
        border: Border.all(
          color:
              borderColor ??
              (useDefaultGold ? AppTheme.goldButtonBottom : colors.border),
        ),
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
                color:
                    iconColor ??
                    (useDefaultGold ? AppTheme.goldText : colors.textSecondary),
              ),
              SizedBox(width: context.space.xs),
              Text(
                formatCurrency(balance),
                style: context.type.label.copyWith(
                  fontWeight: FontWeight.w700,
                  color:
                      textColor ??
                      (useDefaultGold ? AppTheme.goldText : colors.textPrimary),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
