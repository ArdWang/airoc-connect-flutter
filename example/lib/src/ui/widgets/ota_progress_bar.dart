import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter/material.dart';

class OtaProgressBar extends StatelessWidget {
  final OtaProgress progress;

  const OtaProgressBar({
    super.key,
    required this.progress,
  });

  Color _statusColor(BuildContext context) {
    switch (progress.status) {
      case OtaStatus.success:
        return Colors.green;
      case OtaStatus.failed:
      case OtaStatus.aborted:
        return Theme.of(context).colorScheme.error;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: progress.progress.clamp(0.0, 100.0) / 100,
          minHeight: 10,
          color: color,
        ),
        const SizedBox(height: 8),
        Text(
          '${progress.progress.toStringAsFixed(1)}% • ${progress.status.name}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(progress.message),
        if (progress.totalBytes > 0) ...[
          const SizedBox(height: 4),
          Text('${progress.bytesTransferred} / ${progress.totalBytes} bytes'),
        ],
      ],
    );
  }
}
