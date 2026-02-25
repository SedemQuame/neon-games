import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/api_client.dart';
import '../services/session_manager.dart';

class MobileMoneyDepositScreen extends StatefulWidget {
  const MobileMoneyDepositScreen({super.key});

  @override
  State<MobileMoneyDepositScreen> createState() =>
      _MobileMoneyDepositScreenState();
}

class _MobileMoneyDepositScreenState extends State<MobileMoneyDepositScreen> {
  String selectedNetwork = 'MTN Mobile Money';
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _phoneController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Mobile Money',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Fund your account directly from your mobile wallet.',
                      style: TextStyle(color: Color(0xFF94a3b8), fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    // Network Selection
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Select Network',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFcbd5e1),
                        ),
                      ),
                    ),
                    _buildNetworkSelector(),
                    const SizedBox(height: 24),

                    // Phone Number Input
                    _buildTextField(
                      label: 'Phone Number',
                      icon: Icons.phone_android,
                      placeholder: 'Enter your MoMo number',
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 24),

                    // Amount Input
                    _buildTextField(
                      label: 'Amount (\$)',
                      icon: Icons.attach_money,
                      placeholder: 'Enter deposit amount',
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Min: \$5.00',
                          style: TextStyle(
                            color: Color(0xFF94a3b8),
                            fontSize: 12,
                          ),
                        ),
                        const Text(
                          'Max: \$5,000.00',
                          style: TextStyle(
                            color: Color(0xFF94a3b8),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),

                    // Proceed Button
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9999),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.3),
                            blurRadius: 20,
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: _loading
                            ? null
                            : () => _submitPayment(context),
                        child: _loading
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Proceed to Pay',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.arrow_forward, size: 20),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.surfaceDark,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.borderDark),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),
          const Text(
            'MOBILE MONEY',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 2.0,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildNetworkSelector() {
    final networks = [
      {'name': 'MTN Mobile Money', 'color': Colors.yellow.shade700},
      {'name': 'Vodafone Cash', 'color': Colors.redAccent},
      {'name': 'AirtelTigo Money', 'color': Colors.blueAccent},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.borderDark),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedNetwork,
          dropdownColor: AppTheme.surfaceDark,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white),
          items: networks.map((network) {
            return DropdownMenuItem<String>(
              value: network['name'] as String,
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: network['color'] as Color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    network['name'] as String,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                selectedNetwork = newValue;
              });
            }
          },
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    required String placeholder,
    TextInputType? keyboardType,
    TextEditingController? controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFFcbd5e1),
            ),
          ),
        ),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: placeholder,
            prefixIcon: Icon(icon),
            fillColor: AppTheme.backgroundDark,
            filled: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.borderDark),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.borderDark),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.primaryColor),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _submitPayment(BuildContext context) async {
    final session = context.read<SessionManager>();
    final token = session.session?.accessToken;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to continue')),
      );
      return;
    }
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0 || _phoneController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid phone and amount')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final response = await session.paymentService.initiateMoMoDeposit(
        token: token,
        phone: _phoneController.text.trim(),
        amount: amount,
        channel: _mapNetworkToChannel(selectedNetwork),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Prompt sent! Ref ${response.reference}')),
      );
    } on ApiException catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  String _mapNetworkToChannel(String label) {
    switch (label) {
      case 'Vodafone Cash':
        return 'vodafone-gh';
      case 'AirtelTigo Money':
        return 'airteltigo-gh';
      default:
        return 'mtn-gh';
    }
  }
}
