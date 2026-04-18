import 'api_client.dart';
import 'models.dart';

class AuthService {
  AuthService(this._client);

  final ApiClient _client;

  Future<AuthSession> loginWithFirebaseIdToken({
    required String idToken,
  }) async {
    final response = await _client.post(
      '/api/v1/auth/firebase/login',
      body: {'idToken': idToken},
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

  Future<void> logout({String? refreshToken}) async {
    await _client.post(
      '/api/v1/auth/logout',
      body: {
        if (refreshToken != null && refreshToken.isNotEmpty)
          'refreshToken': refreshToken,
      },
    );
  }
}

class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;
}
