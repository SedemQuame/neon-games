import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'shared_bottom_nav.dart';

class TradesScreen extends StatelessWidget {
  const TradesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.auto_graph,
                  size: 80,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'YOUR TRADES',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -1,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Trade portfolio coming soon.',
                  style: TextStyle(color: Color(0xFF94a3b8), fontSize: 14),
                ),
              ],
            ),

            // Shared Nav
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SharedBottomNav(currentIndex: 1),
            ),
          ],
        ),
      ),
    );
  }
}
