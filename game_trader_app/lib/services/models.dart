class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final Map<String, dynamic> user;

  String get userId => user['id']?.toString() ?? '';
  String get username => user['username']?.toString() ?? 'Pilot';

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    return AuthSession(
      accessToken: json['accessToken'] as String? ?? '',
      refreshToken: json['refreshToken'] as String? ?? '',
      user: (json['user'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }
}

class WalletBalance {
  const WalletBalance({
    required this.availableUsd,
    required this.reservedUsd,
    required this.updatedAt,
  });

  final double availableUsd;
  final double reservedUsd;
  final DateTime? updatedAt;

  factory WalletBalance.fromJson(Map<String, dynamic> json) {
    return WalletBalance(
      availableUsd: (json['availableUsd'] as num?)?.toDouble() ?? 0,
      reservedUsd: (json['reservedUsd'] as num?)?.toDouble() ?? 0,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'].toString())
          : null,
    );
  }
}

class LedgerEntry {
  const LedgerEntry({
    required this.type,
    required this.amountUsd,
    required this.reference,
    required this.createdAt,
  });

  final String type;
  final double amountUsd;
  final String reference;
  final DateTime? createdAt;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      type: json['type']?.toString() ?? 'LEDGER',
      amountUsd: (json['amountUsd'] as num?)?.toDouble() ?? 0,
      reference: json['reference']?.toString() ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }
}

class MoMoDepositResponse {
  const MoMoDepositResponse({
    required this.reference,
    required this.message,
    required this.status,
  });

  final String reference;
  final String message;
  final String status;

  factory MoMoDepositResponse.fromJson(Map<String, dynamic> json) {
    return MoMoDepositResponse(
      reference: json['reference']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      status: json['status']?.toString() ?? 'PENDING',
    );
  }
}

class CryptoAddress {
  const CryptoAddress({
    required this.coin,
    required this.address,
    required this.network,
  });

  final String coin;
  final String address;
  final String network;

  factory CryptoAddress.fromJson(Map<String, dynamic> json) {
    return CryptoAddress(
      coin: json['coin']?.toString() ?? 'USDT',
      address: json['address']?.toString() ?? '',
      network: json['network']?.toString() ?? '',
    );
  }
}
