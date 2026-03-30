import 'package:flutter/material.dart';

import 'src/ota/example_ota_manager.dart';
import 'src/ui/device_scan_screen.dart';

void main() {
  runApp(const AirocOtaExampleApp());
}

class AirocOtaExampleApp extends StatelessWidget {
  const AirocOtaExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AIROC OTA Example',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const DeviceScanScreenWrapper(),
    );
  }
}

/// Wrapper to create the ExampleOtaManager and pass it to DeviceScanScreen
class DeviceScanScreenWrapper extends StatefulWidget {
  const DeviceScanScreenWrapper({super.key});

  @override
  State<DeviceScanScreenWrapper> createState() => _DeviceScanScreenWrapperState();
}

class _DeviceScanScreenWrapperState extends State<DeviceScanScreenWrapper> {
  late final ExampleOtaManager _manager;

  @override
  void initState() {
    super.initState();
    _manager = ExampleOtaManager();
  }

  @override
  void dispose() {
    _manager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DeviceScanScreen(manager: _manager);
  }
}
