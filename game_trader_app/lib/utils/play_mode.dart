import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/game_service.dart';
import 'balance_guard.dart';

enum PlayMode { demo, real }

extension PlayModeLabel on PlayMode {
  bool get isDemo => this == PlayMode.demo;

  String get label {
    switch (this) {
      case PlayMode.demo:
        return 'Demo';
      case PlayMode.real:
        return 'Real';
    }
  }

  String get statusPrefix => isDemo ? 'Demo' : 'Real';
}

Future<bool> ensureStakeForPlayMode(
  BuildContext context,
  PlayMode playMode,
  double stakeUsd,
) {
  if (playMode.isDemo) {
    return Future.value(true);
  }
  return BalanceGuard.ensurePlayableStake(context, stakeUsd);
}

GameResultEvent buildDemoGameResult({
  required String gameType,
  required double stakeUsd,
  required double payoutMultiplier,
  double winChance = 0.48,
  math.Random? rng,
}) {
  final random = rng ?? math.Random();
  final win = random.nextDouble() < winChance;
  final payoutUsd = win ? stakeUsd * payoutMultiplier : 0.0;
  final winAmountUsd = win ? math.max(0.0, payoutUsd - stakeUsd) : 0.0;
  final id = DateTime.now().microsecondsSinceEpoch.toString();

  return GameResultEvent(
    sessionId: 'demo-$id',
    userId: 'demo',
    gameType: gameType,
    outcome: win ? 'WIN' : 'LOSS',
    payoutUsd: payoutUsd,
    winAmountUsd: winAmountUsd,
    stakeUsd: stakeUsd,
    newBalance: 0,
    traceId: 'demo-$id',
  );
}
