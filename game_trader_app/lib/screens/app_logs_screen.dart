import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/app_logger.dart';
import '../widgets/app_shell.dart';
import '../widgets/casino_top_nav.dart';

class AppLogsScreen extends StatelessWidget {
  const AppLogsScreen({super.key});

  Color _colorForLevel(BuildContext context, LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return context.colors.danger;
      case LogLevel.warning:
        return context.colors.warning;
      case LogLevel.debug:
        return context.colors.primary;
      case LogLevel.info:
        return context.colors.textPrimary;
    }
  }

  @override
  Widget build(BuildContext context) {
    return CasinoScaffold(
      appBar: CasinoTopNav(
        title: 'Logs',
        showBackButton: true,
        actions: [
          IconButton(
            tooltip: 'Clear logs',
            onPressed: AppLogger.instance.clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: StreamBuilder<List<LogEntry>>(
        initialData: AppLogger.instance.entries,
        stream: AppLogger.instance.stream,
        builder: (context, snapshot) {
          final entries = snapshot.data ?? const <LogEntry>[];
          if (entries.isEmpty) {
            return Center(
              child: Text(
                'No logs.',
                style: context.type.body.copyWith(
                  color: context.colors.textSecondary,
                ),
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.symmetric(vertical: context.space.md),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[entries.length - 1 - index];
              return Padding(
                padding: EdgeInsets.only(bottom: context.space.sm),
                child: SurfaceCard(
                  child: ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      entry.message,
                      style: context.type.body.copyWith(
                        color: _colorForLevel(context, entry.level),
                      ),
                    ),
                    subtitle: Text(
                      '[${entry.category}] ${entry.timestamp.toIso8601String()}',
                      style: context.type.label.copyWith(
                        color: context.colors.textSecondary,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
