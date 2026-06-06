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

enum _LootTier { common, silver, gold, obsidian, mythic }

extension _LootTierMeta on _LootTier {
  String get label {
    switch (this) {
      case _LootTier.common:
        return 'Common';
      case _LootTier.silver:
        return 'Silver';
      case _LootTier.gold:
        return 'Gold';
      case _LootTier.obsidian:
        return 'Obsidian';
      case _LootTier.mythic:
        return 'Mythic';
    }
  }

  String get chip {
    switch (this) {
      case _LootTier.common:
        return 'C';
      case _LootTier.silver:
        return 'S';
      case _LootTier.gold:
        return 'G';
      case _LootTier.obsidian:
        return 'O';
      case _LootTier.mythic:
        return 'M';
    }
  }

  double get payoutWeight {
    switch (this) {
      case _LootTier.common:
        return 1.00;
      case _LootTier.silver:
        return 1.15;
      case _LootTier.gold:
        return 1.35;
      case _LootTier.obsidian:
        return 1.70;
      case _LootTier.mythic:
        return 2.10;
    }
  }

  Color get accent {
    switch (this) {
      case _LootTier.common:
        return const Color(0xFF919191);
      case _LootTier.silver:
        return const Color(0xFFB8B8B8);
      case _LootTier.gold:
        return AppTheme.goldButtonBottom;
      case _LootTier.obsidian:
        return const Color(0xFF232323);
      case _LootTier.mythic:
        return const Color(0xFFEFC85F);
    }
  }
}

class LootBoxPoolScreen extends StatefulWidget {
  const LootBoxPoolScreen({super.key});

  @override
  State<LootBoxPoolScreen> createState() => _LootBoxPoolScreenState();
}

class _LootBoxPoolScreenState extends State<LootBoxPoolScreen> {
  static const int _poolSize = 20;
  static const int _winnerCount = 5;
  static const double _commissionRate = 0.15;
  static const int _seatCount = 20;

  final math.Random _rng = math.Random();

  double _stakeUsd = BalanceGuard.minStakeUsd;
  PlayMode _playMode = PlayMode.demo;
  int? _selectedNumber;
  int _roundNumber = 1;
  bool _isDrawing = false;
  String _status = 'Pick one box from 1 to 20 to join the pot round.';

  late Map<int, _LootTier> _boxTiers;
  List<int> _winningNumbers = const [];
  _LootPoolOutcome? _lastOutcome;

  static const List<String> _botNames = [
    'Atlas',
    'Nova',
    'Rex',
    'Iris',
    'Flux',
    'Echo',
    'Vega',
    'Pyro',
    'Kite',
    'Drift',
    'Rune',
    'Bolt',
    'Lux',
    'Zeph',
    'Mint',
    'Dusk',
    'Onyx',
    'Sable',
    'Pace',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SessionManager>().gameService.viewGame('loot_box_pool');
      }
    });
    _boxTiers = _generateLootTiers();
  }

  Map<int, _LootTier> _generateLootTiers() {
    final tiers = <int, _LootTier>{};
    for (var number = 1; number <= _poolSize; number++) {
      tiers[number] = _randomTier();
    }
    return tiers;
  }

  _LootTier _randomTier() {
    final roll = _rng.nextDouble();
    if (roll < 0.40) return _LootTier.common;
    if (roll < 0.68) return _LootTier.silver;
    if (roll < 0.86) return _LootTier.gold;
    if (roll < 0.96) return _LootTier.obsidian;
    return _LootTier.mythic;
  }

  Future<void> _runRound() async {
    if (_isDrawing) return;
    final pick = _selectedNumber;
    if (pick == null) {
      showGameMessage(context, 'Select a number first.');
      return;
    }

    final canPlay = await ensureStakeForPlayMode(context, _playMode, _stakeUsd);
    if (!canPlay) return;
    if (!mounted) return;

    setState(() {
      _isDrawing = true;
      _winningNumbers = const [];
      _lastOutcome = null;
      _status = 'Locking 20 seats and filling the loot pot...';
    });
    if (_playMode.isDemo) {
      final session = context.read<SessionManager>();
      if (!session.deductDemoBalance(_stakeUsd)) {
        showGameMessage(context, 'Insufficient demo balance.');
        return;
      }
      showGameMessage(context, 'Demo pot. Wallet unchanged.');
    }

    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;

    setState(() {
      _status = 'Drawing 5 winning boxes...';
    });
    await Future<void>.delayed(const Duration(milliseconds: 850));
    if (!mounted) return;

    final outcome = _simulateRound(userNumber: pick, userStake: _stakeUsd);
    final userNet = outcome.userPayout - outcome.userStake;

    setState(() {
      _isDrawing = false;
      _winningNumbers = outcome.winningNumbers;
      _lastOutcome = outcome;
      _roundNumber += 1;
      _status = outcome.userPayout > 0
          ? 'You won ${formatCurrency(userNet.abs())} from this pot.'
          : 'No hit this round. 5 winners split 85% of the pot.';
    });

    showGameMessage(
      context,
      outcome.userPayout > 0
          ? 'Win: ${formatCurrency(outcome.userPayout)} from prize pool.'
          : 'No payout this round. Try a different number.',
    );

    if (_playMode.isDemo && outcome.userPayout > 0) {
      context.read<SessionManager>().addDemoWinnings(outcome.userPayout);
    }
  }

  _LootPoolOutcome _simulateRound({
    required int userNumber,
    required double userStake,
  }) {
    final seats = List<_RoundSeat>.generate(_seatCount, (index) {
      final number = index + 1;
      final tier = _boxTiers[number] ?? _LootTier.common;
      if (number == userNumber) {
        return _RoundSeat(
          name: 'You',
          number: number,
          stake: userStake,
          tier: tier,
          isUser: true,
        );
      }

      final botStake = (userStake * (0.65 + _rng.nextDouble() * 1.65)).clamp(
        1.0,
        1200.0,
      );
      final roundedStake = _roundMoney(botStake);
      return _RoundSeat(
        name: _botNames[index - (index > userNumber - 1 ? 1 : 0)],
        number: number,
        stake: roundedStake,
        tier: tier,
      );
    });

    final winningNumbers = _drawWinningNumbers();
    final winners = seats
        .where((seat) => winningNumbers.contains(seat.number))
        .toList();

    final pot = _roundMoney(
      seats.fold<double>(0, (sum, seat) => sum + seat.stake),
    );
    final commission = _roundMoney(pot * _commissionRate);
    final distributable = _roundMoney(pot - commission);

    final totalWeight = winners.fold<double>(
      0,
      (sum, seat) => sum + seat.tier.payoutWeight,
    );

    final winnerPayouts = <_WinnerPayout>[];
    var allocated = 0.0;
    for (var index = 0; index < winners.length; index++) {
      final winner = winners[index];
      final isLast = index == winners.length - 1;
      final payout = isLast
          ? _roundMoney(distributable - allocated)
          : _roundMoney(
              distributable * (winner.tier.payoutWeight / totalWeight),
            );
      allocated = _roundMoney(allocated + payout);

      winnerPayouts.add(
        _WinnerPayout(
          name: winner.name,
          number: winner.number,
          tier: winner.tier,
          payout: payout,
          isUser: winner.isUser,
        ),
      );
    }

    winnerPayouts.sort((a, b) => b.payout.compareTo(a.payout));
    final userPayout = winnerPayouts
        .where((winner) => winner.isUser)
        .fold<double>(0, (sum, winner) => sum + winner.payout);

    return _LootPoolOutcome(
      seats: seats,
      pot: pot,
      commission: commission,
      distributable: distributable,
      winningNumbers: winningNumbers,
      winners: winnerPayouts,
      userPayout: userPayout,
      userStake: userStake,
    );
  }

  List<int> _drawWinningNumbers() {
    final numbers = List<int>.generate(_poolSize, (index) => index + 1)
      ..shuffle(_rng);
    final winners = numbers.take(_winnerCount).toList()..sort();
    return winners;
  }

  double _roundMoney(double value) => (value * 100).roundToDouble() / 100;

  String _compactMoney(double value) {
    if (value >= 1000000) {
      return '\$${(value / 1000000).toStringAsFixed(1)}m';
    }
    if (value >= 1000) {
      return '\$${(value / 1000).toStringAsFixed(1)}k';
    }
    return '\$${value.toStringAsFixed(0)}';
  }

  void _pickRandomNumber() {
    if (_isDrawing) return;
    setState(() {
      _selectedNumber = _rng.nextInt(_poolSize) + 1;
      _status =
          'Number $_selectedNumber locked. Start the round when you are ready.';
    });
  }

  void _refreshLootBoxes() {
    if (_isDrawing) return;
    setState(() {
      _boxTiers = _generateLootTiers();
      _winningNumbers = const [];
      _lastOutcome = null;
      _status = 'Loot boxes shuffled. Pick your number.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      backgroundColor: AppTheme.gameBackground,
      appBar: const GameActivityAppBar(title: 'Loot Box Pool (Multi)'),
      bottomNavigationBar: PlayModeBottomBar(
        value: _playMode,
        enabled: !_isDrawing,
        onChanged: (mode) => setState(() => _playMode = mode),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                children: [
                  _buildRoundSummary(),
                  const SizedBox(height: 10),
                  _buildBoard(),
                  const SizedBox(height: 10),
                  if (_lastOutcome != null) _buildRoundResult(),
                  if (_lastOutcome != null) const SizedBox(height: 10),
                  _buildRules(),
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
                    enabled: !_isDrawing,
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
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPillButton(
                          label: 'Quick Pick',
                          icon: Icons.casino_outlined,
                          onTap: _isDrawing ? null : _pickRandomNumber,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildPillButton(
                          label: 'Shuffle Boxes',
                          icon: Icons.grid_view_outlined,
                          onTap: _isDrawing ? null : _refreshLootBoxes,
                        ),
                      ),
                    ],
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

  Widget _buildRoundSummary() {
    final last = _lastOutcome;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _statTile(label: 'Round', value: '#$_roundNumber'),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statTile(
              label: 'Winners',
              value: '$_winnerCount/$_poolSize',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statTile(
              label: 'Platform',
              value: '15%',
              detail: last == null
                  ? null
                  : '${formatCurrency(last.commission)} • ${last.seats.length}/$_seatCount',
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required String label,
    required String value,
    String? detail,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 1),
            Text(
              detail,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBoard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Loot Boxes (1-20)',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Each number is one seat. Exactly 5 seats win each session.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _poolSize,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.92,
            ),
            itemBuilder: (context, index) {
              final number = index + 1;
              return _buildBox(number);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBox(int number) {
    final tier = _boxTiers[number] ?? _LootTier.common;
    final selected = _selectedNumber == number;
    final isWinning = _winningNumbers.contains(number);
    final winnerPayout = _lastOutcome == null
        ? 0.0
        : _lastOutcome!.winnerPayoutFor(number);

    final tileGradient = isWinning
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF171717), Color(0xFF40300A)],
          )
        : selected
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
          )
        : null;

    final textColor = isWinning
        ? Colors.white
        : selected
        ? AppTheme.goldText
        : AppTheme.textPrimary;

    final box = PressScale(
      enabled: !_isDrawing,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _isDrawing
              ? null
              : () {
                  setState(() {
                    _selectedNumber = number;
                    _status =
                        'Number $number selected. This seat joins the next pot.';
                  });
                },
          child: Ink(
            decoration: BoxDecoration(
              color: tileGradient == null ? AppTheme.gameBackground : null,
              gradient: tileGradient,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isWinning || selected
                    ? AppTheme.goldButtonBottom
                    : AppTheme.gameBorder,
                width: isWinning || selected ? 2 : 1,
              ),
            ),
            child: Stack(
              children: [
                Positioned(
                  top: 7,
                  left: 7,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: tier.accent,
                    ),
                  ),
                ),
                if (isWinning)
                  const Positioned(
                    top: 4,
                    right: 4,
                    child: Icon(
                      Icons.workspace_premium,
                      color: Color(0xFFEEC654),
                      size: 14,
                    ),
                  ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 16,
                        color: textColor.withValues(alpha: 0.9),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$number',
                        style: TextStyle(
                          color: textColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        tier.chip,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.85),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (winnerPayout > 0) ...[
                        const SizedBox(height: 1),
                        Text(
                          _compactMoney(winnerPayout),
                          style: const TextStyle(
                            color: Color(0xFF8FE5B3),
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!isWinning || _lastOutcome == null) return box;
    return _FlashingWinningBox(child: box);
  }

  Widget _buildRoundResult() {
    final outcome = _lastOutcome!;
    final userNet = outcome.userPayout - outcome.userStake;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Winning numbers: ${outcome.winningNumbers.join(', ')}',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Pot: ${formatCurrency(outcome.pot)} • Platform 15%: ${formatCurrency(outcome.commission)}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Prize pool distributed: ${formatCurrency(outcome.distributable)}',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            outcome.userPayout > 0
                ? 'Your return: +${formatCurrency(userNet)}'
                : 'Your return: -${formatCurrency(outcome.userStake)}',
            style: TextStyle(
              color: outcome.userPayout > 0
                  ? AppTheme.success
                  : AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          ...outcome.winners.map((winner) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${winner.isUser ? 'You' : winner.name} • #${winner.number} (${winner.tier.label}) • ${formatCurrency(winner.payout)}',
                style: TextStyle(
                  color: winner.isUser
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: winner.isUser ? FontWeight.w800 : FontWeight.w700,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRules() {
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
            'Rules',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 4),
          Text(
            '1) 20 players fill 20 numbered loot boxes each round.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '2) Exactly 5 numbers are drawn as winners.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '3) The round pot is all player stakes combined.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '4) Platform commission is fixed at 15% every session.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            '5) Remaining 85% is split across winning boxes by loot rarity weight.',
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

  Widget _buildPillButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;

    return PressScale(
      enabled: enabled,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: enabled
                ? const [AppTheme.goldButtonTop, AppTheme.goldButtonBottom]
                : const [AppTheme.goldDisabledTop, AppTheme.goldDisabledBottom],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppTheme.goldButtonBottom.withValues(
              alpha: enabled ? 0.9 : 0.4,
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: AppTheme.goldText.withValues(
                    alpha: enabled ? 1 : 0.65,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.goldText.withValues(
                      alpha: enabled ? 1 : 0.65,
                    ),
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLaunchButton() {
    return PressScale(
      enabled: !_isDrawing,
      child: Container(
        height: 62,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isDrawing
                ? const [AppTheme.goldDisabledTop, AppTheme.goldDisabledBottom]
                : const [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppTheme.goldButtonBottom.withValues(
              alpha: _isDrawing ? 0.4 : 0.9,
            ),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.goldButtonBottom.withValues(
                alpha: _isDrawing ? 0.08 : 0.24,
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
            onTap: _isDrawing ? null : _runRound,
            child: Center(
              child: Text(
                _isDrawing ? 'DRAWING ROUND...' : 'JOIN POT ROUND',
                style: TextStyle(
                  color: AppTheme.goldText.withValues(
                    alpha: _isDrawing ? 0.65 : 1,
                  ),
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: -0.3,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FlashingWinningBox extends StatefulWidget {
  const _FlashingWinningBox({required this.child});

  final Widget child;

  @override
  State<_FlashingWinningBox> createState() => _FlashingWinningBoxState();
}

class _FlashingWinningBoxState extends State<_FlashingWinningBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    if (mounted) {
      context.read<SessionManager>().gameService.leaveGame();
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final glow = 0.35 + (_controller.value * 0.45);
        final scale = 1 + (_controller.value * 0.045);
        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.goldButtonBottom.withValues(alpha: glow),
                  blurRadius: 16 + (_controller.value * 10),
                  spreadRadius: 1 + (_controller.value * 2),
                ),
              ],
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _RoundSeat {
  const _RoundSeat({
    required this.name,
    required this.number,
    required this.stake,
    required this.tier,
    this.isUser = false,
  });

  final String name;
  final int number;
  final double stake;
  final _LootTier tier;
  final bool isUser;
}

class _WinnerPayout {
  const _WinnerPayout({
    required this.name,
    required this.number,
    required this.tier,
    required this.payout,
    required this.isUser,
  });

  final String name;
  final int number;
  final _LootTier tier;
  final double payout;
  final bool isUser;
}

class _LootPoolOutcome {
  const _LootPoolOutcome({
    required this.seats,
    required this.pot,
    required this.commission,
    required this.distributable,
    required this.winningNumbers,
    required this.winners,
    required this.userPayout,
    required this.userStake,
  });

  final List<_RoundSeat> seats;
  final double pot;
  final double commission;
  final double distributable;
  final List<int> winningNumbers;
  final List<_WinnerPayout> winners;
  final double userPayout;
  final double userStake;

  double winnerPayoutFor(int number) {
    for (final winner in winners) {
      if (winner.number == number) return winner.payout;
    }
    return 0;
  }
}
