import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_shell.dart';
import '../widgets/casino_top_nav.dart';
import '../widgets/section_header.dart';
import '../widgets/tag_badge.dart';
import 'crypto_deposit_screen.dart';
import 'mobile_money_deposit_screen.dart';

enum _DepositMethod { mobileMoney, crypto, card }

class DepositScreen extends StatefulWidget {
  const DepositScreen({super.key});

  @override
  State<DepositScreen> createState() => _DepositScreenState();
}

class _DepositScreenState extends State<DepositScreen> {
  final TextEditingController _amountController = TextEditingController(
    text: '100.00',
  );
  _DepositMethod _selected = _DepositMethod.crypto;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _selectAmount(num value) {
    _amountController.text = value.toStringAsFixed(2);
  }

  void _continue() {
    switch (_selected) {
      case _DepositMethod.mobileMoney:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Mobile Money deposits are coming soon.')),
        );
        return;
      case _DepositMethod.crypto:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CryptoDepositScreen()),
        );
        return;
      case _DepositMethod.card:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Card deposits are coming soon.')),
        );
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CasinoScaffold(
      appBar: const CasinoTopNav(title: 'Deposit', showBackButton: true),
      body: ListView(
        padding: EdgeInsets.symmetric(vertical: context.space.md),
        children: [
          const SectionHeader(title: 'Deposit'),
          SizedBox(height: context.space.md),
          _buildMethodCard(
            method: _DepositMethod.crypto,
            title: 'Crypto',
            subtitle: 'BTC, ETH, USDT',
            icon: Icons.currency_bitcoin_rounded,
            color: Colors.orange,
            badge: 'Live',
          ),
          SizedBox(height: context.space.sm),
          _buildMethodCard(
            method: _DepositMethod.mobileMoney,
            title: 'Mobile Money',
            subtitle: 'Coming soon',
            icon: Icons.phone_android_rounded,
            color: context.colors.primary,
            badge: 'Soon',
          ),
          SizedBox(height: context.space.sm),
          _buildMethodCard(
            method: _DepositMethod.card,
            title: 'Cards',
            subtitle: 'Coming soon',
            icon: Icons.credit_card_rounded,
            color: AppTheme.rewardGold,
            badge: 'Soon',
          ),
          SizedBox(height: context.space.lg),
          _buildAmountPanel(),
          SizedBox(height: context.space.md),
          _buildSummaryPanel(),
          SizedBox(height: context.space.lg),
          PrimaryButton(
            expanded: true,
            label: _selected == _DepositMethod.crypto ? 'Continue' : 'Notify Me',
            icon: Icons.bolt_rounded,
            onPressed: _continue,
          ),
        ],
      ),
    );
  }

  Widget _buildMethodCard({
    required _DepositMethod method,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String badge,
  }) {
    final selected = _selected == method;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      backgroundColor: selected
          ? context.colors.primary.withValues(alpha: 0.08)
          : context.colors.bgCard,
      child: InkWell(
        borderRadius: BorderRadius.circular(context.radii.lg),
        onTap: () => setState(() => _selected = method),
        child: Padding(
          padding: EdgeInsets.all(context.space.sm),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(context.radii.lg),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: color),
              ),
              SizedBox(width: context.space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: context.type.bodyStrong.copyWith(
                              color: context.colors.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        TagBadge(
                          label: badge,
                          backgroundColor: color.withValues(alpha: 0.14),
                          foregroundColor: color,
                        ),
                      ],
                    ),
                    SizedBox(height: context.space.xxs),
                    Text(
                      subtitle,
                      style: context.type.body.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: context.space.sm),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected
                        ? context.colors.primary
                        : context.colors.border,
                    width: 2,
                  ),
                ),
                child: selected
                    ? Center(
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: context.colors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAmountPanel() {
    return SurfaceCard(
      padding: EdgeInsets.all(context.space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount',
            style: context.type.bodyStrong.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: context.space.sm),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: context.type.heroTitle.copyWith(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w900,
            ),
            decoration: InputDecoration(
              prefixText: r'$ ',
              prefixStyle: context.type.heroTitle.copyWith(
                color: context.colors.primary,
                fontWeight: FontWeight.w900,
              ),
              hintText: '0.00',
            ),
          ),
          SizedBox(height: context.space.md),
          Wrap(
            spacing: context.space.xs,
            runSpacing: context.space.xs,
            children: [
              _amountChip(10),
              _amountChip(50),
              _amountChip(100),
              _amountChip(500),
            ],
          ),
        ],
      ),
    );
  }

  Widget _amountChip(num value) {
    return ActionChip(
      label: Text(formatAmountLabel(value)),
      onPressed: () => _selectAmount(value),
      backgroundColor: context.colors.bgSurface,
      side: BorderSide(color: context.colors.border),
      labelStyle: context.type.label.copyWith(
        color: context.colors.textPrimary,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  String formatAmountLabel(num value) => '\$${value.toStringAsFixed(0)}';

  Widget _buildSummaryPanel() {
    final methodLabel = switch (_selected) {
      _DepositMethod.mobileMoney => 'Mobile Money',
      _DepositMethod.crypto => 'Crypto',
      _DepositMethod.card => 'Cards',
    };

    return SurfaceCard(
      padding: EdgeInsets.all(context.space.md),
      backgroundColor: context.colors.bgSurface,
      child: Column(
        children: [
          _summaryLine('Gateway', methodLabel),
          Divider(height: context.space.lg, color: context.colors.border),
          _summaryLine('Fee', '\$0.00', accent: context.colors.primary),
          Divider(height: context.space.lg, color: context.colors.border),
          _summaryLine(
            'Estimated Time',
            _selected == _DepositMethod.card ? 'Pending launch' : 'Instant',
          ),
        ],
      ),
    );
  }

  Widget _summaryLine(String label, String value, {Color? accent}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: context.type.body.copyWith(
              color: context.colors.textSecondary,
            ),
          ),
        ),
        Text(
          value,
          style: context.type.bodyStrong.copyWith(
            color: accent ?? context.colors.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
