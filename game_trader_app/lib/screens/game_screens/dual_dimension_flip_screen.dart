import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/game_service.dart';
import '../../services/session_manager.dart';
import '../../utils/balance_guard.dart';
import '../../utils/format.dart';
import '../../utils/game_round_mixin.dart';
import '../../widgets/game_message.dart';
import '../../widgets/wallet_balance_chip.dart';

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
  double stakeAmount = 10.00;
  List<int> recentTicks = [8, 3, 2, 0, 7];
  int currentNumber = 8;

  GamePhase gamePhase = GamePhase.idle;
  UserPick? userPick;
  bool? userWon;
  bool _isPlacing = false;
  String _statusMessage = 'Choose EVEN or ODD';
  final Random _rng = Random();

  late AnimationController _pulseController;
  late AnimationController _overlayController;
  late Animation<double> _overlayFade;
  late Animation<double> _overlayScale;

  Timer? _shuffleTimer;

  @override
  void initState() {
    super.initState();
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
    final canPlay = await BalanceGuard.ensurePlayableStake(
      context,
      stakeAmount,
    );
    if (!canPlay) return;

    setState(() {
      userPick = pick;
      gamePhase = GamePhase.shuffling;
      _isPlacing = true;
      _statusMessage = pick == UserPick.even
          ? 'Calibrating EVEN core...'
          : 'Calibrating ODD core...';
    });

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
        _statusMessage = 'Choose EVEN or ODD';
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
      recentTicks = [resultNumber, ...recentTicks.take(4)];
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

  String get _coreLabel {
    if (gamePhase == GamePhase.idle) return 'EVEN';
    if (gamePhase == GamePhase.shuffling) return '—';
    return currentNumber % 2 == 0 ? 'EVEN' : 'ODD';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF100B16),
      body: Stack(
        children: [
          // Background Split
          Column(
            children: [
              Expanded(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0xFFFDFBFF), Color(0xFFEBDDFF)],
                    ),
                  ),
                ),
              ),
              Expanded(child: Container(color: const Color(0xFF100B16))),
            ],
          ),

          // Main Content
          SafeArea(
            child: Column(
              children: [
                // App Bar
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          color: Color(0xFF100B16),
                          size: 24,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            const Text(
                              'LIVE BALANCE',
                              style: TextStyle(
                                color: Color(0xFF6B7280),
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Consumer<SessionManager>(
                              builder: (context, session, _) {
                                return Text(
                                  formatCurrency(
                                    session.cachedBalance?.availableUsd,
                                  ),
                                  style: const TextStyle(
                                    color: Color(0xFF100B16),
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const WalletBalanceChip(
                        margin: EdgeInsets.only(left: 8),
                        backgroundColor: Color(0xFFede9fe),
                        borderColor: Color(0xFFddd6fe),
                        iconColor: Color(0xFF6B21A8),
                        textColor: Color(0xFF6B21A8),
                      ),
                    ],
                  ),
                ),

                // Top: EVEN label
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'THE CORE',
                        style: TextStyle(
                          color: Color(0xFF9333EA),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _coreLabel,
                              key: ValueKey(_coreLabel),
                              style: const TextStyle(
                                color: Color(0xFF7E22CE),
                                fontSize: 56,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -2.0,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.brightness_high,
                            color: Color(0xFF7E22CE),
                            size: 36,
                          ),
                        ],
                      ),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),

                // Bottom section
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      const SizedBox(height: 70),

                      // EVEN / ODD Pick Buttons
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
                            const SizedBox(width: 12),
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

                      const SizedBox(height: 28),

                      // Payout info
                      const Text(
                        'PAYOUT: 9.2x  •  RECENT TRANSITIONS',
                        style: TextStyle(
                          color: Color(0xFF6B7280),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2.0,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Recent Tick Bubbles
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: recentTicks.map((tick) {
                          bool isEven = tick % 2 == 0;
                          return Container(
                            width: 32,
                            height: 32,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: isEven
                                  ? const Color(0xFF9333EA)
                                  : const Color(0xFF1F2937),
                              shape: BoxShape.circle,
                              border: isEven
                                  ? null
                                  : Border.all(color: const Color(0xFF374151)),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              tick.toString(),
                              style: TextStyle(
                                color: isEven
                                    ? Colors.white
                                    : const Color(0xFF9CA3AF),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      const SizedBox(height: 16),
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Stake Box
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF231E33),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(color: const Color(0xFF38334E)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'STAKE',
                                    style: TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1.0,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '\$${stakeAmount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  _buildCircledIcon(Icons.remove, () {
                                    if (gamePhase == GamePhase.idle) {
                                      setState(() {
                                        if (stakeAmount > 1) stakeAmount -= 1;
                                      });
                                    }
                                  }),
                                  const SizedBox(width: 8),
                                  _buildCircledIcon(Icons.add, () {
                                    if (gamePhase == GamePhase.idle) {
                                      setState(() => stakeAmount += 1);
                                    }
                                  }),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Center Floating Orb
          Center(
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
                      colors: [Colors.white, Color(0xFFEBDDFF)],
                      stops: [0.4, 1.0],
                    ),
                    border: Border.all(
                      color: const Color(0xFF7E22CE).withValues(alpha: 0.6),
                      width: 4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7E22CE).withValues(alpha: glow),
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
                    shadows: [Shadow(color: Color(0xFFC084FC), blurRadius: 20)],
                  ),
                ),
              ),
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
                                colors: [Color(0xFF9333EA), Color(0xFF6D28D9)],
                              ),
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFF9333EA,
                                  ).withValues(alpha: 0.5),
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
                                color: Colors.white,
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
    final isSelected = userPick == pick;
    final isDisabled = gamePhase != GamePhase.idle || _isPlacing;
    return GestureDetector(
      onTap: isDisabled ? null : () => _onPickTapped(pick),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 64,
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFF9333EA), Color(0xFF6D28D9)],
                )
              : null,
          color: isSelected ? null : const Color(0xFF231E33),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFA855F7)
                : const Color(0xFF38334E),
            width: 2,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF9333EA).withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: -4,
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.white : const Color(0xFF6B7280),
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF6B7280),
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 2.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCircledIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Color(0xFF38354A),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
