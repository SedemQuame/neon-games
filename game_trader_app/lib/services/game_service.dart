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
  bool _liveStatsRequestPending = false;
  bool _liveStatsUnsupported = false;

  Stream<GameEvent> get events => _events.stream;
  bool get isConnected => _channel != null;

  Future<void> connect(String token) async {
    if (token.isEmpty) return;
    if (_currentToken == token && _channel != null) {
      return;
    }
    await disconnect();
    final uri = Uri.parse('${_client.websocketBase}/ws?token=$token');
    debugPrint('[GameService] connecting to $uri');
    AppLogger.instance.log('ws', 'Connecting to $uri');
    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    _currentToken = token;
    _subscription = channel.stream.listen(
      _handleMessage,
      onError: (error, stackTrace) {
        if (_channel != channel) return;
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
        if (_channel != channel) return;
        debugPrint('[GameService] socket closed');
        AppLogger.instance.log('ws', 'Socket closed', level: LogLevel.warning);
        _events.add(const GameErrorEvent('Connection closed'));
        _failPending(const GameSocketException('Connection closed'));
        unawaited(disconnect());
      },
    );
    try {
      await channel.ready.timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw const GameSocketException('Game server connection timed out');
        },
      );
    } catch (_) {
      if (_channel == channel) {
        await disconnect();
      }
      rethrow;
    }
    _startPing();
  }

  Future<void> disconnect() async {
    _pingTimer?.cancel();
    _pingTimer = null;
    final subscription = _subscription;
    final channel = _channel;
    _subscription = null;
    _channel = null;
    _currentToken = null;
    await subscription?.cancel();
    await channel?.sink.close();
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

  void cashOutBet({
    required String sessionId,
    String? traceId,
    double? multiplier,
  }) {
    final payload = <String, dynamic>{
      'type': 'CASH_OUT_BET',
      'sessionId': sessionId,
    };
    if (traceId != null && traceId.isNotEmpty) {
      payload['traceId'] = traceId;
    }
    if (multiplier != null) {
      payload['multiplier'] = multiplier;
    }
    safeSend(payload);
  }

  void createRoom({
    required String gameKey,
    bool isPublic = false,
    int minPlayers = 2,
    int maxPlayers = 4,
    double stakeUsd = 1,
  }) {
    safeSend({
      'type': 'CREATE_ROOM',
      'gameKey': gameKey,
      'visibility': isPublic ? 'PUBLIC' : 'PRIVATE',
      'minPlayers': minPlayers,
      'maxPlayers': maxPlayers,
      'stakeUsd': stakeUsd,
    });
  }

  void listPublicRooms({String? gameKey}) {
    safeSend({
      'type': 'LIST_PUBLIC_ROOMS',
      if (gameKey != null && gameKey.isNotEmpty) 'gameKey': gameKey,
    });
  }

  void joinRoom(String roomCode) {
    safeSend({'type': 'JOIN_ROOM', 'roomCode': roomCode});
  }

  void leaveRoom() {
    safeSend({'type': 'LEAVE_ROOM'});
  }

  void setRoomReady(bool ready) {
    safeSend({'type': 'SET_ROOM_READY', 'ready': ready});
  }

  void updateRoomStake(double stakeUsd) {
    safeSend({'type': 'UPDATE_ROOM_STAKE', 'stakeUsd': stakeUsd});
  }

  void startRoomRound({double? stakeUsd}) {
    safeSend({
      'type': 'START_ROOM_ROUND',
      if (stakeUsd != null && stakeUsd > 0) 'stakeUsd': stakeUsd,
    });
  }

  void submitRoomAction(Map<String, dynamic> action) {
    safeSend({'type': 'SUBMIT_ROOM_ACTION', 'action': action});
  }

  void inviteToRoom(String targetUserId) {
    safeSend({'type': 'INVITE_TO_ROOM', 'targetUserId': targetUserId});
  }

  void listAvailablePlayers() {
    safeSend(const {'type': 'LIST_AVAILABLE_PLAYERS'});
  }

  void requestLiveStats() {
    if (_liveStatsUnsupported) {
      _events.add(const LiveStatsEvent(livePlayers: 1, gameStats: {}));
      return;
    }
    _liveStatsRequestPending = true;
    safeSend(const {'type': 'GET_LIVE_STATS'});
  }

  void viewGame(String gameKey) {
    safeSend({'type': 'VIEW_GAME', 'gameKey': gameKey});
  }

  void leaveGame() {
    safeSend(const {'type': 'LEAVE_GAME'});
  }

  void kickRoomPlayer(String targetUserId) {
    safeSend({'type': 'KICK_ROOM_PLAYER', 'targetUserId': targetUserId});
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
    try {
      channel.sink.add(jsonEncode(data));
    } catch (error) {
      AppLogger.instance.log(
        'ws',
        'Send failed: $error',
        level: LogLevel.warning,
      );
      _events.add(const GameErrorEvent('Connection closed'));
      unawaited(disconnect());
      return;
    }
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
            livePlayers: (decoded['livePlayers'] as num?)?.toInt(),
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
          final stakeUsd = (payload['stakeUsd'] as num?)?.toDouble() ?? 0;
          final payoutUsd = (payload['payoutUsd'] as num?)?.toDouble() ?? 0;
          final outcome = payload['outcome']?.toString() ?? '';
          double winAmountUsd =
              (payload['winAmountUsd'] as num?)?.toDouble() ?? double.nan;
          if (winAmountUsd.isNaN) {
            if (outcome.toUpperCase() == 'WIN') {
              winAmountUsd = payoutUsd - stakeUsd;
            } else {
              winAmountUsd = 0;
            }
          }
          if (winAmountUsd < 0) {
            winAmountUsd = 0;
          }
          final result = GameResultEvent(
            sessionId: payload['sessionId']?.toString() ?? '',
            userId: payload['userId']?.toString() ?? '',
            gameType: payload['gameType']?.toString() ?? '',
            outcome: outcome,
            payoutUsd: payoutUsd,
            winAmountUsd: winAmountUsd,
            stakeUsd: stakeUsd,
            newBalance: (payload['newBalance'] as num?)?.toDouble() ?? 0,
            traceId: payload['traceId']?.toString() ?? '',
            derivContractId: payload['derivContractId']?.toString(),
          );
          event = result;
          AppLogger.instance.log(
            'ws',
            '[${result.traceId}] result ${result.outcome} stake=${result.stakeUsd} '
                'payout=${result.payoutUsd} win=${result.winAmountUsd}',
          );
          emitEvent = true;
          break;
        case 'ROOM_CREATED':
          final payload =
              decoded['payload'] as Map<String, dynamic>? ?? const {};
          event = RoomCreatedEvent(RoomStateSnapshot.fromJson(payload));
          emitEvent = true;
          break;
        case 'ROOM_STATE':
          final payload =
              decoded['payload'] as Map<String, dynamic>? ?? const {};
          event = RoomStateEvent(RoomStateSnapshot.fromJson(payload));
          emitEvent = true;
          break;
        case 'ROOM_LIST':
          final payload =
              decoded['payload'] as Map<String, dynamic>? ?? const {};
          final items = (payload['rooms'] as List? ?? const [])
              .whereType<Map>()
              .map((item) => RoomSummary.fromJson(item.cast<String, dynamic>()))
              .toList();
          event = RoomListEvent(items);
          emitEvent = true;
          break;
        case 'LIVE_STATS':
          _liveStatsRequestPending = false;
          final payload =
              decoded['payload'] as Map<String, dynamic>? ?? const {};
          final gameStatsRaw = payload['gameStats'] as Map? ?? {};
          final gameStats = <String, int>{};
          for (final key in gameStatsRaw.keys) {
            gameStats[key.toString()] =
                (gameStatsRaw[key] as num?)?.toInt() ?? 0;
          }
          event = LiveStatsEvent(
            livePlayers: (payload['livePlayers'] as num?)?.toInt() ?? 0,
            gameStats: gameStats,
          );
          emitEvent = true;
          break;
        case 'ROOM_INVITE':
          final payload =
              decoded['payload'] as Map<String, dynamic>? ?? const {};
          final roomRaw = payload['room'] as Map<String, dynamic>? ?? const {};
          event = RoomInviteEvent(
            room: RoomSummary.fromJson(roomRaw),
            fromUserId: payload['fromUserId']?.toString() ?? '',
            fromUserName: payload['fromUserName']?.toString() ?? '',
          );
          emitEvent = true;
          break;
        case 'ROOM_ROUND_STARTED':
          final payload =
              decoded['payload'] as Map<String, dynamic>? ?? const {};
          event = RoomRoundStartedEvent(
            RoomRoundStartedPayload.fromJson(payload),
          );
          emitEvent = true;
          break;
        case 'ROOM_ROUND_RESULT':
          final payload =
              decoded['payload'] as Map<String, dynamic>? ?? const {};
          event = RoomRoundResultEvent(
            RoomRoundResultPayload.fromJson(payload),
          );
          emitEvent = true;
          break;
        case 'ROOM_LEFT':
          event = const RoomInfoEvent('LEFT_ROOM');
          emitEvent = true;
          break;
        case 'ROOM_INVITE_SENT':
          event = const RoomInfoEvent('INVITE_SENT');
          emitEvent = true;
          break;
        case 'AVAILABLE_PLAYERS':
          final payload =
              decoded['payload'] as Map<String, dynamic>? ?? const {};
          final players = (payload['players'] as List? ?? const [])
              .whereType<Map>()
              .map(
                (item) =>
                    AvailableRoomPlayer.fromJson(item.cast<String, dynamic>()),
              )
              .toList();
          event = AvailablePlayersEvent(players);
          emitEvent = true;
          break;
        case 'ROOM_PLAYER_KICKED':
          event = const RoomInfoEvent('PLAYER_KICKED');
          emitEvent = true;
          break;
        case 'ROOM_KICKED':
          final payload =
              decoded['payload'] as Map<String, dynamic>? ?? const {};
          event = RoomKickedEvent(
            roomCode: payload['roomCode']?.toString() ?? '',
            gameKey: payload['gameKey']?.toString() ?? '',
            message:
                payload['message']?.toString() ??
                'You were removed from the room',
          );
          emitEvent = true;
          break;
        case 'ROOM_ERROR':
          final message = decoded['message']?.toString() ?? 'Room error';
          event = RoomErrorEvent(message);
          emitEvent = true;
          break;
        case 'ERROR':
          final msg = decoded['message']?.toString() ?? 'Unknown error';
          if (_liveStatsRequestPending &&
              msg.toLowerCase().contains('unknown message type')) {
            _liveStatsRequestPending = false;
            _liveStatsUnsupported = true;
            event = const LiveStatsEvent(livePlayers: 1, gameStats: {});
            emitEvent = true;
            break;
          }
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
  const GameConnectedEvent({required this.userId, this.livePlayers})
    : super('CONNECTED');
  final String userId;
  final int? livePlayers;
}

class LiveStatsEvent extends GameEvent {
  const LiveStatsEvent({required this.livePlayers, required this.gameStats})
    : super('LIVE_STATS');
  final int livePlayers;
  final Map<String, int> gameStats;
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
    required this.winAmountUsd,
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
  final double winAmountUsd;
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

class RoomPlayerSnapshot {
  const RoomPlayerSnapshot({
    required this.userId,
    required this.displayName,
    required this.ready,
    this.joinedAt,
  });

  final String userId;
  final String displayName;
  final bool ready;
  final DateTime? joinedAt;

  factory RoomPlayerSnapshot.fromJson(Map<String, dynamic> json) {
    return RoomPlayerSnapshot(
      userId: json['userId']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      ready: json['ready'] == true,
      joinedAt: json['joinedAt'] != null
          ? DateTime.tryParse(json['joinedAt'].toString())
          : null,
    );
  }
}

class RoomStateSnapshot {
  const RoomStateSnapshot({
    required this.roomCode,
    required this.gameKey,
    required this.visibility,
    required this.hostUserId,
    required this.minPlayers,
    required this.maxPlayers,
    required this.stakeUsd,
    required this.state,
    required this.players,
    this.createdAt,
    this.updatedAt,
  });

  final String roomCode;
  final String gameKey;
  final String visibility;
  final String hostUserId;
  final int minPlayers;
  final int maxPlayers;
  final double stakeUsd;
  final String state;
  final List<RoomPlayerSnapshot> players;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPublic => visibility.toUpperCase() == 'PUBLIC';
  bool get inRound => state.toUpperCase() == 'IN_ROUND';

  factory RoomStateSnapshot.fromJson(Map<String, dynamic> json) {
    return RoomStateSnapshot(
      roomCode: json['roomCode']?.toString() ?? '',
      gameKey: json['gameKey']?.toString() ?? '',
      visibility: json['visibility']?.toString() ?? 'PRIVATE',
      hostUserId: json['hostUserId']?.toString() ?? '',
      minPlayers: (json['minPlayers'] as num?)?.toInt() ?? 2,
      maxPlayers: (json['maxPlayers'] as num?)?.toInt() ?? 4,
      stakeUsd: (json['stakeUsd'] as num?)?.toDouble() ?? 1,
      state: json['state']?.toString() ?? 'WAITING',
      players: (json['players'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => RoomPlayerSnapshot.fromJson(item.cast<String, dynamic>()),
          )
          .toList(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }
}

class RoomSummary {
  const RoomSummary({
    required this.roomCode,
    required this.gameKey,
    required this.hostUserId,
    required this.hostDisplayName,
    required this.playerCount,
    required this.minPlayers,
    required this.maxPlayers,
    required this.stakeUsd,
    this.createdAt,
    this.updatedAt,
  });

  final String roomCode;
  final String gameKey;
  final String hostUserId;
  final String hostDisplayName;
  final int playerCount;
  final int minPlayers;
  final int maxPlayers;
  final double stakeUsd;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory RoomSummary.fromJson(Map<String, dynamic> json) {
    return RoomSummary(
      roomCode: json['roomCode']?.toString() ?? '',
      gameKey: json['gameKey']?.toString() ?? '',
      hostUserId: json['hostUserId']?.toString() ?? '',
      hostDisplayName: json['hostDisplayName']?.toString() ?? '',
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 0,
      minPlayers: (json['minPlayers'] as num?)?.toInt() ?? 2,
      maxPlayers: (json['maxPlayers'] as num?)?.toInt() ?? 4,
      stakeUsd: (json['stakeUsd'] as num?)?.toDouble() ?? 1,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }
}

class RoomRoundStartedPayload {
  const RoomRoundStartedPayload({
    required this.roomCode,
    required this.roundId,
    required this.gameKey,
    required this.requiresAction,
    required this.actionHint,
    required this.actionCount,
    required this.playerCount,
    required this.stakeUsd,
    required this.potUsd,
    required this.commissionUsd,
    required this.distributableUsd,
    required this.choices,
    this.startedAt,
    this.actionDeadline,
    this.rollDeadline,
  });

  final String roomCode;
  final String roundId;
  final String gameKey;
  final bool requiresAction;
  final String actionHint;
  final int actionCount;
  final int playerCount;
  final double stakeUsd;
  final double potUsd;
  final double commissionUsd;
  final double distributableUsd;
  final List<RoomPlayerChoice> choices;
  final DateTime? startedAt;
  final DateTime? actionDeadline;
  final DateTime? rollDeadline;

  factory RoomRoundStartedPayload.fromJson(Map<String, dynamic> json) {
    return RoomRoundStartedPayload(
      roomCode: json['roomCode']?.toString() ?? '',
      roundId: json['roundId']?.toString() ?? '',
      gameKey: json['gameKey']?.toString() ?? '',
      requiresAction: json['requiresAction'] == true,
      actionHint: json['actionHint']?.toString() ?? '',
      actionCount: (json['actionCount'] as num?)?.toInt() ?? 0,
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 0,
      stakeUsd: (json['stakeUsd'] as num?)?.toDouble() ?? 0,
      potUsd: (json['potUsd'] as num?)?.toDouble() ?? 0,
      commissionUsd: (json['commissionUsd'] as num?)?.toDouble() ?? 0,
      distributableUsd: (json['distributableUsd'] as num?)?.toDouble() ?? 0,
      choices: (json['choices'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => RoomPlayerChoice.fromJson(item.cast<String, dynamic>()),
          )
          .toList(),
      startedAt: json['startedAt'] != null
          ? DateTime.tryParse(json['startedAt'].toString())
          : null,
      actionDeadline: json['actionDeadline'] != null
          ? DateTime.tryParse(json['actionDeadline'].toString())
          : null,
      rollDeadline: json['rollDeadline'] != null
          ? DateTime.tryParse(json['rollDeadline'].toString())
          : null,
    );
  }
}

class RoomPlayerChoice {
  const RoomPlayerChoice({
    required this.userId,
    required this.displayName,
    required this.submitted,
    required this.revealed,
    required this.choice,
  });

  final String userId;
  final String displayName;
  final bool submitted;
  final bool revealed;
  final String choice;

  factory RoomPlayerChoice.fromJson(Map<String, dynamic> json) {
    return RoomPlayerChoice(
      userId: json['userId']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      submitted: json['submitted'] == true,
      revealed: json['revealed'] == true,
      choice: json['choice']?.toString() ?? '',
    );
  }
}

class RoomWinnerPayout {
  const RoomWinnerPayout({
    required this.userId,
    required this.displayName,
    required this.payoutUsd,
    required this.newBalance,
  });

  final String userId;
  final String displayName;
  final double payoutUsd;
  final double newBalance;

  factory RoomWinnerPayout.fromJson(Map<String, dynamic> json) {
    return RoomWinnerPayout(
      userId: json['userId']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
      payoutUsd: (json['payoutUsd'] as num?)?.toDouble() ?? 0,
      newBalance: (json['newBalance'] as num?)?.toDouble() ?? 0,
    );
  }
}

class RoomRoundResultPayload {
  const RoomRoundResultPayload({
    required this.roomCode,
    required this.roundId,
    required this.gameKey,
    required this.stakeUsd,
    required this.potUsd,
    required this.commissionUsd,
    required this.distributableUsd,
    required this.payoutPerWinnerUsd,
    required this.winnerUserIds,
    required this.winners,
    required this.summary,
    required this.detail,
    required this.choices,
    required this.participantCount,
    required this.platformCutPercent,
    this.completedAt,
  });

  final String roomCode;
  final String roundId;
  final String gameKey;
  final double stakeUsd;
  final double potUsd;
  final double commissionUsd;
  final double distributableUsd;
  final double payoutPerWinnerUsd;
  final List<String> winnerUserIds;
  final List<RoomWinnerPayout> winners;
  final String summary;
  final Map<String, dynamic> detail;
  final List<RoomPlayerChoice> choices;
  final int participantCount;
  final double platformCutPercent;
  final DateTime? completedAt;

  factory RoomRoundResultPayload.fromJson(Map<String, dynamic> json) {
    return RoomRoundResultPayload(
      roomCode: json['roomCode']?.toString() ?? '',
      roundId: json['roundId']?.toString() ?? '',
      gameKey: json['gameKey']?.toString() ?? '',
      stakeUsd: (json['stakeUsd'] as num?)?.toDouble() ?? 0,
      potUsd: (json['potUsd'] as num?)?.toDouble() ?? 0,
      commissionUsd: (json['commissionUsd'] as num?)?.toDouble() ?? 0,
      distributableUsd: (json['distributableUsd'] as num?)?.toDouble() ?? 0,
      payoutPerWinnerUsd: (json['payoutPerWinnerUsd'] as num?)?.toDouble() ?? 0,
      winnerUserIds: (json['winnerUserIds'] as List? ?? const [])
          .map((item) => item.toString())
          .toList(),
      winners: (json['winners'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => RoomWinnerPayout.fromJson(item.cast<String, dynamic>()),
          )
          .toList(),
      summary: json['summary']?.toString() ?? '',
      detail: (json['detail'] as Map?)?.cast<String, dynamic>() ?? const {},
      choices: (json['choices'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => RoomPlayerChoice.fromJson(item.cast<String, dynamic>()),
          )
          .toList(),
      participantCount: (json['participantCount'] as num?)?.toInt() ?? 0,
      platformCutPercent:
          (json['platformCutPercent'] as num?)?.toDouble() ?? 15,
      completedAt: json['completedAt'] != null
          ? DateTime.tryParse(json['completedAt'].toString())
          : null,
    );
  }
}

class RoomCreatedEvent extends GameEvent {
  const RoomCreatedEvent(this.room) : super('ROOM_CREATED');
  final RoomStateSnapshot room;
}

class RoomStateEvent extends GameEvent {
  const RoomStateEvent(this.room) : super('ROOM_STATE');
  final RoomStateSnapshot room;
}

class RoomListEvent extends GameEvent {
  const RoomListEvent(this.rooms) : super('ROOM_LIST');
  final List<RoomSummary> rooms;
}

class RoomInviteEvent extends GameEvent {
  const RoomInviteEvent({
    required this.room,
    required this.fromUserId,
    required this.fromUserName,
  }) : super('ROOM_INVITE');

  final RoomSummary room;
  final String fromUserId;
  final String fromUserName;
}

class AvailableRoomPlayer {
  const AvailableRoomPlayer({required this.userId, required this.displayName});

  final String userId;
  final String displayName;

  factory AvailableRoomPlayer.fromJson(Map<String, dynamic> json) {
    return AvailableRoomPlayer(
      userId: json['userId']?.toString() ?? '',
      displayName: json['displayName']?.toString() ?? '',
    );
  }
}

class AvailablePlayersEvent extends GameEvent {
  const AvailablePlayersEvent(this.players) : super('AVAILABLE_PLAYERS');

  final List<AvailableRoomPlayer> players;
}

class RoomRoundStartedEvent extends GameEvent {
  const RoomRoundStartedEvent(this.payload) : super('ROOM_ROUND_STARTED');
  final RoomRoundStartedPayload payload;
}

class RoomRoundResultEvent extends GameEvent {
  const RoomRoundResultEvent(this.payload) : super('ROOM_ROUND_RESULT');
  final RoomRoundResultPayload payload;
}

class RoomErrorEvent extends GameEvent {
  const RoomErrorEvent(this.message) : super('ROOM_ERROR');
  final String message;
}

class RoomKickedEvent extends GameEvent {
  const RoomKickedEvent({
    required this.roomCode,
    required this.gameKey,
    required this.message,
  }) : super('ROOM_KICKED');

  final String roomCode;
  final String gameKey;
  final String message;
}

class RoomInfoEvent extends GameEvent {
  const RoomInfoEvent(this.code) : super('ROOM_INFO');
  final String code;
}
