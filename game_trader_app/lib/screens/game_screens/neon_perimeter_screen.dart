import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/game_service.dart';
import '../../services/session_manager.dart';
import '../../utils/balance_guard.dart';
import '../../widgets/game_message.dart';
import '../../widgets/wallet_balance_chip.dart';

class NeonPerimeterScreen extends StatefulWidget {
  const NeonPerimeterScreen({super.key});

  @override
  State<NeonPerimeterScreen> createState() => _NeonPerimeterScreenState();
}

class _NeonPerimeterScreenState extends State<NeonPerimeterScreen>
    with TickerProviderStateMixin {
  static const int _minMinutes = 3;
  static const int _maxMinutes = 15;

  int _selectedTabIndex = 0;
  final int _durationMinutes = 5;

  late AnimationController _pulseController;
  final math.Random _rng = math.Random();
  Offset _ballPosition = Offset.zero;
  Offset _startPosition = Offset.zero;
  Offset _targetPosition = Offset.zero;
  bool _lastTargetOutside = false;
  bool _isPlaying = false;

  String _status = 'Choose IN or OUT to begin';
  double _stakeUsd = 5;
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
    final session = context.read<SessionManager>();
    if (!session.isAuthenticated) {
      if (!mounted) return;
      showGameMessage(context, 'Please log in to place a bet.');
      return;
    }
    final canPlay = await BalanceGuard.ensurePlayableStake(context, _stakeUsd);
    if (!canPlay) return;

    await _ensureSocket();
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

    try {
      setState(() => _status = 'Submitting bet...');
      final ack = await session.gameService.placeBet(
        gameType: 'NEON_PERIMETER',
        stakeUsd: _stakeUsd,
        prediction: prediction,
      );
      setState(() {
        _status = 'Listening for a response...';
        _activeSessionId = ack.sessionId;
        _activeTraceId = ack.traceId;
      });
      _startAnimation();
    } on GameSocketException catch (err) {
      if (!mounted) return;
      setState(() => _status = err.message);
      showGameMessage(context, err.message);
    } catch (err) {
      if (!mounted) return;
      setState(() => _status = 'Bet failed');
      showGameMessage(context, 'Bet failed: $err');
    }
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
      final win = event.outcome.toUpperCase() == 'WIN';
      setState(() {
        _status = win
            ? 'IN zone held steady! +\$${event.payoutUsd.toStringAsFixed(2)}'
            : 'Round ended ${event.outcome}.';
        _activeSessionId = null;
        _activeTraceId = null;
      });
      _stopAnimation();
      _showResultDialog(event);
    } else if (event is GameBetRejected && event.traceId == _activeTraceId) {
      setState(() {
        _status = 'Bet rejected: ${event.reason}';
        _activeTraceId = null;
      });
      _stopAnimation();
      showGameMessage(context, 'Bet rejected: ${event.reason}');
    } else if (event is GameErrorEvent) {
      setState(() => _status = event.message);
      _stopAnimation();
    }
  }

  void _showResultDialog(GameResultEvent event) {
    final win = event.outcome.toUpperCase() == 'WIN';
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151b24),
        title: Text(
          win ? 'Result: IN' : 'Result: ${event.outcome}',
          style: TextStyle(color: win ? Colors.greenAccent : Colors.redAccent),
        ),
        content: Text(
          win
              ? 'Payout: \$${event.payoutUsd.toStringAsFixed(2)}'
              : 'No payout this round.',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Colors.blueAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF10151c), // Very dark background
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: AppBar(
            backgroundColor: const Color(0xFF10151c),
            elevation: 0,
            leadingWidth: 80,
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                margin: const EdgeInsets.only(left: 16, top: 12, bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1e293b),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  size: 16,
                  color: Colors.blueAccent,
                ),
              ),
            ),
            title: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.grid_view, size: 20, color: Colors.blueAccent),
                SizedBox(width: 8),
                Text(
                  'KINETIC ARCADE',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                    color: Colors.white,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            actions: [
              const WalletBalanceChip(
                margin: EdgeInsets.only(right: 12),
                backgroundColor: Color(0xFF11213b),
                borderColor: Color(0xFF1e3a8a),
                iconColor: Colors.blueAccent,
                textColor: Colors.blueAccent,
              ),
              const CircleAvatar(
                radius: 14,
                backgroundColor: Color(0xFF1e293b),
                child: Icon(Icons.person, size: 18, color: Colors.white70),
              ),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
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
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Target: Range / OneTouch',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
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
                          color: Colors.white.withValues(alpha: 0.4),
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

            // Tabs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1e293b),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (!_isPlaying) {
                            setState(() => _selectedTabIndex = 0);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _selectedTabIndex == 0
                                ? Colors.blueAccent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'IN',
                            style: TextStyle(
                              color: _selectedTabIndex == 0
                                  ? Colors.white
                                  : Colors.white54,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (!_isPlaying) {
                            setState(() => _selectedTabIndex = 1);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: _selectedTabIndex == 1
                                ? Colors.blueAccent
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'OUT',
                            style: TextStyle(
                              color: _selectedTabIndex == 1
                                  ? Colors.white
                                  : Colors.white54,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // The Main Perimeter Visual
            Padding(
              padding: const EdgeInsets.all(20),
              child: Container(
                height: 320,
                decoration: BoxDecoration(
                  color: const Color(0xFF151b24),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
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

            // Bottom Info Cards
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151b24),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'WINDOW',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '$_durationMinutes min (auto)',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Window is fixed for this mode.',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151b24),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'STAKE (USD)',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '\$${_stakeUsd.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Slider(
                    min: 1,
                    max: 100,
                    divisions: 99,
                    value: _stakeUsd,
                    activeColor: Colors.blueAccent,
                    onChanged: (value) {
                      if (_isPlaying) return;
                      setState(() => _stakeUsd = value);
                    },
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _status,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // START PULSE Button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: _isPlaying
                            ? Colors.transparent
                            : Colors.blueAccent.withValues(alpha: 0.3),
                        blurRadius: 15,
                        spreadRadius: -2,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isPlaying
                          ? Colors.blueGrey
                          : Colors.blueAccent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: _isPlaying ? null : _placeBet,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isPlaying ? Icons.hourglass_empty : Icons.bolt,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _isPlaying ? 'WAITING...' : 'ENGAGE MISSION',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
