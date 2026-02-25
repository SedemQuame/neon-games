import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/app_logger.dart';

class AppLogsScreen extends StatelessWidget {
  const AppLogsScreen({super.key});

  Color _colorForLevel(LogLevel level) {
    switch (level) {
      case LogLevel.error:
        return Colors.redAccent;
      case LogLevel.warning:
        return Colors.amber;
      case LogLevel.debug:
        return Colors.blueGrey;
      case LogLevel.info:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundDark,
        foregroundColor: Colors.white,
        title: const Text('Application Logs'),
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
            return const Center(
              child: Text(
                'No logs captured yet.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[entries.length - 1 - index];
              final color = _colorForLevel(entry.level);
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  entry.message,
                  style: TextStyle(color: color, fontSize: 14),
                ),
                subtitle: Text(
                  '[${entry.category}] ${entry.timestamp.toIso8601String()}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
