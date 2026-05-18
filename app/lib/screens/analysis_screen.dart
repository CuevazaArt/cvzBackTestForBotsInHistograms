import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../analysis/metrics.dart';
import '../analysis/monte_carlo.dart';
import '../analysis/stress.dart';
import '../analysis/walk_forward.dart';
import '../bots/registry.dart';
import '../core/config.dart';
import '../core/models/backtest_result.dart';
import '../services/export_service.dart';
import '../state/backtest_state.dart';
import '../state/providers.dart';
import '../widgets/equity_curve.dart';
import '../widgets/trades_table.dart';

class AnalysisScreen extends ConsumerWidget {
  const AnalysisScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(backtestControllerProvider);
    final result = status is BacktestDone ? status.result : null;

    if (result == null) {
      return const Center(
        child: Text('Run a backtest first, then come here to analyze results.',
            style: TextStyle(color: Colors.grey)),
      );
    }

    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: TabBar(
                  isScrollable: true,
                  tabs: [
                    Tab(text: 'Metrics'),
                    Tab(text: 'Equity'),
                    Tab(text: 'Trades'),
                    Tab(text: 'Monte Carlo'),
                    Tab(text: 'Stress Test'),
                    Tab(text: 'Walk Forward'),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.file_download),
                tooltip: 'Export',
                onSelected: (v) => _export(context, result, v),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'csv', child: Text('Copy trades CSV')),
                  PopupMenuItem(value: 'json', child: Text('Copy result JSON')),
                ],
              ),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _MetricsTab(result: result),
                _EquityTab(result: result),
                _TradesTab(result: result),
                _MonteCarloTab(result: result),
                _StressTab(result: result),
                _WalkForwardTab(ref: ref),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _export(BuildContext context, BacktestResult result, String format) {
    final text = format == 'csv'
        ? ExportService.tradesToCsv(result.trades)
        : const JsonEncoder.withIndent('  ').convert(
            jsonDecode(ExportService.resultToJson(result)));
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${format.toUpperCase()} copied to clipboard')),
    );
  }
}

class _EquityTab extends StatelessWidget {
  final BacktestResult result;
  const _EquityTab({required this.result});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Equity Curve', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Expanded(
            child: EquityCurveWidget(
              equityCurve: result.equityCurve,
              initialCash: result.initialCash,
            ),
          ),
        ],
      ),
    );
  }
}

class _TradesTab extends StatelessWidget {
  final BacktestResult result;
  const _TradesTab({required this.result});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('${result.totalTrades} trades', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text(
                '${result.wins} W / ${result.totalTrades - result.wins} L',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(child: TradesTable(trades: result.trades)),
        ],
      ),
    );
  }
}

class _MetricsTab extends StatelessWidget {
  final BacktestResult result;
  const _MetricsTab({required this.result});

  @override
  Widget build(BuildContext context) {
    final m = MetricsCalculator.compute(result, timeframe: '1h');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MetricCard(title: 'Return', items: [
          _Item('Total Return', '${result.returnPct.toStringAsFixed(2)}%'),
          _Item('Final Equity', '${result.finalEquity.toStringAsFixed(2)} USDT'),
          _Item('Total Trades', '${result.totalTrades}'),
          _Item('Win Rate', '${result.winRate.toStringAsFixed(1)}%'),
          _Item('Profit Factor', result.profitFactor.isFinite ? result.profitFactor.toStringAsFixed(2) : '∞'),
        ]),
        _MetricCard(title: 'Risk-adjusted', items: [
          _Item('Sharpe Ratio', m.sharpe.toStringAsFixed(3)),
          _Item('Sortino Ratio', m.sortino.toStringAsFixed(3)),
          _Item('Calmar Ratio', m.calmar.toStringAsFixed(3)),
          _Item('Ulcer Index', m.ulcerIndex.toStringAsFixed(3)),
          _Item('Recovery Factor', m.recoveryFactor.toStringAsFixed(3)),
          _Item('Max Drawdown', '${m.maxDrawdownPct.toStringAsFixed(2)}%'),
        ]),
        _MetricCard(title: 'Trade Analysis', items: [
          _Item('Expectancy', m.expectancy.toStringAsFixed(2)),
          _Item('Avg Win', m.avgWin.toStringAsFixed(2)),
          _Item('Avg Loss', m.avgLoss.toStringAsFixed(2)),
          _Item('Win Streak', '${m.longestWinStreak}'),
          _Item('Loss Streak', '${m.longestLossStreak}'),
          _Item('Avg MFE', '${m.avgMfe.toStringAsFixed(2)}%'),
          _Item('Avg MAE', '${m.avgMae.toStringAsFixed(2)}%'),
        ]),
      ],
    );
  }
}

class _MonteCarloTab extends StatefulWidget {
  final BacktestResult result;
  const _MonteCarloTab({required this.result});
  @override
  State<_MonteCarloTab> createState() => _MonteCarloTabState();
}

class _MonteCarloTabState extends State<_MonteCarloTab> {
  int _simulations = 1000;
  double _ruinPct = 50.0;
  MonteCarloResult? _mcResult;

  void _run() {
    setState(() {
      _mcResult = MonteCarloSimulator.simulate(
        widget.result,
        simulations: _simulations,
        ruinDrawdownPct: _ruinPct,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Configuration', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(labelText: 'Simulations', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(text: '$_simulations'),
                        onChanged: (v) => _simulations = int.tryParse(v) ?? 1000,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(labelText: 'Ruin DD %', border: OutlineInputBorder()),
                        keyboardType: TextInputType.number,
                        controller: TextEditingController(text: '$_ruinPct'),
                        onChanged: (v) => _ruinPct = double.tryParse(v) ?? 50.0,
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: _run,
                      icon: const Icon(Icons.casino),
                      label: const Text('Run'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (_mcResult != null) ...[
          const SizedBox(height: 8),
          _MetricCard(title: 'Monte Carlo Results (${_mcResult!.simulations} sims)', items: [
            _Item('Median Return', '${_mcResult!.medianReturn.toStringAsFixed(2)}%'),
            _Item('P5 Return', '${_mcResult!.p5Return.toStringAsFixed(2)}%'),
            _Item('P95 Return', '${_mcResult!.p95Return.toStringAsFixed(2)}%'),
            _Item('Median Max DD', '${_mcResult!.medianMaxDrawdown.toStringAsFixed(2)}%'),
            _Item('Worst Max DD', '${_mcResult!.worstMaxDrawdown.toStringAsFixed(2)}%'),
            _Item('Prob. Profit', '${_mcResult!.probProfit.toStringAsFixed(1)}%'),
            _Item('Prob. Ruin', '${_mcResult!.probRuin.toStringAsFixed(1)}%'),
            _Item('VaR 95%', '${_mcResult!.valueAtRisk95.toStringAsFixed(2)}%'),
          ]),
        ],
      ],
    );
  }
}

class _StressTab extends StatefulWidget {
  final BacktestResult result;
  const _StressTab({required this.result});
  @override
  State<_StressTab> createState() => _StressTabState();
}

class _StressTabState extends State<_StressTab> {
  List<StressResult>? _results;

  void _run() {
    setState(() {
      _results = StressTester.run(widget.result, scenarios: const [
        StressScenario(name: 'Baseline'),
        StressScenario(name: '2x Fees', feeMultiplier: 2.0),
        StressScenario(name: '3x Fees', feeMultiplier: 3.0),
        StressScenario(name: '2x Slippage', slippageMultiplier: 2.0),
        StressScenario(name: '2x Fees + 2x Slip', feeMultiplier: 2.0, slippageMultiplier: 2.0),
        StressScenario(name: 'Drop Best 10%', dropBestPercentile: 10.0),
        StressScenario(name: 'Drop Best 25%', dropBestPercentile: 25.0),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: FilledButton.icon(
            onPressed: _run,
            icon: const Icon(Icons.speed),
            label: const Text('Run Stress Test'),
          ),
        ),
        const SizedBox(height: 12),
        if (_results != null)
          Card(
            child: DataTable(
              columnSpacing: 16,
              columns: const [
                DataColumn(label: Text('Scenario')),
                DataColumn(label: Text('Return %'), numeric: true),
                DataColumn(label: Text('Max DD %'), numeric: true),
                DataColumn(label: Text('Sharpe'), numeric: true),
                DataColumn(label: Text('Trades'), numeric: true),
              ],
              rows: [
                for (final r in _results!)
                  DataRow(cells: [
                    DataCell(Text(r.scenarioName)),
                    DataCell(Text(
                      r.returnPct.toStringAsFixed(2),
                      style: TextStyle(color: r.returnPct >= 0 ? Colors.green : Colors.red),
                    )),
                    DataCell(Text(r.maxDrawdownPct.toStringAsFixed(2))),
                    DataCell(Text(r.sharpe.toStringAsFixed(2))),
                    DataCell(Text('${r.totalTrades}')),
                  ]),
              ],
            ),
          ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final List<_Item> items;
  const _MetricCard({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(item.label, style: const TextStyle(color: Colors.grey)),
                    Text(item.value, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Item {
  final String label;
  final String value;
  const _Item(this.label, this.value);
}

class _WalkForwardTab extends StatefulWidget {
  final WidgetRef ref;
  const _WalkForwardTab({required this.ref});
  @override
  State<_WalkForwardTab> createState() => _WalkForwardTabState();
}

class _WalkForwardTabState extends State<_WalkForwardTab> {
  String _symbol = 'BTCUSDT';
  String _timeframe = '1h';
  String _bot = 'ema_cross';
  int _isBars = 500;
  int _oosBars = 125;
  int _stepBars = 125;
  WalkForwardResult? _result;
  bool _running = false;

  Future<void> _run() async {
    final db = widget.ref.read(databaseProvider);
    final candles = await db.candles.queryRange(_symbol, _timeframe);
    if (!mounted) return;
    if (candles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No candles for $_symbol $_timeframe')),
      );
      return;
    }

    setState(() { _running = true; _result = null; });

    final wfa = WalkForwardAnalyzer.analyze(
      candles: candles,
      botFactory: () => BotRegistry.create(_bot),
      config: const BacktestConfig(),
      inSampleBars: _isBars,
      outSampleBars: _oosBars,
      stepBars: _stepBars,
    );

    if (!mounted) return;
    setState(() { _running = false; _result = wfa; });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    initialValue: _symbol,
                    decoration: const InputDecoration(labelText: 'Symbol', border: OutlineInputBorder()),
                    onChanged: (v) => _symbol = v.toUpperCase(),
                  ),
                ),
                SizedBox(
                  width: 80,
                  child: DropdownButtonFormField<String>(
                    initialValue: _timeframe,
                    decoration: const InputDecoration(labelText: 'TF', border: OutlineInputBorder()),
                    items: ['1m', '5m', '15m', '1h', '4h', '1d']
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => _timeframe = v ?? '1h',
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: DropdownButtonFormField<String>(
                    initialValue: _bot,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Bot', border: OutlineInputBorder()),
                    items: BotRegistry.names
                        .map((n) => DropdownMenuItem(
                            value: n,
                            child: Text(BotRegistry.info(n).displayName, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) { if (v != null) _bot = v; },
                  ),
                ),
                SizedBox(width: 80, child: TextFormField(
                  initialValue: '$_isBars',
                  decoration: const InputDecoration(labelText: 'IS bars', border: OutlineInputBorder()),
                  onChanged: (v) => _isBars = int.tryParse(v) ?? 500,
                )),
                SizedBox(width: 80, child: TextFormField(
                  initialValue: '$_oosBars',
                  decoration: const InputDecoration(labelText: 'OOS bars', border: OutlineInputBorder()),
                  onChanged: (v) => _oosBars = int.tryParse(v) ?? 125,
                )),
                SizedBox(width: 80, child: TextFormField(
                  initialValue: '$_stepBars',
                  decoration: const InputDecoration(labelText: 'Step', border: OutlineInputBorder()),
                  onChanged: (v) => _stepBars = int.tryParse(v) ?? 125,
                )),
                FilledButton.icon(
                  onPressed: _running ? null : _run,
                  icon: _running
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.timeline),
                  label: Text(_running ? 'Running...' : 'Analyze'),
                ),
              ],
            ),
          ),
        ),
        if (_result != null) ...[
          const SizedBox(height: 12),
          _MetricCard(title: 'Walk-Forward Summary', items: [
            _Item('Windows', '${_result!.windows.length}'),
            _Item('Avg IS Return', '${_result!.avgInSampleReturn.toStringAsFixed(2)}%'),
            _Item('Avg OOS Return', '${_result!.avgOutSampleReturn.toStringAsFixed(2)}%'),
            _Item('Efficiency Ratio', _result!.efficiencyRatio.toStringAsFixed(3)),
            _Item('Verdict', _result!.verdict.toUpperCase()),
          ]),
          const SizedBox(height: 8),
          if (_result!.windows.isNotEmpty)
            Card(
              child: DataTable(
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('#'), numeric: true),
                  DataColumn(label: Text('IS Start'), numeric: true),
                  DataColumn(label: Text('IS End'), numeric: true),
                  DataColumn(label: Text('IS Return %'), numeric: true),
                  DataColumn(label: Text('OOS Return %'), numeric: true),
                ],
                rows: [
                  for (int i = 0; i < _result!.windows.length; i++)
                    DataRow(cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(Text('${_result!.windows[i].inSampleStart}')),
                      DataCell(Text('${_result!.windows[i].inSampleEnd}')),
                      DataCell(Text(
                        _result!.windows[i].inSampleReturn.toStringAsFixed(2),
                        style: TextStyle(
                          color: _result!.windows[i].inSampleReturn >= 0 ? Colors.green : Colors.red,
                        ),
                      )),
                      DataCell(Text(
                        _result!.windows[i].outSampleReturn.toStringAsFixed(2),
                        style: TextStyle(
                          color: _result!.windows[i].outSampleReturn >= 0 ? Colors.green : Colors.red,
                        ),
                      )),
                    ]),
                ],
              ),
            ),
        ],
      ],
    );
  }
}
