import 'dart:io' show Platform;

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
    if (device.isDisconnected) {
      AirocDataLogger.instance
          .i('BLE', 'Connecting to ${device.remoteId.str} (${device.platformName})…');
      await device.connect(
        timeout: AirocOtaConstants.connectTimeout,
        mtu: null,
      );
      AirocDataLogger.instance
          .i('BLE', 'Connected ✓  remoteId=${device.remoteId.str}');
    }
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
