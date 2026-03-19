/// Lifecycle states of an OTA upgrade operation.
enum OtaStatus {
  /// No OTA operation in progress.
  idle,

  /// BLE scanning for devices.
  scanning,

  /// Establishing BLE connection.
  connecting,

  /// Discovering BLE services and characteristics.
  discoveringServices,

  /// Negotiating MTU and sending PREPARE_DOWNLOAD command.
  preparingDownload,

  /// Sending firmware chunks via the OTA Data characteristic.
  transferring,

  /// Sending VERIFY command; waiting for CRC confirmation.
  verifying,

  /// Upgrade completed successfully; device rebooting.
  success,

  /// Upgrade failed due to an error.
  failed,

  /// Upgrade was cancelled by the host.
  aborted,
}

/// Snapshot of OTA upgrade progress emitted on the progress stream.
class OtaProgress {
  /// Current lifecycle state of the operation.
  final OtaStatus status;

  /// Upload percentage in the range [0.0, 100.0].
  final double progress;

  /// Number of firmware bytes written so far.
  final int bytesTransferred;

  /// Total firmware image size in bytes.
  final int totalBytes;

  /// Human-readable description of the current activity.
  final String message;

  const OtaProgress({
    required this.status,
    this.progress = 0.0,
    this.bytesTransferred = 0,
    this.totalBytes = 0,
    this.message = '',
  });

  /// Returns `true` when the operation has ended (success, failure or abort).
  bool get isTerminal =>
      status == OtaStatus.success ||
      status == OtaStatus.failed ||
      status == OtaStatus.aborted;

  /// Convenience constructor for the idle initial state.
  factory OtaProgress.idle() =>
      const OtaProgress(status: OtaStatus.idle, message: 'Ready');

  /// Creates a copy with the given fields replaced.
  OtaProgress copyWith({
    OtaStatus? status,
    double? progress,
    int? bytesTransferred,
    int? totalBytes,
    String? message,
  }) {
    return OtaProgress(
      status: status ?? this.status,
      progress: progress ?? this.progress,
      bytesTransferred: bytesTransferred ?? this.bytesTransferred,
      totalBytes: totalBytes ?? this.totalBytes,
      message: message ?? this.message,
    );
  }

  @override
  String toString() =>
      'OtaProgress(status: $status, '
      'progress: ${progress.toStringAsFixed(1)}%, '
      'bytes: $bytesTransferred/$totalBytes, '
      'message: "$message")';
}

