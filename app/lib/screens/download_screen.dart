import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/data_quality.dart';
import '../state/download_state.dart';
import '../state/providers.dart';

class DownloadScreen extends ConsumerStatefulWidget {
  const DownloadScreen({super.key});

  @override
  ConsumerState<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends ConsumerState<DownloadScreen> {
  String _symbol = 'BTCUSDT';
  String _timeframe = '1h';
  DateTime _from = DateTime.utc(DateTime.now().year, 1, 1);
  DateTime _to = DateTime.now().toUtc();

  static const _timeframes = ['1m', '5m', '15m', '1h', '4h', '1d'];

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(downloadControllerProvider);
    final ctrl = ref.read(downloadControllerProvider.notifier);
    final db = ref.read(databaseProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Data downloads',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 160,
                child: TextFormField(
                  initialValue: _symbol,
                  decoration: const InputDecoration(
                    labelText: 'Symbol',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => _symbol = v.toUpperCase(),
                ),
              ),
              SizedBox(
                width: 120,
                child: DropdownButtonFormField<String>(
                  initialValue: _timeframe,
                  decoration: const InputDecoration(
                    labelText: 'Timeframe',
                    border: OutlineInputBorder(),
                  ),
                  items: _timeframes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => setState(() => _timeframe = v ?? '1h'),
                ),
              ),
              _DateField(
                label: 'From',
                value: _from,
                onChanged: (d) => setState(() => _from = d),
              ),
              _DateField(
                label: 'To',
                value: _to,
                onChanged: (d) => setState(() => _to = d),
              ),
              FilledButton.icon(
                onPressed: status is DownloadRunning
                    ? null
                    : () => ctrl.start(
                          symbol: _symbol,
                          timeframe: _timeframe,
                          fromMs: _from.millisecondsSinceEpoch,
                          toMs: _to.millisecondsSinceEpoch,
                        ),
                icon: const Icon(Icons.download),
                label: const Text('Download'),
              ),
              if (status is DownloadRunning)
                OutlinedButton.icon(
                  onPressed: ctrl.cancel,
                  icon: const Icon(Icons.stop),
                  label: const Text('Cancel'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          _StatusBox(status: status),
          const SizedBox(height: 24),
          Text('Stored series', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<Map<String, List<String>>>(
              future: db.candles.availableSymbols(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.data!.isEmpty) {
                  return const Center(
                    child: Text('No data downloaded yet.',
                        style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView(
                  children: [
                    for (final entry in snap.data!.entries)
                      for (final tf in entry.value)
                        _SeriesTile(
                          symbol: entry.key,
                          timeframe: tf,
                          db: db,
                          onDeleted: () => setState(() {}),
                        ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  const _DateField({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime.utc(2017),
          lastDate: DateTime.now().toUtc(),
        );
        if (picked != null) onChanged(picked.toUtc());
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text('${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}'),
      ),
    );
  }
}

class _StatusBox extends StatelessWidget {
  final DownloadStatus status;
  const _StatusBox({required this.status});

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      DownloadIdle() => const SizedBox.shrink(),
      DownloadRunning(:final symbol, :final timeframe, :final fetched, :final total) => Card(
          color: Colors.blue.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Downloading $symbol $timeframe — $fetched / ${total ?? "?"} candles'),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if ((status as DownloadRunning).candlesPerSec > 0)
                      Text(
                        '${(status as DownloadRunning).candlesPerSec.toStringAsFixed(0)} candles/s',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    const Spacer(),
                    if ((status as DownloadRunning).eta.isNotEmpty)
                      Text(
                        'ETA: ${(status as DownloadRunning).eta}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: total != null && total > 0 ? fetched / total : null),
              ],
            ),
          ),
        ),
      DownloadDone(:final symbol, :final timeframe, :final totalCandles) => Card(
          color: Colors.green.withValues(alpha: 0.1),
          child: ListTile(
            leading: const Icon(Icons.check_circle, color: Colors.green),
            title: Text('Saved $totalCandles candles for $symbol $timeframe'),
          ),
        ),
      DownloadErrorState(:final message) => Card(
          color: Colors.red.withValues(alpha: 0.1),
          child: ListTile(
            leading: const Icon(Icons.error_outline, color: Colors.red),
            title: const Text('Download failed'),
            subtitle: Text(message),
          ),
        ),
    };
  }
}

class _SeriesTile extends StatefulWidget {
  final String symbol;
  final String timeframe;
  final dynamic db;
  final VoidCallback onDeleted;
  const _SeriesTile({
    required this.symbol,
    required this.timeframe,
    required this.db,
    required this.onDeleted,
  });

  @override
  State<_SeriesTile> createState() => _SeriesTileState();
}

class _SeriesTileState extends State<_SeriesTile> {
  int? _count;
  QualityReport? _quality;
  bool _checking = false;

  static const Map<String, int> _tfMs = {
    '1m': 60000, '5m': 300000, '15m': 900000,
    '1h': 3600000, '4h': 14400000, '1d': 86400000,
  };

  @override
  void initState() {
    super.initState();
    _loadCount();
  }

  Future<void> _loadCount() async {
    final count = await widget.db.candles.countCandles(widget.symbol, widget.timeframe);
    if (mounted) setState(() => _count = count);
  }

  Future<void> _checkQuality() async {
    setState(() => _checking = true);
    final candles = await widget.db.candles.queryRange(widget.symbol, widget.timeframe);
    final barMs = _tfMs[widget.timeframe] ?? 3600000;
    final report = DataQualityValidator().validate(candles, expectedBarMs: barMs);
    if (mounted) setState(() { _quality = report; _checking = false; });
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete series?'),
        content: Text('Remove all ${widget.symbol} ${widget.timeframe} candles?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.db.candles.deleteSymbol(widget.symbol, widget.timeframe);
      widget.onDeleted();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.candlestick_chart),
            title: Text('${widget.symbol}  ${widget.timeframe}'),
            subtitle: Text(_count != null ? '$_count candles' : 'loading...'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: _checking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.verified_outlined),
                  tooltip: 'Check data quality',
                  onPressed: _checking ? null : _checkQuality,
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  tooltip: 'Delete series',
                  onPressed: _delete,
                ),
              ],
            ),
          ),
          if (_quality != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  Icon(
                    _quality!.isClean ? Icons.check_circle : Icons.warning,
                    size: 16,
                    color: _quality!.isClean ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _quality!.isClean
                          ? 'Clean — ${_quality!.completenessPercect.toStringAsFixed(1)}% complete'
                          : '${_quality!.violations.length} issues — ${_quality!.completenessPercect.toStringAsFixed(1)}% complete, ${_quality!.missingBars} gaps',
                      style: TextStyle(
                        fontSize: 12,
                        color: _quality!.isClean ? Colors.green : Colors.orange,
                      ),
                    ),
                  ),
                  if (!_quality!.isClean)
                    TextButton(
                      onPressed: () => _showViolations(context),
                      child: const Text('Details', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _showViolations(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${widget.symbol} ${widget.timeframe} — Quality Report'),
        content: SizedBox(
          width: 500,
          height: 300,
          child: ListView(
            children: [
              for (final v in _quality!.violations)
                ListTile(
                  dense: true,
                  leading: Icon(
                    v.type == ViolationType.missingBar ? Icons.timeline :
                    v.type == ViolationType.outlierReturn ? Icons.trending_up :
                    Icons.error_outline,
                    size: 16,
                  ),
                  title: Text(v.type.name, style: const TextStyle(fontSize: 12)),
                  subtitle: Text(v.detail, style: const TextStyle(fontSize: 11)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}
