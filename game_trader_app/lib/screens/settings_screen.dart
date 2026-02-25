import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/session_manager.dart';
import '../widgets/game_message.dart';
import 'app_logs_screen.dart';
import 'deposit_screen.dart';
import 'signup_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionManager>();
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark,
        elevation: 0,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _SectionHeader(label: 'ACCOUNT'),
          SwitchListTile(
            value: session.rememberMe,
            onChanged: (value) => _handleRememberMe(context, value),
            activeThumbColor: AppTheme.primaryColor,
            title: const Text(
              'Stay signed in',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: Text(
              session.rememberedEmail?.isNotEmpty == true
                  ? 'Using ${session.rememberedEmail}'
                  : 'Remembers your email on this device',
              style: const TextStyle(color: Color(0xFF94a3b8)),
            ),
          ),
          ListTile(
            title: const Text(
              'Refresh wallet balance',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Fetch the latest funds from Glory Grid',
              style: TextStyle(color: Color(0xFF94a3b8)),
            ),
            trailing: const Icon(Icons.refresh, color: Colors.white54),
            onTap: () => _handleRefreshBalance(context),
          ),
          const SizedBox(height: 16),
          _SectionHeader(label: 'TOOLS'),
          ListTile(
            title: const Text(
              'View app logs',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Inspect API, socket, and UI events',
              style: TextStyle(color: Color(0xFF94a3b8)),
            ),
            trailing: const Icon(Icons.list_alt, color: Colors.white54),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AppLogsScreen()),
              );
            },
          ),
          ListTile(
            title: const Text(
              'Deposit funds',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Top up your arcade wallet',
              style: TextStyle(color: Color(0xFF94a3b8)),
            ),
            trailing: const Icon(Icons.account_balance_wallet, color: Colors.white54),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DepositScreen()),
              );
            },
          ),
          const SizedBox(height: 16),
          _SectionHeader(label: 'SECURITY'),
          ListTile(
            title: const Text(
              'Log out',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
            ),
            trailing: const Icon(Icons.power_settings_new, color: Colors.redAccent),
            onTap: () => _handleLogout(context),
          ),
        ],
      ),
    );
  }

  void _handleRememberMe(BuildContext context, bool value) {
    final session = context.read<SessionManager>();
    unawaited(session.setRememberMe(value));
    if (!value) {
      unawaited(session.rememberEmail(null));
      showGameMessage(context, 'Saved login cleared.');
    } else {
      showGameMessage(context, 'Remember me enabled. Login email will be saved.');
    }
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
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignupScreen()),
      (route) => false,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF94a3b8),
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
    );
  }
}
