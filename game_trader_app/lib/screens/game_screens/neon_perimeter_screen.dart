import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../services/game_service.dart';
import '../../services/session_manager.dart';
import '../../utils/balance_guard.dart';
import '../../utils/play_mode.dart';
import '../../widgets/game_activity_app_bar.dart';
import '../../widgets/game_message.dart';
import '../../widgets/play_mode_toggle.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/stake_adjuster.dart';

class NeonPerimeterScreen extends StatefulWidget {
  const NeonPerimeterScreen({super.key});

  @override
  State<NeonPerimeterScreen> createState() => _NeonPerimeterScreenState();
}

class _NeonPerimeterScreenState extends State<NeonPerimeterScreen>
    with TickerProviderStateMixin {
  int _selectedTabIndex = 0;
  final int _durationMinutes = 5;

  late AnimationController _pulseController;
  final math.Random _rng = math.Random();
  Offset _ballPosition = Offset.zero;
  Offset _startPosition = Offset.zero;
  Offset _targetPosition = Offset.zero;
  bool _lastTargetOutside = false;
  bool _isPlaying = false;

  double _stakeUsd = BalanceGuard.minStakeUsd;
  PlayMode _playMode = PlayMode.demo;
  String? _activeSessionId;
  String? _activeTraceId;
  StreamSubscription<GameEvent>? _gameSubscription;

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 1800),
          )
          ..addListener(_updateBallPosition)
          ..addStatusListener((status) {
            if (_isPlaying && status == AnimationStatus.completed) {
              _assignNextTarget();
              _pulseController.forward(from: 0);
            }
          });

    _assignNextTarget(initial: true);
  }

  @override
  void dispose() {
    _gameSubscription?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _gameSubscription ??= context.read<SessionManager>().gameEvents.listen(
      _handleGameEvent,
    );
  }

  Future<void> _ensureSocket() async {
    if (!mounted) return;
    await context.read<SessionManager>().ensureGameSocket();
  }

  Future<void> _placeBet() async {
    final prediction = {
      'direction': _selectedTabIndex == 0 ? 'IN' : 'OUT',
      'symbol': 'R_50',
      'derivContractType': _selectedTabIndex == 0
          ? 'EXPIRYRANGE'
          : 'EXPIRYMISS',
      'durationMinutes': _durationMinutes,
      'duration': _durationMinutes,
      'durationUnit': 'm',
      'barrierHigh': 0.0015,
      'barrierLow': -0.0015,
    };

    if (_playMode.isDemo) {
      _startAnimation();
      showGameMessage(context, 'Demo range. Wallet unchanged.');
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (!mounted || !_isPlaying) return;
      _stopAnimation();
      _showResultDialog(
        buildDemoGameResult(
          gameType: 'NEON_PERIMETER',
          stakeUsd: _stakeUsd,
          payoutMultiplier: 1.85,
          winChance: 0.48,
          rng: _rng,
        ),
      );
      return;
    }

    final session = context.read<SessionManager>();
    if (!session.isAuthenticated) {
      if (!mounted) return;
      showGameMessage(context, 'Please log in to place a bet.');
      return;
    }
    final canPlay = await ensureStakeForPlayMode(context, _playMode, _stakeUsd);
    if (!canPlay) return;

    await _ensureSocket();

    try {
      final ack = await session.gameService.placeBet(
        gameType: 'NEON_PERIMETER',
        stakeUsd: _stakeUsd,
        prediction: prediction,
      );
      setState(() {
        _activeSessionId = ack.sessionId;
        _activeTraceId = ack.traceId;
      });
      _startAnimation();
    } on GameSocketException catch (err) {
      if (!mounted) return;
      showGameMessage(context, err.message);
    } catch (err) {
      if (!mounted) return;
      showGameMessage(context, 'Bet failed: $err');
    }
  }

  Future<void> _placeBetForDirection(int directionIndex) async {
    if (_isPlaying) return;
    setState(() => _selectedTabIndex = directionIndex);
    await _placeBet();
  }

  void _startAnimation() {
    if (_isPlaying) return;
    setState(() {
      _isPlaying = true;
    });
    _startPosition = _ballPosition;
    _assignNextTarget(initial: true);
    _pulseController.forward(from: 0);
  }

  void _handleGameEvent(GameEvent event) {
    if (!mounted) return;
    if (event is GameResultEvent && event.sessionId == _activeSessionId) {
      setState(() {
        _activeSessionId = null;
        _activeTraceId = null;
      });
      _stopAnimation();
      _showResultDialog(event);
    } else if (event is GameBetRejected && event.traceId == _activeTraceId) {
      setState(() {
        _activeTraceId = null;
      });
      _stopAnimation();
      showGameMessage(context, 'Bet rejected: ${event.reason}');
    } else if (event is GameErrorEvent) {
      _stopAnimation();
    }
  }

  void _showResultDialog(GameResultEvent event) {
    final win = event.outcome.toUpperCase() == 'WIN';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.gameSurface,
        title: Text(
          win ? 'Result: IN' : 'Result: ${event.outcome}',
          style: TextStyle(color: win ? Colors.greenAccent : Colors.redAccent),
        ),
        content: Text(
          win
              ? 'Winnings: \$${event.winAmountUsd.toStringAsFixed(2)}'
              : 'No payout this round.',
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(color: AppTheme.goldButtonBottom),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.gameBackground,
      appBar: const GameActivityAppBar(title: 'Neon Perimeter'),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Title Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Neon Perimeter',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Target: Range / OneTouch',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'STATUS',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.greenAccent,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.greenAccent,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            'LIVE',
                            style: TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // The Main Perimeter Visual
            Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                height: 320,
                decoration: BoxDecoration(
                  color: AppTheme.gameSurface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.gameBorder),
                  boxShadow: [
                    // slight shadow
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    // Grid background
                    CustomPaint(
                      size: const Size(double.infinity, double.infinity),
                      painter: _PerimeterGridPainter(),
                    ),
                    // Inner glowing frame
                    Padding(
                      padding: const EdgeInsets.all(40),
                      child: Stack(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.blueAccent.withValues(alpha: 0.5),
                                width: 2,
                              ),
                              color: Colors.blueAccent.withValues(alpha: 0.05),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.blueAccent.withValues(
                                    alpha: 0.1,
                                  ),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                          // 4 dots on borders
                          Align(
                            alignment: Alignment.topCenter,
                            child: FractionalTranslation(
                              translation: const Offset(0, -0.5),
                              child: _buildGlowingDot(),
                            ),
                          ),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: FractionalTranslation(
                              translation: const Offset(0, 0.5),
                              child: _buildGlowingDot(),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: FractionalTranslation(
                              translation: const Offset(-0.5, 0),
                              child: _buildGlowingDot(),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FractionalTranslation(
                              translation: const Offset(0.5, 0),
                              child: _buildGlowingDot(),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Central Ball with Animation Translation
                    Align(
                      alignment: Alignment.center,
                      child: FractionalTranslation(
                        // Range for inner board seems to be roughly -1.0 to 1.0 for the whole board
                        // Padding is 40 off a ~320 box.
                        translation: _ballPosition,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.blueAccent.withValues(alpha: 0.8),
                                blurRadius: 20,
                                spreadRadius: 8,
                              ),
                              BoxShadow(
                                color: Colors.lightBlueAccent.withValues(
                                  alpha: 0.5,
                                ),
                                blurRadius: 40,
                                spreadRadius: 15,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Stability Info Inside
                    Positioned(
                      top: 55,
                      left: 55,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'STABILITY',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 8,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _buildStabilityDash(Colors.blueAccent),
                              const SizedBox(width: 2),
                              _buildStabilityDash(Colors.blueAccent),
                              const SizedBox(width: 2),
                              _buildStabilityDash(
                                Colors.blueAccent.withValues(alpha: 0.3),
                              ),
                              const SizedBox(width: 2),
                              _buildStabilityDash(
                                Colors.blueAccent.withValues(alpha: 0.3),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Yield info inside
                    const Positioned(
                      bottom: 50,
                      right: 50,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'YIELD',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 8,
                              letterSpacing: 1.0,
                            ),
                          ),
                          Text(
                            'x1.85',
                            style: TextStyle(
                              color: Colors.blueAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom Info + Stake
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.gameSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.gameBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WINDOW',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.0,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_durationMinutes min (auto)',
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Window is fixed for this mode.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: StakeAdjuster(
                label: 'STAKE',
                value: _stakeUsd,
                enabled: !_isPlaying,
                onChanged: (next) => setState(() => _stakeUsd = next),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: PlayModeToggle(
                value: _playMode,
                enabled: !_isPlaying,
                onChanged: (mode) => setState(() => _playMode = mode),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: _buildDirectionButton(
                      label: 'IN',
                      selected: _selectedTabIndex == 0,
                      onTap: () => _placeBetForDirection(0),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildDirectionButton(
                      label: 'OUT',
                      selected: _selectedTabIndex == 1,
                      onTap: () => _placeBetForDirection(1),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  void _updateBallPosition() {
    if (!mounted) return;
    final t = _pulseController.value;
    setState(() {
      final eased = Curves.easeInOutCubic.transform(t);
      final overshoot = 1 + 0.25 * math.sin(t * math.pi * 4);
      final wobbleX = math.sin(t * math.pi * 6) * 0.2;
      final wobbleY = math.cos(t * math.pi * 5) * 0.2;
      final dx =
          _startPosition.dx +
          (_targetPosition.dx - _startPosition.dx) * eased * overshoot +
          wobbleX;
      final dy =
          _startPosition.dy +
          (_targetPosition.dy - _startPosition.dy) * eased * overshoot +
          wobbleY;
      _ballPosition = Offset(dx.clamp(-1.4, 1.4), dy.clamp(-1.4, 1.4));
    });
  }

  void _assignNextTarget({bool initial = false}) {
    bool goOutside;
    if (initial) {
      goOutside = _selectedTabIndex == 1;
    } else {
      goOutside = !_lastTargetOutside || _rng.nextDouble() < 0.5;
    }
    _lastTargetOutside = goOutside;
    _startPosition = _ballPosition;
    _targetPosition = _randomPoint(outside: goOutside);
  }

  Offset _randomPoint({required bool outside}) {
    final radius = outside
        ? 0.9 + _rng.nextDouble() * 0.6
        : 0.2 + _rng.nextDouble() * 0.6;
    final angle = _rng.nextDouble() * 2 * math.pi;
    final dx = radius * math.cos(angle);
    final dy = radius * math.sin(angle);
    return Offset(dx, dy);
  }

  void _stopAnimation() {
    if (!_isPlaying) return;
    setState(() {
      _isPlaying = false;
    });
    _pulseController.stop();
  }

  Widget _buildDirectionButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final disabled = _isPlaying;
    return PressScale(
      enabled: !disabled,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: disabled
                ? const [AppTheme.goldDisabledTop, AppTheme.goldDisabledBottom]
                : const [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.goldButtonBottom.withValues(
              alpha: disabled ? 0.4 : 0.9,
            ),
            width: selected ? 1.8 : 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.goldButtonBottom.withValues(
                alpha: disabled ? 0.08 : 0.24,
              ),
              blurRadius: 14,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: disabled ? null : onTap,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: AppTheme.goldText.withValues(
                    alpha: disabled ? 0.65 : 1,
                  ),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlowingDot() {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: Colors.blueAccent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withValues(alpha: 0.6),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildStabilityDash(Color color) {
    return Container(
      height: 3,
      width: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _PerimeterGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blueAccent.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    // dotted kind of grid or faint line grid
    for (double i = 0; i < size.width; i += 20) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 20) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
