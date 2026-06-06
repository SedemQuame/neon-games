import 'dart:async';
import 'dart:math' as math;

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

class KineticSurvivorScreen extends StatefulWidget {
  const KineticSurvivorScreen({super.key});

  @override
  State<KineticSurvivorScreen> createState() => _KineticSurvivorScreenState();
}

class _KineticSurvivorScreenState extends State<KineticSurvivorScreen>
    with TickerProviderStateMixin, GameRoundMixin<KineticSurvivorScreen> {
  static const int _minMinutes = 3;
  static const int _maxMinutes = 15;
  double stakeAmount = BalanceGuard.minStakeUsd;
  PlayMode _playMode = PlayMode.demo;
  int durationMinutes = _minMinutes;

  final math.Random _rng = math.Random();
  Offset _ballOffset = Offset.zero;
  bool _highlightWin = false;
  bool _isSimulating = false;
  String _status = 'Awaiting command';
  String _activeMode = 'SURVIVE';
  Timer? _ballTicker;

  @override
  void dispose() {
    if (mounted) {
      context.read<SessionManager>().gameService.leaveGame();
    }
    _ballTicker?.cancel();
    super.dispose();
  }


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SessionManager>().gameService.viewGame('kinetic_survivor');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      backgroundColor: AppTheme.gameBackground,
      appBar: const GameActivityAppBar(title: 'Kinetic Survivor'),
      bottomNavigationBar: PlayModeBottomBar(
        value: _playMode,
        enabled: !_isSimulating,
        onChanged: (mode) => setState(() => _playMode = mode),
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.gameSurface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.gameBorder),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFFf97316,
                          ).withValues(alpha: 0.05),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        CustomPaint(
                          size: const Size(double.infinity, double.infinity),
                          painter: _GridPainter(Colors.orangeAccent),
                        ),
                        Positioned(
                          top: 50,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            color: Colors.red.withValues(alpha: 0.5),
                          ),
                        ),
                        Positioned(
                          bottom: 50,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            color: Colors.red.withValues(alpha: 0.5),
                          ),
                        ),
                        CustomPaint(
                          size: const Size(double.infinity, double.infinity),
                          painter: _ChartPainter(color: Colors.orangeAccent),
                        ),
                        Positioned.fill(
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 340),
                            curve: Curves.easeInOut,
                            alignment: Alignment(
                              _ballOffset.dx,
                              _ballOffset.dy,
                            ),
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (_highlightWin
                                                ? Colors.greenAccent
                                                : Colors.orangeAccent)
                                            .withValues(alpha: 0.6),
                                    blurRadius: 25,
                                    spreadRadius: 6,
                                  ),
                                ],
                                gradient: RadialGradient(
                                  colors: _highlightWin
                                      ? [
                                          Colors.greenAccent,
                                          Colors.green.shade800,
                                        ]
                                      : [
                                          Colors.orangeAccent,
                                          Colors.deepOrange,
                                        ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: 20,
                          top: 20,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.orangeAccent.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'KINETIC SURVIVOR',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.orangeAccent,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Stay within bounds',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF94a3b8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.gameBackground,
                    border: Border(top: BorderSide(color: AppTheme.gameBorder)),
                  ),
                  child: Column(
                    children: [
                      StakeAdjuster(
                        label: 'STAKE',
                        value: stakeAmount,
                        enabled: !_isSimulating,
                        onChanged: (next) => setState(() => stakeAmount = next),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTradeButton(
                              label: 'SURVIVE',
                              icon: Icons.shield,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTradeButton(
                              label: 'BREACH',
                              icon: Icons.flash_on,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildControlPanel(
                              label: 'DURATION',
                              value: '$durationMinutes min',
                              icon: Icons.timer,
                              onDecrease: () => setState(() {
                                if (durationMinutes > _minMinutes) {
                                  durationMinutes--;
                                }
                              }),
                              onIncrease: () => setState(() {
                                if (durationMinutes < _maxMinutes) {
                                  durationMinutes++;
                                }
                              }),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _status,
                          style: TextStyle(
                            color: _highlightWin
                                ? Colors.greenAccent
                                : AppTheme.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
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
    );
  }

  Widget _buildControlPanel({
    required String label,
    required String value,
    required IconData icon,
    VoidCallback? onDecrease,
    VoidCallback? onIncrease,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.orangeAccent),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const Spacer(),
          _buildStakeStepButton(icon: Icons.remove, onTap: onDecrease),
          const SizedBox(width: 8),
          _buildStakeStepButton(icon: Icons.add, onTap: onIncrease),
        ],
      ),
    );
  }

  Widget _buildStakeStepButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
          ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.goldButtonBottom),
        ),
        child: Icon(icon, color: AppTheme.goldText),
      ),
    );
  }

  Widget _buildTradeButton({required String label, required IconData icon}) {
    final busy = _isSimulating && label == _activeMode;
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
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: busy ? null : () => _handlePlay(label),
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
                  busy ? 'ARMED...' : label,
                  style: TextStyle(
                    color: AppTheme.goldText.withValues(alpha: busy ? 0.65 : 1),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handlePlay(String mode) async {
    if (_isSimulating) return;
    final canPlay = await ensureStakeForPlayMode(
      context,
      _playMode,
      stakeAmount,
    );
    if (!canPlay) return;
    if (!mounted) return;
    try {
      setState(() {
        _status = 'Deploying $mode run...';
        _highlightWin = false;
        _activeMode = mode;
      });
      if (_playMode.isDemo) {
        setState(() {
          _status = 'Demo mission running...';
          _isSimulating = true;
        });
        _startBallDrift(mode);
        showGameMessage(context, 'Demo mission. Wallet unchanged.');
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        if (!mounted || !_isSimulating) return;
        onGameResult(
          buildDemoGameResult(
            gameType: 'KINETIC_SURVIVOR',
            stakeUsd: stakeAmount,
            payoutMultiplier: 2.1,
            winChance: 0.46,
            rng: _rng,
          ),
        );
        return;
      }
      final ack = await placeGameBet(
        gameType: 'KINETIC_SURVIVOR',
        stakeUsd: stakeAmount,
        prediction: _buildPrediction(mode),
      );
      if (!mounted) return;
      setState(() {
        _status = 'Listening for a response...';
        _isSimulating = true;
      });
      _startBallDrift(mode);
      showGameMessage(
        context,
        '$mode mission armed with \$${stakeAmount.toStringAsFixed(2)} stake.',
      );
      debugPrint('Session ${ack.sessionId} trace=${ack.traceId}');
    } on GameSocketException catch (err) {
      if (!mounted) return;
      setState(() => _status = err.message);
      showGameMessage(context, err.message);
    } catch (err) {
      if (!mounted) return;
      setState(() => _status = 'Failed to start mission');
      showGameMessage(context, 'Bet failed: $err');
    }
  }

  Map<String, dynamic> _buildPrediction(String mode) {
    final survive = mode == 'SURVIVE';
    return {
      'direction': survive ? 'IN' : 'OUT',
      'symbol': 'R_50',
      // Range contracts enforce a minimum window on Volatility 50.
      'durationMinutes': durationMinutes,
      'duration': durationMinutes,
      'durationUnit': 'm',
      'barrierHigh': 0.001,
      'barrierLow': -0.001,
      'derivContractType': survive ? 'EXPIRYRANGE' : 'EXPIRYMISS',
    };
  }

  void _startBallDrift(String mode) {
    _ballTicker?.cancel();
    _ballTicker = Timer.periodic(const Duration(milliseconds: 380), (_) {
      setState(() {
        _ballOffset = _randomOffset(mode == 'SURVIVE');
      });
    });
  }

  Offset _randomOffset(bool inside) {
    if (inside) {
      final dx = (_rng.nextDouble() * 1.2) - 0.6;
      final dy = (_rng.nextDouble() * 1.2) - 0.6;
      return Offset(dx.clamp(-0.6, 0.6), dy.clamp(-0.6, 0.6));
    }
    final edge = 0.85 + _rng.nextDouble() * 0.3;
    final dx = _rng.nextBool() ? edge : -edge;
    final dy = _rng.nextBool() ? edge : -edge;
    return Offset(dx.clamp(-1.2, 1.2), dy.clamp(-1.2, 1.2));
  }

  void _haltBall() {
    _ballTicker?.cancel();
    _ballTicker = null;
    setState(() => _isSimulating = false);
  }

  @override
  void onGameResult(GameResultEvent event) {
    final win = event.outcome.toUpperCase() == 'WIN';
    _haltBall();
    setState(() {
      _ballOffset = _randomOffset(win);
      _highlightWin = win;
      _status = win
          ? 'Mission survived · +\$${event.winAmountUsd.toStringAsFixed(2)}'
          : 'Mission ${event.outcome.toLowerCase()}';
    });
    showGameMessage(
      context,
      win
          ? 'You won \$${event.winAmountUsd.toStringAsFixed(2)}'
          : 'Mission ${event.outcome}',
    );
  }

  @override
  void onBetRejected(GameBetRejected event) {
    _haltBall();
    setState(() {
      _status = 'Bet rejected: ${event.reason}';
      _highlightWin = false;
    });
    showGameMessage(context, 'Bet rejected: ${event.reason}');
  }

  @override
  void onGameError(GameErrorEvent event) {
    _haltBall();
    setState(() {
      _status = event.message;
      _highlightWin = false;
    });
  }
}

class _GridPainter extends CustomPainter {
  final Color themeColor;
  _GridPainter(this.themeColor);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = themeColor.withValues(alpha: 0.05)
      ..strokeWidth = 1;
    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChartPainter extends CustomPainter {
  final Color color;
  _ChartPainter({required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height * 0.5)
      ..quadraticBezierTo(
        size.width * 0.25,
        size.height * 0.3,
        size.width * 0.5,
        size.height * 0.5,
      )
      ..quadraticBezierTo(
        size.width * 0.75,
        size.height * 0.7,
        size.width,
        size.height * 0.5,
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
