import 'dart:io' show Platform;
import 'dart:async';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class FlutterBluePlusOtaTransport implements AirocOtaTransport {
  final BluetoothDevice device;
  final String otaServiceUuid;
  final String otaCharacteristicUuid;
  final Guid _otaServiceGuid;
  final Guid _otaCharacteristicGuid;
  BluetoothCharacteristic? _characteristic;

  FlutterBluePlusOtaTransport(
    this.device, {
    this.otaServiceUuid = AirocOtaConstants.otaServiceUuid,
    this.otaCharacteristicUuid = AirocOtaConstants.otaCharacteristicUuid,
  })  : _otaServiceGuid = Guid(otaServiceUuid),
        _otaCharacteristicGuid = Guid(otaCharacteristicUuid);

  @override
  Stream<List<int>> get notifications {
    final characteristic = _characteristic;
    if (characteristic == null) {
      return const Stream<List<int>>.empty();
    }
    return characteristic.onValueReceived.where((value) => value.isNotEmpty);
  }

  @override
  Future<void> connect() async {
    // If already connected, reuse the existing connection (like iOS does).
    // This avoids disconnect/reconnect cycles that trigger repeat pairing on Android.
    if (device.isConnected) {
      AirocDataLogger.instance.i('BLE', 'Device already connected, reusing existing connection ✓');

      // Verify bond state on the live connection (Android only).
      // iOS/macOS 无法查询 bondState，配对由系统在访问加密特征值时隐式完成。
      if (Platform.isAndroid) {
        final bondState = await device.bondState.first;
        final isBonded = bondState.toString().contains('bonded');
        if (!isBonded) {
          AirocDataLogger.instance.w(
            'BLE',
            'Device is NOT bonded ($bondState). '
            'Please pair with the device before starting OTA upgrade.',
          );
          throw const AirocOtaProtocolException(
            'Device is not paired. Please go back to Step 1 and pair the device first.',
          );
        }
        AirocDataLogger.instance.i('BLE', 'Device is bonded ✓');
      }
      return;
    }

    // Device is not connected — connect fresh
    AirocDataLogger.instance
        .i('BLE', 'Connecting to ${device.remoteId.str} (${device.platformName})…');
    await device.connect(
      timeout: AirocOtaConstants.connectTimeout,
      mtu: null,
    );
    AirocDataLogger.instance
        .i('BLE', 'Connected ✓  remoteId=${device.remoteId.str}');

    // Wait for bond state to settle after connection
    await Future.delayed(const Duration(milliseconds: 300));

    // Verify the device is bonded (Android only).
    // On Android, pairing should be done externally before OTA;
    // on Apple platforms pairing is implicit when an encrypted characteristic
    // is accessed during discover()/enableNotifications()/write().
    if (Platform.isAndroid) {
      final bondState = await device.bondState.first;
      final isBonded = bondState.toString().contains('bonded');
      if (!isBonded) {
        AirocDataLogger.instance.w(
          'BLE',
          'Device is NOT bonded ($bondState). '
          'Please pair with the device before starting OTA upgrade.',
        );
        throw const AirocOtaProtocolException(
          'Device is not paired. Please go back to Step 1 and pair the device first.',
        );
      }
      AirocDataLogger.instance.i('BLE', 'Device is bonded ✓');
    }
  }

  /// Check if the device is currently bonded/paired
  Future<bool> get isBonded async {
    // iOS/macOS 无法查询 bondState，用"已连接"作为就绪信号。
    if (!Platform.isAndroid) {
      return device.isConnected;
    }
    final state = await device.bondState.first;
    return state == BluetoothBondState.bonded;
  }

  @override
  Future<void> discover() async {
    AirocDataLogger.instance.i('BLE', 'Discovering services…');

    final services = await device.discoverServices();
    final otaServiceList =
        services.where((service) => service.uuid == _otaServiceGuid);
    if (otaServiceList.isEmpty) {
      throw const AirocOtaProtocolException('OTA service was not found.');
    }

    final otaService = otaServiceList.first;
    final allChars = otaService.characteristics;

    // Log all discovered characteristics for debugging
    for (final c in allChars) {
      AirocDataLogger.instance.v(
        'BLE',
        'Characteristic: ${c.uuid}  properties=${c.properties}',
      );
    }

    // Find characteristic matching OTA UUID that supports WRITE and NOTIFY
    final characteristicList = allChars.where(
      (c) => c.uuid == _otaCharacteristicGuid,
    );

    if (characteristicList.isEmpty) {
      throw const AirocOtaProtocolException('OTA characteristic was not found.');
    }

    // Pick the first characteristic that has both WRITE and NOTIFY properties
    BluetoothCharacteristic? bestChar;
    for (final c in characteristicList) {
      final hasWrite = c.properties.write || c.properties.writeWithoutResponse;
      final hasNotify = c.properties.notify || c.properties.indicate;
      AirocDataLogger.instance.i(
        'BLE',
        'OTA char ${c.uuid}: write=$hasWrite notify=$hasNotify  '
        'props=${c.properties}',
      );
      if (hasWrite && hasNotify) {
        bestChar = c;
        break;
      }
    }

    if (bestChar == null) {
      // Fallback to first matching characteristic even without proper properties
      bestChar = characteristicList.first;
      AirocDataLogger.instance.w(
        'BLE',
        'OTA characteristic found but missing WRITE or NOTIFY property! '
        'This may cause OTA to fail. Using ${bestChar.uuid} anyway.',
      );
    }

    _characteristic = bestChar;
    AirocDataLogger.instance.i('BLE', 'Selected characteristic: ${_characteristic!.uuid}');
  }

  @override
  Future<void> enableNotifications() async {
    final characteristic = _requireCharacteristic();
    if (!characteristic.isNotifying) {
      await characteristic.setNotifyValue(true);
    }
  }

  @override
  Future<int> requestMtu(int desiredMtu) async {
    if (!kIsWeb && Platform.isAndroid) {
      return device.requestMtu(desiredMtu);
    }
    return device.mtuNow;
  }

  @override
  Future<void> write(List<int> data, {bool withoutResponse = false}) {
    final char = _requireCharacteristic();
    // Auto-detect: if characteristic doesn't support regular WRITE,
    // fall back to WRITE_WITHOUT_RESPONSE
    final useWithoutResponse = withoutResponse ||
        (!char.properties.write && char.properties.writeWithoutResponse);
    if (useWithoutResponse && !withoutResponse) {
      AirocDataLogger.instance.v(
        'BLE',
        'Characteristic only supports writeWithoutResponse, using that mode',
      );
    }
    return char.write(
      data,
      withoutResponse: useWithoutResponse,
    );
  }

  @override
  Future<void> disconnect() async {
    if (device.isConnected) {
      await device.disconnect();
    }
  }

  BluetoothCharacteristic _requireCharacteristic() {
    final characteristic = _characteristic;
    if (characteristic == null) {
      throw const AirocOtaProtocolException(
        'OTA characteristic is not ready. Call discover() first.',
      );
    }
    return characteristic;
  }
}
