import 'dart:io';
import 'dart:typed_data';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ble/airoc_ble_scanner.dart';
import '../models/airoc_device.dart';
import 'flutter_blue_plus_ota_transport.dart';

typedef ExampleOtaTransportFactory =
    AirocOtaTransport Function(AirocDevice device);

class ExampleOtaManager {
  final AirocBleScanner scanner;
  final ExampleOtaTransportFactory transportFactory;
  final String otaServiceUuid;
  final String otaCharacteristicUuid;

  AirocOtaService? _activeService;

  ExampleOtaManager({
    AirocBleScanner? scanner,
    ExampleOtaTransportFactory? transportFactory,
    this.otaServiceUuid = AirocOtaConstants.otaServiceUuid,
    this.otaCharacteristicUuid = AirocOtaConstants.otaCharacteristicUuid,
  })  : scanner = scanner ?? AirocBleScanner(otaServiceUuid: otaServiceUuid),
        transportFactory = transportFactory ??
            ((device) => FlutterBluePlusOtaTransport(
                  device.device,
                  otaServiceUuid: otaServiceUuid,
                  otaCharacteristicUuid: otaCharacteristicUuid,
                ));

  Future<bool> ensurePermissions() async {
    if (Platform.isIOS || Platform.isMacOS) {
      return true;
    }

    try {
      if (Platform.isAndroid) {
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
        ].request();

        final btScan = statuses[Permission.bluetoothScan];
        final btConnect = statuses[Permission.bluetoothConnect];
        final location = statuses[Permission.locationWhenInUse];

        final btReady =
            (btScan?.isGranted ?? false) || (btScan?.isLimited ?? false);
        final connectReady =
            (btConnect?.isGranted ?? false) || (btConnect?.isLimited ?? false);
        final locationReady =
            (location?.isGranted ?? false) ||
            (location?.isLimited ?? false) ||
            (location?.isPermanentlyDenied ?? false);

        return btReady && connectReady && locationReady;
      }

      return true;
    } on MissingPluginException {
      return false;
    } on UnsupportedError {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
    bool otaOnly = false,
  }) {
    return scanner.startScan(timeout: timeout, otaOnly: otaOnly);
  }

  Future<void> stopScan() => scanner.stopScan();

  Future<OtaFile?> pickFirmwareFile() async {
    final bool useAnyType =
        Platform.isIOS || Platform.isMacOS || Platform.isAndroid;

    final result = await FilePicker.platform.pickFiles(
      type: useAnyType ? FileType.any : FileType.custom,
      allowedExtensions:
          useAnyType ? null : AirocOtaConstants.supportedFirmwareExtensions,
      withData: true,
    );

    if (result == null || result.files.isEmpty) {
      return null;
    }

    final file = result.files.single;
    final fileName = file.name;

    if (useAnyType) {
      final lower = fileName.toLowerCase();
      final supported = AirocOtaConstants.supportedFirmwareExtensions
          .any((ext) => lower.endsWith('.$ext'));
      if (!supported) {
        throw UnsupportedError(
          'Unsupported file: "$fileName".\n'
          'Please select a .cyacd2 or .cyacd firmware file.',
        );
      }
    }

    Uint8List bytes;
    if (file.bytes != null && file.bytes!.isNotEmpty) {
      bytes = file.bytes!;
    } else if (file.path != null) {
      bytes = await File(file.path!).readAsBytes();
    } else {
      throw StateError(
        'Could not read firmware file "$fileName": '
        'no bytes or path returned by the file picker.',
      );
    }

    return loadFirmwareFromBytes(bytes, fileName);
  }

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
    required AirocDevice device,
    required OtaFile file,
    void Function(OtaProgress progress)? onProgress,
    int? securityKeyOverride,
  }) async {
    await _activeService?.dispose();
    _activeService = AirocOtaService(
      transport: transportFactory(device),
    );
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
    await scanner.dispose();
  }
}
