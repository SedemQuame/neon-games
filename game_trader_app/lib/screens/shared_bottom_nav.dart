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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
      decoration: BoxDecoration(
        color: AppTheme.backgroundDark.withValues(alpha: 0.95),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      child: SafeArea(
        top: false,
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
                label: 'Trade',
                isActive: currentIndex == 1,
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -28),
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: currentIndex == 2
                            ? AppTheme.primaryColor
                            : AppTheme.surfaceDark,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.backgroundDark,
                          width: 4,
                        ),
                        boxShadow: currentIndex == 2
                            ? [
                                BoxShadow(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.4,
                                  ),
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
                      color: currentIndex == 2
                          ? AppTheme.primaryColor
                          : const Color(0xFF64748b),
                    ),
                  ),
                ],
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
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required String label,
    bool isActive = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          color: isActive ? AppTheme.primaryColor : const Color(0xFF64748b),
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          label,
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
