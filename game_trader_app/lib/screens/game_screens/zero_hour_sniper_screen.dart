import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/game_service.dart';
import '../../utils/balance_guard.dart';
import '../../utils/game_round_mixin.dart';
import '../../widgets/game_message.dart';
import '../../widgets/wallet_balance_chip.dart';

class ZeroHourSniperScreen extends StatefulWidget {
  const ZeroHourSniperScreen({super.key});

  @override
  State<ZeroHourSniperScreen> createState() => _ZeroHourSniperScreenState();
}

class _ZeroHourSniperScreenState extends State<ZeroHourSniperScreen>
    with SingleTickerProviderStateMixin, GameRoundMixin<ZeroHourSniperScreen> {
  int targetNumber = 8;
  double stakeAmount = 50.00;
  List<int> liveTicks = [3, 7, 2, 0, 8, 4, 1];
  bool _isFiring = false;
  String _statusMessage = 'Lock target and fire';

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(
        0xFF0F1115,
      ), // Very dark industrial background
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        toolbarHeight: 70,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 20,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'KINETIC ARCADE',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 10,
                color: Color(0xFF3b82f6),
                letterSpacing: 1.5,
              ),
            ),
            const Text(
              'ZERO-HOUR SNIPER',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          WalletBalanceChip(
            backgroundColor: Color(0xFF1e293b),
            borderColor: Color(0xFF334155),
            iconColor: Color(0xFF3b82f6),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),
              // LIVE TICK STREAM
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Color(0xFF06b6d4),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'LIVE TICK STREAM',
                    style: TextStyle(
                      color: Color(0xFF94a3b8),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Tick Stream Row
              SizedBox(
                height: 50,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: liveTicks.map((tick) {
                    bool isSelected = tick == targetNumber;
                    return Container(
                      width: 40,
                      height: 50,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1e293b).withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF3b82f6).withValues(alpha: 0.5)
                              : const Color(0xFF334155).withValues(alpha: 0.2),
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        tick.toString(),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: isSelected
                              ? const Color(0xFF3b82f6)
                              : const Color(0xFF475569),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 24),

              // Animated Radar Circle
              SizedBox(
                height: 320,
                width: double.infinity,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return CustomPaint(
                          size: const Size(320, 320),
                          painter: _SniperScopePainter(
                            animationValue: _animationController.value,
                          ),
                        );
                      },
                    ),
                    Text(
                      targetNumber.toString(),
                      style: const TextStyle(
                        fontSize: 100,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Target Selection Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text(
                      'TARGET SELECTION',
                      style: TextStyle(
                        color: Color(0xFF64748b),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    Text(
                      'PAYOUT: 9.2x',
                      style: TextStyle(
                        color: Color(0xFF3b82f6),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Numpad Grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: List.generate(10, (index) {
                    bool isSelected = index == targetNumber;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          targetNumber = index;
                        });
                      },
                      child: Container(
                        width:
                            (MediaQuery.of(context).size.width - 40 - 48) / 5,
                        height: 60,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF2563eb)
                              : const Color(0xFF1e293b).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF60a5fa)
                                : const Color(0xFF334155),
                            width: isSelected ? 2 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: const Color(
                                      0xFF3b82f6,
                                    ).withValues(alpha: 0.5),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          index.toString(),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 32),

              // Stake Amount Section
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'STAKE AMOUNT',
                      style: TextStyle(
                        color: Color(0xFF64748b),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 50,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1e293b,
                              ).withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: const Color(0xFF334155),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Text(
                                  '\$ ',
                                  style: TextStyle(
                                    color: Color(0xFF3b82f6),
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  stakeAmount.toStringAsFixed(2),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildStakeButton(
                          'MIN',
                          () => setState(() => stakeAmount = 1),
                        ),
                        const SizedBox(width: 8),
                        _buildStakeButton(
                          'MAX',
                          () => setState(() => stakeAmount = 250),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _statusMessage,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Trigger Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  height: 100,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF60a5fa), Color(0xFF2563eb)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563eb).withValues(alpha: 0.5),
                        blurRadius: 20,
                        spreadRadius: -5,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: _isFiring ? null : _handleTrigger,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            'ENGAGE TRIGGER',
                            style: TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 4.0,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'SNIPE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 36,
                              fontStyle: FontStyle.italic,
                              letterSpacing: 2.0,
                              shadows: [
                                Shadow(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                ),
                              ],
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
      ),
    );
  }

  Future<void> _handleTrigger() async {
    if (_isFiring) return;
    final canPlay = await BalanceGuard.ensurePlayableStake(
      context,
      stakeAmount,
    );
    if (!canPlay || !mounted) return;
    setState(() {
      _isFiring = true;
      _statusMessage = 'Authorizing sniper shot...';
    });

    try {
      await placeGameBet(
        gameType: 'ZERO_HOUR_SNIPER',
        stakeUsd: stakeAmount,
        prediction: _buildPrediction(),
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Listening for a response...';
      });
      showGameMessage(
        context,
        'Sniper shot placed with \$${stakeAmount.toStringAsFixed(2)} stake.',
      );
    } on GameSocketException catch (err) {
      if (!mounted) return;
      setState(() {
        _isFiring = false;
        _statusMessage = err.message;
      });
      showGameMessage(context, err.message);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isFiring = false;
        _statusMessage = 'Shot failed';
      });
      showGameMessage(context, 'Shot failed: $err');
    }
  }

  Map<String, dynamic> _buildPrediction() {
    return {
      'symbol': 'R_10',
      'derivContractType': 'DIGITMATCH',
      'digitPrediction': targetNumber,
      'barrier': targetNumber.toString(),
      'durationTicks': 1,
      'duration': 1,
      'durationUnit': 't',
    };
  }

  Widget _buildStakeButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 50,
        width: 60,
        decoration: BoxDecoration(
          color: const Color(0xFF1e293b).withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF334155)),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFcbd5e1),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  @override
  void onGameResult(GameResultEvent event) {
    if (!mounted) return;
    final win = event.outcome.toUpperCase() == 'WIN';
    setState(() {
      _isFiring = false;
      _statusMessage = win
          ? 'Impact confirmed +\$${event.winAmountUsd.toStringAsFixed(2)}'
          : 'Shot settled ${event.outcome}';
    });
    showGameMessage(
      context,
      win
          ? 'Sniper shot paid \$${event.winAmountUsd.toStringAsFixed(2)}'
          : 'Sniper shot closed as ${event.outcome}',
    );
  }

  @override
  void onBetRejected(GameBetRejected event) {
    if (!mounted) return;
    setState(() {
      _isFiring = false;
      _statusMessage = 'Rejected: ${event.reason}';
    });
    showGameMessage(context, 'Shot rejected: ${event.reason}');
  }

  @override
  void onGameError(GameErrorEvent event) {
    if (!mounted) return;
    setState(() {
      _isFiring = false;
      _statusMessage = event.message;
    });
    showGameMessage(context, event.message);
  }
}

class _SniperScopePainter extends CustomPainter {
  final double animationValue;

  _SniperScopePainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final coreRadius = size.width * 0.28;

    // Background glow behind the number
    final glowPaint = Paint()
      ..color = const Color(0xFF3b82f6).withValues(alpha: 0.15)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30);
    canvas.drawCircle(center, coreRadius * 0.8, glowPaint);

    // Thick inner border (bright blue glow)
    final innerBorderPaint = Paint()
      ..color = const Color(0xFF3b82f6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;

    innerBorderPaint.shader = const SweepGradient(
      colors: [
        Color(0xFF0ea5e9),
        Color(0xFF3b82f6),
        Color(0xFF2563eb),
        Color(0xFF0ea5e9),
      ],
      stops: [0.0, 0.3, 0.7, 1.0],
    ).createShader(Rect.fromCircle(center: center, radius: coreRadius));

    canvas.drawCircle(center, coreRadius, innerBorderPaint);

    // Dashed outer ring
    final outerRadius = size.width * 0.36;
    final dashPaint = Paint()
      ..color = const Color(0xFF475569)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final double dashAngle = 0.05;
    final double gapAngle = 0.05;
    final int dashCount = (2 * math.pi / (dashAngle + gapAngle)).floor();

    for (int i = 0; i < dashCount; i++) {
      final startAngle =
          i * (dashAngle + gapAngle) + (animationValue * math.pi * 2);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: outerRadius),
        startAngle,
        dashAngle,
        false,
        dashPaint,
      );
    }

    // Thin outer boundary rings
    final thinOuterRadius1 = size.width * 0.45;
    final thinOuterRadius2 = size.width * 0.48;
    final thinPaint = Paint()
      ..color = const Color(0xFF1e293b)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawCircle(center, thinOuterRadius1, thinPaint);
    canvas.drawCircle(center, thinOuterRadius2, thinPaint);

    // Draw Frequency text
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'FREQUENCY\n',
        style: TextStyle(
          color: Color(0xFFec4899),
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
        children: [
          TextSpan(
            text: '240.5ms',
            style: TextStyle(
              color: Color(0xFFec4899),
              fontSize: 10,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(center.dx + outerRadius * 0.6, center.dy - outerRadius * 0.8),
    );

    // Draw Sync state text
    final statePainter = TextPainter(
      text: const TextSpan(
        text: 'SYNC STATE\n',
        style: TextStyle(
          color: Color(0xFF06b6d4),
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
        children: [
          TextSpan(
            text: 'LOCKED',
            style: TextStyle(
              color: Color(0xFF2563eb),
              fontSize: 10,
              fontWeight: FontWeight.normal,
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.left,
    );
    statePainter.layout();
    statePainter.paint(
      canvas,
      Offset(center.dx - outerRadius * 0.9, center.dy + outerRadius * 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _SniperScopePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
