import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

enum LogLevel { debug, info, warning, error }

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.category,
    required this.message,
    required this.level,
  });

  final DateTime timestamp;
  final String category;
  final String message;
  final LogLevel level;
}

class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();
  static const _maxEntries = 500;

  final _entries = ListQueue<LogEntry>();
  final _controller = StreamController<List<LogEntry>>.broadcast();

  List<LogEntry> get entries => List.unmodifiable(_entries);
  Stream<List<LogEntry>> get stream => _controller.stream;

  void log(String category, String message, {LogLevel level = LogLevel.info}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      category: category,
      message: message,
      level: level,
    );
    _entries.addLast(entry);
    while (_entries.length > _maxEntries) {
      _entries.removeFirst();
    }
    _controller.add(List.unmodifiable(_entries));
    if (kDebugMode) {
      debugPrint('[${entry.category}] ${entry.message}');
    }
  }

  void clear() {
    _entries.clear();
    _controller.add(List.unmodifiable(_entries));
  }
}
