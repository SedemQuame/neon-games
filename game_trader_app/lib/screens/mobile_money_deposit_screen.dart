import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  final _picker = ImagePicker();
  File? _proofImage;
  bool _loading = false;

  bool get _isFormValid {
    return _phoneController.text.isNotEmpty &&
        _amountController.text.isNotEmpty &&
        _proofImage != null;
  }

  @override
  void initState() {
    super.initState();
    _phoneController.addListener(() => setState(() {}));
    _amountController.addListener(() => setState(() {}));
  }

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

                    // Manual Instructions
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withValues(alpha: 0.1),
                        border: Border.all(
                          color: AppTheme.primaryColor.withValues(alpha: 0.3),
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Please send your deposit to:',
                            style: TextStyle(color: Colors.white, fontSize: 14),
                          ),
                          SizedBox(height: 8),
                          Text(
                            // TODO: Replace with actual phone number from a merchant account.
                            '0546744163 - Sedem Amekpewu',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'After sending, fill the form below to confirm your deposit.',
                            style: TextStyle(
                              color: Color(0xFF94a3b8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

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
                      label: 'Sending Number',
                      icon: Icons.phone_android,
                      placeholder: 'Number used to send money',
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
                    const SizedBox(height: 24),

                    // Proof of Payment Upload
                    const Padding(
                      padding: EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Proof of Payment',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFcbd5e1),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceDark,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _proofImage != null
                                ? AppTheme.primaryColor
                                : AppTheme.borderDark,
                          ),
                        ),
                        child: _proofImage != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.file(
                                  _proofImage!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                ),
                              )
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.cloud_upload_outlined,
                                    size: 32,
                                    color: AppTheme.primaryColor.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Upload Screenshot',
                                    style: TextStyle(
                                      color: Color(0xFF94a3b8),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                      ),
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
                        onPressed: (_loading || !_isFormValid)
                            ? null
                            : () => _submitPayment(context),
                        child: _loading
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'I have paid',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Icon(Icons.check_circle_outline, size: 20),
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

  Future<void> _pickImage() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      setState(() {
        _proofImage = File(pickedFile.path);
      });
    }
  }

  Future<void> _submitPayment(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final session = context.read<SessionManager>();
    final token = session.session?.accessToken;
    if (token == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please sign in to continue')),
      );
      return;
    }
    final amount = double.tryParse(_amountController.text) ?? 0;
    if (amount <= 0 || _phoneController.text.isEmpty || _proofImage == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Enter valid phone, amount and proof image'),
        ),
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
        proofImagePath: _proofImage?.path,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Deposit pending manual verification. Ref: ${response.reference}',
          ),
        ),
      );
      if (context.mounted) {
        Navigator.pop(context);
      }
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Payment failed: $e')));
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
