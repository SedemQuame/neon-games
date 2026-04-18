import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/api_client.dart';
import '../services/session_manager.dart';

enum _AuthProviderAction { google, apple, x, guest }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _AuthProviderAction? _activeProvider;

  bool get _busy => _activeProvider != null;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionManager>();
    if (!session.isReady) {
      return const Scaffold(
        backgroundColor: AppTheme.backgroundDark,
        body: Center(
          child: CircularProgressIndicator(color: AppTheme.primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final horizontalPadding = width >= 900 ? width * 0.12 : 24.0;
            final cardWidth = width >= 1100
                ? 420.0
                : width >= 700
                ? 440.0
                : double.infinity;

            return Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: 32,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: cardWidth),
                  child: _buildAuthCard(),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildAuthCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.borderDark),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.12),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(
              Icons.sports_esports,
              color: AppTheme.primaryColor,
              size: 30,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Welcome to Glory Grid',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sign in with your preferred provider. Authentication is powered by Firebase across web and mobile.',
            style: TextStyle(
              color: Color(0xFF94a3b8),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 28),
          _providerButton(
            label: 'Continue with Google',
            icon: Icons.g_mobiledata_rounded,
            action: _AuthProviderAction.google,
            onPressed: _signInWithGoogle,
          ),
          const SizedBox(height: 12),
          _providerButton(
            label: 'Continue with Apple',
            icon: Icons.apple,
            action: _AuthProviderAction.apple,
            onPressed: _signInWithApple,
          ),
          const SizedBox(height: 12),
          _providerButton(
            label: 'Continue with X',
            icon: Icons.alternate_email,
            action: _AuthProviderAction.x,
            onPressed: _signInWithX,
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _busy ? null : _signInAsGuest,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _activeProvider == _AuthProviderAction.guest
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Continue as Guest',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Guest mode uses Firebase anonymous auth and can be linked to an SSO account later.',
            style: TextStyle(
              color: Color(0xFF64748b),
              fontSize: 12,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _providerButton({
    required String label,
    required IconData icon,
    required _AuthProviderAction action,
    required Future<void> Function() onPressed,
  }) {
    return ElevatedButton.icon(
      onPressed: _busy ? null : onPressed,
      icon: Icon(icon, size: 20),
      label: _activeProvider == action
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> _signInWithGoogle() {
    return _runAction(_AuthProviderAction.google, () async {
      await context.read<SessionManager>().signInWithGoogle();
    });
  }

  Future<void> _signInWithApple() {
    return _runAction(_AuthProviderAction.apple, () async {
      await context.read<SessionManager>().signInWithApple();
    });
  }

  Future<void> _signInWithX() {
    return _runAction(_AuthProviderAction.x, () async {
      await context.read<SessionManager>().signInWithX();
    });
  }

  Future<void> _signInAsGuest() {
    return _runAction(_AuthProviderAction.guest, () async {
      await context.read<SessionManager>().startGuestMode();
    });
  }

  Future<void> _runAction(
    _AuthProviderAction action,
    Future<void> Function() fn,
  ) async {
    if (_busy) return;
    setState(() => _activeProvider = action);
    try {
      await fn();
    } on ApiException catch (error) {
      _showError(error.message);
    } on FirebaseAuthException catch (error) {
      _showError(_firebaseAuthError(error));
    } catch (error) {
      _showError('Authentication failed: $error');
    } finally {
      if (mounted) {
        setState(() => _activeProvider = null);
      }
    }
  }

  String _firebaseAuthError(FirebaseAuthException error) {
    if (error.code == 'account-exists-with-different-credential') {
      return 'This account already exists with a different sign-in method.';
    }
    if (error.code == 'popup-closed-by-user') {
      return 'Sign-in window was closed before completing authentication.';
    }
    if (error.code == 'operation-not-supported-in-this-environment') {
      return 'This provider is not supported in the current environment.';
    }
    return error.message ?? 'Unable to sign in right now.';
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
