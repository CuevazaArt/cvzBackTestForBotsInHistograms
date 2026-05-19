import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bots/registry.dart';
import '../bots/bot_base.dart';
import '../core/config.dart';
import '../core/engine.dart';
import '../analysis/metrics.dart';
import '../state/providers.dart';
import '../widgets/heatmap.dart';

class OptimizationScreen extends ConsumerStatefulWidget {
  const OptimizationScreen({super.key});

  @override
  ConsumerState<OptimizationScreen> createState() => _OptimizationScreenState();
}

class _OptimizationScreenState extends ConsumerState<OptimizationScreen> {
  String _symbol = 'BTCUSDT';
  String _timeframe = '1h';
  String _selectedBot = 'ema_cross';
  String _param1 = '';
  String _param2 = '';
  double _p1Min = 0, _p1Max = 0, _p1Step = 1;
  double _p2Min = 0, _p2Max = 0, _p2Step = 1;
  bool _running = false;
  List<_OptResult>? _results;
  String _sortMetric = 'sharpe';
  bool _showHeatmap = false;

  List<BotParamSpec> get _specs => BotRegistry.create(_selectedBot).paramSpec();

  @override
  void initState() {
    super.initState();
    _initParams();
  }

  void _initParams() {
    final specs = _specs;
    if (specs.length >= 2) {
      _param1 = specs[0].name;
      _param2 = specs[1].name;
      _p1Min = specs[0].min?.toDouble() ?? 0;
      _p1Max = specs[0].max?.toDouble() ?? 100;
      _p1Step = specs[0].step?.toDouble() ?? 1;
      _p2Min = specs[1].min?.toDouble() ?? 0;
      _p2Max = specs[1].max?.toDouble() ?? 100;
      _p2Step = specs[1].step?.toDouble() ?? 1;
    } else if (specs.isNotEmpty) {
      _param1 = specs[0].name;
      _param2 = '';
      _p1Min = specs[0].min?.toDouble() ?? 0;
      _p1Max = specs[0].max?.toDouble() ?? 100;
      _p1Step = specs[0].step?.toDouble() ?? 1;
    }
  }

  Future<void> _runSweep() async {
    final db = ref.read(databaseProvider);
    final candles = await db.candles.queryRange(_symbol, _timeframe);
    if (!mounted) return;
    if (candles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No candles for $_symbol $_timeframe')),
      );
      return;
    }

    setState(() { _running = true; _results = null; });

    final results = <_OptResult>[];
    final defaults = Map<String, dynamic>.from(BotRegistry.info(_selectedBot).defaultParams);

    final p1Values = _generateRange(_p1Min, _p1Max, _p1Step);
    final p2Values = _param2.isEmpty ? [0.0] : _generateRange(_p2Min, _p2Max, _p2Step);

    for (final v1 in p1Values) {
      for (final v2 in p2Values) {
        final params = Map<String, dynamic>.from(defaults);
        params[_param1] = _isIntParam(_param1) ? v1.toInt() : v1;
        if (_param2.isNotEmpty) {
          params[_param2] = _isIntParam(_param2) ? v2.toInt() : v2;
        }

        try {
          final bot = BotRegistry.create(_selectedBot, params);
          final engine = BacktestEngine(config: const BacktestConfig());
          final result = engine.run(bots: [bot], candles: candles);
          final m = MetricsCalculator.compute(result, timeframe: _timeframe);

          results.add(_OptResult(
            p1: v1,
            p2: _param2.isEmpty ? null : v2,
            returnPct: result.returnPct,
            sharpe: m.sharpe,
            maxDd: m.maxDrawdownPct,
            trades: result.totalTrades,
            winRate: result.winRate,
          ));
        } catch (_) {
          // Skip invalid parameter combinations
        }
      }
    }

    if (!mounted) return;
    setState(() { _running = false; _results = results; });
  }

  List<double> _generateRange(double min, double max, double step) {
    final values = <double>[];
    for (double v = min; v <= max + step * 0.01; v += step) {
      values.add(double.parse(v.toStringAsFixed(6)));
    }
    if (values.length > 50) {
      final newStep = (max - min) / 50;
      values.clear();
      for (double v = min; v <= max + newStep * 0.01; v += newStep) {
        values.add(double.parse(v.toStringAsFixed(6)));
      }
    }
    return values;
  }

  bool _isIntParam(String name) {
    for (final s in _specs) {
      if (s.name == name) return s.type == BotParamType.intParam;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final specs = _specs;
    final paramNames = specs.map((s) => s.name).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Parameter Optimization', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  SizedBox(
                    width: 140,
                    child: TextFormField(
                      initialValue: _symbol,
                      decoration: const InputDecoration(labelText: 'Symbol', border: OutlineInputBorder()),
                      onChanged: (v) => _symbol = v.toUpperCase(),
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: DropdownButtonFormField<String>(
                      initialValue: _timeframe,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'TF', border: OutlineInputBorder()),
                      items: ['1m', '5m', '15m', '1h', '4h', '1d']
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) => setState(() => _timeframe = v ?? '1h'),
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedBot,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Bot', border: OutlineInputBorder()),
                      items: BotRegistry.names
                          .map((n) => DropdownMenuItem(
                              value: n,
                              child: Text(BotRegistry.info(n).displayName, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() { _selectedBot = v; _initParams(); });
                      },
                    ),
                  ),
                  if (paramNames.isNotEmpty)
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        initialValue: paramNames.contains(_param1) ? _param1 : paramNames.first,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Param 1', border: OutlineInputBorder()),
                        items: paramNames.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                        onChanged: (v) { if (v != null) setState(() => _param1 = v); },
                      ),
                    ),
                  _RangeField(label: 'Min', value: _p1Min, onChanged: (v) => _p1Min = v),
                  _RangeField(label: 'Max', value: _p1Max, onChanged: (v) => _p1Max = v),
                  _RangeField(label: 'Step', value: _p1Step, onChanged: (v) => _p1Step = v),
                  if (paramNames.length >= 2) ...[
                    SizedBox(
                      width: 150,
                      child: DropdownButtonFormField<String>(
                        initialValue: paramNames.contains(_param2) ? _param2 : paramNames[1],
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Param 2', border: OutlineInputBorder()),
                        items: [
                          const DropdownMenuItem(value: '', child: Text('(none)')),
                          ...paramNames.map((n) => DropdownMenuItem(value: n, child: Text(n))),
                        ],
                        onChanged: (v) { if (v != null) setState(() => _param2 = v); },
                      ),
                    ),
                    if (_param2.isNotEmpty) ...[
                      _RangeField(label: 'Min', value: _p2Min, onChanged: (v) => _p2Min = v),
                      _RangeField(label: 'Max', value: _p2Max, onChanged: (v) => _p2Max = v),
                      _RangeField(label: 'Step', value: _p2Step, onChanged: (v) => _p2Step = v),
                    ],
                  ],
                  FilledButton.icon(
                    onPressed: _running ? null : _runSweep,
                    icon: _running
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.tune),
                    label: Text(_running ? 'Running...' : 'Optimize'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_results != null) ...[
            Row(
              children: [
                Text('${_results!.length} combinations', style: const TextStyle(color: Colors.grey)),
                const SizedBox(width: 16),
                const Text('Sort by: ', style: TextStyle(color: Colors.grey)),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'sharpe', label: Text('Sharpe')),
                    ButtonSegment(value: 'return', label: Text('Return')),
                    ButtonSegment(value: 'maxDd', label: Text('Max DD')),
                  ],
                  selected: {_sortMetric},
                  onSelectionChanged: (v) => setState(() => _sortMetric = v.first),
                ),
                const Spacer(),
                if (_param2.isNotEmpty)
                  IconButton(
                    icon: Icon(_showHeatmap ? Icons.table_chart : Icons.grid_on),
                    tooltip: _showHeatmap ? 'Show table' : 'Show heatmap',
                    onPressed: () => setState(() => _showHeatmap = !_showHeatmap),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _showHeatmap && _param2.isNotEmpty
                  ? HeatmapWidget(
                      data: _buildHeatmapData(),
                      xLabel: _param1,
                      yLabel: _param2,
                      metricLabel: _sortMetric,
                    )
                  : _ResultsTable(
                      results: _sortedResults(),
                      hasParam2: _param2.isNotEmpty,
                      param1Name: _param1,
                      param2Name: _param2,
                    ),
            ),
          ],
        ],
      ),
    );
  }

  HeatmapData _buildHeatmapData() {
    final xSet = <double>{};
    final ySet = <double>{};
    final cells = <(double, double), double>{};

    for (final r in _results!) {
      xSet.add(r.p1);
      if (r.p2 != null) ySet.add(r.p2!);
      final val = switch (_sortMetric) {
        'return' => r.returnPct,
        'maxDd' => -r.maxDd,
        _ => r.sharpe,
      };
      cells[(r.p1, r.p2 ?? 0)] = val;
    }

    final xs = xSet.toList()..sort();
    final ys = ySet.toList()..sort();
    final vals = cells.values;
    final minV = vals.isEmpty ? 0.0 : vals.reduce((a, b) => a < b ? a : b);
    final maxV = vals.isEmpty ? 0.0 : vals.reduce((a, b) => a > b ? a : b);

    return HeatmapData(
      xValues: xs,
      yValues: ys.isEmpty ? [0] : ys,
      cells: cells,
      minValue: minV,
      maxValue: maxV,
    );
  }

  List<_OptResult> _sortedResults() {
    final sorted = List<_OptResult>.from(_results!);
    switch (_sortMetric) {
      case 'sharpe': sorted.sort((a, b) => b.sharpe.compareTo(a.sharpe));
      case 'return': sorted.sort((a, b) => b.returnPct.compareTo(a.returnPct));
      case 'maxDd': sorted.sort((a, b) => a.maxDd.compareTo(b.maxDd));
    }
    return sorted;
  }
}

class _RangeField extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double> onChanged;
  const _RangeField({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 70,
        child: TextFormField(
          initialValue: value == value.truncateToDouble() ? value.toInt().toString() : value.toString(),
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
          keyboardType: TextInputType.number,
          onChanged: (v) => onChanged(double.tryParse(v) ?? value),
        ),
      );
}

class _ResultsTable extends StatelessWidget {
  final List<_OptResult> results;
  final bool hasParam2;
  final String param1Name;
  final String param2Name;
  const _ResultsTable({
    required this.results,
    required this.hasParam2,
    required this.param1Name,
    required this.param2Name,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          columnSpacing: 20,
          headingRowHeight: 36,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 32,
          columns: [
            DataColumn(label: Text(param1Name), numeric: true),
            if (hasParam2) DataColumn(label: Text(param2Name), numeric: true),
            const DataColumn(label: Text('Return %'), numeric: true),
            const DataColumn(label: Text('Sharpe'), numeric: true),
            const DataColumn(label: Text('Max DD %'), numeric: true),
            const DataColumn(label: Text('Trades'), numeric: true),
            const DataColumn(label: Text('Win %'), numeric: true),
          ],
          rows: [
            for (int i = 0; i < results.length; i++)
              DataRow(
                color: i == 0
                    ? WidgetStateProperty.all(Colors.green.withAlpha(20))
                    : null,
                cells: [
                  DataCell(Text(_fmt(results[i].p1), style: const TextStyle(fontSize: 12))),
                  if (hasParam2)
                    DataCell(Text(_fmt(results[i].p2 ?? 0), style: const TextStyle(fontSize: 12))),
                  DataCell(Text(
                    results[i].returnPct.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 12,
                      color: results[i].returnPct >= 0 ? Colors.green : Colors.red,
                    ),
                  )),
                  DataCell(Text(results[i].sharpe.toStringAsFixed(2), style: const TextStyle(fontSize: 12))),
                  DataCell(Text(results[i].maxDd.toStringAsFixed(2), style: const TextStyle(fontSize: 12))),
                  DataCell(Text('${results[i].trades}', style: const TextStyle(fontSize: 12))),
                  DataCell(Text(results[i].winRate.toStringAsFixed(1), style: const TextStyle(fontSize: 12))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _fmt(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
}

class _OptResult {
  final double p1;
  final double? p2;
  final double returnPct;
  final double sharpe;
  final double maxDd;
  final int trades;
  final double winRate;

  const _OptResult({
    required this.p1,
    this.p2,
    required this.returnPct,
    required this.sharpe,
    required this.maxDd,
    required this.trades,
    required this.winRate,
  });
}
