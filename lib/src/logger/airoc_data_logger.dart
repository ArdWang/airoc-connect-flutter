import 'dart:async';

import 'package:flutter/foundation.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Log level
// ─────────────────────────────────────────────────────────────────────────────

/// Severity level of a log entry.
enum AirocLogLevel {
  /// Verbose / trace – raw BLE bytes, fine-grained state.
  verbose,

  /// Informational – normal OTA lifecycle events.
  info,

  /// Warning – unexpected but recoverable conditions.
  warning,

  /// Error – operation failed.
  error,
}

// ─────────────────────────────────────────────────────────────────────────────
// Log entry
// ─────────────────────────────────────────────────────────────────────────────

/// An immutable snapshot of one log line.
class AirocLogEntry {
  final DateTime timestamp;
  final AirocLogLevel level;

  /// Short category tag, e.g. "OTA", "BLE", "SCAN".
  final String tag;

  /// Human-readable description.
  final String message;

  /// Optional hex dump of raw BLE bytes (TX or RX).
  final String? hex;

  const AirocLogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.hex,
  });

  /// Formatted timestamp: HH:mm:ss.mmm
  String get timeLabel {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    final ms = timestamp.millisecond.toString().padLeft(3, '0');
    return '$h:$m:$s.$ms';
  }

  /// One-letter level abbreviation.
  String get levelLabel {
    switch (level) {
      case AirocLogLevel.verbose:
        return 'V';
      case AirocLogLevel.info:
        return 'I';
      case AirocLogLevel.warning:
        return 'W';
      case AirocLogLevel.error:
        return 'E';
    }
  }

  @override
  String toString() {
    final hexPart = hex != null ? '\n    HEX: $hex' : '';
    return '[$timeLabel] ${levelLabel.padRight(1)} [$tag] $message$hexPart';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logger
// ─────────────────────────────────────────────────────────────────────────────

/// Global, singleton data logger for AIROC BLE/OTA events.
///
/// Usage:
/// ```dart
/// final log = AirocDataLogger.instance;
/// log.i('OTA', 'Connecting to device…');
/// log.logTx('OTA', packet);   // logs hex of bytes written
/// log.logRx('OTA', response); // logs hex of bytes received
/// ```
///
/// Subscribe to [stream] for real-time display, or read [entries] for the
/// buffered history.
class AirocDataLogger {
  AirocDataLogger._();

  /// Global singleton.
  static final AirocDataLogger instance = AirocDataLogger._();

  static const int _maxEntries = 2000;

  final _controller = StreamController<AirocLogEntry>.broadcast();
  final _buffer = <AirocLogEntry>[];

  /// Real-time stream of new log entries.
  Stream<AirocLogEntry> get stream => _controller.stream;

  /// Snapshot of all buffered entries (newest last).
  List<AirocLogEntry> get entries => List.unmodifiable(_buffer);

  // ── Convenience log methods ──────────────────────────────────────────────

  /// Log a verbose / trace message.
  void v(String tag, String message, {String? hex}) =>
      _log(AirocLogLevel.verbose, tag, message, hex: hex);

  /// Log an informational message.
  void i(String tag, String message, {String? hex}) =>
      _log(AirocLogLevel.info, tag, message, hex: hex);

  /// Log a warning.
  void w(String tag, String message, {String? hex}) =>
      _log(AirocLogLevel.warning, tag, message, hex: hex);

  /// Log an error.
  void e(String tag, String message, {String? hex}) =>
      _log(AirocLogLevel.error, tag, message, hex: hex);

  // ── BLE-specific helpers ─────────────────────────────────────────────────

  /// Log bytes that were **written** to a BLE characteristic (TX).
  void logTx(String tag, List<int> bytes, {String? label}) {
    final desc = label != null ? '→ TX  [$label]  ${bytes.length} bytes' : '→ TX  ${bytes.length} bytes';
    _log(AirocLogLevel.verbose, tag, desc, hex: _toHex(bytes));
  }

  /// Log bytes **received** from a BLE notification (RX).
  void logRx(String tag, List<int> bytes, {String? label}) {
    final desc = label != null ? '← RX  [$label]  ${bytes.length} bytes' : '← RX  ${bytes.length} bytes';
    _log(AirocLogLevel.verbose, tag, desc, hex: _toHex(bytes));
  }

  // ── Buffer management ────────────────────────────────────────────────────

  /// Remove all buffered entries.
  void clear() => _buffer.clear();

  /// Return all entries formatted as a plain-text string (for copy / export).
  String exportAsText() => _buffer.map((e) => e.toString()).join('\n');

  // ── Internal ─────────────────────────────────────────────────────────────

  void _log(AirocLogLevel level, String tag, String message, {String? hex}) {
    final entry = AirocLogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      hex: hex,
    );
    _buffer.add(entry);
    if (_buffer.length > _maxEntries) {
      _buffer.removeRange(0, _buffer.length - _maxEntries);
    }
    if (!_controller.isClosed) {
      _controller.add(entry);
    }
    // Mirror to Flutter/IDE console for free.
    debugPrint('[AIROC][${entry.levelLabel}][$tag] $message'
        '${hex != null ? '\n    $hex' : ''}');
  }

  static String _toHex(List<int> bytes) {
    if (bytes.isEmpty) return '(empty)';
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join(' ');
  }

  void dispose() {
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}

