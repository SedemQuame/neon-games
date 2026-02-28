import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../services/game_service.dart';
import '../../utils/balance_guard.dart';
import '../../utils/game_round_mixin.dart';
import '../../widgets/game_message.dart';
import '../../widgets/wallet_balance_chip.dart';

class DigitDashScreen extends StatefulWidget {
  const DigitDashScreen({super.key});

  @override
  State<DigitDashScreen> createState() => _DigitDashScreenState();
}

class _DigitDashScreenState extends State<DigitDashScreen>
    with TickerProviderStateMixin, GameRoundMixin<DigitDashScreen> {
  double stakeAmount = 10.0;
  int predictedDigit = 5;

  late final AnimationController _settleController;
  late final AnimationController _flashController;
  Animation<double>? _settleAnimation;
  Timer? _wheelTicker;
  double _wheelAngle = 0;

  bool _isSpinning = false;
  bool _matchMode = true;
  int? resultDigit;
  String _status = 'Select a digit and mode to begin';

  @override
  void initState() {
    super.initState();
    _settleController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 950),
        )..addListener(() {
          setState(() {
            if (_settleAnimation != null) {
              _wheelAngle = _settleAnimation!.value;
            }
          });
        });
    _settleController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _isSpinning = false);
        _flashController
          ..reset()
          ..repeat(reverse: true);
      }
    });

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() {
    _wheelTicker?.cancel();
    _settleController.dispose();
    _flashController.dispose();
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
              Icons.currency_exchange,
              color: Colors.blueAccent,
              size: 20,
            ),
            const SizedBox(width: 8),
            const Text(
              'BTC/USD',
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
                        image: AssetImage('assets/images/digit_dash_bg.png'),
                        fit: BoxFit.cover,
                        opacity: 0.3,
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
                        Center(
                          child: AnimatedBuilder(
                            animation: _flashController,
                            builder: (context, child) {
                              return Transform.rotate(
                                angle: _wheelAngle,
                                child: CustomPaint(
                                  size: const Size(380, 380),
                                  painter: _RoulettePainter(
                                    selectedIndex: resultDigit,
                                    flashValue: _flashController.value,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Align(
                          alignment: Alignment.topCenter,
                          child: Container(
                            margin: const EdgeInsets.only(top: 16),
                            child: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                              size: 56,
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
                                  color: Colors.blueAccent.withValues(
                                    alpha: 0.2,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'DIGIT DASH',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.blueAccent,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Matches / Differs',
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'PREDICTED LAST DIGIT',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF94a3b8),
                              letterSpacing: 0.5,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: Text(
                              '$predictedDigit',
                              style: const TextStyle(
                                color: Colors.blueAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: 10,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final isSelected = predictedDigit == index;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => predictedDigit = index),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 40,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? Colors.blueAccent
                                      : AppTheme.surfaceDark,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? Colors.blueAccent
                                        : AppTheme.borderDark,
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '$index',
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : const Color(0xFF64748b),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildControlPanel(
                        label: 'STAKE',
                        value: '\$${stakeAmount.toStringAsFixed(2)}',
                        icon: Icons.monetization_on,
                        onDecrease: () => setState(
                          () => stakeAmount > 1 ? stakeAmount -= 1 : null,
                        ),
                        onIncrease: () => setState(() => stakeAmount += 1),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Matches: 900.0% | Differs: 9.9%',
                            style: TextStyle(
                              color: Color(0xFF94a3b8),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Est: \$${(stakeAmount * 10.00).toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _status,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _buildTradeButton(
                              label: 'DIFFERS',
                              icon: Icons.difference,
                              color: const Color(0xFF0ea5e9),
                              busy: _isSpinning && !_matchMode,
                              onTap: () => _playDigitBet(false),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildTradeButton(
                              label: 'MATCHES',
                              icon: Icons.done_all,
                              color: const Color(0xFF3b82f6),
                              busy: _isSpinning && _matchMode,
                              onTap: () => _playDigitBet(true),
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
                  decoration: const BoxDecoration(
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
                  decoration: const BoxDecoration(
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
    required VoidCallback onTap,
    bool busy = false,
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
          onTap: busy ? null : onTap,
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
                  fontSize: 16,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _playDigitBet(bool matchMode) async {
    if (_isSpinning) return;
    final canPlay = await BalanceGuard.ensurePlayableStake(
      context,
      stakeAmount,
    );
    if (!canPlay) return;

    setState(() {
      _matchMode = matchMode;
      _status = 'Placing bet...';
      _isSpinning = true;
      resultDigit = null;
    });
    _flashController.stop();
    _wheelTicker?.cancel();

    try {
      await placeGameBet(
        gameType: 'DIGIT_DASH',
        stakeUsd: stakeAmount,
        prediction: _buildPrediction(matchMode),
      );
      if (!mounted) return;
      setState(() => _status = 'Listening for a response...');
      _startWheelLoop();
      showGameMessage(
        context,
        '${matchMode ? "MATCH" : "DIFFERS"} armed at '
        '\$${stakeAmount.toStringAsFixed(2)}',
      );
    } on GameSocketException catch (err) {
      if (!mounted) return;
      setState(() {
        _isSpinning = false;
        _status = err.message;
      });
      showGameMessage(context, err.message);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _isSpinning = false;
        _status = 'Bet failed';
      });
      showGameMessage(context, 'Bet failed: $err');
    }
  }

  Map<String, dynamic> _buildPrediction(bool matchMode) {
    return {
      'direction': matchMode ? 'MATCH' : 'DIFF',
      'derivContractType': matchMode ? 'DIGITMATCH' : 'DIGITDIFF',
      'barrier': predictedDigit.toString(),
      'digitPrediction': predictedDigit,
      'durationTicks': 1,
      'duration': 1,
      'durationUnit': 't',
      'symbol': 'R_10',
    };
  }

  void _startWheelLoop() {
    _wheelTicker?.cancel();
    _wheelTicker = Timer.periodic(const Duration(milliseconds: 65), (_) {
      setState(() {
        _wheelAngle += math.pi / 24;
      });
    });
  }

  void _settleWheel(int digit) {
    _wheelTicker?.cancel();
    final segmentAngle = (math.pi * 2) / 10;
    final target = _wheelAngle + (math.pi * 4) - (digit * segmentAngle);
    _settleAnimation = Tween<double>(begin: _wheelAngle, end: target).animate(
      CurvedAnimation(parent: _settleController, curve: Curves.easeOutCubic),
    );
    _settleController
      ..reset()
      ..forward();
  }

  int _resolveDigit(bool win) {
    if (_matchMode) {
      return win ? predictedDigit : _randomOtherDigit(predictedDigit);
    }
    return win ? _randomOtherDigit(predictedDigit) : predictedDigit;
  }

  int _randomOtherDigit(int exclude) {
    final rnd = math.Random();
    int digit = exclude;
    while (digit == exclude) {
      digit = rnd.nextInt(10);
    }
    return digit;
  }

  @override
  void onGameResult(GameResultEvent event) {
    final win = event.outcome.toUpperCase() == 'WIN';
    final digit = _resolveDigit(win);
    setState(() {
      resultDigit = digit;
      _status = win
          ? 'WIN · +\$${event.winAmountUsd.toStringAsFixed(2)}'
          : 'Round ${event.outcome}';
    });
    _settleWheel(digit);
    showGameMessage(
      context,
      win
          ? 'You won \$${event.winAmountUsd.toStringAsFixed(2)}'
          : 'Round ${event.outcome}',
    );
  }

  @override
  void onBetRejected(GameBetRejected event) {
    _wheelTicker?.cancel();
    setState(() {
      _isSpinning = false;
      _status = 'Bet rejected: ${event.reason}';
    });
    showGameMessage(context, 'Bet rejected: ${event.reason}');
  }

  @override
  void onGameError(GameErrorEvent event) {
    _wheelTicker?.cancel();
    setState(() {
      _isSpinning = false;
      _status = event.message;
    });
  }
}

class _RoulettePainter extends CustomPainter {
  final int? selectedIndex;
  final double flashValue;

  _RoulettePainter({this.selectedIndex, this.flashValue = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width / 2, size.height / 2);
    final sweepAngle = (math.pi * 2) / 10;

    for (int i = 0; i < 10; i++) {
      final startAngle = -math.pi / 2 + (i * sweepAngle) - (sweepAngle / 2);

      Color segmentColor = (i % 2 == 0)
          ? Colors.blueAccent.withValues(alpha: 0.8)
          : AppTheme.surfaceDark;

      if (selectedIndex == i) {
        segmentColor = Color.lerp(
          segmentColor,
          Colors.yellow,
          flashValue * 0.7,
        )!;
      }

      final paint = Paint()
        ..color = segmentColor
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      final borderPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.1)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        borderPaint,
      );

      final textSpan = TextSpan(
        text: i.toString(),
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
          shadows: [
            if (selectedIndex == i)
              Shadow(
                color: Colors.yellow.withValues(alpha: flashValue),
                blurRadius: 20 * flashValue,
              ),
          ],
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      )..layout();

      final textAngle = -math.pi / 2 + (i * sweepAngle);
      final textRadius = radius * 0.7;

      final textCenter = Offset(
        center.dx + textRadius * math.cos(textAngle),
        center.dy + textRadius * math.sin(textAngle),
      );

      canvas.save();
      canvas.translate(textCenter.dx, textCenter.dy);
      canvas.rotate(textAngle + math.pi / 2);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();
    }

    canvas.drawCircle(
      center,
      radius * 0.3,
      Paint()..color = AppTheme.backgroundDark,
    );
    canvas.drawCircle(
      center,
      radius * 0.3,
      Paint()
        ..color = Colors.blueAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _RoulettePainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.flashValue != flashValue;
  }
}
