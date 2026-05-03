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
      appBar: CasinoTopNav(title: 'Settings', showBackButton: showBackButton),
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
    await session.logout();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (route) => false,
    );
  }
}
