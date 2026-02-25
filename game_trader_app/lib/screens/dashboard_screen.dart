import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/models.dart';
import '../services/session_manager.dart';
import 'shared_bottom_nav.dart';
import 'deposit_screen.dart';
import 'game_screens/neon_rise_screen.dart';

import 'game_screens/digit_dash_screen.dart';
import 'game_screens/zero_hour_sniper_screen.dart';

import 'game_screens/dual_dimension_flip_screen.dart';
import 'game_screens/velocity_vector_screen.dart';
import 'game_screens/neon_perimeter_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  WalletBalance? _balance;
  bool _loadingBalance = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshBalance();
    });
  }

  Future<void> _refreshBalance() async {
    final session = context.read<SessionManager>();
    if (!session.isAuthenticated) return;
    setState(() => _loadingBalance = true);
    try {
      final latest = await session.refreshBalance();
      if (mounted) {
        setState(() => _balance = latest);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load balance: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loadingBalance = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildHeader(context, _balance, _loadingBalance),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _refreshBalance,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.only(bottom: 120),
                      children: [
                        _buildPromoScroller(),
                        _buildFilterChips(),
                        _buildGamesGrid(context),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Live Win Feed
          Positioned(bottom: 96, left: 16, right: 16, child: _buildLiveFeed()),

          // Bottom Nav
          const Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SharedBottomNav(currentIndex: 0),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    WalletBalance? balance,
    bool loading,
  ) {
    return Container(
      color: AppTheme.backgroundDark.withValues(alpha: 0.8),
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(Icons.person, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'TOTAL BALANCE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: Color(0xFF94a3b8),
                    ),
                  ),
                  Text(
                    loading
                        ? 'Loading...'
                        : _formatCurrency(balance?.availableUsd ?? 0),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const DepositScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
              minimumSize: const Size(0, 40),
            ),
            icon: const Icon(Icons.add_circle, size: 16),
            label: const Text('Deposit'),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoScroller() {
    return SizedBox(
      height: 144,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildPromoCard(
            title: 'Neon Master Series',
            subtitle: 'Win your share of \$50,000',
            badgeText: 'TOURNAMENT LIVE',
            colors: [AppTheme.primaryColor, Colors.blue.shade600],
            icon: Icons.emoji_events,
          ),
          const SizedBox(width: 12),
          _buildPromoCard(
            title: 'Daily Win Streak',
            subtitle: '5 wins in a row = 20% bonus',
            badgeText: 'BONUS',
            colors: [Colors.purple.shade600, Colors.indigo.shade700],
            icon: Icons.bolt,
          ),
        ],
      ),
    );
  }

  Widget _buildPromoCard({
    required String title,
    required String subtitle,
    required String badgeText,
    required List<Color> colors,
    required IconData icon,
  }) {
    return Container(
      width: 288,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -16,
            bottom: -16,
            child: Icon(
              icon,
              size: 128,
              color: Colors.black.withValues(alpha: 0.1),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Text(
                    badgeText,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Row(children: [_buildChip('All Games', isActive: true)]),
    );
  }

  Widget _buildChip(String label, {bool isActive = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: isActive ? AppTheme.primaryColor : AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isActive ? Colors.white : const Color(0xFFcbd5e1),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildGamesGrid(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Featured Trading Games',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                'See All',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              int crossAxisCount = 1;
              if (constraints.maxWidth >= 900) {
                crossAxisCount = 3;
              } else if (constraints.maxWidth >= 600) {
                crossAxisCount = 2;
              }

              return GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: crossAxisCount == 1 ? 2.0 : 1.5,
                children: [
                  _buildGameCard(
                    title: 'NEON RISE',
                    subtitle: 'Predict market peaks and valleys',
                    badge1: 'RISE/FALL',
                    badge1Color: AppTheme.primaryColor,
                    badge2Title: 'WIN UP TO',
                    badge2Value: '95%',
                    imagePath: 'assets/images/neon_rise_bg.png',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NeonRiseScreen(),
                        ),
                      );
                    },
                  ),

                  _buildGameCard(
                    title: 'DIGIT DASH',
                    subtitle: 'Match the last tick digit for high payout',
                    badge1: 'MATCHES/DIFFERS',
                    badge1Color: Colors.blueAccent,
                    badge2Title: 'WIN UP TO',
                    badge2Value: '900%',
                    imagePath: 'assets/images/digit_dash_bg.png',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DigitDashScreen(),
                        ),
                      );
                    },
                  ),
                  _buildGameCard(
                    title: 'ZERO-HOUR SNIPER',
                    subtitle: 'Pinpoint exact market ticks',
                    badge1: 'EXACT MATCH',
                    badge1Color: Colors.redAccent,
                    badge2Title: 'WIN UP TO',
                    badge2Value: '750%',
                    imagePath: 'assets/images/zero_hour_sniper_bg.png',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ZeroHourSniperScreen(),
                        ),
                      );
                    },
                  ),

                  _buildGameCard(
                    title: 'DUAL DIMENSION FLIP',
                    subtitle: 'Predict market trend reversals',
                    badge1: 'REVERSAL',
                    badge1Color: Colors.tealAccent,
                    badge2Title: 'WIN UP TO',
                    badge2Value: '850%',
                    imagePath: 'assets/images/dual_dimension_flip_bg.png',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const DualDimensionFlipScreen(),
                        ),
                      );
                    },
                  ),
                  _buildGameCard(
                    title: 'VELOCITY VECTOR',
                    subtitle: 'Bet on market speed and momentum',
                    badge1: 'VOLATILITY',
                    badge1Color: Colors.cyanAccent,
                    badge2Title: 'WIN UP TO',
                    badge2Value: '550%',
                    imagePath: 'assets/images/velocity_vector_bg.png',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const VelocityVectorScreen(),
                        ),
                      );
                    },
                  ),
                  _buildGameCard(
                    title: 'NEON PERIMETER',
                    subtitle: 'Predict if price breaches boundaries',
                    badge1: 'ENDS IN/OUT',
                    badge1Color: Colors.pinkAccent,
                    badge2Title: 'WIN UP TO',
                    badge2Value: '600%',
                    imagePath: 'assets/images/neon_perimeter_bg.png',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NeonPerimeterScreen(),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGameCard({
    required String title,
    required String subtitle,
    required String badge1,
    required Color badge1Color,
    required String badge2Title,
    required String badge2Value,
    required String imagePath,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 192,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: AppTheme.surfaceDark,
          border: Border.all(color: AppTheme.borderDark),
          image: DecorationImage(
            image: AssetImage(imagePath),
            fit: BoxFit.cover,
            opacity: 0.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.black.withValues(alpha: 0.2),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: badge1Color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge1,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: badge1Color,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: Colors.white,
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFcbd5e1),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        badge2Title,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF94a3b8),
                        ),
                      ),
                      Text(
                        badge2Value,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.greenAccent,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveFeed() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0b0e11).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'LIVE FEED',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF94a3b8),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              '@User_882 just won \$142.50 in Neon Rise',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double value) {
    return '\$${value.toStringAsFixed(2)}';
  }
}
