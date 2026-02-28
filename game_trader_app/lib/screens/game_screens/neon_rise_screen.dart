import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/game_service.dart';
import '../../utils/balance_guard.dart';
import '../../utils/game_round_mixin.dart';
import '../../widgets/game_message.dart';
import '../../widgets/wallet_balance_chip.dart';

class NeonRiseScreen extends StatefulWidget {
  const NeonRiseScreen({super.key});

  @override
  State<NeonRiseScreen> createState() => _NeonRiseScreenState();
}

class _NeonRiseScreenState extends State<NeonRiseScreen>
    with GameRoundMixin<NeonRiseScreen> {
  static const int _minTicks = 1;
  static const int _maxTicks = 10;

  double stakeAmount = 10.0;
  int durationTicks = 5;
  bool _isPlacing = false;
  String _statusMessage = 'Share your call';
  String? _activeDirection;

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
              Icons.currency_exchange,
              color: AppTheme.primaryColor,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              'EUR/USD',
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
        actions: [WalletBalanceChip()],
      ),
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                // Chart Area (Placeholder)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceDark,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.borderDark),
                      image: const DecorationImage(
                        image: AssetImage('assets/images/neon_rise_bg.png'),
                        fit: BoxFit.cover,
                        opacity:
                            0.3, // higher opacity since it's only in the chart
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withValues(alpha: 0.05),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Grid lines
                        CustomPaint(
                          size: const Size(double.infinity, double.infinity),
                          painter: _GridPainter(),
                        ),
                        // Fake Chart
                        CustomPaint(
                          size: const Size(double.infinity, double.infinity),
                          painter: _ChartPainter(color: AppTheme.primaryColor),
                        ),
                        // Live Price Tag
                        Positioned(
                          right: 0,
                          top: 100, // Roughly where the line ends
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                bottomLeft: Radius.circular(8),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.5,
                                  ),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: const Text(
                              '1.09245',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                        // Game Badge
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
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'NEON RISE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primaryColor,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Rise / Fall',
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

                // Controls Area
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundDark,
                    border: Border(top: BorderSide(color: AppTheme.borderDark)),
                  ),
                  child: Column(
                    children: [
                      // Stake & Duration
                      Row(
                        children: [
                          Expanded(
                            child: _buildControlPanel(
                              label: 'DURATION',
                              value: '$durationTicks Ticks',
                              icon: Icons.timer,
                              onDecrease: () => setState(() {
                                if (durationTicks > _minTicks) {
                                  durationTicks--;
                                }
                              }),
                              onIncrease: () => setState(() {
                                if (durationTicks < _maxTicks) {
                                  durationTicks++;
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
                      const SizedBox(height: 24),
                      // Payout Info
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Payout: 95.3%',
                            style: TextStyle(
                              color: Color(0xFF94a3b8),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Return: \$${(stakeAmount * 1.953).toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
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
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: _buildTradeButton(
                              label: 'LOWER',
                              icon: Icons.arrow_downward,
                              color: const Color(0xFFef4444), // Red
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTradeButton(
                              label: 'HIGHER',
                              icon: Icons.arrow_upward,
                              color: const Color(0xFF22c55e), // Green
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
    required VoidCallback onDecrease,
    required VoidCallback onIncrease,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: const Color(0xFF94a3b8)),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF94a3b8),
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: onDecrease,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundDark,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.remove,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              GestureDetector(
                onTap: onIncrease,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundDark,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 16),
                ),
              ),
            ],
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
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 16,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _isPlacing ? null : () => _handleTrade(label),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleTrade(String label) async {
    if (_isPlacing) return;
    final canPlay = await BalanceGuard.ensurePlayableStake(
      context,
      stakeAmount,
    );
    if (!canPlay || !mounted) return;
    final ticks = durationTicks.clamp(_minTicks, _maxTicks);
    final isHigher = label.toUpperCase() == 'HIGHER';

    setState(() {
      _isPlacing = true;
      _activeDirection = label;
      _statusMessage = '$label signal routing...';
    });

    try {
      await placeGameBet(
        gameType: 'NEON_RISE',
        stakeUsd: stakeAmount,
        prediction: _buildPrediction(isHigher, ticks),
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Listening for a response...';
      });
      showGameMessage(
        context,
        '$label signal armed at \$${stakeAmount.toStringAsFixed(2)}',
      );
    } on GameSocketException catch (err) {
      if (!mounted) return;
      setState(() {
        _isPlacing = false;
        _statusMessage = err.message;
        _activeDirection = null;
      });
      showGameMessage(context, err.message);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isPlacing = false;
        _statusMessage = 'Signal failed';
        _activeDirection = null;
      });
      showGameMessage(context, 'Signal failed: $err');
    }
  }

  Map<String, dynamic> _buildPrediction(bool isHigher, int ticks) {
    return {
      'symbol': 'R_50',
      'direction': isHigher ? 'UP' : 'DOWN',
      'derivContractType': isHigher ? 'CALL' : 'PUT',
      'durationTicks': ticks,
      'duration': ticks,
      'durationUnit': 't',
    };
  }

  @override
  void onGameResult(GameResultEvent event) {
    if (!mounted) return;
    final win = event.outcome.toUpperCase() == 'WIN';
    final label = _activeDirection ?? 'Signal';
    setState(() {
      _isPlacing = false;
      _activeDirection = null;
      _statusMessage = win
          ? '$label cleared +\$${event.winAmountUsd.toStringAsFixed(2)}'
          : '$label settled ${event.outcome}';
    });
    showGameMessage(
      context,
      win
          ? '$label paid \$${event.winAmountUsd.toStringAsFixed(2)}'
          : '$label closed as ${event.outcome}',
    );
  }

  @override
  void onBetRejected(GameBetRejected event) {
    if (!mounted) return;
    setState(() {
      _isPlacing = false;
      _activeDirection = null;
      _statusMessage = 'Rejected: ${event.reason}';
    });
    showGameMessage(context, 'Signal rejected: ${event.reason}');
  }

  @override
  void onGameError(GameErrorEvent event) {
    if (!mounted) return;
    setState(() {
      _isPlacing = false;
      _activeDirection = null;
      _statusMessage = event.message;
    });
    showGameMessage(context, event.message);
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
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
    final path = Path();
    path.moveTo(0, size.height * 0.7);
    path.quadraticBezierTo(
      size.width * 0.2,
      size.height * 0.8,
      size.width * 0.4,
      size.height * 0.5,
    );
    path.quadraticBezierTo(
      size.width * 0.6,
      size.height * 0.2,
      size.width * 0.8,
      size.height * 0.4,
    );
    path.quadraticBezierTo(
      size.width * 0.9,
      size.height * 0.5,
      size.width,
      size.height * 0.3,
    );

    // Subtle fill beneath the line
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    canvas.drawPath(fillPath, fillPaint);

    // Glowing line
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    canvas.drawPath(path, linePaint);

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 8
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawPath(path, glowPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
