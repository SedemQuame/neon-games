import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/session_manager.dart';
import '../utils/format.dart';

class WithdrawalScreen extends StatefulWidget {
  const WithdrawalScreen({super.key});

  @override
  State<WithdrawalScreen> createState() => _WithdrawalScreenState();
}

class _WithdrawalScreenState extends State<WithdrawalScreen> {
  String _selectedMethod = 'Crypto Wallet';
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  final List<Map<String, dynamic>> _methods = [
    {
      'name': 'Crypto Wallet',
      'icon': Icons.currency_bitcoin,
      'color': Colors.orange,
      'hint': 'Enter Wallet Address (BTC, ETH, USDT)',
    },
    {
      'name': 'Bank Transfer',
      'icon': Icons.account_balance,
      'color': Colors.blueAccent,
      'hint': 'Enter IBAN or Account Number',
    },
    {
      'name': 'Credit/Debit Card',
      'icon': Icons.credit_card,
      'color': Colors.purple,
      'hint': 'Enter Card Number',
    },
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final methodData = _methods.firstWhere((m) => m['name'] == _selectedMethod);

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
                      'Withdraw Funds',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Select a destination and enter withdrawal details.',
                      style: TextStyle(color: Color(0xFF94a3b8), fontSize: 14),
                    ),
                    const SizedBox(height: 32),

                    // Available Balance
                    Consumer<SessionManager>(
                      builder: (context, session, _) {
                        final available =
                            session.cachedBalance?.availableUsd ?? 0;
                        return Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceDark,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: AppTheme.borderDark),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Available Balance',
                                    style: TextStyle(
                                      color: Color(0xFFcbd5e1),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    formatCurrency(available),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _amountController.text =
                                        available.toStringAsFixed(2);
                                  });
                                },
                                style: TextButton.styleFrom(
                                  backgroundColor:
                                      AppTheme.primaryColor.withValues(
                                    alpha: 0.1,
                                  ),
                                  foregroundColor: AppTheme.primaryColor,
                                ),
                                child: const Text(
                                  'Max',
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),

                    // Withdrawal Method Selector
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Withdrawal Method',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFcbd5e1),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundDark,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.borderDark),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedMethod,
                          isExpanded: true,
                          dropdownColor: AppTheme.surfaceDark,
                          icon: const Icon(
                            Icons.keyboard_arrow_down,
                            color: Colors.white,
                          ),
                          items: _methods.map((method) {
                            return DropdownMenuItem<String>(
                              value: method['name'] as String,
                              child: Row(
                                children: [
                                  Icon(
                                    method['icon'] as IconData,
                                    color: method['color'] as Color,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    method['name'] as String,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _selectedMethod = newValue;
                                _addressController.clear();
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Amount Input
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Amount (USD)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFcbd5e1),
                        ),
                      ),
                    ),
                    TextField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        hintStyle: const TextStyle(color: Color(0xFF475569)),
                        prefixIcon: const Icon(
                          Icons.attach_money,
                          color: Colors.white,
                        ),
                        filled: true,
                        fillColor: AppTheme.backgroundDark,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 16,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppTheme.borderDark),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Destination Address / Account Input
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Destination Details',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFcbd5e1),
                        ),
                      ),
                    ),
                    TextField(
                      controller: _addressController,
                      style: const TextStyle(color: Colors.white, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: methodData['hint'] as String,
                        hintStyle: const TextStyle(color: Color(0xFF475569)),
                        filled: true,
                        fillColor: AppTheme.backgroundDark,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 16,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(color: AppTheme.borderDark),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Warning Text
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Colors.blueAccent,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Withdrawals process within 15 minutes for crypto, and 1-3 business days for bank/cards. Be sure to double-check destination details.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.6),
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 48),

                    // Submit Button
                    Container(
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(9999),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () {
                          // Dummy submit action
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              backgroundColor: AppTheme.surfaceDark,
                              title: const Text(
                                'Withdrawal Initiated',
                                style: TextStyle(color: Colors.white),
                              ),
                              content: const Text(
                                'Your withdrawal request is being processed array.',
                                style: TextStyle(color: Colors.white70),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(context); // close dialog
                                    Navigator.pop(context); // go back to wallet
                                  },
                                  child: const Text(
                                    'Great',
                                    style: TextStyle(
                                      color: AppTheme.primaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        child: const Text(
                          'CONFIRM WITHDRAWAL',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
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
            'WITHDRAW FILLS',
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
}
