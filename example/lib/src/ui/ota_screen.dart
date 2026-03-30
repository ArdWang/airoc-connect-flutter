import 'dart:async';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter/material.dart';

import '../models/airoc_device.dart';
import '../ota/example_ota_manager.dart';
import 'widgets/data_log_viewer.dart';
import 'widgets/ota_progress_bar.dart';

/// OTA Upgrade screen with workflow:
/// 1. Discover services (auto-pair during connection)
/// 2. Select firmware file
/// 3. Start OTA upgrade
class OtaScreen extends StatefulWidget {
  final AirocDevice device;
  final ExampleOtaManager manager;

  const OtaScreen({
    super.key,
    required this.device,
    required this.manager,
  });

  @override
  State<OtaScreen> createState() => _OtaScreenState();
}

class _OtaScreenState extends State<OtaScreen> {
  // UUID discovery
  bool _isLoadingUuids = false;
  String? _uuidError;
  List<_ServiceWithCharacteristics> _services = const [];
  String? _selectedServiceUuid;
  String? _selectedCharacteristicUuid;

  // Firmware file
  OtaFile? _selectedFile;

  // OTA state
  OtaProgress _progress = OtaProgress.idle();
  OtaResult? _result;
  bool _running = false;

  @override
  void initState() {
    super.initState();
  }

  /// Step 1: Discover services and characteristics (includes auto-pair)
  Future<void> _loadUuidsFromDevice() async {
    setState(() {
      _isLoadingUuids = true;
      _uuidError = null;
      _services = const [];
      _selectedServiceUuid = null;
      _selectedCharacteristicUuid = null;
    });

    final bluetoothDevice = widget.device.device;
    try {
      // Ensure connected - system will prompt for pairing if needed
      if (bluetoothDevice.isDisconnected) {
        await bluetoothDevice.connect(
          timeout: const Duration(seconds: 10),
          mtu: null,
        );
      }

      // Discover services
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
          _uuidError = 'No services with characteristics found.';
        });
        return;
      }

      // Auto-select OTA service if found
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
        _uuidError = 'Failed to discover services: $e';
      });
    } finally {
      // Disconnect after reading services - OTA will reconnect
      if (bluetoothDevice.isConnected) {
        await bluetoothDevice.disconnect();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (mounted) {
        setState(() {
          _isLoadingUuids = false;
        });
      }
    }
  }

  /// Step 2: Select firmware file
  Future<void> _selectFirmwareFile() async {
    OtaFile? file;
    try {
      file = await widget.manager.pickFirmwareFile();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load firmware file: $error'),
          duration: const Duration(seconds: 6),
        ),
      );
      return;
    }
    if (!mounted || file == null) return;
    setState(() {
      _selectedFile = file;
    });
  }

  /// Step 3: Start OTA upgrade
  Future<void> _runUpgrade() async {
    if (!_canStartOta) return;

    // Ensure device is disconnected before starting OTA
    if (widget.device.device.isConnected) {
      AirocDataLogger.instance.i('BLE', 'Disconnecting device before OTA…');
      await widget.device.device.disconnect();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    AirocDataLogger.instance.clear();
    AirocDataLogger.instance.i(
      'UI',
      'User started OTA  device=${widget.device.name}  '
      'file=${_selectedFile!.fileName}',
    );

    setState(() {
      _running = true;
      _result = null;
      _progress = const OtaProgress(
        status: OtaStatus.preparingDownload,
        message: 'Preparing OTA…',
      );
    });

    // Use selected UUIDs
    final manager = ExampleOtaManager(
      otaServiceUuid: _selectedServiceUuid ?? AirocOtaConstants.otaServiceUuid,
      otaCharacteristicUuid:
          _selectedCharacteristicUuid ?? AirocOtaConstants.otaCharacteristicUuid,
    );

    final result = await manager.performOta(
      device: widget.device,
      file: _selectedFile!,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => _progress = progress);
      },
    );

    await manager.dispose();

    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });

    // Auto-navigate back to scan screen after OTA completes
    if (mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    }
  }

  /// Check if OTA can be started
  bool get _canStartOta =>
      _selectedServiceUuid != null &&
      _selectedCharacteristicUuid != null &&
      _selectedFile != null &&
      !_running;

  /// Get current step hint
  String get _currentHint {
    if (_services.isEmpty) {
      return 'Step 1: Tap "Discover Services" to read device UUIDs (pairing will happen automatically on first connect).';
    }
    if (_selectedFile == null) {
      return 'Step 2: Tap "Select Firmware" to choose a firmware file.';
    }
    if (!_canStartOta) {
      return 'Step 3: Complete all steps above, then tap "Start OTA Upgrade".';
    }
    return 'Ready! Note: Device may prompt for pairing again when entering bootloader mode - this is normal.';
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OTA Upgrade'),
      ),
      body: Column(
        children: [
          // Device info summary
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.indigo.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.indigo.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.bluetooth_connected, color: Colors.indigo),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.device.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        widget.device.id,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main scrollable content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                children: [
                  // Step 1: Discover UUIDs Card
                  _buildCard(
                    title: 'Step 1: Discover Services',
                    icon: _services.isNotEmpty
                        ? Icons.check_circle
                        : Icons.dns,
                    iconColor: _services.isNotEmpty ? Colors.green : Colors.indigo,
                    isLoading: _isLoadingUuids,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _services.isNotEmpty
                              ? 'Services discovered ✓'
                              : 'Read device service UUIDs (auto-pair on connect)',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _isLoadingUuids ? null : _loadUuidsFromDevice,
                          icon: _isLoadingUuids
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search),
                          label: const Text('Discover Services'),
                        ),
                        if (_services.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          // Service UUID dropdown
                          DropdownButtonFormField<String>(
                            initialValue: _selectedServiceUuid,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Service UUID',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
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
                            onChanged: (value) {
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
                          const SizedBox(height: 8),
                          // Characteristic UUID dropdown
                          DropdownButtonFormField<String>(
                            initialValue: _selectedCharacteristicUuid,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Characteristic UUID',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                            items: _getCurrentCharacteristicOptions()
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
                            onChanged: (value) {
                              setState(() {
                                _selectedCharacteristicUuid = value;
                              });
                            },
                          ),
                        ],
                        if (_uuidError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _uuidError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Step 2: Select Firmware Card
                  _buildCard(
                    title: 'Step 2: Select Firmware',
                    icon: _selectedFile != null
                        ? Icons.check_circle
                        : Icons.upload_file,
                    iconColor: _selectedFile != null ? Colors.green : Colors.indigo,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _selectedFile != null
                              ? _selectedFile!.fileName
                              : 'Select a .cyacd2 or .cyacd file',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _selectFirmwareFile,
                          icon: const Icon(Icons.folder_open),
                          label: const Text('Select Firmware File'),
                        ),
                        if (_selectedFile != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Rows: ${_selectedFile!.rows.length} | Size: ${_selectedFile!.size} bytes',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Step 3: Start OTA Card
                  _buildCard(
                    title: 'Step 3: Start OTA Upgrade',
                    icon: _canStartOta ? Icons.check_circle : Icons.system_update_alt,
                    iconColor: _canStartOta ? Colors.green : Colors.grey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_selectedFile != null) ...[
                          Text(
                            'Target: ${_selectedFile!.fileName}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                        ],
                        FilledButton.icon(
                          onPressed: _canStartOta ? _runUpgrade : null,
                          icon: _running
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.system_update_alt),
                          label: Text(_running ? 'Upgrading…' : 'Start OTA Upgrade'),
                        ),
                        if (_services.isEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '⚠️ Discover services first (Step 1)',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.orange,
                                ),
                          ),
                        ] else if (_selectedFile == null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '⚠️ Select firmware file first (Step 2)',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.orange,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Result card
                  if (result != null) ...[
                    const SizedBox(height: 16),
                    Card(
                      color: result.success
                          ? Colors.green.withValues(alpha: 0.12)
                          : Theme.of(context)
                              .colorScheme
                              .errorContainer
                              .withValues(alpha: 0.7),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.success
                                  ? '✅ Upgrade Succeeded'
                                  : '❌ Upgrade Failed',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Text('Status      : ${result.status.name}'),
                            Text(
                                'Transferred : ${result.bytesTransferred} bytes'),
                            Text(
                                'Duration    : ${result.duration.inMilliseconds} ms'),
                            if (result.errorMessage != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Error: ${result.errorMessage}',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Progress bar
                  if (_running || result != null) ...[
                    const SizedBox(height: 16),
                    OtaProgressBar(progress: _progress),
                  ],

                  // Log viewer
                  const SizedBox(height: 16),
                  DataLogViewer(
                    initiallyExpanded: _running || result != null,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // Bottom hint bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              border: Border(
                top: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, color: Colors.amber.shade900, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentHint,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.amber.shade900,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    required Widget child,
    bool isLoading = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: iconColor, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const Divider(height: 24),
            child,
          ],
        ),
      ),
    );
  }

  List<String> _getCurrentCharacteristicOptions() {
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
}

class _ServiceWithCharacteristics {
  final String serviceUuid;
  final List<String> characteristicUuids;

  const _ServiceWithCharacteristics({
    required this.serviceUuid,
    required this.characteristicUuids,
  });
}
