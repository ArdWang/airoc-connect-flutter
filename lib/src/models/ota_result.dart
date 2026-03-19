import 'ota_status.dart';

/// The final outcome of a completed OTA upgrade attempt.
class OtaResult {
  /// `true` if the device accepted the firmware and is rebooting.
  final bool success;

  /// The terminal [OtaStatus] that ended the operation.
  final OtaStatus status;

  /// Human-readable error description when [success] is `false`.
  final String? errorMessage;

  /// Platform-level error code when [success] is `false`.
  final int? errorCode;

  /// Total bytes successfully written to the device.
  final int bytesTransferred;

  /// Wall-clock time from connection to finish.
  final Duration duration;

  const OtaResult({
    required this.success,
    required this.status,
    this.errorMessage,
    this.errorCode,
    this.bytesTransferred = 0,
    this.duration = Duration.zero,
  });

  /// Constructs a successful result.
  factory OtaResult.success({
    required int bytesTransferred,
    required Duration duration,
  }) {
    return OtaResult(
      success: true,
      status: OtaStatus.success,
      bytesTransferred: bytesTransferred,
      duration: duration,
    );
  }

  /// Constructs a failure result.
  factory OtaResult.failure({
    required String errorMessage,
    int? errorCode,
    int bytesTransferred = 0,
    Duration duration = Duration.zero,
  }) {
    return OtaResult(
      success: false,
      status: OtaStatus.failed,
      errorMessage: errorMessage,
      errorCode: errorCode,
      bytesTransferred: bytesTransferred,
      duration: duration,
    );
  }

  /// Constructs an aborted result.
  factory OtaResult.aborted({
    String errorMessage = 'OTA upgrade was cancelled by the user.',
  }) {
    return OtaResult(
      success: false,
      status: OtaStatus.aborted,
      errorMessage: errorMessage,
    );
  }

  /// Transfer speed in bytes per second, or `null` if duration is zero.
  double? get transferSpeedBytesPerSecond {
    if (duration == Duration.zero) return null;
    return bytesTransferred / duration.inMilliseconds * 1000;
  }

  @override
  String toString() {
    if (success) {
      return 'OtaResult(success, $bytesTransferred bytes in '
          '${duration.inSeconds}s)';
    }
    return 'OtaResult(${status.name}, errorCode: $errorCode, '
        'message: "$errorMessage")';
  }
}

