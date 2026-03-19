import 'dart:typed_data';

import 'models/ota_result.dart';
import 'models/ota_status.dart';
import 'ota/airoc_ota_constants.dart';
import 'ota/airoc_ota_service.dart';
import 'ota/cyacd2_parser.dart';
import 'ota/cyacd_parser.dart';
import 'ota/ota_file.dart';

/// Lightweight helper for firmware parsing and OTA execution.
///
/// This manager is BLE-stack agnostic. Callers provide an [AirocOtaTransport]
/// implementation from their own platform/BLE plugin.
class AirocOtaManager {
  AirocOtaService? _activeService;

  Stream<OtaProgress> get progressStream =>
      _activeService?.progressStream ?? const Stream<OtaProgress>.empty();

  OtaFile loadFirmwareFromBytes(Uint8List bytes, String fileName) {
    final normalizedName = fileName.toLowerCase();
    if (normalizedName.endsWith(AirocOtaConstants.cyacd2Extension)) {
      return Cyacd2Parser.parse(bytes, fileName: fileName);
    }
    if (normalizedName.endsWith(AirocOtaConstants.cyacdExtension)) {
      return CyacdParser.parse(bytes, fileName: fileName);
    }
    throw UnsupportedError(
      'Only .cyacd2 and .cyacd firmware files are currently supported.',
    );
  }

  Future<OtaResult> performOta({
    required AirocOtaTransport transport,
    required OtaFile file,
    void Function(OtaProgress progress)? onProgress,
    int? securityKeyOverride,
  }) async {
    await _activeService?.dispose();
    _activeService = AirocOtaService(transport: transport);
    return _activeService!.performOta(
      file,
      onProgress: onProgress,
      securityKeyOverride: securityKeyOverride,
    );
  }

  void cancelOta() {
    _activeService?.cancel();
  }

  Future<void> dispose() async {
    await _activeService?.dispose();
  }
}
