import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'app_logger.dart';
import 'auth_service.dart';
import 'firebase_auth_service.dart';
import 'game_service.dart';
import 'models.dart';
import 'payment_service.dart';
import 'wallet_service.dart';

class SessionManager extends ChangeNotifier {
  SessionManager() : this._internal(ApiClient());

  SessionManager._internal(ApiClient client)
    : _client = client,
      _auth = AuthService(client),
      _wallet = WalletService(client),
      _payments = PaymentService(client),
      _game = GameService(client),
      _firebaseAuth = FirebaseAuthService(),
      _secureStorage = const FlutterSecureStorage() {
    _gameEventsSub = _game.events.listen(_handleGameEvent);
    unawaited(_bootstrap());
  }

  final ApiClient _client;
  final AuthService _auth;
  final WalletService _wallet;
  final PaymentService _payments;
  final GameService _game;
  final FirebaseAuthService _firebaseAuth;
  final FlutterSecureStorage _secureStorage;
  final StreamController<GameEvent> _gameEventsCtrl =
      StreamController<GameEvent>.broadcast();
  StreamSubscription<GameEvent>? _gameEventsSub;

  static const _sessionKey = 'gamehub.session';
  static const _rememberMeKey = 'gamehub.rememberMe';
  static const _legacyRememberedEmailKey = 'gamehub.rememberedEmail';

  AuthSession? _session;
  WalletBalance? _cachedBalance;
  bool _rememberMe = false;
  bool _initialized = false;
  Timer? _balancePoller;

  AuthSession? get session => _session;
  bool get isAuthenticated => _session != null;
  WalletBalance? get cachedBalance => _cachedBalance;
  bool get rememberMe => _rememberMe;
  bool get isReady => _initialized;

  ApiClient get client => _client;
  WalletService get walletService => _wallet;
  PaymentService get paymentService => _payments;
  GameService get gameService => _game;
  Stream<GameEvent> get gameEvents => _gameEventsCtrl.stream;

  Future<void> signInWithGoogle() async {
    final idToken = await _firebaseAuth.signInWithGoogle();
    final session = await _auth.loginWithFirebaseIdToken(idToken: idToken);
    await _openSession(session, suppressBalanceErrors: true);
  }

  Future<void> signInWithApple() async {
    final idToken = await _firebaseAuth.signInWithApple();
    final session = await _auth.loginWithFirebaseIdToken(idToken: idToken);
    await _openSession(session, suppressBalanceErrors: true);
  }

  Future<void> signInWithX() async {
    final idToken = await _firebaseAuth.signInWithX();
    final session = await _auth.loginWithFirebaseIdToken(idToken: idToken);
    await _openSession(session, suppressBalanceErrors: true);
  }

  Future<void> startGuestMode() async {
    final idToken = await _firebaseAuth.signInAnonymously();
    final session = await _auth.loginWithFirebaseIdToken(idToken: idToken);
    await _openSession(session, suppressBalanceErrors: true);
  }

  Future<WalletBalance> refreshBalance() async {
    final token = _session?.accessToken;
    if (token == null || token.isEmpty) {
      throw ApiException(message: 'Not authenticated', statusCode: 401);
    }
    try {
      _cachedBalance = await _wallet.fetchBalance(token);
    } on ApiException catch (error) {
      final refreshed = error.statusCode == 401 && await _tryRefreshSession();
      if (refreshed && _session?.accessToken.isNotEmpty == true) {
        _cachedBalance = await _wallet.fetchBalance(_session!.accessToken);
      } else {
        rethrow;
      }
    }
    notifyListeners();
    return _cachedBalance!;
  }

  Future<void> logout() async {
    final refreshToken = _session?.refreshToken ?? '';
    if (refreshToken.isNotEmpty) {
      try {
        await _auth.logout(refreshToken: refreshToken);
      } catch (_) {
        // Ignore backend logout errors; local sign-out should still succeed.
      }
    }
    _session = null;
    _cachedBalance = null;
    await _game.disconnect();
    try {
      await _firebaseAuth.signOut();
    } catch (_) {
      // Ignore Firebase provider sign-out errors if session is already cleared.
    }
    await _secureStorage.delete(key: _sessionKey);
    _balancePoller?.cancel();
    _balancePoller = null;
    notifyListeners();
  }

  Future<void> ensureGameSocket() async {
    if (_session == null) return;
    await _tryRefreshSession();
    final token = _session?.accessToken;
    if (token == null || token.isEmpty) {
      return;
    }
    await _game.connect(token);
  }

  Future<void> _openSession(
    AuthSession session, {
    required bool suppressBalanceErrors,
  }) async {
    _session = session;
    await _persistSessionIfNeeded();
    await _game.connect(_session!.accessToken);
    if (suppressBalanceErrors) {
      try {
        await refreshBalance();
      } catch (_) {
        // Ignore balance refresh errors during sign-in.
      }
    } else {
      await refreshBalance();
    }
    _startBalancePolling();
    notifyListeners();
  }

  @override
  void dispose() {
    _gameEventsSub?.cancel();
    _gameEventsCtrl.close();
    unawaited(_game.disconnect());
    super.dispose();
  }

  void _handleGameEvent(GameEvent event) {
    if (event is GameResultEvent) {
      _applyGameBalance(event.newBalance);
      AppLogger.instance.log(
        'game',
        'Result ${event.gameType} ${event.outcome} '
            'stake=\$${event.stakeUsd.toStringAsFixed(2)} '
            'win=\$${event.winAmountUsd.toStringAsFixed(2)} '
            'payout=\$${event.payoutUsd.toStringAsFixed(2)} '
            'contract=${event.derivContractId ?? 'N/A'}',
      );
    } else if (event is GameBetAccepted) {
      _applyGameBalance(event.newBalance);
      AppLogger.instance.log(
        'game',
        'Bet accepted session=${event.sessionId} '
            'stake=\$${event.stakeUsd.toStringAsFixed(2)} '
            'newBalance=\$${event.newBalance.toStringAsFixed(2)}',
      );
    } else if (event is GameBetRejected) {
      AppLogger.instance.log(
        'game',
        'Bet rejected: ${event.reason}',
        level: LogLevel.warning,
      );
    }
    _gameEventsCtrl.add(event);
  }

  void _applyGameBalance(double newBalance) {
    if (newBalance <= 0 && _cachedBalance == null) {
      return;
    }
    final current = _cachedBalance;
    _cachedBalance = WalletBalance(
      availableUsd: newBalance,
      reservedUsd: current?.reservedUsd ?? 0,
      updatedAt: DateTime.now(),
    );
    notifyListeners();
  }

  Future<void> setRememberMe(bool value) async {
    if (_rememberMe == value) return;
    _rememberMe = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberMeKey, value);
    if (!value) {
      await _secureStorage.delete(key: _sessionKey);
      await prefs.remove(_legacyRememberedEmailKey);
    } else {
      await _persistSessionIfNeeded();
    }
    notifyListeners();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    _rememberMe = prefs.getBool(_rememberMeKey) ?? false;
    if (_rememberMe) {
      await _restoreSession();
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> _restoreSession() async {
    final raw = await _secureStorage.read(key: _sessionKey);
    if (raw == null || raw.isEmpty) {
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _session = AuthSession.fromJson(decoded.cast<String, dynamic>());
      await _tryRefreshSession();
      if (_session == null) {
        return;
      }
      await _game.connect(_session!.accessToken);
      try {
        await refreshBalance();
      } catch (_) {
        // Ignore balance failures during bootstrap.
      }
      _startBalancePolling();
    } catch (_) {
      await _secureStorage.delete(key: _sessionKey);
    }
  }

  Future<void> _persistSessionIfNeeded() async {
    if (!_rememberMe || _session == null) {
      await _secureStorage.delete(key: _sessionKey);
      return;
    }
    final payload = jsonEncode({
      'accessToken': _session!.accessToken,
      'refreshToken': _session!.refreshToken,
      'user': _session!.user,
    });
    await _secureStorage.write(key: _sessionKey, value: payload);
  }

  Future<bool> _tryRefreshSession() async {
    final current = _session;
    if (current == null) return false;
    final refreshToken = current.refreshToken;
    if (refreshToken.isEmpty) return false;
    try {
      final tokens = await _auth.refreshTokens(refreshToken: refreshToken);
      _session = AuthSession(
        accessToken: tokens.accessToken,
        refreshToken: tokens.refreshToken,
        user: current.user,
      );
      await _persistSessionIfNeeded();
      return true;
    } on ApiException catch (error) {
      if (error.statusCode == 401) {
        await logout();
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  void _startBalancePolling() {
    _balancePoller?.cancel();
    if (!isAuthenticated) {
      return;
    }
    _balancePoller = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!isAuthenticated) {
        return;
      }
      unawaited(_refreshBalanceSilently());
    });
  }

  Future<void> _refreshBalanceSilently() async {
    try {
      await refreshBalance();
    } catch (_) {
      // Ignore background errors; explicit refresh will surface issues.
    }
  }
}
