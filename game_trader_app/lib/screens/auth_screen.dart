import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../screens/dashboard_screen.dart';
import '../services/api_client.dart';
import '../services/session_manager.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_shell.dart';
import '../widgets/casino_top_nav.dart';

enum _AuthProviderAction { google, apple, guest }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  _AuthProviderAction? _activeProvider;
  bool _redirecting = false;

  bool get _busy => _activeProvider != null;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionManager>();
    final sessionReady = session.isReady;

    final wide = MediaQuery.of(context).size.width >= 980;

    return CasinoScaffold(
      appBar: const CasinoTopNav(title: 'Glory Grid'),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wide ? 1120 : 460),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(vertical: context.space.xl),
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 380),
              curve: Curves.easeOutCubic,
              tween: Tween(begin: 0, end: 1),
              builder: (context, value, child) => Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 14),
                  child: child,
                ),
              ),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 11, child: _buildIntroPanel(context)),
                        SizedBox(width: context.space.lg),
                        Expanded(
                          flex: 9,
                          child: _buildAuthPanel(context, sessionReady),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildIntroPanel(context),
                        SizedBox(height: context.space.md),
                        _buildAuthPanel(context, sessionReady),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIntroPanel(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 600;

    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(context.radii.lg),
            ),
            child: AspectRatio(
              aspectRatio: compact ? 2.05 : 1.75,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/neon_perimeter_bg.png',
                    fit: BoxFit.cover,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.08),
                          Colors.black.withValues(alpha: 0.74),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: context.space.md,
                    left: context.space.md,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.space.sm,
                        vertical: context.space.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(context.radii.pill),
                        border: Border.all(color: AppTheme.goldButtonBottom),
                      ),
                      child: Text(
                        'FAST',
                        style: context.type.label.copyWith(
                          color: AppTheme.goldText,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: context.space.lg,
                    right: context.space.lg,
                    bottom: context.space.lg,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Play fast.\nSettle live.',
                          style: context.type.heroTitle.copyWith(
                            color: Colors.white,
                            fontSize: compact ? 28 : 34,
                            fontWeight: FontWeight.w900,
                            height: 1.05,
                          ),
                        ),
                        SizedBox(height: context.space.sm),
                        Text(
                          'Guest entry. Room games. Live wallet.',
                          style: context.type.bodyStrong.copyWith(
                            color: Colors.white.withValues(alpha: 0.92),
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(context.space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: context.space.xs,
                  runSpacing: context.space.xs,
                  children: const [
                    _OnboardingPill(
                      icon: Icons.person_outline,
                      label: 'Guest first',
                    ),
                    _OnboardingPill(
                      icon: Icons.groups_2_outlined,
                      label: 'Rooms',
                    ),
                    _OnboardingPill(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'Wallet',
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

  Widget _buildAuthPanel(BuildContext context, bool sessionReady) {
    return SurfaceCard(
      padding: EdgeInsets.all(context.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: BorderRadius.circular(context.radii.lg),
                border: Border.all(color: AppTheme.goldButtonBottom),
              ),
              child: const Icon(
                Icons.sports_esports,
                color: AppTheme.goldText,
                size: 26,
              ),
            ),
          ),
          SizedBox(height: context.space.md),
          Text(
            'Start',
            style: context.type.heroTitle.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: context.space.xs),
          Text(
            'Guest or account.',
            style: context.type.body.copyWith(
              color: context.colors.textSecondary,
              height: 1.35,
            ),
          ),
          SizedBox(height: context.space.lg),
          Container(
            padding: EdgeInsets.all(context.space.md),
            decoration: BoxDecoration(
              color: context.colors.bgSurface,
              borderRadius: BorderRadius.circular(context.radii.lg),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.42),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.space.xs,
                        vertical: context.space.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(context.radii.pill),
                        border: Border.all(color: AppTheme.goldButtonBottom),
                      ),
                      child: Text(
                        'FAST',
                        style: context.type.label.copyWith(
                          color: AppTheme.goldText,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const Spacer(),
                    const Icon(
                      Icons.flash_on_rounded,
                      size: 18,
                      color: AppTheme.primaryColor,
                    ),
                  ],
                ),
                SizedBox(height: context.space.sm),
                Text(
                  'Guest',
                  style: context.type.bodyStrong.copyWith(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                SizedBox(height: context.space.xxs),
                Text(
                  'No signup.',
                  style: context.type.body.copyWith(
                    color: context.colors.textSecondary,
                    height: 1.35,
                  ),
                ),
                SizedBox(height: context.space.md),
                PrimaryButton(
                  expanded: true,
                  onPressed: (_busy || !sessionReady) ? null : _signInAsGuest,
                  label: !sessionReady
                      ? 'Loading...'
                      : _activeProvider == _AuthProviderAction.guest
                      ? 'Signing in...'
                      : 'Enter Lobby',
                ),
              ],
            ),
          ),
          SizedBox(height: context.space.lg),
          Row(
            children: [
              Expanded(child: Divider(color: context.colors.border, height: 1)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.space.sm),
                child: Text(
                  'or',
                  style: context.type.label.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ),
              Expanded(child: Divider(color: context.colors.border, height: 1)),
            ],
          ),
          SizedBox(height: context.space.lg),
          _providerButton(
            label: 'Google',
            icon: Icons.g_mobiledata_rounded,
            action: _AuthProviderAction.google,
            onPressed: _signInWithGoogle,
            sessionReady: sessionReady,
          ),
          SizedBox(height: context.space.sm),
          _providerButton(
            label: 'Apple',
            icon: Icons.apple,
            action: _AuthProviderAction.apple,
            onPressed: _signInWithApple,
            sessionReady: sessionReady,
          ),
          SizedBox(height: context.space.md),
          Text(
            'Accounts sync across devices.',
            style: context.type.label.copyWith(
              color: context.colors.textSecondary,
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
    required bool sessionReady,
  }) {
    return SecondaryButton(
      expanded: true,
      onPressed: (_busy || !sessionReady) ? null : onPressed,
      icon: icon,
      label: _activeProvider == action ? 'Please wait...' : label,
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

  Future<void> _signInAsGuest() {
    return _runAction(_AuthProviderAction.guest, () async {
      await context.read<SessionManager>().startGuestMode();
    });
  }

  Future<void> _runAction(
    _AuthProviderAction action,
    Future<void> Function() fn,
  ) async {
    if (_busy) {
      return;
    }

    setState(() => _activeProvider = action);
    try {
      await fn();
      if (!mounted) {
        return;
      }
      if (context.read<SessionManager>().isAuthenticated) {
        await _openGuestLobby();
        return;
      }
    } on ApiException catch (error) {
      _showError(error.message);
    } on FirebaseAuthException catch (error) {
      _showError(_firebaseAuthError(error));
    } catch (error) {
      _showError('Authentication failed: $error');
    } finally {
      if (mounted && !_redirecting) {
        setState(() => _activeProvider = null);
      }
    }
  }

  Future<void> _openGuestLobby() async {
    if (_redirecting || !mounted) {
      return;
    }
    _redirecting = true;
    await Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DashboardScreen()),
      (route) => false,
    );
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
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _OnboardingPill extends StatelessWidget {
  const _OnboardingPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.space.sm,
        vertical: context.space.xs,
      ),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(context.radii.pill),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.38),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.primaryColor),
          SizedBox(width: context.space.xxs),
          Text(
            label,
            style: context.type.label.copyWith(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
