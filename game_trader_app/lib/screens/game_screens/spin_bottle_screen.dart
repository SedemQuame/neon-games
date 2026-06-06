import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../widgets/game_scaffold.dart';
import '../../services/session_manager.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../utils/balance_guard.dart';
import '../../utils/format.dart';
import '../../utils/play_mode.dart';
import '../../widgets/game_activity_app_bar.dart';
import '../../widgets/game_message.dart';
import '../../widgets/play_mode_toggle.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/stake_adjuster.dart';

enum _BottleSide { left, right, middle }

enum _SpinMode { solo, multiplayer }

class SpinBottleScreen extends StatefulWidget {
  const SpinBottleScreen.solo({super.key}) : _mode = _SpinMode.solo;

  const SpinBottleScreen.multiplayer({super.key})
    : _mode = _SpinMode.multiplayer;

  final _SpinMode _mode;

  @override
  State<SpinBottleScreen> createState() => _SpinBottleScreenState();
}

class _SpinBottleScreenState extends State<SpinBottleScreen> {
  static const _spinDuration = Duration(milliseconds: 2200);
  static const _commissionRate = 0.15;

  final _rng = math.Random();

  double _stakeUsd = BalanceGuard.minStakeUsd;
  PlayMode _playMode = PlayMode.demo;
  bool _isSpinning = false;
  _BottleSide? _selectedSide;
  double _turns = 0;

  String _status = 'Choose LEFT or RIGHT, then spin';
  int _roundNumber = 1;

  _MultiplayerOutcome? _lastMultiplayerOutcome;
  double? _lastSoloNet;

  bool get _isMultiplayer => widget._mode == _SpinMode.multiplayer;

  Future<void> _startSpin() async {
    if (_isSpinning) return;
    if (_selectedSide == null) {
      showGameMessage(context, 'Select LEFT or RIGHT first');
      return;
    }
    final canPlay = await ensureStakeForPlayMode(context, _playMode, _stakeUsd);
    if (!canPlay) return;
    if (!mounted) return;

    setState(() {
      _isSpinning = true;
      _status = _isMultiplayer
          ? 'Players are joining the round...'
          : 'Spinning bottle...';
      _lastMultiplayerOutcome = null;
      _lastSoloNet = null;
    });
    if (_playMode.isDemo) {
      showGameMessage(context, 'Demo spin. Wallet unchanged.');
    }

    final targetSide = _randomOutcome();
    final targetTurns =
        _turns + 4 + _rng.nextDouble() * 3 + _sideOffset(targetSide);

    setState(() {
      _turns = targetTurns;
    });

    await Future<void>.delayed(
      _spinDuration + const Duration(milliseconds: 100),
    );
    if (!mounted) return;

    if (_isMultiplayer) {
      final outcome = _buildMultiplayerOutcome(
        userSide: _selectedSide!,
        userStake: _stakeUsd,
        resultSide: targetSide,
      );
      final userWin = outcome.userPayout > 0;
      final userNet = outcome.userPayout - _stakeUsd;

      setState(() {
        _isSpinning = false;
        _roundNumber += 1;
        _lastMultiplayerOutcome = outcome;
        _status = targetSide == _BottleSide.middle
            ? 'Bottle stopped in the middle. House keeps the pot.'
            : userWin
            ? 'You won ${formatCurrency(userNet.abs())} from the pot.'
            : 'You lost this pot round.';
      });

      showGameMessage(
        context,
        userWin
            ? 'Win: ${formatCurrency(outcome.userPayout)} payout from pooled pot.'
            : 'Round lost. Pot distributed to winning side.',
      );
    } else {
      final payout = _soloPayout(
        resultSide: targetSide,
        pick: _selectedSide!,
        stake: _stakeUsd,
      );
      final net = payout - _stakeUsd;
      final win = net > 0;

      setState(() {
        _isSpinning = false;
        _roundNumber += 1;
        _lastSoloNet = net;
        _status = targetSide == _BottleSide.middle
            ? 'Middle stop: stake lost this round.'
            : win
            ? 'You won ${formatCurrency(net.abs())}.'
            : 'Round lost. Try again.';
      });

      showGameMessage(
        context,
        win
            ? 'Win: ${formatCurrency(payout)} paid (x2 stake).'
            : 'No payout this round.',
      );
    }
  }

  _BottleSide _randomOutcome() {
    final roll = _rng.nextDouble();
    if (roll < 0.475) return _BottleSide.left;
    if (roll < 0.95) return _BottleSide.right;
    return _BottleSide.middle;
  }

  double _sideOffset(_BottleSide side) {
    switch (side) {
      case _BottleSide.left:
        return 0.12;
      case _BottleSide.right:
        return 0.62;
      case _BottleSide.middle:
        return 0.0;
    }
  }

  double _soloPayout({
    required _BottleSide resultSide,
    required _BottleSide pick,
    required double stake,
  }) {
    if (resultSide == _BottleSide.middle) return 0;
    if (resultSide == pick) return stake * 2;
    return 0;
  }

  _MultiplayerOutcome _buildMultiplayerOutcome({
    required _BottleSide userSide,
    required double userStake,
    required _BottleSide resultSide,
  }) {
    final players = <_RoundPlayer>[
      _RoundPlayer(name: 'You', side: userSide, stake: userStake, isUser: true),
    ];

    final botCount = 1 + _rng.nextInt(4); // 1..4 bots => 2..5 total players
    for (var i = 0; i < botCount; i++) {
      final botSide = _rng.nextBool() ? _BottleSide.left : _BottleSide.right;
      final botStake = (userStake * (0.7 + _rng.nextDouble() * 1.8)).clamp(
        1,
        500,
      );
      players.add(
        _RoundPlayer(
          name: 'P${i + 2}',
          side: botSide,
          stake: (botStake * 100).roundToDouble() / 100,
        ),
      );
    }

    final pot = players.fold<double>(0, (sum, p) => sum + p.stake);
    final commission = pot * _commissionRate;
    final distributable = pot - commission;

    final winners = resultSide == _BottleSide.middle
        ? <_RoundPlayer>[]
        : players.where((p) => p.side == resultSide).toList();

    final payoutPerWinner = winners.isEmpty
        ? 0.0
        : distributable / winners.length;
    final userWon = winners.any((w) => w.isUser);
    final userPayout = userWon ? payoutPerWinner : 0.0;

    return _MultiplayerOutcome(
      players: players,
      pot: pot,
      commission: commission,
      distributable: distributable,
      payoutPerWinner: payoutPerWinner,
      winnerCount: winners.length,
      userPayout: userPayout,
    );
  }


  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SessionManager>().gameService.viewGame('spin_bottle');
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
      appBar: GameActivityAppBar(
        title: _isMultiplayer ? 'Spin the Bottle (Multi)' : 'Spin the Bottle',
      ),
      bottomNavigationBar: PlayModeBottomBar(
        value: _playMode,
        enabled: !_isSpinning,
        onChanged: (mode) => setState(() => _playMode = mode),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.gameSurface,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppTheme.gameBorder),
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.goldText.withValues(alpha: 0.05),
                      blurRadius: 30,
                      spreadRadius: 8,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Text(
                        'Round $_roundNumber',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final size = math.min(
                              constraints.maxWidth,
                              constraints.maxHeight,
                            );
                            return Center(
                              child: SizedBox(
                                width: size,
                                height: size,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              color: Color(0xFFB62E2E),
                                              borderRadius: BorderRadius.only(
                                                topLeft: Radius.circular(999),
                                                bottomLeft: Radius.circular(
                                                  999,
                                                ),
                                              ),
                                            ),
                                            alignment: Alignment.center,
                                            child: const Text(
                                              'LEFT',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 34,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF121212),
                                              borderRadius: BorderRadius.only(
                                                topRight: Radius.circular(999),
                                                bottomRight: Radius.circular(
                                                  999,
                                                ),
                                              ),
                                            ),
                                            alignment: Alignment.center,
                                            child: const Text(
                                              'RIGHT',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w900,
                                                fontSize: 34,
                                                letterSpacing: 1,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Align(
                                      alignment: Alignment.center,
                                      child: Container(
                                        width: 8,
                                        height: size,
                                        color: AppTheme.gameBackground,
                                      ),
                                    ),
                                    const Align(
                                      alignment: Alignment.topCenter,
                                      child: Icon(
                                        Icons.arrow_drop_down,
                                        size: 42,
                                        color: AppTheme.goldText,
                                      ),
                                    ),
                                    AnimatedRotation(
                                      turns: _turns,
                                      duration: _spinDuration,
                                      curve: Curves.easeOutCubic,
                                      child: Icon(
                                        Icons.navigation,
                                        size: size * 0.55,
                                        color: Colors.white.withValues(
                                          alpha: 0.92,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'If the bottle stops in the middle, the bet is a loss',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isMultiplayer
                            ? 'Pot mode • platform commission 15%'
                            : 'Solo mode • pays x2',
                        style: const TextStyle(
                          color: AppTheme.goldText,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
              child: Column(
                children: [
                  StakeAdjuster(
                    label: 'STAKE',
                    value: _stakeUsd,
                    enabled: !_isSpinning,
                    onChanged: (next) => setState(() => _stakeUsd = next),
                  ),
                  if (_isMultiplayer) ...[
                    const SizedBox(height: 10),
                    _buildPotPreview(),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _status,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildChoiceButton(
                          label: 'LEFT',
                          side: _BottleSide.left,
                          color: const Color(0xFFB62E2E),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _buildChoiceButton(
                          label: 'RIGHT',
                          side: _BottleSide.right,
                          color: const Color(0xFF121212),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildSpinButton(),
                  if (_isMultiplayer && _lastMultiplayerOutcome != null) ...[
                    const SizedBox(height: 12),
                    _buildMultiplayerResult(),
                  ],
                  if (!_isMultiplayer && _lastSoloNet != null) ...[
                    const SizedBox(height: 12),
                    _buildSoloResult(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceButton({
    required String label,
    required _BottleSide side,
    required Color color,
  }) {
    final selected = _selectedSide == side;
    final disabled = _isSpinning;

    return PressScale(
      enabled: !disabled,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.goldButtonBottom
                : color.withValues(alpha: 0.35),
            width: selected ? 2.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.goldButtonBottom.withValues(alpha: 0.28),
                    blurRadius: 14,
                    spreadRadius: -4,
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: disabled ? null : () => setState(() => _selectedSide = side),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: disabled ? 0.55 : 1),
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSpinButton() {
    return PressScale(
      enabled: !_isSpinning,
      child: Container(
        height: 62,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isSpinning
                ? const [AppTheme.goldDisabledTop, AppTheme.goldDisabledBottom]
                : const [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.goldButtonBottom.withValues(
              alpha: _isSpinning ? 0.4 : 0.9,
            ),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.goldButtonBottom.withValues(
                alpha: _isSpinning ? 0.08 : 0.24,
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
            onTap: _isSpinning ? null : _startSpin,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.casino,
                  color: AppTheme.goldText.withValues(
                    alpha: _isSpinning ? 0.65 : 1,
                  ),
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  _isSpinning ? 'SPINNING...' : 'SPIN BOTTLE',
                  style: TextStyle(
                    color: AppTheme.goldText.withValues(
                      alpha: _isSpinning ? 0.65 : 1,
                    ),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPotPreview() {
    final estimatedBots = 3;
    final estimatedPot = _stakeUsd * (estimatedBots + 1);
    final estimatedNetPot = estimatedPot * (1 - _commissionRate);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Pot preview: ${formatCurrency(estimatedPot)}',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            'After 15%: ${formatCurrency(estimatedNetPot)}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiplayerResult() {
    final outcome = _lastMultiplayerOutcome!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pot: ${formatCurrency(outcome.pot)} • Commission: ${formatCurrency(outcome.commission)}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Winners: ${outcome.winnerCount} • Payout/winner: ${formatCurrency(outcome.payoutPerWinner)}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            outcome.userPayout > 0
                ? 'You received ${formatCurrency(outcome.userPayout)}'
                : 'You did not win this round',
            style: TextStyle(
              color: outcome.userPayout > 0
                  ? AppTheme.success
                  : AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSoloResult() {
    final net = _lastSoloNet!;
    final win = net > 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Text(
        win
            ? 'Round net: +${formatCurrency(net)}'
            : 'Round net: -${formatCurrency(_stakeUsd)}',
        style: TextStyle(
          color: win ? AppTheme.success : AppTheme.textPrimary,
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RoundPlayer {
  const _RoundPlayer({
    required this.name,
    required this.side,
    required this.stake,
    this.isUser = false,
  });

  final String name;
  final _BottleSide side;
  final double stake;
  final bool isUser;
}

class _MultiplayerOutcome {
  const _MultiplayerOutcome({
    required this.players,
    required this.pot,
    required this.commission,
    required this.distributable,
    required this.payoutPerWinner,
    required this.winnerCount,
    required this.userPayout,
  });

  final List<_RoundPlayer> players;
  final double pot;
  final double commission;
  final double distributable;
  final double payoutPerWinner;
  final int winnerCount;
  final double userPayout;
}
