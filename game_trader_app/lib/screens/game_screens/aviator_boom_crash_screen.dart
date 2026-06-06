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

enum _AviatorMarket { boom, crash }

class AviatorBoomCrashScreen extends StatefulWidget {
  const AviatorBoomCrashScreen({super.key});

  @override
  State<AviatorBoomCrashScreen> createState() => _AviatorBoomCrashScreenState();
}

class _AviatorBoomCrashScreenState extends State<AviatorBoomCrashScreen>
    with GameRoundMixin<AviatorBoomCrashScreen> {
  static const double _maxLeverage = 2000.0;
  static const double _maxVisibleMultiplier = 25.0;

  double stakeAmount = BalanceGuard.minStakeUsd;
  PlayMode _playMode = PlayMode.demo;
  _AviatorMarket _market = _AviatorMarket.boom;

  bool _isPlacing = false;
  bool _isFlying = false;
  bool _isLanding = false;
  bool _landRequested = false;
  double _liveMultiplier = 1.0;
  String _statusMessage = 'Select BOOM or CRASH, then launch';

  final Stopwatch _flightWatch = Stopwatch();
  Timer? _flightTicker;
  Timer? _demoCrashTimer;
  final math.Random _rng = math.Random();
  final List<double> _recentMultipliers = [
    1.90,
    3.24,
    2.84,
    1.51,
    3.62,
    2.02,
    1.43,
  ];

  @override
  void dispose() {
    if (mounted) {
      context.read<SessionManager>().gameService.leaveGame();
    }
    _demoCrashTimer?.cancel();
    _stopFlightTicker();
    super.dispose();
  }

  Future<void> _launchFlight() async {
    if (_isFlying || _isPlacing) return;

    final canPlay = await ensureStakeForPlayMode(
      context,
      _playMode,
      stakeAmount,
    );
    if (!canPlay) return;
    if (!mounted) return;

    setState(() {
      _isPlacing = true;
      _isFlying = true;
      _isLanding = false;
      _landRequested = false;
      _liveMultiplier = 1.0;
      _statusMessage = 'Taking off...';
    });
    _startFlightTicker();

    if (_playMode.isDemo) {
      final session = context.read<SessionManager>();
      if (!session.deductDemoBalance(stakeAmount)) {
        showGameMessage(context, 'Insufficient demo balance.');
        _stopFlightTicker();
        setState(() {
          _isPlacing = false;
          _isFlying = false;
        });
        return;
      }
      setState(() {
        _isPlacing = false;
        _statusMessage = 'Land before the crash';
      });
      _startDemoCrashTimer();
      return;
    }

    try {
      await placeGameBet(
        gameType: 'AVIATOR_BOOM_CRASH',
        stakeUsd: stakeAmount,
        prediction: _buildPrediction(),
      );
      if (!mounted) return;
      setState(() {
        _isPlacing = false;
        _statusMessage = 'Flight live. Land when ready.';
      });
    } on GameSocketException catch (err) {
      if (!mounted) return;
      _stopFlightTicker();
      setState(() {
        _isPlacing = false;
        _isFlying = false;
        _isLanding = false;
        _landRequested = false;
        _statusMessage = err.message;
      });
      showGameMessage(context, err.message);
    } catch (err) {
      if (!mounted) return;
      _stopFlightTicker();
      setState(() {
        _isPlacing = false;
        _isFlying = false;
        _isLanding = false;
        _landRequested = false;
        _statusMessage = 'Launch failed';
      });
      showGameMessage(context, 'Launch failed: $err');
    }
  }

  Map<String, dynamic> _buildPrediction() {
    final isBoom = _market == _AviatorMarket.boom;
    return {
      'symbol': isBoom ? 'BOOM1000' : 'CRASH1000',
      'direction': isBoom ? 'UP' : 'DOWN',
      'derivContractType': isBoom ? 'MULTUP' : 'MULTDOWN',
      'multiplier': _maxLeverage,
      // Keep protective controls broad to allow high-leverage behavior.
      'stopLoss': stakeAmount,
      'takeProfit': stakeAmount * 50,
    };
  }

  void _startDemoCrashTimer() {
    _demoCrashTimer?.cancel();
    final crashDelay = Duration(milliseconds: 5000 + _rng.nextInt(4000));
    _demoCrashTimer = Timer(crashDelay, () {
      if (!mounted || !_isFlying || _isLanding) return;
      _settleDemoFlight(win: false, multiplier: _liveMultiplier);
    });
  }

  Future<void> _landPlane() async {
    if (!_isFlying || _isPlacing || _isLanding) return;
    final settledAt = _liveMultiplier.clamp(1.01, _maxLeverage).toDouble();

    if (_playMode.isDemo) {
      _demoCrashTimer?.cancel();
      setState(() {
        _isLanding = true;
        _landRequested = true;
        _statusMessage = 'Landing at ${settledAt.toStringAsFixed(2)}x';
      });
      _settleDemoFlight(win: true, multiplier: settledAt);
      return;
    }

    try {
      setState(() {
        _isLanding = true;
        _landRequested = true;
        _statusMessage = 'Landing at ${settledAt.toStringAsFixed(2)}x';
      });
      await cashOutActiveGameBet(multiplier: settledAt);
      if (!mounted) return;
      showGameMessage(context, 'Landing requested.');
    } on GameSocketException catch (err) {
      if (!mounted) return;
      setState(() {
        _isLanding = false;
        _landRequested = false;
        _statusMessage = err.message;
      });
      showGameMessage(context, err.message);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isLanding = false;
        _landRequested = false;
        _statusMessage = 'Landing failed';
      });
      showGameMessage(context, 'Landing failed: $err');
    }
  }

  void _settleDemoFlight({required bool win, required double multiplier}) {
    if (!mounted) return;
    final payoutUsd = win ? stakeAmount * multiplier : 0.0;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    onGameResult(
      GameResultEvent(
        sessionId: 'demo-$id',
        userId: 'demo',
        gameType: 'AVIATOR_BOOM_CRASH',
        outcome: win ? 'WIN' : 'LOSS',
        payoutUsd: payoutUsd,
        winAmountUsd: win ? math.max(0.0, payoutUsd - stakeAmount) : 0.0,
        stakeUsd: stakeAmount,
        newBalance: 0,
        traceId: 'demo-$id',
        derivContractId: win ? 'DEMO_LANDED' : 'DEMO_CRASH',
      );
      if (win) {
        context.read<SessionManager>().addDemoWinnings(result.winAmountUsd);
      }
      onGameResult(result);
  }

  void _startFlightTicker() {
    _stopFlightTicker();
    _flightWatch
      ..reset()
      ..start();

    _flightTicker = Timer.periodic(const Duration(milliseconds: 70), (_) {
      if (!mounted || !_isFlying) return;
      final t = _flightWatch.elapsedMilliseconds / 1000.0;
      final next = 1 + (t * 0.55) + (t * t * 0.26);
      setState(() {
        _liveMultiplier = next.clamp(1.0, _maxLeverage);
      });
    });
  }

  void _stopFlightTicker() {
    _flightWatch.stop();
    _flightTicker?.cancel();
    _flightTicker = null;
  }

  @override
  void onGameResult(GameResultEvent event) {
    if (!mounted) return;
    _demoCrashTimer?.cancel();
    _stopFlightTicker();

    final settledAt = _liveMultiplier.clamp(1.0, _maxLeverage);
    final win = event.outcome.toUpperCase() == 'WIN';
    final landed = _landRequested && win;
    setState(() {
      _isPlacing = false;
      _isFlying = false;
      _isLanding = false;
      _landRequested = false;
      _statusMessage = win
          ? landed
                ? 'Landed at ${settledAt.toStringAsFixed(2)}x'
                : 'Cashed out at ${settledAt.toStringAsFixed(2)}x'
          : 'Crashed at ${settledAt.toStringAsFixed(2)}x';
      _recentMultipliers.insert(0, settledAt);
      if (_recentMultipliers.length > 14) {
        _recentMultipliers.removeLast();
      }
    });

    showGameMessage(
      context,
      win
          ? landed
                ? 'Landed +\$${event.winAmountUsd.toStringAsFixed(2)} at ${settledAt.toStringAsFixed(2)}x'
                : 'Win +\$${event.winAmountUsd.toStringAsFixed(2)} at ${settledAt.toStringAsFixed(2)}x'
          : 'Loss. Flight ended at ${settledAt.toStringAsFixed(2)}x',
    );
  }

  @override
  void onBetRejected(GameBetRejected event) {
    _demoCrashTimer?.cancel();
    _stopFlightTicker();
    if (!mounted) return;
    setState(() {
      _isPlacing = false;
      _isFlying = false;
      _isLanding = false;
      _landRequested = false;
      _statusMessage = 'Rejected: ${event.reason}';
    });
    showGameMessage(context, 'Bet rejected: ${event.reason}');
  }

  @override
  void onGameError(GameErrorEvent event) {
    _demoCrashTimer?.cancel();
    _stopFlightTicker();
    if (!mounted) return;
    setState(() {
      _isPlacing = false;
      _isFlying = false;
      _isLanding = false;
      _landRequested = false;
      _statusMessage = event.message;
    });
    showGameMessage(context, event.message);
  }


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SessionManager>().gameService.viewGame('aviator_boom_crash');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      backgroundColor: AppTheme.gameBackground,
      appBar: const GameActivityAppBar(title: 'Aviator Boom/Crash'),
      bottomNavigationBar: PlayModeBottomBar(
        value: _playMode,
        enabled: !_isFlying && !_isPlacing,
        onChanged: (mode) => setState(() => _playMode = mode),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: SizedBox(
                height: 28,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _recentMultipliers.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final value = _recentMultipliers[index];
                    final good = value >= 2;
                    return Text(
                      '${value.toStringAsFixed(2)}x',
                      style: TextStyle(
                        color: good
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFEF4444),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0E15),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFF1F2937)),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final point = _curvePoint(
                      Size(constraints.maxWidth, constraints.maxHeight),
                      _liveMultiplier,
                    );

                    return Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _AviatorBoardPainter(
                              multiplier: _liveMultiplier,
                            ),
                          ),
                        ),
                        Positioned(
                          left: (point.dx - 14).clamp(
                            10.0,
                            constraints.maxWidth - 40,
                          ),
                          top: (point.dy - 20).clamp(
                            10.0,
                            constraints.maxHeight - 40,
                          ),
                          child: Transform.rotate(
                            angle: -0.22,
                            child: const Icon(
                              Icons.airplanemode_active,
                              size: 30,
                              color: Color(0xFFEF4444),
                            ),
                          ),
                        ),
                        Center(
                          child: Text(
                            '${_liveMultiplier.toStringAsFixed(2)}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 72,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
              decoration: BoxDecoration(
                color: AppTheme.gameBackground,
                border: Border(top: BorderSide(color: AppTheme.gameBorder)),
              ),
              child: Column(
                children: [
                  StakeAdjuster(
                    label: 'STAKE',
                    value: stakeAmount,
                    enabled: !_isFlying && !_isPlacing,
                    onChanged: (next) => setState(() => stakeAmount = next),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMarketButton(
                          label: 'BOOM',
                          selected: _market == _AviatorMarket.boom,
                          color: const Color(0xFF8B1E1E),
                          onTap: () =>
                              setState(() => _market = _AviatorMarket.boom),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMarketButton(
                          label: 'CRASH',
                          selected: _market == _AviatorMarket.crash,
                          color: const Color(0xFF171717),
                          onTap: () =>
                              setState(() => _market = _AviatorMarket.crash),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _market == _AviatorMarket.boom
                          ? 'BOOM1000 / MULTUP'
                          : 'CRASH1000 / MULTDOWN',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final canLand = _isFlying && !_isPlacing && !_isLanding;
                      final canLaunch = !_isFlying && !_isPlacing;
                      final buttonEnabled = canLand || canLaunch;
                      final isLandingAction = _isFlying;
                      final buttonText = _isLanding
                          ? 'LANDING...'
                          : _isPlacing
                          ? 'ARMING...'
                          : isLandingAction
                          ? 'LAND PLANE'
                          : 'LAUNCH BET';
                      final icon = isLandingAction
                          ? Icons.flight_land
                          : Icons.flight_takeoff;
                      return _buildActionButton(
                        enabled: buttonEnabled,
                        icon: icon,
                        label: buttonText,
                        onTap: isLandingAction ? _landPlane : _launchFlight,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required bool enabled,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return PressScale(
      enabled: enabled,
      child: Container(
        width: double.infinity,
        height: 62,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: enabled
                ? const [AppTheme.goldButtonTop, AppTheme.goldButtonBottom]
                : const [AppTheme.goldDisabledTop, AppTheme.goldDisabledBottom],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.goldButtonBottom),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled ? onTap : null,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    color: AppTheme.goldText.withValues(
                      alpha: enabled ? 1 : 0.65,
                    ),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: TextStyle(
                      color: AppTheme.goldText.withValues(
                        alpha: enabled ? 1 : 0.65,
                      ),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Offset _curvePoint(Size size, double multiplier) {
    final normalized = (math.log(multiplier) / math.log(_maxVisibleMultiplier))
        .clamp(0.0, 1.0);
    final x = normalized * (size.width - 22) + 8;
    final y =
        size.height - (math.pow(normalized, 2.15) * (size.height - 14)) - 8;
    return Offset(x, y);
  }

  Widget _buildMarketButton({
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    final disabled = _isFlying || _isPlacing;
    return PressScale(
      enabled: !disabled,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppTheme.goldButtonBottom
                : color.withValues(alpha: 0.5),
            width: selected ? 2 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: disabled ? null : onTap,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: disabled ? 0.6 : 1),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AviatorBoardPainter extends CustomPainter {
  const _AviatorBoardPainter({required this.multiplier});

  final double multiplier;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0E1522), Color(0xFF080B12)],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(22)),
      bgPaint,
    );

    final center = Offset(size.width * 0.5, size.height * 0.55);
    for (var i = 0; i < 36; i++) {
      final angle = (math.pi * 2 / 36) * i;
      final rayPaint = Paint()
        ..color = const Color(0xFF93C5FD).withValues(alpha: 0.05)
        ..strokeWidth = 1.2;
      canvas.drawLine(
        center,
        center +
            Offset(math.cos(angle) * size.width, math.sin(angle) * size.height),
        rayPaint,
      );
    }

    final normalized = (math.log(multiplier.clamp(1.0, 25.0)) / math.log(25))
        .clamp(0.0, 1.0);
    final pointCount = 56;
    final path = Path();
    final fillPath = Path();

    for (var i = 0; i <= pointCount; i++) {
      final t = i / pointCount;
      final x = t * (size.width - 22) + 8;
      final y = size.height - (math.pow(t, 2.15) * (size.height - 14)) - 8;

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      if (t >= normalized) {
        break;
      }
    }

    final currentX = normalized * (size.width - 22) + 8;
    fillPath
      ..lineTo(currentX, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x66EF4444), Color(0x22EF4444)],
      ).createShader(rect)
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _AviatorBoardPainter oldDelegate) {
    return oldDelegate.multiplier != multiplier;
  }
}
