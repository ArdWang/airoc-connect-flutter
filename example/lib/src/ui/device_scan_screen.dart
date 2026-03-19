import 'dart:async';
import 'dart:io';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter/material.dart';

import '../models/airoc_device.dart';
import '../ota/example_ota_manager.dart';
import 'ota_screen.dart';
import 'widgets/device_list_item.dart';

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
  OtaFile? _selectedFile;
  bool _scanning = false;
  bool _permissionReady = false;
  bool _otaOnly = false;
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

  @override
  void didUpdateWidget(DeviceScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manager != widget.manager) {
      _devicesSubscription?.cancel();
      _subscribeToScanner(widget.manager);
    }
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
      granted = false;
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

  Future<void> _pickFirmware() async {
    OtaFile? file;
    try {
      file = await widget.manager.pickFirmwareFile();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load firmware file: $error'),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }
    if (!mounted || file == null) return;
    setState(() {
      _selectedFile = file;
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
      await widget.manager.startScan(otaOnly: _otaOnly);
    } catch (_) {
      if (!Platform.isIOS && !Platform.isMacOS) {
        rethrow;
      }
      await Future<void>.delayed(_appleScanRetryDelay);
      await widget.manager.startScan(otaOnly: _otaOnly);
    }
  }

  Future<void> _openUpgrade(AirocDevice device) async {
    final file = _selectedFile;
    if (file == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a .cyacd2 or .cyacd firmware file first.'),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OtaScreen(
          device: device,
          file: file,
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
      return Center(
        child: Text(
          _otaOnly
              ? 'No AIROC OTA devices found.'
              : 'No devices found (prefix filter: blue/ota/r/sc).',
          textAlign: TextAlign.center,
        ),
      );
    }
    return const Center(
      child: Text('Grant permissions and tap "Scan Devices" to start.'),
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
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Firmware File',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(_selectedFile?.fileName ?? 'No file selected'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _pickFirmware,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Select Firmware'),
                        ),
                        if (Platform.isAndroid)
                          OutlinedButton.icon(
                            onPressed: _ensurePermissions,
                            icon: const Icon(Icons.bluetooth_searching),
                            label: Text(
                              _permissionReady
                                  ? 'Permissions Ready ✓'
                                  : 'Grant Permissions',
                            ),
                          ),
                        FilledButton.icon(
                          onPressed: _scanning ? null : _scan,
                          icon: const Icon(Icons.search),
                          label: Text(_scanning ? 'Scanning…' : 'Scan Devices'),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text('Show OTA-capable devices only'),
                        const Spacer(),
                        Switch(
                          value: _otaOnly,
                          onChanged: _scanning
                              ? null
                              : (value) => setState(() {
                                    _otaOnly = value;
                                    _devices = const [];
                                    _scanCompleted = false;
                                  }),
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
                        onTap: () => _openUpgrade(_devices[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
