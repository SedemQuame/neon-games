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

class NeonRiseScreen extends StatefulWidget {
  const NeonRiseScreen({super.key});

  @override
  State<NeonRiseScreen> createState() => _NeonRiseScreenState();
}

class _NeonRiseScreenState extends State<NeonRiseScreen>
    with GameRoundMixin<NeonRiseScreen> {
  static const int _minTicks = 1;
  static const int _maxTicks = 10;

  double stakeAmount = BalanceGuard.minStakeUsd;
  PlayMode _playMode = PlayMode.demo;
  int durationTicks = 5;
  bool _isPlacing = false;
  String _statusMessage = 'Choose direction';
  String? _activeDirection;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SessionManager>().gameService.viewGame('neon_rise');
      }
    });
  }


  @override
  void dispose() {
    if (mounted) {
      context.read<SessionManager>().gameService.leaveGame();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      backgroundColor: AppTheme.gameBackground,
      appBar: const GameActivityAppBar(title: 'Neon Rise'),
      bottomNavigationBar: PlayModeBottomBar(
        value: _playMode,
        enabled: !_isPlacing,
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
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppTheme.gameBorder),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withValues(alpha: 0.18),
                          blurRadius: 32,
                          spreadRadius: -8,
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
                        CustomPaint(
                          size: const Size(double.infinity, double.infinity),
                          painter: _ChartPainter(color: AppTheme.primarySoft),
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '1.45x',
                                style: TextStyle(
                                  color: AppTheme.primarySoft,
                                  fontSize: 64,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(
                                      color: AppTheme.primaryColor.withValues(
                                        alpha: 0.65,
                                      ),
                                      blurRadius: 22,
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: AppTheme.primaryColor.withValues(
                                      alpha: 0.24,
                                    ),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    _LiveDot(),
                                    SizedBox(width: 8),
                                    Text(
                                      'Live Prediction',
                                      style: TextStyle(
                                        color: AppTheme.primarySoft,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 100,
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
                                  color: AppTheme.goldText.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'NEON RISE',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: AppTheme.primarySoft,
                                    letterSpacing: 0,
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
                        enabled: !_isPlacing,
                        onChanged: (next) => setState(() => stakeAmount = next),
                      ),
                      const SizedBox(height: 16),
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
                            letterSpacing: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTradeButton(
                              label: 'LOWER',
                              icon: Icons.arrow_downward,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTradeButton(
                              label: 'HIGHER',
                              icon: Icons.arrow_upward,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
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
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gameBorder),
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
                  letterSpacing: 0,
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
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.goldButtonTop,
                        AppTheme.goldButtonBottom,
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.remove,
                    color: AppTheme.goldText,
                    size: 16,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              GestureDetector(
                onTap: onIncrease,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.goldButtonTop,
                        AppTheme.goldButtonBottom,
                      ],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.add,
                    color: AppTheme.goldText,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTradeButton({required String label, required IconData icon}) {
    final isDisabled = _isPlacing;
    return PressScale(
      enabled: !isDisabled,
      child: Container(
        height: 64,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isDisabled
                ? const [AppTheme.goldDisabledTop, AppTheme.goldDisabledBottom]
                : const [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.goldButtonBottom.withValues(
              alpha: isDisabled ? 0.4 : 0.9,
            ),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.goldButtonBottom.withValues(
                alpha: isDisabled ? 0.08 : 0.26,
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
            onTap: isDisabled ? null : () => _handleTrade(label),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: AppTheme.goldText.withValues(
                    alpha: isDisabled ? 0.65 : 1,
                  ),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.goldText.withValues(
                      alpha: isDisabled ? 0.65 : 1,
                    ),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleTrade(String label) async {
    if (_isPlacing) return;
    final canPlay = await ensureStakeForPlayMode(
      context,
      _playMode,
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

    if (_playMode.isDemo) {
      showGameMessage(context, 'Demo signal. Wallet unchanged.');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted || !_isPlacing) return;
      onGameResult(
        buildDemoGameResult(
          gameType: 'NEON_RISE',
          stakeUsd: stakeAmount,
          payoutMultiplier: 1.95,
          winChance: 0.49,
        ),
      );
      return;
    }

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

class _LiveDot extends StatelessWidget {
  const _LiveDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: AppTheme.primarySoft,
        shape: BoxShape.circle,
      ),
    );
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
