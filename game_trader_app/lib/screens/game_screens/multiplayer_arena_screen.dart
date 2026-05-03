import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_theme.dart';
import '../../services/game_service.dart';
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
  late MultiplayerGameDefinition _selected;

  RoomStateSnapshot? _room;
  RoomRoundStartedPayload? _round;
  RoomRoundResultPayload? _lastResult;
  final List<RoomSummary> _publicRooms = [];
  final List<RoomInviteEvent> _pendingInvites = [];

  bool _loadingPublicRooms = false;
  bool _creatingRoom = false;
  bool _demoResolving = false;
  bool _isRoomPublic = true;
  bool _handledInitialJoin = false;
  bool _resultDialogOpen = false;
  _RoomStakeFilter _roomStakeFilter = _RoomStakeFilter.any;
  PlayMode _playMode = PlayMode.demo;
  int _minPlayers = 2;
  int _maxPlayers = 4;
  double _stakeUsd = 1;

  String _status = 'Join or create a room.';
  String _demoStatus = 'Demo room ready.';
  String? _submittedRoundId;
  _DemoRoomResult? _demoResult;

  String _rpsPick = 'ROCK';
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

  bool get _hasSubmittedAction =>
      (_playMode.isDemo && _demoResolving) ||
      (_round != null && _submittedRoundId == _round!.roundId);

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
      _session.gameService.joinRoom(initialRoomCode);
      if (mounted) {
        setState(() {
          _status = 'Opening room $initialRoomCode...';
        });
      }
    }
  }

  void _handleGameEvent(GameEvent event) {
    if (!mounted) return;

    if (event is RoomCreatedEvent) {
      _createRoomFallback?.cancel();
      _adoptRoom(event.room);
      setState(() {
        _creatingRoom = false;
        _status = 'Room ${event.room.roomCode} created.';
      });
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
    if (event is RoomRoundStartedEvent) {
      if (_room != null && _room!.roomCode != event.payload.roomCode) return;
      setState(() {
        _round = event.payload;
        _lastResult = null;
        _submittedRoundId = null;
        _status = event.payload.requiresAction
            ? 'Pot locked. Submit.'
            : 'Pot locked. Resolving.';
      });
      return;
    }
    if (event is RoomRoundResultEvent) {
      if (_room != null && _room!.roomCode != event.payload.roomCode) return;
      setState(() {
        _round = null;
        _submittedRoundId = null;
        _lastResult = event.payload;
        _status = event.payload.summary;
      });
      unawaited(_session.refreshBalance());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showRoundOutcomeDialog(event.payload);
        }
      });
      return;
    }
    if (event is RoomKickedEvent) {
      setState(() {
        _room = null;
        _round = null;
        _lastResult = null;
        _submittedRoundId = null;
        _status = event.message;
      });
      _refreshPublicRooms();
      showGameMessage(context, event.message);
      return;
    }
    if (event is RoomInfoEvent) {
      if (event.code == 'LEFT_ROOM') {
        setState(() {
          _room = null;
          _round = null;
          _lastResult = null;
          _submittedRoundId = null;
          _status = 'You left the room.';
        });
        _refreshPublicRooms();
      } else if (event.code == 'INVITE_SENT') {
        showGameMessage(context, 'Invite sent.');
      } else if (event.code == 'PLAYER_KICKED') {
        showGameMessage(context, 'Player removed from room.');
      }
      return;
    }
    if (event is RoomErrorEvent) {
      _createRoomFallback?.cancel();
      setState(() {
        _creatingRoom = false;
        _loadingPublicRooms = false;
        _status = event.message;
      });
      showGameMessage(context, event.message);
    }
  }

  void _adoptRoom(RoomStateSnapshot room) {
    final selectedDef = multiplayerGameForKey(room.gameKey) ?? _selected;
    setState(() {
      _room = room;
      _selected = selectedDef;
      if (_stakeUsd < _selected.minStake) {
        _stakeUsd = _selected.minStake;
      }
    });
  }

  String _initialStatus() {
    return 'Join or create ${_selected.title}.';
  }

  bool _sameGameKey(String left, String right) {
    return left.trim().toUpperCase() == right.trim().toUpperCase();
  }

  void _setPlayMode(PlayMode mode) {
    if (_playMode == mode || _room != null) return;
    setState(() {
      _playMode = mode;
      _demoResolving = false;
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
    final stake = _stakeUsd < _selected.minStake
        ? _selected.minStake
        : _stakeUsd;
    setState(() {
      _stakeUsd = stake;
      _demoResolving = true;
      _demoResult = null;
      _demoStatus = 'Demo pot locked.';
    });

    await Future<void>.delayed(const Duration(milliseconds: 950));
    if (!mounted || !_demoResolving) return;

    final rng = math.Random();
    final playerCount =
        _minPlayers + rng.nextInt(_maxPlayers - _minPlayers + 1);
    final pot = _roundMoney(stake * playerCount);
    final commission = _roundMoney(pot * 0.15);
    final distributable = _roundMoney(pot - commission);
    final won = _demoWinForGame(rng);
    final winnerCount = won ? 1 : 1 + rng.nextInt(math.max(1, playerCount - 1));
    final payout = won ? _roundMoney(distributable / winnerCount) : 0.0;
    final net = _roundMoney(payout - stake);
    final result = _DemoRoomResult(
      won: won,
      playerCount: playerCount,
      winnerCount: winnerCount,
      stakeUsd: stake,
      potUsd: pot,
      commissionUsd: commission,
      payoutUsd: payout,
      netUsd: net,
      action: _demoActionLabel(),
    );

    setState(() {
      _demoResolving = false;
      _demoResult = result;
      _demoStatus = won
          ? 'Demo win ${formatCurrency(net)}.'
          : 'Demo loss. Wallet unchanged.';
    });
    showGameMessage(
      context,
      won
          ? 'Demo win: ${formatCurrency(payout)} payout shown.'
          : 'Demo round settled. Wallet unchanged.',
    );
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

  String _demoActionLabel() {
    switch (_selected.key) {
      case 'RPS_CLASH':
        return _rpsPick;
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

  void _createRoom() {
    if (_creatingRoom || _room != null) return;
    setState(() {
      _creatingRoom = true;
      _status = 'Creating room...';
    });
    _createRoomFallback?.cancel();
    _createRoomFallback = Timer(const Duration(seconds: 8), () {
      if (!mounted || !_creatingRoom) return;
      setState(() {
        _creatingRoom = false;
        _status = 'Room was not created. Try again.';
      });
    });
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
    _session.gameService.joinRoom(code);
    setState(() => _status = 'Joining room $code...');
  }

  void _joinPublicRoom(String code) {
    _session.gameService.joinRoom(code);
    setState(() => _status = 'Joining room $code...');
  }

  void _leaveRoom() {
    _session.gameService.leaveRoom();
    setState(() => _status = 'Leaving room...');
  }

  void _setReady(bool ready) {
    _session.gameService.setRoomReady(ready);
    setState(
      () => _status = ready
          ? 'Ready on. Waiting for host start.'
          : 'Ready removed.',
    );
  }

  void _startRound() {
    _session.gameService.startRoomRound();
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
    final userId = _inviteUserController.text.trim();
    if (userId.isEmpty) {
      showGameMessage(context, 'Enter a user ID to invite.');
      return;
    }
    _session.gameService.inviteToRoom(userId);
  }

  void _acceptInvite(RoomInviteEvent invite) {
    _session.gameService.joinRoom(invite.room.roomCode);
    setState(() {
      _pendingInvites.remove(invite);
      _selected = multiplayerGameForKey(invite.room.gameKey) ?? _selected;
      _status = 'Joining ${invite.room.roomCode}...';
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

  void _showInstructions(MultiplayerGameDefinition game) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.gameSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: AppTheme.gameBorder),
          ),
          title: Text(
            '${game.title} • How To Play',
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  game.modeSummary,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 12),
                ...game.instructions.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: const BoxDecoration(
                            color: AppTheme.goldButtonBottom,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            line,
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.gameBackground,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.gameBorder),
                  ),
                  child: const Text(
                    'Ready players enter the pot. Winners split 85%.',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
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
    final choices = _resultChoicesFor(result);

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppTheme.gameSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(
              color: won ? AppTheme.success : AppTheme.gameBorder,
            ),
          ),
          title: Text(
            won ? 'Round Won' : 'Round Lost',
            style: TextStyle(
              color: won ? AppTheme.success : AppTheme.textPrimary,
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
                if (_isSpinBottleResult(result)) ...[
                  const SizedBox(height: 10),
                  _buildSpinBottleOutcome(result, compact: true),
                ],
                if (choices.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildPlayerChoicesPanel(
                    choices,
                    title: 'Player Choices',
                    compact: true,
                  ),
                ],
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
    final readyCount = room.players.where((player) => player.ready).length;
    return readyCount >= room.minPlayers && readyCount >= 2;
  }

  int _readyCount(RoomStateSnapshot room) =>
      room.players.where((player) => player.ready).length;

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
                  const SizedBox(height: 12),
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
    return Scaffold(
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
        _buildPlayModeHeader(),
        const SizedBox(height: 12),
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
        _buildPlayModeHeader(),
        const SizedBox(height: 12),
        _buildGameSwitcherRow(),
        const SizedBox(height: 12),
        _buildDemoRoomCard(),
      ],
    );
  }

  Widget _buildPlayModeHeader() {
    return PlayModeToggle(
      value: _playMode,
      enabled: _room == null && !_creatingRoom && !_demoResolving,
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
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 2.35,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(_selected.imagePath, fit: BoxFit.cover),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.84),
                          Colors.black.withValues(alpha: 0.16),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _LiveBadge(text: 'DEMO ROOM'),
                        const SizedBox(height: 8),
                        Text(
                          _selected.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
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
          const SizedBox(height: 10),
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
          if (_selected.requiresAction) ...[
            const SizedBox(height: 12),
            _buildActionInputForGame(),
          ],
          const SizedBox(height: 12),
          PrimaryButton(
            expanded: true,
            label: _demoResolving ? 'Resolving...' : 'Play Demo',
            icon: Icons.play_arrow_rounded,
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
              'Move ${result.action} • Payout ${formatCurrency(result.payoutUsd)}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoomLobbyView() {
    final room = _room!;
    return ListView(
      key: ValueKey(
        'room-${room.roomCode}-${_round?.roundId ?? _lastResult?.roundId ?? 'waiting'}',
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      children: [
        _buildRoomStageCard(),
        const SizedBox(height: 12),
        _buildRoomCodeCard(),
        if (_showStatusNotice) ...[
          const SizedBox(height: 12),
          _buildStatusNotice(),
        ],
        if (!room.inRound && room.players.length < room.maxPlayers) ...[
          const SizedBox(height: 12),
          _buildInviteActionCard(),
        ],
        const SizedBox(height: 12),
        _buildPlayersCard(),
        const SizedBox(height: 12),
        _buildRoomEconomyCard(),
        if (_round != null) ...[const SizedBox(height: 12), _buildRoundCard()],
        if (_lastResult != null) ...[
          const SizedBox(height: 12),
          _buildResultCard(),
        ],
        if (_round == null) ...[
          const SizedBox(height: 12),
          _buildLobbyFooterCard(),
        ],
      ],
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
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 2.55,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.asset(_selected.imagePath, fit: BoxFit.cover),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.82),
                          Colors.black.withValues(alpha: 0.12),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 12,
                    left: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.goldButtonTop,
                            AppTheme.goldButtonBottom,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.goldButtonBottom),
                      ),
                      child: Text(
                        _selected.cardTag,
                        style: const TextStyle(
                          color: AppTheme.goldText,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          letterSpacing: 0,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 12,
                    child: _MiniGoldButton(
                      label: 'Rules',
                      icon: Icons.info_outline,
                      onTap: () => _showInstructions(_selected),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selected.title,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _selected.modeSummary,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
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

  Widget _buildRoomCodeCard() {
    final room = _room!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Column(
        children: [
          const Text(
            'ROOM CODE',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.gameBackground,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.gameBorder),
            ),
            child: Text(
              room.roomCode,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w900,
                fontSize: 28,
                letterSpacing: 5,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${formatCurrency(room.stakeUsd)} • ${room.players.length}/${room.maxPlayers} seats',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  expanded: true,
                  label: 'COPY CODE',
                  onPressed: _copyRoomCode,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(
                  expanded: true,
                  label: 'SHARE LINK',
                  onPressed: _copyRoomLink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInviteActionCard() {
    final room = _room!;
    final seatsLeft = room.maxPlayers - room.players.length;
    return PressScale(
      enabled: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _openInviteSheet,
          borderRadius: BorderRadius.circular(16),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.gameSurface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.gameBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.goldButtonTop,
                        AppTheme.goldButtonBottom,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppTheme.goldButtonBottom),
                  ),
                  child: const Icon(
                    Icons.group_add_rounded,
                    color: AppTheme.goldText,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
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
                      const SizedBox(height: 4),
                      Text(
                        '$seatsLeft seat${seatsLeft == 1 ? '' : 's'} left.',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppTheme.textPrimary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRoomEconomyCard() {
    final room = _room!;
    final readyCount = _readyCount(room);
    final stake = _round?.stakeUsd ?? room.stakeUsd;
    final participantCount = _round?.playerCount ?? readyCount;
    final pot =
        _round?.potUsd ?? _roundMoney(stake * participantCount.toDouble());
    final commission = _round?.commissionUsd ?? _roundMoney(pot * 0.15);
    final distributable =
        _round?.distributableUsd ?? _roundMoney(pot - commission);
    final title = _round != null ? 'Pot Locked' : 'Pot Preview';
    final helper = _round != null
        ? 'Funds are in the pot.'
        : 'Entry moves on start.';

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
      ),
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
          ...room.players.map((player) {
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
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
          }),
        ],
      ),
    );
  }

  Widget _buildRoundCard() {
    final round = _round!;
    final progress = round.playerCount > 0
        ? round.actionCount / round.playerCount
        : 0.0;
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
          const SizedBox(height: 10),
          if (round.choices.isNotEmpty) ...[
            _buildPlayerChoicesPanel(round.choices),
            const SizedBox(height: 10),
          ],
          if (round.requiresAction)
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
            const _ActionHint(text: 'Pick your move.'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildIconChoiceChip(
                    icon: '🪨',
                    label: 'ROCK',
                    selected: _rpsPick,
                    onSelect: (v) => _rpsPick = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildIconChoiceChip(
                    icon: '📄',
                    label: 'PAPER',
                    selected: _rpsPick,
                    onSelect: (v) => _rpsPick = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildIconChoiceChip(
                    icon: '✂️',
                    label: 'SCISSORS',
                    selected: _rpsPick,
                    onSelect: (v) => _rpsPick = v,
                  ),
                ),
              ],
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ActionHint(text: 'Pick a side.'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildIconChoiceChip(
                    icon: '🌕',
                    label: 'HEADS',
                    selected: _coinSide,
                    onSelect: (v) => _coinSide = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildIconChoiceChip(
                    icon: '🌑',
                    label: 'TAILS',
                    selected: _coinSide,
                    onSelect: (v) => _coinSide = v,
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
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ActionHint(text: 'Bid 1-100.'),
            const SizedBox(height: 10),
            Center(
              child: Text(
                '$_secretBid',
                style: const TextStyle(
                  color: AppTheme.goldButtonBottom,
                  fontWeight: FontWeight.w900,
                  fontSize: 42,
                ),
              ),
            ),
            Slider(
              value: _secretBid.toDouble(),
              min: 1,
              max: 100,
              divisions: 99,
              label: '$_secretBid',
              activeColor: AppTheme.goldButtonBottom,
              inactiveColor: AppTheme.gameBorder,
              onChanged: _hasSubmittedAction
                  ? null
                  : (v) => setState(() => _secretBid = v.round()),
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
      case 'SPIN_BOTTLE':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _ActionHint(text: 'Pick a side.'),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildIconChoiceChip(
                    icon: '⬅️',
                    label: 'LEFT',
                    selected: _spinBottleSide,
                    onSelect: (v) => _spinBottleSide = v,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildIconChoiceChip(
                    icon: '➡️',
                    label: 'RIGHT',
                    selected: _spinBottleSide,
                    onSelect: (v) => _spinBottleSide = v,
                  ),
                ),
              ],
            ),
          ],
        );
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
    final details = _formatDetail(result.detail);
    final choices = _resultChoicesFor(result);
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

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: didWin
              ? AppTheme.success.withValues(alpha: 0.6)
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
                  : AppTheme.gameBackground,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  didWin
                      ? Icons.emoji_events_rounded
                      : Icons.sentiment_dissatisfied_rounded,
                  color: didWin ? AppTheme.success : AppTheme.textSecondary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        didWin ? 'You Won!' : 'Better luck next time',
                        style: TextStyle(
                          color: didWin
                              ? AppTheme.success
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
                if (_isSpinBottleResult(result)) ...[
                  const SizedBox(height: 10),
                  _buildSpinBottleOutcome(result),
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
                if (choices.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildPlayerChoicesPanel(choices, title: 'Player Choices'),
                ],
                if (result.winners.isNotEmpty &&
                    !_isSpinBottleResult(result)) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'WINNERS',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...result.winners.map(
                    (winner) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.person_rounded,
                            size: 14,
                            color: winner.userId == _myUserId
                                ? AppTheme.success
                                : AppTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              winner.displayName,
                              style: TextStyle(
                                color: winner.userId == _myUserId
                                    ? AppTheme.success
                                    : AppTheme.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Text(
                            formatCurrency(winner.payoutUsd),
                            style: TextStyle(
                              color: winner.userId == _myUserId
                                  ? AppTheme.success
                                  : AppTheme.textPrimary,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
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
    final isReady = me?.ready == true;
    final canStart = _canStartRound();

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
                _isHost ? 'Host Controls' : 'Your Controls',
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
            _isHost
                ? canStart
                      ? 'Ready to start.'
                      : 'Ready up to start.'
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
          Row(
            children: [
              Expanded(
                child: PrimaryButton(
                  expanded: true,
                  label: isReady ? 'UNREADY' : 'READY',
                  onPressed: me == null ? null : () => _setReady(!isReady),
                ),
              ),
              if (_isHost) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: PrimaryButton(
                    expanded: true,
                    label: 'START ROUND',
                    onPressed: canStart ? _startRound : null,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            expanded: true,
            label: 'LEAVE ROOM',
            onPressed: _leaveRoom,
          ),
        ],
      ),
    );
  }

  bool _isSpinBottleResult(RoomRoundResultPayload result) {
    return result.gameKey.trim().toUpperCase() == 'SPIN_BOTTLE';
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
      'DICE_DUEL' => 'rolls',
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
        return 'Roll $text';
      case 'TARGET_STRIKE':
        return 'Number $text';
      case 'HIGH_CARD':
        return 'Card $text';
      case 'PARITY_CLASH':
        return 'Digit $text';
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
    final suffix = userId.length > 6
        ? userId.substring(userId.length - 6)
        : userId;
    return suffix.isEmpty ? 'Player' : 'P-${suffix.toUpperCase()}';
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

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.goldButtonBottom,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.goldText,
          fontWeight: FontWeight.w900,
          fontSize: 10,
        ),
      ),
    );
  }
}

class _DemoRoomResult {
  const _DemoRoomResult({
    required this.won,
    required this.playerCount,
    required this.winnerCount,
    required this.stakeUsd,
    required this.potUsd,
    required this.commissionUsd,
    required this.payoutUsd,
    required this.netUsd,
    required this.action,
  });

  final bool won;
  final int playerCount;
  final int winnerCount;
  final double stakeUsd;
  final double potUsd;
  final double commissionUsd;
  final double payoutUsd;
  final double netUsd;
  final String action;

  String get summary => won
      ? 'Demo win ${formatCurrency(netUsd)}'
      : 'Demo loss ${formatCurrency(stakeUsd)}';
}

enum _RoomStakeFilter { any, entry1to5, entry6to20, entry21Plus }
