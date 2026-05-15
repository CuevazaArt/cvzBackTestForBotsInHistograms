import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/backtest_state.dart';
import 'params_editor.dart';

class Sidebar extends ConsumerWidget {
  final VoidCallback onRun;
  const Sidebar({super.key, required this.onRun});

  static const _timeframes = ['1m', '5m', '15m', '1h', '4h', '1d'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg   = ref.watch(configProvider);
    final cfgN  = ref.read(configProvider.notifier);
    final bots  = ref.watch(botsProvider);
    final syms  = ref.watch(symbolsProvider);
    final tt    = Theme.of(context).textTheme;

    return Container(
      color: const Color(0xFF1E222D),
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [

          // ── Symbol ──────────────────────────────────────────────
          Text('Symbol', style: tt.bodySmall),
          const SizedBox(height: 4),
          syms.when(
            data: (list) {
              final symbols = list.map((e) => e['symbol'] as String).toSet().toList()..sort();
              return _Dropdown<String>(
                value: symbols.contains(cfg.symbol) ? cfg.symbol : null,
                items: symbols,
                label: (s) => s,
                onChanged: (s) { if (s != null) cfgN.setSymbol(s); },
              );
            },
            loading: () => const LinearProgressIndicator(),
            error:   (e, _) => Text('$e', style: const TextStyle(color: Color(0xFFEF5350), fontSize: 11)),
          ),
          const SizedBox(height: 12),

          // ── Timeframe ────────────────────────────────────────────
          Text('Timeframe', style: tt.bodySmall),
          const SizedBox(height: 4),
          _Dropdown<String>(
            value: cfg.timeframe,
            items: _timeframes,
            label: (tf) => tf,
            onChanged: (tf) { if (tf != null) cfgN.setTimeframe(tf); },
          ),
          const SizedBox(height: 12),

          // ── Bot ─────────────────────────────────────────────────
          Text('Bot', style: tt.bodySmall),
          const SizedBox(height: 4),
          bots.when(
            data: (list) => _Dropdown<String>(
              value: list.any((b) => b.name == cfg.bot) ? cfg.bot : null,
              items: list.map((b) => b.name).toList(),
              label: (n) => n,
              onChanged: (name) {
                if (name == null) return;
                final spec = list.firstWhere((b) => b.name == name);
                cfgN.setBot(name, spec.defaultParams());
              },
            ),
            loading: () => const LinearProgressIndicator(),
            error:   (e, _) => Text('$e', style: const TextStyle(color: Color(0xFFEF5350), fontSize: 11)),
          ),
          const SizedBox(height: 16),

          // ── Bot params ───────────────────────────────────────────
          bots.when(
            data: (list) {
              final spec = list.where((b) => b.name == cfg.bot).firstOrNull;
              if (spec == null) return const SizedBox.shrink();
              return ParamsEditor(spec: spec);
            },
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 12),

          // ── Cash ────────────────────────────────────────────────
          Text('Initial cash (USDT)', style: tt.bodySmall),
          const SizedBox(height: 4),
          TextFormField(
            initialValue: cfg.initialCash.toStringAsFixed(0),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 12),
            onChanged: (v) {
              final d = double.tryParse(v);
              if (d != null && d > 0) cfgN.setCash(d);
            },
          ),
          const SizedBox(height: 16),

          // ── Run ─────────────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: onRun,
            icon: const Icon(Icons.play_arrow, size: 16),
            label: const Text('Run Backtest'),
          ),
        ],
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final T? value;
  final List<T> items;
  final String Function(T) label;
  final void Function(T?) onChanged;

  const _Dropdown({
    required this.value,
    required this.items,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      isDense: true,
      style: const TextStyle(fontSize: 12, color: Color(0xFFD1D4DC)),
      dropdownColor: const Color(0xFF1E222D),
      decoration: const InputDecoration(isDense: true),
      items: items
          .map((i) => DropdownMenuItem<T>(value: i, child: Text(label(i))))
          .toList(),
      onChanged: onChanged,
    );
  }
}
