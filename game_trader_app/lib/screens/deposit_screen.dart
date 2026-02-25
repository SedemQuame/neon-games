import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'crypto_deposit_screen.dart';
import 'mobile_money_deposit_screen.dart';

class DepositScreen extends StatelessWidget {
  const DepositScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                children: [
                  const Text(
                    'Select Deposit Method',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Choose how you want to fund your arcade wallet. Transactions are fast and secure.',
                    style: TextStyle(color: Color(0xFF94a3b8), fontSize: 14),
                  ),
                  const SizedBox(height: 32),
                  _buildMethodCard(
                    context,
                    title: 'Cryptocurrency',
                    subtitle: 'Instant deposit via BTC, ETH, USDT',
                    icon: Icons.currency_bitcoin,
                    iconColor: Colors.orange,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const CryptoDepositScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildMethodCard(
                    context,
                    title: 'Mobile Money',
                    subtitle: 'Deposit via MTN, Vodafone, or AirtelTigo',
                    icon: Icons.phone_iphone,
                    iconColor: Colors.greenAccent,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              const MobileMoneyDepositScreen(),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  _buildMethodCard(
                    context,
                    title: 'Credit / Debit Card',
                    subtitle: 'Visa, Mastercard supported',
                    icon: Icons.credit_card,
                    iconColor: Colors.blueAccent,
                    onTap: () {
                      // Placeholder for future Card deposit implementation
                    },
                    isComingSoon: true,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const Text(
            'DEPOSIT FUNDS',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 40), // Spacer for centering
        ],
      ),
    );
  }

  Widget _buildMethodCard(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    bool isComingSoon = false,
  }) {
    return GestureDetector(
      onTap: isComingSoon ? null : onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surfaceDark,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isComingSoon ? Colors.transparent : AppTheme.borderDark,
          ),
          boxShadow: isComingSoon
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isComingSoon
                              ? Colors.white.withValues(alpha: 0.5)
                              : Colors.white,
                        ),
                      ),
                      if (isComingSoon) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'SOON',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isComingSoon
                          ? const Color(0xFF94a3b8).withValues(alpha: 0.5)
                          : const Color(0xFF94a3b8),
                    ),
                  ),
                ],
              ),
            ),
            if (!isComingSoon)
              const Icon(
                Icons.arrow_forward_ios,
                color: AppTheme.primaryColor,
                size: 16,
              ),
          ],
        ),
      ),
    );
  }
}
