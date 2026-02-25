import 'api_client.dart';
import 'models.dart';

class AuthService {
  AuthService(this._client);

  final ApiClient _client;

  Future<AuthSession> register({
    required String email,
    required String username,
    required String password,
  }) async {
    final response = await _client.post(
      '/api/v1/auth/email/register',
      body: {'email': email, 'username': username, 'password': password},
    );
    return AuthSession.fromJson((response as Map).cast<String, dynamic>());
  }

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final response = await _client.post(
      '/api/v1/auth/email/login',
      body: {'email': email, 'password': password},
    );
    return AuthSession.fromJson((response as Map).cast<String, dynamic>());
  }

  Future<TokenPair> refreshTokens({required String refreshToken}) async {
    final response = await _client.post(
      '/api/v1/auth/refresh',
      body: {'refreshToken': refreshToken},
    );
    final data = (response as Map).cast<String, dynamic>();
    return TokenPair(
      accessToken: data['accessToken']?.toString() ?? '',
      refreshToken: data['refreshToken']?.toString() ?? '',
    );
  }

  Future<void> requestPasswordReset({required String email}) async {
    await _client.post(
      '/api/v1/auth/email/forgot',
      body: {'email': email},
    );
  }

  Future<void> resetPassword({
    required String token,
    required String password,
  }) async {
    await _client.post(
      '/api/v1/auth/email/reset',
      body: {'token': token, 'password': password},
    );
  }
}

class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;
}
