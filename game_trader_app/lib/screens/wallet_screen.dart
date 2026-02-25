import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_theme.dart';
import '../services/models.dart';
import '../services/session_manager.dart';
import 'shared_bottom_nav.dart';
import 'deposit_screen.dart';
import 'crypto_deposit_screen.dart';
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
    if (!mounted || latest == null) return;
    setState(() {
      _balance = latest;
    });
  }

  Future<void> _loadData() async {
    final session = context.read<SessionManager>();
    if (!session.isAuthenticated) return;
    setState(() => _loading = true);
    try {
      final balance = await session.refreshBalance();
      final ledger = await session.walletService.fetchLedger(
        session.session!.accessToken,
      );
      if (mounted) {
        setState(() {
          _balance = balance;
          _ledger = ledger;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load wallet: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildHeader(context),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      children: [
                        _buildBalanceSection(),
                        const SizedBox(height: 24),
                        _buildActionButtons(context),
                        const SizedBox(height: 40),
                        _buildPaymentMethods(context),
                        const SizedBox(height: 32),
                        _buildTransactionHistory(),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SharedBottomNav(currentIndex: 2),
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
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(Icons.person, color: AppTheme.primaryColor),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TRADER PRO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                      color: Color(0xFF94a3b8),
                    ),
                  ),
                  Text(
                    'Alex Rivera',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: AppTheme.surfaceDark,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.settings, color: Colors.white, size: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceSection() {
    final sessionBalance = context.watch<SessionManager>().cachedBalance;
    final balance = _balance ?? sessionBalance;
    final available = balance?.availableUsd ?? 0;
    final reserved = balance?.reservedUsd ?? 0;
    final updatedAt = balance?.updatedAt;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          const Text(
            'Total Balance',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF94a3b8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '\$${available.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              color: AppTheme.primaryColor,
              shadows: [
                Shadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.5),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(9999),
              border: Border.all(
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.savings_outlined,
                  color: AppTheme.primaryColor,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  'Reserved \$${reserved.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          if (updatedAt != null) ...[
            const SizedBox(height: 6),
            Text(
              'Updated ${updatedAt.toLocal()}',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94a3b8)),
            ),
          ],
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              children: [
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TIER: GOLD TRADER',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94a3b8),
                      ),
                    ),
                    Text(
                      '85% to Platinum',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        fontStyle: FontStyle.italic,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  height: 6,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1e293b),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: 0.85,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor,
                        borderRadius: BorderRadius.circular(9999),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryColor.withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9999),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryColor.withValues(alpha: 0.2),
                  blurRadius: 20,
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DepositScreen(),
                  ),
                );
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle, size: 20),
                  SizedBox(width: 8),
                  Text('Deposit'),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const WithdrawalScreen(),
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                backgroundColor: AppTheme.surfaceDark,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    size: 20,
                    color: Colors.white,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Withdraw',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentMethods(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Payment Methods',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Text(
              'MANAGE',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: AppTheme.primaryColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CryptoDepositScreen(),
                    ),
                  );
                },
                child: _buildPaymentCard(
                  icon: Icons.currency_bitcoin,
                  color: Colors.orange,
                  title: 'Crypto',
                  subtitle: 'BTC, ETH, USDT',
                ),
              ),
              const SizedBox(width: 16),
              _buildPaymentCard(
                icon: Icons.credit_card,
                color: Colors.blue,
                title: 'Cards',
                subtitle: 'Visa, Mastercard',
              ),
              const SizedBox(width: 16),
              _buildPaymentCard(
                icon: Icons.account_balance,
                color: Colors.purple,
                title: 'E-Wallets',
                subtitle: 'PayPal, Skrill',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.transparent),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, color: Color(0xFF94a3b8)),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent Activity',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            Icon(Icons.tune, color: Color(0xFF94a3b8), size: 20),
          ],
        ),
        const SizedBox(height: 16),
        if (_ledger.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              _loading
                  ? 'Loading activity...'
                  : 'No recorded transactions yet.',
              style: const TextStyle(color: Color(0xFF94a3b8)),
            ),
          )
        else
          ..._ledger.map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildTransactionItem(entry),
            ),
          ),
      ],
    );
  }

  Widget _buildTransactionItem(LedgerEntry entry) {
    final isCredit = entry.amountUsd >= 0;
    final color = isCredit ? Colors.greenAccent : Colors.redAccent;
    final icon = isCredit ? Icons.arrow_downward : Icons.arrow_upward;
    final amountText =
        '${isCredit ? '+' : ''}${_formatCurrency(entry.amountUsd.abs())}';
    final timestamp = entry.createdAt?.toLocal().toString() ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceDark.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.type,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timestamp,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF94a3b8),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amountText,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                entry.reference.isEmpty ? '—' : entry.reference,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF94a3b8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCurrency(double value) {
    return '\$${value.toStringAsFixed(2)}';
  }
}
