import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/airoc_device.dart';
import '../ota/example_ota_manager.dart';
import 'ota_screen.dart';
import 'widgets/device_list_item.dart';

/// Device scan screen - scans for BLE devices and navigates to OTA upgrade screen
class DeviceScanScreen extends StatefulWidget {
  final ExampleOtaManager manager;

  const DeviceScanScreen({
    super.key,
    required this.manager,
  });

  @override
  State<DeviceScanScreen> createState() => _DeviceScanScreenState();
}

class _DeviceScanScreenState extends State<DeviceScanScreen> {
  StreamSubscription<List<AirocDevice>>? _devicesSubscription;
  List<AirocDevice> _devices = const [];
  bool _scanning = false;
  bool _permissionReady = false;
  bool _scanCompleted = false;
  String? _scanError;

  static const Duration _appleScanRetryDelay = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS || Platform.isMacOS) {
      _permissionReady = true;
    }
    _subscribeToScanner(widget.manager);
  }

  void _subscribeToScanner(ExampleOtaManager manager) {
    _devicesSubscription = manager.scanner.devicesStream.listen((devices) {
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _scanError = null;
      });
    }, onError: (Object error) {
      if (!mounted) return;
      setState(() {
        _scanError = error.toString();
        _scanning = false;
      });
    });
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    super.dispose();
  }

  Future<void> _ensurePermissions() async {
    bool granted = false;
    try {
      granted = await widget.manager.ensurePermissions();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Permission request failed: $error')),
        );
      }
    }
    if (!mounted) return;
    setState(() {
      _permissionReady = granted;
    });
  }

  Future<void> _scan() async {
    if (Platform.isAndroid) {
      await _ensurePermissions();
      if (!_permissionReady) return;
    }

    setState(() {
      _scanning = true;
      _scanCompleted = false;
      _scanError = null;
      _devices = const [];
    });
    try {
      await _startScanWithAppleRetry();
    } catch (error) {
      if (mounted) {
        setState(() {
          _scanError = error.toString();
        });
      }
    }
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _scanCompleted = true;
    });
  }

  Future<void> _startScanWithAppleRetry() async {
    try {
      await widget.manager.startScan(otaOnly: false);
    } catch (_) {
      if (!Platform.isIOS && !Platform.isMacOS) {
        rethrow;
      }
      await Future<void>.delayed(_appleScanRetryDelay);
      await widget.manager.startScan(otaOnly: false);
    }
  }

  /// Navigate to OTA upgrade screen with selected device
  Future<void> _openOtaUpgrade(AirocDevice device) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OtaScreen(
          device: device,
          manager: widget.manager,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_scanning) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Scanning for BLE devices…'),
          ],
        ),
      );
    }
    if (_scanError != null) {
      return Center(
        child: Text(_scanError!, textAlign: TextAlign.center),
      );
    }
    if (_scanCompleted) {
      return const Center(
        child: Text('No devices found.'),
      );
    }
    return const Center(
      child: Text('Tap "Scan Devices" to start scanning.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AIROC OTA Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scan control card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (Platform.isAndroid) ...[
                      OutlinedButton.icon(
                        onPressed: _ensurePermissions,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: Text(
                          _permissionReady
                              ? 'Permissions Ready ✓'
                              : 'Grant Permissions',
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        FilledButton.icon(
                          onPressed: _scanning ? null : _scan,
                          icon: const Icon(Icons.search),
                          label: Text(_scanning ? 'Scanning…' : 'Scan Devices'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Discovered Devices',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _devices.isEmpty
                  ? _buildEmptyState()
                  : ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (context, index) => DeviceListItem(
                        device: _devices[index],
                        onTap: () => _openOtaUpgrade(_devices[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
