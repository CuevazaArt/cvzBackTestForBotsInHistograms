import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
                      Card(
                        child: ListTile(
                          leading: const Icon(Icons.candlestick_chart),
                          title: Text(entry.key),
                          subtitle: Text(entry.value.join(', ')),
                        ),
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
