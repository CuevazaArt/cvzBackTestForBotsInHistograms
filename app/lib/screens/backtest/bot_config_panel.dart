import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bots/registry.dart';
import '../../state/providers.dart';

/// Configuration column: symbol/timeframe + bot selection + global config.
class BotConfigPanel extends ConsumerWidget {
  final String symbol;
  final String timeframe;
  final String selectedBot;
  final double initialCash;
  final double feePct;
  final double slippagePct;
  final ValueChanged<String> onSymbolChanged;
  final ValueChanged<String> onTimeframeChanged;
  final ValueChanged<String> onBotChanged;
  final ValueChanged<double> onInitialCashChanged;
  final ValueChanged<double> onFeeChanged;
  final ValueChanged<double> onSlippageChanged;

  const BotConfigPanel({
    super.key,
    required this.symbol,
    required this.timeframe,
    required this.selectedBot,
    required this.initialCash,
    required this.feePct,
    required this.slippagePct,
    required this.onSymbolChanged,
    required this.onTimeframeChanged,
    required this.onBotChanged,
    required this.onInitialCashChanged,
    required this.onFeeChanged,
    required this.onSlippageChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Configuration',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, List<String>>>(
              future: db.candles.availableSymbols(),
              builder: (context, snap) {
                final symbols = snap.hasData
                    ? (snap.data!.keys.toList()..sort())
                    : <String>[];
                final tfs = (snap.hasData && snap.data![symbol] != null)
                    ? (List<String>.from(snap.data![symbol]!)..sort())
                    : <String>['1h'];
                return Column(
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: symbols.contains(symbol) ? symbol : null,
                      decoration: const InputDecoration(
                          labelText: 'Symbol', border: OutlineInputBorder()),
                      items: symbols
                          .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                          .toList(),
                      onChanged: (v) => v != null ? onSymbolChanged(v) : null,
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: tfs.contains(timeframe) ? timeframe : tfs.first,
                      decoration: const InputDecoration(
                          labelText: 'Timeframe', border: OutlineInputBorder()),
                      items: tfs
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => v != null ? onTimeframeChanged(v) : null,
                    ),
                  ],
                );
              },
            ),
            const Divider(height: 24),
            DropdownButtonFormField<String>(
              initialValue: selectedBot,
              isExpanded: true,
              decoration: const InputDecoration(
                  labelText: 'Bot', border: OutlineInputBorder()),
              items: BotRegistry.all
                  .map((b) =>
                      DropdownMenuItem(value: b.id, child: Text(b.displayName, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) => v != null ? onBotChanged(v) : null,
            ),
            const SizedBox(height: 4),
            Text(
              BotRegistry.info(selectedBot).description,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const Divider(height: 24),
            _NumberField(
              label: 'Initial cash',
              value: initialCash,
              onChanged: onInitialCashChanged,
              suffix: 'USDT',
            ),
            const SizedBox(height: 8),
            _NumberField(
              label: 'Taker fee %',
              value: feePct,
              onChanged: onFeeChanged,
            ),
            const SizedBox(height: 8),
            _NumberField(
              label: 'Slippage %',
              value: slippagePct,
              onChanged: onSlippageChanged,
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  final String? suffix;
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixText: suffix,
        isDense: true,
      ),
      onChanged: (v) {
        final parsed = double.tryParse(v);
        if (parsed != null) onChanged(parsed);
      },
    );
  }
}
