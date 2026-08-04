import 'dart:async';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter/material.dart';

import '../models/airoc_device.dart';
import '../ota/example_ota_manager.dart';
import 'widgets/data_log_viewer.dart';
import 'widgets/ota_progress_bar.dart';

/// OTA Upgrade screen with workflow:
/// 1. Pair device (manual pairing)
/// 2. Discover services
/// 3. Select firmware file
/// 4. Start OTA upgrade
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
  // Pairing state
  bool _isBonded = false;
  bool _isBonding = false;
  bool _isUnpairing = false;

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
    // Check if device is already bonded
    _checkInitialBondState();
  }

  /// Check if the device is already paired (e.g. from a previous session)
  Future<void> _checkInitialBondState() async {
    try {
      final isBonded = await widget.manager.isDeviceBonded(widget.device);
      if (!mounted) return;
      setState(() {
        _isBonded = isBonded;
      });
    } catch (_) {
      // Device may be out of range - that's fine, user will pair manually
    }
  }

  /// Step 1: Pair device manually
  Future<void> _pairDevice() async {
    if (_isBonding || _isBonded) return;

    setState(() {
      _isBonding = true;
    });

    try {
      final success = await widget.manager.pairDevice(widget.device);
      if (!mounted) return;
      setState(() {
        _isBonding = false;
        _isBonded = success;
      });

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Device paired successfully ✓'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pairing failed. Please try again.'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isBonding = false;
        _isBonded = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pairing error: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  /// Step 2: Discover services and characteristics
  Future<void> _loadUuidsFromDevice() async {
    if (!_isBonded) return;

    setState(() {
      _isLoadingUuids = true;
      _uuidError = null;
      _services = const [];
      _selectedServiceUuid = null;
      _selectedCharacteristicUuid = null;
    });

    final bluetoothDevice = widget.device.device;
    try {
      // Connect to device (pairing already done in step 1)
      if (bluetoothDevice.isDisconnected) {
        await bluetoothDevice.connect(
          timeout: const Duration(seconds: 10),
          mtu: null,
        );
      }

      // Discover services
      final discoveredServices = await bluetoothDevice.discoverServices();

      // Filter: only include characteristics that support WRITE and NOTIFY
      final services = <_ServiceWithCharacteristics>[];
      for (final service in discoveredServices) {
        final validChars = service.characteristics.where((c) {
          final hasWrite = c.properties.write || c.properties.writeWithoutResponse;
          final hasNotify = c.properties.notify || c.properties.indicate;
          return hasWrite && hasNotify;
        }).toList();
        if (validChars.isNotEmpty) {
          services.add(_ServiceWithCharacteristics(
            serviceUuid: service.uuid.toString(),
            characteristicUuids: validChars.map((c) => c.uuid.toString()).toList(),
          ));
        }
      }

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
    }
    // Keep connection alive — OTA will reuse the same connection without
    // reconnecting, just like iOS CoreBluetooth does. This avoids Android
    // re-triggering the pairing dialog on reconnect.
    if (mounted) {
      setState(() {
        _isLoadingUuids = false;
      });
    }
  }

  /// Step 3: Select firmware file
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

  /// Step 4: Start OTA upgrade
  Future<void> _runUpgrade() async {
    if (!_canStartOta) return;

    // Device is already connected from Step 2 (service discovery).
    // The transport will reuse the existing connection — no disconnect/reconnect
    // needed. This matches iOS CoreBluetooth behavior: one continuous connection.

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

    // Unpair the device after OTA completes
    if (mounted) {
      setState(() => _isUnpairing = true);
      AirocDataLogger.instance.i('UI', 'OTA finished, unpairing device…');
      final unpaired = await widget.manager.unpairDevice(widget.device);
      if (!mounted) return;
      setState(() {
        _isUnpairing = false;
        _isBonded = _isBonded && !unpaired;
      });
      AirocDataLogger.instance.i('UI', 'Unpair ${unpaired ? "succeeded" : "failed"}');
    }

    // Auto-navigate back to scan screen after OTA completes
    if (mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    }
  }

  /// Check if Step 2 (discover services) can be started
  bool get _canDiscoverServices => _isBonded && !_isBonding;

  /// Check if OTA can be started
  bool get _canStartOta =>
      _isBonded &&
      _selectedServiceUuid != null &&
      _selectedCharacteristicUuid != null &&
      _selectedFile != null &&
      !_running;

  /// Get current step hint
  String get _currentHint {
    if (!_isBonded) {
      return 'Step 1: Tap "Pair Device" to pair with the device first.';
    }
    if (_services.isEmpty) {
      return 'Step 2: Tap "Discover Services" to read device UUIDs.';
    }
    if (_selectedFile == null) {
      return 'Step 3: Tap "Select Firmware" to choose a firmware file.';
    }
    if (!_canStartOta) {
      return 'Step 4: Complete all steps above, then tap "Start OTA Upgrade".';
    }
    return 'Ready! Tap "Start OTA Upgrade" to begin the firmware update.';
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
                // Bond state chip
                _buildBondStateChip(),
              ],
            ),
          ),

          // Main scrollable content
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListView(
                children: [
                  // Step 1: Pair Device Card
                  _buildCard(
                    title: 'Step 1: Pair Device',
                    icon: _isBonded ? Icons.check_circle : Icons.bluetooth_connected,
                    iconColor: _isBonded ? Colors.green : Colors.indigo,
                    isLoading: _isBonding,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isBonded
                              ? 'Device paired successfully ✓'
                              : 'Pair with the device before proceeding',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        // Pair button
                        if (_isBonded)
                          FilledButton.tonalIcon(
                            onPressed: null,
                            icon: const Icon(Icons.check_circle, size: 18),
                            label: const Text('Paired ✓'),
                          )
                        else if (_isBonding)
                          FilledButton.tonalIcon(
                            onPressed: null,
                            icon: const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            label: const Text('Pairing…'),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: _pairDevice,
                            icon: const Icon(Icons.bluetooth_connected),
                            label: const Text('Pair Device'),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Step 2: Discover Services Card
                  _buildCard(
                    title: 'Step 2: Discover Services',
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
                              : 'Read device service UUIDs',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed:
                              (_isLoadingUuids || !_canDiscoverServices)
                                  ? null
                                  : _loadUuidsFromDevice,
                          icon: _isLoadingUuids
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.search),
                          label: const Text('Discover Services'),
                        ),
                        if (!_canDiscoverServices && !_isLoadingUuids) ...[
                          const SizedBox(height: 4),
                          Text(
                            '⚠️ Pair device first (Step 1)',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.orange,
                                ),
                          ),
                        ],
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

                  // Step 3: Select Firmware Card
                  _buildCard(
                    title: 'Step 3: Select Firmware',
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

                  // Step 4: Start OTA Card
                  _buildCard(
                    title: 'Step 4: Start OTA Upgrade',
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
                        if (!_isBonded) ...[
                          const SizedBox(height: 4),
                          Text(
                            '⚠️ Pair device first (Step 1)',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.orange,
                                ),
                          ),
                        ] else if (_services.isEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '⚠️ Discover services first (Step 2)',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.orange,
                                ),
                          ),
                        ] else if (_selectedFile == null) ...[
                          const SizedBox(height: 4),
                          Text(
                            '⚠️ Select firmware file first (Step 3)',
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

  Widget _buildBondStateChip() {
    if (_isUnpairing) {
      return const Chip(
        avatar: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
        label: Text('Unpairing…'),
        backgroundColor: Colors.orange,
        labelStyle: TextStyle(color: Colors.white, fontSize: 12),
      );
    }
    if (_isBonding) {
      return const Chip(
        avatar: SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
        label: Text('Pairing…'),
        backgroundColor: Colors.orange,
        labelStyle: TextStyle(color: Colors.white, fontSize: 12),
      );
    }
    if (_isBonded) {
      return const Chip(
        avatar: Icon(Icons.check_circle, size: 16, color: Colors.white),
        label: Text('Paired'),
        backgroundColor: Colors.green,
        labelStyle: TextStyle(color: Colors.white, fontSize: 12),
      );
    }
    return Chip(
      avatar: Icon(
        Icons.bluetooth_disabled,
        size: 16,
        color: Colors.red.shade300,
      ),
      label: const Text('Not Paired'),
      backgroundColor: Colors.grey.shade200,
      labelStyle: TextStyle(color: Colors.grey.shade700, fontSize: 12),
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
