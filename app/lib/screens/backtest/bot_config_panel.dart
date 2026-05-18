import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bots/registry.dart';
import '../../data/daos/presets_dao.dart';
import '../../state/providers.dart';

class BotConfigToolbar extends ConsumerWidget {
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

  const BotConfigToolbar({
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

    return FutureBuilder<Map<String, List<String>>>(
      future: db.candles.availableSymbols(),
      builder: (context, snap) {
        final symbols = snap.hasData
            ? (snap.data!.keys.toList()..sort())
            : <String>[];
        final tfs = (snap.hasData && snap.data![symbol] != null)
            ? (List<String>.from(snap.data![symbol]!)..sort())
            : <String>['1h'];

        return Row(
          children: [
            _CompactDropdown(
              value: symbols.contains(symbol) ? symbol : null,
              items: symbols,
              tooltip: 'Symbol',
              width: 110,
              onChanged: onSymbolChanged,
            ),
            const SizedBox(width: 4),
            _CompactDropdown(
              value: tfs.contains(timeframe) ? timeframe : tfs.first,
              items: tfs,
              tooltip: 'Timeframe',
              width: 64,
              onChanged: onTimeframeChanged,
            ),
            const SizedBox(width: 4),
            _CompactDropdown(
              value: selectedBot,
              items: BotRegistry.all.map((b) => b.id).toList(),
              labels: {for (final b in BotRegistry.all) b.id: b.displayName},
              tooltip: 'Bot',
              width: 140,
              onChanged: onBotChanged,
            ),
            const SizedBox(width: 4),
            _ParamsMenuButton(
              params: mergedParams,
              onChanged: onBotParamsChanged,
            ),
            const _Sep(),
            _MiniField(tooltip: 'Cash', value: initialCash, width: 72, onChanged: onInitialCashChanged),
            const SizedBox(width: 4),
            _MiniField(tooltip: 'Fee %', value: feePct, width: 52, onChanged: onFeeChanged),
            const SizedBox(width: 4),
            _MiniField(tooltip: 'Slip %', value: slippagePct, width: 52, onChanged: onSlippageChanged),
            const SizedBox(width: 4),
            _PresetButtons(
              selectedBot: selectedBot,
              botParams: botParams,
              onParamsChanged: onBotParamsChanged,
            ),
          ],
        );
      },
    );
  }
}

class _CompactDropdown extends StatelessWidget {
  final String? value;
  final List<String> items;
  final Map<String, String>? labels;
  final String tooltip;
  final double width;
  final ValueChanged<String> onChanged;

  const _CompactDropdown({
    required this.value,
    required this.items,
    required this.tooltip,
    required this.width,
    required this.onChanged,
    this.labels,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: width,
        height: 32,
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            border: const OutlineInputBorder(),
            hintText: tooltip,
            hintStyle: const TextStyle(fontSize: 11),
          ),
          style: const TextStyle(fontSize: 12),
          items: items.map((v) => DropdownMenuItem(
            value: v,
            child: Text(
              labels?[v] ?? v,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          )).toList(),
          onChanged: (v) => v != null ? onChanged(v) : null,
        ),
      ),
    );
  }
}

class _ParamsMenuButton extends StatelessWidget {
  final Map<String, dynamic> params;
  final ValueChanged<Map<String, dynamic>> onChanged;
  const _ParamsMenuButton({required this.params, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.tune, size: 18),
      tooltip: 'Bot parameters',
      visualDensity: VisualDensity.compact,
      onPressed: () => _showParamsSheet(context),
    );
  }

  void _showParamsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => _ParamsSheet(params: params, onChanged: onChanged),
    );
  }
}

class _ParamsSheet extends StatefulWidget {
  final Map<String, dynamic> params;
  final ValueChanged<Map<String, dynamic>> onChanged;
  const _ParamsSheet({required this.params, required this.onChanged});
  @override
  State<_ParamsSheet> createState() => _ParamsSheetState();
}

class _ParamsSheetState extends State<_ParamsSheet> {
  late Map<String, dynamic> _local;

  @override
  void initState() {
    super.initState();
    _local = Map<String, dynamic>.from(widget.params);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bot Parameters', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final entry in _local.entries)
                SizedBox(
                  width: 150,
                  child: entry.value is bool
                      ? CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(entry.key, style: const TextStyle(fontSize: 12)),
                          value: entry.value as bool,
                          onChanged: (v) {
                            setState(() => _local[entry.key] = v ?? false);
                            widget.onChanged(Map.from(_local));
                          },
                        )
                      : TextFormField(
                          initialValue: entry.value.toString(),
                          decoration: InputDecoration(
                            labelText: entry.key,
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          style: const TextStyle(fontSize: 12),
                          onChanged: (v) {
                            final parsed = entry.value is int
                                ? int.tryParse(v)
                                : double.tryParse(v);
                            if (parsed != null) {
                              _local[entry.key] = parsed;
                              widget.onChanged(Map.from(_local));
                            }
                          },
                        ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniField extends StatelessWidget {
  final String tooltip;
  final double value;
  final double width;
  final ValueChanged<double> onChanged;
  const _MiniField({required this.tooltip, required this.value, required this.width, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: width,
        height: 32,
        child: TextFormField(
          initialValue: value % 1 == 0 ? value.toInt().toString() : value.toString(),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            border: const OutlineInputBorder(),
            hintText: tooltip,
            hintStyle: const TextStyle(fontSize: 10),
          ),
          style: const TextStyle(fontSize: 11),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) {
            final parsed = double.tryParse(v);
            if (parsed != null) onChanged(parsed);
          },
        ),
      ),
    );
  }
}

class _Sep extends StatelessWidget {
  const _Sep();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: SizedBox(height: 20, child: VerticalDivider(width: 1, color: Theme.of(context).dividerColor)),
  );
}

class _PresetButtons extends ConsumerWidget {
  final String selectedBot;
  final Map<String, dynamic> botParams;
  final ValueChanged<Map<String, dynamic>> onParamsChanged;

  const _PresetButtons({
    required this.selectedBot,
    required this.botParams,
    required this.onParamsChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.save_outlined, size: 16),
          tooltip: 'Save preset',
          visualDensity: VisualDensity.compact,
          onPressed: () => _savePreset(context, ref),
        ),
        IconButton(
          icon: const Icon(Icons.folder_open_outlined, size: 16),
          tooltip: 'Load preset',
          visualDensity: VisualDensity.compact,
          onPressed: () => _loadPreset(context, ref),
        ),
      ],
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
            title: Text('Load Preset'),
            content: SizedBox(
              width: 400,
              height: 300,
              child: presets.isEmpty
                  ? const Center(child: Text('No presets saved.', style: TextStyle(color: Colors.grey)))
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
                                    onParamsChanged(params);
                                    Navigator.pop(ctx);
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
