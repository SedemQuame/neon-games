import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../widgets/game_scaffold.dart';
import '../../services/session_manager.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../services/game_service.dart';
import '../../utils/balance_guard.dart';
import '../../utils/game_round_mixin.dart';
import '../../utils/play_mode.dart';
import '../../widgets/game_activity_app_bar.dart';
import '../../widgets/game_message.dart';
import '../../widgets/play_mode_toggle.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/stake_adjuster.dart';

class DualDimensionFlipScreen extends StatefulWidget {
  const DualDimensionFlipScreen({super.key});

  @override
  State<DualDimensionFlipScreen> createState() =>
      _DualDimensionFlipScreenState();
}

enum GamePhase { idle, shuffling, result }

enum UserPick { even, odd }

class _DualDimensionFlipScreenState extends State<DualDimensionFlipScreen>
    with TickerProviderStateMixin, GameRoundMixin<DualDimensionFlipScreen> {
  double stakeAmount = BalanceGuard.minStakeUsd;
  PlayMode _playMode = PlayMode.demo;
  int currentNumber = 8;

  GamePhase gamePhase = GamePhase.idle;
  UserPick? userPick;
  bool? userWon;
  bool _isPlacing = false;
  String _statusMessage = 'Choose Even or Odd';
  final Random _rng = Random();

  late AnimationController _pulseController;
  late AnimationController _overlayController;
  late Animation<double> _overlayFade;
  late Animation<double> _overlayScale;

  Timer? _shuffleTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SessionManager>().gameService.viewGame('dual_dimension_flip');
      }
    });
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _overlayFade = CurvedAnimation(
      parent: _overlayController,
      curve: Curves.easeOut,
    );
    _overlayScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _overlayController, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _overlayController.dispose();
    _shuffleTimer?.cancel();
    super.dispose();
  }

  Future<void> _onPickTapped(UserPick pick) async {
    if (gamePhase != GamePhase.idle || _isPlacing) return;
    final canPlay = await ensureStakeForPlayMode(
      context,
      _playMode,
      stakeAmount,
    );
    if (!canPlay) return;
    if (!mounted) return;

    setState(() {
      userPick = pick;
      gamePhase = GamePhase.shuffling;
      _isPlacing = true;
      _statusMessage = pick == UserPick.even
          ? 'Calibrating EVEN core...'
          : 'Calibrating ODD core...';
    });

    if (_playMode.isDemo) {
      final session = context.read<SessionManager>();
      if (!session.deductDemoBalance(stakeAmount)) {
        showGameMessage(context, 'Insufficient demo balance.');
        return;
      }
      setState(() {
        _isPlacing = false;
        _statusMessage = 'Demo round running...';
      });
      _startShuffleLoop();
      showGameMessage(context, 'Demo round. Wallet unchanged.');
      await Future<void>.delayed(const Duration(milliseconds: 950));
      if (!mounted || gamePhase != GamePhase.shuffling) return;
      final demoRes = buildDemoGameResult(
          gameType: 'DUAL_DIMENSION_FLIP',
          stakeUsd: stakeAmount,
          payoutMultiplier: 1.95,
          winChance: 0.49,
        );
      if (demoRes.winAmountUsd > 0) {
        context.read<SessionManager>().addDemoWinnings(demoRes.winAmountUsd);
      }
      onGameResult(demoRes);
      return;
    }

    try {
      await placeGameBet(
        gameType: 'DUAL_DIMENSION_FLIP',
        stakeUsd: stakeAmount,
        prediction: _buildPrediction(pick),
      );
      if (!mounted) return;
      setState(() {
        _isPlacing = false;
        _statusMessage = 'Listening for a response...';
      });
      _startShuffleLoop();
    } on GameSocketException catch (err) {
      if (!mounted) return;
      _resetToIdle(err.message);
      showGameMessage(context, err.message);
    } catch (err) {
      if (!mounted) return;
      _resetToIdle('Bet failed');
      showGameMessage(context, 'Bet failed: $err');
    }
  }

  void _onPlayAgain() {
    _overlayController.reverse().then((_) {
      setState(() {
        gamePhase = GamePhase.idle;
        userPick = null;
        userWon = null;
        _isPlacing = false;
        _statusMessage = 'Choose Even or Odd';
      });
    });
  }

  Map<String, dynamic> _buildPrediction(UserPick pick) {
    final isEven = pick == UserPick.even;
    const ticks = 5;
    return {
      'symbol': 'R_50',
      'direction': isEven ? 'EVEN' : 'ODD',
      'derivContractType': isEven ? 'DIGITEVEN' : 'DIGITODD',
      'durationTicks': ticks,
      'duration': ticks,
      'durationUnit': 't',
    };
  }

  void _startShuffleLoop() {
    _stopShuffleLoop();
    _shuffleTimer = Timer.periodic(const Duration(milliseconds: 110), (_) {
      if (!mounted) return;
      setState(() {
        currentNumber = _rng.nextInt(10);
      });
    });
  }

  void _stopShuffleLoop() {
    _shuffleTimer?.cancel();
    _shuffleTimer = null;
  }

  void _resetToIdle(String message) {
    _stopShuffleLoop();
    if (!mounted) return;
    setState(() {
      _isPlacing = false;
      _statusMessage = message;
      gamePhase = GamePhase.idle;
      userPick = null;
      userWon = null;
    });
  }

  void _revealResult(GameResultEvent event) {
    final win = event.outcome.toUpperCase() == 'WIN';
    final wantsEven = userPick == UserPick.even;
    final parity = win ? wantsEven : !wantsEven;
    final resultNumber = _generateDigit(parity);
    _stopShuffleLoop();
    if (!mounted) return;
    setState(() {
      currentNumber = resultNumber;
      userWon = win;
      gamePhase = GamePhase.result;
      _statusMessage = win
          ? 'Core stabilized +\$${event.winAmountUsd.toStringAsFixed(2)}'
          : 'Core destabilized ${event.outcome}';
    });
    _overlayController.forward(from: 0);
  }

  int _generateDigit(bool even) {
    int value;
    do {
      value = _rng.nextInt(10);
    } while ((value % 2 == 0) != even);
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      backgroundColor: AppTheme.gameBackground,
      appBar: const GameActivityAppBar(title: 'Even or Odd'),
      bottomNavigationBar: PlayModeBottomBar(
        value: _playMode,
        enabled: gamePhase == GamePhase.idle && !_isPlacing,
        onChanged: (mode) => setState(() => _playMode = mode),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Container(color: AppTheme.gameBackground)),

          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final glow = gamePhase == GamePhase.shuffling
                            ? 0.3 + _pulseController.value * 0.4
                            : 0.3;
                        return Container(
                          width: 156,
                          height: 156,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              colors: [Color(0xFFF3F3EF), Color(0xFFD7D4CC)],
                              stops: [0.4, 1.0],
                            ),
                            border: Border.all(
                              color: const Color(
                                0xFFC9AA5C,
                              ).withValues(alpha: 0.7),
                              width: 4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(
                                  0xFFC9AA5C,
                                ).withValues(alpha: glow),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 30,
                                offset: const Offset(0, 15),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: child,
                        );
                      },
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 100),
                        transitionBuilder: (child, anim) =>
                            ScaleTransition(scale: anim, child: child),
                        child: Text(
                          currentNumber.toString(),
                          key: ValueKey(currentNumber),
                          style: const TextStyle(
                            fontSize: 84,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            shadows: [
                              Shadow(color: Color(0xFF7D776A), blurRadius: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: StakeAdjuster(
                          label: 'STAKE',
                          value: stakeAmount,
                          enabled: gamePhase == GamePhase.idle && !_isPlacing,
                          onChanged: (next) =>
                              setState(() => stakeAmount = next),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            _statusMessage,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildPickButton(
                                label: 'EVEN',
                                icon: Icons.brightness_high,
                                pick: UserPick.even,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildPickButton(
                                label: 'ODD',
                                icon: Icons.emergency,
                                pick: UserPick.odd,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // WIN / LOSE Overlay
          if (gamePhase == GamePhase.result)
            FadeTransition(
              opacity: _overlayFade,
              child: Container(
                color: Colors.black.withValues(alpha: 0.75),
                alignment: Alignment.center,
                child: ScaleTransition(
                  scale: _overlayScale,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 40),
                    padding: const EdgeInsets.all(36),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A0D2B),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: userWon == true
                            ? const Color(0xFF9333EA)
                            : const Color(0xFF6B2A5A),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              (userWon == true
                                      ? const Color(0xFF9333EA)
                                      : const Color(0xFF6B2A5A))
                                  .withValues(alpha: 0.5),
                          blurRadius: 40,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          userWon == true ? '🎯 YOU WIN!' : '💥 MISS!',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Landed on $currentNumber (${currentNumber % 2 == 0 ? "EVEN" : "ODD"})',
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          userWon == true
                              ? '+\$${(stakeAmount * 9.2).toStringAsFixed(2)}'
                              : '-\$${stakeAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            color: userWon == true
                                ? const Color(0xFFA855F7)
                                : const Color(0xFFEC4899),
                          ),
                        ),
                        const SizedBox(height: 32),
                        GestureDetector(
                          onTap: _onPlayAgain,
                          child: Container(
                            width: double.infinity,
                            height: 56,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  AppTheme.goldButtonTop,
                                  AppTheme.goldButtonBottom,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.goldButtonBottom.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 20,
                                  spreadRadius: -5,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              'PLAY AGAIN',
                              style: TextStyle(
                                color: AppTheme.goldText,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                letterSpacing: 3.0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  void onGameResult(GameResultEvent event) {
    _revealResult(event);
    final win = event.outcome.toUpperCase() == 'WIN';
    showGameMessage(
      context,
      win
          ? 'Dimension flip paid \$${event.winAmountUsd.toStringAsFixed(2)}'
          : 'Dimension flip closed as ${event.outcome}',
    );
  }

  @override
  void onBetRejected(GameBetRejected event) {
    _resetToIdle('Rejected: ${event.reason}');
    showGameMessage(context, 'Bet rejected: ${event.reason}');
  }

  @override
  void onGameError(GameErrorEvent event) {
    _resetToIdle(event.message);
    showGameMessage(context, event.message);
  }

  Widget _buildPickButton({
    required String label,
    required IconData icon,
    required UserPick pick,
  }) {
    final busy = gamePhase != GamePhase.idle || _isPlacing;
    return PressScale(
      enabled: !busy,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: busy
                ? const [AppTheme.goldDisabledTop, AppTheme.goldDisabledBottom]
                : const [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.goldButtonBottom.withValues(
              alpha: busy ? 0.4 : 0.9,
            ),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.goldButtonBottom.withValues(
                alpha: busy ? 0.08 : 0.26,
              ),
              blurRadius: 16,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: busy ? null : () => _onPickTapped(pick),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: AppTheme.goldText.withValues(alpha: busy ? 0.65 : 1),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.goldText.withValues(alpha: busy ? 0.65 : 1),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
