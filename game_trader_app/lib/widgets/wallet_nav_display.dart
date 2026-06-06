import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/session_manager.dart';
import '../utils/format.dart';
import '../screens/deposit_screen.dart';

class WalletNavDisplay extends StatelessWidget {
  const WalletNavDisplay({super.key});

  void _showDemoRefillDialog(BuildContext context, SessionManager session) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.colors.bgCard,
        title: const Text('Refill Demo Wallet'),
        content: const Text(
          'Your demo wallet allows you to practice games without risking real money.\n\n'
          'Would you like to reset your demo balance to \$1,000.00?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: context.colors.onPrimary,
            ),
            onPressed: () {
              session.refillDemoWallet(1000.0);
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Demo wallet refilled to \$1,000.00')),
              );
            },
            child: const Text('Refill \$1,000'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionManager>();
    final demoBalance = session.demoBalance;
    final realBalance = session.cachedBalance?.availableUsd ?? 0.0;
    final isAuthenticated = session.isAuthenticated;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Demo Wallet Pill
        InkWell(
          onTap: () => _showDemoRefillDialog(context, session),
          borderRadius: BorderRadius.circular(context.radii.pill),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: context.space.sm,
              vertical: context.space.xs,
            ),
            decoration: BoxDecoration(
              color: AppTheme.backgroundDark.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(context.radii.pill),
              border: Border.all(color: AppTheme.gameBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.science_outlined,
                  size: 14,
                  color: AppTheme.textSecondary,
                ),
                SizedBox(width: context.space.xs),
                Text(
                  'Demo: ${formatCurrency(demoBalance)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        if (isAuthenticated) ...[
          SizedBox(width: context.space.sm),
          // Real Wallet Pill
          InkWell(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DepositScreen()),
              );
            },
            borderRadius: BorderRadius.circular(context.radii.pill),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: context.space.sm,
                vertical: context.space.xs,
              ),
              decoration: BoxDecoration(
                color: context.colors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(context.radii.pill),
                border: Border.all(
                  color: context.colors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    size: 14,
                    color: context.colors.primary,
                  ),
                  SizedBox(width: context.space.xs),
                  Text(
                    'Real: ${formatCurrency(realBalance)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: context.colors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        SizedBox(width: context.space.md),
      ],
    );
  }
}
