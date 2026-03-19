import 'dart:async';
import 'dart:io';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter/material.dart';

import 'src/models/airoc_device.dart';
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
      home: const UuidSelectionScreen(),
    );
  }
}

class UuidSelectionScreen extends StatefulWidget {
  const UuidSelectionScreen({super.key});

  @override
  State<UuidSelectionScreen> createState() => _UuidSelectionScreenState();
}

class _UuidSelectionScreenState extends State<UuidSelectionScreen> {
  final ExampleOtaManager _discoveryManager = ExampleOtaManager();
  StreamSubscription<List<AirocDevice>>? _devicesSubscription;

  List<AirocDevice> _devices = const [];
  bool _isScanning = false;
  bool _isLoadingUuids = false;
  String? _error;

  AirocDevice? _selectedDevice;
  List<_ServiceWithCharacteristics> _services = const [];
  String? _selectedServiceUuid;
  String? _selectedCharacteristicUuid;

  static const Duration _appleScanRetryDelay = Duration(milliseconds: 800);

  @override
  void initState() {
    super.initState();
    _devicesSubscription = _discoveryManager.scanner.devicesStream.listen(
      (devices) {
        if (!mounted) return;
        setState(() {
          _devices = devices;
          _error = null;
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _error = 'Scan failed: $e';
          _isScanning = false;
        });
      },
    );
  }

  @override
  void dispose() {
    _devicesSubscription?.cancel();
    _discoveryManager.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _error = null;
      _isScanning = true;
      _selectedDevice = null;
      _services = const [];
      _selectedServiceUuid = null;
      _selectedCharacteristicUuid = null;
    });

    if (Platform.isAndroid) {
      final granted = await _discoveryManager.ensurePermissions();
      if (!granted) {
        setState(() {
          _isScanning = false;
          _error =
              'Bluetooth permissions are required. Please grant and try again.';
        });
        return;
      }
    }

    try {
      await _startScanWithAppleRetry();
    } catch (e) {
      setState(() {
        _error = 'Scan failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isScanning = false;
        });
      }
    }
  }

  Future<void> _startScanWithAppleRetry() async {
    try {
      await _discoveryManager.startScan(otaOnly: false);
    } catch (_) {
      if (!Platform.isIOS && !Platform.isMacOS) {
        rethrow;
      }
      await Future<void>.delayed(_appleScanRetryDelay);
      await _discoveryManager.startScan(otaOnly: false);
    }
  }

  Future<void> _loadUuidsFromDevice(AirocDevice device) async {
    setState(() {
      _isLoadingUuids = true;
      _selectedDevice = device;
      _services = const [];
      _selectedServiceUuid = null;
      _selectedCharacteristicUuid = null;
      _error = null;
    });

    final bluetoothDevice = device.device;
    try {
      if (bluetoothDevice.isDisconnected) {
        await bluetoothDevice.connect();
      }
      final discoveredServices = await bluetoothDevice.discoverServices();

      final services = discoveredServices
          .where((s) => s.characteristics.isNotEmpty)
          .map(
            (s) => _ServiceWithCharacteristics(
              serviceUuid: s.uuid.toString(),
              characteristicUuids:
                  s.characteristics.map((c) => c.uuid.toString()).toList(),
            ),
          )
          .toList();

      if (services.isEmpty) {
        setState(() {
          _error = 'No discoverable service/characteristic UUID found.';
        });
        return;
      }

      final preferredService = services.firstWhere(
        (s) => s.serviceUuid.toLowerCase() ==
            AirocOtaConstants.otaServiceUuid.toLowerCase(),
        orElse: () => services.first,
      );
      final preferredChar = preferredService.characteristicUuids.firstWhere(
        (c) => c.toLowerCase() ==
            AirocOtaConstants.otaCharacteristicUuid.toLowerCase(),
        orElse: () => preferredService.characteristicUuids.first,
      );

      setState(() {
        _services = services;
        _selectedServiceUuid = preferredService.serviceUuid;
        _selectedCharacteristicUuid = preferredChar;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to read UUIDs: $e';
      });
    } finally {
      if (bluetoothDevice.isConnected) {
        await bluetoothDevice.disconnect();
      }
      if (mounted) {
        setState(() {
          _isLoadingUuids = false;
        });
      }
    }
  }

  List<String> get _currentCharacteristicOptions {
    final serviceUuid = _selectedServiceUuid;
    if (serviceUuid == null) return const [];
    final service = _services.firstWhere(
      (s) => s.serviceUuid == serviceUuid,
      orElse: () => const _ServiceWithCharacteristics(
        serviceUuid: '',
        characteristicUuids: <String>[],
      ),
    );
    return service.characteristicUuids;
  }

  Future<void> _openOtaScreen() async {
    final serviceUuid = _selectedServiceUuid;
    final characteristicUuid = _selectedCharacteristicUuid;
    if (serviceUuid == null || characteristicUuid == null) {
      return;
    }

    final manager = ExampleOtaManager(
      otaServiceUuid: serviceUuid,
      otaCharacteristicUuid: characteristicUuid,
    );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeviceScanScreen(manager: manager),
      ),
    );

    await manager.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canContinue =
        _selectedServiceUuid != null && _selectedCharacteristicUuid != null;

    return Scaffold(
      appBar: AppBar(title: const Text('AIROC OTA Example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Step 1: Scan devices and read UUIDs',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _isScanning ? null : _startScan,
                      icon: const Icon(Icons.search),
                      label: Text(_isScanning ? 'Scanning…' : 'Scan Devices'),
                    ),
                    const SizedBox(height: 12),
                    if (_devices.isEmpty)
                      const Text('No devices yet. Tap "Scan Devices".')
                    else
                      ..._devices.map(
                        (d) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(d.name),
                          subtitle: Text('${d.id} • RSSI ${d.rssi} dBm'),
                          trailing: OutlinedButton(
                            onPressed: _isLoadingUuids
                                ? null
                                : () => _loadUuidsFromDevice(d),
                            child: const Text('Read UUIDs'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Step 2: Choose discovered UUIDs',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedDevice == null
                          ? 'Selected device: none'
                          : 'Selected device: ${_selectedDevice!.name}',
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedServiceUuid,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Service UUID',
                        border: OutlineInputBorder(),
                      ),
                      selectedItemBuilder: (context) => _services
                          .map(
                            (s) => Text(
                              s.serviceUuid,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                          .toList(),
                      items: _services
                          .map(
                            (s) => DropdownMenuItem<String>(
                              value: s.serviceUuid,
                              child: Text(
                                s.serviceUuid,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _services.isEmpty
                          ? null
                          : (value) {
                              if (value == null) return;
                              final chars = _services
                                  .firstWhere((s) => s.serviceUuid == value)
                                  .characteristicUuids;
                              setState(() {
                                _selectedServiceUuid = value;
                                _selectedCharacteristicUuid =
                                    chars.isNotEmpty ? chars.first : null;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCharacteristicUuid,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Characteristic UUID',
                        border: OutlineInputBorder(),
                      ),
                      selectedItemBuilder: (context) =>
                          _currentCharacteristicOptions
                              .map(
                                (c) => Text(
                                  c,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              )
                              .toList(),
                      items: _currentCharacteristicOptions
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c,
                              child: Text(
                                c,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _currentCharacteristicOptions.isEmpty
                          ? null
                          : (value) {
                              setState(() {
                                _selectedCharacteristicUuid = value;
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: canContinue ? _openOtaScreen : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Continue to OTA'),
                    ),
                  ],
                ),
              ),
            ),
            if (_isLoadingUuids) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ServiceWithCharacteristics {
  final String serviceUuid;
  final List<String> characteristicUuids;

  const _ServiceWithCharacteristics({
    required this.serviceUuid,
    required this.characteristicUuids,
  });
}
