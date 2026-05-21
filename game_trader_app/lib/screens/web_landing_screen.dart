import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_theme.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_shell.dart';
import '../widgets/casino_top_nav.dart';
import '../widgets/section_header.dart';
import '../widgets/tag_badge.dart';
import 'auth_screen.dart';
import 'game_screens/digit_dash_screen.dart';
import 'game_screens/neon_perimeter_screen.dart';
import 'game_screens/neon_rise_screen.dart';
import 'game_screens/velocity_vector_screen.dart';

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

  final _gamesKey = GlobalKey();
  final _featuresKey = GlobalKey();
  final _accessKey = GlobalKey();
  final _scrollCtrl = ScrollController();

  static const List<_GamePreview> _soloGames = [
    _GamePreview(
      title: 'Neon Rise',
      tagline: 'Market direction.',
      imagePath: 'assets/images/neon_rise_bg.png',
      demoPlayable: true,
      gameScreen: NeonRiseScreen(),
    ),
    _GamePreview(
      title: 'Digit Dash',
      tagline: 'Last digit.',
      imagePath: 'assets/images/digit_dash_bg.png',
      demoPlayable: true,
      gameScreen: DigitDashScreen(),
    ),
    _GamePreview(
      title: 'Neon Perimeter',
      tagline: 'Boundary break.',
      imagePath: 'assets/images/neon_perimeter_bg.png',
      demoPlayable: true,
      gameScreen: NeonPerimeterScreen(),
    ),
    _GamePreview(
      title: 'Velocity Vector',
      tagline: 'Momentum.',
      imagePath: 'assets/images/velocity_vector_bg.png',
      demoPlayable: true,
      gameScreen: VelocityVectorScreen(),
    ),
  ];

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wideNav = MediaQuery.of(context).size.width >= 1120;

    return CasinoScaffold(
      appBar: CasinoTopNav(
        title: 'Glory Grid',
        actions: [
          if (wideNav) ...[
            TextButton(
              onPressed: () => _scrollTo(_gamesKey),
              child: Text('Games'),
            ),
            TextButton(
              onPressed: () => _scrollTo(_featuresKey),
              child: Text('Features'),
            ),
            TextButton(
              onPressed: () => _openExternal(_iosUrl),
              child: Text('iOS'),
            ),
            TextButton(
              onPressed: () => _openExternal(_androidUrl),
              child: Text('Android'),
            ),
          ],
          Padding(
            padding: EdgeInsets.only(right: context.space.sm),
            child: PrimaryButton(
              label: 'Play Now',
              onPressed: () => _openAuth(context),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          _buildBackgroundDecor(),
          SingleChildScrollView(
            controller: _scrollCtrl,
            padding: EdgeInsets.symmetric(vertical: context.space.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHero(context),
                SizedBox(height: context.space.lg),
                _buildStatsStrip(context),
                SizedBox(height: context.space.xxl),
                Container(key: _gamesKey, child: _buildGamesSection(context)),
                SizedBox(height: context.space.xxl),
                Container(
                  key: _featuresKey,
                  child: _buildFeaturesSection(context),
                ),
                SizedBox(height: context.space.xxl),
                Container(key: _accessKey, child: _buildAccessSection(context)),
                SizedBox(height: context.space.xl),
                Text(
                  'Glory Grid • Games, rooms, wallet.',
                  style: context.type.label.copyWith(
                    color: context.colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundDecor() {
    return const SizedBox.shrink();
  }

  Widget _buildHero(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1040;

        final left = SurfaceCard(
          padding: EdgeInsets.all(context.space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TagBadge(label: 'GUEST'),
              SizedBox(height: context.space.md),
              Text(
                'Play the next round instantly.',
                style: context.type.heroTitle.copyWith(
                  fontSize: wide ? 48 : 34,
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w900,
                  height: 1.05,
                ),
              ),
              SizedBox(height: context.space.sm),
              Text(
                'Solo demos are playable now. Live lobbies are unlocked with guest access or SSO.',
                style: context.type.bodyStrong.copyWith(
                  color: context.colors.textSecondary,
                  height: 1.45,
                ),
              ),
              SizedBox(height: context.space.md),
              Wrap(
                spacing: context.space.sm,
                runSpacing: context.space.sm,
                children: [
                  PrimaryButton(
                    label: 'Play demo',
                    onPressed: () => _launchFirstDemo(context),
                  ),
                  SecondaryButton(
                    label: 'Join lobby',
                    onPressed: () => _openAuth(context),
                    expanded: false,
                  ),
                ],
              ),
              SizedBox(height: context.space.md),
              Wrap(
                spacing: context.space.xs,
                runSpacing: context.space.xs,
                children: const [
                  _HeroChip(label: 'Demo first'),
                  _HeroChip(label: 'Guest entry'),
                  _HeroChip(label: 'Live wallet'),
                ],
              ),
            ],
          ),
        );

        final right = _buildHeroVisual(context);

        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 11, child: left),
              SizedBox(width: context.space.lg),
              Expanded(flex: 9, child: right),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            left,
            SizedBox(height: context.space.md),
            right,
          ],
        );
      },
    );
  }

  Widget _buildHeroVisual(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.all(context.space.md),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(context.radii.lg),
            child: AspectRatio(
              aspectRatio: 1.02,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(
                    'assets/images/neon_rise_bg.png',
                    fit: BoxFit.cover,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.06),
                          Colors.black.withValues(alpha: 0.72),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: context.space.md,
            left: context.space.md,
            right: context.space.md,
            child: Row(
              children: [
                Expanded(
                  child: _floatingMetricCard(
                    context,
                    title: 'LIVE GAMES',
                    value: '15+ games',
                  ),
                ),
                SizedBox(width: context.space.sm),
                Expanded(
                  child: _floatingMetricCard(
                    context,
                    title: 'WALLET',
                    value: 'Live balance',
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: context.space.md,
            right: context.space.md,
            bottom: context.space.md,
            child: SurfaceCard(
              backgroundColor: Colors.black.withValues(alpha: 0.62),
              padding: EdgeInsets.all(context.space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fast entry',
                    style: context.type.bodyStrong.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: context.space.xs),
                  Text(
                    'Guest login opens the lobby.',
                    style: context.type.body.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                      height: 1.35,
                    ),
                  ),
                  SizedBox(height: context.space.sm),
                  Wrap(
                    spacing: context.space.xs,
                    runSpacing: context.space.xs,
                    children: const [
                      _HeroChip(label: 'Guest', dark: true),
                      _HeroChip(label: 'Rooms', dark: true),
                      _HeroChip(label: 'Wallet', dark: true),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _floatingMetricCard(
    BuildContext context, {
    required String title,
    required String value,
  }) {
    return Container(
      padding: EdgeInsets.all(context.space.sm),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(context.radii.lg),
        border: Border.all(
          color: AppTheme.goldButtonBottom.withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: context.type.label.copyWith(
              color: AppTheme.goldButtonTop,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: context.space.xxs),
          Text(
            value,
            style: context.type.bodyStrong.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsStrip(BuildContext context) {
    final cards = [
      _statTile(context, value: '15+', label: 'Games'),
      _statTile(context, value: '2–4', label: 'Players'),
      _statTile(context, value: 'Guest', label: 'Entry'),
      _statTile(context, value: 'Live', label: 'Wallet'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 920) {
          return Row(
            children: [
              Expanded(child: cards[0]),
              SizedBox(width: context.space.sm),
              Expanded(child: cards[1]),
              SizedBox(width: context.space.sm),
              Expanded(child: cards[2]),
              SizedBox(width: context.space.sm),
              Expanded(child: cards[3]),
            ],
          );
        }
        return Column(
          children: [
            Row(
              children: [
                Expanded(child: cards[0]),
                SizedBox(width: context.space.sm),
                Expanded(child: cards[1]),
              ],
            ),
            SizedBox(height: context.space.sm),
            Row(
              children: [
                Expanded(child: cards[2]),
                SizedBox(width: context.space.sm),
                Expanded(child: cards[3]),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _statTile(
    BuildContext context, {
    required String value,
    required String label,
  }) {
    return SurfaceCard(
      padding: EdgeInsets.all(context.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: context.type.sectionTitle.copyWith(
              color: AppTheme.primaryColor,
              fontWeight: FontWeight.w900,
              fontSize: 26,
            ),
          ),
          SizedBox(height: context.space.xxs),
          Text(
            label,
            style: context.type.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGamesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Games'),
        SizedBox(height: context.space.sm),
        Text(
          'Play solo demos instantly. Live lobby titles shown below require guest access or SSO to enter.',
          style: context.type.body.copyWith(
            color: context.colors.textSecondary,
            height: 1.5,
          ),
        ),
        SizedBox(height: context.space.md),
        _buildGameCategoryRow(
          context,
          label: 'SOLO DEMOS',
          games: _soloGames,
        ),
        SizedBox(height: context.space.lg),
        _buildGameCategoryRow(
          context,
          label: 'LOBBY GAMES',
          games: const [
            _GamePreview(
              title: 'Target Strike',
              tagline: 'Closest number.',
              imagePath: 'assets/images/digit_dash_bg.png',
            ),
            _GamePreview(
              title: 'Parity Clash',
              tagline: 'Odd or even.',
              imagePath: 'assets/images/dual_dimension_flip_bg.png',
            ),
            _GamePreview(
              title: 'Dice Duel',
              tagline: 'Highest roll.',
              imagePath: 'assets/images/neon_rise_bg.png',
            ),
            _GamePreview(
              title: 'Secret Bid',
              tagline: 'Unique bid.',
              imagePath: 'assets/images/neon_perimeter_bg.png',
            ),
          ],
        ),
        SizedBox(height: context.space.lg),
        Center(
          child: PrimaryButton(
            label: 'Open lobby',
            onPressed: () => _openAuth(context),
          ),
        ),
        SizedBox(height: context.space.lg),
        _buildLiveFeedSection(context),
      ],
    );
  }

  Widget _buildGameCategoryRow(
    BuildContext context, {
    required String label,
    required List<_GamePreview> games,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: EdgeInsets.only(bottom: context.space.sm),
          padding: EdgeInsets.symmetric(
            horizontal: context.space.sm,
            vertical: context.space.xxs,
          ),
          decoration: BoxDecoration(
            color: AppTheme.primaryColor,
            borderRadius: BorderRadius.circular(context.radii.pill),
          ),
          child: Text(
            label,
            style: context.type.label.copyWith(
              color: AppTheme.goldText,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0,
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth >= 1040
                ? 4
                : constraints.maxWidth >= 680
                ? 2
                : 1;
            final itemWidth =
                (constraints.maxWidth -
                    context.space.sm * (crossAxisCount - 1)) /
                crossAxisCount;

            return Wrap(
              spacing: context.space.sm,
              runSpacing: context.space.sm,
              children: games
                  .map(
                    (g) => SizedBox(
                      width: itemWidth,
                      child: _gamePreviewCard(context, g),
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }

  Widget _gamePreviewCard(BuildContext context, _GamePreview game) {
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.radii.lg),
        child: Stack(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(game.imagePath, fit: BoxFit.cover),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.82),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: context.space.sm,
              left: context.space.sm,
              child: TagBadge(
                label: game.demoPlayable ? 'DEMO' : 'LOBBY',
                backgroundColor: AppTheme.backgroundDark,
                foregroundColor: AppTheme.primaryColor,
              ),
            ),
            Positioned(
              left: context.space.sm,
              right: context.space.sm,
              bottom: context.space.sm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    game.title,
                    style: context.type.bodyStrong.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: context.space.xxs),
                  Text(
                    game.tagline,
                    style: context.type.label.copyWith(
                      color: Colors.white.withValues(alpha: 0.8),
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: context.space.sm),
                  if (game.demoPlayable)
                    PrimaryButton(
                      expanded: true,
                      label: 'Play demo',
                      onPressed: () => _launchGame(context, game),
                    )
                  else
                    SecondaryButton(
                      expanded: true,
                      label: 'Sign in',
                      onPressed: () => _openAuth(context),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiveFeedSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Live feed'),
        SizedBox(height: context.space.sm),
        SurfaceCard(
          padding: EdgeInsets.all(context.space.md),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Latest outcomes',
                    style: context.type.bodyStrong.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  Text(
                    'Updated now',
                    style: context.type.label.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: context.space.md),
              Column(
                children: [
                  _feedRow(context, 'Neon Rise', '+3.2%', 'WIN'),
                  SizedBox(height: context.space.sm),
                  _feedRow(context, 'Parity Clash', '-1.8%', 'LOSS'),
                  SizedBox(height: context.space.sm),
                  _feedRow(context, 'Target Strike', '+2.5%', 'WIN'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _feedRow(BuildContext context, String game, String result, String status) {
    return Row(
      children: [
        Expanded(
          child: Text(
            game,
            style: context.type.bodyStrong.copyWith(
              color: context.colors.textPrimary,
            ),
          ),
        ),
        Text(
          result,
          style: context.type.bodyStrong.copyWith(
            color: status == 'WIN' ? AppTheme.primaryColor : context.colors.textSecondary,
          ),
        ),
        SizedBox(width: context.space.sm),
        TagBadge(
          label: status,
          backgroundColor: context.colors.bgSurface,
          foregroundColor: status == 'WIN' ? AppTheme.primaryColor : context.colors.textSecondary,
        ),
      ],
    );
  }

  Widget _buildFeaturesSection(BuildContext context) {
    final cards = [
      _infoCard(
        context,
        icon: Icons.bolt_rounded,
        title: 'Fast Start',
        body: 'Guest entry in seconds.',
      ),
      _infoCard(
        context,
        icon: Icons.groups_2_outlined,
        title: 'Rooms',
        body: 'Public or private play.',
      ),
      _infoCard(
        context,
        icon: Icons.account_balance_wallet_outlined,
        title: 'Wallet',
        body: 'Live balance updates.',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Built for Play'),
        SizedBox(height: context.space.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 920;
            if (wide) {
              return Row(
                children: [
                  Expanded(child: cards[0]),
                  SizedBox(width: context.space.md),
                  Expanded(child: cards[1]),
                  SizedBox(width: context.space.md),
                  Expanded(child: cards[2]),
                ],
              );
            }
            return Column(
              children: [
                cards[0],
                SizedBox(height: context.space.sm),
                cards[1],
                SizedBox(height: context.space.sm),
                cards[2],
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildAccessSection(BuildContext context) {
    return SurfaceCard(
      padding: EdgeInsets.all(context.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Access'),
          SizedBox(height: context.space.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 920;
              final launchCard = SurfaceCard(
                backgroundColor: AppTheme.goldButtonTop.withValues(alpha: 0.18),
                padding: EdgeInsets.all(context.space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Web App',
                      style: context.type.bodyStrong.copyWith(
                        fontWeight: FontWeight.w800,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    SizedBox(height: context.space.xxs),
                    Text(
                      'Open the lobby now.',
                      style: context.type.body.copyWith(
                        color: context.colors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                    SizedBox(height: context.space.md),
                    PrimaryButton(
                      expanded: true,
                      label: 'Launch',
                      onPressed: () => _openAuth(context),
                    ),
                  ],
                ),
              );
              final storeColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _storeButton(
                    context,
                    icon: Icons.apple,
                    title: 'iPhone',
                    subtitle: 'App Store',
                    onTap: () => _openExternal(_iosUrl),
                  ),
                  SizedBox(height: context.space.sm),
                  _storeButton(
                    context,
                    icon: Icons.android,
                    title: 'Android',
                    subtitle: 'Play Store',
                    onTap: () => _openExternal(_androidUrl),
                  ),
                ],
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    launchCard,
                    SizedBox(height: context.space.md),
                    storeColumn,
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 11, child: launchCard),
                  SizedBox(width: context.space.md),
                  Expanded(flex: 9, child: storeColumn),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _storeButton(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return SurfaceCard(
      backgroundColor: context.colors.bgSurface,
      child: InkWell(
        borderRadius: BorderRadius.circular(context.radii.lg),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(context.space.md),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  borderRadius: BorderRadius.circular(context.radii.lg),
                  border: Border.all(color: AppTheme.goldButtonBottom),
                ),
                child: Icon(icon, color: AppTheme.goldText),
              ),
              SizedBox(width: context.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.type.bodyStrong),
                    Text(
                      subtitle,
                      style: context.type.body.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new,
                size: 16,
                color: context.colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
  }) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: AppTheme.goldButtonTop,
            child: Icon(icon, color: AppTheme.goldText),
          ),
          SizedBox(height: context.space.sm),
          Text(title, style: context.type.bodyStrong),
          SizedBox(height: context.space.xxs),
          Text(
            body,
            style: context.type.body.copyWith(
              color: context.colors.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  void _openAuth(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AuthScreen()));
  }

  void _launchGame(BuildContext context, _GamePreview game) {
    if (!game.demoPlayable || game.gameScreen == null) {
      _openAuth(context);
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => game.gameScreen!),
    );
  }

  void _launchFirstDemo(BuildContext context) {
    final demoGame = _soloGames.firstWhere(
      (game) => game.demoPlayable,
      orElse: () => _soloGames.first,
    );
    _launchGame(context, demoGame);
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open $url')));
    }
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final contextRef = key.currentContext;
    if (contextRef == null) {
      return;
    }
    await Scrollable.ensureVisible(
      contextRef,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOut,
      alignment: 0.04,
    );
  }
}

class _GamePreview {
  const _GamePreview({
    required this.title,
    required this.tagline,
    required this.imagePath,
    this.demoPlayable = false,
    this.gameScreen,
  });

  final String title;
  final String tagline;
  final String imagePath;
  final bool demoPlayable;
  final Widget? gameScreen;
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.label, this.dark = false});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.space.sm,
        vertical: context.space.xs,
      ),
      decoration: BoxDecoration(
        color: dark
            ? AppTheme.backgroundDark.withValues(alpha: 0.4)
            : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(context.radii.pill),
        border: Border.all(
          color: AppTheme.borderDark.withValues(
            alpha: dark ? 0.42 : 0.32,
          ),
        ),
      ),
      child: Text(
        label,
        style: context.type.label.copyWith(
          color: dark ? Colors.white : AppTheme.primaryColor,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}
