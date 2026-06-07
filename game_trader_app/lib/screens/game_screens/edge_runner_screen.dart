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

class EdgeRunnerScreen extends StatefulWidget {
  const EdgeRunnerScreen({super.key});

  @override
  State<EdgeRunnerScreen> createState() => _EdgeRunnerScreenState();
}

class _EdgeRunnerScreenState extends State<EdgeRunnerScreen>
    with GameRoundMixin<EdgeRunnerScreen> {
  static const int _minTicks = 5;
  static const int _maxTicks = 10;

  double stakeAmount = BalanceGuard.minStakeUsd;
  PlayMode _playMode = PlayMode.demo;
  int durationTicks = _minTicks;
  bool _isPlacing = false;
  String _statusMessage = 'Awaiting signal';
  String? _activeMode;


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SessionManager>().gameService.viewGame('edge_runner');
      }
    });
  }


  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      backgroundColor: AppTheme.gameBackground,
      appBar: const GameActivityAppBar(title: 'Edge Runner'),
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
                // Chart Area (Placeholder)
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.gameSurface,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppTheme.gameBorder),
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
                        // Fake Barrier Line
                        Positioned(
                          top: 150,
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 2,
                            color: Colors.redAccent.withValues(alpha: 0.5),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Colors.redAccent,
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(4),
                                      bottomLeft: Radius.circular(4),
                                    ),
                                  ),
                                  child: const Text(
                                    'BARRIER',
                                    style: TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Fake Chart
                        CustomPaint(
                          size: const Size(double.infinity, double.infinity),
                          painter: _ChartPainter(color: Colors.purpleAccent),
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
                              color: Colors.purpleAccent,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                bottomLeft: Radius.circular(8),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.purpleAccent.withValues(
                                    alpha: 0.5,
                                  ),
                                  blurRadius: 12,
                                ),
                              ],
                            ),
                            child: const Text(
                              '189.245',
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
                                  color: Colors.purpleAccent.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'EDGE RUNNER',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.purpleAccent,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Touch / No Touch',
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
                    color: AppTheme.gameBackground,
                    border: Border(top: BorderSide(color: AppTheme.gameBorder)),
                  ),
                  child: Column(
                    children: [
                      // Stake (full width)
                      StakeAdjuster(
                        label: 'STAKE',
                        value: stakeAmount,
                        enabled: !_isPlacing,
                        onChanged: (next) => setState(() => stakeAmount = next),
                      ),
                      const SizedBox(height: 16),
                      // Action Buttons
                      Row(
                        children: [
                          Expanded(
                            child: _buildTradeButton(
                              label: 'TOUCH',
                              icon: Icons.touch_app,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTradeButton(
                              label: 'NO TOUCH',
                              icon: Icons.do_not_touch,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Duration
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
                      const SizedBox(height: 16),
                      // Payout Info
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Payout: 250.0%',
                            style: TextStyle(
                              color: Color(0xFF94a3b8),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Return: \$${(stakeAmount * 3.50).toStringAsFixed(2)}',
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
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.4,
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
                    fontSize:
                        16, // Adjusted slightly smaller for "NO TOUCH" to fit
                    letterSpacing: -0.5,
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
    final normalized = label.toUpperCase();
    final isTouch = normalized.contains('TOUCH') && !normalized.contains('NO');

    setState(() {
      _isPlacing = true;
      _activeMode = label;
      _statusMessage = '$label vector routing...';
    });

    if (_playMode.isDemo) {
      final session = context.read<SessionManager>();
      if (!session.deductDemoBalance(stakeAmount)) {
        showGameMessage(context, 'Insufficient demo balance.');
        return;
      }
      showGameMessage(context, 'Demo order. Wallet unchanged.');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (!mounted || !_isPlacing) return;
      final demoRes = buildDemoGameResult(
          gameType: 'EDGE_RUNNER',
          stakeUsd: stakeAmount,
          payoutMultiplier: 3.5,
          winChance: 0.36,
        );
      if (demoRes.winAmountUsd > 0) {
        context.read<SessionManager>().addDemoWinnings(demoRes.winAmountUsd);
      }
      onGameResult(demoRes);
      return;
    }

    try {
      await placeGameBet(
        gameType: 'EDGE_RUNNER',
        stakeUsd: stakeAmount,
        prediction: _buildPrediction(isTouch, ticks),
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Listening for a response...';
      });
      showGameMessage(
        context,
        '$label order armed at \$${stakeAmount.toStringAsFixed(2)}',
      );
    } on GameSocketException catch (err) {
      if (!mounted) return;
      setState(() {
        _isPlacing = false;
        _statusMessage = err.message;
        _activeMode = null;
      });
      showGameMessage(context, err.message);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isPlacing = false;
        _statusMessage = 'Order failed';
        _activeMode = null;
      });
      showGameMessage(context, 'Order failed: $err');
    }
  }

  Map<String, dynamic> _buildPrediction(bool touch, int ticks) {
    final barrier = touch ? '+0.0180' : '+0.0180';
    return {
      'symbol': 'R_50',
      'derivContractType': touch ? 'ONETOUCH' : 'NOTOUCH',
      'durationTicks': ticks,
      'duration': ticks,
      'durationUnit': 't',
      'barrier': barrier,
    };
  }

  @override
  void onGameResult(GameResultEvent event) {
    if (!mounted) return;
    final win = event.outcome.toUpperCase() == 'WIN';
    final label = _activeMode ?? 'Signal';
    setState(() {
      _isPlacing = false;
      _activeMode = null;
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
      _activeMode = null;
      _statusMessage = 'Rejected: ${event.reason}';
    });
    showGameMessage(context, 'Order rejected: ${event.reason}');
  }

  @override
  void onGameError(GameErrorEvent event) {
    if (!mounted) return;
    setState(() {
      _isPlacing = false;
      _activeMode = null;
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
