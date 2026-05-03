import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app_theme.dart';
import '../services/api_client.dart';
import '../services/models.dart';
import '../services/session_manager.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_shell.dart';
import '../widgets/casino_top_nav.dart';
import '../widgets/section_header.dart';
import '../widgets/tag_badge.dart';

class CryptoDepositScreen extends StatefulWidget {
  const CryptoDepositScreen({super.key});

  @override
  State<CryptoDepositScreen> createState() => _CryptoDepositScreenState();
}

class _CryptoDepositScreenState extends State<CryptoDepositScreen> {
  String _selectedCoin = 'BTC';
  bool _loading = false;
  bool _checkingPayment = false;
  String? _error;
  CryptoAddress? _address;

  final Map<String, Map<String, dynamic>> _coins = {
    'BTC': {
      'name': 'Bitcoin (BTC)',
      'icon': Icons.currency_bitcoin,
      'color': Colors.orange,
      'network': 'Bitcoin Network',
    },
    'ETH': {
      'name': 'Ethereum (ETH)',
      'icon': Icons.diamond,
      'color': Colors.blueAccent,
      'network': 'ERC20 Network',
    },
    'USDT': {
      'name': 'Tether (USDT)',
      'icon': Icons.attach_money,
      'color': Colors.green,
      'network': 'TRC20 Network',
    },
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _generateAddress());
  }

  Future<void> _generateAddress() async {
    final session = context.read<SessionManager>();
    final token = session.session?.accessToken;
    if (token == null) {
      setState(() => _error = 'Sign in required.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _address = null;
    });

    try {
      final address = await session.paymentService.generateCryptoAddress(
        token: token,
        coin: _selectedCoin,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _address = address;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Address failed.';
        _loading = false;
      });
    }
  }

  Future<void> _checkPayment() async {
    if (_address == null || _checkingPayment) {
      return;
    }

    final session = context.read<SessionManager>();
    final token = session.session?.accessToken;
    if (token == null) {
      return;
    }

    setState(() => _checkingPayment = true);

    int totalElapsedSeconds = 0;
    const maxPollingSeconds = 270;
    const delaySeconds = 10;
    var found = false;

    try {
      while (totalElapsedSeconds < maxPollingSeconds &&
          mounted &&
          _checkingPayment) {
        final response = await session.paymentService.checkCryptoDeposit(
          token: token,
          coin: _selectedCoin,
          address: _address!.address,
        );

        if (!mounted) {
          break;
        }

        final status = response['status'] as String?;
        if (status == 'CONFIRMED' || status == 'PENDING') {
          found = true;
          break;
        }

        await Future.delayed(const Duration(seconds: delaySeconds));
        totalElapsedSeconds += delaySeconds;
      }

      if (!mounted) {
        return;
      }

      if (found) {
        _showSuccessDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('No transaction found yet.'),
            backgroundColor: context.colors.warning,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Check failed.')));
      }
    } finally {
      if (mounted) {
        setState(() => _checkingPayment = false);
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(context.radii.xl),
          ),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: context.colors.success),
              SizedBox(width: context.space.xs),
              const Text('Deposit Detected!'),
            ],
          ),
          content: Text(
            'Transaction found. Balance updates after confirmation.',
            style: context.type.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          actions: [
            PrimaryButton(
              label: 'Dashboard',
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final coinData = _coins[_selectedCoin]!;
    final displayAddress = _address?.address ?? '';

    return CasinoScaffold(
      appBar: const CasinoTopNav(title: 'Crypto', showBackButton: true),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: context.space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Crypto'),
            SizedBox(height: context.space.lg),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Coin',
                    style: context.type.label.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: context.space.xs),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedCoin,
                    items: _coins.keys.map((key) {
                      final data = _coins[key]!;
                      return DropdownMenuItem<String>(
                        value: key,
                        child: Row(
                          children: [
                            Icon(
                              data['icon'] as IconData,
                              color: data['color'] as Color,
                            ),
                            SizedBox(width: context.space.sm),
                            Text(data['name'] as String),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      if (newValue != null && newValue != _selectedCoin) {
                        setState(() => _selectedCoin = newValue);
                        _generateAddress();
                      }
                    },
                  ),
                  SizedBox(height: context.space.md),
                  Text(
                    'Network',
                    style: context.type.label.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: context.space.xs),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.space.md,
                      vertical: context.space.sm,
                    ),
                    decoration: BoxDecoration(
                      color: context.colors.bgSurface,
                      borderRadius: BorderRadius.circular(context.radii.lg),
                      border: Border.all(color: context.colors.border),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.hub, color: Colors.blueAccent),
                        SizedBox(width: context.space.sm),
                        Expanded(
                          child: Text(
                            _address?.network ?? coinData['network'] as String,
                            style: context.type.bodyStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: context.space.md),
            SurfaceCard(
              child: Column(
                children: [
                  Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(context.radii.lg),
                      border: Border.all(color: context.colors.border),
                    ),
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                        ? Center(
                            child: Icon(
                              Icons.error_outline,
                              size: 40,
                              color: context.colors.danger,
                            ),
                          )
                        : QrImageView(
                            data: _address?.address ?? '',
                            version: QrVersions.auto,
                            size: 180,
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black87,
                            ),
                          ),
                  ),
                  if (_error != null) ...[
                    SizedBox(height: context.space.sm),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: context.type.body.copyWith(
                        color: context.colors.danger,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _generateAddress,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: context.space.md),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Address',
                    style: context.type.label.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: context.space.xs),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: SelectableText(
                          displayAddress.isEmpty
                              ? 'Generating...'
                              : displayAddress,
                          style: context.type.bodyStrong.copyWith(
                            fontFamily: 'monospace',
                            color: displayAddress.isEmpty
                                ? context.colors.textSecondary
                                : context.colors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy address',
                        onPressed: displayAddress.isEmpty
                            ? null
                            : () {
                                Clipboard.setData(
                                  ClipboardData(text: displayAddress),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Address copied')),
                                );
                              },
                        icon: Icon(
                          Icons.copy_rounded,
                          color: context.colors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: context.space.lg),
            if (_address != null && !_loading && _error == null)
              PrimaryButton(
                label: _checkingPayment ? 'Checking...' : 'Confirm',
                onPressed: _checkingPayment ? null : _checkPayment,
                icon: Icons.check_circle_outline,
                expanded: true,
              ),
            if (_address != null && !_loading && _error == null)
              SizedBox(height: context.space.md),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        color: coinData['color'] as Color,
                        size: 20,
                      ),
                      SizedBox(width: context.space.xs),
                      Text('Important', style: context.type.bodyStrong),
                      SizedBox(width: context.space.xs),
                      const TagBadge(label: 'Read'),
                    ],
                  ),
                  SizedBox(height: context.space.sm),
                  _buildInfoRow('Send only $_selectedCoin.'),
                  _buildInfoRow('Use ${coinData['network']}.'),
                  _buildInfoRow('Credits after confirmation.'),
                ],
              ),
            ),
            SizedBox(height: context.space.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: context.space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: EdgeInsets.only(top: context.space.xs - 2),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: context.colors.textSecondary,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(width: context.space.sm),
          Expanded(
            child: Text(
              text,
              style: context.type.body.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
