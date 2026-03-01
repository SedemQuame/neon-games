import 'dart:async';

import 'package:http/http.dart' as http;
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
    String? proofImagePath,
  }) async {
    final fields = {
      'phone': phone,
      'amount': amount.toString(),
      'channel': channel,
    };

    dynamic response;
    if (proofImagePath != null && proofImagePath.isNotEmpty) {
      final file = await http.MultipartFile.fromPath(
        'proofUrl',
        proofImagePath,
      );
      response = await _client.multipartPost(
        '/api/v1/payments/momo/deposit',
        token: token,
        fields: fields,
        file: file,
      );
    } else {
      // Fallback or no image
      response = await _client.post(
        '/api/v1/payments/momo/deposit',
        token: token,
        body: {'phone': phone, 'amount': amount, 'channel': channel},
      );
    }

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

  Future<Map<String, dynamic>> checkCryptoDeposit({
    required String token,
    required String coin,
    required String address,
  }) async {
    final response = await _client.post(
      '/api/v1/payments/crypto/check',
      token: token,
      body: {'coin': coin, 'address': address},
    );
    return (response as Map).cast<String, dynamic>();
  }

  Stream<dynamic> paymentUpdates(String token) {
    final uri = Uri.parse('${_client.websocketBase}/ws/payments?token=$token');
    final channel = WebSocketChannel.connect(uri);
    return channel.stream;
  }

  Future<Map<String, dynamic>> initiateMoMoWithdrawal({
    required String token,
    required String phone,
    required double amount,
    required String channel,
  }) async {
    final response = await _client.post(
      '/api/v1/payments/momo/withdraw',
      token: token,
      body: {'phone': phone, 'amount': amount, 'channel': channel},
    );
    return (response as Map).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> initiateCryptoWithdrawal({
    required String token,
    required String coin,
    required String address,
    required double amount,
  }) async {
    final response = await _client.post(
      '/api/v1/payments/crypto/withdraw',
      token: token,
      body: {'coin': coin, 'address': address, 'amount': amount},
    );
    return (response as Map).cast<String, dynamic>();
  }
}
