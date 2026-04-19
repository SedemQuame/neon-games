import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import 'auth_screen.dart';

class WebLandingScreen extends StatefulWidget {
  const WebLandingScreen({super.key});

  @override
  State<WebLandingScreen> createState() => _WebLandingScreenState();
}

class _WebLandingScreenState extends State<WebLandingScreen> {
  static const _iosUrl = String.fromEnvironment(
    'GAMEHUB_IOS_URL',
    defaultValue: 'https://apps.apple.com/',
  );
  static const _androidUrl = String.fromEnvironment(
    'GAMEHUB_ANDROID_URL',
    defaultValue: 'https://play.google.com/store',
  );

  final _detailsKey = GlobalKey();
  final _accessKey = GlobalKey();
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 1000;
            final horizontal = wide ? constraints.maxWidth * 0.08 : 20.0;
            return SingleChildScrollView(
              controller: _scrollCtrl,
              child: Padding(
                padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildNavBar(context),
                    const SizedBox(height: 40),
                    _buildHero(context, wide),
                    const SizedBox(height: 56),
                    Container(
                      key: _detailsKey,
                      child: _buildDetailsSection(wide),
                    ),
                    const SizedBox(height: 56),
                    Container(key: _accessKey, child: _buildAccessSection()),
                    const SizedBox(height: 40),
                    const Divider(color: AppTheme.borderDark, height: 1),
                    const SizedBox(height: 20),
                    const Text(
                      'Glory Grid • Skill-based game sessions with real-time wallet tracking.',
                      style: TextStyle(color: Color(0xFF64748b), fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNavBar(BuildContext context) {
    final compact = MediaQuery.of(context).size.width < 760;
    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppTheme.primaryColor.withValues(alpha: 0.35),
            ),
          ),
          child: const Icon(Icons.sports_esports, color: AppTheme.primaryColor),
        ),
        const SizedBox(width: 12),
        const Text(
          'Glory Grid',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        TextButton(
          onPressed: () => _scrollTo(_detailsKey),
          child: const Text('Details'),
        ),
        ElevatedButton(
          onPressed: () => _openAuth(context),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(110, 44),
            padding: const EdgeInsets.symmetric(horizontal: 18),
          ),
          child: const Text('Login'),
        ),
        OutlinedButton(
          onPressed: () => _openAuth(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            minimumSize: const Size(110, 44),
          ),
          child: const Text('Sign up'),
        ),
      ],
    );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [brand, const SizedBox(height: 16), actions],
      );
    }

    return Row(children: [brand, const Spacer(), actions]);
  }

  Widget _buildHero(BuildContext context, bool wide) {
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'LIVE PLATFORM',
            style: TextStyle(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w700,
              fontSize: 11,
              letterSpacing: 0.8,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Predict game outcomes.\nTrack wallet performance live.',
          style: TextStyle(
            fontSize: 44,
            height: 1.1,
            fontWeight: FontWeight.w900,
            color: Colors.white,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Glory Grid combines skill-based prediction games with unified wallet controls, instant crypto funding, and real-time result streams.',
          style: TextStyle(fontSize: 16, height: 1.6, color: Color(0xFF94a3b8)),
        ),
        const SizedBox(height: 22),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ElevatedButton(
              onPressed: () => _openAuth(context),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(180, 50),
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              child: const Text('Get started'),
            ),
            OutlinedButton(
              onPressed: () => _scrollTo(_detailsKey),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                minimumSize: const Size(180, 50),
              ),
              child: const Text('View details'),
            ),
          ],
        ),
      ],
    );

    final right = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Get the mobile app',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Download on your preferred store.',
            style: TextStyle(color: Color(0xFF94a3b8), fontSize: 13),
          ),
          const SizedBox(height: 18),
          _storeButton(
            icon: Icons.apple,
            title: 'iOS version',
            subtitle: 'Open App Store',
            onTap: () => _openExternal(_iosUrl),
          ),
          const SizedBox(height: 12),
          _storeButton(
            icon: Icons.android,
            title: 'Android version',
            subtitle: 'Open Play Store',
            onTap: () => _openExternal(_androidUrl),
          ),
        ],
      ),
    );

    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 6, child: left),
          const SizedBox(width: 28),
          Expanded(flex: 4, child: right),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [left, const SizedBox(height: 24), right],
    );
  }

  Widget _buildDetailsSection(bool wide) {
    final cards = [
      _infoCard(
        icon: Icons.security,
        title: 'Secure Auth',
        body:
            'Firebase-backed identity flow with token exchange into GameHub sessions.',
      ),
      _infoCard(
        icon: Icons.flash_on,
        title: 'Real-time Games',
        body:
            'WebSocket game sessions with immediate bet acknowledgements and outcomes.',
      ),
      _infoCard(
        icon: Icons.account_balance_wallet,
        title: 'Unified Wallet',
        body:
            'Single wallet ledger across deposits, settlements, and payout updates.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Platform details',
          style: TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Designed for fast interaction, transparent wallet events, and consistent cross-device play.',
          style: TextStyle(color: Color(0xFF94a3b8), fontSize: 14),
        ),
        const SizedBox(height: 20),
        if (wide)
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 14),
              Expanded(child: cards[1]),
              const SizedBox(width: 14),
              Expanded(child: cards[2]),
            ],
          )
        else
          Column(
            children: [
              cards[0],
              const SizedBox(height: 12),
              cards[1],
              const SizedBox(height: 12),
              cards[2],
            ],
          ),
      ],
    );
  }

  Widget _buildAccessSection() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.borderDark),
          ),
          padding: const EdgeInsets.all(24),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Login / Signup',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Use Google, Apple, X, or guest mode to access the platform.',
                      style: TextStyle(color: Color(0xFF94a3b8), fontSize: 14),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => _openAuth(context),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(180, 50),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        child: const Text('Continue'),
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Login / Signup',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Use Google, Apple, X, or guest mode to access the platform.',
                            style: TextStyle(
                              color: Color(0xFF94a3b8),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    ElevatedButton(
                      onPressed: () => _openAuth(context),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(180, 50),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      child: const Text('Continue'),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String body,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 22),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: Color(0xFF94a3b8),
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _storeButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
        minimumSize: const Size(double.infinity, 58),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: Color(0xFF94a3b8)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _openAuth(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  Future<void> _openExternal(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) {
      _showToast('Invalid mobile app link configured.');
      return;
    }
    final opened = await launchUrl(uri, webOnlyWindowName: '_blank');
    if (!opened && mounted) {
      _showToast('Could not open link: $rawUrl');
    }
  }

  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
