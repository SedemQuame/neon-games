import 'dart:async';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';
import 'models.dart';

class PaymentService {
  PaymentService(this._client);

  final ApiClient _client;

  Future<MoMoDepositResponse> initiateMoMoDeposit({
    required String token,
    required String phone,
    required double amount,
    required String channel,
  }) async {
    final response = await _client.post(
      '/api/v1/payments/momo/deposit',
      token: token,
      body: {'phone': phone, 'amount': amount, 'channel': channel},
    );
    return MoMoDepositResponse.fromJson(
      (response as Map).cast<String, dynamic>(),
    );
  }

  Future<CryptoAddress> generateCryptoAddress({
    required String token,
    required String coin,
  }) async {
    final response = await _client.post(
      '/api/v1/payments/crypto/address',
      token: token,
      body: {'coin': coin},
    );
    return CryptoAddress.fromJson((response as Map).cast<String, dynamic>());
  }

  Stream<dynamic> paymentUpdates(String token) {
    final uri = Uri.parse('${_client.websocketBase}/ws/payments?token=$token');
    final channel = WebSocketChannel.connect(uri);
    return channel.stream;
  }
}
