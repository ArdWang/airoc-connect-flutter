import 'package:flutter/material.dart';

import '../../models/airoc_device.dart';

class DeviceListItem extends StatelessWidget {
  final AirocDevice device;
  final VoidCallback? onTap;

  const DeviceListItem({
    super.key,
    required this.device,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          child: Text('${device.signalStrengthPercent}%'),
        ),
        title: Text(device.name),
        subtitle: Text('${device.id}\nRSSI: ${device.rssi} dBm'),
        isThreeLine: true,
        trailing: device.hasOtaService
            ? const Chip(label: Text('OTA'))
            : const Chip(label: Text('BLE')),
      ),
    );
  }
}
