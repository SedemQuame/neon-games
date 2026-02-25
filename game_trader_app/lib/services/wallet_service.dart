import 'api_client.dart';
import 'models.dart';

class WalletService {
  WalletService(this._client);

  final ApiClient _client;

  Future<WalletBalance> fetchBalance(String token) async {
    final response = await _client.get('/api/v1/wallet/balance', token: token);
    return WalletBalance.fromJson((response as Map).cast<String, dynamic>());
  }

  Future<List<LedgerEntry>> fetchLedger(String token, {int limit = 25}) async {
    final response = await _client.get(
      '/api/v1/wallet/ledger',
      token: token,
      query: {'limit': limit},
    );
    final entries = (response as Map)['entries'] as List? ?? const [];
    return entries
        .cast<Map>()
        .map((item) => LedgerEntry.fromJson(item.cast<String, dynamic>()))
        .toList();
  }
}
