import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/api_client.dart';
import '../services/session_manager.dart';
import '../utils/format.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_shell.dart';
import '../widgets/casino_top_nav.dart';
import '../widgets/price_label.dart';
import '../widgets/section_header.dart';
import '../widgets/tag_badge.dart';

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
    return CasinoScaffold(
      appBar: const CasinoTopNav(title: 'Mobile Money', showBackButton: true),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: context.space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: 'Mobile Money'),
            SizedBox(height: context.space.lg),
            SurfaceCard(
              backgroundColor: context.colors.primary.withValues(alpha: 0.06),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TagBadge(label: 'Transfer'),
                  SizedBox(height: context.space.sm),
                  Text(
                    'Send to',
                    style: context.type.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: context.space.xs),
                  Text(
                    '0546744163 - Sedem Amekpewu',
                    style: context.type.bodyStrong.copyWith(
                      color: context.colors.textPrimary,
                    ),
                  ),
                  SizedBox(height: context.space.xs),
                  Text(
                    'Then confirm below.',
                    style: context.type.body.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: context.space.md),
            _buildNetworkSelector(),
            SizedBox(height: context.space.md),
            _buildTextField(
              label: 'Sender',
              icon: Icons.phone_android,
              placeholder: 'Phone number',
              controller: _phoneController,
              keyboardType: TextInputType.phone,
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
            SizedBox(height: context.space.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [
                PriceLabel(value: 5, label: 'Min Stake'),
                PriceLabel(value: 5000, label: 'From'),
              ],
            ),
            SizedBox(height: context.space.md),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Proof',
                    style: context.type.label.copyWith(
                      color: context.colors.textSecondary,
                    ),
                  ),
                  SizedBox(height: context.space.xs),
                  GestureDetector(
                    onTap: _pickImage,
                    child: Container(
                      height: 140,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: context.colors.bgSurface,
                        borderRadius: BorderRadius.circular(context.radii.lg),
                        border: Border.all(
                          color: _proofImage != null
                              ? context.colors.primary
                              : context.colors.border,
                        ),
                      ),
                      child: _proofImage != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(
                                context.radii.lg,
                              ),
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
                                  color: context.colors.primary,
                                ),
                                SizedBox(height: context.space.xs),
                                Text(
                                  'Upload',
                                  style: context.type.body.copyWith(
                                    color: context.colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: context.space.xl),
            PrimaryButton(
              label: _loading ? 'Submitting...' : 'Confirm',
              icon: Icons.check_circle_outline,
              onPressed: (_loading || !_isFormValid)
                  ? null
                  : () => _submitPayment(context),
              expanded: true,
            ),
            SizedBox(height: context.space.xs),
            Text(
              'Amount: ${formatCurrency(double.tryParse(_amountController.text) ?? 0)}',
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

  Widget _buildNetworkSelector() {
    final networks = [
      {'name': 'MTN Mobile Money', 'color': Colors.yellow.shade700},
      {'name': 'Vodafone Cash', 'color': Colors.redAccent},
      {'name': 'AirtelTigo Money', 'color': Colors.blueAccent},
    ];

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
            initialValue: selectedNetwork,
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
                    SizedBox(width: context.space.sm),
                    Text(network['name'] as String),
                  ],
                ),
              );
            }).toList(),
            onChanged: (newValue) {
              if (newValue != null) {
                setState(() => selectedNetwork = newValue);
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
    TextInputType? keyboardType,
    TextEditingController? controller,
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
          TextFormField(
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
    } on ApiException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('Payment failed: $error')));
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
