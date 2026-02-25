import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';

import 'api_client.dart';
import 'app_logger.dart';

class GameService {
  GameService(this._client);

  final ApiClient _client;
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  final _events = StreamController<GameEvent>.broadcast();
  final _pending = <String, Completer<GameBetAccepted>>{};
  Timer? _pingTimer;
  String? _currentToken;

  Stream<GameEvent> get events => _events.stream;

  Future<void> connect(String token) async {
    if (token.isEmpty) return;
    if (_currentToken == token && _channel != null) {
      return;
    }
    await disconnect();
    final uri = Uri.parse('${_client.websocketBase}/ws?token=$token');
    debugPrint('[GameService] connecting to $uri');
    AppLogger.instance.log('ws', 'Connecting to $uri');
    _channel = WebSocketChannel.connect(uri);
    _currentToken = token;
    _subscription = _channel!.stream.listen(
      _handleMessage,
      onError: (error, stackTrace) {
        debugPrint('[GameService] socket error: $error');
        AppLogger.instance.log(
          'ws',
          'Socket error: $error',
          level: LogLevel.error,
        );
        _events.add(GameErrorEvent(error.toString()));
        _failPending(error);
      },
      onDone: () {
        debugPrint('[GameService] socket closed');
        AppLogger.instance.log('ws', 'Socket closed', level: LogLevel.warning);
        _events.add(const GameErrorEvent('Connection closed'));
        _failPending(const GameSocketException('Connection closed'));
        disconnect();
      },
    );
    _startPing();
  }

  Future<void> disconnect() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
    _currentToken = null;
  }

  Future<GameBetAccepted> placeBet({
    required String gameType,
    required double stakeUsd,
    required Map<String, dynamic> prediction,
    String? traceId,
  }) async {
    final channel = _channel;
    if (channel == null) {
      throw const GameSocketException('Not connected to the game server');
    }
    if (stakeUsd <= 0) {
      throw const GameSocketException('Stake must be greater than zero');
    }
    final id = traceId ?? const Uuid().v4();
    final completer = Completer<GameBetAccepted>();
    _pending[id] = completer;

    final payload = <String, dynamic>{
      'type': 'PLACE_BET',
      'gameType': gameType,
      'stakeUsd': stakeUsd,
      'prediction': prediction,
      'traceId': id,
      'clientTs': DateTime.now().toIso8601String(),
    };

    final logMessage = 'PLACE_BET $gameType \$${stakeUsd.toStringAsFixed(2)}';
    debugPrint('[GameService][$id] -> $logMessage');
    AppLogger.instance.log('ws', '[$id] -> $logMessage');
    channel.sink.add(jsonEncode(payload));

    return completer.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        _pending.remove(id);
        throw const GameSocketException('Bet acknowledgement timed out');
      },
    );
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      safeSend(const {'type': 'PING'});
    });
  }

  void safeSend(Map<String, dynamic> data) {
    final channel = _channel;
    if (channel == null) return;
    channel.sink.add(jsonEncode(data));
    AppLogger.instance.log(
      'ws',
      'Outbound: ${data['type'] ?? 'UNKNOWN'}',
      level: LogLevel.debug,
    );
  }

  void _handleMessage(dynamic data) {
    if (data == null) return;
    late GameEvent event;
    var emitEvent = false;
    try {
      final raw = data is String ? data : data.toString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final type = decoded['type']?.toString() ?? '';
      switch (type) {
        case 'CONNECTED':
          event = GameConnectedEvent(
            userId: decoded['userId']?.toString() ?? '',
          );
          emitEvent = true;
          AppLogger.instance.log(
            'ws',
            'Connected as ${decoded['userId']}',
            level: LogLevel.info,
          );
          break;
        case 'BET_ACCEPTED':
          final accepted = GameBetAccepted(
            sessionId: decoded['sessionId']?.toString() ?? '',
            stakeUsd: (decoded['stakeUsd'] as num?)?.toDouble() ?? 0,
            newBalance: (decoded['newBalance'] as num?)?.toDouble() ?? 0,
            traceId: decoded['traceId']?.toString() ?? '',
          );
          event = accepted;
          _completePending(accepted);
          AppLogger.instance.log(
            'ws',
            '[${accepted.traceId}] bet accepted newBalance=${accepted.newBalance}',
          );
          emitEvent = true;
          break;
        case 'BET_REJECTED':
          final rejected = GameBetRejected(
            reason: decoded['reason']?.toString() ?? 'Unknown error',
            traceId: decoded['traceId']?.toString() ?? '',
          );
          event = rejected;
          _failPending(
            GameSocketException(rejected.reason),
            traceId: rejected.traceId,
          );
          AppLogger.instance.log(
            'ws',
            '[${rejected.traceId}] bet rejected: ${rejected.reason}',
            level: LogLevel.warning,
          );
          emitEvent = true;
          break;
        case 'GAME_RESULT':
          final payload =
              decoded['payload'] as Map<String, dynamic>? ?? decoded;
          final result = GameResultEvent(
            sessionId: payload['sessionId']?.toString() ?? '',
            userId: payload['userId']?.toString() ?? '',
            gameType: payload['gameType']?.toString() ?? '',
            outcome: payload['outcome']?.toString() ?? '',
            payoutUsd: (payload['payoutUsd'] as num?)?.toDouble() ?? 0,
            stakeUsd: (payload['stakeUsd'] as num?)?.toDouble() ?? 0,
            newBalance: (payload['newBalance'] as num?)?.toDouble() ?? 0,
            traceId: payload['traceId']?.toString() ?? '',
            derivContractId: payload['derivContractId']?.toString(),
          );
          event = result;
          AppLogger.instance.log(
            'ws',
            '[${result.traceId}] result ${result.outcome} stake=${result.stakeUsd} payout=${result.payoutUsd}',
          );
          emitEvent = true;
          break;
        case 'ERROR':
          final msg = decoded['message']?.toString() ?? 'Unknown error';
          AppLogger.instance.log(
            'ws',
            'Server error: $msg',
            level: LogLevel.error,
          );
          event = GameErrorEvent(msg);
          emitEvent = true;
          break;
        case 'PONG':
          return;
        default:
          debugPrint('[GameService] ignoring message: $decoded');
          return;
      }
    } catch (err, stack) {
      debugPrint('[GameService] failed to decode message: $err\n$stack');
      AppLogger.instance.log(
        'ws',
        'Malformed message: $err',
        level: LogLevel.error,
      );
      event = GameErrorEvent('Malformed server response');
      emitEvent = true;
    }
    if (emitEvent) {
      _events.add(event);
    }
  }

  void _completePending(GameBetAccepted event) {
    final completer = _pending.remove(event.traceId);
    completer?.complete(event);
  }

  void _failPending(Object error, {String? traceId}) {
    if (traceId != null && traceId.isNotEmpty) {
      _pending.remove(traceId)?.completeError(error);
      return;
    }
    if (_pending.isEmpty) return;
    final pending = Map<String, Completer<GameBetAccepted>>.from(_pending);
    _pending.clear();
    for (final completer in pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    AppLogger.instance.log(
      'ws',
      'Cleared pending requests: $error',
      level: LogLevel.error,
    );
  }
}

abstract class GameEvent {
  const GameEvent(this.type);
  final String type;
}

class GameConnectedEvent extends GameEvent {
  const GameConnectedEvent({required this.userId}) : super('CONNECTED');
  final String userId;
}

class GameBetAccepted extends GameEvent {
  const GameBetAccepted({
    required this.sessionId,
    required this.stakeUsd,
    required this.newBalance,
    required this.traceId,
  }) : super('BET_ACCEPTED');

  final String sessionId;
  final double stakeUsd;
  final double newBalance;
  final String traceId;
}

class GameBetRejected extends GameEvent {
  const GameBetRejected({required this.reason, required this.traceId})
    : super('BET_REJECTED');
  final String reason;
  final String traceId;
}

class GameResultEvent extends GameEvent {
  const GameResultEvent({
    required this.sessionId,
    required this.userId,
    required this.gameType,
    required this.outcome,
    required this.payoutUsd,
    required this.stakeUsd,
    required this.newBalance,
    required this.traceId,
    this.derivContractId,
  }) : super('GAME_RESULT');

  final String sessionId;
  final String userId;
  final String gameType;
  final String outcome;
  final double payoutUsd;
  final double stakeUsd;
  final double newBalance;
  final String traceId;
  final String? derivContractId;
}

class GameErrorEvent extends GameEvent {
  const GameErrorEvent(this.message) : super('ERROR');
  final String message;
}

class GameSocketException implements Exception {
  const GameSocketException(this.message);
  final String message;

  @override
  String toString() => 'GameSocketException: $message';
}
