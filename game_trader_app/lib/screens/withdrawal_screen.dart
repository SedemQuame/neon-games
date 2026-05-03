import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/session_manager.dart';
import '../utils/format.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_shell.dart';
import '../widgets/casino_top_nav.dart';
import '../widgets/price_label.dart';
import '../widgets/section_header.dart';

class WithdrawalScreen extends StatefulWidget {
  const WithdrawalScreen({super.key});

  @override
  State<WithdrawalScreen> createState() => _WithdrawalScreenState();
}

class _WithdrawalScreenState extends State<WithdrawalScreen> {
  String _selectedMethod = 'Mobile Money';
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  bool _loading = false;

  String _selectedNetwork = 'MTN Mobile Money';
  final List<String> _networks = [
    'MTN Mobile Money',
    'Vodafone Cash',
    'AirtelTigo Money',
  ];

  String _selectedCrypto = 'USDT';
  final List<String> _cryptos = ['BTC', 'ETH', 'USDT'];

  final List<Map<String, dynamic>> _methods = [
    {
      'name': 'Mobile Money',
      'icon': Icons.phone_android,
      'color': Colors.green,
      'hint': 'Mobile number',
    },
    {
      'name': 'Crypto Wallet',
      'icon': Icons.currency_bitcoin,
      'color': Colors.orange,
      'hint': 'Wallet address',
    },
  ];

  @override
  void initState() {
    super.initState();
    _amountController.addListener(() => setState(() {}));
    _addressController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  String _mapNetworkToChannel(String network) {
    if (network.contains('MTN')) {
      return 'mtn-gh';
    }
    if (network.contains('Vodafone')) {
      return 'vodafone-gh';
    }
    return 'airteltigo-gh';
  }

  double get _enteredAmount => double.tryParse(_amountController.text) ?? 0;
  double get _rakeFee => _enteredAmount * 0.05;
  double get _finalPayout => _enteredAmount - _rakeFee;

  bool get _isValid {
    if (_enteredAmount <= 0) {
      return false;
    }
    if (_addressController.text.isEmpty) {
      return false;
    }
    return true;
  }

  Future<void> _submitWithdrawal(BuildContext context) async {
    final session = context.read<SessionManager>();
    final token = session.session?.accessToken;
    if (token == null) {
      return;
    }

    final paymentService = session.paymentService;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _loading = true);

    try {
      if (_selectedMethod == 'Mobile Money') {
        final response = await paymentService.initiateMoMoWithdrawal(
          token: token,
          phone: _addressController.text.trim(),
          amount: _enteredAmount,
          channel: _mapNetworkToChannel(_selectedNetwork),
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Withdrawal Processing'),
          ),
        );
        try {
          await session.refreshBalance();
        } catch (_) {}
        if (context.mounted) {
          Navigator.pop(context);
        }
      } else if (_selectedMethod == 'Crypto Wallet') {
        final response = await paymentService.initiateCryptoWithdrawal(
          token: token,
          coin: _selectedCrypto,
          address: _addressController.text.trim(),
          amount: _enteredAmount,
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(response['message'] ?? 'Withdrawal Processing'),
          ),
        );
        try {
          await session.refreshBalance();
        } catch (_) {}
        if (context.mounted) {
          Navigator.pop(context);
        }
      }
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final methodData = _methods.firstWhere((m) => m['name'] == _selectedMethod);

    return CasinoScaffold(
      appBar: const CasinoTopNav(title: 'Withdraw', showBackButton: true),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: context.space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Withdraw'),
            SizedBox(height: context.space.lg),
            _buildBalanceCard(),
            SizedBox(height: context.space.md),
            _buildMethodSelector(),
            SizedBox(height: context.space.md),
            if (_selectedMethod == 'Mobile Money') ...[
              _buildNetworkSelector(),
              SizedBox(height: context.space.md),
            ] else ...[
              _buildCryptoSelector(),
              SizedBox(height: context.space.md),
            ],
            _buildTextField(
              label: _selectedMethod == 'Mobile Money'
                  ? 'Mobile Number'
                  : 'Wallet Address',
              icon: methodData['icon'] as IconData,
              placeholder: methodData['hint'] as String,
              controller: _addressController,
              keyboardType: _selectedMethod == 'Mobile Money'
                  ? TextInputType.phone
                  : TextInputType.text,
            ),
            SizedBox(height: context.space.md),
            _buildTextField(
              label: 'Amount',
              icon: Icons.attach_money,
              placeholder: 'Amount',
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            SizedBox(height: context.space.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                PriceLabel(value: 5, label: 'Min Stake'),
                PriceLabel(value: 5000, label: 'From'),
              ],
            ),
            SizedBox(height: context.space.lg),
            _buildSummaryCard(),
            SizedBox(height: context.space.xl),
            PrimaryButton(
              label: _loading ? 'Processing...' : 'Submit',
              icon: Icons.arrow_forward,
              onPressed: (_loading || !_isValid)
                  ? null
                  : () => _submitWithdrawal(context),
              expanded: true,
            ),
            SizedBox(height: context.space.xs),
            Text(
              '5% fee applies.',
              textAlign: TextAlign.center,
              style: context.type.label.copyWith(
                color: context.colors.textSecondary,
              ),
            ),
            SizedBox(height: context.space.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Consumer<SessionManager>(
      builder: (context, session, _) {
        final available = session.cachedBalance?.availableUsd ?? 0;

        return SurfaceCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available',
                    style: context.type.label.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: context.space.xxs),
                  Text(
                    formatCurrency(available),
                    style: context.type.sectionTitle.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                ],
              ),
              SecondaryButton(
                label: 'Use Max',
                onPressed: () {
                  setState(() {
                    _amountController.text = available.toStringAsFixed(2);
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMethodSelector() {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Method',
            style: context.type.label.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          SizedBox(height: context.space.xs),
          DropdownButtonFormField<String>(
            initialValue: _selectedMethod,
            items: _methods.map((method) {
              return DropdownMenuItem<String>(
                value: method['name'] as String,
                child: Row(
                  children: [
                    Icon(
                      method['icon'] as IconData,
                      color: method['color'] as Color,
                    ),
                    SizedBox(width: context.space.sm),
                    Text(method['name'] as String),
                  ],
                ),
              );
            }).toList(),
            onChanged: (value) {
              if (value == null) {
                return;
              }
              setState(() {
                _selectedMethod = value;
                _addressController.clear();
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkSelector() {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Network',
            style: context.type.label.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          SizedBox(height: context.space.xs),
          DropdownButtonFormField<String>(
            initialValue: _selectedNetwork,
            items: _networks
                .map(
                  (network) => DropdownMenuItem<String>(
                    value: network,
                    child: Text(network),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedNetwork = value);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCryptoSelector() {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Crypto Coin',
            style: context.type.label.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          SizedBox(height: context.space.xs),
          DropdownButtonFormField<String>(
            initialValue: _selectedCrypto,
            items: _cryptos
                .map(
                  (coin) =>
                      DropdownMenuItem<String>(value: coin, child: Text(coin)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedCrypto = value);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    required String placeholder,
    required TextEditingController controller,
    required TextInputType keyboardType,
  }) {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.type.label.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
          SizedBox(height: context.space.xs),
          TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: placeholder,
              prefixIcon: Icon(icon),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard() {
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader(title: 'Summary'),
          SizedBox(height: context.space.sm),
          _summaryRow('Amount', formatCurrency(_enteredAmount)),
          SizedBox(height: context.space.xs),
          _summaryRow('Fee', '- ${formatCurrency(_rakeFee)}'),
          const Divider(height: 18),
          _summaryRow('Payout', formatCurrency(_finalPayout), isStrong: true),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, {bool isStrong = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: context.type.body.copyWith(
            color: context.colors.textSecondary,
          ),
        ),
        Text(
          value,
          style: context.type.bodyStrong.copyWith(
            color: isStrong
                ? context.colors.primary
                : context.colors.textPrimary,
            fontWeight: isStrong ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
