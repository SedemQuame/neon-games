import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/game_service.dart';
import '../services/models.dart';
import '../services/session_manager.dart';
import '../utils/format.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_shell.dart';
import '../widgets/casino_top_nav.dart';
import '../widgets/filter_chip_row.dart';
import '../widgets/game_card_tile.dart';
import '../widgets/section_header.dart';
import 'deposit_screen.dart';
import 'game_screens/digit_dash_screen.dart';
import 'game_screens/dual_dimension_flip_screen.dart';
import 'game_screens/mini_roulette_screen.dart';
import 'game_screens/multiplayer_arena_screen.dart';
import 'game_screens/multiplayer_game_catalog.dart';
import 'game_screens/neon_perimeter_screen.dart';
import 'game_screens/neon_rise_screen.dart';
import 'game_screens/aviator_boom_crash_screen.dart';
import 'game_screens/spin_bottle_screen.dart';
import 'game_screens/velocity_vector_screen.dart';
import 'shared_bottom_nav.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  WalletBalance? _balance;
  StreamSubscription<GameEvent>? _gameEventsSub;
  Timer? _liveStatsTimer;
  int? _livePlayers;
  Map<String, int> _gameStats = {};
  bool _loadingBalance = false;
  bool _showAllGames = false;
  bool _handledInitialArenaLink = false;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    _gameEventsSub = context.read<SessionManager>().gameEvents.listen(
      _handleGameEvent,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshBalance();
      _refreshLiveStats();
      _liveStatsTimer = Timer.periodic(
        const Duration(seconds: 30),
        (_) => _refreshLiveStats(),
      );
      _openArenaLinkIfPresent();
    });
  }

  @override
  void dispose() {
    _liveStatsTimer?.cancel();
    _gameEventsSub?.cancel();
    super.dispose();
  }

  void _handleGameEvent(GameEvent event) {
    int? livePlayers;
    Map<String, int>? gameStats;
    if (event is LiveStatsEvent) {
      livePlayers = event.livePlayers;
      gameStats = event.gameStats;
    } else if (event is GameConnectedEvent) {
      livePlayers = event.livePlayers ?? 1;
    }
    if (livePlayers == null || !mounted) {
      return;
    }
    setState(() {
      _livePlayers = livePlayers;
      if (gameStats != null) {
        _gameStats = gameStats;
      }
    });
  }

  Future<void> _refreshLiveStats() async {
    final session = context.read<SessionManager>();
    if (!session.isAuthenticated) {
      if (mounted) {
        setState(() => _livePlayers = 0);
      }
      return;
    }
    try {
      await session.ensureGameSocket();
      if (mounted && _livePlayers == null) {
        setState(() => _livePlayers = 1);
      }
      session.gameService.requestLiveStats();
    } catch (_) {
      // Keep the last known count if the socket is temporarily unavailable.
    }
  }

  Future<void> _refreshBalance() async {
    final session = context.read<SessionManager>();
    if (!session.isAuthenticated) {
      return;
    }

    setState(() => _loadingBalance = true);
    try {
      final latest = await session.refreshBalance();
      if (!mounted) {
        return;
      }
      setState(() => _balance = latest);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load balance: $error')));
    } finally {
      if (mounted) {
        setState(() => _loadingBalance = false);
      }
    }
  }

  Future<void> _openActivity(Widget screen) {
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.025),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  void _openArenaLinkIfPresent() {
    if (_handledInitialArenaLink) {
      return;
    }
    final query = Uri.base.queryParameters;
    final roomCode = query['room']?.trim().toUpperCase();
    final gameKey = query['game']?.trim().toUpperCase();
    if (roomCode == null || roomCode.isEmpty) {
      return;
    }

    _handledInitialArenaLink = true;
    _openActivity(
      MultiplayerArenaScreen(
        initialGameKey: gameKey,
        initialRoomCode: roomCode,
      ),
    );
  }

  void _openMultiplayerGame(String gameKey) {
    _openActivity(MultiplayerArenaScreen(initialGameKey: gameKey));
  }

  @override
  Widget build(BuildContext context) {
    final allGames = _games(context);
    final soloGamesAll = allGames
        .where((game) => game.mode == _GameMode.solo)
        .toList();
    final multiplayerGamesAll = allGames
        .where((game) => game.mode == _GameMode.multiplayer)
        .toList();
    final hasOverflow =
        soloGamesAll.length > 10 || multiplayerGamesAll.length > 10;
    final soloGames = _showAllGames
        ? soloGamesAll
        : soloGamesAll.take(10).toList();
    final multiplayerGames = _showAllGames
        ? multiplayerGamesAll
        : multiplayerGamesAll.take(10).toList();
    final showSolo = _selectedCategory != 'Multiplayer';
    final showMultiplayer =
        _selectedCategory != 'Solo' && _selectedCategory != 'Featured';

    return CasinoScaffold(
      useNarrowLayout: true,
      appBar: const CasinoTopNav(title: 'Glory Grid'),
      bottomNavigationBar: const SharedBottomNav(currentIndex: 0),
      maxContentWidth: 1120,
      body: RefreshIndicator(
        onRefresh: _refreshBalance,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= 900;
            final content = ListView(
              padding: isDesktop
                  ? EdgeInsets.fromLTRB(
                      context.space.lg,
                      context.space.lg,
                      context.space.lg,
                      96,
                    )
                  : EdgeInsets.only(top: context.space.md, bottom: 96),
              children: [
                _buildHeroSummary(),
                SizedBox(height: context.space.md),
                FilterChipRow(
                  options: const ['All', 'Featured', 'Solo', 'Multiplayer'],
                  selected: _selectedCategory,
                  onSelected: (value) =>
                      setState(() => _selectedCategory = value),
                ),
                SizedBox(height: context.space.md),
                SectionHeader(
                  title: 'Featured',
                  actionLabel: hasOverflow
                      ? (_showAllGames ? 'Show less' : 'See all')
                      : null,
                  onAction: hasOverflow
                      ? () => setState(() => _showAllGames = !_showAllGames)
                      : null,
                ),
                SizedBox(height: context.space.md),
                if (allGames.isNotEmpty)
                  _buildFeaturedGamePanel(allGames.first),
                if (showSolo) ...[
                  SizedBox(height: context.space.lg),
                  _buildModeSection(
                    title: 'Solo Games',
                    subtitle: 'Solo rounds',
                    icon: Icons.person,
                    games: soloGames,
                  ),
                ],
                if (showMultiplayer) ...[
                  SizedBox(height: context.space.lg),
                  _buildModeSection(
                    title: 'Multiplayer Games',
                    subtitle: 'Rooms',
                    icon: Icons.groups_2_outlined,
                    games: multiplayerGames,
                    intro: _buildMultiplayerSpotlight(),
                  ),
                ],
              ],
            );
            if (!isDesktop) {
              return content;
            }
            return Container(
              margin: EdgeInsets.symmetric(vertical: context.space.lg),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: context.colors.bgSurface.withValues(alpha: 0.24),
                borderRadius: BorderRadius.circular(context.radii.xl),
                border: Border.all(
                  color: context.colors.border.withValues(alpha: 0.72),
                ),
              ),
              child: content,
            );
          },
        ),
      ),
    );
  }

  Widget _buildModeSection({
    required String title,
    required String subtitle,
    required IconData icon,
    required List<_GameConfig> games,
    Widget? intro,
  }) {
    if (games.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: context.colors.primary),
            SizedBox(width: context.space.xs),
            Text(
              title,
              style: context.type.bodyStrong.copyWith(
                color: context.colors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        SizedBox(height: context.space.xs),
        Text(
          subtitle,
          style: context.type.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        if (intro != null) ...[SizedBox(height: context.space.md), intro],
        SizedBox(height: context.space.md),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final columns = _columnsForWidth(width);
            final aspectRatio = 0.75;
            return GridView.builder(
              itemCount: games.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: context.space.md,
                mainAxisSpacing: context.space.md,
                childAspectRatio: aspectRatio,
              ),
              itemBuilder: (context, index) {
                final game = games[index];
                return GameCardTile(
                  title: game.title,
                  subtitle: game.subtitle,
                  imagePath: game.image,
                  tag: game.tag,
                  minStake: game.minStake,
                  playersCount: game.playersCount,
                  onPlayDemo: () {
                    // Demo mode from dashboard
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Demo mode starting...')),
                    );
                    game.onTap();
                  },
                  onPlayReal: game.onTap,
                  highlighted: game.mode == _GameMode.multiplayer,
                  compact: false,
                );
              },
            );
          },
        ),
      ],
    );
  }

  int _columnsForWidth(double width) {
    if (width >= 1200) return 4;
    if (width >= 860) return 3;
    return 2; // Mobile users also get 2 columns to keep cards vertical
  }

  Widget _buildMultiplayerSpotlight() {
    return SurfaceCard(
      padding: EdgeInsets.all(context.space.md),
      backgroundColor: context.colors.primary.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
                  ),
                  borderRadius: BorderRadius.circular(context.radii.lg),
                  border: Border.all(color: AppTheme.goldButtonBottom),
                ),
                child: const Icon(
                  Icons.groups_2_outlined,
                  color: AppTheme.goldText,
                ),
              ),
              SizedBox(width: context.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Room Play',
                      style: context.type.bodyStrong.copyWith(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: context.space.xxs),
                    Text(
                      'Public and private rooms.',
                      style: context.type.body.copyWith(
                        color: context.colors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: context.space.sm),
          Wrap(
            spacing: context.space.xs,
            runSpacing: context.space.xs,
            children: const [
              _SpotlightPill(label: 'Public Rooms'),
              _SpotlightPill(label: 'Invites'),
              _SpotlightPill(label: '2-4 Players'),
              _SpotlightPill(label: '85% Pool'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFeaturedGamePanel(_GameConfig game) {
    return SurfaceCard(
      padding: EdgeInsets.all(context.space.sm),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(context.radii.lg),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.asset(game.image, fit: BoxFit.cover),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.9),
                      Colors.black.withValues(alpha: 0.18),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: context.space.md,
                left: context.space.md,
                child: const _LivePill(label: 'Featured Game'),
              ),
              Positioned(
                left: context.space.md,
                right: context.space.md,
                bottom: context.space.md,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      game.title,
                      style: context.type.heroTitle.copyWith(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: context.space.xs),
                    Text(
                      game.subtitle,
                      style: context.type.body.copyWith(
                        color: Colors.white.withValues(alpha: 0.86),
                      ),
                    ),
                    SizedBox(height: context.space.md),
                    Row(
                      children: [
                        _MetricPill(
                          label: 'Entry',
                          value: formatCurrency(game.minStake),
                        ),
                        SizedBox(width: context.space.xs),
                        _MetricPill(
                          label: 'Mode',
                          value: game.mode == _GameMode.solo ? 'Solo' : 'Room',
                        ),
                        const Spacer(),
                        PrimaryButton(
                          label: 'Play',
                          icon: Icons.play_arrow_rounded,
                          onPressed: game.onTap,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSummary() {
    final available = _balance?.availableUsd ?? 0;
    final liveLabel = _livePlayers == null ? 'Live ...' : '$_livePlayers Live';

    return SurfaceCard(
      padding: EdgeInsets.all(context.space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(context.radii.pill),
                  border: Border.all(
                    color: context.colors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(Icons.person, color: context.colors.primary),
              ),
              SizedBox(width: context.space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total Balance',
                      style: context.type.label.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                    SizedBox(height: context.space.xxs),
                    Text(
                      _loadingBalance
                          ? 'Loading...'
                          : formatCurrency(available),
                      style: context.type.heroTitle.copyWith(
                        color: context.colors.textPrimary,
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: context.space.xs),
                    Wrap(
                      spacing: context.space.xs,
                      runSpacing: context.space.xs,
                      children: [
                        _LivePill(label: liveLabel),
                      ],
                    ),
                  ],
                ),
              ),
              PrimaryButton(
                label: 'Deposit',
                icon: Icons.add,
                onPressed: () {
                  _openActivity(const DepositScreen());
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_GameConfig> _games(BuildContext context) {
    return [
      _GameConfig(
        title: 'Even or Odd',
        subtitle: 'Odd or even',
        image: 'assets/images/dual_dimension_flip_bg.png',
        tag: 'NEW',
        minStake: 1,
        playersCount: _gameStats['dual_dimension_flip'] ?? 0,
        mode: _GameMode.solo,
        onTap: () {
          _openActivity(const DualDimensionFlipScreen());
        },
      ),
      _GameConfig(
        title: 'Digit Dash',
        subtitle: 'Last digit',
        image: 'assets/images/digit_dash_bg.png',
        tag: 'POPULAR',
        minStake: 1,
        playersCount: _gameStats['digit_dash'] ?? 0,
        mode: _GameMode.solo,
        onTap: () {
          _openActivity(const DigitDashScreen());
        },
      ),
      _GameConfig(
        title: 'Mini Roulette',
        subtitle: 'Color or digit',
        image: 'assets/images/screen_14.png',
        tag: 'NEW',
        minStake: 1,
        playersCount: _gameStats['mini_roulette'] ?? 0,
        mode: _GameMode.solo,
        onTap: () {
          _openActivity(const MiniRouletteScreen());
        },
      ),

      _GameConfig(
        title: 'Velocity Vector',
        subtitle: 'Momentum',
        image: 'assets/images/velocity_vector_bg.png',
        tag: 'HOT',
        minStake: 2,
        playersCount: _gameStats['velocity_vector'] ?? 0,
        mode: _GameMode.solo,
        onTap: () {
          _openActivity(const VelocityVectorScreen());
        },
      ),
      _GameConfig(
        title: 'Neon Perimeter',
        subtitle: 'Boundary break',
        image: 'assets/images/neon_perimeter_bg.png',
        tag: 'TRENDING',
        minStake: 1,
        playersCount: _gameStats['neon_perimeter'] ?? 0,
        mode: _GameMode.solo,
        onTap: () {
          _openActivity(const NeonPerimeterScreen());
        },
      ),
      _GameConfig(
        title: 'Aviator Boom/Crash',
        subtitle: 'Boom or crash',
        image: 'assets/images/screen_11.png',
        tag: 'TRENDING',
        minStake: 1,
        playersCount: _gameStats['aviator_boom_crash'] ?? 0,
        mode: _GameMode.solo,
        onTap: () {
          _openActivity(const AviatorBoomCrashScreen());
        },
      ),
      _GameConfig(
        title: 'Spin the Bottle',
        subtitle: 'Left or right',
        image: 'assets/images/screen_12.png',
        tag: 'NEW',
        minStake: 1,
        playersCount: _gameStats['spin_bottle'] ?? 0,
        mode: _GameMode.solo,
        onTap: () {
          _openActivity(const SpinBottleScreen.solo());
        },
      ),
      ...multiplayerGameCatalog.map(_multiplayerGameConfig),
    ];
  }

  _GameConfig _multiplayerGameConfig(MultiplayerGameDefinition game) {
    return _GameConfig(
      title: game.title,
      subtitle: game.modeSummary,
      image: game.imagePath,
      tag: game.cardTag,
      minStake: game.minStake,
      playersCount: _gameStats[game.key] ?? 0,
      mode: _GameMode.multiplayer,
      onTap: () {
        _openMultiplayerGame(game.key);
      },
    );
  }
}

enum _GameMode { solo, multiplayer }

class _GameConfig {
  const _GameConfig({
    required this.title,
    required this.subtitle,
    required this.image,
    required this.tag,
    required this.minStake,
    this.playersCount = 0,
    required this.mode,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String image;
  final String tag;
  final num minStake;
  final int playersCount;
  final _GameMode mode;
  final VoidCallback onTap;
}

class _SpotlightPill extends StatelessWidget {
  const _SpotlightPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.space.sm,
        vertical: context.space.xs,
      ),
      decoration: BoxDecoration(
        color: context.colors.bgCard,
        borderRadius: BorderRadius.circular(context.radii.pill),
        border: Border.all(
          color: context.colors.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        label,
        style: context.type.label.copyWith(
          color: context.colors.textPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.space.sm,
        vertical: context.space.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(context.radii.pill),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: context.type.label.copyWith(
              color: Colors.white.withValues(alpha: 0.68),
              fontSize: 11,
            ),
          ),
          SizedBox(width: context.space.xs),
          Text(
            value,
            style: context.type.label.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _LivePill extends StatelessWidget {
  const _LivePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.space.sm,
        vertical: context.space.xxs,
      ),
      decoration: BoxDecoration(
        color: context.colors.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(context.radii.pill),
        border: Border.all(
          color: context.colors.primary.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: context.colors.primary,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: context.space.xs),
          Text(
            label,
            style: context.type.label.copyWith(
              color: context.colors.primary,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
