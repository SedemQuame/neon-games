import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/game_service.dart';
import '../../utils/balance_guard.dart';
import '../../utils/game_round_mixin.dart';
import '../../widgets/game_message.dart';
import '../../widgets/wallet_balance_chip.dart';

class KineticSurvivorScreen extends StatefulWidget {
  const KineticSurvivorScreen({super.key});

  @override
  State<KineticSurvivorScreen> createState() => _KineticSurvivorScreenState();
}

class _KineticSurvivorScreenState extends State<KineticSurvivorScreen>
    with TickerProviderStateMixin, GameRoundMixin<KineticSurvivorScreen> {
  static const int _minMinutes = 3;
  static const int _maxMinutes = 15;
  double stakeAmount = 10.0;
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
    _ballTicker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.directions_run,
              color: Colors.orangeAccent,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              'US30',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.keyboard_arrow_down,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ],
        ),
        actions: const [WalletBalanceChip()],
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
                      color: AppTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.borderDark),
                      image: const DecorationImage(
                        image: AssetImage(
                          'assets/images/kinetic_survivor_bg.png',
                        ),
                        fit: BoxFit.cover,
                        opacity: 0.3,
                      ),
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
                    color: AppTheme.backgroundDark,
                    border: Border(top: BorderSide(color: AppTheme.borderDark)),
                  ),
                  child: Column(
                    children: [
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
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildControlPanel(
                              label: 'STAKE',
                              value: '\$${stakeAmount.toStringAsFixed(2)}',
                              icon: Icons.monetization_on,
                              onDecrease: () => setState(
                                () => stakeAmount > 1 ? stakeAmount -= 1 : null,
                              ),
                              onIncrease: () =>
                                  setState(() => stakeAmount += 1),
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
                                : Colors.white70,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTradeButton(
                              label: 'SURVIVE',
                              icon: Icons.shield,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTradeButton(
                              label: 'BREACH',
                              icon: Icons.flash_on,
                              color: Colors.redAccent,
                            ),
                          ),
                        ],
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
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderDark),
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
                  color: Colors.white54,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: onDecrease,
            icon: const Icon(Icons.remove, color: Colors.white70),
          ),
          IconButton(
            onPressed: onIncrease,
            icon: const Icon(Icons.add, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildTradeButton({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final busy = _isSimulating && label == _activeMode;
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: busy ? null : () => _handlePlay(label),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(
                busy ? 'ARMED...' : label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handlePlay(String mode) async {
    final canPlay = await BalanceGuard.ensurePlayableStake(
      context,
      stakeAmount,
    );
    if (!canPlay || _isSimulating) return;
    try {
      setState(() {
        _status = 'Deploying $mode run...';
        _highlightWin = false;
        _activeMode = mode;
      });
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
