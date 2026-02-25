import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/session_manager.dart';
import 'format.dart';
import '../widgets/game_message.dart';
import '../screens/deposit_screen.dart';

class BalanceGuard {
  static const double _minStake = 1.0;

  static Future<bool> ensurePlayableStake(
    BuildContext context,
    double stakeUsd,
  ) async {
    final session = context.read<SessionManager>();
    if (!session.isAuthenticated) {
      if (!context.mounted) {
        return false;
      }
      showGameMessage(context, 'Please log in to start a game.');
      return false;
    }

    final required = stakeUsd >= _minStake ? stakeUsd : _minStake;
    try {
      final balance = session.cachedBalance ?? await session.refreshBalance();
      if (balance.availableUsd < required) {
        if (!context.mounted) {
          return false;
        }
        await _showDepositDialog(
          context,
          required,
          balance.availableUsd,
        );
        return false;
      }
      return true;
    } on ApiException catch (error) {
      if (!context.mounted) {
        return false;
      }
      showGameMessage(context, error.message);
      return false;
    } catch (_) {
      if (!context.mounted) {
        return false;
      }
      showGameMessage(
        context,
        'Unable to verify your wallet. Please try again.',
      );
      return false;
    }
  }

  static Future<void> _showDepositDialog(
    BuildContext context,
    double required,
    double available,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0f172a),
        title: const Text(
          'Add Funds',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          'You need at least ${formatCurrency(required)} to play.\n'
          'Current balance: ${formatCurrency(available)}.\n'
          'Deposit funds to continue.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const DepositScreen(),
                ),
              );
            },
            child: const Text('Deposit Now'),
          ),
        ],
      ),
    );
  }
}
