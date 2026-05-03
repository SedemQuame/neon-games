import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';
import 'trades_screen.dart';
import 'wallet_screen.dart';

class SharedBottomNav extends StatelessWidget {
  const SharedBottomNav({super.key, required this.currentIndex});

  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.navBackground,
        border: Border(
          top: BorderSide(
            color: context.colors.primary.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.space.md,
            vertical: context.space.xs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _NavItem(
                icon: Icons.sports_esports,
                label: 'Games',
                isActive: currentIndex == 0,
                onTap: () => _navigateTo(
                  context,
                  const DashboardScreen(),
                  destinationIndex: 0,
                ),
              ),
              _NavItem(
                icon: Icons.auto_graph,
                label: 'Activity',
                isActive: currentIndex == 1,
                onTap: () => _navigateTo(
                  context,
                  const TradesScreen(),
                  destinationIndex: 1,
                ),
              ),
              _NavItem(
                icon: Icons.account_balance_wallet,
                label: 'Wallet',
                isActive: currentIndex == 2,
                onTap: () => _navigateTo(
                  context,
                  const WalletScreen(),
                  destinationIndex: 2,
                ),
              ),
              _NavItem(
                icon: Icons.person,
                label: 'Profile',
                isActive: currentIndex == 3,
                onTap: () => _navigateTo(
                  context,
                  const SettingsScreen(
                    showBackButton: false,
                    isProfileTab: true,
                  ),
                  destinationIndex: 3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateTo(
    BuildContext context,
    Widget page, {
    required int destinationIndex,
  }) {
    if (destinationIndex == currentIndex) {
      return;
    }
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return InkWell(
      borderRadius: BorderRadius.circular(context.radii.pill),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: isActive ? context.space.md : context.space.sm,
          vertical: context.space.xs,
        ),
        decoration: BoxDecoration(
          color: isActive
              ? colors.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(context.radii.pill),
          border: Border.all(
            color: isActive
                ? colors.primary.withValues(alpha: 0.28)
                : Colors.transparent,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isActive ? colors.primary : colors.textSecondary,
            ),
            SizedBox(height: context.space.xxs),
            Text(
              label,
              style: context.type.navLabel.copyWith(
                color: isActive ? colors.primary : colors.textSecondary,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
