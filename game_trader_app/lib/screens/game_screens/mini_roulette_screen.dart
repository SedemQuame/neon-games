import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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

enum _RouletteBetMode { color, number }

enum _RouletteColor { black, red }

class MiniRouletteScreen extends StatefulWidget {
  const MiniRouletteScreen({super.key});

  @override
  State<MiniRouletteScreen> createState() => _MiniRouletteScreenState();
}

class _MiniRouletteScreenState extends State<MiniRouletteScreen>
    with GameRoundMixin<MiniRouletteScreen> {
  final math.Random _rng = math.Random();

  double _stakeUsd = BalanceGuard.minStakeUsd;
  PlayMode _playMode = PlayMode.demo;
  _RouletteBetMode _betMode = _RouletteBetMode.color;
  _RouletteColor _selectedColor = _RouletteColor.black;
  int _selectedNumber = 0;
  int _currentResultDigit = 0;

  _RouletteBetMode? _activeMode;
  _RouletteColor? _activeColor;
  int? _activeNumber;

  bool _isPlacing = false;
  bool _isSpinning = false;
  String _status = 'Pick a color or digit, then place your bet.';

  Timer? _spinTicker;

  @override
  void dispose() {
    _stopSpinTicker();
    super.dispose();
  }

  Future<void> _placeSelectedBet() async {
    if (_isPlacing || _isSpinning) return;
    final canPlay = await ensureStakeForPlayMode(context, _playMode, _stakeUsd);
    if (!canPlay) return;
    if (!mounted) return;

    final mode = _betMode;
    final color = _selectedColor;
    final number = _selectedNumber;

    setState(() {
      _isPlacing = true;
      _isSpinning = true;
      _activeMode = mode;
      _activeColor = color;
      _activeNumber = number;
      _status = mode == _RouletteBetMode.color
          ? 'Placing color bet (${_labelForColor(color)})...'
          : 'Placing number match bet ($number)...';
    });
    _startSpinTicker();

    if (_playMode.isDemo) {
      showGameMessage(context, 'Demo round. Wallet unchanged.');
      await Future<void>.delayed(const Duration(milliseconds: 950));
      if (!mounted || !_isSpinning) return;
      onGameResult(
        buildDemoGameResult(
          gameType: mode == _RouletteBetMode.color
              ? 'DUAL_DIMENSION_FLIP'
              : 'DIGIT_DASH',
          stakeUsd: _stakeUsd,
          payoutMultiplier: mode == _RouletteBetMode.color ? 1.95 : 10.0,
          winChance: mode == _RouletteBetMode.color ? 0.49 : 0.10,
          rng: _rng,
        ),
      );
      return;
    }

    try {
      if (mode == _RouletteBetMode.color) {
        await placeGameBet(
          gameType: 'DUAL_DIMENSION_FLIP',
          stakeUsd: _stakeUsd,
          prediction: _buildColorPrediction(color),
        );
      } else {
        await placeGameBet(
          gameType: 'DIGIT_DASH',
          stakeUsd: _stakeUsd,
          prediction: _buildNumberPrediction(number),
        );
      }
      if (!mounted) return;
      setState(() {
        _isPlacing = false;
        _status = 'Bet armed. Waiting for result...';
      });
    } on GameSocketException catch (err) {
      if (!mounted) return;
      _stopSpinTicker();
      setState(() {
        _isPlacing = false;
        _isSpinning = false;
        _status = err.message;
      });
      showGameMessage(context, err.message);
    } catch (err) {
      if (!mounted) return;
      _stopSpinTicker();
      setState(() {
        _isPlacing = false;
        _isSpinning = false;
        _status = 'Bet failed';
      });
      showGameMessage(context, 'Bet failed: $err');
    }
  }

  Map<String, dynamic> _buildColorPrediction(_RouletteColor color) {
    final isBlack = color == _RouletteColor.black;
    const ticks = 5;
    return {
      // Black maps to EVEN, Red maps to ODD.
      'direction': isBlack ? 'EVEN' : 'ODD',
      'derivContractType': isBlack ? 'DIGITEVEN' : 'DIGITODD',
      'durationTicks': ticks,
      'duration': ticks,
      'durationUnit': 't',
      'symbol': 'R_50',
    };
  }

  Map<String, dynamic> _buildNumberPrediction(int digit) {
    return {
      // Number bet uses MATCHES from the existing digit market flow.
      'direction': 'MATCH',
      'derivContractType': 'DIGITMATCH',
      'barrier': digit.toString(),
      'digitPrediction': digit,
      'durationTicks': 1,
      'duration': 1,
      'durationUnit': 't',
      'symbol': 'R_10',
    };
  }

  void _startSpinTicker() {
    _stopSpinTicker();
    _spinTicker = Timer.periodic(const Duration(milliseconds: 85), (_) {
      if (!mounted || !_isSpinning) return;
      setState(() {
        _currentResultDigit = _rng.nextInt(10);
      });
    });
  }

  void _stopSpinTicker() {
    _spinTicker?.cancel();
    _spinTicker = null;
  }

  int _resolveResultDigit(bool win) {
    final mode = _activeMode ?? _betMode;
    if (mode == _RouletteBetMode.number) {
      final target = _activeNumber ?? _selectedNumber;
      return win ? target : _randomOtherDigit(target);
    }

    final color = _activeColor ?? _selectedColor;
    final wantsEven = color == _RouletteColor.black;
    final resolvedEven = win ? wantsEven : !wantsEven;
    return _randomDigitWithParity(resolvedEven);
  }

  int _randomDigitWithParity(bool even) {
    int value;
    do {
      value = _rng.nextInt(10);
    } while ((value % 2 == 0) != even);
    return value;
  }

  int _randomOtherDigit(int excluded) {
    int value = excluded;
    while (value == excluded) {
      value = _rng.nextInt(10);
    }
    return value;
  }

  String _labelForColor(_RouletteColor color) {
    return color == _RouletteColor.black ? 'BLACK' : 'RED';
  }

  @override
  void onGameResult(GameResultEvent event) {
    final win = event.outcome.toUpperCase() == 'WIN';
    final resultDigit = _resolveResultDigit(win);

    _stopSpinTicker();
    if (!mounted) return;
    setState(() {
      _isPlacing = false;
      _isSpinning = false;
      _currentResultDigit = resultDigit;
      _status = win
          ? 'WIN · +\$${event.winAmountUsd.toStringAsFixed(2)}'
          : 'Round ${event.outcome}';
    });

    showGameMessage(
      context,
      win
          ? 'You won \$${event.winAmountUsd.toStringAsFixed(2)}'
          : 'Round ${event.outcome}',
    );
  }

  @override
  void onBetRejected(GameBetRejected event) {
    _stopSpinTicker();
    if (!mounted) return;
    setState(() {
      _isPlacing = false;
      _isSpinning = false;
      _status = 'Bet rejected: ${event.reason}';
    });
    showGameMessage(context, 'Bet rejected: ${event.reason}');
  }

  @override
  void onGameError(GameErrorEvent event) {
    _stopSpinTicker();
    if (!mounted) return;
    setState(() {
      _isPlacing = false;
      _isSpinning = false;
      _status = event.message;
    });
    showGameMessage(context, event.message);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.gameBackground,
      appBar: const GameActivityAppBar(title: 'Mini Roulette'),
      bottomNavigationBar: PlayModeBottomBar(
        value: _playMode,
        enabled: !_isPlacing && !_isSpinning,
        onChanged: (mode) => setState(() => _playMode = mode),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                children: [
                  _buildResultBoard(),
                  const SizedBox(height: 10),
                  _buildBetTypeSelector(),
                  const SizedBox(height: 10),
                  if (_betMode == _RouletteBetMode.color)
                    _buildColorPicker()
                  else
                    _buildNumberPicker(),
                  const SizedBox(height: 10),
                  _buildRulesCard(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
              decoration: BoxDecoration(
                color: AppTheme.gameBackground,
                border: Border(top: BorderSide(color: AppTheme.gameBorder)),
              ),
              child: Column(
                children: [
                  StakeAdjuster(
                    label: 'STAKE',
                    value: _stakeUsd,
                    enabled: !_isPlacing && !_isSpinning,
                    onChanged: (next) => setState(() => _stakeUsd = next),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _status,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _betMode == _RouletteBetMode.color
                          ? 'Action: Bet on BLACK/RED (mapped to EVEN/ODD).'
                          : 'Action: Match your chosen digit (0-9).',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildLaunchButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultBoard() {
    final isEven = _currentResultDigit % 2 == 0;
    final bg = isEven ? const Color(0xFF101010) : const Color(0xFF9E2A2A);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        children: [
          const Text(
            'Result Digit',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.goldButtonBottom, width: 3),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.goldButtonBottom.withValues(alpha: 0.22),
                  blurRadius: 18,
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Center(
              child: Text(
                '$_currentResultDigit',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 56,
                  fontWeight: FontWeight.w900,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isEven ? 'BLACK (EVEN)' : 'RED (ODD)',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBetTypeSelector() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildModeButton(
              label: 'Color Bet',
              selected: _betMode == _RouletteBetMode.color,
              onTap: () => setState(() => _betMode = _RouletteBetMode.color),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildModeButton(
              label: 'Number Bet',
              selected: _betMode == _RouletteBetMode.number,
              onTap: () => setState(() => _betMode = _RouletteBetMode.number),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return PressScale(
      enabled: !_isPlacing && !_isSpinning,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
                )
              : null,
          color: selected ? null : AppTheme.gameBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.goldButtonBottom : AppTheme.gameBorder,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: (_isPlacing || _isSpinning) ? null : onTap,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? AppTheme.goldText : AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Pick BLACK or RED',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'BLACK uses EVEN contract, RED uses ODD contract.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildColorOptionButton(
                  label: 'BLACK',
                  helper: 'Even',
                  swatch: const Color(0xFF0F0F10),
                  selected: _selectedColor == _RouletteColor.black,
                  onTap: () =>
                      setState(() => _selectedColor = _RouletteColor.black),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildColorOptionButton(
                  label: 'RED',
                  helper: 'Odd',
                  swatch: const Color(0xFFA52C2C),
                  selected: _selectedColor == _RouletteColor.red,
                  onTap: () =>
                      setState(() => _selectedColor = _RouletteColor.red),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildColorOptionButton({
    required String label,
    required String helper,
    required Color swatch,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final disabled = _isPlacing || _isSpinning;
    return PressScale(
      enabled: !disabled,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.goldText : AppTheme.goldButtonBottom,
            width: selected ? 2.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.goldButtonBottom.withValues(alpha: 0.26),
                    blurRadius: 12,
                    spreadRadius: -4,
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: disabled ? null : onTap,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: swatch,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: AppTheme.goldText.withValues(
                          alpha: disabled ? 0.6 : 1,
                        ),
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        letterSpacing: 0.4,
                      ),
                    ),
                    Text(
                      helper.toUpperCase(),
                      style: TextStyle(
                        color: AppTheme.goldText.withValues(
                          alpha: disabled ? 0.55 : 0.72,
                        ),
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberPicker() {
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
          const Text(
            'Pick a number (0-9)',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Number bets are placed using MATCHES.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: 10,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 1.6,
            ),
            itemBuilder: (context, index) {
              final selected = _selectedNumber == index;
              return PressScale(
                enabled: !_isPlacing && !_isSpinning,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: (_isPlacing || _isSpinning)
                        ? null
                        : () => setState(() => _selectedNumber = index),
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: selected
                            ? const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  AppTheme.goldButtonTop,
                                  AppTheme.goldButtonBottom,
                                ],
                              )
                            : null,
                        color: selected ? null : AppTheme.gameBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? AppTheme.goldButtonBottom
                              : AppTheme.gameBorder,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$index',
                          style: TextStyle(
                            color: selected
                                ? AppTheme.goldText
                                : AppTheme.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRulesCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Game Rules',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '1) Color bet: BLACK/RED only, settled via EVEN/ODD.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '2) Number bet: 0-9 only, settled via MATCHES.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '3) Removed: LOW/MID/HIGH and 1-6, 4-9, 7-12 side ranges.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLaunchButton() {
    final busy = _isPlacing || _isSpinning;
    final label = busy
        ? 'SPINNING...'
        : (_betMode == _RouletteBetMode.color
              ? 'PLACE COLOR BET'
              : 'PLACE NUMBER MATCH');

    return PressScale(
      enabled: !busy,
      child: Container(
        width: double.infinity,
        height: 62,
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
          boxShadow: [
            BoxShadow(
              color: AppTheme.goldButtonBottom.withValues(
                alpha: busy ? 0.08 : 0.24,
              ),
              blurRadius: 14,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: busy ? null : _placeSelectedBet,
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: AppTheme.goldText.withValues(alpha: busy ? 0.65 : 1),
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: -0.4,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
