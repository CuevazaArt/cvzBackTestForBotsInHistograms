// Decision-support analysis screen — Phase 3.
//
// Four tabs, each addressing a question a trader asks before deploying:
//   - History     : "What backtests have I already run?"  (ResultStore browser)
//   - Walk-Forward: "Does this setup hold up out-of-sample?"
//   - Monte Carlo : "What's the worst case I should plan for?"
//   - Robustness  : "Which candidate is most stable across metrics?"
//
// All tabs share a single ApiService injected from main.dart. The screen is
// self-contained and can be opened/closed without affecting other state.

import 'dart:convert' show jsonDecode;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:backtester_shell/services/api_service.dart';
import 'package:backtester_shell/widgets/compare_panel.dart';

class AnalysisScreen extends StatefulWidget {
  final ApiService apiService;
  const AnalysisScreen({super.key, required this.apiService});

  @override
  State<AnalysisScreen> createState() => _AnalysisScreenState();
}

class _AnalysisScreenState extends State<AnalysisScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  Map<String, dynamic>? _selectedRun; // shared between tabs (for MC/WF context)

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Decision Tools'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.history), text: 'History'),
            Tab(icon: Icon(Icons.timeline), text: 'Walk-Forward'),
            Tab(icon: Icon(Icons.shuffle), text: 'Monte Carlo'),
            Tab(icon: Icon(Icons.score), text: 'Robustness'),
            Tab(icon: Icon(Icons.compare), text: 'Compare'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _HistoryTab(
            api: widget.apiService,
            onSelect: (r) => setState(() => _selectedRun = r),
          ),
          _WalkForwardTab(api: widget.apiService),
          _MonteCarloTab(api: widget.apiService, selectedRun: _selectedRun),
          _RobustnessTab(api: widget.apiService),
          _CompareTab(api: widget.apiService),
        ],
      ),
    );
  }
}


// ──────────────────────────────────────────────────────────────────────────
// History tab — browse persisted backtest results
// ──────────────────────────────────────────────────────────────────────────

class _HistoryTab extends StatefulWidget {
  final ApiService api;
  final ValueChanged<Map<String, dynamic>>? onSelect;
  const _HistoryTab({required this.api, this.onSelect});

  @override
  State<_HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<_HistoryTab> {
  List<Map<String, dynamic>> _runs = [];
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _detail;
  final _symbolFilter = TextEditingController();
  final _timeframeFilter = TextEditingController();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _symbolFilter.dispose();
    _timeframeFilter.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final runs = await widget.api.listResults(
        symbol: _symbolFilter.text.trim().isEmpty ? null : _symbolFilter.text.trim(),
        timeframe: _timeframeFilter.text.trim().isEmpty ? null : _timeframeFilter.text.trim(),
        limit: 100,
      );
      setState(() {
        _runs = runs;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _selectRun(String runId) async {
    try {
      final r = await widget.api.getResult(runId);
      setState(() => _detail = r);
      widget.onSelect?.call(r);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _exportHtml(String runId) async {
    try {
      final html = await widget.api.downloadReportHtml(runId);
      final dir = Directory('${Directory.current.path}/exports');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final subDir = Directory('${dir.path}/run_$ts');
      subDir.createSync();
      final outFile = File('${subDir.path}/report.html');
      await outFile.writeAsString(html);
      await Clipboard.setData(ClipboardData(text: outFile.path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF26a69a),
        content: Text(
          'HTML report saved → ${outFile.path} (path copied)',
          style: const TextStyle(color: Colors.black, fontSize: 12),
        ),
        duration: const Duration(seconds: 4),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export HTML report: $e')),
      );
    }
  }

  Future<void> _delete(String runId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete run?'),
        content: Text('Permanently remove $runId from history?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await widget.api.deleteResult(runId);
        await _reload();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(children: [
            SizedBox(
              width: 140,
              child: TextField(
                controller: _symbolFilter,
                decoration: const InputDecoration(labelText: 'Symbol filter', isDense: true),
                onSubmitted: (_) => _reload(),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 120,
              child: TextField(
                controller: _timeframeFilter,
                decoration: const InputDecoration(labelText: 'Timeframe', isDense: true),
                onSubmitted: (_) => _reload(),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Reload'),
            ),
            const Spacer(),
            Text('${_runs.length} runs', style: const TextStyle(color: Colors.grey)),
          ]),
          const SizedBox(height: 8),
          if (_error != null) Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Row(children: [
                    // Left: run list
                    Expanded(flex: 2, child: _buildRunList()),
                    const VerticalDivider(),
                    // Right: detail
                    Expanded(flex: 3, child: _buildDetail()),
                  ]),
          ),
        ],
      ),
    );
  }

  Widget _buildRunList() {
    if (_runs.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No backtest results yet.\nRun a backtest from the main screen to populate history.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _runs.length,
      itemBuilder: (_, i) {
        final r = _runs[i];
        final runId = r['run_id'] as String? ?? '';
        final isSelected = _detail?['run_id'] == runId;
        final payload = (r['payload'] as Map?) ?? r;
        final summary = (payload['summary'] as Map?) ?? {};
        final ret = (summary['total_return_pct'] as num?)?.toDouble() ?? 0;
        final trades = (summary['trades'] as num?)?.toInt() ?? 0;
        final dd = (summary['max_drawdown_pct'] as num?)?.toDouble() ?? 0;
        return Card(
          color: isSelected ? Colors.indigo.withValues(alpha: 0.15) : null,
          margin: const EdgeInsets.symmetric(vertical: 3),
          child: ListTile(
            dense: true,
            title: Text('${r['symbol']} ${r['timeframe']}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              'Return: ${ret.toStringAsFixed(2)}%  •  Trades: $trades  •  DD: ${dd.toStringAsFixed(2)}%',
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _delete(runId),
            ),
            onTap: () => _selectRun(runId),
          ),
        );
      },
    );
  }

  Widget _buildDetail() {
    if (_detail == null) {
      return const Center(
        child: Text('Select a run to see details', style: TextStyle(color: Colors.grey)),
      );
    }
    final payload = (_detail!['payload'] as Map?) ?? _detail!;
    final summary = (payload['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final perBot = (payload['per_bot'] as Map?)?.cast<String, dynamic>() ?? {};
    final trades = (payload['trades'] as List?) ?? [];

    final runId = _detail!['run_id']?.toString() ?? '';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SelectableText('Run ID: $runId',
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11)),
              ),
              OutlinedButton.icon(
                onPressed: runId.isEmpty ? null : () => _exportHtml(runId),
                icon: const Icon(Icons.description_outlined, size: 16),
                label: const Text('Export HTML report'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: summary.entries.map((e) =>
                _MetricChip(label: e.key, value: e.value)).toList(),
          ),
          const SizedBox(height: 16),
          if (perBot.isNotEmpty) ...[
            const Text('Per-bot metrics', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            ...perBot.entries.map((e) => Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${e.value}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                  ],
                ),
              ),
            )),
          ],
          const SizedBox(height: 8),
          if (trades.isNotEmpty) ...[
            Text('Trades (${trades.length})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            _TradesPreview(trades: trades.cast<Map<String, dynamic>>()),
          ],
        ],
      ),
    );
  }
}


class _MetricChip extends StatelessWidget {
  final String label;
  final dynamic value;
  const _MetricChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final String text;
    Color color = Colors.grey.shade700;
    if (value is num) {
      text = value.toStringAsFixed(2);
      if (label.contains('return') || label.contains('profit')) {
        color = value > 0 ? Colors.green : Colors.red;
      } else if (label.contains('drawdown') || label.contains('mae')) {
        color = value.abs() > 10 ? Colors.orange : Colors.grey.shade700;
      }
    } else {
      text = '$value';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.replaceAll('_', ' '),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          Text(text, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}


class _TradesPreview extends StatelessWidget {
  final List<Map<String, dynamic>> trades;
  const _TradesPreview({required this.trades});

  @override
  Widget build(BuildContext context) {
    final show = trades.take(50).toList();
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 30,
          dataRowMinHeight: 26,
          dataRowMaxHeight: 26,
          columns: const [
            DataColumn(label: Text('#')),
            DataColumn(label: Text('Bot')),
            DataColumn(label: Text('PnL')),
            DataColumn(label: Text('PnL%')),
            DataColumn(label: Text('MFE%')),
            DataColumn(label: Text('MAE%')),
            DataColumn(label: Text('Bars')),
            DataColumn(label: Text('Reason')),
          ],
          rows: List.generate(show.length, (i) {
            final t = show[i];
            final pnl = (t['pnl'] as num?)?.toDouble() ?? 0;
            return DataRow(cells: [
              DataCell(Text('${i + 1}')),
              DataCell(Text(t['bot_id']?.toString() ?? '')),
              DataCell(Text(pnl.toStringAsFixed(2),
                  style: TextStyle(color: pnl >= 0 ? Colors.green : Colors.red))),
              DataCell(Text(((t['pnl_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(2))),
              DataCell(Text(((t['mfe_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
                  style: const TextStyle(color: Colors.green))),
              DataCell(Text(((t['mae_pct'] as num?)?.toDouble() ?? 0).toStringAsFixed(2),
                  style: const TextStyle(color: Colors.red))),
              DataCell(Text('${(t['duration_bars'] as num?)?.toInt() ?? 0}')),
              DataCell(Text(t['reason']?.toString() ?? '', style: const TextStyle(fontSize: 10))),
            ]);
          }),
        ),
      ),
    );
  }
}


// ──────────────────────────────────────────────────────────────────────────
// Walk-Forward Analysis tab
// ──────────────────────────────────────────────────────────────────────────

class _WalkForwardTab extends StatefulWidget {
  final ApiService api;
  const _WalkForwardTab({required this.api});

  @override
  State<_WalkForwardTab> createState() => _WalkForwardTabState();
}

class _WalkForwardTabState extends State<_WalkForwardTab> {
  final _symbol = TextEditingController(text: 'BTCUSDT');
  final _timeframe = TextEditingController(text: '1h');
  final _bot = TextEditingController(text: 'EMACross');
  final _trainSize = TextEditingController(text: '500');
  final _testSize = TextEditingController(text: '100');
  final _trials = TextEditingController(text: '20');
  final _paramRangesJson = TextEditingController(
    text: '{"fast_ema": [5, 20], "slow_ema": [21, 50]}',
  );
  bool _anchored = false;
  String _objective = 'total_return_pct';
  bool _running = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _symbol.dispose();
    _timeframe.dispose();
    _bot.dispose();
    _trainSize.dispose();
    _testSize.dispose();
    _trials.dispose();
    _paramRangesJson.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });
    try {
      // Parse param_ranges JSON
      Map<String, List<double>> ranges;
      try {
        final raw = jsonDecodeSafe(_paramRangesJson.text);
        ranges = {};
        (raw as Map).forEach((k, v) {
          final list = (v as List).map((e) => (e as num).toDouble()).toList();
          ranges[k as String] = list;
        });
      } catch (_) {
        throw const FormatException(
          'param_ranges JSON must be like {"fast_ema": [5, 20], ...}',
        );
      }
      final r = await widget.api.runWalkForward(
        symbol: _symbol.text.trim().toUpperCase(),
        timeframe: _timeframe.text.trim(),
        bot: _bot.text.trim(),
        baseParams: const {},
        paramRanges: ranges,
        trainSize: int.parse(_trainSize.text),
        testSize: int.parse(_testSize.text),
        anchored: _anchored,
        trialsPerWindow: int.parse(_trials.text),
        objectiveMetric: _objective,
      );
      setState(() {
        _result = r;
        _running = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Walk-Forward Analysis',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Optimize on a rolling in-sample window, then validate on the '
              'following out-of-sample window. The verdict tells you whether '
              'this strategy is robust or overfit.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _fieldBox('Symbol', _symbol, width: 110),
                _fieldBox('Timeframe', _timeframe, width: 90),
                _fieldBox('Bot', _bot, width: 130),
                _fieldBox('Train size', _trainSize, width: 100),
                _fieldBox('Test size', _testSize, width: 100),
                _fieldBox('Trials/window', _trials, width: 110),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _objective,
                    decoration: const InputDecoration(labelText: 'Objective metric'),
                    items: const [
                      DropdownMenuItem(value: 'total_return_pct', child: Text('Total return %')),
                      DropdownMenuItem(value: 'sharpe_ratio', child: Text('Sharpe ratio')),
                      DropdownMenuItem(value: 'profit_factor', child: Text('Profit factor')),
                      DropdownMenuItem(value: 'recovery_factor', child: Text('Recovery factor')),
                      DropdownMenuItem(value: 'max_drawdown_pct', child: Text('Max DD % (min)')),
                    ],
                    onChanged: (v) => setState(() => _objective = v ?? 'total_return_pct'),
                  ),
                ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(value: _anchored, onChanged: (v) => setState(() => _anchored = v ?? false)),
                  const Text('Anchored (expand train)'),
                ]),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _paramRangesJson,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Parameter ranges (JSON)',
                helperText: 'Map of param name → [low, high] to optimize each window',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_running ? 'Running walk-forward...' : 'Run Walk-Forward'),
            ),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
            if (_result != null) ...[
              const SizedBox(height: 24),
              _WalkForwardSummary(result: _result!),
            ],
          ],
        ),
      ),
    );
  }
}


Widget _fieldBox(String label, TextEditingController c, {double width = 100}) {
  return SizedBox(
    width: width,
    child: TextField(
      controller: c,
      decoration: InputDecoration(labelText: label, isDense: true),
    ),
  );
}


class _WalkForwardSummary extends StatelessWidget {
  final Map<String, dynamic> result;
  const _WalkForwardSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final summary = (result['summary'] as Map).cast<String, dynamic>();
    final windows = (result['windows'] as List).cast<Map<String, dynamic>>();
    final verdict = summary['verdict'] as String;
    final verdictColor = _verdictColor(verdict);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: verdictColor.withValues(alpha: 0.15),
            border: Border.all(color: verdictColor, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Icon(_verdictIcon(verdict), color: verdictColor, size: 32),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Verdict: ${verdict.toUpperCase()}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: verdictColor)),
              Text(_verdictExplanation(verdict),
                  style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _MetricChip(label: 'Avg OOS return %', value: summary['avg_oos_return_pct']),
          _MetricChip(label: 'Avg IS return %', value: summary['avg_is_return_pct']),
          _MetricChip(label: 'Efficiency', value: summary['efficiency_ratio']),
          _MetricChip(label: 'Consistency', value: summary['consistency']),
          _MetricChip(
            label: 'Profitable windows',
            value: '${summary['profitable_windows']}/${summary['total_windows']}',
          ),
        ]),
        const SizedBox(height: 16),
        const Text('Per-window detail', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _WindowsTable(windows: windows),
      ],
    );
  }

  static Color _verdictColor(String v) => switch (v) {
        'robust' => Colors.green,
        'weak' => Colors.orange,
        'overfit' => Colors.red,
        _ => Colors.grey,
      };
  static IconData _verdictIcon(String v) => switch (v) {
        'robust' => Icons.verified,
        'weak' => Icons.warning_amber,
        'overfit' => Icons.error,
        _ => Icons.help_outline,
      };
  static String _verdictExplanation(String v) => switch (v) {
        'robust' => 'OOS positive, efficient, and consistent — safe to deploy with caution.',
        'weak'   => 'OOS positive but unstable. Re-tune or reduce position size.',
        'overfit'=> 'IS optimization does not generalize. Do NOT deploy this setup.',
        _ => 'Not enough data to draw a conclusion. Try smaller windows or more candles.',
      };
}


class _WindowsTable extends StatelessWidget {
  final List<Map<String, dynamic>> windows;
  const _WindowsTable({required this.windows});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 30,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 28,
          columns: const [
            DataColumn(label: Text('#')),
            DataColumn(label: Text('IS range')),
            DataColumn(label: Text('OOS range')),
            DataColumn(label: Text('IS return %')),
            DataColumn(label: Text('OOS return %')),
            DataColumn(label: Text('Efficiency')),
            DataColumn(label: Text('Best params')),
          ],
          rows: windows.map((w) {
            final isRange = (w['is_range'] as List);
            final oosRange = (w['oos_range'] as List);
            final isMet = (w['is_metrics'] as Map?) ?? {};
            final oosMet = (w['oos_metrics'] as Map?) ?? {};
            final isRet = (isMet['total_return_pct'] as num?)?.toDouble() ?? 0;
            final oosRet = (oosMet['total_return_pct'] as num?)?.toDouble() ?? 0;
            final eff = (w['efficiency'] as num?)?.toDouble() ?? 0;
            return DataRow(cells: [
              DataCell(Text('${w['window_idx']}')),
              DataCell(Text('${isRange[0]}–${isRange[1]}')),
              DataCell(Text('${oosRange[0]}–${oosRange[1]}')),
              DataCell(Text(isRet.toStringAsFixed(2),
                  style: TextStyle(color: isRet >= 0 ? Colors.green : Colors.red))),
              DataCell(Text(oosRet.toStringAsFixed(2),
                  style: TextStyle(color: oosRet >= 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.bold))),
              DataCell(Text(eff.toStringAsFixed(2),
                  style: TextStyle(color: eff > 0.5 ? Colors.green : Colors.orange))),
              DataCell(Text(
                (w['best_params'] as Map).entries
                    .map((e) => '${e.key}=${e.value}').join(', '),
                style: const TextStyle(fontSize: 10),
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}


// ──────────────────────────────────────────────────────────────────────────
// Monte Carlo tab
// ──────────────────────────────────────────────────────────────────────────

class _MonteCarloTab extends StatefulWidget {
  final ApiService api;
  final Map<String, dynamic>? selectedRun;
  const _MonteCarloTab({required this.api, this.selectedRun});

  @override
  State<_MonteCarloTab> createState() => _MonteCarloTabState();
}

class _MonteCarloTabState extends State<_MonteCarloTab> {
  final _trials = TextEditingController(text: '1000');
  final _initial = TextEditingController(text: '10000');
  String _method = 'shuffle';
  bool _running = false;
  String? _error;
  Map<String, dynamic>? _result;

  @override
  void dispose() {
    _trials.dispose();
    _initial.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final run = widget.selectedRun;
    if (run == null) {
      setState(() => _error = 'Select a run from the History tab first.');
      return;
    }
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await widget.api.runMonteCarlo(
        runId: run['run_id'] as String,
        trials: int.parse(_trials.text),
        method: _method,
        initialEquity: double.parse(_initial.text),
      );
      setState(() {
        _result = r;
        _running = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final run = widget.selectedRun;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Monte Carlo Simulation',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Text(
              'Resample the trade sequence many times to see what range of '
              'outcomes was possible. P5 is your "worst credible case", P50 '
              'the median, P95 the upside.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: run == null ? Colors.orange.shade100 : Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(children: [
                Icon(run == null ? Icons.warning : Icons.check_circle,
                    color: run == null ? Colors.orange : Colors.indigo),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    run == null
                        ? 'Pick a run in the History tab to simulate its trade sequence.'
                        : 'Source: ${run['symbol']} ${run['timeframe']} '
                          '(run ${run['run_id']?.toString().substring(0, 8)}...)',
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12, runSpacing: 12,
              children: [
                _fieldBox('Trials', _trials, width: 100),
                _fieldBox('Initial equity', _initial, width: 130),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _method,
                    decoration: const InputDecoration(labelText: 'Method'),
                    items: const [
                      DropdownMenuItem(value: 'shuffle', child: Text('Shuffle (order randomization)')),
                      DropdownMenuItem(value: 'bootstrap', child: Text('Bootstrap (with replacement)')),
                    ],
                    onChanged: (v) => setState(() => _method = v ?? 'shuffle'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _running ? null : _run,
              icon: _running
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_running ? 'Simulating...' : 'Run Simulation'),
            ),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              _MonteCarloSummary(result: _result!),
            ],
          ],
        ),
      ),
    );
  }
}


class _MonteCarloSummary extends StatelessWidget {
  final Map<String, dynamic> result;
  const _MonteCarloSummary({required this.result});

  @override
  Widget build(BuildContext context) {
    final ret = (result['return_pct'] as Map).cast<String, dynamic>();
    final dd = (result['max_drawdown_pct'] as Map).cast<String, dynamic>();
    final streak = (result['worst_losing_streak'] as Map).cast<String, dynamic>();
    final pp = (result['prob_profit'] as num).toDouble();
    final pr = (result['prob_ruin'] as num).toDouble();
    final var95 = (result['var_95_pct'] as num).toDouble();
    final cvar = (result['cvar_95_pct'] as num).toDouble();
    final curves = ((result['sample_curves'] as List?) ?? [])
        .map((c) => (c as List).map((v) => (v as num).toDouble()).toList())
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Trials: ${result['n_trials']}  •  Trades: ${result['n_trades']}',
            style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _percTable('Return %', ret)),
          const SizedBox(width: 8),
          Expanded(child: _percTable('Max DD %', dd)),
          const SizedBox(width: 8),
          Expanded(child: _percTable('Worst streak', streak)),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _bigMetric('P(profit)', '${(pp * 100).toStringAsFixed(1)}%',
              color: pp > 0.6 ? Colors.green : Colors.orange),
          _bigMetric('P(ruin)', '${(pr * 100).toStringAsFixed(1)}%',
              color: pr > 0.1 ? Colors.red : Colors.green),
          _bigMetric('VaR 95%', '${var95.toStringAsFixed(2)}%', color: Colors.red),
          _bigMetric('CVaR 95%', '${cvar.toStringAsFixed(2)}%', color: Colors.red),
        ]),
        const SizedBox(height: 16),
        if (curves.isNotEmpty) ...[
          const Text('Sample equity curves (${20} of trials)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          SizedBox(
            height: 250,
            child: CustomPaint(
              painter: _CurvesPainter(curves: curves),
              size: const Size(double.infinity, 250),
            ),
          ),
        ],
      ],
    );
  }

  Widget _percTable(String title, Map<String, dynamic> p) {
    Widget row(String k, dynamic v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(k, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text((v as num).toStringAsFixed(2),
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
      ]),
    );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        const Divider(height: 8),
        row('P5  (worst case)', p['p5']),
        row('P25', p['p25']),
        row('P50 (median)', p['p50']),
        row('P75', p['p75']),
        row('P95 (best case)', p['p95']),
        row('mean', p['mean']),
        row('std', p['std']),
      ]),
    );
  }

  Widget _bigMetric(String label, String value, {required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 11, color: color)),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}


class _CurvesPainter extends CustomPainter {
  final List<List<double>> curves;
  _CurvesPainter({required this.curves});

  @override
  void paint(Canvas canvas, Size size) {
    if (curves.isEmpty) return;
    // Find global min/max
    double minV = double.infinity, maxV = -double.infinity;
    int maxLen = 0;
    for (final c in curves) {
      for (final v in c) {
        if (v < minV) minV = v;
        if (v > maxV) maxV = v;
      }
      if (c.length > maxLen) maxLen = c.length;
    }
    if (maxV == minV) return;
    // Draw each curve with low alpha so overlapping reveals density
    final paint = Paint()
      ..color = Colors.indigo.withValues(alpha: 0.18)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final c in curves) {
      final path = Path();
      for (int i = 0; i < c.length; i++) {
        final x = i / (maxLen - 1) * size.width;
        final y = size.height - ((c[i] - minV) / (maxV - minV)) * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
    // Initial equity baseline (dashed)
    final initial = curves[0][0];
    final yBase = size.height - ((initial - minV) / (maxV - minV)) * size.height;
    final base = Paint()..color = Colors.grey..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, yBase), Offset(x + 3, yBase), base);
    }
  }

  @override
  bool shouldRepaint(_) => true;
}


// ──────────────────────────────────────────────────────────────────────────
// Robustness tab — compare candidates side-by-side
// ──────────────────────────────────────────────────────────────────────────

class _RobustnessTab extends StatefulWidget {
  final ApiService api;
  const _RobustnessTab({required this.api});

  @override
  State<_RobustnessTab> createState() => _RobustnessTabState();
}

class _RobustnessTabState extends State<_RobustnessTab> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _runs = [];
  List<Map<String, dynamic>> _ranked = [];
  bool _scoring = false;

  @override
  void initState() {
    super.initState();
    _loadRuns();
  }

  Future<void> _loadRuns() async {
    setState(() => _loading = true);
    try {
      _runs = await widget.api.listResults(limit: 200);
      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _score() async {
    setState(() => _scoring = true);
    try {
      final cands = _runs.map((r) {
        final payload = (r['payload'] as Map?) ?? r;
        final summary = (payload['summary'] as Map?) ?? {};
        return {
          'params': {
            'run': (r['run_id'] as String? ?? '').substring(0, 8),
            'symbol': r['symbol'],
            'tf': r['timeframe'],
          },
          'metrics': Map<String, dynamic>.from(summary),
        };
      }).toList();
      _ranked = await widget.api.rankRobustness(candidates: cands);
      setState(() => _scoring = false);
    } catch (e) {
      setState(() {
        _error = '$e';
        _scoring = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Robustness Ranking',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Ranks all your saved runs by a weighted composite of Sharpe, '
            'profit factor, recovery factor, win rate, and trade count.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton.icon(
              onPressed: _runs.isEmpty || _scoring ? null : _score,
              icon: _scoring
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.score),
              label: Text(_scoring ? 'Scoring...' : 'Rank ${_runs.length} runs'),
            ),
            const SizedBox(width: 12),
            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
          ]),
          const SizedBox(height: 12),
          if (_ranked.isNotEmpty) Expanded(child: _buildLeaderboard()),
          if (_ranked.isEmpty && !_scoring) const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No ranking computed yet. Click "Rank runs" after generating '
              'a few backtest results.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeaderboard() {
    return ListView.builder(
      itemCount: _ranked.length,
      itemBuilder: (_, i) {
        final r = _ranked[i];
        final score = (r['score'] as num).toDouble();
        final metrics = (r['metrics'] as Map?) ?? {};
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 3),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: _rankColor(r['rank'] as int),
                child: Text('${r['rank']}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(r['label']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(
                    'Sharpe ${(metrics['sharpe_ratio'] ?? 0).toStringAsFixed(2)}  •  '
                    'Return ${(metrics['total_return_pct'] ?? 0).toStringAsFixed(2)}%  •  '
                    'DD ${(metrics['max_drawdown_pct'] ?? 0).toStringAsFixed(2)}%  •  '
                    'Trades ${metrics['trades']}',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ]),
              ),
              Column(children: [
                Text(score.toStringAsFixed(3),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('score', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ]),
            ]),
          ),
        );
      },
    );
  }

  Color _rankColor(int rank) {
    if (rank == 1) return const Color(0xFFD4AF37);  // gold
    if (rank == 2) return const Color(0xFFC0C0C0);  // silver
    if (rank == 3) return const Color(0xFFCD7F32);  // bronze
    return Colors.indigo;
  }
}


// ──────────────────────────────────────────────────────────────────────────
// Helpers
// ──────────────────────────────────────────────────────────────────────────

dynamic jsonDecodeSafe(String s) {
  // Light wrapper that gives a more useful exception type for the UI
  // (Dart's default jsonDecode throws FormatException already)
  return jsonDecodeOrNull(s) ??
      (throw const FormatException('Invalid JSON'));
}

dynamic jsonDecodeOrNull(String s) {
  try {
    return jsonDecode(s);
  } catch (_) {
    return null;
  }
}

// (jsonDecode is imported at the top of this file)


// ──────────────────────────────────────────────────────────────────────────
// Compare tab — side-by-side run comparator
// ──────────────────────────────────────────────────────────────────────────

class _CompareTab extends StatefulWidget {
  final ApiService api;
  const _CompareTab({required this.api});

  @override
  State<_CompareTab> createState() => _CompareTabState();
}

class _CompareTabState extends State<_CompareTab> {
  bool _loadingHistory = true;
  String? _error;
  List<Map<String, dynamic>> _history = [];
  final Set<String> _selectedIds = <String>{};
  List<Map<String, dynamic>> _comparedRuns = [];
  List<String> _missingRunIds = [];
  bool _comparing = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _error = null;
    });
    try {
      final runs = await widget.api.listResults(limit: 200);
      setState(() {
        _history = runs;
        _loadingHistory = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loadingHistory = false;
      });
    }
  }

  Future<void> _compare() async {
    if (_selectedIds.isEmpty) return;
    setState(() {
      _comparing = true;
      _error = null;
    });
    try {
      final res = await widget.api.compareRuns(runIds: _selectedIds.toList());
      setState(() {
        _comparedRuns = ((res['runs'] as List?) ?? [])
            .cast<Map<String, dynamic>>();
        _missingRunIds = ((res['missing'] as List?) ?? [])
            .map((e) => e.toString())
            .toList();
        _comparing = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _comparing = false;
      });
    }
  }

  void _openSelector() async {
    final picked = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _RunSelectorDialog(
        history: _history,
        initiallySelected: _selectedIds,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedIds
          ..clear()
          ..addAll(picked);
      });
      if (_selectedIds.isNotEmpty) {
        await _compare();
      } else {
        setState(() {
          _comparedRuns = [];
          _missingRunIds = [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Run Comparator',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const Text(
            'Pick up to 10 stored runs and compare their key metrics + '
            'equity curves side-by-side.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton.icon(
              onPressed: _openSelector,
              icon: const Icon(Icons.checklist),
              label: Text(_selectedIds.isEmpty
                  ? 'Pick runs'
                  : 'Pick runs (${_selectedIds.length} selected)'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _loadHistory,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Reload history'),
            ),
            if (_comparing) const Padding(
              padding: EdgeInsets.only(left: 12),
              child: SizedBox(
                width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ]),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: const TextStyle(color: Colors.red)),
          ),
          if (_missingRunIds.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Missing runs (deleted?): ${_missingRunIds.join(", ")}',
              style: const TextStyle(color: Colors.orange, fontSize: 11),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: ComparePanel(
                runs: _comparedRuns,
                onAddRun: _openSelector,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _RunSelectorDialog extends StatefulWidget {
  final List<Map<String, dynamic>> history;
  final Set<String> initiallySelected;
  const _RunSelectorDialog({
    required this.history,
    required this.initiallySelected,
  });

  @override
  State<_RunSelectorDialog> createState() => _RunSelectorDialogState();
}

class _RunSelectorDialogState extends State<_RunSelectorDialog> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initiallySelected);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Select runs to compare'),
      content: SizedBox(
        width: 460, height: 420,
        child: ListView.builder(
          itemCount: widget.history.length,
          itemBuilder: (_, i) {
            final r = widget.history[i];
            final runId = r['run_id'] as String? ?? '';
            final payload = (r['payload'] as Map?) ?? (r['result'] as Map?) ?? r;
            final summary = (payload['summary'] as Map?) ?? {};
            final ret = (summary['total_return_pct'] as num?)?.toDouble() ?? 0;
            return CheckboxListTile(
              dense: true,
              value: _selected.contains(runId),
              onChanged: (v) => setState(() {
                if (v == true && _selected.length < 10) {
                  _selected.add(runId);
                } else {
                  _selected.remove(runId);
                }
              }),
              title: Text('${r['symbol']} ${r['timeframe']}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Return ${ret.toStringAsFixed(2)}%  •  id ${runId.substring(0, runId.length.clamp(0, 8))}…',
                style: const TextStyle(fontSize: 11),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => setState(_selected.clear),
          child: const Text('Clear'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text('Compare (${_selected.length})'),
        ),
      ],
    );
  }
}
