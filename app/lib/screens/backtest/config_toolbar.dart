import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bots/registry.dart';
import '../../data/daos/presets_dao.dart';
import '../../state/backtest_state.dart';
import '../../state/providers.dart';

/// Compact horizontal toolbar: [Symbol] [TF] [Bot] [Params▼] | [Speed] | [▶ ⏸ ⏭ ⏹] | [progress]
class ConfigToolbar extends ConsumerWidget {
  final String symbol;
  final String timeframe;
  final String selectedBot;
  final Map<String, dynamic> botParams;
  final double initialCash;
  final double feePct;
  final double slippagePct;
  final int speedMs;
  final BacktestStatus status;

  final ValueChanged<String> onSymbolChanged;
  final ValueChanged<String> onTimeframeChanged;
  final ValueChanged<String> onBotChanged;
  final ValueChanged<Map<String, dynamic>> onBotParamsChanged;
  final ValueChanged<double> onInitialCashChanged;
  final ValueChanged<double> onFeeChanged;
  final ValueChanged<double> onSlippageChanged;
  final ValueChanged<int> onSpeedChanged;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStep;
  final VoidCallback onCancel;

  const ConfigToolbar({
    super.key,
    required this.symbol,
    required this.timeframe,
    required this.selectedBot,
    required this.botParams,
    required this.initialCash,
    required this.feePct,
    required this.slippagePct,
    required this.speedMs,
    required this.status,
    required this.onSymbolChanged,
    required this.onTimeframeChanged,
    required this.onBotChanged,
    required this.onBotParamsChanged,
    required this.onInitialCashChanged,
    required this.onFeeChanged,
    required this.onSlippageChanged,
    required this.onSpeedChanged,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStep,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final running = status is BacktestRunning;
    final paused = running && (status as BacktestRunning).paused;
    final db = ref.watch(databaseProvider);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          // ─── Data selectors ─────────────────────────────
          FutureBuilder<Map<String, List<String>>>(
            future: db.candles.availableSymbols(),
            builder: (context, snap) {
              final symbols =
                  snap.hasData ? (snap.data!.keys.toList()..sort()) : <String>[];
              final tfs = (snap.hasData && snap.data![symbol] != null)
                  ? (List<String>.from(snap.data![symbol]!)..sort())
                  : <String>['1h'];

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CompactDropdown(
                    value: symbols.contains(symbol) ? symbol : null,
                    items: symbols,
                    hint: 'Symbol',
                    width: 110,
                    onChanged: (v) => v != null ? onSymbolChanged(v) : null,
                  ),
                  const SizedBox(width: 4),
                  _CompactDropdown(
                    value: tfs.contains(timeframe) ? timeframe : tfs.first,
                    items: tfs,
                    hint: 'TF',
                    width: 70,
                    onChanged: (v) => v != null ? onTimeframeChanged(v) : null,
                  ),
                ],
              );
            },
          ),

          _Sep(),

          // ─── Bot selector + params ──────────────────────
          _CompactDropdown(
            value: selectedBot,
            items: BotRegistry.names,
            labels: {
              for (final b in BotRegistry.all) b.id: b.displayName,
            },
            hint: 'Bot',
            width: 140,
            onChanged: (v) => v != null ? onBotChanged(v) : null,
          ),
          const SizedBox(width: 2),
          _ParamsMenuButton(
            selectedBot: selectedBot,
            botParams: botParams,
            initialCash: initialCash,
            feePct: feePct,
            slippagePct: slippagePct,
            onBotParamsChanged: onBotParamsChanged,
            onInitialCashChanged: onInitialCashChanged,
            onFeeChanged: onFeeChanged,
            onSlippageChanged: onSlippageChanged,
          ),
          const SizedBox(width: 2),
          _PresetButtons(
            selectedBot: selectedBot,
            botParams: botParams,
            onBotParamsChanged: onBotParamsChanged,
          ),

          _Sep(),

          // ─── Speed control ──────────────────────────────
          const Icon(Icons.speed, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          SizedBox(
            width: 100,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
              ),
              child: Slider(
                value: speedMs.toDouble(),
                min: 0,
                max: 500,
                divisions: 10,
                onChanged: (v) => onSpeedChanged(v.toInt()),
              ),
            ),
          ),
          Text(
            speedMs == 0 ? 'max' : '${speedMs}ms',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),

          _Sep(),

          // ─── Playback controls ──────────────────────────
          if (!running) ...[
            _ToolbarButton(
              icon: Icons.play_arrow,
              tooltip: 'Start backtest',
              color: Colors.green,
              onPressed: onStart,
              filled: true,
            ),
          ] else ...[
            if (paused) ...[
              _ToolbarButton(
                icon: Icons.play_arrow,
                tooltip: 'Resume',
                color: Colors.green,
                onPressed: onResume,
              ),
              _ToolbarButton(
                icon: Icons.skip_next,
                tooltip: 'Step one candle',
                onPressed: onStep,
              ),
            ] else
              _ToolbarButton(
                icon: Icons.pause,
                tooltip: 'Pause',
                color: Colors.amber,
                onPressed: onPause,
              ),
            _ToolbarButton(
              icon: Icons.stop,
              tooltip: 'Cancel',
              color: Colors.red,
              onPressed: onCancel,
            ),
          ],

          // ─── Live badge ─────────────────────────────────
          if (running) ...[
            const SizedBox(width: 8),
            _LiveBadge(status: status as BacktestRunning),
          ],

          const Spacer(),

          // ─── Progress ───────────────────────────────────
          if (running)
            SizedBox(
              width: 120,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(
                    value: (status as BacktestRunning).percent / 100,
                    minHeight: 3,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${(status as BacktestRunning).percent.toStringAsFixed(0)}%',
                    style: const TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Small reusable pieces ──────────────────────────────────────

class _Sep extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          height: 20,
          child: VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
        ),
      );
}

class _CompactDropdown extends StatelessWidget {
  final String? value;
  final List<String> items;
  final Map<String, String>? labels;
  final String hint;
  final double width;
  final ValueChanged<String?> onChanged;

  const _CompactDropdown({
    required this.value,
    required this.items,
    this.labels,
    required this.hint,
    required this.width,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: 30,
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isDense: true,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: hint,
            labelStyle: const TextStyle(fontSize: 11),
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          ),
          style: const TextStyle(fontSize: 12),
          items: items
              .map((i) => DropdownMenuItem(
                    value: i,
                    child: Text(
                      labels?[i] ?? i,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      );
}

class _ToolbarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onPressed;
  final bool filled;

  const _ToolbarButton({
    required this.icon,
    required this.tooltip,
    this.color,
    required this.onPressed,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: SizedBox(
          height: 28,
          child: FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(icon, size: 16),
            label: const Text('Run', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              backgroundColor: color,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 16, color: color),
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        splashRadius: 14,
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final BacktestRunning status;
  const _LiveBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.withAlpha(30),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.green.withAlpha(80)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: status.paused ? Colors.amber : Colors.green,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            status.paused ? 'PAUSED' : 'LIVE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: status.paused ? Colors.amber : Colors.green,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${status.trades.length} trades',
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _ParamsMenuButton extends StatelessWidget {
  final String selectedBot;
  final Map<String, dynamic> botParams;
  final double initialCash;
  final double feePct;
  final double slippagePct;
  final ValueChanged<Map<String, dynamic>> onBotParamsChanged;
  final ValueChanged<double> onInitialCashChanged;
  final ValueChanged<double> onFeeChanged;
  final ValueChanged<double> onSlippageChanged;

  const _ParamsMenuButton({
    required this.selectedBot,
    required this.botParams,
    required this.initialCash,
    required this.feePct,
    required this.slippagePct,
    required this.onBotParamsChanged,
    required this.onInitialCashChanged,
    required this.onFeeChanged,
    required this.onSlippageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        icon: const Icon(Icons.tune, size: 16),
        tooltip: 'Bot parameters & settings',
        padding: EdgeInsets.zero,
        onPressed: () => _showParamsDialog(context),
      ),
    );
  }

  void _showParamsDialog(BuildContext context) {
    final defaults = BotRegistry.info(selectedBot).defaultParams;
    final merged = {...defaults, ...botParams};

    showDialog(
      context: context,
      builder: (ctx) => _ParamsDialog(
        botName: BotRegistry.info(selectedBot).displayName,
        params: Map<String, dynamic>.from(merged),
        initialCash: initialCash,
        feePct: feePct,
        slippagePct: slippagePct,
        onParamsChanged: onBotParamsChanged,
        onInitialCashChanged: onInitialCashChanged,
        onFeeChanged: onFeeChanged,
        onSlippageChanged: onSlippageChanged,
      ),
    );
  }
}

class _ParamsDialog extends StatefulWidget {
  final String botName;
  final Map<String, dynamic> params;
  final double initialCash;
  final double feePct;
  final double slippagePct;
  final ValueChanged<Map<String, dynamic>> onParamsChanged;
  final ValueChanged<double> onInitialCashChanged;
  final ValueChanged<double> onFeeChanged;
  final ValueChanged<double> onSlippageChanged;

  const _ParamsDialog({
    required this.botName,
    required this.params,
    required this.initialCash,
    required this.feePct,
    required this.slippagePct,
    required this.onParamsChanged,
    required this.onInitialCashChanged,
    required this.onFeeChanged,
    required this.onSlippageChanged,
  });

  @override
  State<_ParamsDialog> createState() => _ParamsDialogState();
}

class _ParamsDialogState extends State<_ParamsDialog> {
  late Map<String, dynamic> _params;
  late double _cash;
  late double _fee;
  late double _slip;

  @override
  void initState() {
    super.initState();
    _params = Map<String, dynamic>.from(widget.params);
    _cash = widget.initialCash;
    _fee = widget.feePct;
    _slip = widget.slippagePct;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${widget.botName} — Parameters'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Bot Parameters',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              for (final entry in _params.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _paramField(entry.key, entry.value),
                ),
              const Divider(),
              Text('Execution Settings',
                  style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 8),
              _numField('Initial cash (USDT)', _cash,
                  (v) => setState(() => _cash = v)),
              const SizedBox(height: 8),
              _numField(
                  'Taker fee %', _fee, (v) => setState(() => _fee = v)),
              const SizedBox(height: 8),
              _numField(
                  'Slippage %', _slip, (v) => setState(() => _slip = v)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            widget.onParamsChanged(_params);
            widget.onInitialCashChanged(_cash);
            widget.onFeeChanged(_fee);
            widget.onSlippageChanged(_slip);
            Navigator.pop(context);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }

  Widget _paramField(String key, dynamic value) {
    if (value is bool) {
      return SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: Text(key, style: const TextStyle(fontSize: 13)),
        value: value,
        onChanged: (v) => setState(() => _params[key] = v),
      );
    }
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: key,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) {
        final asInt = int.tryParse(v);
        if (asInt != null && value is int) {
          setState(() => _params[key] = asInt);
          return;
        }
        final asDouble = double.tryParse(v);
        if (asDouble != null) {
          setState(() => _params[key] = asDouble);
        }
      },
    );
  }

  Widget _numField(String label, double value, ValueChanged<double> cb) {
    return TextFormField(
      initialValue: value.toString(),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      onChanged: (v) {
        final parsed = double.tryParse(v);
        if (parsed != null) cb(parsed);
      },
    );
  }
}

class _PresetButtons extends ConsumerWidget {
  final String selectedBot;
  final Map<String, dynamic> botParams;
  final ValueChanged<Map<String, dynamic>> onBotParamsChanged;

  const _PresetButtons({
    required this.selectedBot,
    required this.botParams,
    required this.onBotParamsChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            icon: const Icon(Icons.save_outlined, size: 14),
            tooltip: 'Save preset',
            padding: EdgeInsets.zero,
            onPressed: () => _savePreset(context, ref),
          ),
        ),
        SizedBox(
          width: 28,
          height: 28,
          child: IconButton(
            icon: const Icon(Icons.folder_open_outlined, size: 14),
            tooltip: 'Load preset',
            padding: EdgeInsets.zero,
            onPressed: () => _loadPreset(context, ref),
          ),
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
            hintText:
                '${BotRegistry.info(selectedBot).displayName} custom',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
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
            title: Text(
                'Load Preset — ${BotRegistry.info(selectedBot).displayName}'),
            content: SizedBox(
              width: 400,
              height: 300,
              child: presets.isEmpty
                  ? const Center(
                      child: Text('No presets saved.',
                          style: TextStyle(color: Colors.grey)))
                  : ListView(
                      children: [
                        for (final p in presets)
                          ListTile(
                            title: Text(p.name),
                            subtitle: Text(p.updatedAt
                                .toLocal()
                                .toString()
                                .substring(0, 16)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                      Icons.check_circle_outline),
                                  tooltip: 'Load',
                                  onPressed: () {
                                    final params =
                                        Map<String, dynamic>.from(
                                            jsonDecode(p.paramsYaml)
                                                as Map);
                                    onBotParamsChanged(params);
                                    Navigator.pop(ctx);
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  tooltip: 'Delete',
                                  onPressed: () async {
                                    if (p.id != null) {
                                      await db.presets
                                          .deletePreset(p.id!);
                                    }
                                    if (ctx.mounted) Navigator.pop(ctx);
                                    if (context.mounted) {
                                      _loadPreset(context, ref);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close')),
            ],
          );
        },
      ),
    );
  }
}
