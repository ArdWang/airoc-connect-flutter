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
// ANSI color helpers (for terminal output)
// ─────────────────────────────────────────────────────────────────────────────

/// ANSI escape code helpers for colorized terminal output.
class _Ansi {
  const _Ansi._();

  static const reset = '\x1B[0m';
  static const bold = '\x1B[1m';
  static const dim = '\x1B[2m';

  // Foreground
  static const green = '\x1B[32m';
  static const magenta = '\x1B[35m';
  static const cyan = '\x1B[36m';
  static const gray = '\x1B[90m';
  static const brightRed = '\x1B[91m';
  static const brightYellow = '\x1B[93m';
  static const brightCyan = '\x1B[96m';
  static const white = '\x1B[97m';

  // Backgrounds
  static const bgRed = '\x1B[41m';
  static const bgYellow = '\x1B[43m';
  static const bgBlue = '\x1B[44m';

  /// Level color.
  static String levelColor(AirocLogLevel level) {
    switch (level) {
      case AirocLogLevel.verbose:
        return '$dim$gray';
      case AirocLogLevel.info:
        return brightCyan;
      case AirocLogLevel.warning:
        return '$brightYellow$bold';
      case AirocLogLevel.error:
        return '$brightRed$bold';
    }
  }

  /// Level badge with colored background.
  static String levelBadge(AirocLogLevel level) {
    switch (level) {
      case AirocLogLevel.verbose:
        return '$gray$bgBlue V $reset$gray';
      case AirocLogLevel.info:
        return '$white$bgBlue I $reset';
      case AirocLogLevel.warning:
        return '$white$bgYellow W $reset';
      case AirocLogLevel.error:
        return '$white$bgRed E $reset';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Log entry
// ─────────────────────────────────────────────────────────────────────────────

/// Which direction BLE data flowed: transmit (phone→device) or receive (device→phone).
enum AirocDataDirection { tx, rx }

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

  /// Data direction for BLE hex entries, null for plain messages.
  final AirocDataDirection? direction;

  const AirocLogEntry({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.hex,
    this.direction,
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

  /// Colorized string for terminal output.
  String toColorizedString() {
    final badge = _Ansi.levelBadge(level);
    final tagStr = '${_Ansi.green}[$tag]${_Ansi.reset}';
    final time = '${_Ansi.gray}$timeLabel${_Ansi.reset}';
    final msgColor = _Ansi.levelColor(level);

    String hexPart = '';
    if (hex != null && hex!.isNotEmpty) {
      final hexColor = direction == AirocDataDirection.tx
          ? _Ansi.magenta
          : direction == AirocDataDirection.rx
              ? _Ansi.cyan
              : _Ansi.gray;
      hexPart = '\n    $hexColor$hex$_Ansi.reset';
    }

    return '$badge $time  $tagStr $msgColor$message$_Ansi.reset$hexPart';
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
    final desc = label != null
        ? '→ TX  [$label]  ${bytes.length} bytes'
        : '→ TX  ${bytes.length} bytes';
    _log(
      AirocLogLevel.verbose,
      tag,
      desc,
      hex: _toHex(bytes),
      direction: AirocDataDirection.tx,
    );
  }

  /// Log bytes **received** from a BLE notification (RX).
  void logRx(String tag, List<int> bytes, {String? label}) {
    final desc = label != null
        ? '← RX  [$label]  ${bytes.length} bytes'
        : '← RX  ${bytes.length} bytes';
    _log(
      AirocLogLevel.verbose,
      tag,
      desc,
      hex: _toHex(bytes),
      direction: AirocDataDirection.rx,
    );
  }

  // ── Buffer management ────────────────────────────────────────────────────

  /// Remove all buffered entries.
  void clear() => _buffer.clear();

  /// Return all entries formatted as a plain-text string (for copy / export).
  String exportAsText() => _buffer.map((e) => e.toString()).join('\n');

  // ── Internal ─────────────────────────────────────────────────────────────

  void _log(AirocLogLevel level, String tag, String message,
      {String? hex, AirocDataDirection? direction}) {
    final entry = AirocLogEntry(
      timestamp: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      hex: hex,
      direction: direction,
    );
    _buffer.add(entry);
    if (_buffer.length > _maxEntries) {
      _buffer.removeRange(0, _buffer.length - _maxEntries);
    }
    if (!_controller.isClosed) {
      _controller.add(entry);
    }
    // Mirror to Flutter/IDE console with ANSI colors.
    debugPrint(entry.toColorizedString());
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
