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
    // First ensure device is fully disconnected before reconnecting
    // This prevents GATT 133 errors from connection conflicts
    if (device.isConnected) {
      AirocDataLogger.instance.i('BLE', 'Device already connected, disconnecting first…');
      await device.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Clear GATT cache by waiting a bit
    await Future.delayed(const Duration(milliseconds: 200));

    AirocDataLogger.instance
        .i('BLE', 'Connecting to ${device.remoteId.str} (${device.platformName})…');
    await device.connect(
      timeout: AirocOtaConstants.connectTimeout,
      mtu: null,
    );
    AirocDataLogger.instance
        .i('BLE', 'Connected ✓  remoteId=${device.remoteId.str}');

    // Wait a bit for bond state to update after connection
    // The bondState stream may return stale data immediately after connect
    await Future.delayed(const Duration(milliseconds: 300));

    // Check bond state AFTER connection is established with fresh value
    final bondState = await device.bondState.first;
    AirocDataLogger.instance.i('BLE', 'Bond state: $bondState');

    // Only pair if not bonded - use string comparison for reliability
    final isBonded = bondState.toString().contains('bonded');
    if (!isBonded) {
      AirocDataLogger.instance.w('BLE', 'Device not bonded! Pairing now…');
      await device.createBond();
      // Wait up to 10 seconds for pairing to complete
      for (int i = 0; i < 20; i++) {
        final state = await device.bondState.first;
        if (state.toString().contains('bonded')) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
      AirocDataLogger.instance.i('BLE', 'Paired ✓');
    } else {
      AirocDataLogger.instance.i('BLE', 'Device already bonded ✓');
    }
  }

  /// Check if the device is currently bonded/paired
  Future<bool> get isBonded async {
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

    final characteristicList = otaServiceList.first.characteristics.where(
      (c) => c.uuid == _otaCharacteristicGuid,
    );
    if (characteristicList.isEmpty) {
      throw const AirocOtaProtocolException('OTA characteristic was not found.');
    }
    _characteristic = characteristicList.first;
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
    return _requireCharacteristic().write(
      data,
      withoutResponse: withoutResponse,
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
