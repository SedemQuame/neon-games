import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/session_manager.dart';
import '../widgets/game_message.dart';

class ForgotPasswordSheet extends StatefulWidget {
  const ForgotPasswordSheet({super.key});

  @override
  State<ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends State<ForgotPasswordSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _requestEmailController = TextEditingController();
  final _resetTokenController = TextEditingController();
  final _resetPasswordController = TextEditingController();
  bool _sendingLink = false;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    final remembered = context.read<SessionManager>().rememberedEmail;
    if (remembered != null && remembered.isNotEmpty) {
      _requestEmailController.text = remembered;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _requestEmailController.dispose();
    _resetTokenController.dispose();
    _resetPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.backgroundDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const Text(
            'Reset Password',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: AppTheme.primaryColor,
            tabs: const [
              Tab(text: 'Request Link'),
              Tab(text: 'Apply Token'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildRequestForm(),
                _buildResetForm(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Enter the email associated with your account. We’ll send a secure link that lets you choose a new password.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _requestEmailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Email address',
            prefixIcon: Icon(Icons.alternate_email),
          ),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: _sendingLink ? null : _sendLink,
          child: _sendingLink
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Email Reset Link'),
        ),
      ],
    );
  }

  Widget _buildResetForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Paste the token from your email and choose a new password.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _resetTokenController,
          decoration: const InputDecoration(
            labelText: 'Reset token',
            prefixIcon: Icon(Icons.lock_open),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _resetPasswordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'New password',
            prefixIcon: Icon(Icons.key),
          ),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: _resetting ? null : _applyReset,
          child: _resetting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Update Password'),
        ),
      ],
    );
  }

  Future<void> _sendLink() async {
    final email = _requestEmailController.text.trim();
    if (email.isEmpty) {
      showGameMessage(context, 'Email is required.');
      return;
    }
    setState(() => _sendingLink = true);
    try {
      await context.read<SessionManager>().requestPasswordReset(email);
      if (!mounted) return;
      showGameMessage(context, 'If the email exists, a reset link is on the way.');
    } catch (err) {
      if (!mounted) return;
      showGameMessage(context, 'Unable to send email: $err');
    } finally {
      if (mounted) {
        setState(() => _sendingLink = false);
      }
    }
  }

  Future<void> _applyReset() async {
    final token = _resetTokenController.text.trim();
    final password = _resetPasswordController.text;
    if (token.isEmpty || password.length < 6) {
      showGameMessage(context, 'Token and a 6+ character password are required.');
      return;
    }
    setState(() => _resetting = true);
    try {
      await context.read<SessionManager>().resetPassword(
            token: token,
            password: password,
          );
      if (!mounted) return;
      showGameMessage(context, 'Password updated. You can now sign in.');
    } catch (err) {
      if (!mounted) return;
      showGameMessage(context, 'Reset failed: $err');
    } finally {
      if (mounted) {
        setState(() => _resetting = false);
      }
    }
  }
}
