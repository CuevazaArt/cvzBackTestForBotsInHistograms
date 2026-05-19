import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bots/registry.dart';
import '../../data/daos/presets_dao.dart';
import '../../state/providers.dart';

class BotConfigPanel extends ConsumerWidget {
  final String symbol;
  final String timeframe;
  final String selectedBot;
  final Map<String, dynamic> botParams;
  final double initialCash;
  final double feePct;
  final double slippagePct;
  final ValueChanged<String> onSymbolChanged;
  final ValueChanged<String> onTimeframeChanged;
  final ValueChanged<String> onBotChanged;
  final ValueChanged<Map<String, dynamic>> onBotParamsChanged;
  final ValueChanged<double> onInitialCashChanged;
  final ValueChanged<double> onFeeChanged;
  final ValueChanged<double> onSlippageChanged;

  const BotConfigPanel({
    super.key,
    required this.symbol,
    required this.timeframe,
    required this.selectedBot,
    required this.botParams,
    required this.initialCash,
    required this.feePct,
    required this.slippagePct,
    required this.onSymbolChanged,
    required this.onTimeframeChanged,
    required this.onBotChanged,
    required this.onBotParamsChanged,
    required this.onInitialCashChanged,
    required this.onFeeChanged,
    required this.onSlippageChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(databaseProvider);
    final defaults = BotRegistry.info(selectedBot).defaultParams;
    final mergedParams = {...defaults, ...botParams};

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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Save Preset', style: TextStyle(fontSize: 12)),
                    onPressed: () => _savePreset(context, ref),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    label: const Text('Load Preset', style: TextStyle(fontSize: 12)),
                    onPressed: () => _loadPreset(context, ref),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            Text('Bot Parameters',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            for (final entry in mergedParams.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _ParamField(
                  label: entry.key,
                  value: entry.value,
                  onChanged: (v) {
                    final updated = {...mergedParams, entry.key: v};
                    onBotParamsChanged(updated);
                  },
                ),
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

  void _savePreset(BuildContext context, WidgetRef ref) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save Preset'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Preset name',
            hintText: '${BotRegistry.info(selectedBot).displayName} custom',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final db = ref.read(databaseProvider);
              await db.presets.upsert(BotPreset(
                name: name,
                botName: selectedBot,
                paramsYaml: jsonEncode(botParams),
                updatedAt: DateTime.now(),
              ));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Saved preset "$name"')),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _loadPreset(BuildContext context, WidgetRef ref) {
    final db = ref.read(databaseProvider);
    showDialog(
      context: context,
      builder: (ctx) => FutureBuilder<List<BotPreset>>(
        future: db.presets.listForBot(selectedBot),
        builder: (context, snap) {
          final presets = snap.data ?? [];
          return AlertDialog(
            title: Text('Load Preset — ${BotRegistry.info(selectedBot).displayName}'),
            content: SizedBox(
              width: 400,
              height: 300,
              child: presets.isEmpty
                  ? const Center(child: Text('No presets saved for this bot.',
                      style: TextStyle(color: Colors.grey)))
                  : ListView(
                      children: [
                        for (final p in presets)
                          ListTile(
                            title: Text(p.name),
                            subtitle: Text(p.updatedAt.toLocal().toString().substring(0, 16)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.check_circle_outline),
                                  tooltip: 'Load',
                                  onPressed: () {
                                    final params = Map<String, dynamic>.from(
                                        jsonDecode(p.paramsYaml) as Map);
                                    onBotParamsChanged(params);
                                    Navigator.pop(ctx);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Loaded preset "${p.name}"')),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  tooltip: 'Delete',
                                  onPressed: () async {
                                    if (p.id != null) {
                                      await db.presets.deletePreset(p.id!);
                                    }
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (context.mounted) _loadPreset(context, ref);
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }
}

class _ParamField extends StatelessWidget {
  final String label;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  const _ParamField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (value is bool) {
      return SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 13)),
        value: value as bool,
        onChanged: onChanged,
      );
    }
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) {
        final asInt = int.tryParse(v);
        if (asInt != null && value is int) {
          onChanged(asInt);
          return;
        }
        final asDouble = double.tryParse(v);
        if (asDouble != null) {
          onChanged(asDouble);
        }
      },
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
