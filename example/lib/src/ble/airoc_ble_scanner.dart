import 'dart:async';
import 'dart:io';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../models/airoc_device.dart';

class AirocBleScanner {
  static const List<String> _allowedNamePrefixes = <String>[
    'blue',
    'ota',
    'r',
    'sc',
  ];

  final StreamController<List<AirocDevice>> _devicesController =
      StreamController<List<AirocDevice>>.broadcast();
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  final Guid _otaServiceGuid;

  AirocBleScanner({
    String otaServiceUuid = AirocOtaConstants.otaServiceUuid,
  }) : _otaServiceGuid = Guid(otaServiceUuid);

  Stream<List<AirocDevice>> get devicesStream => _devicesController.stream;

  Future<void> startScan({
    Duration timeout = const Duration(seconds: 10),
    bool otaOnly = false,
  }) async {
    await stopScan();

    await _ensureAdapterReady();

    _scanSubscription = FlutterBluePlus.onScanResults.listen((results) {
      final devices = results
          .map(_fromScanResult)
          .where((device) => _matchesAllowedPrefix(device.name))
          .where((device) => !otaOnly || device.hasOtaService)
          .toList()
        ..sort((a, b) {
          final otaCompare =
              (b.hasOtaService ? 1 : 0).compareTo(a.hasOtaService ? 1 : 0);
          if (otaCompare != 0) return otaCompare;
          return b.rssi.compareTo(a.rssi);
        });
      if (!_devicesController.isClosed) {
        _devicesController.add(devices);
      }
    }, onError: (Object error) {
      if (!_devicesController.isClosed) {
        _devicesController.addError(error);
      }
    });

    await FlutterBluePlus.startScan(
      timeout: timeout,
      androidUsesFineLocation: false,
    );
  }

  Future<void> _ensureAdapterReady() async {
    final adapterState = await FlutterBluePlus.adapterState.first;
    if (adapterState == BluetoothAdapterState.on) {
      return;
    }

    // Apple platforms can briefly report a non-ready state right after launch.
    final waitDuration =
        (Platform.isIOS || Platform.isMacOS)
            ? const Duration(seconds: 5)
            : const Duration(seconds: 2);

    try {
      await FlutterBluePlus.adapterState
          .where((state) => state == BluetoothAdapterState.on)
          .first
          .timeout(waitDuration);
      return;
    } on TimeoutException {
      final latest = await FlutterBluePlus.adapterState.first;
      throw StateError(
        'Bluetooth adapter is not on (state: $latest). '
        'Please enable Bluetooth and try again.',
      );
    }
  }

  Future<void> stopScan() async {
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }
  }

  Future<void> dispose() async {
    await stopScan();
    await _devicesController.close();
  }

  AirocDevice _fromScanResult(ScanResult result) {
    final serviceUuids = result.advertisementData.serviceUuids;
    final hasOtaService = serviceUuids.contains(_otaServiceGuid);
    final name = result.advertisementData.advName.isNotEmpty
        ? result.advertisementData.advName
        : (result.device.platformName.isNotEmpty
            ? result.device.platformName
            : 'Unknown device (${result.device.remoteId.str})');

    return AirocDevice(
      device: result.device,
      name: name,
      id: result.device.remoteId.str,
      rssi: result.rssi,
      hasOtaService: hasOtaService,
      advertisementData: result.advertisementData,
    );
  }

  bool _matchesAllowedPrefix(String name) {
    final normalized = name.trim().toLowerCase();
    if (normalized.isEmpty || normalized == 'unknown device') {
      return false;
    }
    return _allowedNamePrefixes.any(normalized.startsWith);
  }
}
