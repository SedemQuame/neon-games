import 'package:flutter/material.dart';

import '../../services/game_service.dart';
import '../../utils/balance_guard.dart';
import '../../utils/game_round_mixin.dart';
import '../../widgets/game_message.dart';
import '../../widgets/wallet_balance_chip.dart';

class VelocityVectorScreen extends StatefulWidget {
  const VelocityVectorScreen({super.key});

  @override
  State<VelocityVectorScreen> createState() => _VelocityVectorScreenState();
}

class _VelocityVectorScreenState extends State<VelocityVectorScreen>
    with GameRoundMixin<VelocityVectorScreen> {
  double stakeAmount = 15.0;
  bool _isExecuting = false;
  String _statusMessage = 'Awaiting vector command';
  String? _activeCommand;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0b121c),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(80),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
            ),
          ),
          child: AppBar(
            backgroundColor: const Color(0xFF0b121c),
            elevation: 0,
            leadingWidth: 80,
            leading: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                margin: const EdgeInsets.only(left: 16, top: 12, bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF131c2c),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  size: 16,
                  color: Colors.blueAccent,
                ),
              ),
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'VELOCITY VECTOR',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Colors.blueAccent,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'SQ: 29.92  |  HDG: 042°',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.5),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
            ),
            actions: [
              WalletBalanceChip(
                margin: const EdgeInsets.only(right: 16),
                backgroundColor: const Color(0xFF131c2c),
                borderColor: const Color(0xFF1e293b),
                iconColor: Colors.blueAccent,
              ),
            ],
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background Grid
          CustomPaint(
            size: const Size(double.infinity, double.infinity),
            painter: _GridPainter(Colors.blueAccent),
          ),
          Column(
            children: [
              // Top Flight Info Data
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 32,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoText('PITCH: ', '+12.4°'),
                        const SizedBox(height: 12),
                        _buildInfoText('ROLL: ', '-2.1°'),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoText('LAT: ', '40.7128° N'),
                        const SizedBox(height: 12),
                        _buildInfoText('LON: ', '74.0060° W'),
                      ],
                    ),
                  ],
                ),
              ),

              // Center Radar / Multiplier
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildIndicatorBar('ALTITUDE', Colors.blueAccent, 0.6),
                    const SizedBox(width: 8),
                    Center(
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // Radar Outer Circle
                          Container(
                            width: 260,
                            height: 260,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.blueAccent.withValues(alpha: 0.3),
                                width: 1.5,
                              ),
                            ),
                          ),
                          // Multiplier Text Details
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'MULTIPLIER',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 1.5,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.baseline,
                                textBaseline: TextBaseline.alphabetic,
                                children: [
                                  const Text(
                                    '1.42',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 64,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -1.0,
                                    ),
                                  ),
                                  const Text(
                                    'x',
                                    style: TextStyle(
                                      color: Colors.blueAccent,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.trending_up,
                                    color: Colors.greenAccent,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    '+\$14.20',
                                    style: TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          // The swooping Curve
                          Positioned(
                            left: 0,
                            top: 0,
                            right: 0,
                            bottom: 0,
                            child: CustomPaint(
                              painter: _CurvePainter(color: Colors.blueAccent),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildIndicatorBar('AIRSPEED', Colors.greenAccent, 0.45),
                  ],
                ),
              ),

              // Bottom Actions Area
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0e1520),
                  border: Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'STAKE',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Row(
                          children: [
                            _buildStakeAdjustButton(
                              icon: Icons.remove,
                              onTap: () {
                                setState(
                                  () =>
                                      stakeAmount > 1 ? stakeAmount -= 1 : null,
                                );
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                '\$${stakeAmount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            _buildStakeAdjustButton(
                              icon: Icons.add,
                              onTap: () => setState(() => stakeAmount += 1),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: _buildActionButton(
                            label: 'CLIMB',
                            subLabel: 'VECTOR +',
                            icon: Icons.keyboard_arrow_up,
                            color: Colors.blueAccent,
                            onTap: () => _handleCommand('CLIMB'),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildActionButton(
                            label: 'DIVE',
                            subLabel: 'VECTOR -',
                            icon: Icons.keyboard_arrow_down,
                            color: Colors.redAccent,
                            onTap: () => _handleCommand('DIVE'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Status + Land Button
                    Align(
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
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 60,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blueAccent.withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: -5,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blueAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          onPressed: () => _handleCommand('LAND'),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.flight_land,
                                color: Colors.white,
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'LAND POSITION',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 2.0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoText(String label, String value) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF3b82f6),
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.blueAccent,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  Widget _buildIndicatorBar(String label, Color color, double fillRatio) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 140,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(3),
          ),
          alignment: Alignment.bottomCenter,
          child: Container(
            width: 6,
            height: 140 * fillRatio,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildStakeAdjustButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF131c2c),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }

  Future<void> _handleCommand(String command) async {
    if (_isExecuting) return;
    final canPlay = await BalanceGuard.ensurePlayableStake(
      context,
      stakeAmount,
    );
    if (!canPlay) return;
    if (!mounted) return;

    setState(() {
      _isExecuting = true;
      _activeCommand = command;
      _statusMessage = '$command vector routing...';
    });

    try {
      await placeGameBet(
        gameType: 'VELOCITY_VECTOR',
        stakeUsd: stakeAmount,
        prediction: _buildPrediction(command),
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Listening for a response...';
      });
      showGameMessage(
        context,
        '$command maneuver armed at \$${stakeAmount.toStringAsFixed(2)}',
      );
    } on GameSocketException catch (err) {
      if (!mounted) return;
      setState(() {
        _isExecuting = false;
        _statusMessage = err.message;
        _activeCommand = null;
      });
      showGameMessage(context, err.message);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isExecuting = false;
        _statusMessage = 'Command failed';
        _activeCommand = null;
      });
      showGameMessage(context, 'Command failed: $err');
    }
  }

  Map<String, dynamic> _buildPrediction(String command) {
    final isDive = command == 'DIVE';
    final multiplier = command == 'LAND' ? 50.0 : 100.0;
    final takeProfit = stakeAmount * 2.5;
    final stopLoss = stakeAmount;
    return {
      'direction': isDive ? 'DOWN' : 'UP',
      'symbol': 'R_50',
      'multiplier': multiplier,
      'takeProfit': takeProfit,
      'stopLoss': stopLoss,
    };
  }

  Widget _buildActionButton({
    required String label,
    required String subLabel,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        color: const Color(0xFF111928),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isExecuting ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Text(
                      subLabel,
                      style: TextStyle(
                        color: color,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
                Icon(icon, color: color, size: 36),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void onGameResult(GameResultEvent event) {
    if (!mounted) return;
    final win = event.outcome.toUpperCase() == 'WIN';
    final commandLabel = _activeCommand ?? 'Vector';
    setState(() {
      _isExecuting = false;
      _activeCommand = null;
      _statusMessage = win
          ? '$commandLabel cleared +\$${event.payoutUsd.toStringAsFixed(2)}'
          : '$commandLabel settled ${event.outcome}';
    });
    showGameMessage(
      context,
      win
          ? '$commandLabel paid \$${event.payoutUsd.toStringAsFixed(2)}'
          : '$commandLabel closed as ${event.outcome}',
    );
  }

  @override
  void onBetRejected(GameBetRejected event) {
    if (!mounted) return;
    final commandLabel = _activeCommand ?? 'Vector';
    setState(() {
      _isExecuting = false;
      _activeCommand = null;
      _statusMessage = '$commandLabel rejected: ${event.reason}';
    });
    showGameMessage(context, '$commandLabel rejected: ${event.reason}');
  }

  @override
  void onGameError(GameErrorEvent event) {
    if (!mounted) return;
    final commandLabel = _activeCommand ?? 'Vector';
    setState(() {
      _isExecuting = false;
      _activeCommand = null;
      _statusMessage = '$commandLabel error: ${event.message}';
    });
    showGameMessage(context, event.message);
  }
}

class _GridPainter extends CustomPainter {
  final Color themeColor;
  _GridPainter(this.themeColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = themeColor.withValues(alpha: 0.03)
      ..strokeWidth = 1;

    // Create a subtle grid across the body
    for (double i = 0; i < size.width; i += 30) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += 30) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CurvePainter extends CustomPainter {
  final Color color;
  _CurvePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    // Start slightly outside bottom-left
    path.moveTo(-20, size.height * 0.9);

    // Curve through the center to top-right
    path.quadraticBezierTo(
      size.width * 0.4,
      size.height * 0.7,
      size.width + 40,
      size.height * 0.2, // Go upwards
    );

    // Glow Effect
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..strokeWidth = 6
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );

    // Main line
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );

    // Calculate a target point along the path around t = 0.8
    // P = (1-t)^2*P0 + 2(1-t)t*P1 + t^2*P2
    double t = 0.8;
    double p0x = -20, p0y = size.height * 0.9;
    double p1x = size.width * 0.4, p1y = size.height * 0.7;
    double p2x = size.width + 40, p2y = size.height * 0.2;

    double pointX =
        (1 - t) * (1 - t) * p0x + 2 * (1 - t) * t * p1x + t * t * p2x;
    double pointY =
        (1 - t) * (1 - t) * p0y + 2 * (1 - t) * t * p1y + t * t * p2y;

    final pointOffset = Offset(pointX, pointY);

    // Outer faint ring
    canvas.drawCircle(
      pointOffset,
      12,
      Paint()
        ..color = color.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // Inner bright square
    canvas.drawRect(
      Rect.fromCenter(center: pointOffset, width: 8, height: 8),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
