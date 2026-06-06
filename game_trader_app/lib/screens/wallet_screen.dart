import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/models.dart';
import '../services/session_manager.dart';
import '../utils/format.dart';
import '../widgets/app_buttons.dart';
import '../widgets/app_shell.dart';
import '../widgets/casino_top_nav.dart';
import '../widgets/price_label.dart';
import '../widgets/section_header.dart';
import 'crypto_deposit_screen.dart';
import 'deposit_screen.dart';
import 'shared_bottom_nav.dart';
import 'withdrawal_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  WalletBalance? _balance;
  List<LedgerEntry> _ledger = const [];
  bool _loading = false;
  SessionManager? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _session = context.read<SessionManager>();
      _session?.addListener(_handleSessionChanged);
      _balance = _session?.cachedBalance;
      _loadData();
    });
  }

  @override
  void dispose() {
    _session?.removeListener(_handleSessionChanged);
    super.dispose();
  }

  void _handleSessionChanged() {
    final latest = _session?.cachedBalance;
    if (!mounted || latest == null) {
      return;
    }
    setState(() => _balance = latest);
  }

  Future<void> _loadData() async {
    final session = context.read<SessionManager>();
    if (!session.isAuthenticated) {
      return;
    }

    setState(() => _loading = true);
    try {
      final balance = await session.refreshBalance();
      final ledger = await session.walletService.fetchLedger(
        session.session!.accessToken,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _balance = balance;
        _ledger = ledger;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not load wallet: $error')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionBalance = context.watch<SessionManager>().cachedBalance;
    final balance = _balance ?? sessionBalance;

    return CasinoScaffold(
      useNarrowLayout: true,
      appBar: const CasinoTopNav(title: 'Wallet'),
      bottomNavigationBar: const SharedBottomNav(currentIndex: 2),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: context.space.md, bottom: 96),
          children: [
            _buildBalanceSection(balance),
            SizedBox(height: context.space.lg),
            _buildActionButtons(context),
            SizedBox(height: context.space.lg),
            _buildPaymentMethods(context),
            SizedBox(height: context.space.lg),
            _buildTransactionHistory(),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceSection(WalletBalance? balance) {
    final available = balance?.availableUsd ?? 0;
    final reserved = balance?.reservedUsd ?? 0;
    final updatedAt = balance?.updatedAt;

    return Container(
      padding: EdgeInsets.all(context.space.md),
      decoration: BoxDecoration(
        color: context.colors.bgCard,
        borderRadius: BorderRadius.circular(context.radii.xl),
        border: Border.all(
          color: context.colors.primary.withValues(alpha: 0.24),
        ),
        boxShadow: context.elevation.focused,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -52,
            right: -44,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: context.colors.primary.withValues(alpha: 0.12),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeader(
                title: 'Balance',
                subtitle: updatedAt == null
                    ? null
                    : 'Updated ${updatedAt.toLocal().toString().split('.').first}',
              ),
              SizedBox(height: context.space.md),
              Text(
                formatCurrency(available),
                style: context.type.heroTitle.copyWith(
                  color: context.colors.primary,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: context.space.md),
              Wrap(
                spacing: context.space.sm,
                runSpacing: context.space.xs,
                children: [
                  PriceLabel(value: reserved, label: 'Reserved'),
                  _WalletStatusPill(
                    icon: Icons.shield_outlined,
                    label: 'Secure Ledger',
                    color: context.colors.success,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: PrimaryButton(
            label: 'Deposit',
            icon: Icons.add_circle,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DepositScreen()),
              );
            },
            expanded: true,
          ),
        ),
        SizedBox(width: context.space.md),
        Expanded(
          child: SecondaryButton(
            label: 'Withdraw',
            icon: Icons.account_balance_wallet,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const WithdrawalScreen()),
              );
            },
            expanded: true,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethods(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Methods', actionLabel: 'Manage'),
        SizedBox(height: context.space.md),
        SizedBox(
          height: 124,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _paymentMethodCard(
                icon: Icons.currency_bitcoin_rounded,
                title: 'Crypto',
                subtitle: 'BTC, ETH, USDT',
                color: Colors.orange,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CryptoDepositScreen(),
                    ),
                  );
                },
              ),
              SizedBox(width: context.space.sm),
              _paymentMethodCard(
                icon: Icons.phone_android_rounded,
                title: 'Mobile Money',
                subtitle: 'Coming soon',
                color: context.colors.primary,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Mobile Money deposits are coming soon.'),
                    ),
                  );
                },
              ),
              SizedBox(width: context.space.sm),
              _paymentMethodCard(
                icon: Icons.credit_card_rounded,
                title: 'Cards',
                subtitle: 'Coming soon',
                color: AppTheme.rewardGold,
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Card deposits are coming soon.'),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _paymentMethodCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 148,
      child: SurfaceCard(
        padding: EdgeInsets.all(context.space.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(context.radii.lg),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(context.radii.lg),
                  border: Border.all(color: color.withValues(alpha: 0.26)),
                ),
                child: Icon(icon, color: color),
              ),
              const Spacer(),
              Text(
                title,
                style: context.type.bodyStrong.copyWith(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: context.space.xxs),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.type.label.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'Activity'),
        SizedBox(height: context.space.md),
        if (_ledger.isEmpty)
          SurfaceCard(
            child: Padding(
              padding: EdgeInsets.all(context.space.md),
              child: Text(
                _loading ? 'Loading...' : 'No activity.',
                style: context.type.body.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          )
        else
          ..._ledger.map(
            (entry) => Padding(
              padding: EdgeInsets.only(bottom: context.space.sm),
              child: _buildTransactionItem(entry),
            ),
          ),
      ],
    );
  }

  Widget _buildTransactionItem(LedgerEntry entry) {
    final isCredit = entry.amountUsd >= 0;
    final color = isCredit ? context.colors.success : context.colors.danger;
    final icon = isCredit ? Icons.arrow_downward : Icons.arrow_upward;
    final amountText = formatSignedCurrency(entry.amountUsd);
    final timestamp = entry.createdAt?.toLocal().toString() ?? '';

    return SurfaceCard(
      backgroundColor: context.colors.bgSurface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(context.radii.lg),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                SizedBox(width: context.space.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.type,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.bodyStrong.copyWith(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: context.space.xxs),
                      Text(
                        timestamp,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.type.label.copyWith(
                          color: context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: context.space.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amountText,
                style: context.type.bodyStrong.copyWith(
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: context.space.xxs),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: context.space.xs,
                  vertical: context.space.xxs,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(context.radii.pill),
                ),
                child: Text(
                  entry.reference.isEmpty ? 'Recorded' : entry.reference,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.type.label.copyWith(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletStatusPill extends StatelessWidget {
  const _WalletStatusPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: context.space.sm,
        vertical: context.space.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(context.radii.pill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          SizedBox(width: context.space.xs),
          Text(
            label,
            style: context.type.label.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
