import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class AirocDevice {
  final BluetoothDevice device;
  final String name;
  final String id;
  final int rssi;
  final bool hasOtaService;
  final AdvertisementData? advertisementData;

  const AirocDevice({
    required this.device,
    required this.name,
    required this.id,
    required this.rssi,
    this.hasOtaService = false,
    this.advertisementData,
  });

  int get signalStrengthPercent {
    const minRssi = -100;
    const maxRssi = -50;
    final clamped = rssi.clamp(minRssi, maxRssi);
    return ((clamped - minRssi) / (maxRssi - minRssi) * 100).round();
  }
}
