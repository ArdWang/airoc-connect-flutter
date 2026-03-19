import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter/material.dart';

import '../models/airoc_device.dart';
import '../ota/example_ota_manager.dart';
import 'widgets/data_log_viewer.dart';
import 'widgets/ota_progress_bar.dart';

class OtaScreen extends StatefulWidget {
  final AirocDevice device;
  final OtaFile file;
  final ExampleOtaManager manager;

  const OtaScreen({
    super.key,
    required this.device,
    required this.file,
    required this.manager,
  });

  @override
  State<OtaScreen> createState() => _OtaScreenState();
}

class _OtaScreenState extends State<OtaScreen> {
  OtaProgress _progress = OtaProgress.idle();
  OtaResult? _result;
  bool _running = false;

  Future<void> _runUpgrade() async {
    AirocDataLogger.instance.clear();
    AirocDataLogger.instance.i(
      'UI',
      'User started OTA  device=${widget.device.name}  '
      'file=${widget.file.fileName}',
    );

    setState(() {
      _running = true;
      _result = null;
      _progress = const OtaProgress(
        status: OtaStatus.preparingDownload,
        message: 'Preparing OTA…',
      );
    });

    final result = await widget.manager.performOta(
      device: widget.device,
      file: widget.file,
      onProgress: (progress) {
        if (!mounted) return;
        setState(() => _progress = progress);
      },
    );

    if (!mounted) return;
    setState(() {
      _running = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return Scaffold(
      appBar: AppBar(title: const Text('AIROC OTA Upgrade')),
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
                    Text(
                      widget.device.name,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(widget.device.id),
                    const SizedBox(height: 8),
                    Text('Firmware  : ${widget.file.fileName}'),
                    Text('File type : ${widget.file.fileType.name}'),
                    Text(
                      'Rows      : ${widget.file.rows.length}  (${widget.file.size} bytes)',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            OtaProgressBar(progress: _progress),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _running ? null : _runUpgrade,
              icon: const Icon(Icons.system_update_alt),
              label: Text(_running ? 'Upgrading…' : 'Start OTA Upgrade'),
            ),
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
                            ? '✅  Upgrade Succeeded'
                            : '❌  Upgrade Failed',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Status      : ${result.status.name}'),
                      Text('Transferred : ${result.bytesTransferred} bytes'),
                      Text('Duration    : ${result.duration.inMilliseconds} ms'),
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
            const SizedBox(height: 16),
            DataLogViewer(initiallyExpanded: _running || result != null),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
