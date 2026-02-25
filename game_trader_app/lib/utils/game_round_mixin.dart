import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/game_service.dart';
import '../services/session_manager.dart';

mixin GameRoundMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<GameEvent>? _gameSubscription;
  String? activeSessionId;
  String? activeTraceId;

  SessionManager get _session => context.read<SessionManager>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _gameSubscription ??= _session.gameEvents.listen(_handleIncomingGameEvent);
  }

  Future<GameBetAccepted> placeGameBet({
    required String gameType,
    required double stakeUsd,
    required Map<String, dynamic> prediction,
  }) async {
    await _session.ensureGameSocket();
    final ack = await _session.gameService.placeBet(
      gameType: gameType,
      stakeUsd: stakeUsd,
      prediction: prediction,
    );
    activeSessionId = ack.sessionId;
    activeTraceId = ack.traceId;
    return ack;
  }

  void _handleIncomingGameEvent(GameEvent event) {
    if (event is GameResultEvent && event.sessionId == activeSessionId) {
      activeSessionId = null;
      activeTraceId = null;
      onGameResult(event);
    } else if (event is GameBetRejected &&
        (activeTraceId == null || event.traceId == activeTraceId)) {
      activeTraceId = null;
      onBetRejected(event);
    } else if (event is GameErrorEvent) {
      onGameError(event);
    }
  }

  @protected
  void onGameResult(GameResultEvent event);

  @protected
  void onBetRejected(GameBetRejected event) {}

  @protected
  void onGameError(GameErrorEvent event) {}

  @override
  void dispose() {
    _gameSubscription?.cancel();
    super.dispose();
  }
}
