import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'dashboard_screen.dart';
import 'trades_screen.dart';
import 'wallet_screen.dart';
import 'ranking_screen.dart';
import 'profile_screen.dart';

class SharedBottomNav extends StatelessWidget {
  final int currentIndex;

  const SharedBottomNav({super.key, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.sizeOf(context).width >= 1024;
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: isDesktop ? 8 : 12,
        horizontal: isDesktop ? 16 : 24,
      ),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isDesktop ? 980 : double.infinity,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () {
                    if (currentIndex != 0) {
                      Navigator.of(context).pushReplacement(
                        PageRouteBuilder(
                          pageBuilder: (context, animation1, animation2) =>
                              const DashboardScreen(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      );
                    }
                  },
                  child: _buildNavItem(
                    icon: Icons.sports_esports,
                    label: 'Games',
                    isActive: currentIndex == 0,
                    isDesktop: isDesktop,
                  ),
                ),

                GestureDetector(
                  onTap: () {
                    if (currentIndex != 1) {
                      Navigator.of(context).pushReplacement(
                        PageRouteBuilder(
                          pageBuilder: (context, animation1, animation2) =>
                              const TradesScreen(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      );
                    }
                  },
                  child: _buildNavItem(
                    icon: Icons.auto_graph,
                    label: 'Activity',
                    isActive: currentIndex == 1,
                    isDesktop: isDesktop,
                  ),
                ),

                GestureDetector(
                  onTap: () {
                    if (currentIndex != 2) {
                      Navigator.of(context).pushReplacement(
                        PageRouteBuilder(
                          pageBuilder: (context, animation1, animation2) =>
                              const WalletScreen(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      );
                    }
                  },
                  child: _buildWalletNavItem(
                    isActive: currentIndex == 2,
                    isDesktop: isDesktop,
                  ),
                ),

                GestureDetector(
                  onTap: () {
                    if (currentIndex != 3) {
                      Navigator.of(context).pushReplacement(
                        PageRouteBuilder(
                          pageBuilder: (context, animation1, animation2) =>
                              const RankingScreen(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      );
                    }
                  },
                  child: _buildNavItem(
                    icon: Icons.leaderboard,
                    label: 'Ranking',
                    isActive: currentIndex == 3,
                    isDesktop: isDesktop,
                  ),
                ),

                GestureDetector(
                  onTap: () {
                    if (currentIndex != 4) {
                      Navigator.of(context).pushReplacement(
                        PageRouteBuilder(
                          pageBuilder: (context, animation1, animation2) =>
                              const ProfileScreen(),
                          transitionDuration: Duration.zero,
                          reverseTransitionDuration: Duration.zero,
                        ),
                      );
                    }
                  },
                  child: _buildNavItem(
                    icon: Icons.person,
                    label: 'Profile',
                    isActive: currentIndex == 4,
                    isDesktop: isDesktop,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    bool isActive = false,
    bool isDesktop = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: isActive ? AppTheme.primaryColor : const Color(0xFF64748b),
          size: isDesktop ? 22 : 24,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: isDesktop ? 11 : 10,
            fontWeight: FontWeight.bold,
            color: isActive ? AppTheme.primaryColor : const Color(0xFF64748b),
          ),
        ),
      ],
    );
  }

  Widget _buildWalletNavItem({
    required bool isActive,
    required bool isDesktop,
  }) {
    if (isDesktop) {
      return _buildNavItem(
        icon: Icons.account_balance_wallet,
        label: 'Wallet',
        isActive: isActive,
        isDesktop: true,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Transform.translate(
          offset: const Offset(0, -28),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive ? AppTheme.primaryColor : AppTheme.surfaceDark,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.backgroundDark, width: 4),
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: AppTheme.primaryColor.withValues(alpha: 0.4),
                        blurRadius: 20,
                      ),
                    ]
                  : [],
            ),
            child: const Icon(
              Icons.account_balance_wallet,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'WALLET',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: isActive ? AppTheme.primaryColor : const Color(0xFF64748b),
          ),
        ),
      ],
    );
  }
}
