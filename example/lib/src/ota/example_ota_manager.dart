import 'dart:io';
import 'dart:async';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
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

  /// iOS/macOS (CoreBluetooth) 没有给 App 的编程式配对接口，
  /// `createBond()` / `bondState` 在 flutter_blue_plus 中是 Android-only。
  /// 苹果平台上配对是隐式的：访问加密特征值时由系统自动弹出配对框。
  bool get _isAndroid => Platform.isAndroid;

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

  /// Check if the device is currently bonded/paired
  Future<bool> isDeviceBonded(AirocDevice device) async {
    // iOS/macOS 无法查询 bondState，用"已连接"作为就绪信号。
    if (!_isAndroid) {
      return device.device.isConnected;
    }
    final state = await device.device.bondState.first;
    return state == BluetoothBondState.bonded;
  }

  /// Create a bond/pair with the device
  /// Note: Device must be connected before pairing.
  Future<bool> pairDevice(AirocDevice device) async {
    // iOS/macOS：CoreBluetooth 无编程式配对接口，createBond/bondState 是
    // Android-only。这里只需建立连接，系统会在访问加密特征值时自动提示配对。
    if (!_isAndroid) {
      try {
        if (device.device.isDisconnected) {
          AirocDataLogger.instance.i('BLE', 'Connecting device (implicit pairing on Apple platforms)…');
          await device.device.connect(
            timeout: const Duration(seconds: 10),
            mtu: null,
          );
        }
        AirocDataLogger.instance.i(
          'BLE',
          'Device connected ✓ Pairing (if required) will be prompted by the OS '
          'when an encrypted characteristic is accessed.',
        );
        return device.device.isConnected;
      } catch (e) {
        AirocDataLogger.instance.e('BLE', 'Connection failed: $e');
        return false;
      }
    }

    // Android: 显式创建绑定
    // Check current bond state
    final initialState = await device.device.bondState.first;
    if (initialState == BluetoothBondState.bonded) {
      AirocDataLogger.instance.i('BLE', 'Device already bonded');
      return true;
    }

    try {
      // Ensure device is connected before pairing
      if (device.device.isDisconnected) {
        AirocDataLogger.instance.i('BLE', 'Connecting device before pairing…');
        await device.device.connect(
          timeout: const Duration(seconds: 10),
          mtu: null,
        );
        // Wait for connection to stabilize
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Now create bond (pairing)
      AirocDataLogger.instance.i('BLE', 'Creating bond…');
      await device.device.createBond();

      // Wait for bond state to update to bonded
      AirocDataLogger.instance.i('BLE', 'Waiting for bond to complete…');
      final bondState = await device.device.bondState
          .firstWhere((state) => state == BluetoothBondState.bonded,
              orElse: () => BluetoothBondState.none)
          .timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          AirocDataLogger.instance.w('BLE', 'Bond timeout, checking current state…');
          return BluetoothBondState.none;
        },
      );

      final isBonded = bondState == BluetoothBondState.bonded;
      AirocDataLogger.instance.i('BLE', 'Bond ${isBonded ? "success" : "failed"}: $bondState');

      // Keep device connected for immediate OTA, user can navigate back to disconnect
      return isBonded;
    } catch (e) {
      AirocDataLogger.instance.e('BLE', 'Pairing failed: $e');
      return false;
    }
  }

  /// Get the current bond state of the device
  Future<String> getDeviceBondState(AirocDevice device) async {
    // iOS/macOS 无法查询 bondState，返回连接状态作为近似。
    if (!_isAndroid) {
      return device.device.isConnected ? 'connected' : 'disconnected';
    }
    final state = await device.device.bondState.first;
    return state.toString();
  }

  void cancelOta() {
    _activeService?.cancel();
  }

  Future<void> dispose() async {
    await _activeService?.dispose();
    await scanner.dispose();
  }
}
