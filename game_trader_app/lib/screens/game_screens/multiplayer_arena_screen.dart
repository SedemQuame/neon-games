import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../widgets/game_scaffold.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../services/game_service.dart';
import '../../services/models.dart' as auth_models;
import '../../services/session_manager.dart';
import '../../utils/app_clipboard.dart';
import '../../utils/format.dart';
import '../../utils/play_mode.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/game_activity_app_bar.dart';
import '../../widgets/game_message.dart';
import '../../widgets/play_mode_toggle.dart';
import '../../widgets/press_scale.dart';
import '../../widgets/stake_adjuster.dart';
import 'multiplayer_game_catalog.dart';

enum _RoomLobbyPanel { controls, invite, players }

class MultiplayerArenaScreen extends StatefulWidget {
  const MultiplayerArenaScreen({
    super.key,
    this.initialGameKey,
    this.initialRoomCode,
  });

  final String? initialGameKey;
  final String? initialRoomCode;

  @override
  State<MultiplayerArenaScreen> createState() => _MultiplayerArenaScreenState();
}

class _MultiplayerArenaScreenState extends State<MultiplayerArenaScreen> {
  final TextEditingController _joinCodeController = TextEditingController();
  final TextEditingController _inviteUserController = TextEditingController();

  StreamSubscription<GameEvent>? _eventsSub;
  Timer? _publicRefreshFallback;
  Timer? _createRoomFallback;
  Timer? _stakeUpdateDebounce;
  Timer? _demoRpsShuffleTimer;
  Timer? _availablePlayersFallback;
  Timer? _readyUpdateFallback;
  Timer? _roomRecoveryFallback;
  late MultiplayerGameDefinition _selected;

  RoomStateSnapshot? _room;
  RoomRoundStartedPayload? _round;
  RoomRoundResultPayload? _lastResult;
  final List<RoomSummary> _publicRooms = [];
  final List<RoomInviteEvent> _pendingInvites = [];
  final List<AvailableRoomPlayer> _availablePlayers = [];

  bool _loadingPublicRooms = false;
  bool _loadingAvailablePlayers = false;
  bool _creatingRoom = false;
  bool _demoResolving = false;
  bool _isRoomPublic = true;
  bool _handledInitialJoin = false;
  bool _resultDialogOpen = false;
  bool _leavingCurrentRoomForRetry = false;
  bool _retryCreateRoomAfterLeave = false;
  bool _pendingHostReadyHandoff = false;
  bool _recoveringRoomConnection = false;
  _RoomStakeFilter _roomStakeFilter = _RoomStakeFilter.any;
  _RoomLobbyPanel _roomLobbyPanel = _RoomLobbyPanel.controls;
  PlayMode _playMode = PlayMode.real;
  int _minPlayers = 2;
  int _maxPlayers = 4;
  double _stakeUsd = 1;

  String _status = 'Join or create a room.';
  String _demoStatus = 'Demo room ready.';
  String? _submittedRoundId;
  String? _retryJoinRoomCode;
  DateTime? _demoRollDeadline;
  _DemoRoomResult? _demoResult;

  String _rpsPick = 'ROCK';
  String? _demoRpsComputerPick;
  int _dicePick = 1;
  int _targetPick = 50;
  int _parityDigit = 0;
  String _coinSide = 'HEADS';
  int _treasureBoxPick = 1;
  int _secretBid = 55;
  String _spinBottleSide = 'LEFT';
  int _lootBoxPick = 1;

  SessionManager get _session => context.read<SessionManager>();

  String get _myUserId => _session.session?.userId ?? '';

  RoomPlayerSnapshot? get _me {
    final room = _room;
    if (room == null) return null;
    for (final player in room.players) {
      if (player.userId == _myUserId) {
        return player;
      }
    }
    return null;
  }

  bool get _isHost => _room?.hostUserId == _myUserId;

  bool get _hasSubmittedAction {
    if (_playMode.isDemo && _demoResolving) return true;
    final round = _round;
    if (round == null) return false;
    if (_submittedRoundId == round.roundId) return true;
    return round.choices.any(
      (choice) => choice.userId == _myUserId && choice.submitted,
    );
  }

  @override
  void initState() {
    super.initState();
    _selected =
        multiplayerGameForKey(widget.initialGameKey) ??
        multiplayerGameCatalog.first;
    if (widget.initialRoomCode?.trim().isNotEmpty == true) {
      _playMode = PlayMode.real;
    }
    _stakeUsd = _selected.minStake;
    _status = _initialStatus();
    _eventsSub = _session.gameEvents.listen(_handleGameEvent);
    if (!_playMode.isDemo) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
    }
  }

  @override
  void dispose() {
    _publicRefreshFallback?.cancel();
    _createRoomFallback?.cancel();
    _stakeUpdateDebounce?.cancel();
    _demoRpsShuffleTimer?.cancel();
    _availablePlayersFallback?.cancel();
    _readyUpdateFallback?.cancel();
    _roomRecoveryFallback?.cancel();
    _eventsSub?.cancel();
    _joinCodeController.dispose();
    _inviteUserController.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    await _session.ensureGameSocket();
    _refreshPublicRooms();
    final initialRoomCode = widget.initialRoomCode?.trim().toUpperCase();
    if (!_handledInitialJoin &&
        initialRoomCode != null &&
        initialRoomCode.isNotEmpty) {
      _handledInitialJoin = true;
      _joinCodeController.text = initialRoomCode;
      _requestJoinRoom(initialRoomCode, 'Opening room $initialRoomCode...');
    }
  }

  Future<void> _recoverRoomConnection(String roomCode) async {
    if (_recoveringRoomConnection) return;
    setState(() => _recoveringRoomConnection = true);
    _roomRecoveryFallback?.cancel();
    try {
      await _session.ensureGameSocket();
      if (!mounted || _room?.roomCode != roomCode) return;
      _session.gameService.joinRoom(roomCode);
      _roomRecoveryFallback = Timer(const Duration(seconds: 5), () {
        if (!mounted || _room?.roomCode != roomCode) return;
        setState(() {
          _room = null;
          _round = null;
          _lastResult = null;
          _submittedRoundId = null;
          _pendingHostReadyHandoff = false;
          _recoveringRoomConnection = false;
          _roomLobbyPanel = _RoomLobbyPanel.controls;
          _status = 'Room connection lost. Create or join again.';
        });
        _refreshPublicRooms();
      });
    } catch (_) {
      if (!mounted || _room?.roomCode != roomCode) return;
      setState(() {
        _room = null;
        _round = null;
        _lastResult = null;
        _submittedRoundId = null;
        _pendingHostReadyHandoff = false;
        _recoveringRoomConnection = false;
        _roomLobbyPanel = _RoomLobbyPanel.controls;
        _status = 'Room connection lost. Create or join again.';
      });
      _refreshPublicRooms();
    }
  }

  void _handleGameEvent(GameEvent event) {
    if (!mounted) return;

    if (event is GameErrorEvent) {
      final room = _room;
      _readyUpdateFallback?.cancel();
      setState(() {
        _pendingHostReadyHandoff = false;
        _status = room == null
            ? event.message
            : 'Room connection lost. Reconnecting...';
      });
      if (room != null && !_playMode.isDemo) {
        unawaited(_recoverRoomConnection(room.roomCode));
      }
      return;
    }

    if (event is RoomCreatedEvent) {
      _createRoomFallback?.cancel();
      _adoptRoom(event.room);
      setState(() {
        _creatingRoom = false;
        _status = 'Room ${event.room.roomCode} created.';
      });
      _refreshAvailablePlayers();
      return;
    }
    if (event is RoomStateEvent) {
      _adoptRoom(event.room);
      if (event.room.state.toUpperCase() == 'WAITING') {
        setState(() {
          _round = null;
          _submittedRoundId = null;
        });
      }
      _refreshAvailablePlayers();
      return;
    }
    if (event is RoomListEvent) {
      final filtered =
          event.rooms
              .where((room) => _sameGameKey(room.gameKey, _selected.key))
              .toList()
            ..sort((a, b) {
              final byStake = a.stakeUsd.compareTo(b.stakeUsd);
              if (byStake != 0) return byStake;
              final aTime = a.updatedAt?.millisecondsSinceEpoch ?? 0;
              final bTime = b.updatedAt?.millisecondsSinceEpoch ?? 0;
              return bTime.compareTo(aTime);
            });
      setState(() {
        _publicRooms
          ..clear()
          ..addAll(filtered);
        _loadingPublicRooms = false;
      });
      return;
    }
    if (event is RoomInviteEvent) {
      setState(() {
        _pendingInvites.removeWhere(
          (invite) =>
              invite.room.roomCode == event.room.roomCode &&
              invite.fromUserId == event.fromUserId,
        );
        _pendingInvites.insert(0, event);
      });
      showGameMessage(
        context,
        'Invite from ${event.fromUserName} to room ${event.room.roomCode}',
      );
      return;
    }
    if (event is AvailablePlayersEvent) {
      _availablePlayersFallback?.cancel();
      setState(() {
        _availablePlayers
          ..clear()
          ..addAll(event.players.where((player) => player.userId != _myUserId));
        _loadingAvailablePlayers = false;
      });
      return;
    }
    if (event is RoomRoundStartedEvent) {
      if (_room != null && _room!.roomCode != event.payload.roomCode) return;
      final myChoiceSubmitted = event.payload.choices.any(
        (choice) => choice.userId == _myUserId && choice.submitted,
      );
      final gameKey = event.payload.gameKey.trim().toUpperCase();
      final isDiceRolling =
          gameKey == 'DICE_DUEL' && event.payload.rollDeadline != null;
      final isCoinFlipping =
          gameKey == 'COIN_TOSS' && event.payload.rollDeadline != null;
      setState(() {
        _round = event.payload;
        _lastResult = null;
        _submittedRoundId = myChoiceSubmitted ? event.payload.roundId : null;
        _status = isDiceRolling
            ? 'Dice rolling.'
            : isCoinFlipping
            ? 'Coin flipping.'
            : event.payload.requiresAction
            ? (myChoiceSubmitted ? 'Move submitted.' : 'Pot locked. Submit.')
            : 'Pot locked. Resolving.';
      });
      return;
    }
    if (event is RoomRoundResultEvent) {
      if (_room != null && _room!.roomCode != event.payload.roomCode) return;
      final continues = event.payload.detail['continues'] == true;
      setState(() {
        if (!continues) {
          _round = null;
          _lastResult = event.payload;
        }
        _submittedRoundId = null;
        _status = event.payload.summary;
      });
      if (continues) {
        return;
      }
      unawaited(_session.refreshBalance());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showRoundOutcomeDialog(event.payload);
        }
      });
      return;
    }
    if (event is RoomKickedEvent) {
      _roomRecoveryFallback?.cancel();
      setState(() {
        _room = null;
        _round = null;
        _lastResult = null;
        _submittedRoundId = null;
        _recoveringRoomConnection = false;
        _status = event.message;
        _retryJoinRoomCode = null;
        _retryCreateRoomAfterLeave = false;
        _leavingCurrentRoomForRetry = false;
      });
      _refreshPublicRooms();
      showGameMessage(context, event.message);
      return;
    }
    if (event is RoomInfoEvent) {
      if (event.code == 'LEFT_ROOM') {
        _roomRecoveryFallback?.cancel();
        final retryJoinCode = _retryJoinRoomCode;
        final retryCreate = _retryCreateRoomAfterLeave;
        final shouldRetry = _leavingCurrentRoomForRetry;
        setState(() {
          _room = null;
          _round = null;
          _lastResult = null;
          _submittedRoundId = null;
          _recoveringRoomConnection = false;
          _status = shouldRetry ? 'Switching rooms...' : 'You left the room.';
        });
        if (shouldRetry && retryJoinCode != null) {
          setState(() {
            _leavingCurrentRoomForRetry = false;
            _status = 'Joining room $retryJoinCode...';
          });
          unawaited(_sendJoinRoomRequest(retryJoinCode));
          return;
        }
        if (shouldRetry && retryCreate) {
          setState(() {
            _leavingCurrentRoomForRetry = false;
            _retryCreateRoomAfterLeave = false;
            _creatingRoom = true;
            _status = 'Creating room...';
          });
          _startCreateRoomFallback();
          unawaited(_sendCreateRoomRequest());
          return;
        }
        _retryJoinRoomCode = null;
        _retryCreateRoomAfterLeave = false;
        _leavingCurrentRoomForRetry = false;
        _refreshPublicRooms();
      } else if (event.code == 'INVITE_SENT') {
        showGameMessage(context, 'Invite sent.');
      } else if (event.code == 'PLAYER_KICKED') {
        showGameMessage(context, 'Player removed from room.');
      }
      return;
    }
    if (event is RoomErrorEvent) {
      final lowerMessage = event.message.trim().toLowerCase();
      final lostRoom =
          lowerMessage.contains('not in this room') ||
          lowerMessage.contains('room not found');
      if (lostRoom) {
        _readyUpdateFallback?.cancel();
        _roomRecoveryFallback?.cancel();
        setState(() {
          _room = null;
          _round = null;
          _lastResult = null;
          _submittedRoundId = null;
          _pendingHostReadyHandoff = false;
          _recoveringRoomConnection = false;
          _roomLobbyPanel = _RoomLobbyPanel.controls;
          _status = 'Room connection lost. Create or join again.';
        });
        _refreshPublicRooms();
        showGameMessage(context, 'Room connection lost. Create or join again.');
        return;
      }
      if (_shouldLeaveAndRetry(event.message)) {
        _createRoomFallback?.cancel();
        final retryingCreate = _creatingRoom;
        setState(() {
          _creatingRoom = false;
          _loadingPublicRooms = false;
          _leavingCurrentRoomForRetry = true;
          _retryCreateRoomAfterLeave = retryingCreate;
          if (retryingCreate) {
            _retryJoinRoomCode = null;
          }
          _status = retryingCreate
              ? 'Preparing new room...'
              : 'Switching rooms...';
        });
        _session.gameService.leaveRoom();
        return;
      }
      _createRoomFallback?.cancel();
      setState(() {
        _creatingRoom = false;
        _loadingPublicRooms = false;
        _status = event.message;
        _retryJoinRoomCode = null;
        _retryCreateRoomAfterLeave = false;
        _leavingCurrentRoomForRetry = false;
      });
      showGameMessage(context, event.message);
    }
  }

  void _adoptRoom(RoomStateSnapshot room) {
    final selectedDef = multiplayerGameForKey(room.gameKey) ?? _selected;
    final changedRooms = _room != null && _room!.roomCode != room.roomCode;
    final currentStatus = _status.trim();
    final isHostInRoom = room.hostUserId == _myUserId;
    final myReady = room.players.any(
      (player) => player.userId == _myUserId && player.ready,
    );
    final shouldOpenInviteAfterReady =
        _pendingHostReadyHandoff &&
        isHostInRoom &&
        myReady &&
        !room.inRound &&
        _round == null;
    final shouldResetStatus =
        currentStatus.startsWith('Join or create ') ||
        currentStatus.startsWith('Opening room ') ||
        currentStatus.startsWith('Room connection lost.');
    setState(() {
      _room = room;
      _selected = selectedDef;
      _stakeUsd = room.stakeUsd < _selected.minStake
          ? _selected.minStake
          : room.stakeUsd;
      _roomRecoveryFallback?.cancel();
      _recoveringRoomConnection = false;
      if (changedRooms) {
        _round = null;
        _lastResult = null;
        _submittedRoundId = null;
        _roomLobbyPanel = _RoomLobbyPanel.controls;
        _pendingHostReadyHandoff = false;
      }
      _retryJoinRoomCode = null;
      _retryCreateRoomAfterLeave = false;
      _leavingCurrentRoomForRetry = false;
      if (shouldOpenInviteAfterReady) {
        _readyUpdateFallback?.cancel();
        _pendingHostReadyHandoff = false;
        _roomLobbyPanel = _RoomLobbyPanel.invite;
        _status = 'Ready on. Waiting for host start.';
      }
      if (shouldResetStatus) {
        _status = '${_readyCount(room)}/${room.players.length} ready.';
      }
    });
  }

  String _initialStatus() {
    return 'Join or create ${_selected.title}.';
  }

  bool _sameGameKey(String left, String right) {
    return left.trim().toUpperCase() == right.trim().toUpperCase();
  }

  bool _shouldLeaveAndRetry(String message) {
    final alreadyInRoom =
        message.trim().toLowerCase() == 'user already in a room';
    if (!alreadyInRoom || _round != null) return false;
    if (_leavingCurrentRoomForRetry) return false;
    return _retryJoinRoomCode != null || _creatingRoom;
  }

  void _setPlayMode(PlayMode mode) {
    if (_playMode == mode || _room != null) return;
    setState(() {
      _playMode = mode;
      _demoResolving = false;
      _demoRollDeadline = null;
      _demoRpsShuffleTimer?.cancel();
      _demoRpsComputerPick = null;
      _demoResult = null;
      _demoStatus = 'Demo room ready.';
      _status = mode.isDemo ? _demoStatus : _initialStatus();
    });
    if (!mode.isDemo) {
      _boot();
    }
  }

  Future<void> _runDemoRoomRound() async {
    if (_demoResolving) return;
    final rng = math.Random();
    final isRpsDemo = _selected.key == 'RPS_CLASH';
    final isDiceDemo = _selected.key == 'DICE_DUEL';
    final isCoinDemo = _selected.key == 'COIN_TOSS';
    final hasRollingArtifact = isDiceDemo || isCoinDemo;
    final rpsComputerPick = isRpsDemo ? _randomRpsMove(rng) : null;
    final demoRollDeadline = hasRollingArtifact
        ? DateTime.now().add(const Duration(seconds: 10))
        : null;
    final resolveDuration = hasRollingArtifact
        ? const Duration(seconds: 10)
        : isRpsDemo
        ? const Duration(milliseconds: 1800)
        : const Duration(milliseconds: 950);
    final stake = _stakeUsd < _selected.minStake
        ? _selected.minStake
        : _stakeUsd;
    final session = context.read<SessionManager>();
    if (!session.deductDemoBalance(stake)) {
      showGameMessage(context, 'Insufficient demo balance.');
      return;
    }

    setState(() {
      _stakeUsd = stake;
      _demoResolving = true;
      _demoRollDeadline = demoRollDeadline;
      _demoRpsComputerPick = isRpsDemo ? _randomRpsMove(rng) : null;
      _demoResult = null;
      _demoStatus = isRpsDemo
          ? 'Computer choosing.'
          : isDiceDemo
          ? 'Dice rolling.'
          : isCoinDemo
          ? 'Coin flipping.'
          : 'Demo pot locked.';
    });
    if (isRpsDemo) {
      _startDemoRpsShuffle();
    }

    await Future<void>.delayed(resolveDuration);
    if (!mounted || !_demoResolving) return;
    _demoRpsShuffleTimer?.cancel();
    _demoRpsShuffleTimer = null;

    final diceRoll = isDiceDemo ? rng.nextInt(6) + 1 : null;
    final coinFace = isCoinDemo
        ? (rng.nextInt(2) == 0 ? 'HEADS' : 'TAILS')
        : null;
    final playerCount = isRpsDemo
        ? 2
        : _minPlayers + rng.nextInt(_maxPlayers - _minPlayers + 1);
    final pot = _roundMoney(stake * playerCount);
    final commission = _roundMoney(pot * 0.15);
    final distributable = _roundMoney(pot - commission);
    final secretBidOutcome = _selected.key == 'SECRET_BID'
        ? _buildDemoSecretBidOutcome(rng, playerCount)
        : null;
    final rpsOutcome = rpsComputerPick == null
        ? null
        : _rpsDemoOutcome(_rpsPick, rpsComputerPick);
    final tied = rpsOutcome == 0;
    final won =
        (rpsOutcome != null ? rpsOutcome > 0 : null) ??
        (diceRoll != null ? _dicePick == diceRoll : null) ??
        (coinFace != null ? _coinSide == coinFace : null) ??
        secretBidOutcome?.userWon ??
        _demoWinForGame(rng);
    final winnerCount = tied
        ? 2
        : secretBidOutcome?.winnerCount ??
              (won ? 1 : 1 + rng.nextInt(math.max(1, playerCount - 1)));
    final payout = won && !tied
        ? _roundMoney(distributable / winnerCount)
        : 0.0;
    final net = _roundMoney(payout - stake);
    final result = _DemoRoomResult(
      won: won,
      tied: tied,
      playerCount: playerCount,
      winnerCount: winnerCount,
      stakeUsd: stake,
      potUsd: pot,
      commissionUsd: commission,
      payoutUsd: payout,
      netUsd: net,
      action: _demoActionLabel(),
      rpsComputerPick: rpsComputerPick,
      diceRoll: diceRoll,
      coinFace: coinFace,
      secretBidWinningBid: secretBidOutcome?.winningBid,
      secretBidOpponentRows: secretBidOutcome?.opponentRows ?? const [],
    );

    setState(() {
      _demoResolving = false;
      _demoRollDeadline = null;
      _demoRpsComputerPick = rpsComputerPick;
      _demoResult = result;
      _demoStatus = tied
          ? 'Demo tie. Stake returned.'
          : won
          ? 'Demo win ${formatCurrency(net)}.'
          : 'Demo loss.';
    });
    
    if (tied) {
      context.read<SessionManager>().addDemoWinnings(stake);
    } else if (won && payout > 0) {
      context.read<SessionManager>().addDemoWinnings(payout);
    }

    final settledMessage = isRpsDemo && rpsComputerPick != null
        ? 'Demo round settled. Computer picked $rpsComputerPick.'
        : 'Demo round settled.';
    showGameMessage(
      context,
      tied
          ? 'Demo tie. Computer picked $rpsComputerPick. Stake returned.'
          : won
          ? 'Demo win: ${formatCurrency(payout)} payout.'
          : settledMessage,
    );
  }

  void _startDemoRpsShuffle() {
    _demoRpsShuffleTimer?.cancel();
    final rng = math.Random();
    _demoRpsShuffleTimer = Timer.periodic(const Duration(milliseconds: 150), (
      _,
    ) {
      if (!mounted) return;
      final next = _randomRpsMove(rng);
      setState(() {
        _demoRpsComputerPick = next == _demoRpsComputerPick
            ? _rpsBeats(next)
            : next;
      });
    });
  }

  String _randomRpsMove(math.Random rng) {
    const moves = ['ROCK', 'PAPER', 'SCISSORS'];
    return moves[rng.nextInt(moves.length)];
  }

  int _rpsDemoOutcome(String playerPick, String computerPick) {
    final player = playerPick.trim().toUpperCase();
    final computer = computerPick.trim().toUpperCase();
    if (player == computer) return 0;
    return _rpsBeats(player) == computer ? 1 : -1;
  }

  bool _demoWinForGame(math.Random rng) {
    switch (_selected.key) {
      case 'DICE_DUEL':
      case 'HIGH_CARD':
        return rng.nextDouble() < 0.34;
      case 'TARGET_STRIKE':
      case 'SECRET_BID':
        return rng.nextDouble() < 0.38;
      case 'LOOT_BOX_POOL':
        return rng.nextDouble() < 0.28;
      default:
        return rng.nextDouble() < 0.46;
    }
  }

  _DemoSecretBidOutcome _buildDemoSecretBidOutcome(
    math.Random rng,
    int playerCount,
  ) {
    final usedBids = <int>{_secretBid};
    final opponentNames = ['Nova', 'Ace', 'Blaze', 'Mika'];
    final rows = <_SecretBidRow>[];
    var winningBid = _secretBid;
    var userWon = true;

    for (var i = 0; i < playerCount - 1; i++) {
      var bid = rng.nextInt(100) + 1;
      while (usedBids.contains(bid)) {
        bid = rng.nextInt(100) + 1;
      }
      usedBids.add(bid);
      if (bid > winningBid) {
        winningBid = bid;
        userWon = false;
      }
      rows.add(
        _SecretBidRow(
          displayName: opponentNames[i % opponentNames.length],
          bid: bid,
          distance: 0,
          isWinner: false,
        ),
      );
    }

    final sortedRows =
        rows
            .map(
              (row) => _SecretBidRow(
                displayName: row.displayName,
                bid: row.bid,
                distance: (row.bid - winningBid).abs(),
                isWinner: row.bid == winningBid,
              ),
            )
            .toList()
          ..sort(_compareSecretBidRows);

    return _DemoSecretBidOutcome(
      winningBid: winningBid,
      userWon: userWon,
      winnerCount: 1,
      opponentRows: sortedRows,
    );
  }

  String _demoActionLabel() {
    switch (_selected.key) {
      case 'RPS_CLASH':
        return _rpsPick;
      case 'DICE_DUEL':
        return 'Pick $_dicePick';
      case 'TARGET_STRIKE':
        return '$_targetPick';
      case 'PARITY_CLASH':
        return '$_parityDigit';
      case 'COIN_TOSS':
        return _coinSide;
      case 'TREASURE_BOX':
        return 'Box $_treasureBoxPick';
      case 'SECRET_BID':
        return 'Bid $_secretBid';
      case 'SPIN_BOTTLE':
        return _spinBottleSide;
      case 'LOOT_BOX_POOL':
        return 'Box $_lootBoxPick';
      default:
        return 'Auto';
    }
  }

  void _refreshPublicRooms() {
    if (_playMode.isDemo) return;
    setState(() {
      _loadingPublicRooms = true;
      _publicRooms.clear();
    });
    _session.gameService.listPublicRooms(gameKey: _selected.key);
    _publicRefreshFallback?.cancel();
    _publicRefreshFallback = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _loadingPublicRooms = false);
    });
  }

  void _refreshAvailablePlayers() {
    final room = _room;
    if (!mounted) return;
    if (_playMode.isDemo ||
        room == null ||
        !_isHost ||
        room.inRound ||
        room.players.length >= room.maxPlayers) {
      if (_availablePlayers.isNotEmpty || _loadingAvailablePlayers) {
        _availablePlayersFallback?.cancel();
        setState(() {
          _availablePlayers.clear();
          _loadingAvailablePlayers = false;
        });
      }
      return;
    }
    setState(() => _loadingAvailablePlayers = true);
    _session.gameService.listAvailablePlayers();
    _availablePlayersFallback?.cancel();
    _availablePlayersFallback = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _loadingAvailablePlayers = false);
    });
  }

  void _createRoom() {
    if (_creatingRoom || _round != null) return;
    final replacingRoom = _room != null;
    setState(() {
      _creatingRoom = true;
      _status = replacingRoom ? 'Creating new room...' : 'Creating room...';
      _retryCreateRoomAfterLeave = replacingRoom;
      _retryJoinRoomCode = null;
    });
    _startCreateRoomFallback();
    unawaited(_sendCreateRoomRequest());
  }

  void _startCreateRoomFallback() {
    _createRoomFallback?.cancel();
    _createRoomFallback = Timer(const Duration(seconds: 8), () {
      if (!mounted || !_creatingRoom) return;
      setState(() {
        _creatingRoom = false;
        _status = 'Room was not created. Try again.';
        _retryCreateRoomAfterLeave = false;
        _leavingCurrentRoomForRetry = false;
      });
    });
  }

  Future<void> _sendCreateRoomRequest() async {
    try {
      await _session.ensureGameSocket();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _creatingRoom = false;
        _status = 'Could not connect. Try again.';
      });
      return;
    }
    if (!mounted) return;
    _session.gameService.createRoom(
      gameKey: _selected.key,
      isPublic: _isRoomPublic,
      minPlayers: _minPlayers,
      maxPlayers: _maxPlayers,
      stakeUsd: _stakeUsd < _selected.minStake ? _selected.minStake : _stakeUsd,
    );
  }

  void _joinRoomByCode() {
    final code = _joinCodeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      showGameMessage(context, 'Enter a room code.');
      return;
    }
    _requestJoinRoom(code, 'Joining room $code...');
  }

  void _joinPublicRoom(String code) {
    _requestJoinRoom(code, 'Joining room $code...');
  }

  void _requestJoinRoom(String code, String status) {
    final roomCode = code.trim().toUpperCase();
    if (roomCode.isEmpty) return;
    _retryJoinRoomCode = roomCode;
    _retryCreateRoomAfterLeave = false;
    if (mounted) {
      setState(() => _status = status);
    }
    unawaited(_sendJoinRoomRequest(roomCode));
  }

  Future<void> _sendJoinRoomRequest(String roomCode) async {
    try {
      await _session.ensureGameSocket();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _retryJoinRoomCode = null;
        _status = 'Could not connect. Try again.';
      });
      return;
    }
    if (!mounted) return;
    _session.gameService.joinRoom(roomCode);
  }

  void _leaveRoom() {
    _retryJoinRoomCode = null;
    _retryCreateRoomAfterLeave = false;
    _leavingCurrentRoomForRetry = false;
    _recoveringRoomConnection = false;
    _roomRecoveryFallback?.cancel();
    _session.gameService.leaveRoom();
    setState(() => _status = 'Leaving room...');
  }

  Future<void> _setReady(bool ready) async {
    final shouldHandoff = ready && _isHost && _round == null;
    setState(() {
      _pendingHostReadyHandoff = shouldHandoff;
      _status = ready ? 'Marking ready...' : 'Removing ready...';
    });
    _readyUpdateFallback?.cancel();
    if (shouldHandoff) {
      _readyUpdateFallback = Timer(const Duration(seconds: 4), () {
        if (!mounted || !_pendingHostReadyHandoff) return;
        setState(() {
          _pendingHostReadyHandoff = false;
          _status = 'Ready did not update. Try again.';
        });
      });
    }

    try {
      await _session.ensureGameSocket();
      if (!mounted) return;
      _session.gameService.setRoomReady(ready);
      if (!ready) {
        _readyUpdateFallback?.cancel();
        setState(() {
          _pendingHostReadyHandoff = false;
          _status = 'Ready removed.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      _readyUpdateFallback?.cancel();
      setState(() {
        _pendingHostReadyHandoff = false;
        _status = 'Connection lost. Try again.';
      });
    }
  }

  void _setNextRoomStake(double next) {
    final stake = next < _selected.minStake ? _selected.minStake : next;
    final room = _room;
    final shouldUpdateRoom = _isHost && room != null && _round == null;
    setState(() {
      _stakeUsd = stake;
      if (shouldUpdateRoom) {
        _room = _roomWithStake(room, stake);
        _status = '0/${room.players.length} ready.';
      }
    });
    if (!shouldUpdateRoom) {
      return;
    }
    _stakeUpdateDebounce?.cancel();
    _stakeUpdateDebounce = Timer(const Duration(milliseconds: 450), () {
      _session.gameService.updateRoomStake(stake);
    });
  }

  RoomStateSnapshot _roomWithStake(RoomStateSnapshot room, double stake) {
    return RoomStateSnapshot(
      roomCode: room.roomCode,
      gameKey: room.gameKey,
      visibility: room.visibility,
      hostUserId: room.hostUserId,
      minPlayers: room.minPlayers,
      maxPlayers: room.maxPlayers,
      stakeUsd: stake,
      state: room.state,
      players: [
        for (final player in room.players)
          RoomPlayerSnapshot(
            userId: player.userId,
            displayName: player.displayName,
            ready: false,
            joinedAt: player.joinedAt,
          ),
      ],
      createdAt: room.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  void _startRound() {
    final stake = _stakeUsd < _selected.minStake
        ? _selected.minStake
        : _stakeUsd;
    _session.gameService.startRoomRound(stakeUsd: stake);
    setState(() => _status = 'Round started.');
  }

  void _submitAction() {
    final round = _round;
    if (round == null || !round.requiresAction || _hasSubmittedAction) return;

    Map<String, dynamic> action;
    switch (_selected.key) {
      case 'RPS_CLASH':
        action = {'pick': _rpsPick};
        break;
      case 'DICE_DUEL':
        action = {'number': _dicePick};
        break;
      case 'TARGET_STRIKE':
        action = {'number': _targetPick};
        break;
      case 'PARITY_CLASH':
        action = {'digit': _parityDigit};
        break;
      case 'COIN_TOSS':
        action = {'side': _coinSide};
        break;
      case 'TREASURE_BOX':
        action = {'box': _treasureBoxPick};
        break;
      case 'SECRET_BID':
        action = {'bid': _secretBid};
        break;
      case 'SPIN_BOTTLE':
        action = {'side': _spinBottleSide};
        break;
      case 'LOOT_BOX_POOL':
        action = {'box': _lootBoxPick};
        break;
      default:
        action = const {};
    }

    _session.gameService.submitRoomAction(action);
    setState(() {
      _submittedRoundId = round.roundId;
      _status = 'Move submitted.';
    });
  }

  void _sendInvite() {
    _sendDirectInvite(_inviteUserController.text);
  }

  void _sendDirectInvite(String targetUserId) {
    final userId = targetUserId.trim();
    if (userId.isEmpty) {
      showGameMessage(context, 'Enter a user ID to invite.');
      return;
    }
    _inviteUserController.text = userId;
    _session.gameService.inviteToRoom(userId);
  }

  void _acceptInvite(RoomInviteEvent invite) {
    _requestJoinRoom(
      invite.room.roomCode,
      'Joining ${invite.room.roomCode}...',
    );
    setState(() {
      _pendingInvites.remove(invite);
      _selected = multiplayerGameForKey(invite.room.gameKey) ?? _selected;
    });
  }

  void _dismissInvite(RoomInviteEvent invite) {
    setState(() => _pendingInvites.remove(invite));
  }

  Future<void> _copyRoomCode() async {
    final room = _room;
    if (room == null) return;
    final copied = await copyTextToClipboard(room.roomCode);
    if (!mounted) return;
    showGameMessage(
      context,
      copied ? 'Room code copied.' : 'Copy failed. Use the code on screen.',
    );
  }

  Future<void> _copyRoomLink() async {
    final room = _room;
    if (room == null) return;
    final value = _buildJoinLink(room);
    final copied = await copyTextToClipboard(value);
    if (!mounted) return;
    showGameMessage(
      context,
      copied
          ? (kIsWeb ? 'Join link copied.' : 'Invite copied.')
          : 'Copy failed.',
    );
  }

  String _buildJoinLink(RoomStateSnapshot room) {
    if (!kIsWeb) {
      return 'Glory Grid room ${room.roomCode} • ${_selected.title} • Entry ${formatCurrency(room.stakeUsd)}';
    }
    final query = Map<String, String>.from(Uri.base.queryParameters)
      ..['arena'] = '1'
      ..['game'] = room.gameKey
      ..['room'] = room.roomCode;
    return Uri.base.replace(queryParameters: query).toString();
  }

  Future<void> _kickPlayer(RoomPlayerSnapshot player) async {
    final shouldKick = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.gameSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppTheme.gameBorder),
          ),
          title: const Text(
            'Remove Player',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Remove ${player.displayName}?',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (shouldKick != true) return;
    _session.gameService.kickRoomPlayer(player.userId);
    setState(() => _status = 'Removing player...');
  }

  Future<void> _showRoundOutcomeDialog(RoomRoundResultPayload result) async {
    if (_resultDialogOpen) return;
    _resultDialogOpen = true;
    final won = result.winnerUserIds.contains(_myUserId);
    RoomWinnerPayout? myWinnerRow;
    for (final winner in result.winners) {
      if (winner.userId == _myUserId) {
        myWinnerRow = winner;
        break;
      }
    }
    final payout = myWinnerRow?.payoutUsd ?? 0;
    final net = payout - result.stakeUsd;
    final isSecretBid = _isSecretBidResult(result);
    final noWinnerResult = _isNoWinnerResult(result);
    final tieResult = _isTieResult(result);
    final title = noWinnerResult
        ? 'No Winner'
        : tieResult
        ? 'Round Tied'
        : won
        ? 'Round Won'
        : 'Round Lost';
    final titleColor = noWinnerResult
        ? AppTheme.textPrimary
        : tieResult
        ? AppTheme.goldButtonBottom
        : won
        ? AppTheme.success
        : AppTheme.textPrimary;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.gameSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: won && !tieResult
                  ? AppTheme.success
                  : tieResult
                  ? AppTheme.goldButtonBottom.withValues(alpha: 0.55)
                  : AppTheme.gameBorder,
            ),
          ),
          title: Text(
            title,
            style: TextStyle(
              color: titleColor,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.summary,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                if (isSecretBid) ...[
                  const SizedBox(height: 10),
                  _buildSecretBidResultReveal(result),
                ],
                if (_isSpinBottleResult(result)) ...[
                  const SizedBox(height: 10),
                  _buildSpinBottleOutcome(result, compact: true),
                ],
                if (_isTargetStrikeResult(result)) ...[
                  const SizedBox(height: 10),
                  _buildTargetStrikeResultReveal(result, compact: true),
                ],
                const SizedBox(height: 10),
                _buildRoundTransparencyPanel(result, compact: true),
                const SizedBox(height: 10),
                _moneyLine('Entry moved from wallet', result.stakeUsd),
                _moneyLine('Total room pot', result.potUsd),
                _moneyLine('Platform commission', result.commissionUsd),
                _moneyLine('Winner pool', result.distributableUsd),
                _moneyLine(
                  won ? 'Returned to your wallet' : 'Returned to your wallet',
                  payout,
                ),
                _moneyLine('Net result', net),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
    _resultDialogOpen = false;
  }

  Widget _moneyLine(String label, double value) {
    final positive = value > 0;
    final zero = value == 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            '${positive
                ? '+'
                : zero
                ? ''
                : ''}${formatCurrency(value)}',
            style: TextStyle(
              color: positive
                  ? AppTheme.success
                  : zero
                  ? AppTheme.textPrimary
                  : AppTheme.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  bool _canStartRound() {
    final room = _room;
    if (room == null || room.inRound || !_isHost) return false;
    final readyCount = _readyCount(room);
    return readyCount >= room.minPlayers && readyCount >= 2;
  }

  int _readyCount(RoomStateSnapshot room) =>
      room.players.where((player) => player.ready).length;

  int _potParticipantCount(RoomStateSnapshot room) {
    final round = _round;
    if (round != null) return math.max(1, round.playerCount);
    return math.max(room.minPlayers, room.players.length);
  }

  double _roundMoney(double value) => (value * 100).roundToDouble() / 100;

  List<RoomSummary> get _visiblePublicRooms => _publicRooms
      .where((room) => _sameGameKey(room.gameKey, _selected.key))
      .where(_matchesStakeFilter)
      .toList(growable: false);

  bool _matchesStakeFilter(RoomSummary room) {
    switch (_roomStakeFilter) {
      case _RoomStakeFilter.any:
        return true;
      case _RoomStakeFilter.entry1to5:
        return room.stakeUsd <= 5;
      case _RoomStakeFilter.entry6to20:
        return room.stakeUsd >= 6 && room.stakeUsd <= 20;
      case _RoomStakeFilter.entry21Plus:
        return room.stakeUsd >= 21;
    }
  }

  bool get _showStatusNotice {
    final message = _status.trim();
    if (message.isEmpty) return false;
    if (_room == null) {
      return _loadingPublicRooms ||
          _creatingRoom ||
          message != _initialStatus();
    }
    if (_round == null &&
        _lastResult == null &&
        (RegExp(r'^\d+/\d+ ready\.$').hasMatch(message) ||
            RegExp(r'^Room [A-Z0-9]+ created\.$').hasMatch(message))) {
      return false;
    }
    return true;
  }

  String get _roomStageTitle {
    if (_round != null) return 'Round Live';
    if (_lastResult != null) return 'Round Result';
    return 'Waiting Room';
  }

  String get _roomStageSummary {
    final room = _room;
    if (room == null) return _initialStatus();
    if (_round != null) {
      return _round!.requiresAction
          ? 'Players are locking moves.'
          : 'Resolving from the pot.';
    }
    if (_lastResult != null) {
      final result = _lastResult!;
      if (_isSpinBottleResult(result)) {
        return _spinBottleRoundSummary(result);
      }
      return 'Round settled.';
    }
    final readyCount = _readyCount(room);
    return '$readyCount/${room.players.length} ready.';
  }

  Future<void> _openCreateRoomSheet() async {
    var localStake = _stakeUsd < _selected.minStake
        ? _selected.minStake
        : _stakeUsd;
    var localMinPlayers = _minPlayers;
    var localMaxPlayers = _maxPlayers;
    var localIsPublic = _isRoomPublic;

    final shouldCreate = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return _buildSheetFrame(
              context: context,
              title: 'Create ${_selected.title} Room',
              subtitle: 'Set entry and seats.',
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildSmallSelect(
                          label: 'Min Players',
                          value: localMinPlayers.toString(),
                          onTap: () {
                            setSheetState(() {
                              localMinPlayers = localMinPlayers == 4
                                  ? 2
                                  : localMinPlayers + 1;
                              if (localMaxPlayers < localMinPlayers) {
                                localMaxPlayers = localMinPlayers;
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSmallSelect(
                          label: 'Max Players',
                          value: localMaxPlayers.toString(),
                          onTap: () {
                            setSheetState(() {
                              localMaxPlayers = localMaxPlayers == 4
                                  ? localMinPlayers
                                  : localMaxPlayers + 1;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSmallSelect(
                          label: 'Visibility',
                          value: localIsPublic ? 'PUBLIC' : 'PRIVATE',
                          onTap: () => setSheetState(
                            () => localIsPublic = !localIsPublic,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  StakeAdjuster(
                    label: 'ENTRY AMOUNT',
                    value: localStake,
                    onChanged: (next) => setSheetState(
                      () => localStake = next < _selected.minStake
                          ? _selected.minStake
                          : next,
                    ),
                    min: _selected.minStake,
                    max: 1000,
                    step: 1,
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: PrimaryButton(
                          expanded: true,
                          label: 'CANCEL',
                          onPressed: () => Navigator.of(context).pop(false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PrimaryButton(
                          expanded: true,
                          label: 'CREATE ROOM',
                          onPressed: () => Navigator.of(context).pop(true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (shouldCreate != true || !mounted) return;
    setState(() {
      _stakeUsd = localStake;
      _minPlayers = localMinPlayers;
      _maxPlayers = localMaxPlayers;
      _isRoomPublic = localIsPublic;
    });
    _createRoom();
  }

  Future<void> _openJoinRoomSheet() async {
    final controller = TextEditingController(text: _joinCodeController.text);
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _buildSheetFrame(
          context: context,
          title: 'Join ${_selected.title} Room',
          subtitle: 'Paste a code.',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                decoration: _sheetInputDecoration(
                  'Enter room code (e.g. AB12CD)',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: PrimaryButton(
                      expanded: true,
                      label: 'CANCEL',
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryButton(
                      expanded: true,
                      label: 'JOIN ROOM',
                      onPressed: () {
                        final value = controller.text.trim().toUpperCase();
                        if (value.isEmpty) {
                          showGameMessage(this.context, 'Enter a room code.');
                          return;
                        }
                        Navigator.of(context).pop(value);
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (code == null || code.isEmpty || !mounted) return;
    _joinCodeController.text = code;
    _joinRoomByCode();
  }

  Future<void> _openInviteSheet() async {
    final room = _room;
    if (room == null) return;
    final controller = TextEditingController(text: _inviteUserController.text);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _buildSheetFrame(
          context: context,
          title: 'Invite To ${room.roomCode}',
          subtitle: 'Send a direct invite.',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: _sheetInputDecoration('Invite by user ID'),
              ),
              const SizedBox(height: 12),
              PrimaryButton(
                expanded: true,
                label: 'SEND INVITE',
                onPressed: () {
                  final userId = controller.text.trim();
                  if (userId.isEmpty) {
                    showGameMessage(this.context, 'Enter a user ID to invite.');
                    return;
                  }
                  _inviteUserController.text = userId;
                  Navigator.of(context).pop();
                  _sendInvite();
                },
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
  }

  Widget _buildSheetFrame({
    required BuildContext context,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
      child: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.gameSurface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppTheme.gameBorder),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _sheetInputDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      fillColor: AppTheme.gameBackground,
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.gameBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.gameBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppTheme.goldButtonBottom),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GameScaffold(
      backgroundColor: AppTheme.gameBackground,
      appBar: GameActivityAppBar(title: _selected.title),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: _playMode.isDemo
              ? _buildDemoArenaView()
              : _room == null
              ? _buildRoomBrowserView()
              : _buildRoomLobbyView(),
        ),
      ),
    );
  }

  Widget _buildRoomBrowserView() {
    return ListView(
      key: ValueKey('browser-${_selected.key}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      children: [
        _buildGameSwitcherRow(),
        const SizedBox(height: 12),
        _buildInviteCodeBar(),
        const SizedBox(height: 12),
        _buildSelectedGameCard(),
        if (_showStatusNotice) ...[
          const SizedBox(height: 12),
          _buildStatusNotice(),
        ],
        if (_pendingInvites.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildInvitesCard(),
        ],
        const SizedBox(height: 12),
        _buildPublicRoomsCard(),
      ],
    );
  }

  Widget _buildDemoArenaView() {
    return ListView(
      key: ValueKey('demo-${_selected.key}-${_demoResult?.summary ?? ''}'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      children: [
        _buildGameSwitcherRow(),
        const SizedBox(height: 12),
        _buildDemoRoomCard(),
      ],
    );
  }

  Widget _buildBottomPlayModeBar() {
    return PlayModeBottomBar(
      value: _playMode,
      enabled: !_creatingRoom && !_demoResolving,
      onChanged: _setPlayMode,
    );
  }

  Widget _buildInviteCodeBar() {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _joinCodeController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Enter invite code',
                prefixIcon: Icon(
                  Icons.key_rounded,
                  color: AppTheme.textSecondary.withValues(alpha: 0.8),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 38,
                  minHeight: 38,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 88,
            height: 44,
            child: OutlinedButton(
              onPressed: _joinRoomByCode,
              style: OutlinedButton.styleFrom(
                backgroundColor: AppTheme.gameBackground,
                foregroundColor: AppTheme.textPrimary,
                side: const BorderSide(color: AppTheme.gameBorder),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: const Text('Verify', overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoRoomCard() {
    final result = _demoResult;
    final stake = _stakeUsd < _selected.minStake
        ? _selected.minStake
        : _stakeUsd;
    final playerCount = result?.playerCount ?? _minPlayers;
    final pot = result?.potUsd ?? _roundMoney(stake * playerCount);
    final winnerPool = result == null
        ? _roundMoney(pot * 0.85)
        : _roundMoney(result.potUsd - result.commissionUsd);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaPill(label: 'Players', value: '$playerCount'),
              _MetaPill(label: 'Pot', value: formatCurrency(pot)),
              _MetaPill(
                label: 'Winner Pool',
                value: formatCurrency(winnerPool),
              ),
              const _MetaPill(label: 'Wallet', value: 'No Change'),
            ],
          ),
          if (_selected.key == 'DICE_DUEL') ...[
            const SizedBox(height: 12),
            _buildActionInputForGame(),
          ] else if (_selected.requiresAction) ...[
            const SizedBox(height: 12),
            _buildActionInputForGame(),
          ],
          const SizedBox(height: 12),
          StakeAdjuster(
            label: 'ENTRY',
            value: stake,
            enabled: !_demoResolving,
            min: _selected.minStake,
            onChanged: (next) => setState(
              () => _stakeUsd = next < _selected.minStake
                  ? _selected.minStake
                  : next,
            ),
          ),
          const SizedBox(height: 12),
          PrimaryButton(
            expanded: true,
            label: _demoResolving
                ? (_selected.key == 'DICE_DUEL'
                      ? 'Rolling...'
                      : _selected.key == 'COIN_TOSS'
                      ? 'Flipping...'
                      : 'Resolving...')
                : _selected.key == 'SPIN_BOTTLE'
                ? 'SPIN BOTTLE'
                : 'Play Demo',
            icon: _selected.key == 'SPIN_BOTTLE'
                ? Icons.casino
                : Icons.play_arrow_rounded,
            onPressed: _demoResolving ? null : _runDemoRoomRound,
          ),
          const SizedBox(height: 10),
          _buildDemoStatus(result),
        ],
      ),
    );
  }

  Widget _buildDemoStatus(_DemoRoomResult? result) {
    final resultColor = result == null
        ? AppTheme.textSecondary
        : result.tied
        ? AppTheme.textSecondary
        : result.won
        ? AppTheme.success
        : AppTheme.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result?.summary ?? _demoStatus,
            style: TextStyle(
              color: resultColor,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 6),
            Text(
              result.rpsComputerPick != null
                  ? 'You ${result.action} • Computer ${result.rpsComputerPick}${result.tied ? ' • Tie' : ''} • Payout ${formatCurrency(result.payoutUsd)}'
                  : result.diceRoll == null
                  ? result.coinFace == null
                        ? 'Move ${result.action} • Payout ${formatCurrency(result.payoutUsd)}'
                        : 'Coin ${result.coinFace} • ${result.action} • Payout ${formatCurrency(result.payoutUsd)}'
                  : 'Roll ${result.diceRoll} • ${result.action} • Payout ${formatCurrency(result.payoutUsd)}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            if (result.secretBidOpponentRows.isNotEmpty) ...[
              const SizedBox(height: 10),
              _buildSecretBidOpponentList(
                rows: result.secretBidOpponentRows,
                targetBid: result.secretBidWinningBid,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildRoomLobbyView() {
    final room = _room!;
    final activePanel = _normalizedRoomLobbyPanel(room);
    final isWaiting = _round == null;
    final isSubpage = isWaiting && activePanel != _RoomLobbyPanel.controls;
    return ListView(
      key: ValueKey(
        'room-${room.roomCode}-${activePanel.name}-${_round?.roundId ?? _lastResult?.roundId ?? 'waiting'}',
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      children: [
        if (isSubpage)
          _buildRoomSubpageHeader(activePanel)
        else if (_lastResult != null || _round != null)
          _buildRoomStageCard()
        else
          _buildRoomCompactHeader(room),
        if (isWaiting) ...[
          const SizedBox(height: 12),
          _buildRoomPanelContent(activePanel),
          if (!isSubpage && !_isHost) ...[
            const SizedBox(height: 12),
            _buildRoomQuickActions(room),
          ],
        ],
        if (_showStatusNotice) ...[
          const SizedBox(height: 12),
          _buildStatusNotice(),
        ],
        if (_round != null) ...[
          const SizedBox(height: 12),
          _buildRoomEconomyCard(),
          const SizedBox(height: 12),
          _buildPlayersCard(),
          const SizedBox(height: 12),
          _buildRoundCard(),
        ],
        if (_lastResult != null) ...[
          const SizedBox(height: 12),
          _buildResultCard(),
        ],
      ],
    );
  }

  _RoomLobbyPanel _normalizedRoomLobbyPanel(RoomStateSnapshot room) {
    final inviteAvailable = _isHost && !room.inRound;
    if (_roomLobbyPanel == _RoomLobbyPanel.invite && !inviteAvailable) {
      return _RoomLobbyPanel.controls;
    }
    return _roomLobbyPanel;
  }

  Widget _buildRoomPanelContent(_RoomLobbyPanel activePanel) {
    switch (activePanel) {
      case _RoomLobbyPanel.controls:
        return _buildLobbyFooterCard();
      case _RoomLobbyPanel.invite:
        return _buildRoomInviteCard();
      case _RoomLobbyPanel.players:
        return _buildPlayersCard();
    }
  }

  Widget _buildRoomCompactHeader(RoomStateSnapshot room) {
    final readyCount = _readyCount(room);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.35),
              ),
            ),
            child: const Icon(
              Icons.meeting_room_rounded,
              color: AppTheme.primaryColor,
              size: 19,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Room ${room.roomCode}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${room.players.length}/${room.maxPlayers} players · $readyCount ready',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _MetaPill(label: 'Entry', value: formatCurrency(room.stakeUsd)),
        ],
      ),
    );
  }

  Widget _buildRoomSubpageHeader(_RoomLobbyPanel panel) {
    final room = _room!;
    final title = switch (panel) {
      _RoomLobbyPanel.controls => _isHost ? 'Host Controls' : 'Your Controls',
      _RoomLobbyPanel.invite => 'Invite Players',
      _RoomLobbyPanel.players => 'Players',
    };
    return Row(
      children: [
        PressScale(
          enabled: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () =>
                  setState(() => _roomLobbyPanel = _RoomLobbyPanel.controls),
              borderRadius: BorderRadius.circular(12),
              child: Ink(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.gameSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.gameBorder),
                ),
                child: const Icon(
                  Icons.arrow_back_rounded,
                  color: AppTheme.textPrimary,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
        ),
        _MetaPill(label: 'Room', value: room.roomCode),
      ],
    );
  }

  Widget _buildRoomQuickActions(RoomStateSnapshot room) {
    final seatsLeft = room.maxPlayers - room.players.length;
    final hostInvitePage = _isHost && !room.inRound;
    return Column(
      children: [
        if (hostInvitePage)
          _buildRoomActionRow(
            icon: Icons.group_add_rounded,
            title: 'Invite Players',
            detail: seatsLeft > 0
                ? '$seatsLeft seat${seatsLeft == 1 ? '' : 's'} open'
                : 'Room full',
            panel: _RoomLobbyPanel.invite,
          )
        else
          _buildRoomActionRow(
            icon: Icons.groups_2_rounded,
            title: 'Players',
            detail: '${room.players.length}/${room.maxPlayers} joined',
            panel: _RoomLobbyPanel.players,
          ),
      ],
    );
  }

  Widget _buildRoomActionRow({
    required IconData icon,
    required String title,
    required String detail,
    required _RoomLobbyPanel panel,
  }) {
    return PressScale(
      enabled: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _roomLobbyPanel = panel),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.gameSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.gameBorder),
            ),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.goldButtonBottom, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        detail,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textSecondary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGameSwitcherRow() {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: multiplayerGameCatalog.length,
        separatorBuilder: (context, i) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final game = multiplayerGameCatalog[index];
          final active = game.key == _selected.key;
          return PressScale(
            enabled: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: active
                    ? null
                    : () {
                        setState(() {
                          _selected = game;
                          _stakeUsd = game.minStake;
                          _roomStakeFilter = _RoomStakeFilter.any;
                          _publicRooms.clear();
                          _loadingPublicRooms = !_playMode.isDemo;
                          _demoRollDeadline = null;
                          _demoResult = null;
                          _demoStatus = 'Demo room ready.';
                          _status = 'Join or create ${game.title}.';
                        });
                        if (!_playMode.isDemo) {
                          _refreshPublicRooms();
                        }
                      },
                borderRadius: BorderRadius.circular(999),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    gradient: active
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.goldButtonTop,
                              AppTheme.goldButtonBottom,
                            ],
                          )
                        : null,
                    color: active ? null : AppTheme.gameSurface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: active
                          ? AppTheme.goldButtonBottom
                          : AppTheme.gameBorder,
                    ),
                  ),
                  child: Text(
                    game.short,
                    style: TextStyle(
                      color: active ? AppTheme.goldText : AppTheme.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectedGameCard() {
    final activeRoomCount = _publicRooms
        .where((room) => _sameGameKey(room.gameKey, _selected.key))
        .length;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaPill(
                label: 'Entry From',
                value: formatCurrency(_selected.minStake),
              ),
              const _MetaPill(label: 'Players', value: '2–4'),
              _MetaPill(label: 'Open Rooms', value: '$activeRoomCount'),
              const _MetaPill(label: 'Winner Pool', value: '85%'),
            ],
          ),
          if (_selected.key == 'DICE_DUEL') ...[
            const SizedBox(height: 12),
            const _DiceRollPanel(compact: true),
          ] else if (_selected.key == 'COIN_TOSS') ...[
            const SizedBox(height: 12),
            _CoinFlipPanel(compact: true, value: _coinSide),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  expanded: true,
                  label: 'Create Room',
                  onPressed: _openCreateRoomSheet,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SecondaryButton(
                  expanded: true,
                  label: 'Join Code',
                  onPressed: _openJoinRoomSheet,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusNotice() {
    final showSpinner = _creatingRoom || _loadingPublicRooms;
    final message = _creatingRoom
        ? 'Creating room...'
        : _loadingPublicRooms
        ? 'Refreshing open rooms...'
        : _status;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Row(
        children: [
          if (showSpinner) ...[
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppTheme.goldButtonBottom,
                ),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInvitesCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pending Invites',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 8),
          ..._pendingInvites.take(3).map((invite) {
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.gameBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.gameBorder),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${invite.fromUserName} invited you to ${invite.room.roomCode}',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Entry ${formatCurrency(invite.room.stakeUsd)} • ${invite.room.playerCount}/${invite.room.maxPlayers} players',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MiniGoldButton(
                    label: 'Join',
                    onTap: () => _acceptInvite(invite),
                  ),
                  const SizedBox(width: 6),
                  _MiniGoldButton(
                    label: 'Later',
                    icon: Icons.close,
                    onTap: () => _dismissInvite(invite),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSmallSelect({
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return PressScale(
      enabled: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.gameBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.gameBorder),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPublicRoomsCard() {
    final visibleRooms = _visiblePublicRooms;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Available Rooms',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              _MiniGoldButton(
                label: 'Refresh',
                icon: Icons.refresh,
                onTap: _refreshPublicRooms,
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Filter by entry.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStakeFilterChip(_RoomStakeFilter.any, 'Any'),
              _buildStakeFilterChip(_RoomStakeFilter.entry1to5, '\$1-\$5'),
              _buildStakeFilterChip(_RoomStakeFilter.entry6to20, '\$6-\$20'),
              _buildStakeFilterChip(_RoomStakeFilter.entry21Plus, '\$21+'),
            ],
          ),
          const SizedBox(height: 10),
          if (_loadingPublicRooms)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (visibleRooms.isEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No rooms found.',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ] else
            ...visibleRooms.map((room) {
              final seatsLeft = room.maxPlayers - room.playerCount;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.gameBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.gameBorder),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                room.roomCode,
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: seatsLeft > 0
                                      ? AppTheme.success.withValues(alpha: 0.14)
                                      : AppTheme.gameBorder,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  seatsLeft > 0
                                      ? '$seatsLeft seat${seatsLeft == 1 ? '' : 's'} open'
                                      : 'Full',
                                  style: TextStyle(
                                    color: seatsLeft > 0
                                        ? AppTheme.success
                                        : AppTheme.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${room.playerCount}/${room.maxPlayers} players · ${formatCurrency(room.stakeUsd)} entry',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _MiniGoldButton(
                      label: 'Join',
                      onTap: () => _joinPublicRoom(room.roomCode),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildStakeFilterChip(_RoomStakeFilter filter, String label) {
    final selected = _roomStakeFilter == filter;
    return PressScale(
      enabled: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _roomStakeFilter = filter),
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: selected
                    ? AppTheme.goldButtonBottom
                    : AppTheme.gameBorder,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? AppTheme.goldText : AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomStageCard() {
    final room = _room!;
    final isWaiting = _round == null && _lastResult == null;
    final isLive = _round != null;

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
              _StagePip(label: 'LOBBY', active: isWaiting, done: !isWaiting),
              _stageLine(!isWaiting),
              _StagePip(
                label: 'ROUND',
                active: isLive,
                done: _lastResult != null,
              ),
              _stageLine(_lastResult != null),
              _StagePip(
                label: 'RESULT',
                active: _lastResult != null,
                done: false,
              ),
              const Spacer(),
              _MetaPill(label: 'Room', value: room.roomCode),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _roomStageTitle,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            _roomStageSummary,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _stageLine(bool done) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: done ? AppTheme.goldButtonBottom : AppTheme.gameBorder,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildRoomInviteCard() {
    final room = _room!;
    final seatsLeft = room.maxPlayers - room.players.length;
    final candidates = _availablePlayers
        .where((player) {
          return !room.players.any((member) => member.userId == player.userId);
        })
        .take(4)
        .toList(growable: false);
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
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
                  ),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppTheme.goldButtonBottom),
                ),
                child: const Icon(
                  Icons.group_add_rounded,
                  color: AppTheme.goldText,
                  size: 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Invite Players',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$seatsLeft seat${seatsLeft == 1 ? '' : 's'} left.',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh players',
                onPressed: _refreshAvailablePlayers,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: AppTheme.textSecondary.withValues(alpha: 0.9),
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.gameBackground,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.gameBorder),
                  ),
                  child: Text(
                    room.roomCode,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                      letterSpacing: 3,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(
                  expanded: true,
                  label: 'COPY CODE',
                  onPressed: _copyRoomCode,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            expanded: true,
            label: 'SHARE LINK',
            onPressed: _copyRoomLink,
          ),
          const SizedBox(height: 12),
          if (_loadingAvailablePlayers)
            const LinearProgressIndicator(
              minHeight: 2,
              color: AppTheme.goldButtonBottom,
              backgroundColor: AppTheme.gameBorder,
            )
          else if (candidates.isEmpty)
            Text(
              'No online players available. Share the code or link.',
              style: TextStyle(
                color: AppTheme.textSecondary.withValues(alpha: 0.9),
                fontWeight: FontWeight.w700,
                fontSize: 12,
                height: 1.35,
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < candidates.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  _buildAvailablePlayerInviteTile(candidates[i]),
                ],
              ],
            ),
          const SizedBox(height: 10),
          SecondaryButton(
            expanded: true,
            label: 'INVITE BY USER ID',
            onPressed: _openInviteSheet,
          ),
          const SizedBox(height: 14),
          _buildJoinedPlayersSection(),
          if (_isHost) ...[
            const SizedBox(height: 12),
            _buildInviteHostActions(),
          ],
        ],
      ),
    );
  }

  Widget _buildInviteHostActions() {
    final canStart = _canStartRound();
    final hasResult = _lastResult != null;
    return Row(
      children: [
        Expanded(
          child: PrimaryButton(
            expanded: true,
            label: hasResult ? 'RESTART' : 'START ROUND',
            onPressed: canStart ? _startRound : null,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: PrimaryButton(
            expanded: true,
            label: 'LEAVE ROOM',
            onPressed: _leaveRoom,
          ),
        ),
      ],
    );
  }

  Widget _buildJoinedPlayersSection() {
    final room = _room!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Players Added',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              '${room.players.length}/${room.maxPlayers}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Ready players enter the pot.',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        for (final player in room.players) _buildRoomPlayerRow(player),
      ],
    );
  }

  Widget _buildAvailablePlayerInviteTile(AvailableRoomPlayer player) {
    final displayName = player.displayName.trim().isEmpty
        ? auth_models.fallbackGuestDisplayName(player.userId)
        : player.displayName.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: AppTheme.goldButtonBottom.withValues(alpha: 0.16),
            child: Text(
              displayName.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: AppTheme.goldButtonBottom,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              displayName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: FilledButton(
              onPressed: () => _sendDirectInvite(player.userId),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.goldButtonBottom,
                foregroundColor: AppTheme.goldText,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
              child: const Text('INVITE'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomPlayerRow(RoomPlayerSnapshot player) {
    final room = _room!;
    final isHostPlayer = player.userId == room.hostUserId;
    final canBoot = _isHost && !room.inRound && !isHostPlayer;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${player.displayName}${isHostPlayer ? ' (Host)' : ''}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  player.ready ? 'Ready' : 'Waiting to ready up',
                  style: TextStyle(
                    color: player.ready
                        ? AppTheme.success
                        : AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              gradient: player.ready
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.goldButtonTop,
                        AppTheme.goldButtonBottom,
                      ],
                    )
                  : null,
              color: player.ready ? null : AppTheme.gameSurface,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: player.ready
                    ? AppTheme.goldButtonBottom
                    : AppTheme.gameBorder,
              ),
            ),
            child: Text(
              player.ready ? 'READY' : 'WAITING',
              style: TextStyle(
                color: player.ready
                    ? AppTheme.goldText
                    : AppTheme.textSecondary,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (canBoot) ...[
            const SizedBox(width: 8),
            _MiniGoldButton(
              label: 'Boot',
              icon: Icons.person_remove_alt_1,
              onTap: () => _kickPlayer(player),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoomEconomyCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: _buildRoomEconomyContent(),
    );
  }

  Widget _buildRoomEconomyContent() {
    final room = _room!;
    final stake = _round?.stakeUsd ?? room.stakeUsd;
    final participantCount = _round?.playerCount ?? _potParticipantCount(room);
    final pot =
        _round?.potUsd ?? _roundMoney(stake * participantCount.toDouble());
    final commission = _round?.commissionUsd ?? _roundMoney(pot * 0.15);
    final distributable =
        _round?.distributableUsd ?? _roundMoney(pot - commission);
    final title = _round != null ? 'Pot Locked' : 'Pot Preview';
    final helper = _round != null
        ? 'Funds are in the pot.'
        : 'Host sets entry. Pot updates by seats.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          helper,
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _MetaPill(label: 'Each Entry', value: formatCurrency(stake)),
            _MetaPill(label: 'Players In', value: '$participantCount'),
            _MetaPill(label: 'Pot', value: formatCurrency(pot)),
            _MetaPill(
              label: 'Winner Pool',
              value: formatCurrency(distributable),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Platform commission ${formatCurrency(commission)} (15%)',
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildPlayersCard() {
    final room = _room!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Players',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(
                '${room.players.length}/${room.maxPlayers}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Ready players enter the pot.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          for (final player in room.players) _buildRoomPlayerRow(player),
        ],
      ),
    );
  }

  Widget _buildRoundCard() {
    final round = _round!;
    final progress = round.playerCount > 0
        ? round.actionCount / round.playerCount
        : 0.0;
    final isDiceRound = round.gameKey.trim().toUpperCase() == 'DICE_DUEL';
    final isCoinRound = round.gameKey.trim().toUpperCase() == 'COIN_TOSS';
    final diceRolling = isDiceRound && round.rollDeadline != null;
    final coinFlipping = isCoinRound && round.rollDeadline != null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppTheme.goldButtonBottom.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.goldButtonBottom,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'ROUND LIVE',
                style: TextStyle(
                  color: AppTheme.goldButtonBottom,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                '${round.actionCount}/${round.playerCount} locked',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: AppTheme.gameBorder,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppTheme.goldButtonBottom,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            round.actionHint,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          if (diceRolling || coinFlipping) ...[
            const SizedBox(height: 10),
            _RoundDeadlineNotice(
              deadline: round.rollDeadline!,
              label: diceRolling ? 'Roll stops' : 'Flip lands',
            ),
          ] else if (round.actionDeadline != null) ...[
            const SizedBox(height: 10),
            _RoundDeadlineNotice(
              deadline: round.actionDeadline!,
              label: 'Pick window',
            ),
          ],
          const SizedBox(height: 10),
          if (round.choices.isNotEmpty) ...[
            _buildPlayerChoicesPanel(round.choices),
            const SizedBox(height: 10),
          ],
          if (diceRolling)
            _DiceRollPanel(rolling: true, countdownDeadline: round.rollDeadline)
          else if (coinFlipping)
            _CoinFlipPanel(rolling: true, countdownDeadline: round.rollDeadline)
          else if (round.requiresAction)
            _buildActionPanel()
          else
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.gameBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.gameBorder),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.hourglass_top_rounded,
                    size: 14,
                    color: AppTheme.textSecondary,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Auto-resolving.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayerChoicesPanel(
    List<RoomPlayerChoice> choices, {
    String title = 'Choices',
    bool compact = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          ...choices.map((choice) {
            final isMe = choice.userId == _myUserId;
            final submitted = choice.submitted;
            final label = submitted
                ? (choice.revealed && choice.choice.trim().isNotEmpty
                      ? choice.choice
                      : 'Locked')
                : 'Waiting';
            final color = submitted
                ? AppTheme.goldButtonBottom
                : AppTheme.textSecondary;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    submitted
                        ? Icons.lock_rounded
                        : Icons.hourglass_empty_rounded,
                    size: 14,
                    color: color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${choice.displayName}${isMe ? ' (You)' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isMe
                            ? AppTheme.goldButtonBottom
                            : AppTheme.textPrimary,
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: submitted
                          ? AppTheme.goldButtonBottom.withValues(alpha: 0.12)
                          : AppTheme.gameSurface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: submitted
                            ? AppTheme.goldButtonBottom.withValues(alpha: 0.5)
                            : AppTheme.gameBorder,
                      ),
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        color: submitted
                            ? AppTheme.goldButtonBottom
                            : AppTheme.textSecondary,
                        fontSize: compact ? 10 : 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRoundTransparencyPanel(
    RoomRoundResultPayload result, {
    bool compact = false,
  }) {
    final rows = _roundResultRowsFor(result);
    final ruleSummary = _roundRuleSummary(result);
    if (rows.isEmpty && ruleSummary.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.goldButtonBottom.withValues(alpha: 0.34),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.fact_check_rounded,
                size: 15,
                color: AppTheme.goldButtonBottom,
              ),
              const SizedBox(width: 7),
              const Text(
                'ROUND AUDIT',
                style: TextStyle(
                  color: AppTheme.goldButtonBottom,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Text(
                '${result.participantCount} players',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          if (ruleSummary.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              ruleSummary,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ],
          if (result.gameKey.trim().toUpperCase() == 'RPS_CLASH') ...[
            const SizedBox(height: 8),
            _buildRpsRuleStrip(compact: compact),
          ],
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...rows.map((row) => _buildRoundResultRow(row, compact: compact)),
          ],
        ],
      ),
    );
  }

  Widget _buildRpsRuleStrip({bool compact = false}) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _buildRuleChip('Rock beats Scissors', compact: compact),
        _buildRuleChip('Scissors beats Paper', compact: compact),
        _buildRuleChip('Paper beats Rock', compact: compact),
      ],
    );
  }

  Widget _buildRuleChip(String label, {bool compact = false}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 9,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: AppTheme.goldButtonBottom.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.goldButtonBottom.withValues(alpha: 0.35),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.goldButtonBottom,
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildRoundResultRow(_RoundResultRow row, {bool compact = false}) {
    final statusColor = _resultStatusColor(row.status);
    final isMe = row.userId == _myUserId;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(compact ? 9 : 10),
      decoration: BoxDecoration(
        color: isMe
            ? AppTheme.goldButtonBottom.withValues(alpha: 0.08)
            : AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMe
              ? AppTheme.goldButtonBottom.withValues(alpha: 0.5)
              : statusColor.withValues(alpha: 0.32),
        ),
      ),
      child: Row(
        children: [
          Icon(_resultStatusIcon(row.status), size: 16, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row.displayName}${isMe ? ' (You)' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isMe
                        ? AppTheme.goldButtonBottom
                        : AppTheme.textPrimary,
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.choice,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: compact ? 7 : 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  row.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: compact ? 9 : 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatCurrency(row.payoutUsd),
                style: TextStyle(
                  color: row.payoutUsd > 0
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<_RoundResultRow> _roundResultRowsFor(RoomRoundResultPayload result) {
    final choices = _resultChoicesFor(result);
    if (choices.isEmpty) return const [];

    final gameKey = result.gameKey.trim().toUpperCase();
    final target = gameKey == 'TARGET_STRIKE'
        ? _intFromAny(result.detail['target'])
        : null;
    final targetPicks = gameKey == 'TARGET_STRIKE'
        ? _intMapFromDetail(result.detail['picks'])
        : const <String, int>{};
    final winnerSet = result.winnerUserIds.toSet();
    final payoutByUser = {
      for (final winner in result.winners) winner.userId: winner.payoutUsd,
    };
    final noWinner = _isNoWinnerResult(result);
    final tie = _isTieResult(result);
    final rows = choices.map((choice) {
      final isWinner = winnerSet.contains(choice.userId);
      final status = noWinner
          ? 'NO WIN'
          : tie
          ? 'TIE'
          : isWinner
          ? 'WIN'
          : 'LOSS';
      final payout = isWinner
          ? (payoutByUser[choice.userId] ?? result.payoutPerWinnerUsd)
          : 0.0;
      final pick = targetPicks[choice.userId];
      final distance = target != null && pick != null
          ? (pick - target).abs()
          : null;
      final choiceText = target != null && pick != null
          ? 'Number $pick • $distance away'
          : choice.choice.trim().isEmpty
          ? 'No move'
          : choice.choice;
      return _RoundResultRow(
        userId: choice.userId,
        displayName: choice.displayName,
        choice: choiceText,
        status: status,
        payoutUsd: payout,
        distance: distance,
      );
    }).toList();

    rows.sort((a, b) {
      if (target != null) {
        final leftDistance = a.distance ?? 1000000;
        final rightDistance = b.distance ?? 1000000;
        final distance = leftDistance.compareTo(rightDistance);
        if (distance != 0) return distance;
      }
      final rank = _resultStatusRank(
        a.status,
      ).compareTo(_resultStatusRank(b.status));
      if (rank != 0) return rank;
      if (a.userId == _myUserId && b.userId != _myUserId) return -1;
      if (b.userId == _myUserId && a.userId != _myUserId) return 1;
      return a.displayName.compareTo(b.displayName);
    });
    return rows;
  }

  Map<String, int> _intMapFromDetail(Object? raw) {
    if (raw is! Map) return const {};
    final values = <String, int>{};
    for (final entry in raw.entries) {
      final value = _intFromAny(entry.value);
      if (value != null) {
        values[entry.key.toString()] = value;
      }
    }
    return values;
  }

  int _resultStatusRank(String status) {
    return switch (status) {
      'WIN' => 0,
      'TIE' => 1,
      'NO WIN' => 2,
      _ => 3,
    };
  }

  Color _resultStatusColor(String status) {
    return switch (status) {
      'WIN' => AppTheme.success,
      'TIE' => AppTheme.goldButtonBottom,
      'NO WIN' => AppTheme.textSecondary,
      _ => AppTheme.danger,
    };
  }

  IconData _resultStatusIcon(String status) {
    return switch (status) {
      'WIN' => Icons.emoji_events_rounded,
      'TIE' => Icons.balance_rounded,
      'NO WIN' => Icons.remove_circle_outline_rounded,
      _ => Icons.close_rounded,
    };
  }

  bool _isNoWinnerResult(RoomRoundResultPayload result) {
    return result.detail['noWinners'] == true ||
        (result.winnerUserIds.isEmpty && result.winners.isEmpty);
  }

  bool _isTieResult(RoomRoundResultPayload result) {
    if (_isNoWinnerResult(result)) return false;
    final summary = result.summary.toLowerCase();
    if (summary.contains('tie') || summary.contains('split across all')) {
      return true;
    }
    final gameKey = result.gameKey.trim().toUpperCase();
    if (gameKey == 'RPS_CLASH') {
      return result.detail['winningPick'] == null &&
          result.winnerUserIds.length > 1;
    }
    if (gameKey == 'SECRET_BID') {
      return result.detail['winningBid'] == null &&
          result.winnerUserIds.length > 1;
    }
    return false;
  }

  String _roundRuleSummary(RoomRoundResultPayload result) {
    final detail = result.detail;
    switch (result.gameKey.trim().toUpperCase()) {
      case 'RPS_CLASH':
        final winningPick = detail['winningPick']?.toString().toUpperCase();
        if (winningPick == 'ROCK' ||
            winningPick == 'PAPER' ||
            winningPick == 'SCISSORS') {
          final pick = winningPick!;
          return '${_rpsMoveName(pick)} beats ${_rpsMoveName(_rpsBeats(pick))}. Winners picked ${_rpsMoveName(pick)}.';
        }
        return 'Tie: everyone picked the same move, or all three moves appeared. Pot splits across the table.';
      case 'DICE_DUEL':
        final roll = detail['roll'];
        return roll == null
            ? 'Matching the room dice wins.'
            : 'Dice landed $roll. Players who picked $roll win.';
      case 'TARGET_STRIKE':
        final target = detail['target'];
        return target == null
            ? 'Closest number wins.'
            : 'Closest number to $target wins.';
      case 'HIGH_CARD':
        return 'Highest card rank wins. Matching top cards split the winner pool.';
      case 'PARITY_CLASH':
        final sum = detail['sum'];
        final parity = detail['parity'];
        return sum == null || parity == null
            ? 'Digits matching the final parity win.'
            : 'Sum is $sum ($parity). Players with $parity digits win.';
      case 'COIN_TOSS':
        final coin = detail['coin'];
        return coin == null
            ? 'Matching the coin side wins.'
            : 'Coin landed $coin. Matching picks win.';
      case 'TREASURE_BOX':
        final box = detail['winningBox'];
        final resolution = detail['resolution']?.toString() ?? 'EXACT';
        if (box == null) return 'Exact box wins; otherwise closest wins.';
        return resolution == 'CLOSEST'
            ? 'Box $box opened. No exact hit, so the closest pick wins.'
            : 'Box $box opened. Exact picks win.';
      case 'SECRET_BID':
        final bid = detail['winningBid'];
        return bid == null
            ? 'No highest unique bid. Pot splits across all players.'
            : 'Highest unique bid wins. Winning bid: $bid.';
      case 'SPIN_BOTTLE':
        final stop = _spinBottleStop(result);
        if (stop == 'MIDDLE') return 'Bottle stopped in the middle. No winner.';
        return stop.isEmpty
            ? 'Pick matching the bottle side wins.'
            : 'Bottle landed $stop. Matching picks win.';
      case 'LOOT_BOX_POOL':
        final boxes = detail['winningBoxes'];
        final label = boxes is List && boxes.isNotEmpty
            ? boxes.join(', ')
            : 'the winning set';
        final resolution = detail['resolution']?.toString() ?? 'EXACT';
        return resolution == 'CLOSEST'
            ? 'Winning boxes: $label. No exact hit, so closest picks win.'
            : 'Winning boxes: $label. Exact hits win.';
      default:
        return result.summary;
    }
  }

  String _rpsBeats(String move) {
    return switch (move) {
      'ROCK' => 'SCISSORS',
      'PAPER' => 'ROCK',
      _ => 'PAPER',
    };
  }

  String _rpsMoveName(String move) {
    final lower = move.toLowerCase();
    return lower.isEmpty
        ? move
        : '${lower[0].toUpperCase()}${lower.substring(1)}';
  }

  String _rpsMoveIcon(String? move) {
    return switch (move?.trim().toUpperCase()) {
      'ROCK' => '🪨',
      'PAPER' => '📄',
      'SCISSORS' => '✂️',
      _ => '?',
    };
  }

  void _setDemoRpsPick(String pick) {
    _rpsPick = pick;
    if (_playMode.isDemo) {
      _demoResult = null;
      _demoRpsComputerPick = null;
      _demoStatus = 'Demo room ready.';
    }
  }

  Widget _buildRpsDemoFaceOff() {
    final result = _demoResult;
    final computerPick = _demoRpsComputerPick ?? result?.rpsComputerPick;
    final outcomeColor = result == null
        ? AppTheme.goldButtonBottom
        : result.tied
        ? AppTheme.textSecondary
        : result.won
        ? AppTheme.success
        : AppTheme.danger;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: outcomeColor.withValues(alpha: 0.34)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildRpsDemoMoveTile(
              title: 'YOU',
              move: _rpsPick,
              accent: AppTheme.goldButtonBottom,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              'VS',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Expanded(
            child: _buildRpsDemoMoveTile(
              title: 'COMPUTER',
              move: computerPick,
              accent: outcomeColor,
              placeholder: _demoResolving ? 'CHOOSING' : 'READY',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRpsDemoMoveTile({
    required String title,
    required String? move,
    required Color accent,
    String placeholder = 'READY',
  }) {
    final normalized = move?.trim().toUpperCase();
    final label = normalized == null || normalized.isEmpty
        ? placeholder
        : normalized;
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.36)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            child: Text(
              _rpsMoveIcon(normalized),
              key: ValueKey('$title-$label-icon'),
              style: const TextStyle(fontSize: 24),
            ),
          ),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            child: Text(
              label,
              key: ValueKey('$title-$label-text'),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: normalized == null ? AppTheme.textSecondary : accent,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildActionInputForGame(),
        const SizedBox(height: 12),
        if (_hasSubmittedAction)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppTheme.success.withValues(alpha: 0.4),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.success,
                  size: 16,
                ),
                SizedBox(width: 8),
                Text(
                  'Move submitted.',
                  style: TextStyle(
                    color: AppTheme.success,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          )
        else
          PrimaryButton(
            expanded: true,
            label: _selected.actionLabel,
            onPressed: _submitAction,
          ),
      ],
    );
  }

  Widget _buildActionInputForGame() {
    switch (_selected.key) {
      case 'RPS_CLASH':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_playMode.isDemo) ...[
              _buildRpsDemoFaceOff(),
              const SizedBox(height: 12),
            ],
            const _ActionHint(text: 'Pick your move.'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildIconChoiceChip(
                    icon: '🪨',
                    label: 'ROCK',
                    selected: _rpsPick,
                    onSelect: (v) => _setDemoRpsPick(v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildIconChoiceChip(
                    icon: '📄',
                    label: 'PAPER',
                    selected: _rpsPick,
                    onSelect: (v) => _setDemoRpsPick(v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildIconChoiceChip(
                    icon: '✂️',
                    label: 'SCISSORS',
                    selected: _rpsPick,
                    onSelect: (v) => _setDemoRpsPick(v),
                  ),
                ),
              ],
            ),
          ],
        );
      case 'DICE_DUEL':
        final demoResultRoll = _playMode.isDemo && !_demoResolving
            ? _demoResult?.diceRoll
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DiceRollPanel(
              value: demoResultRoll ?? _dicePick,
              rolling: _playMode.isDemo && _demoResolving,
              countdownDeadline: _demoRollDeadline,
              phaseLabel: demoResultRoll == null ? null : 'LANDED',
              valueText: demoResultRoll == null ? null : 'Roll $demoResultRoll',
            ),
            const SizedBox(height: 12),
            const _ActionHint(text: 'Pick 1-6 before the roll.'),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 6,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.55,
              ),
              itemBuilder: (context, index) {
                final n = index + 1;
                return _buildSelectableNumber(
                  label: '$n',
                  selected: _dicePick == n,
                  onTap: _hasSubmittedAction
                      ? null
                      : () => setState(() {
                          _dicePick = n;
                          _demoResult = null;
                          _demoStatus = 'Demo room ready.';
                        }),
                );
              },
            ),
          ],
        );
      case 'TARGET_STRIKE':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ActionHint(text: 'Pick 0-99.'),
            const SizedBox(height: 10),
            Center(
              child: Text(
                '$_targetPick',
                style: const TextStyle(
                  color: AppTheme.goldButtonBottom,
                  fontWeight: FontWeight.w900,
                  fontSize: 42,
                ),
              ),
            ),
            Slider(
              value: _targetPick.toDouble(),
              min: 0,
              max: 99,
              divisions: 99,
              label: '$_targetPick',
              activeColor: AppTheme.goldButtonBottom,
              inactiveColor: AppTheme.gameBorder,
              onChanged: _hasSubmittedAction
                  ? null
                  : (v) => setState(() => _targetPick = v.round()),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                Text(
                  '0',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '99',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        );
      case 'PARITY_CLASH':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ActionHint(text: 'Pick 0-9.'),
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
              itemBuilder: (context, index) => _buildSelectableNumber(
                label: '$index',
                selected: _parityDigit == index,
                onTap: _hasSubmittedAction
                    ? null
                    : () => setState(() => _parityDigit = index),
              ),
            ),
          ],
        );
      case 'COIN_TOSS':
        final demoResultCoin = _playMode.isDemo && !_demoResolving
            ? _demoResult?.coinFace
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CoinFlipPanel(
              value: demoResultCoin ?? _coinSide,
              rolling: _playMode.isDemo && _demoResolving,
              countdownDeadline: _demoRollDeadline,
              phaseLabel: demoResultCoin == null ? null : 'LANDED',
              valueText: demoResultCoin == null ? null : 'Coin $demoResultCoin',
            ),
            const SizedBox(height: 12),
            const _ActionHint(text: 'Pick a side.'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildIconChoiceChip(
                    icon: '🌕',
                    label: 'HEADS',
                    selected: _coinSide,
                    onSelect: (v) {
                      _coinSide = v;
                      _demoResult = null;
                      _demoStatus = 'Demo room ready.';
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildIconChoiceChip(
                    icon: '🌑',
                    label: 'TAILS',
                    selected: _coinSide,
                    onSelect: (v) {
                      _coinSide = v;
                      _demoResult = null;
                      _demoStatus = 'Demo room ready.';
                    },
                  ),
                ),
              ],
            ),
          ],
        );
      case 'TREASURE_BOX':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ActionHint(text: 'Choose one box.'),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 6,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.55,
              ),
              itemBuilder: (context, index) {
                final n = index + 1;
                return _buildSelectableNumber(
                  label: '📦 $n',
                  selected: _treasureBoxPick == n,
                  onTap: _hasSubmittedAction
                      ? null
                      : () => setState(() => _treasureBoxPick = n),
                );
              },
            ),
          ],
        );
      case 'SECRET_BID':
        return _buildSecretBidActionInput();
      case 'SPIN_BOTTLE':
        return _buildSpinBottleActionInput();
      case 'LOOT_BOX_POOL':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ActionHint(text: 'Choose 1-20.'),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 20,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 1.55,
              ),
              itemBuilder: (context, index) {
                final n = index + 1;
                return _buildSelectableNumber(
                  label: '$n',
                  selected: _lootBoxPick == n,
                  onTap: _hasSubmittedAction
                      ? null
                      : () => setState(() => _lootBoxPick = n),
                );
              },
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildIconChoiceChip({
    required String icon,
    required String label,
    required String selected,
    required ValueChanged<String> onSelect,
  }) {
    final active = selected == label;
    return PressScale(
      enabled: !_hasSubmittedAction,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _hasSubmittedAction
              ? null
              : () => setState(() => onSelect(label)),
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: active
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.goldButtonTop,
                        AppTheme.goldButtonBottom,
                      ],
                    )
                  : null,
              color: active ? null : AppTheme.gameBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? AppTheme.goldButtonBottom : AppTheme.gameBorder,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: active ? AppTheme.goldText : AppTheme.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSecretBidActionInput() {
    final resolved =
        _playMode.isDemo &&
        _selected.key == 'SECRET_BID' &&
        _demoResult?.secretBidWinningBid != null;
    final displayBid = resolved
        ? _demoResult!.secretBidWinningBid!
        : _secretBid;
    final accent = resolved ? AppTheme.success : AppTheme.goldButtonBottom;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          resolved ? 'Winning bid' : 'Bid 1-100.',
          style: TextStyle(
            color: resolved ? AppTheme.success : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            '$displayBid',
            style: TextStyle(
              color: accent,
              fontWeight: FontWeight.w900,
              fontSize: 42,
            ),
          ),
        ),
        _buildSecretBidSlider(
          value: displayBid,
          accent: accent,
          enabled: !_hasSubmittedAction,
          onChanged: (v) => setState(() {
            _secretBid = v;
            _demoResult = null;
          }),
        ),
      ],
    );
  }

  Widget _buildSecretBidSlider({
    required int value,
    required Color accent,
    required bool enabled,
    required ValueChanged<int> onChanged,
  }) {
    final boundedValue = value.clamp(1, 100).toDouble();
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: accent,
            thumbColor: accent,
            valueIndicatorColor: accent,
            disabledActiveTrackColor: accent,
            disabledThumbColor: accent,
            inactiveTrackColor: AppTheme.gameBorder,
            disabledInactiveTrackColor: AppTheme.gameBorder,
          ),
          child: Slider(
            value: boundedValue,
            min: 1,
            max: 100,
            divisions: 99,
            label: '${boundedValue.round()}',
            activeColor: accent,
            inactiveColor: AppTheme.gameBorder,
            onChanged: enabled ? (v) => onChanged(v.round()) : null,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: const [
            Text(
              '1',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '100',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSpinBottleActionInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSpinBottleBoard(),
        const SizedBox(height: 12),
        const Text(
          'Choose LEFT or RIGHT, then spin',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildSpinBottleSideButton(
                label: 'LEFT',
                color: const Color(0xFFB62E2E),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _buildSpinBottleSideButton(
                label: 'RIGHT',
                color: const Color(0xFF121212),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSpinBottleBoard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
      child: Column(
        children: [
          Text(
            _round == null ? 'Demo Round' : 'Round Live',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1,
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
                                    bottomLeft: Radius.circular(999),
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'LEFT',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: math.max(22.0, size * 0.12),
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
                                    bottomRight: Radius.circular(999),
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  'RIGHT',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: math.max(22.0, size * 0.12),
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
                        Icon(
                          Icons.navigation,
                          size: size * 0.55,
                          color: Colors.white.withValues(alpha: 0.92),
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
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pot mode • platform commission 15%',
            style: TextStyle(
              color: AppTheme.goldText,
              fontSize: 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpinBottleSideButton({
    required String label,
    required Color color,
  }) {
    final active = _spinBottleSide == label;
    return PressScale(
      enabled: !_hasSubmittedAction,
      child: Container(
        height: 62,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active
                ? AppTheme.goldButtonBottom
                : color.withValues(alpha: 0.35),
            width: active ? 2.4 : 1,
          ),
          boxShadow: active
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
            onTap: _hasSubmittedAction
                ? null
                : () => setState(() => _spinBottleSide = label),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(
                    alpha: _hasSubmittedAction ? 0.55 : 1,
                  ),
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

  Widget _buildSelectableNumber({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return PressScale(
      enabled: onTap != null,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
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
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected
                    ? AppTheme.goldButtonBottom
                    : AppTheme.gameBorder,
              ),
            ),
            child: Center(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: selected ? AppTheme.goldText : AppTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultCard() {
    final result = _lastResult!;
    final didWin = result.winnerUserIds.contains(_myUserId);
    final isSecretBid = _isSecretBidResult(result);
    final details = isSecretBid
        ? const <String>[]
        : _formatDetail(result.detail);
    final noWinnerResult = _isNoWinnerResult(result);
    final tieResult = _isTieResult(result);
    RoomWinnerPayout? myWinnerRow;
    for (final winner in result.winners) {
      if (winner.userId == _myUserId) {
        myWinnerRow = winner;
        break;
      }
    }
    final net = myWinnerRow != null
        ? myWinnerRow.payoutUsd - result.stakeUsd
        : -result.stakeUsd;
    final outcomeTitle = noWinnerResult
        ? 'No winner this round'
        : tieResult
        ? 'Round tied'
        : didWin
        ? 'You Won!'
        : 'Better luck next time';
    final outcomeIcon = noWinnerResult
        ? Icons.remove_circle_outline_rounded
        : tieResult
        ? Icons.balance_rounded
        : didWin
        ? Icons.emoji_events_rounded
        : Icons.sentiment_dissatisfied_rounded;
    final outcomeColor = noWinnerResult
        ? AppTheme.textSecondary
        : tieResult
        ? AppTheme.goldButtonBottom
        : didWin
        ? AppTheme.success
        : AppTheme.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: didWin && !tieResult
              ? AppTheme.success.withValues(alpha: 0.6)
              : tieResult
              ? AppTheme.goldButtonBottom.withValues(alpha: 0.5)
              : AppTheme.gameBorder,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              color: didWin
                  ? AppTheme.success.withValues(alpha: 0.1)
                  : tieResult
                  ? AppTheme.goldButtonBottom.withValues(alpha: 0.1)
                  : AppTheme.gameBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Icon(outcomeIcon, color: outcomeColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        outcomeTitle,
                        style: TextStyle(
                          color: didWin && !tieResult
                              ? AppTheme.success
                              : tieResult
                              ? AppTheme.goldButtonBottom
                              : AppTheme.textPrimary,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        result.summary,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: net >= 0
                        ? AppTheme.success.withValues(alpha: 0.15)
                        : AppTheme.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${net >= 0 ? '+' : ''}${formatCurrency(net)}',
                    style: TextStyle(
                      color: net >= 0 ? AppTheme.success : AppTheme.danger,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _MetaPill(
                      label: 'Entry',
                      value: formatCurrency(result.stakeUsd),
                    ),
                    _MetaPill(
                      label: 'Pot',
                      value: formatCurrency(result.potUsd),
                    ),
                    _MetaPill(
                      label: 'Winner Pool',
                      value: formatCurrency(result.distributableUsd),
                    ),
                    _MetaPill(
                      label: 'Per Winner',
                      value: formatCurrency(result.payoutPerWinnerUsd),
                    ),
                  ],
                ),
                if (_winningLootBoxesFor(result).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildLootBoxReveal(result),
                ],
                if (_isDiceResult(result)) ...[
                  const SizedBox(height: 10),
                  _buildDiceResultReveal(result),
                ],
                if (_isCoinResult(result)) ...[
                  const SizedBox(height: 10),
                  _buildCoinResultReveal(result),
                ],
                if (_isTargetStrikeResult(result)) ...[
                  const SizedBox(height: 10),
                  _buildTargetStrikeResultReveal(result),
                ],
                if (_isSpinBottleResult(result)) ...[
                  const SizedBox(height: 10),
                  _buildSpinBottleOutcome(result),
                ],
                if (isSecretBid) ...[
                  const SizedBox(height: 10),
                  _buildSecretBidResultReveal(result),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...details.map(
                    (line) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        line,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                _buildRoundTransparencyPanel(result),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLootBoxReveal(RoomRoundResultPayload result) {
    final winningBoxes = _winningLootBoxesFor(result);
    final pickedBoxes = _pickedLootBoxesFor(result);
    final isPool = result.gameKey == 'LOOT_BOX_POOL';
    final count = isPool ? 20 : 6;
    if (winningBoxes.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.goldButtonBottom.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'WINNING BOXES',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: count,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 7,
              crossAxisSpacing: 7,
              childAspectRatio: 1.15,
            ),
            itemBuilder: (context, index) {
              final number = index + 1;
              final winning = winningBoxes.contains(number);
              final picked = pickedBoxes.contains(number);
              final tile = Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: winning
                      ? const Color(0xFF3D300D)
                      : picked
                      ? AppTheme.goldButtonBottom.withValues(alpha: 0.14)
                      : AppTheme.gameSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: winning
                        ? AppTheme.goldButtonBottom
                        : picked
                        ? AppTheme.goldButtonBottom.withValues(alpha: 0.6)
                        : AppTheme.gameBorder,
                    width: winning ? 2 : 1,
                  ),
                ),
                child: Text(
                  '$number',
                  style: TextStyle(
                    color: winning
                        ? AppTheme.goldButtonBottom
                        : picked
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              );
              if (!winning) return tile;
              return _FlashingWinningBox(child: tile);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSecretBidResultReveal(RoomRoundResultPayload result) {
    final winningBid = _secretBidWinningBidForResult(result);
    final displayBid =
        winningBid ?? _highestSecretBidFromResult(result) ?? _secretBid;
    final rows = _secretBidOpponentRowsForResult(result, displayBid);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            winningBid == null ? 'NO UNIQUE BID' : 'WINNING BID',
            style: const TextStyle(
              color: AppTheme.success,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Center(
            child: Text(
              '$displayBid',
              style: const TextStyle(
                color: AppTheme.success,
                fontWeight: FontWeight.w900,
                fontSize: 42,
              ),
            ),
          ),
          _buildSecretBidSlider(
            value: displayBid,
            accent: AppTheme.success,
            enabled: false,
            onChanged: (_) {},
          ),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildSecretBidOpponentList(
              rows: rows,
              targetBid: winningBid ?? displayBid,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTargetStrikeResultReveal(
    RoomRoundResultPayload result, {
    bool compact = false,
  }) {
    final target = _intFromAny(result.detail['target']);
    final picks = _intMapFromDetail(result.detail['picks']);
    if (target == null) return const SizedBox.shrink();

    int? bestDistance;
    for (final pick in picks.values) {
      final distance = (pick - target).abs();
      if (bestDistance == null || distance < bestDistance) {
        bestDistance = distance;
      }
    }
    final winnerLabel = result.winners.isEmpty
        ? 'No winner'
        : result.winners.length == 1
        ? '${result.winners.first.displayName} wins'
        : '${result.winners.length} winners';

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.goldButtonBottom.withValues(alpha: 0.38),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 58 : 68,
            height: compact ? 58 : 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.goldButtonBottom.withValues(alpha: 0.1),
              border: Border.all(color: AppTheme.goldButtonBottom, width: 2),
            ),
            child: Center(
              child: Text(
                '$target',
                style: TextStyle(
                  color: AppTheme.goldButtonBottom,
                  fontSize: compact ? 24 : 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TARGET NUMBER',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Closest pick wins',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  bestDistance == null
                      ? winnerLabel
                      : '$winnerLabel • $bestDistance away',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecretBidOpponentList({
    required List<_SecretBidRow> rows,
    required int? targetBid,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          targetBid == null ? 'OPPONENT BIDS' : 'CLOSEST OPPONENT BIDS',
          style: const TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 8),
        ...rows.map((row) {
          final rowColor = row.isWinner
              ? AppTheme.success
              : AppTheme.textPrimary;
          final distanceLabel = row.distance == 0
              ? 'Exact'
              : 'Off by ${row.distance}';
          return Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Row(
              children: [
                Icon(
                  row.isWinner
                      ? Icons.emoji_events_rounded
                      : Icons.person_rounded,
                  color: row.isWinner
                      ? AppTheme.success
                      : AppTheme.textSecondary,
                  size: 15,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    row.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: rowColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: row.isWinner
                        ? AppTheme.success.withValues(alpha: 0.12)
                        : AppTheme.gameSurface,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: row.isWinner
                          ? AppTheme.success.withValues(alpha: 0.45)
                          : AppTheme.gameBorder,
                    ),
                  ),
                  child: Text(
                    'Bid ${row.bid}',
                    style: TextStyle(
                      color: row.isWinner
                          ? AppTheme.success
                          : AppTheme.textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 58,
                  child: Text(
                    distanceLabel,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDiceResultReveal(RoomRoundResultPayload result) {
    final roll = _intFromAny(result.detail['roll']) ?? 1;
    final round = _intFromAny(result.detail['tieBreakerRound']) ?? 1;
    final winnerLabel = result.winners.isEmpty
        ? 'No winner'
        : result.winners.length == 1
        ? result.winners.first.displayName
        : '${result.winners.length} winners';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.goldButtonBottom.withValues(alpha: 0.38),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: 58, height: 58, child: _DiceFace(value: roll)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ROUND $round ROLL',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Landed $roll',
                  style: const TextStyle(
                    color: AppTheme.goldButtonBottom,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  winnerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoinResultReveal(RoomRoundResultPayload result) {
    final coin = result.detail['coin']?.toString().trim().toUpperCase();
    final face = coin == 'TAILS' ? 'TAILS' : 'HEADS';
    final winnerLabel = result.winners.isEmpty
        ? 'No winner'
        : result.winners.length == 1
        ? result.winners.first.displayName
        : '${result.winners.length} winners';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.goldButtonBottom.withValues(alpha: 0.38),
        ),
      ),
      child: Row(
        children: [
          SizedBox(width: 58, height: 58, child: _CoinFace(face: face)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'COIN FLIP',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Landed $face',
                  style: const TextStyle(
                    color: AppTheme.goldButtonBottom,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  winnerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpinBottleOutcome(
    RoomRoundResultPayload result, {
    bool compact = false,
  }) {
    final stop = _spinBottleStop(result);
    final stopLabel = stop.isEmpty ? 'UNKNOWN' : stop;
    final winners = result.winners;
    final hasWinner = winners.isNotEmpty;
    final isMiddle = stop == 'MIDDLE';
    final accent = hasWinner
        ? AppTheme.success
        : isMiddle
        ? AppTheme.danger
        : AppTheme.goldButtonBottom;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.38)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: compact ? 32 : 38,
                height: compact ? 32 : 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasWinner
                      ? Icons.emoji_events_rounded
                      : Icons.trip_origin_rounded,
                  color: accent,
                  size: compact ? 16 : 19,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BOTTLE LANDED',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stopLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w900,
                        fontSize: compact ? 16 : 18,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: hasWinner
                      ? AppTheme.success.withValues(alpha: 0.12)
                      : AppTheme.gameSurface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withValues(alpha: 0.45)),
                ),
                child: Text(
                  hasWinner
                      ? '${winners.length} winner${winners.length == 1 ? '' : 's'}'
                      : 'No winner',
                  style: TextStyle(
                    color: accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (hasWinner)
            ...winners.map(
              (winner) => Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Icon(
                      winner.userId == _myUserId
                          ? Icons.check_circle_rounded
                          : Icons.person_rounded,
                      color: winner.userId == _myUserId
                          ? AppTheme.success
                          : AppTheme.textSecondary,
                      size: 15,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${winner.displayName}${winner.userId == _myUserId ? ' (You)' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: winner.userId == _myUserId
                              ? AppTheme.success
                              : AppTheme.textPrimary,
                          fontSize: compact ? 11 : 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      formatCurrency(winner.payoutUsd),
                      style: TextStyle(
                        color: winner.userId == _myUserId
                            ? AppTheme.success
                            : AppTheme.textPrimary,
                        fontSize: compact ? 11 : 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Text(
              isMiddle ? 'Middle keeps the pot.' : 'No player matched it.',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLobbyFooterCard() {
    final me = _me;
    final room = _room!;
    final isReady = me?.ready == true;
    final canStart = _canStartRound();
    final hasResult = _lastResult != null;
    final nextStake = _stakeUsd < _selected.minStake
        ? _selected.minStake
        : _stakeUsd;
    final potParticipants = _potParticipantCount(room);
    final currentPot = _roundMoney(nextStake * potParticipants.toDouble());

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
              Icon(
                _isHost ? Icons.manage_accounts_rounded : Icons.person_rounded,
                size: 16,
                color: AppTheme.goldButtonBottom,
              ),
              const SizedBox(width: 6),
              Text(
                _isHost && hasResult
                    ? 'Restart Room'
                    : _isHost
                    ? 'Host Controls'
                    : 'Your Controls',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            hasResult && _isHost
                ? 'Set entry and restart.'
                : hasResult
                ? 'Join the next round or leave.'
                : _isHost
                ? canStart
                      ? 'Set entry and start.'
                      : 'Set entry and ready up.'
                : isReady
                ? 'Waiting for host.'
                : 'Lock your seat.',
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          _buildRoomEconomyContent(),
          if (_isHost) ...[
            const SizedBox(height: 12),
            StakeAdjuster(
              label: 'ENTRY EACH',
              value: nextStake,
              min: _selected.minStake,
              onChanged: _setNextRoomStake,
            ),
            const SizedBox(height: 6),
            Text(
              '${formatCurrency(currentPot)} pot across $potParticipants seats.',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _StableGoldRoomButton(
                  expanded: true,
                  label: _pendingHostReadyHandoff
                      ? 'READYING...'
                      : isReady
                      ? 'UNREADY'
                      : hasResult
                      ? 'JOIN NEXT'
                      : 'READY',
                  onPressed:
                      me == null ||
                          _pendingHostReadyHandoff ||
                          _recoveringRoomConnection
                      ? null
                      : () => _setReady(!isReady),
                ),
              ),
              if (!_isHost) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                    expanded: true,
                    label: 'LEAVE ROOM',
                    onPressed: _leaveRoom,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  bool _isSpinBottleResult(RoomRoundResultPayload result) {
    return result.gameKey.trim().toUpperCase() == 'SPIN_BOTTLE';
  }

  bool _isDiceResult(RoomRoundResultPayload result) {
    return result.gameKey.trim().toUpperCase() == 'DICE_DUEL';
  }

  bool _isCoinResult(RoomRoundResultPayload result) {
    return result.gameKey.trim().toUpperCase() == 'COIN_TOSS';
  }

  bool _isTargetStrikeResult(RoomRoundResultPayload result) {
    return result.gameKey.trim().toUpperCase() == 'TARGET_STRIKE';
  }

  bool _isSecretBidResult(RoomRoundResultPayload result) {
    return result.gameKey.trim().toUpperCase() == 'SECRET_BID';
  }

  int? _secretBidWinningBidForResult(RoomRoundResultPayload result) {
    return _intFromAny(result.detail['winningBid']);
  }

  int? _highestSecretBidFromResult(RoomRoundResultPayload result) {
    final raw = result.detail['bids'];
    if (raw is! Map || raw.isEmpty) return null;
    final bids = raw.values.map(_intFromAny).whereType<int>();
    if (bids.isEmpty) return null;
    return bids.reduce(math.max);
  }

  List<_SecretBidRow> _secretBidOpponentRowsForResult(
    RoomRoundResultPayload result,
    int targetBid,
  ) {
    final raw = result.detail['bids'];
    if (raw is! Map || raw.isEmpty) return const [];
    final rows = <_SecretBidRow>[];
    for (final entry in raw.entries) {
      final userId = entry.key.toString();
      if (userId == _myUserId) continue;
      final bid = _intFromAny(entry.value);
      if (bid == null) continue;
      rows.add(
        _SecretBidRow(
          displayName: _displayNameForUserId(userId),
          bid: bid,
          distance: (bid - targetBid).abs(),
          isWinner: result.winnerUserIds.contains(userId),
        ),
      );
    }
    rows.sort(_compareSecretBidRows);
    return rows;
  }

  int _compareSecretBidRows(_SecretBidRow a, _SecretBidRow b) {
    final distance = a.distance.compareTo(b.distance);
    if (distance != 0) return distance;
    final bid = b.bid.compareTo(a.bid);
    if (bid != 0) return bid;
    return a.displayName.compareTo(b.displayName);
  }

  String _spinBottleStop(RoomRoundResultPayload result) {
    final raw = result.detail['bottleStop'] ?? result.detail['winningSide'];
    return raw?.toString().trim().toUpperCase() ?? '';
  }

  String _spinBottleRoundSummary(RoomRoundResultPayload result) {
    final stop = _spinBottleStop(result);
    final stopText = stop.isEmpty ? 'Bottle settled.' : 'Bottle landed $stop.';
    if (result.winners.isEmpty) {
      return '$stopText No winner.';
    }

    final names = result.winners
        .map((winner) => winner.displayName.trim())
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
    if (names.isEmpty) return '$stopText Winner selected.';
    if (names.length == 1) return '$stopText ${names.first} wins.';
    if (names.length == 2) return "$stopText ${names.join(' and ')} win.";
    return '$stopText ${names.first} and ${names.length - 1} others win.';
  }

  List<String> _formatDetail(Map<String, dynamic> detail) {
    if (detail.isEmpty) return const [];
    final lines = <String>[];

    if (detail['target'] != null) {
      lines.add('Target ${detail['target']}');
    }
    if (detail['parity'] != null && detail['sum'] != null) {
      lines.add('Sum ${detail['sum']} (${detail['parity']})');
    }
    if (detail['winningPick'] != null) {
      lines.add('Winning pick ${detail['winningPick']}');
    }
    if (detail['roll'] != null) {
      final round = detail['tieBreakerRound'];
      lines.add(
        round == null
            ? 'Dice roll ${detail['roll']}'
            : 'Dice roll ${detail['roll']} • Round $round',
      );
    }
    if (detail['coin'] != null) {
      lines.add('Coin ${detail['coin']}');
    }
    if (detail['winningBox'] != null) {
      final resolution = detail['resolution']?.toString() ?? 'EXACT';
      lines.add('Winning box ${detail['winningBox']} ($resolution)');
    }
    final winningBoxes = detail['winningBoxes'];
    if (winningBoxes is List && winningBoxes.isNotEmpty) {
      lines.add('Winning boxes ${winningBoxes.join(', ')}');
    }
    if (detail['winningBid'] != null) {
      lines.add('Winning bid ${detail['winningBid']}');
    }
    return lines;
  }

  List<RoomPlayerChoice> _resultChoicesFor(RoomRoundResultPayload result) {
    if (result.choices.isNotEmpty) {
      return result.choices;
    }
    final detailKey = switch (result.gameKey) {
      'RPS_CLASH' => 'picks',
      'DICE_DUEL' => 'picks',
      'TARGET_STRIKE' => 'picks',
      'HIGH_CARD' => 'cards',
      'PARITY_CLASH' => 'digits',
      'COIN_TOSS' => 'picks',
      'TREASURE_BOX' => 'boxes',
      'SECRET_BID' => 'bids',
      'SPIN_BOTTLE' => 'picks',
      'LOOT_BOX_POOL' => 'boxPicks',
      _ => '',
    };
    if (detailKey.isEmpty) return const [];
    final raw = result.detail[detailKey];
    if (raw is! Map || raw.isEmpty) return const [];

    final choices = raw.entries.map((entry) {
      final userId = entry.key.toString();
      return RoomPlayerChoice(
        userId: userId,
        displayName: _displayNameForUserId(userId),
        submitted: true,
        revealed: true,
        choice: _choiceLabelForResult(result.gameKey, entry.value),
      );
    }).toList();
    choices.sort((a, b) => a.displayName.compareTo(b.displayName));
    return choices;
  }

  Set<int> _winningLootBoxesFor(RoomRoundResultPayload result) {
    if (result.gameKey == 'TREASURE_BOX') {
      final value = _intFromAny(result.detail['winningBox']);
      return value == null ? const {} : {value};
    }
    if (result.gameKey != 'LOOT_BOX_POOL') {
      return const {};
    }
    final raw = result.detail['winningBoxes'];
    if (raw is! List) return const {};
    return raw.map(_intFromAny).whereType<int>().toSet();
  }

  Set<int> _pickedLootBoxesFor(RoomRoundResultPayload result) {
    final key = result.gameKey == 'LOOT_BOX_POOL'
        ? 'boxPicks'
        : result.gameKey == 'TREASURE_BOX'
        ? 'boxes'
        : '';
    if (key.isEmpty) return const {};
    final raw = result.detail[key];
    if (raw is! Map) return const {};
    return raw.values.map(_intFromAny).whereType<int>().toSet();
  }

  int? _intFromAny(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  String _choiceLabelForResult(String gameKey, Object? value) {
    final text = value?.toString() ?? '';
    switch (gameKey) {
      case 'DICE_DUEL':
        return 'Pick $text';
      case 'TARGET_STRIKE':
        return 'Number $text';
      case 'HIGH_CARD':
        return 'Card $text';
      case 'PARITY_CLASH':
        return 'Digit $text';
      case 'COIN_TOSS':
        return 'Pick $text';
      case 'TREASURE_BOX':
      case 'LOOT_BOX_POOL':
        return 'Box $text';
      case 'SECRET_BID':
        return 'Bid $text';
      default:
        return text;
    }
  }

  String _displayNameForUserId(String userId) {
    final room = _room;
    if (room != null) {
      for (final player in room.players) {
        if (player.userId == userId) {
          return player.displayName;
        }
      }
    }
    final result = _lastResult;
    if (result != null) {
      for (final winner in result.winners) {
        if (winner.userId == userId) {
          return winner.displayName;
        }
      }
    }
    return auth_models.fallbackGuestDisplayName(userId);
  }
}

class _RoundDeadlineNotice extends StatefulWidget {
  const _RoundDeadlineNotice({
    required this.deadline,
    this.label = 'Pick window',
  });

  final DateTime deadline;
  final String label;

  @override
  State<_RoundDeadlineNotice> createState() => _RoundDeadlineNoticeState();
}

class _RoundDeadlineNoticeState extends State<_RoundDeadlineNotice> {
  late Timer _timer;
  late int _secondsLeft;

  @override
  void initState() {
    super.initState();
    _secondsLeft = _remainingSeconds();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft = _remainingSeconds());
    });
  }

  @override
  void didUpdateWidget(covariant _RoundDeadlineNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.deadline != widget.deadline) {
      _secondsLeft = _remainingSeconds();
    }
  }

  int _remainingSeconds() {
    final remaining = widget.deadline.difference(DateTime.now()).inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.goldButtonBottom.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.goldButtonBottom.withValues(alpha: 0.34),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.timer_rounded,
            size: 15,
            color: AppTheme.goldButtonBottom,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.label,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${_secondsLeft}s',
            style: const TextStyle(
              color: AppTheme.goldButtonBottom,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiceRollPanel extends StatefulWidget {
  const _DiceRollPanel({
    this.compact = false,
    this.rolling = false,
    this.value,
    this.countdownDeadline,
    this.phaseLabel,
    this.valueText,
  });

  final bool compact;
  final bool rolling;
  final int? value;
  final DateTime? countdownDeadline;
  final String? phaseLabel;
  final String? valueText;

  @override
  State<_DiceRollPanel> createState() => _DiceRollPanelState();
}

class _DiceRollPanelState extends State<_DiceRollPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final math.Random _random;
  Timer? _faceTimer;
  Timer? _countdownTimer;
  int _face = 1;
  int? _secondsLeft;

  @override
  void initState() {
    super.initState();
    _random = math.Random();
    _face = (widget.value ?? 1).clamp(1, 6).toInt();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1150),
    );
    _syncAnimation();
    _syncCountdown();
  }

  @override
  void didUpdateWidget(covariant _DiceRollPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rolling != widget.rolling) {
      _syncAnimation();
      _syncCountdown();
    } else if (oldWidget.countdownDeadline != widget.countdownDeadline) {
      _syncCountdown();
    }
    if (!widget.rolling && oldWidget.value != widget.value) {
      setState(() => _face = (widget.value ?? 1).clamp(1, 6).toInt());
    }
  }

  void _syncAnimation() {
    _faceTimer?.cancel();
    _faceTimer = null;
    if (widget.rolling) {
      _controller.repeat();
      _faceTimer = Timer.periodic(
        const Duration(milliseconds: 340),
        (_) => _shuffleFace(),
      );
      return;
    }
    _controller.stop();
    _controller.value = 0;
    _face = (widget.value ?? _face).clamp(1, 6).toInt();
  }

  void _syncCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (!widget.rolling) {
      _secondsLeft = null;
      return;
    }
    _secondsLeft = _remainingSeconds();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft = _remainingSeconds());
    });
  }

  int _remainingSeconds() {
    final deadline = widget.countdownDeadline;
    if (deadline == null) return 10;
    final remaining = deadline.difference(DateTime.now()).inSeconds;
    return remaining < 0 ? 0 : remaining + 1;
  }

  void _shuffleFace() {
    if (!mounted) return;
    var next = 1 + _random.nextInt(6);
    if (next == _face) {
      next = (next % 6) + 1;
    }
    setState(() => _face = next);
  }

  @override
  void dispose() {
    _faceTimer?.cancel();
    _countdownTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dieSlot = widget.compact ? 74.0 : 96.0;
    final dieSize = widget.compact ? 54.0 : 70.0;
    final phaseLabel =
        widget.phaseLabel ?? (widget.rolling ? 'ROLLING' : 'PREDICTION');
    final valueLabel =
        widget.valueText ??
        (widget.rolling
            ? '${_secondsLeft ?? 10}s'
            : widget.value == null
            ? '1-6'
            : 'Number ${widget.value}');

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(widget.compact ? 10 : 12),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.goldButtonBottom.withValues(alpha: 0.34),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  phaseLabel,
                  style: TextStyle(
                    color: AppTheme.goldButtonBottom,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  valueLabel,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: widget.compact ? 20 : 26,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: dieSlot,
            height: dieSlot,
            child: Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final turn = widget.rolling
                      ? _controller.value * math.pi * 2
                      : 0.0;
                  final bob = widget.rolling
                      ? math.sin(_controller.value * math.pi * 2) *
                            (widget.compact ? 1.5 : 2.5)
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(0, bob),
                    child: Transform.rotate(
                      angle: turn,
                      child: SizedBox(
                        width: dieSize,
                        height: dieSize,
                        child: _DiceFace(value: _face),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiceFace extends StatelessWidget {
  const _DiceFace({required this.value});

  final int value;

  @override
  Widget build(BuildContext context) {
    final pips = _pipAlignments(value.clamp(1, 6));
    return LayoutBuilder(
      builder: (context, constraints) {
        final pipSize = math.max(6.0, constraints.maxWidth * 0.16);
        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white, AppTheme.goldButtonTop],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.goldButtonBottom, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.goldButtonBottom.withValues(alpha: 0.28),
                blurRadius: 18,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(constraints.maxWidth * 0.17),
            child: Stack(
              children: [
                for (final alignment in pips)
                  Align(
                    alignment: alignment,
                    child: Container(
                      width: pipSize,
                      height: pipSize,
                      decoration: const BoxDecoration(
                        color: AppTheme.goldText,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<Alignment> _pipAlignments(int face) {
    const topLeft = Alignment(-0.88, -0.88);
    const topRight = Alignment(0.88, -0.88);
    const middleLeft = Alignment(-0.88, 0);
    const center = Alignment.center;
    const middleRight = Alignment(0.88, 0);
    const bottomLeft = Alignment(-0.88, 0.88);
    const bottomRight = Alignment(0.88, 0.88);

    return switch (face) {
      1 => const [center],
      2 => const [topLeft, bottomRight],
      3 => const [topLeft, center, bottomRight],
      4 => const [topLeft, topRight, bottomLeft, bottomRight],
      5 => const [topLeft, topRight, center, bottomLeft, bottomRight],
      _ => const [
        topLeft,
        middleLeft,
        bottomLeft,
        topRight,
        middleRight,
        bottomRight,
      ],
    };
  }
}

class _CoinFlipPanel extends StatefulWidget {
  const _CoinFlipPanel({
    this.compact = false,
    this.rolling = false,
    this.value,
    this.countdownDeadline,
    this.phaseLabel,
    this.valueText,
  });

  final bool compact;
  final bool rolling;
  final String? value;
  final DateTime? countdownDeadline;
  final String? phaseLabel;
  final String? valueText;

  @override
  State<_CoinFlipPanel> createState() => _CoinFlipPanelState();
}

class _CoinFlipPanelState extends State<_CoinFlipPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final math.Random _random;
  Timer? _faceTimer;
  Timer? _countdownTimer;
  String _face = 'HEADS';
  int? _secondsLeft;

  @override
  void initState() {
    super.initState();
    _random = math.Random();
    _face = _normalizeFace(widget.value);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncAnimation();
    _syncCountdown();
  }

  @override
  void didUpdateWidget(covariant _CoinFlipPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.rolling != widget.rolling) {
      _syncAnimation();
      _syncCountdown();
    } else if (oldWidget.countdownDeadline != widget.countdownDeadline) {
      _syncCountdown();
    }
    if (!widget.rolling && oldWidget.value != widget.value) {
      setState(() => _face = _normalizeFace(widget.value));
    }
  }

  String _normalizeFace(String? value) {
    final face = value?.trim().toUpperCase();
    return face == 'TAILS' ? 'TAILS' : 'HEADS';
  }

  void _syncAnimation() {
    _faceTimer?.cancel();
    _faceTimer = null;
    if (widget.rolling) {
      _controller.repeat();
      _faceTimer = Timer.periodic(const Duration(milliseconds: 260), (_) {
        if (!mounted) return;
        final next = _random.nextInt(2) == 0 ? 'HEADS' : 'TAILS';
        setState(() {
          _face = next == _face ? (_face == 'HEADS' ? 'TAILS' : 'HEADS') : next;
        });
      });
      return;
    }
    _controller.stop();
    _controller.value = 0;
    _face = _normalizeFace(widget.value);
  }

  void _syncCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (!widget.rolling) {
      _secondsLeft = null;
      return;
    }
    _secondsLeft = _remainingSeconds();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _secondsLeft = _remainingSeconds());
    });
  }

  int _remainingSeconds() {
    final deadline = widget.countdownDeadline;
    if (deadline == null) return 10;
    final remaining = deadline.difference(DateTime.now()).inSeconds;
    return remaining < 0 ? 0 : remaining + 1;
  }

  @override
  void dispose() {
    _faceTimer?.cancel();
    _countdownTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final coinSlot = widget.compact ? 74.0 : 96.0;
    final coinSize = widget.compact ? 56.0 : 72.0;
    final phaseLabel =
        widget.phaseLabel ?? (widget.rolling ? 'FLIPPING' : 'PREDICTION');
    final valueLabel =
        widget.valueText ?? (widget.rolling ? '${_secondsLeft ?? 10}s' : _face);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(widget.compact ? 10 : 12),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.goldButtonBottom.withValues(alpha: 0.34),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  phaseLabel,
                  style: const TextStyle(
                    color: AppTheme.goldButtonBottom,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  valueLabel,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w900,
                    fontSize: widget.compact ? 20 : 26,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: coinSlot,
            height: coinSlot,
            child: Center(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  final turn = widget.rolling
                      ? _controller.value * math.pi * 2
                      : 0.0;
                  final bob = widget.rolling
                      ? math.sin(_controller.value * math.pi * 2) *
                            (widget.compact ? 1.5 : 2.5)
                      : 0.0;
                  return Transform.translate(
                    offset: Offset(0, bob),
                    child: Transform.rotate(
                      angle: turn,
                      child: SizedBox(
                        width: coinSize,
                        height: coinSize,
                        child: _CoinFace(face: _face),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoinFace extends StatelessWidget {
  const _CoinFace({required this.face});

  final String face;

  @override
  Widget build(BuildContext context) {
    final normalized = face.trim().toUpperCase() == 'TAILS' ? 'TAILS' : 'HEADS';
    final letter = normalized == 'HEADS' ? 'H' : 'T';
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFF6B8),
                AppTheme.goldButtonTop,
                AppTheme.goldButtonBottom,
              ],
            ),
            border: Border.all(color: AppTheme.goldButtonBottom, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppTheme.goldButtonBottom.withValues(alpha: 0.28),
                blurRadius: 18,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.all(size * 0.12),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.goldText.withValues(alpha: 0.38),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      letter,
                      style: TextStyle(
                        color: AppTheme.goldText,
                        fontWeight: FontWeight.w900,
                        fontSize: size * 0.42,
                        height: 0.92,
                      ),
                    ),
                    Text(
                      normalized,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppTheme.goldText,
                        fontWeight: FontWeight.w900,
                        fontSize: size * 0.12,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
              borderRadius: BorderRadius.circular(12),
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

class _ActionHint extends StatelessWidget {
  const _ActionHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          height: 1.35,
        ),
      ),
    );
  }
}

class _StagePip extends StatelessWidget {
  const _StagePip({
    required this.label,
    required this.active,
    required this.done,
  });

  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final filled = active || done;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: filled
                ? const LinearGradient(
                    colors: [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
                  )
                : null,
            color: filled ? null : AppTheme.gameBorder,
            border: Border.all(
              color: filled ? AppTheme.goldButtonBottom : AppTheme.gameBorder,
              width: active ? 2 : 1,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: filled ? AppTheme.goldButtonBottom : AppTheme.textSecondary,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.gameBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _StableGoldRoomButton extends StatelessWidget {
  const _StableGoldRoomButton({
    required this.label,
    required this.onPressed,
    this.expanded = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(context.radii.lg);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: 44,
              minWidth: expanded ? double.infinity : 120,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.primaryColor,
                borderRadius: radius,
                border: Border.all(color: AppTheme.goldButtonBottom),
              ),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: context.space.lg,
                    vertical: context.space.sm,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: context.type.bodyStrong.copyWith(
                      color: AppTheme.goldText,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniGoldButton extends StatelessWidget {
  const _MiniGoldButton({required this.label, required this.onTap, this.icon});

  final String label;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      enabled: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.32),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: AppTheme.primaryColor, size: 16),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DemoRoomResult {
  const _DemoRoomResult({
    required this.won,
    this.tied = false,
    required this.playerCount,
    required this.winnerCount,
    required this.stakeUsd,
    required this.potUsd,
    required this.commissionUsd,
    required this.payoutUsd,
    required this.netUsd,
    required this.action,
    this.rpsComputerPick,
    this.diceRoll,
    this.coinFace,
    this.secretBidWinningBid,
    this.secretBidOpponentRows = const [],
  });

  final bool won;
  final bool tied;
  final int playerCount;
  final int winnerCount;
  final double stakeUsd;
  final double potUsd;
  final double commissionUsd;
  final double payoutUsd;
  final double netUsd;
  final String action;
  final String? rpsComputerPick;
  final int? diceRoll;
  final String? coinFace;
  final int? secretBidWinningBid;
  final List<_SecretBidRow> secretBidOpponentRows;

  String get summary => tied
      ? 'Demo tie'
      : won
      ? 'Demo win ${formatCurrency(netUsd)}'
      : 'Demo loss ${formatCurrency(stakeUsd)}';
}

class _DemoSecretBidOutcome {
  const _DemoSecretBidOutcome({
    required this.winningBid,
    required this.userWon,
    required this.winnerCount,
    required this.opponentRows,
  });

  final int winningBid;
  final bool userWon;
  final int winnerCount;
  final List<_SecretBidRow> opponentRows;
}

class _SecretBidRow {
  const _SecretBidRow({
    required this.displayName,
    required this.bid,
    required this.distance,
    required this.isWinner,
  });

  final String displayName;
  final int bid;
  final int distance;
  final bool isWinner;
}

class _RoundResultRow {
  const _RoundResultRow({
    required this.userId,
    required this.displayName,
    required this.choice,
    required this.status,
    required this.payoutUsd,
    this.distance,
  });

  final String userId;
  final String displayName;
  final String choice;
  final String status;
  final double payoutUsd;
  final int? distance;
}

enum _RoomStakeFilter { any, entry1to5, entry6to20, entry21Plus }
