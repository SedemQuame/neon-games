import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/session_manager.dart';
import '../widgets/app_shell.dart';
import '../widgets/casino_top_nav.dart';
import '../widgets/game_message.dart';
import '../widgets/section_header.dart';
import 'auth_screen.dart';
import 'deposit_screen.dart';
import 'shared_bottom_nav.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    this.showBackButton = true,
    this.isProfileTab = false,
  });

  final bool showBackButton;
  final bool isProfileTab;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionManager>();
    return CasinoScaffold(
      useNarrowLayout: true,
      appBar: CasinoTopNav(
        title: isProfileTab ? 'Profile' : 'Settings',
        showBackButton: showBackButton,
      ),
      bottomNavigationBar: isProfileTab
          ? const SharedBottomNav(currentIndex: 3)
          : null,
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: context.space.md),
        children: [
          const SectionHeader(title: 'Account'),
          SizedBox(height: context.space.xs),
          SurfaceCard(
            child: Column(
              children: [
                SwitchListTile(
                  value: session.rememberMe,
                  onChanged: (value) => _handleRememberMe(context, value),
                  activeThumbColor: context.colors.primary,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Stay signed in',
                    style: context.type.bodyStrong.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    session.rememberMe ? 'On' : 'Off',
                    style: context.type.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Refresh balance',
                    style: context.type.bodyStrong,
                  ),
                  subtitle: Text(
                    'Update wallet',
                    style: context.type.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  trailing: const Icon(Icons.refresh),
                  onTap: () => _handleRefreshBalance(context),
                ),
              ],
            ),
          ),
          SizedBox(height: context.space.lg),
          const SectionHeader(title: 'Tools'),
          SizedBox(height: context.space.xs),
          SurfaceCard(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Deposit', style: context.type.bodyStrong),
                  subtitle: Text(
                    'Add funds',
                    style: context.type.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  trailing: const Icon(Icons.account_balance_wallet),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DepositScreen()),
                    );
                  },
                ),
              ],
            ),
          ),
          SizedBox(height: context.space.lg),
          const SectionHeader(title: 'Security'),
          SizedBox(height: context.space.xs),
          SurfaceCard(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Log out',
                style: context.type.bodyStrong.copyWith(
                  color: context.colors.danger,
                ),
              ),
              trailing: Icon(
                Icons.power_settings_new,
                color: context.colors.danger,
              ),
              onTap: () => _handleLogout(context),
            ),
          ),
          SizedBox(height: context.space.xl),
        ],
      ),
    );
  }

  void _handleRememberMe(BuildContext context, bool value) {
    final session = context.read<SessionManager>();
    unawaited(session.setRememberMe(value));
    showGameMessage(
      context,
      value ? 'Stay signed in is enabled.' : 'Stay signed in is disabled.',
    );
  }

  Future<void> _handleRefreshBalance(BuildContext context) async {
    final session = context.read<SessionManager>();
    try {
      await session.refreshBalance();
      if (context.mounted) {
        showGameMessage(context, 'Wallet balance updated.');
      }
    } catch (error) {
      if (context.mounted) {
        showGameMessage(context, 'Refresh failed: $error');
      }
    }
  }

  Future<void> _handleLogout(BuildContext context) async {
    final session = context.read<SessionManager>();
    if (session.isAnonymous) {
      final shouldLogout = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: context.colors.bgSurface,
          title: Text('Guest Account', style: context.type.sectionTitle.copyWith(color: context.colors.textPrimary)),
          content: Text(
            'You are playing anonymously. If you log out now, your balance and game history will be permanently lost.',
            style: context.type.body.copyWith(color: context.colors.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Logout Anyway', style: context.type.label.copyWith(color: context.colors.danger)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, false);
                _showLinkAccountDialog(context, session);
              },
              style: ElevatedButton.styleFrom(backgroundColor: context.colors.primary),
              child: Text('Link Account', style: context.type.label.copyWith(color: context.colors.bgApp)),
            ),
          ],
        ),
      );
      if (shouldLogout != true) return;
    }
    await _performLogout(context, session);
  }

  Future<void> _performLogout(BuildContext context, SessionManager session) async {
    await session.logout();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }

  void _showLinkAccountDialog(BuildContext context, SessionManager session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.bgSurface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: EdgeInsets.all(context.space.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Link Account', style: context.type.sectionTitle.copyWith(color: context.colors.textPrimary), textAlign: TextAlign.center),
              SizedBox(height: context.space.sm),
              Text('Secure your account to play across devices and save your balance.', style: context.type.body.copyWith(color: context.colors.textSecondary), textAlign: TextAlign.center),
              SizedBox(height: context.space.xl),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await session.linkGoogleAccount();
                    if (context.mounted) {
                      Navigator.pop(context);
                      showGameMessage(context, 'Account successfully linked to Google!');
                    }
                  } catch (e) {
                    if (context.mounted) showGameMessage(context, 'Failed to link account: $e');
                  }
                },
                icon: const Icon(Icons.g_mobiledata),
                label: const Text('Link with Google'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  padding: EdgeInsets.all(context.space.md),
                ),
              ),
              SizedBox(height: context.space.md),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    await session.linkAppleAccount();
                    if (context.mounted) {
                      Navigator.pop(context);
                      showGameMessage(context, 'Account successfully linked to Apple!');
                    }
                  } catch (e) {
                    if (context.mounted) showGameMessage(context, 'Failed to link account: $e');
                  }
                },
                icon: const Icon(Icons.apple),
                label: const Text('Link with Apple'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.all(context.space.md),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
