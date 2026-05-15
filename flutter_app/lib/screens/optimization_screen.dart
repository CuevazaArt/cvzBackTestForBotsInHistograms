import 'dart:async';
import 'package:flutter/material.dart';
import 'package:backtester_shell/services/api_service.dart';
import 'package:backtester_shell/services/ws_service.dart';
import 'package:backtester_shell/utils/param_grid.dart';
import 'package:backtester_shell/widgets/param_bounds_editor.dart';

/// Payload handed off to the Backtest screen when the user clicks "Apply best".
class OptimizationResult {
  final String symbol;
  final String timeframe;
  final String botName;
  final Map<String, dynamic> params;
  const OptimizationResult({
    required this.symbol,
    required this.timeframe,
    required this.botName,
    required this.params,
  });
}

class OptimizationScreen extends StatefulWidget {
  final ApiService apiService;
  final WsService wsService;
  final ValueChanged<OptimizationResult>? onApplyBest;
  const OptimizationScreen({super.key, required this.apiService, required this.wsService, this.onApplyBest});

  @override
  State<OptimizationScreen> createState() => _OptimizationScreenState();
}

class _OptimizationScreenState extends State<OptimizationScreen> {
  List<SymbolEntry> _symbols = [];
  List<BotInfo> _bots = [];
  String? _selectedSymbol;
  String _selectedTimeframe = '1h';
  String? _selectedBot;

  Map<String, ParamSpec> _paramSpecs = {};
  Map<String, ParamBound> _bounds = {};

  bool _running = false;
  String? _error;
  String? _info;
  double _progress = 0;
  String? _jobMessage;
  Timer? _poll;

  // Latest sweep output (sorted by total_return_pct desc).
  List<_TrialRow> _trials = [];

  int _maxWorkers = 4;

  // ── Optimizer mode ────────────────────────────────────────────
  String _mode = 'grid';          // 'grid' | 'tpe' | 'cmaes' | 'random'
  int _optunaTrials = 100;
  String _objective = 'total_return_pct';

  WsService get _ws => widget.wsService;
  StreamSubscription<WsEvent>? _wsSub;

  @override
  void initState() {
    super.initState();
    _wsSub = _ws.events.listen(_onWsEvent);
    _loadCatalog();
  }

  void _onWsEvent(WsEvent ev) {
    switch (ev.type) {
      case WsEventType.trialCompleted:
        if (!mounted) return;
        final m = ev.data['metrics'] as Map<String, dynamic>? ?? {};
        setState(() {
          _progress = (ev.data['trial'] as int) / _optunaTrials * 100;
          _info = 'Completed trial ${ev.data['trial']} / $_optunaTrials';
          _trials.add(_TrialRow(
            bot: _selectedBot ?? '?',
            params: Map<String, dynamic>.from(ev.data['params'] ?? {}),
            success: true,
            error: null,
            returnPct: (m['total_return_pct'] as num?)?.toDouble() ?? double.nan,
            trades: (m['trades'] as num?)?.toInt() ?? 0,
            winRatePct: (m['win_rate_pct'] as num?)?.toDouble() ?? 0,
            profitFactor: (m['profit_factor'] as num?)?.toDouble() ?? 0,
            maxDdPct: (m['max_drawdown_pct'] as num?)?.toDouble() ?? 0,
            finalEquity: (m['final_equity'] as num?)?.toDouble() ?? 0,
          ));
          _trials.sort((a, b) => b.returnPct.compareTo(a.returnPct));
        });
      case WsEventType.optimizeDone:
        if (!mounted) return;
        setState(() {
          _running = false;
          _progress = 100;
          _info = 'Optimization completed.';
        });
      case WsEventType.error:
        if (!mounted) return;
        setState(() {
          _running = false;
          _error = ev.data['message'] as String? ?? 'Optimization error';
        });
      case WsEventType.reconnecting:
      case WsEventType.disconnected:
        if (!mounted) return;
        if (_running) {
          setState(() {
            _running = false;
            _error = 'Connection lost';
          });
        }
      default:
        break;
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _wsSub?.cancel();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final syms = await widget.apiService.listSymbols();
      final bots = await widget.apiService.listBots();
      if (mounted) {
        setState(() {
          _symbols = syms;
          _bots = bots;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadBotParams(String botName) async {
    try {
      final res = await widget.apiService.getBotParams(botName);
      if (mounted) {
        setState(() {
          _paramSpecs = res.params;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _runOptimization() async {
    if (_selectedSymbol == null || _selectedBot == null) return;

    if (_mode == 'grid') {
      return _runGridSweep();
    } else {
      return _runOptuna();
    }
  }

  Future<void> _runGridSweep() async {
    final grid = expandBounds(_bounds, cap: 200);
    if (grid.combos.isEmpty) {
      setState(() => _error = 'Search space is empty. Adjust the param bounds.');
      return;
    }

    setState(() {
      _running = true;
      _error = null;
      _info = grid.capped
          ? 'Grid capped at 200 combos (would have been ${grid.wouldHaveBeen}).'
          : 'Running ${grid.combos.length} combinations…';
      _progress = 0;
      _trials = [];
      _jobMessage = null;
    });

    try {
      final jobId = await widget.apiService.runOptimization(
        symbol: _selectedSymbol!,
        timeframe: _selectedTimeframe,
        bots: [
          {'name': _selectedBot, 'configs': grid.combos},
        ],
        workers: _maxWorkers,
      );
      _startPolling(jobId);
    } on ApiValidationError catch (e) {
      setState(() {
        _running = false;
        _error = 'Validation: $e';
      });
    } catch (e) {
      setState(() {
        _running = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _runOptuna() async {
    // Build search_space from bounds
    final searchSpace = <String, Map<String, dynamic>>{};
    final fixedParams = <String, dynamic>{};
    for (final entry in _bounds.entries) {
      final b = entry.value;
      if (b.optimize) {
        searchSpace[entry.key] = {
          'type': b.type,
          'low': b.min,
          'high': b.max,
          if (b.step != null) 'step': b.step,
        };
      } else {
        fixedParams[entry.key] = b.fixedValue;
      }
    }
    if (searchSpace.isEmpty) {
      setState(() => _error = 'No params to optimize. Enable at least one checkbox.');
      return;
    }

    setState(() {
      _running = true;
      _error = null;
      _info = 'Running $_optunaTrials trials via ${_mode.toUpperCase()} sampler…';
      _progress = 0;
      _trials = [];
      _jobMessage = null;
    });

    try {
      _ws.runOptimize(
        symbol: _selectedSymbol!,
        timeframe: _selectedTimeframe,
        bot: _selectedBot!,
        searchSpace: searchSpace,
        fixedParams: fixedParams,
        objective: _objective,
        trials: _optunaTrials,
        sampler: _mode == 'cmaes' ? 'cma' : _mode,
      );
    } on ApiValidationError catch (e) {
      setState(() {
        _running = false;
        _error = 'Validation: $e';
      });
    } catch (e) {
      setState(() {
        _running = false;
        _error = e.toString();
      });
    }
  }

  void _startPolling(String jobId) {
    _poll = Timer.periodic(const Duration(seconds: 1), (timer) async {
      try {
        final st = await widget.apiService.getJob(jobId);
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _progress = st.progress;
          _jobMessage = st.message;
        });
        if (st.status == 'done') {
          timer.cancel();
          _onJobDone(st);
        } else if (st.status == 'error') {
          timer.cancel();
          setState(() {
            _running = false;
            _error = st.message ?? 'Optimization failed';
          });
        }
      } catch (e) {
        // Network blip — ignore one tick.
      }
    });
  }

  void _onJobDone(JobStatus st) {
    final runs = (st.result?['runs'] as List?) ?? [];
    final rows = <_TrialRow>[];
    for (final r in runs) {
      final m = r as Map<String, dynamic>;
      final ok = m['success'] as bool? ?? false;
      final metrics = (m['metrics'] as Map?)?.cast<String, dynamic>() ?? const {};
      rows.add(_TrialRow(
        bot: m['bot'] as String? ?? '?',
        params: Map<String, dynamic>.from(m['params'] as Map? ?? {}),
        success: ok,
        error: m['error'] as String?,
        returnPct: (metrics['total_return_pct'] as num?)?.toDouble() ?? double.nan,
        trades: (metrics['trades'] as num?)?.toInt() ?? 0,
        winRatePct: (metrics['win_rate_pct'] as num?)?.toDouble() ?? 0,
        profitFactor: (metrics['profit_factor'] as num?)?.toDouble() ?? 0,
        maxDdPct: (metrics['max_drawdown_pct'] as num?)?.toDouble() ?? 0,
        finalEquity: (metrics['final_equity'] as num?)?.toDouble() ?? 0,
      ));
    }
    rows.sort((a, b) {
      // Success first, then by return desc.
      if (a.success != b.success) return a.success ? -1 : 1;
      if (a.returnPct.isNaN) return 1;
      if (b.returnPct.isNaN) return -1;
      return b.returnPct.compareTo(a.returnPct);
    });
    setState(() {
      _running = false;
      _trials = rows;
      _info = 'Completed ${rows.length} trials. Top: '
          '${rows.isNotEmpty && rows.first.success ? "${rows.first.returnPct.toStringAsFixed(2)}%" : "n/a"}';
    });
  }

  void _applyBest() {
    if (_trials.isEmpty || _selectedSymbol == null || _selectedBot == null) return;
    final top = _trials.firstWhere((t) => t.success, orElse: () => _trials.first);
    widget.onApplyBest?.call(OptimizationResult(
      symbol: _selectedSymbol!,
      timeframe: _selectedTimeframe,
      botName: _selectedBot!,
      params: top.params,
    ));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: const Color(0xFF26a69a),
      content: Text(
        'Applied best to Backtest: ${top.params}',
        style: const TextStyle(color: Colors.black, fontSize: 12),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _OptTopBar(
          symbols: _symbols,
          bots: _bots,
          selectedSymbol: _selectedSymbol,
          selectedTimeframe: _selectedTimeframe,
          selectedBot: _selectedBot,
          running: _running,
          progress: _progress * 100,
          maxWorkers: _maxWorkers,
          mode: _mode,
          optunaTrials: _optunaTrials,
          objective: _objective,
          onModeChanged: (v) => setState(() => _mode = v),
          onTrialsChanged: (v) => setState(() => _optunaTrials = v),
          onObjectiveChanged: (v) => setState(() => _objective = v),
          onWorkersChanged: (v) => setState(() => _maxWorkers = v),
          onSymbolChanged: (v) => setState(() => _selectedSymbol = v),
          onTimeframeChanged: (v) => setState(() => _selectedTimeframe = v),
          onBotChanged: (v) {
            setState(() {
              _selectedBot = v;
              _paramSpecs = {};
              _bounds = {};
            });
            if (v != null) _loadBotParams(v);
          },
          onRun: _runOptimization,
        ),
        if (_error != null)
          Container(
            color: const Color(0xFFef5350).withValues(alpha: 0.12),
            padding: const EdgeInsets.all(8),
            width: double.infinity,
            child: Row(
              children: [
                Expanded(child: Text('⚠ $_error', style: const TextStyle(color: Color(0xFFef5350), fontSize: 12))),
                IconButton(
                  iconSize: 14,
                  icon: const Icon(Icons.close, color: Color(0xFFef5350)),
                  onPressed: () => setState(() => _error = null),
                ),
              ],
            ),
          ),
        if (_info != null && _error == null)
          Container(
            color: const Color(0xFF26a69a).withValues(alpha: 0.10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            width: double.infinity,
            child: Text(_info!, style: const TextStyle(color: Color(0xFF26a69a), fontSize: 11)),
          ),
        if (_running && _jobMessage != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            width: double.infinity,
            child: Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFb388ff)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_jobMessage!, style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 11)),
                ),
                Text('${(_progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Color(0xFF787B86), fontSize: 11)),
              ],
            ),
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Parameter Setup
              SizedBox(
                width: 420,
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Color(0xFF2B2B43))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text('SEARCH SPACE',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                color: Color(0xFF787B86), letterSpacing: 1)),
                      ),
                      Expanded(
                        child: _selectedBot == null
                            ? const Center(
                                child: Text('Select a bot to define the search space',
                                    style: TextStyle(color: Color(0xFF787B86), fontSize: 12)),
                              )
                            : ParamBoundsEditor(
                                paramSpecs: _paramSpecs,
                                onChanged: (b) => _bounds = b,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              // Right: Leaderboard
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Row(
                        children: [
                          const Text('LEADERBOARD',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                  color: Color(0xFF787B86), letterSpacing: 1)),
                          const Spacer(),
                          if (_trials.isNotEmpty && widget.onApplyBest != null)
                            FilledButton.icon(
                              onPressed: _applyBest,
                              icon: const Icon(Icons.shortcut, size: 14),
                              label: const Text('Apply best to Backtest'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF26a69a),
                                minimumSize: const Size(0, 30),
                                textStyle: const TextStyle(fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _trials.isEmpty
                          ? Center(
                              child: Text(
                                _running
                                    ? 'Running trials…'
                                    : 'Configure bounds and click Run to start.',
                                style: const TextStyle(color: Color(0xFF787B86), fontSize: 12),
                              ),
                            )
                          : _LeaderboardTable(rows: _trials),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Leaderboard ─────────────────────────────────────────────────

class _TrialRow {
  final String bot;
  final Map<String, dynamic> params;
  final bool success;
  final String? error;
  final double returnPct;
  final int trades;
  final double winRatePct;
  final double profitFactor;
  final double maxDdPct;
  final double finalEquity;

  const _TrialRow({
    required this.bot,
    required this.params,
    required this.success,
    required this.error,
    required this.returnPct,
    required this.trades,
    required this.winRatePct,
    required this.profitFactor,
    required this.maxDdPct,
    required this.finalEquity,
  });
}

class _LeaderboardTable extends StatefulWidget {
  final List<_TrialRow> rows;
  const _LeaderboardTable({required this.rows});

  @override
  State<_LeaderboardTable> createState() => _LeaderboardTableState();
}

class _LeaderboardTableState extends State<_LeaderboardTable> {
  int _sortCol = 1; // default: Return
  bool _sortAsc = false;

  List<_TrialRow> get _sorted {
    final list = List<_TrialRow>.from(widget.rows);
    list.sort((a, b) {
      if (a.success != b.success) return a.success ? -1 : 1;
      int cmp(double x, double y) {
        if (x.isNaN) return 1;
        if (y.isNaN) return -1;
        return x.compareTo(y);
      }
      int r;
      switch (_sortCol) {
        case 1: r = cmp(a.returnPct, b.returnPct); break;
        case 2: r = a.trades.compareTo(b.trades); break;
        case 3: r = cmp(a.winRatePct, b.winRatePct); break;
        case 4: r = cmp(a.profitFactor, b.profitFactor); break;
        case 5: r = cmp(a.maxDdPct, b.maxDdPct); break;
        case 6: r = cmp(a.finalEquity, b.finalEquity); break;
        default: r = 0;
      }
      return _sortAsc ? r : -r;
    });
    return list;
  }

  void _setSort(int c) {
    setState(() {
      if (_sortCol == c) {
        _sortAsc = !_sortAsc;
      } else {
        _sortCol = c;
        _sortAsc = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final rows = _sorted;
    return ListView.builder(
      itemCount: rows.length + 1,
      itemBuilder: (ctx, i) {
        if (i == 0) return _header();
        return _row(rows[i - 1], i, i.isEven);
      },
    );
  }

  Widget _header() {
    Widget col(String label, int idx, {int flex = 1, TextAlign align = TextAlign.left}) {
      final isSort = _sortCol == idx;
      return Expanded(
        flex: flex,
        child: InkWell(
          onTap: idx == 0 ? null : () => _setSort(idx),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: align == TextAlign.right ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      color: isSort ? const Color(0xFFb388ff) : const Color(0xFF787B86),
                      fontSize: 10,
                      letterSpacing: 0.8,
                    )),
                if (isSort)
                  Icon(_sortAsc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      size: 14, color: const Color(0xFFb388ff)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF131722),
      child: Row(
        children: [
          col('#', 0, flex: 1),
          col('PARAMS', 0, flex: 4),
          col('RETURN', 1, flex: 2, align: TextAlign.right),
          col('TRADES', 2, flex: 2, align: TextAlign.right),
          col('WIN%', 3, flex: 2, align: TextAlign.right),
          col('PF', 4, flex: 2, align: TextAlign.right),
          col('DD%', 5, flex: 2, align: TextAlign.right),
          col('EQUITY', 6, flex: 2, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _row(_TrialRow t, int rank, bool alt) {
    final ret = t.returnPct;
    final retColor = !t.success || ret.isNaN
        ? const Color(0xFF787B86)
        : (ret >= 0 ? const Color(0xFF26a69a) : const Color(0xFFef5350));

    String fmt(double v, {bool pct = false}) {
      if (v.isNaN || !v.isFinite) return '—';
      return '${v.toStringAsFixed(2)}${pct ? '%' : ''}';
    }

    Widget cell(String text, {int flex = 1, Color? color, TextAlign align = TextAlign.left, FontWeight? weight}) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(text,
              textAlign: align,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color ?? const Color(0xFFD9D9D9),
                fontSize: 11,
                fontWeight: weight,
              )),
        ),
      );
    }

    final paramsStr = t.params.entries
        .map((e) => '${e.key.replaceAll('_', '')}=${_fmtNum(e.value)}')
        .join(' · ');

    return Container(
      color: alt ? const Color(0xFF1A1D26) : const Color(0xFF1E222D),
      child: Row(
        children: [
          cell('$rank', flex: 1, color: const Color(0xFF787B86)),
          cell(t.success ? paramsStr : '${t.error ?? "error"} · $paramsStr',
              flex: 4, color: t.success ? const Color(0xFFD9D9D9) : const Color(0xFFef5350)),
          cell(fmt(ret, pct: true), flex: 2, align: TextAlign.right, color: retColor, weight: FontWeight.w600),
          cell('${t.trades}', flex: 2, align: TextAlign.right),
          cell(fmt(t.winRatePct, pct: true), flex: 2, align: TextAlign.right, color: const Color(0xFF26a69a)),
          cell(fmt(t.profitFactor), flex: 2, align: TextAlign.right),
          cell(fmt(t.maxDdPct, pct: true), flex: 2, align: TextAlign.right, color: const Color(0xFFef5350)),
          cell('\$${fmt(t.finalEquity)}', flex: 2, align: TextAlign.right),
        ],
      ),
    );
  }

  String _fmtNum(dynamic v) {
    if (v is int) return '$v';
    if (v is double) return v.toStringAsFixed(v.abs() < 1 ? 4 : 2);
    return '$v';
  }
}

// ── Top bar ─────────────────────────────────────────────────────

class _OptTopBar extends StatelessWidget {
  final List<SymbolEntry> symbols;
  final List<BotInfo> bots;
  final String? selectedSymbol;
  final String selectedTimeframe;
  final String? selectedBot;
  final bool running;
  final double progress;
  final int maxWorkers;
  final String mode;
  final int optunaTrials;
  final String objective;
  final ValueChanged<String> onModeChanged;
  final ValueChanged<int> onTrialsChanged;
  final ValueChanged<String> onObjectiveChanged;
  final ValueChanged<int> onWorkersChanged;
  final ValueChanged<String?> onSymbolChanged;
  final ValueChanged<String> onTimeframeChanged;
  final ValueChanged<String?> onBotChanged;
  final VoidCallback onRun;

  const _OptTopBar({
    required this.symbols,
    required this.bots,
    required this.selectedSymbol,
    required this.selectedTimeframe,
    required this.selectedBot,
    required this.running,
    required this.progress,
    required this.maxWorkers,
    required this.mode,
    required this.optunaTrials,
    required this.objective,
    required this.onModeChanged,
    required this.onTrialsChanged,
    required this.onObjectiveChanged,
    required this.onWorkersChanged,
    required this.onSymbolChanged,
    required this.onTimeframeChanged,
    required this.onBotChanged,
    required this.onRun,
  });

  static const _timeframes = ['1m', '5m', '15m', '1h', '4h', '1d'];
  static const _modes = {'grid': 'Grid Sweep', 'tpe': 'Optuna TPE', 'cmaes': 'CMA-ES', 'random': 'Random'};
  static const _objectives = {
    'total_return_pct': 'Return %',
    'win_rate_pct': 'Win Rate %',
    'profit_factor': 'Profit Factor',
    'max_drawdown_pct': 'Min Drawdown',
    'trades': 'Max Trades',
  };

  @override
  Widget build(BuildContext context) {
    final distinctSymbols = symbols.map((s) => s.symbol).toSet().toList()..sort();
    final isOptuna = mode != 'grid';
    final btnLabel = isOptuna
        ? (running ? '${progress.toStringAsFixed(0)}%' : 'Run Optuna')
        : (running ? '${progress.toStringAsFixed(0)}%' : 'Run Sweep');
    return Container(
      color: const Color(0xFF1E222D),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _DropdownChip<String>(
            value: selectedSymbol,
            hint: 'Symbol',
            items: distinctSymbols,
            onChanged: onSymbolChanged,
          ),
          _DropdownChip<String>(
            value: selectedTimeframe,
            hint: 'TF',
            items: _timeframes,
            onChanged: (v) {
              if (v != null) onTimeframeChanged(v);
            },
          ),
          _DropdownChip<String>(
            value: selectedBot,
            hint: 'Bot',
            items: bots.map((b) => b.name).toList(),
            onChanged: onBotChanged,
          ),
          Container(width: 1, height: 24, color: const Color(0xFF2B2B43)),
          // Mode selector
          DropdownButton<String>(
            value: mode,
            isDense: true,
            underline: const SizedBox(),
            style: const TextStyle(color: Color(0xFFb388ff), fontSize: 12, fontWeight: FontWeight.w600),
            dropdownColor: const Color(0xFF1E222D),
            items: _modes.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v != null) onModeChanged(v);
            },
          ),
          if (isOptuna) ...[
            // Trials
            SizedBox(
              width: 60,
              height: 28,
              child: TextFormField(
                initialValue: '$optunaTrials',
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 12),
                decoration: const InputDecoration(
                  labelText: 'Trials',
                  labelStyle: TextStyle(color: Color(0xFF787B86), fontSize: 10),
                  isDense: true,
                  border: InputBorder.none,
                ),
                onChanged: (v) {
                  final n = int.tryParse(v);
                  if (n != null && n > 0) onTrialsChanged(n);
                },
              ),
            ),
            // Objective
            DropdownButton<String>(
              value: objective,
              isDense: true,
              underline: const SizedBox(),
              style: const TextStyle(color: Color(0xFF26a69a), fontSize: 11),
              dropdownColor: const Color(0xFF1E222D),
              items: _objectives.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) {
                if (v != null) onObjectiveChanged(v);
              },
            ),
          ],
          if (!isOptuna) ...[
            const Text('Workers:', style: TextStyle(color: Color(0xFF787B86), fontSize: 11)),
            DropdownButton<int>(
              value: maxWorkers,
              isDense: true,
              underline: const SizedBox(),
              style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 12),
              dropdownColor: const Color(0xFF1E222D),
              items: const [1, 2, 4, 8]
                  .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                  .toList(),
              onChanged: (v) {
                if (v != null) onWorkersChanged(v);
              },
            ),
          ],
          FilledButton.icon(
            onPressed: running || selectedSymbol == null || selectedBot == null ? null : onRun,
            icon: running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(isOptuna ? Icons.auto_awesome : Icons.science, size: 16),
            label: Text(btnLabel),
            style: FilledButton.styleFrom(
              backgroundColor: isOptuna ? const Color(0xFF7C4DFF) : const Color(0xFFb388ff),
              minimumSize: const Size(100, 32),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _DropdownChip<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  const _DropdownChip({required this.value, required this.hint, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
      hint: Text(hint, style: const TextStyle(color: Color(0xFF787B86), fontSize: 13)),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.toString(), style: const TextStyle(fontSize: 13)))).toList(),
      onChanged: onChanged,
      underline: const SizedBox(),
      isDense: true,
      style: const TextStyle(color: Color(0xFFD9D9D9)),
      dropdownColor: const Color(0xFF1E222D),
    );
  }
}
