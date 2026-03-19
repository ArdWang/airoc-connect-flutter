import 'dart:async';

import 'package:airoc_connect_flutter/airoc_connect_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DataLogViewer extends StatefulWidget {
  final bool initiallyExpanded;

  const DataLogViewer({super.key, this.initiallyExpanded = true});

  @override
  State<DataLogViewer> createState() => _DataLogViewerState();
}

class _DataLogViewerState extends State<DataLogViewer> {
  final _scrollController = ScrollController();
  final _entries = <AirocLogEntry>[];
  StreamSubscription<AirocLogEntry>? _sub;

  AirocLogLevel _minLevel = AirocLogLevel.verbose;
  bool _autoScroll = true;
  bool _expanded = true;

  List<AirocLogEntry> get _filtered =>
      _entries.where((e) => e.level.index >= _minLevel.index).toList();

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _entries.addAll(AirocDataLogger.instance.entries);
    _sub = AirocDataLogger.instance.stream.listen(_onEntry);
  }

  void _onEntry(AirocLogEntry entry) {
    if (!mounted) return;
    setState(() => _entries.add(entry));
    if (_autoScroll && _expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _clear() {
    AirocDataLogger.instance.clear();
    setState(() => _entries.clear());
  }

  Future<void> _copyAll() async {
    final text = AirocDataLogger.instance.exportAsText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Log copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Color _levelColor(AirocLogLevel level, BuildContext context) {
    switch (level) {
      case AirocLogLevel.verbose:
        return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38);
      case AirocLogLevel.info:
        return Colors.blue.shade300;
      case AirocLogLevel.warning:
        return Colors.orange.shade300;
      case AirocLogLevel.error:
        return Colors.red.shade400;
    }
  }

  Color _levelBadgeColor(AirocLogLevel level) {
    switch (level) {
      case AirocLogLevel.verbose:
        return Colors.grey.shade700;
      case AirocLogLevel.info:
        return Colors.blue.shade700;
      case AirocLogLevel.warning:
        return Colors.orange.shade700;
      case AirocLogLevel.error:
        return Colors.red.shade700;
    }
  }

  Widget _buildEntry(AirocLogEntry entry, BuildContext context) {
    final textColor = _levelColor(entry.level, context);
    final mono = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontFamily: 'monospace',
          fontSize: 11,
          color: textColor,
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.timeLabel,
            style: mono?.copyWith(
              color:
                  Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: _levelBadgeColor(entry.level),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              entry.levelLabel,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text('[${entry.tag}] ',
              style: mono?.copyWith(fontWeight: FontWeight.bold)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.message, style: mono),
                if (entry.hex != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    entry.hex!,
                    style: mono?.copyWith(
                      letterSpacing: 1.2,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(AirocLogLevel level, String label) {
    final selected = _minLevel == level;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 11)),
        selected: selected,
        onSelected: (_) => setState(() => _minLevel = level),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.bug_report, size: 18),
                  const SizedBox(width: 8),
                  const Text('Debug Log',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        Text('${filtered.length}', style: const TextStyle(fontSize: 11)),
                  ),
                  const Spacer(),
                  Tooltip(
                    message: 'Auto-scroll',
                    child: IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        _autoScroll ? Icons.vertical_align_bottom : Icons.pause,
                        color: _autoScroll
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                      onPressed: () => setState(() => _autoScroll = !_autoScroll),
                    ),
                  ),
                  Tooltip(
                    message: 'Copy all to clipboard',
                    child: IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.copy),
                      onPressed: filtered.isEmpty ? null : _copyAll,
                    ),
                  ),
                  Tooltip(
                    message: 'Clear log',
                    child: IconButton(
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.delete_sweep),
                      onPressed: filtered.isEmpty ? null : _clear,
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                children: [
                  _buildFilterChip(AirocLogLevel.verbose, 'V+'),
                  _buildFilterChip(AirocLogLevel.info, 'I+'),
                  _buildFilterChip(AirocLogLevel.warning, 'W+'),
                  _buildFilterChip(AirocLogLevel.error, 'E'),
                ],
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                controller: _scrollController,
                itemCount: filtered.length,
                itemBuilder: (context, index) =>
                    _buildEntry(filtered[index], context),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
