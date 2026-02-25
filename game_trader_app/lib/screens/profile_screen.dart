import 'package:flutter/material.dart';
import '../app_theme.dart';
import 'settings_screen.dart';
import 'shared_bottom_nav.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

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
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.person,
                    size: 40,
                    color: AppTheme.primaryColor,
                  ),
                ),
                const SizedBox(height: 16),
                const Center(
                  child: Text(
                    'YOUR PROFILE',
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
                  'Account settings and preferences coming soon.',
                  style: TextStyle(color: Color(0xFF94a3b8), fontSize: 14),
                ),
              ],
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings, color: Colors.white),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                },
              ),
            ),

            // Shared Nav
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SharedBottomNav(currentIndex: 4),
            ),
          ],
        ),
      ),
    );
  }
}
