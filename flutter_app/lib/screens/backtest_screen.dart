import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:backtester_shell/services/api_service.dart';
import 'package:backtester_shell/services/presets_service.dart';
import 'package:backtester_shell/services/ws_service.dart';
import 'package:backtester_shell/screens/optimization_screen.dart'
    show OptimizationResult;
import 'package:backtester_shell/widgets/chart_webview.dart';
import 'package:backtester_shell/widgets/results_panel.dart';
import 'package:backtester_shell/widgets/trades_table.dart';
import 'package:backtester_shell/widgets/mini_weight_chart.dart';
import 'package:backtester_shell/widgets/validation_error_dialog.dart';
import 'package:backtester_shell/services/ui_state_service.dart';

/// Playback transport state for a backtest run.
enum _RunState { idle, running, paused, done }

/// Speed presets: label → speed_ms value.
/// Higher ms = slower playback (delay between candles).
const _speedPresets = <String, int>{
  '0.2x': 500,
  '0.5x': 200,
  '1x': 100,
  '2x': 50,
  '5x': 20,
  '10x': 10,
  'Max': 0,
};

/// Throttled buffer that decouples WebSocket event rate from WebView
/// rendering rate.  All chart events are accumulated and drained at a
/// controlled cadence (~60 fps) so the WebView2 COM bridge never overflows.
class _ChartDispatcher {
  _ChartDispatcher(this._ctrl);

  final ChartWebViewController _ctrl;
  Timer? _timer;

  final List<Map<String, dynamic>> _candles = [];
  final List<Map<String, dynamic>> _trades  = [];
  final List<Map<String, dynamic>> _equity  = [];

  /// Maximum candles to push per tick.  Keeps each JS call < 200 KB.
  static const int _batchSize = 200;
  /// Drain cadence: 16 ms ≈ 60 fps.
  static const Duration _interval = Duration(milliseconds: 16);

  // ── enqueue ──────────────────────────────────────────────────
  void addCandle(Map<String, dynamic> c) => _candles.add(c);
  void addTrade(Map<String, dynamic> t)  => _trades.add(t);
  void addEquity(Map<String, dynamic> e) => _equity.add(e);

  // ── lifecycle ────────────────────────────────────────────────
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _drain());
  }

  void reset() {
    _timer?.cancel();
    _candles.clear();
    _trades.clear();
    _equity.clear();
  }

  /// Flush everything remaining (called on 'result' or 'cancelled').
  void flush() {
    _timer?.cancel();
    // Candles: append remaining without resetting chart.
    if (_candles.isNotEmpty) {
      _ctrl.appendCandles(_candles);
      _candles.clear();
    }
    // Trades & equity: deliver individually (low volume).
    for (final t in _trades) {
      _ctrl.addTradeMarker(t);
    }
    for (final e in _equity) {
      _ctrl.addEquityPoint(e);
    }
    _trades.clear();
    _equity.clear();
  }

  void dispose() {
    _timer?.cancel();
  }

  // ── internal drain tick ─────────────────────────────────────
  void _drain() {
    if (_candles.isEmpty && _trades.isEmpty && _equity.isEmpty) return;

    // Candles: send a batch via appendCandles (one JS call, no reset).
    if (_candles.isNotEmpty) {
      final end = _candles.length.clamp(0, _batchSize);
      final batch = _candles.sublist(0, end);
      _ctrl.appendCandles(batch);
      _candles.removeRange(0, end);
    }

    // Trades: up to 20 per tick.
    final tradeEnd = _trades.length.clamp(0, 20);
    for (var i = 0; i < tradeEnd; i++) {
      _ctrl.addTradeMarker(_trades[i]);
    }
    if (tradeEnd > 0) _trades.removeRange(0, tradeEnd);

    // Equity: up to 50 per tick.
    final eqEnd = _equity.length.clamp(0, 50);
    for (var i = 0; i < eqEnd; i++) {
      _ctrl.addEquityPoint(_equity[i]);
    }
    if (eqEnd > 0) _equity.removeRange(0, eqEnd);
  }
}

/// Main backtest workspace: controls + chart + results.
class BacktestScreen extends StatefulWidget {
  final ApiService apiService;
  final WsService wsService;
  final String chartUrl;
  final double defaultCash;
  final double defaultFeePct;
  final double defaultSlippagePct;
  final OptimizationResult? initialApply;
  final VoidCallback? onApplyConsumed;
  const BacktestScreen({
    super.key,
    required this.apiService,
    required this.wsService,
    required this.chartUrl,
    required this.defaultCash,
    required this.defaultFeePct,
    required this.defaultSlippagePct,
    this.initialApply,
    this.onApplyConsumed,
  });

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  WsService get _ws => widget.wsService;
  final PresetsService _presets = PresetsService();
  final UiStateService _uiStateService = UiStateService();
  final ChartWebViewController _chartCtrl = ChartWebViewController();

  List<SymbolEntry> _symbols = [];
  List<BotInfo> _bots = [];
  final Map<String, BotParamsResponse> _botParamSpecs = {};
  String? _selectedSymbol;
  String _selectedTimeframe = '1h';
  List<String> _selectedBots = [];
  double _initialCash = 10000.0;
  double _takerFeePct = 0.1;
  double _slippagePct = 0.05;
  bool _fillOnNextOpen = true;
  String _selectedFormula = 'ohlc';
  double _brickSize = 10.0;
  String? _startDateIso;
  String? _endDateIso;
  Map<String, Map<String, dynamic>> _botsParams = {};

  List<Map<String, dynamic>> _selectedIndicators = [
    {'name': 'ema', 'period': 9},
    {'name': 'ema', 'period': 21},
  ];

  _RunState _runState = _RunState.idle;
  int _selectedSpeedMs = 100;
  double _progress = 0;
  Map<String, dynamic>? _lastResult;
  Map<String, dynamic>? _perBotResult;
  String? _wsError;
  String? _catalogError;
  String _statusText = 'Idle — select params and click Run';
  final List<TradeRow> _trades = [];
  late final _ChartDispatcher _dispatcher = _ChartDispatcher(_chartCtrl);

  // ── Live HUD state ─────────────────────────────────────────────
  // Cleared on each run. Driven by `equity`, `trade`, and `progress`
  // events so the user can see how the run is going without scrolling
  // to the results panel at the bottom.
  double? _liveEquity;
  double? _peakEquity;
  double _liveDrawdownPct = 0.0;
  double? _lastTradePnl;
  DateTime? _runStartedAt;
  String? _liveEta;

  StreamSubscription<WsEvent>? _wsSub;

  @override
  void initState() {
    super.initState();
    _initialCash = widget.defaultCash;
    _takerFeePct = widget.defaultFeePct;
    _slippagePct = widget.defaultSlippagePct;

    final saved = _uiStateService.load();
    if (saved.isNotEmpty) {
      _selectedSymbol = saved['symbol'] as String?;
      _selectedTimeframe = saved['timeframe'] as String? ?? '1h';
      _selectedFormula = saved['formula'] as String? ?? 'ohlc';
      _selectedBots = (saved['bots'] as List?)?.cast<String>() ?? [];
      _selectedSpeedMs = saved['speed_ms'] as int? ?? 100;
      _startDateIso = saved['start_date'] as String?;
      _endDateIso = saved['end_date'] as String?;
      _brickSize = (saved['brick_size'] as num?)?.toDouble() ?? 10.0;
      
      if (saved['bots_params'] != null) {
        final bp = saved['bots_params'] as Map;
        for (final k in bp.keys) {
          _botsParams[k as String] = Map<String, dynamic>.from(bp[k] as Map);
        }
      }
      if (saved['indicators'] != null) {
        _selectedIndicators = List<Map<String, dynamic>>.from(
          (saved['indicators'] as List).map((e) => Map<String, dynamic>.from(e as Map))
        );
      }
    }

    _loadCatalog();
    _wsSub = _ws.events.listen(_onWsEvent);
    if (widget.initialApply != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _consumeInitialApply(widget.initialApply!),
      );
    }
  }

  @override
  void didUpdateWidget(BacktestScreen old) {
    super.didUpdateWidget(old);
    if (old.defaultCash != widget.defaultCash) {
      _initialCash = widget.defaultCash;
    }
    if (old.defaultFeePct != widget.defaultFeePct) {
      _takerFeePct = widget.defaultFeePct;
    }
    if (old.defaultSlippagePct != widget.defaultSlippagePct) {
      _slippagePct = widget.defaultSlippagePct;
    }
    if (widget.initialApply != null &&
        widget.initialApply != old.initialApply) {
      _consumeInitialApply(widget.initialApply!);
    }
  }

  Future<void> _consumeInitialApply(OptimizationResult r) async {
    // Ensure params spec is loaded so the editor sliders pick up the values.
    await _fetchBotParams(r.botName);
    if (!mounted) return;
    setState(() {
      _selectedSymbol = r.symbol;
      _selectedTimeframe = r.timeframe;
      if (!_selectedBots.contains(r.botName)) {
        _selectedBots = [..._selectedBots, r.botName];
      }
      _botsParams[r.botName] = Map<String, dynamic>.from(r.params);
    });
    await _fetchInitialChartData();
    widget.onApplyConsumed?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFb388ff),
          content: Text(
            'Optimized params loaded for ${r.botName}. Click Run to backtest.',
            style: const TextStyle(color: Colors.black, fontSize: 12),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _loadCatalog() async {
    try {
      final syms = await widget.apiService.listSymbols();
      final bots = await widget.apiService.listBots();
      if (mounted) {
        setState(() {
          _symbols = syms;
          _bots = bots;
          _catalogError = null;
          final symbolNames = syms.map((s) => s.symbol).toSet();
          if (_selectedSymbol != null && !symbolNames.contains(_selectedSymbol)) {
            _selectedSymbol = null;
          }
          if (_symbols.isNotEmpty && _selectedSymbol == null) {
            _selectedSymbol = _symbols.first.symbol;
          }
          final availableBots = bots.map((b) => b.name).toList()..sort();
          _selectedBots =
              _selectedBots.where(availableBots.contains).toList(growable: false);
          if (availableBots.isNotEmpty && _selectedBots.isEmpty) {
            _selectedBots = [availableBots.first];
            _fetchBotParams(availableBots.first);
          }
        });
        await _fetchInitialChartData();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _catalogError =
              'Cannot load symbols/bots. Check backend URL and token in Settings.';
        });
      }
      debugPrint('BacktestScreen _loadCatalog error: $e');
    }
  }

  Future<void> _fetchBotParams(String botName) async {
    if (_botParamSpecs.containsKey(botName)) return;
    try {
      final spec = await widget.apiService.getBotParams(botName);
      if (mounted) {
        setState(() {
          _botParamSpecs[botName] = spec;
          if (!_botsParams.containsKey(botName)) {
            _botsParams[botName] = {
              for (final e in spec.params.entries) e.key: e.value.defaultValue,
            };
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchInitialChartData() async {
    if (_selectedSymbol == null ||
        _runState == _RunState.running ||
        !_chartCtrl.isReady) {
      return;
    }
    // Always clear first so the user sees the chart switch immediately — and
    // stale data from the previous symbol/timeframe is never left on screen.
    _chartCtrl.clear();
    _chartCtrl.setChartFormula(_selectedFormula, brickSize: _brickSize);
    try {
      final candles = await widget.apiService.getCandles(
        symbol: _selectedSymbol!,
        timeframe: _selectedTimeframe,
        startMs: _parseDateToMs(_startDateIso),
        endMs: _parseDateToMs(_endDateIso, endOfDay: true),
        limit: 1500,
      );
      if (!mounted) return;
      // setCandles with [] makes the chart show its "no candles in range"
      // empty state instead of stale data.
      _chartCtrl.setCandles(candles);
      if (candles.isEmpty) {
        setState(() =>
            _statusText = 'No data for $_selectedSymbol ($_selectedTimeframe) in selected range.');
      } else {
        setState(() => _statusText =
            'Loaded ${candles.length} candles — ready to run backtest.');
      }
    } catch (e) {
      debugPrint('Error fetching initial chart data: $e');
      if (mounted) {
        setState(() => _statusText =
            'Failed to load $_selectedSymbol ($_selectedTimeframe): ${e.toString().split(":").first}. Try downloading the range.');
      }
    }
  }

  @override
  void dispose() {
    _dispatcher.dispose();
    _wsSub?.cancel();
    super.dispose();
  }

  void _onWsEvent(WsEvent ev) {
    switch (ev.type) {
      case WsEventType.start:
        _dispatcher.reset();
        _dispatcher.start();
        final overlayKeys = List<String>.from(ev.data['indicators_keys'] ?? []);
        final oscKeys = List<String>.from(ev.data['oscillator_keys'] ?? []);
        final botIds = List<String>.from(ev.data['bot_ids'] ?? []);
        _chartCtrl.initIndicators(overlayKeys);
        _chartCtrl.initOscillators(oscKeys);
        _chartCtrl.initBotSeries(['total', ...botIds]);
        if (mounted) setState(() => _statusText = 'Streaming candles…');
      case WsEventType.candle:
        _dispatcher.addCandle(ev.data);
      case WsEventType.trade:
        _dispatcher.addTrade(ev.data);
        final pnl = (ev.data['pnl'] as num?)?.toDouble();
        if (mounted) {
          setState(() {
            _trades.add(TradeRow.fromWs(ev.data));
            if (pnl != null) _lastTradePnl = pnl;
          });
        }
      case WsEventType.equity:
        _dispatcher.addEquity(ev.data);
        // Drive the live HUD off the aggregate equity series only — per-bot
        // ticks would jitter the drawdown reading on multi-bot runs.
        final botId = ev.data['bot_id'] as String? ?? 'total';
        if (botId == 'total') {
          final v = (ev.data['value'] as num?)?.toDouble();
          if (v != null && mounted) {
            setState(() {
              _liveEquity = v;
              if (_peakEquity == null || v > _peakEquity!) _peakEquity = v;
              _liveDrawdownPct = _peakEquity == null || _peakEquity == 0
                  ? 0.0
                  : ((_peakEquity! - v) / _peakEquity!) * 100.0;
            });
          }
        }
      case WsEventType.progress:
        if (mounted) {
          final pct = (ev.data['percent'] as num).toDouble();
          String? eta;
          if (_runStartedAt != null && pct > 0.5) {
            final elapsed = DateTime.now().difference(_runStartedAt!).inMilliseconds;
            final total = elapsed / (pct / 100.0);
            final remaining = ((total - elapsed) / 1000.0).round();
            eta = _formatEta(remaining);
          }
          setState(() {
            _progress = pct;
            _liveEta = eta;
            _statusText = 'Running backtest… ${pct.toStringAsFixed(0)}%';
          });
        }
      case WsEventType.result:
        if (mounted) setState(() => _statusText = 'Rendering chart…');
        _dispatcher.flush();
        if (mounted) {
          setState(() {
            _runState = _RunState.done;
            _lastResult = ev.data;
            _perBotResult = ev.data['per_bot'] as Map<String, dynamic>?;
            _progress = 100;
            _statusText = '✓ Backtest complete — ${_trades.length} trades';
          });
        }
      case WsEventType.error:
        if (mounted) {
          final msg = ev.data['message'] as String? ?? 'Unknown error';
          setState(() {
            _runState = _RunState.idle;
            _wsError = msg;
          });
          _maybeOfferDataManager(msg);
        }
      case WsEventType.paused:
        if (mounted) {
          setState(() {
            _runState = _RunState.paused;
            _statusText = '⏸ Paused — press resume to continue';
          });
        }
      case WsEventType.resumed:
        if (mounted) {
          setState(() {
            _runState = _RunState.running;
            _statusText = 'Resumed — streaming candles…';
          });
        }
      case WsEventType.cancelled:
        if (mounted) {
          // Treat cancellation as terminal for the current run and return to
          // idle immediately so a new run can only start from a clean state.
          setState(() => _runState = _RunState.idle);
        }
      case WsEventType.speedChanged:
        final ms = ev.data['speed_ms'];
        if (mounted && ms is int) setState(() => _selectedSpeedMs = ms);
      case WsEventType.reconnecting:
        final attempt = ev.data['attempt'];
        final max = ev.data['max'];
        if (mounted) setState(() => _wsError = 'Reconnecting ($attempt/$max)…');
      case WsEventType.reconnected:
        if (mounted) setState(() => _wsError = null);
      case WsEventType.disconnected:
        if (mounted) {
          setState(() {
            if (_runState == _RunState.running ||
                _runState == _RunState.paused) {
              _runState = _RunState.idle;
            }
            _wsError = ev.data['message'] as String? ?? 'Connection lost';
          });
        }
      default:
        break;
    }
  }

  void _maybeOfferDataManager(String message) {
    final lower = message.toLowerCase();
    if (!lower.contains('no candles') && !lower.contains('download first')) {
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFef5350),
        duration: const Duration(seconds: 8),
        content: Text(
          'No data for ${_selectedSymbol ?? "this symbol"} ($_selectedTimeframe). Download first.',
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
        action: SnackBarAction(
          label: 'Open Data Manager',
          textColor: Colors.white,
          onPressed: () => _showDownloadDialog(context),
        ),
      ),
    );
  }

  void _runBacktest() {
    if (_selectedSymbol == null || _selectedBots.isEmpty) return;
    if (_runState == _RunState.running || _runState == _RunState.paused) return;
    if (!_ws.isConnected) {
      setState(() => _wsError = 'Not connected to backend.');
      return;
    }
    setState(() {
      _runState = _RunState.running;
      _progress = 0;
      _lastResult = null;
      _perBotResult = null;
      _wsError = null;
      _trades.clear();
      _statusText = 'Connecting to engine…';
      // Reset live HUD so the previous run's numbers don't bleed into
      // the new one. peakEquity seeds at the configured starting cash
      // so drawdown reads correctly from the very first equity tick.
      _liveEquity = _initialCash;
      _peakEquity = _initialCash;
      _liveDrawdownPct = 0.0;
      _lastTradePnl = null;
      _runStartedAt = DateTime.now();
      _liveEta = null;
    });
    _dispatcher.reset();
    _chartCtrl.clear();
    _chartCtrl.setChartFormula(_selectedFormula, brickSize: _brickSize);

    final bots = _selectedBots
        .map((b) => {'name': b, 'params': _botsParams[b] ?? {}})
        .toList();

    _ws.runBacktest(
      bots: bots,
      symbol: _selectedSymbol!,
      timeframe: _selectedTimeframe,
      startMs: _parseDateToMs(_startDateIso),
      endMs: _parseDateToMs(_endDateIso, endOfDay: true),
      initialCash: _initialCash,
      takerFeePct: _takerFeePct,
      slippagePct: _slippagePct,
      fillOnNextOpen: _fillOnNextOpen,
      indicators: _selectedIndicators,
      speedMs: _selectedSpeedMs,
      formula: _selectedFormula,
    );
  }

  int? _parseDateToMs(String? isoDate, {bool endOfDay = false}) {
    if (isoDate == null || isoDate.trim().isEmpty) return null;
    final normalizedStr = isoDate.trim().replaceAll(' ', '-').replaceAll('/', '-');
    final dt = DateTime.tryParse(normalizedStr);
    if (dt == null) return null;
    final normalized = endOfDay
        ? DateTime(dt.year, dt.month, dt.day, 23, 59, 59, 999)
        : DateTime(dt.year, dt.month, dt.day);
    return normalized.millisecondsSinceEpoch;
  }

  Future<void> _validateData() async {
    if (_selectedSymbol == null) return;
    try {
      final report = await widget.apiService.validateData(
        symbol: _selectedSymbol!,
        timeframe: _selectedTimeframe,
        startMs: _parseDateToMs(_startDateIso),
        endMs: _parseDateToMs(_endDateIso, endOfDay: true),
      );
      if (!mounted) return;
      final summaryOk = report['summary_ok'] as bool? ?? false;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Data quality — ${_selectedSymbol!} $_selectedTimeframe'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Status: ${summaryOk ? "OK" : "Issues found"}'),
                Text('Candles: ${report["total_candles"]}'),
                Text(
                  'Completeness: ${(report["completeness_pct"] ?? 0).toString()}%',
                ),
                Text('Gaps: ${((report["gaps"] as List?) ?? const []).length}'),
                Text(
                  'Duplicates: ${((report["duplicates"] as List?) ?? const []).length}',
                ),
                Text(
                  'OHLC violations: ${((report["ohlc_consistency_violations"] as List?) ?? const []).length}',
                ),
                Text(
                  'Outliers: ${((report["outliers_iqr"] as List?) ?? const []).length}',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Data validation failed: $e')));
    }
  }

  // ── Exports ────────────────────────────────────────────────────

  Future<void> _exportHtmlReport() async {
    final runId = _lastResult?['run_id'] as String?;
    if (runId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No run_id on the current result; rerun the backtest.'),
        ),
      );
      return;
    }
    try {
      final html = await widget.apiService.downloadReportHtml(runId);
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF26a69a),
          content: Text(
            'HTML report saved → ${outFile.path} (path copied)',
            style: const TextStyle(color: Colors.black, fontSize: 12),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export HTML report: $e')),
      );
    }
  }

  Future<void> _exportBundle() async {
    if (_lastResult == null) return;
    final dir = Directory('${Directory.current.path}/exports');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final subDir = Directory('${dir.path}/run_$ts');
    subDir.createSync();

    // trades.csv
    final tradesCsv = StringBuffer()
      ..writeln(
        'bot_id,entry_time,exit_time,entry_price,exit_price,qty,pnl,pnl_pct,fee_usdt,reason',
      );
    for (final t in _trades) {
      final eT = DateTime.fromMillisecondsSinceEpoch(
        t.entryTime * 1000,
        isUtc: true,
      );
      final xT = DateTime.fromMillisecondsSinceEpoch(
        t.exitTime * 1000,
        isUtc: true,
      );
      tradesCsv.writeln(
        [
          t.botId,
          eT.toIso8601String(),
          xT.toIso8601String(),
          t.entryPrice.toStringAsFixed(6),
          t.exitPrice.toStringAsFixed(6),
          t.qty.toStringAsFixed(8),
          t.pnl.toStringAsFixed(4),
          t.pnlPct.toStringAsFixed(4),
          t.feeUsdt.toStringAsFixed(4),
          t.reason,
        ].join(','),
      );
    }
    await File('${subDir.path}/trades.csv').writeAsString(tradesCsv.toString());

    // summary.json (global + per-bot + config)
    final config = {
      'symbol': _selectedSymbol,
      'timeframe': _selectedTimeframe,
      'initial_cash': _initialCash,
      'taker_fee_pct': _takerFeePct,
      'slippage_pct': _slippagePct,
      'fill_on_next_open': _fillOnNextOpen,
      if (_startDateIso != null) 'start_date': _startDateIso,
      if (_endDateIso != null) 'end_date': _endDateIso,
      'bots': _selectedBots
          .map((b) => {'name': b, 'params': _botsParams[b] ?? {}})
          .toList(),
      'indicators': _selectedIndicators,
    };
    final summary = {
      'config': config,
      'global': _lastResult,
      'per_bot': _perBotResult,
      'trades_count': _trades.length,
      'exported_at': DateTime.now().toIso8601String(),
    };
    await File(
      '${subDir.path}/summary.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(summary));

    await Clipboard.setData(ClipboardData(text: subDir.path));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF26a69a),
          content: Text(
            'Bundle saved → ${subDir.path} (path copied)',
            style: const TextStyle(color: Colors.black, fontSize: 12),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // ── Presets ────────────────────────────────────────────────────

  Future<void> _savePresetDialog() async {
    if (_selectedSymbol == null || _selectedBots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select symbol and bots before saving a preset'),
        ),
      );
      return;
    }
    final ctrl = TextEditingController(
      text:
          '${_selectedSymbol}_${_selectedTimeframe}_${_selectedBots.join("-")}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Save preset'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Preset name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final preset = BacktestPreset(
      name: name,
      symbol: _selectedSymbol!,
      timeframe: _selectedTimeframe,
      initialCash: _initialCash,
      botNames: List<String>.from(_selectedBots),
      botsParams: {
        for (final b in _selectedBots)
          b: Map<String, dynamic>.from(_botsParams[b] ?? {}),
      },
      indicators: List<Map<String, dynamic>>.from(_selectedIndicators),
      createdAt: DateTime.now().toIso8601String(),
    );
    await _presets.save(preset);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF26a69a),
          content: Text(
            'Preset "$name" saved',
            style: const TextStyle(color: Colors.black, fontSize: 12),
          ),
        ),
      );
    }
  }

  Future<void> _loadPresetDialog() async {
    final presets = await _presets.list();
    if (!mounted) return;
    final selected = await showDialog<BacktestPreset>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text('Load preset'),
        content: SizedBox(
          width: 380,
          height: 320,
          child: presets.isEmpty
              ? Center(
                  child: Text(
                    'No presets saved yet.\nFolder: ${_presets.dirPath}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF787B86),
                      fontSize: 12,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: presets.length,
                  itemBuilder: (c, i) {
                    final p = presets[i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        p.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                      subtitle: Text(
                        '${p.symbol} • ${p.timeframe} • ${p.botNames.join(", ")}',
                        style: const TextStyle(
                          color: Color(0xFF787B86),
                          fontSize: 11,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, p),
                      trailing: IconButton(
                        iconSize: 16,
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Color(0xFFef5350),
                        ),
                        onPressed: () async {
                          await _presets.delete(p.name);
                          if (ctx.mounted) Navigator.pop(ctx, null);
                          _loadPresetDialog();
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (selected != null) _applyPreset(selected);
  }

  void _applyPreset(BacktestPreset p) {
    _updateState(() {
      _selectedSymbol = p.symbol;
      _selectedTimeframe = p.timeframe;
      _initialCash = p.initialCash;
      _selectedBots = List<String>.from(p.botNames);
      _botsParams = {
        for (final e in p.botsParams.entries)
          e.key: Map<String, dynamic>.from(e.value),
      };
      _selectedIndicators = List<Map<String, dynamic>>.from(p.indicators);
    });
    for (final b in _selectedBots) {
      _fetchBotParams(b);
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF26a69a),
        content: Text(
          'Loaded preset "${p.name}"',
          style: const TextStyle(color: Colors.black, fontSize: 12),
        ),
      ),
    );
  }

  // dispose is handled near initState

  void _saveUiState() {
    _uiStateService.save({
      'symbol': _selectedSymbol,
      'timeframe': _selectedTimeframe,
      'formula': _selectedFormula,
      'bots': _selectedBots,
      'speed_ms': _selectedSpeedMs,
      'start_date': _startDateIso,
      'end_date': _endDateIso,
      'brick_size': _brickSize,
      'bots_params': _botsParams,
      'indicators': _selectedIndicators,
    });
  }

  void _updateState(VoidCallback fn) {
    setState(fn);
    _saveUiState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TopBar(
          symbols: _symbols,
          bots: _bots,
          selectedSymbol: _selectedSymbol,
          selectedTimeframe: _selectedTimeframe,
          selectedFormula: _selectedFormula,
          selectedBots: _selectedBots,
          initialCash: _initialCash,
          takerFeePct: _takerFeePct,
          slippagePct: _slippagePct,
          fillOnNextOpen: _fillOnNextOpen,
          startDateIso: _startDateIso,
          endDateIso: _endDateIso,
          selectedIndicators: _selectedIndicators,
          runState: _runState,
          progress: _progress,
          selectedSpeedMs: _selectedSpeedMs,
          wsError: _wsError,
          wsStatus: _ws.status,
          onSymbolChanged: (v) {
            _updateState(() => _selectedSymbol = v);
            _fetchInitialChartData();
          },
          onTimeframeChanged: (v) {
            _updateState(() => _selectedTimeframe = v);
            _fetchInitialChartData();
          },
          onFormulaChanged: (v) {
            _updateState(() => _selectedFormula = v);
            _chartCtrl.setChartFormula(v, brickSize: _brickSize);
          },
          brickSize: _brickSize,
          onBrickSizeChanged: (v) {
            _updateState(() => _brickSize = v);
            if (_selectedFormula == 'renko') {
              _chartCtrl.setChartFormula(
                _selectedFormula,
                brickSize: _brickSize,
              );
            }
          },
          onBotsChanged: (v) {
            _updateState(() => _selectedBots = v);
            for (final b in v) {
              _fetchBotParams(b);
            }
          },
          onCashChanged: (v) => _updateState(() => _initialCash = v),
          onFeeChanged: (v) => _updateState(() => _takerFeePct = v),
          onSlippageChanged: (v) => _updateState(() => _slippagePct = v),
          onFillOnNextOpenChanged: (v) => _updateState(() => _fillOnNextOpen = v),
          onStartDateChanged: (v) {
            _updateState(() => _startDateIso = v);
            _fetchInitialChartData();
          },
          onEndDateChanged: (v) {
            _updateState(() => _endDateIso = v);
            _fetchInitialChartData();
          },
          onIndicatorsChanged: (v) => _updateState(() => _selectedIndicators = v),
          botParamSpecs: _botParamSpecs,
          botsParamValues: _botsParams,
          onBotParamChanged: (botName, params) =>
              _updateState(() => _botsParams[botName] = params),
          onRun: _runBacktest,
          onPauseResume: () {
            if (_runState == _RunState.running) {
              _ws.pause();
            } else if (_runState == _RunState.paused) {
              _ws.resume();
            }
          },
          onStep: _ws.step,
          onStop: _ws.cancelRun,
          onSpeedChanged: (ms) {
            _updateState(() => _selectedSpeedMs = ms);
            if (_runState == _RunState.running ||
                _runState == _RunState.paused) {
              _ws.setSpeed(ms);
            }
          },
          onDownload: () => _showDownloadDialog(context),
          onSavePreset: _savePresetDialog,
          onApplyPreset: _applyPreset,
          onManagePresets: _loadPresetDialog,
          onReconnect: _ws.connect,
          onValidateData: _validateData,
        ),
        if (_symbols.isEmpty)
          Container(
            color: const Color(0xFF26a69a).withValues(alpha: 0.10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(
                  Icons.download_outlined,
                  size: 18,
                  color: Color(0xFF26a69a),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'No data downloaded yet. Open the Data Manager to fetch historical candles before running a backtest.',
                    style: TextStyle(color: Color(0xFFD9D9D9), fontSize: 12),
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _showDownloadDialog(context),
                  icon: const Icon(Icons.cloud_download_outlined, size: 14),
                  label: const Text('Open Data Manager'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF26a69a),
                    minimumSize: const Size(0, 30),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        if (_catalogError != null)
          Container(
            color: const Color(0xFFef5350).withValues(alpha: 0.10),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: Color(0xFFef5350),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _catalogError!,
                    style: const TextStyle(
                      color: Color(0xFFef5350),
                      fontSize: 12,
                    ),
                  ),
                ),
                TextButton(onPressed: _loadCatalog, child: const Text('Retry')),
              ],
            ),
          ),
        // Chart pane — Expanded so it absorbs all remaining vertical space.
        // (We rely on the chart's own ResizeObserver to handle dimension changes.)
        Expanded(
          child: Stack(
            children: [
              ChartWebView(
                controller: _chartCtrl,
                chartUrl: widget.chartUrl,
                onReady: _fetchInitialChartData,
              ),
              // Live HUD: shows equity / DD / last trade PnL / ETA while the
              // run is in flight (and stays visible briefly while the result
              // panel finishes painting so the user can see the final values).
              if (_runState == _RunState.running ||
                  _runState == _RunState.paused ||
                  _runState == _RunState.done)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _LiveHud(
                    initialCash: _initialCash,
                    equity: _liveEquity,
                    drawdownPct: _liveDrawdownPct,
                    lastTradePnl: _lastTradePnl,
                    progressPct: _progress,
                    eta: _liveEta,
                    isPaused: _runState == _RunState.paused,
                    isDone: _runState == _RunState.done,
                  ),
                ),
              // Status bar overlay
              if (_runState != _RunState.idle || !_chartCtrl.isReady)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                    child: Text(
                      _statusText,
                      style: const TextStyle(
                        color: Color(0xFFD9D9D9),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (_lastResult != null || _trades.isNotEmpty)
          SizedBox(
            height: 260,
            child: ResultsPanel(
              data: _lastResult ?? {},
              perBot: _perBotResult,
              trades: _trades,
              onExportAll: _lastResult != null ? _exportBundle : null,
              onExportHtml:
                  (_lastResult != null && _lastResult!['run_id'] != null)
                  ? _exportHtmlReport
                  : null,
              onSavePreset: _selectedSymbol != null && _selectedBots.isNotEmpty
                  ? _savePresetDialog
                  : null,
            ),
          ),
      ],
    );
  }

  void _showDownloadDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => _DownloadDialog(
        apiService: widget.apiService,
        onCatalogSelect: (symbol, tf) {
          setState(() {
            _selectedSymbol = symbol;
            _selectedTimeframe = tf;
          });
        },
      ),
    ).then((_) {
      // After dialog closes, refresh catalog (downloads may have completed).
      _loadCatalog();
    });
  }

  /// Compact human ETA: "12s", "3m 04s", "1h 12m".
  static String _formatEta(int seconds) {
    if (seconds <= 0) return '0s';
    if (seconds < 60) return '${seconds}s';
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m < 60) return '${m}m ${s.toString().padLeft(2, '0')}s';
    final h = m ~/ 60;
    final mm = m % 60;
    return '${h}h ${mm.toString().padLeft(2, '0')}m';
  }
}

// ── Live HUD overlay ───────────────────────────────────────────

/// Compact panel pinned to the top-left of the chart while a run is
/// running, paused, or just-finished. Driven by:
///
///  * `equity` events (`bot_id == 'total'`) → live equity + drawdown %
///  * `trade` events → last realised PnL
///  * `progress` events → ETA + percent
///
/// The widget is purely presentational — all numbers come in as
/// constructor params so it stays cheap to rebuild every WS tick.
class _LiveHud extends StatelessWidget {
  final double initialCash;
  final double? equity;
  final double drawdownPct;
  final double? lastTradePnl;
  final double progressPct;
  final String? eta;
  final bool isPaused;
  final bool isDone;

  const _LiveHud({
    required this.initialCash,
    required this.equity,
    required this.drawdownPct,
    required this.lastTradePnl,
    required this.progressPct,
    required this.eta,
    required this.isPaused,
    required this.isDone,
  });

  @override
  Widget build(BuildContext context) {
    final eq = equity ?? initialCash;
    final retPct = ((eq - initialCash) / initialCash) * 100.0;
    final retColor = retPct >= 0 ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
    final ddColor  = drawdownPct > 0.01 ? const Color(0xFFEF5350) : const Color(0xFF6E7079);
    final pnlColor = (lastTradePnl ?? 0) >= 0
        ? const Color(0xFF26A69A)
        : const Color(0xFFEF5350);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xCC131722),
          border: Border.all(color: const Color(0xFF2A2E39), width: 1),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: DefaultTextStyle.merge(
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFFD1D4DC),
            fontFamily: 'monospace',
            height: 1.35,
          ),
          child: IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: isDone
                            ? const Color(0xFF26A69A)
                            : (isPaused
                                ? const Color(0xFFFFB300)
                                : const Color(0xFF2962FF)),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isDone ? 'DONE' : (isPaused ? 'PAUSED' : 'LIVE'),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                        color: Color(0xFFB2B5BE),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${progressPct.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF787B86),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _row('Equity', '\$${_fmt(eq)}',
                    valueStyle: TextStyle(color: retColor, fontWeight: FontWeight.w600)),
                _row('Return', '${retPct >= 0 ? '+' : ''}${retPct.toStringAsFixed(2)}%',
                    valueStyle: TextStyle(color: retColor)),
                _row('Drawdown', '${drawdownPct.toStringAsFixed(2)}%',
                    valueStyle: TextStyle(color: ddColor)),
                if (lastTradePnl != null)
                  _row('Last PnL',
                      '${lastTradePnl! >= 0 ? '+' : ''}\$${_fmt(lastTradePnl!)}',
                      valueStyle: TextStyle(color: pnlColor)),
                if (eta != null && !isDone)
                  _row('ETA', eta!,
                      valueStyle: const TextStyle(color: Color(0xFFB2B5BE))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {TextStyle? valueStyle}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style: const TextStyle(color: Color(0xFF787B86), fontSize: 10)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                style: valueStyle ??
                    const TextStyle(color: Color(0xFFD1D4DC), fontSize: 11)),
          ),
        ],
      ),
    );
  }

  static String _fmt(double v) {
    final av = v.abs();
    if (av >= 1_000_000) return '${(v / 1_000_000).toStringAsFixed(2)}M';
    if (av >= 10_000) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}

// ── Top control bar ────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final List<SymbolEntry> symbols;
  final List<BotInfo> bots;
  final String? selectedSymbol;
  final String selectedTimeframe;
  final String selectedFormula;
  final List<String> selectedBots;
  final double initialCash;
  final double takerFeePct;
  final double slippagePct;
  final bool fillOnNextOpen;
  final String? startDateIso;
  final String? endDateIso;
  final List<Map<String, dynamic>> selectedIndicators;
  final _RunState runState;
  final double progress;
  final int selectedSpeedMs;
  final String? wsError;
  final ValueNotifier<WsStatus> wsStatus;
  final ValueChanged<String?> onSymbolChanged;
  final ValueChanged<String> onTimeframeChanged;
  final ValueChanged<String> onFormulaChanged;
  final double brickSize;
  final ValueChanged<double> onBrickSizeChanged;
  final ValueChanged<List<String>> onBotsChanged;
  final ValueChanged<double> onCashChanged;
  final ValueChanged<double> onFeeChanged;
  final ValueChanged<double> onSlippageChanged;
  final ValueChanged<bool> onFillOnNextOpenChanged;
  final ValueChanged<String?> onStartDateChanged;
  final ValueChanged<String?> onEndDateChanged;
  final ValueChanged<List<Map<String, dynamic>>> onIndicatorsChanged;
  final Map<String, BotParamsResponse> botParamSpecs;
  final Map<String, Map<String, dynamic>> botsParamValues;
  final void Function(String botName, Map<String, dynamic> params)
  onBotParamChanged;
  final VoidCallback onRun;
  final VoidCallback onPauseResume;
  final VoidCallback onStep;
  final VoidCallback onStop;
  final ValueChanged<int> onSpeedChanged;
  final VoidCallback onDownload;
  final VoidCallback onSavePreset;
  final void Function(BacktestPreset) onApplyPreset;
  final VoidCallback onManagePresets;
  final VoidCallback onReconnect;
  final VoidCallback onValidateData;

  const _TopBar({
    required this.symbols,
    required this.bots,
    required this.selectedSymbol,
    required this.selectedTimeframe,
    required this.selectedFormula,
    required this.selectedBots,
    required this.initialCash,
    required this.takerFeePct,
    required this.slippagePct,
    required this.fillOnNextOpen,
    required this.startDateIso,
    required this.endDateIso,
    required this.selectedIndicators,
    required this.runState,
    required this.progress,
    required this.selectedSpeedMs,
    this.wsError,
    required this.wsStatus,
    required this.onSymbolChanged,
    required this.onTimeframeChanged,
    required this.onFormulaChanged,
    required this.brickSize,
    required this.onBrickSizeChanged,
    required this.onBotsChanged,
    required this.onCashChanged,
    required this.onFeeChanged,
    required this.onSlippageChanged,
    required this.onFillOnNextOpenChanged,
    required this.onStartDateChanged,
    required this.onEndDateChanged,
    required this.onIndicatorsChanged,
    required this.botParamSpecs,
    required this.botsParamValues,
    required this.onBotParamChanged,
    required this.onRun,
    required this.onPauseResume,
    required this.onStep,
    required this.onStop,
    required this.onSpeedChanged,
    required this.onDownload,
    required this.onSavePreset,
    required this.onApplyPreset,
    required this.onManagePresets,
    required this.onReconnect,
    required this.onValidateData,
  });

  static const _timeframes = ['1m', '5m', '15m', '1h', '4h', '1d'];

  @override
  Widget build(BuildContext context) {
    final distinctSymbols = symbols.map((s) => s.symbol).toSet().toList()
      ..sort();
    return Container(
      height: 48,
      color: const Color(0xFF1E222D),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _DropdownChip<String>(
              value: distinctSymbols.isEmpty ? null : selectedSymbol,
              hint: 'Symbol',
              items: distinctSymbols,
              onChanged: distinctSymbols.isEmpty ? null : onSymbolChanged,
            ),
            const SizedBox(width: 8),
            _DropdownChip<String>(
              value: selectedTimeframe,
              hint: 'TF',
              items: _timeframes,
              onChanged: (v) {
                if (v != null) onTimeframeChanged(v);
              },
            ),
            const SizedBox(width: 8),
            _DropdownChip<String>(
              value: selectedFormula,
              hint: 'Chart',
              items: const ['ohlc', 'heikin_ashi', 'renko'],
              onChanged: (v) {
                if (v != null) onFormulaChanged(v);
              },
            ),
            if (selectedFormula == 'renko') ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: TextFormField(
                  initialValue: brickSize.toString(),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    hintText: 'Size',
                    filled: true,
                    fillColor: Color(0xFF2B2B43),
                    border: OutlineInputBorder(borderSide: BorderSide.none),
                  ),
                  onChanged: (v) {
                    final val = double.tryParse(v);
                    if (val != null && val > 0) onBrickSizeChanged(val);
                  },
                ),
              ),
            ],
            const SizedBox(width: 8),
            SizedBox(
              width: 96,
              child: TextFormField(
                initialValue: startDateIso ?? '',
                decoration: const InputDecoration(
                  labelText: 'Start',
                  hintText: 'YYYY-MM-DD',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
                style: const TextStyle(fontSize: 11, color: Color(0xFFD9D9D9)),
                onChanged: (v) =>
                    onStartDateChanged(v.trim().isEmpty ? null : v.trim()),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 96,
              child: TextFormField(
                initialValue: endDateIso ?? '',
                decoration: const InputDecoration(
                  labelText: 'End',
                  hintText: 'YYYY-MM-DD',
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
                style: const TextStyle(fontSize: 11, color: Color(0xFFD9D9D9)),
                onChanged: (v) =>
                    onEndDateChanged(v.trim().isEmpty ? null : v.trim()),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => _showBotsDialog(context),
              icon: const Icon(Icons.smart_toy, size: 14),
              label: Text('Bots (${selectedBots.length})'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD9D9D9),
              ),
            ),
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: () => _showIndicatorDialog(context),
              icon: const Icon(Icons.show_chart, size: 14),
              label: Text('Ind (${selectedIndicators.length})'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD9D9D9),
              ),
            ),
            const SizedBox(width: 4),
            // ── Presets ─────────────────────────────────────────────
            _PresetsToolbar(
              onSavePreset: onSavePreset,
              onApplyPreset: onApplyPreset,
              onManagePresets: onManagePresets,
            ),
            const SizedBox(width: 8),
            _TransportCluster(
              runState: runState,
              progress: progress,
              selectedSpeedMs: selectedSpeedMs,
              canRun: selectedSymbol != null && selectedBots.isNotEmpty,
              onRun: onRun,
              onPauseResume: onPauseResume,
              onStep: onStep,
              onStop: onStop,
              onSpeedChanged: onSpeedChanged,
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: onDownload,
              icon: const Icon(Icons.download, size: 14),
              label: const Text('Data'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF787B86),
                side: const BorderSide(color: Color(0xFF2B2B43)),
                minimumSize: const Size(72, 32),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              key: const ValueKey('validate-data-btn'),
              onPressed: selectedSymbol == null ? null : onValidateData,
              icon: const Icon(Icons.verified_outlined, size: 14),
              label: const Text('Validar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF787B86),
                side: const BorderSide(color: Color(0xFF2B2B43)),
                minimumSize: const Size(82, 32),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            // ── Connection status indicator ─────────────────────────
            _ConnStatus(status: wsStatus, error: wsError, onRetry: onReconnect),
          ],
        ),
      ),
    );
  }

  void _showBotsDialog(BuildContext context) {
    final selectedLocal = List<String>.from(selectedBots);
    final paramsLocal = <String, Map<String, dynamic>>{
      for (final e in botsParamValues.entries)
        e.key: Map<String, dynamic>.from(e.value),
    };
    final cashCtrl = TextEditingController(text: initialCash.toString());
    final feeCtrl = TextEditingController(text: takerFeePct.toString());
    final slippageCtrl = TextEditingController(text: slippagePct.toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Bots & Wallet'),
          backgroundColor: const Color(0xFF1E222D),
          content: StatefulBuilder(
            builder: (context, setStateDialog) {
              return SizedBox(
                width: 560,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 620),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: cashCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Initial Cash / Wallet',
                        ),
                        onChanged: (v) {
                          final val = double.tryParse(v);
                          if (val != null) onCashChanged(val);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Text(
                            'Bots selected: ${selectedLocal.length}/${bots.length}',
                            style: const TextStyle(
                              color: Color(0xFF787B86),
                              fontSize: 11,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () {
                              selectedLocal
                                ..clear()
                                ..addAll(bots.map((b) => b.name));
                              onBotsChanged(List<String>.from(selectedLocal));
                              setStateDialog(() {});
                            },
                            child: const Text('Select all'),
                          ),
                          TextButton(
                            onPressed: () {
                              selectedLocal.clear();
                              onBotsChanged(const []);
                              setStateDialog(() {});
                            },
                            child: const Text('Clear'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.separated(
                          itemCount: bots.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final b = bots[i];
                            final isSelected = selectedLocal.contains(b.name);
                            final spec = botParamSpecs[b.name];
                            final vals =
                                paramsLocal[b.name] ??
                                botsParamValues[b.name] ??
                                {};
                            return Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF151823),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF26a69a)
                                      : const Color(0xFF2B2B43),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CheckboxListTile(
                                    dense: true,
                                    value: isSelected,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(b.name),
                                    subtitle: b.description != null
                                        ? Text(
                                            b.description!,
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF787B86),
                                            ),
                                          )
                                        : null,
                                    onChanged: (checked) {
                                      if (checked == true) {
                                        if (!selectedLocal.contains(b.name)) {
                                          selectedLocal.add(b.name);
                                        }
                                      } else {
                                        selectedLocal.remove(b.name);
                                      }
                                      onBotsChanged(List<String>.from(selectedLocal));
                                      setStateDialog(() {});
                                    },
                                  ),
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 160),
                                    child: isSelected
                                        ? Padding(
                                            key: ValueKey('params-${b.name}'),
                                            padding: const EdgeInsets.fromLTRB(
                                              8,
                                              0,
                                              8,
                                              8,
                                            ),
                                            child: spec == null
                                                ? const Text(
                                                    'Loading params…',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Color(0xFF787B86),
                                                    ),
                                                  )
                                                : spec.params.isEmpty
                                                ? const Text(
                                                    'This bot has no tunable params.',
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      color: Color(0xFF787B86),
                                                    ),
                                                  )
                                                : _BotParamEditor(
                                                    botName: b.name,
                                                    spec: spec,
                                                    values: vals,
                                                    onChanged: (newVals) {
                                                      paramsLocal[b.name] =
                                                          Map<String, dynamic>.from(
                                                            newVals,
                                                          );
                                                      onBotParamChanged(
                                                        b.name,
                                                        newVals,
                                                      );
                                                      setStateDialog(() {});
                                                    },
                                                  ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: feeCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Taker Fee %',
                              ),
                              onChanged: (v) {
                                final n = double.tryParse(v);
                                if (n != null) onFeeChanged(n);
                              },
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextFormField(
                              controller: slippageCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Slippage %',
                              ),
                              onChanged: (v) {
                                final n = double.tryParse(v);
                                if (n != null) onSlippageChanged(n);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Realistic fill (next open)'),
                        subtitle: const Text(
                          'MARKET orders execute on next candle open.',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF787B86),
                          ),
                        ),
                        value: fillOnNextOpen,
                        onChanged: onFillOnNextOpenChanged,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      cashCtrl.dispose();
      feeCtrl.dispose();
      slippageCtrl.dispose();
    });
  }

  static const _indicatorPresets = [
    {
      'label': 'EMA 9',
      'spec': {'name': 'ema', 'period': 9},
    },
    {
      'label': 'EMA 21',
      'spec': {'name': 'ema', 'period': 21},
    },
    {
      'label': 'EMA 50',
      'spec': {'name': 'ema', 'period': 50},
    },
    {
      'label': 'SMA 20',
      'spec': {'name': 'sma', 'period': 20},
    },
    {
      'label': 'SMA 200',
      'spec': {'name': 'sma', 'period': 200},
    },
    {
      'label': 'RSI 14',
      'spec': {'name': 'rsi', 'period': 14},
    },
    {
      'label': 'MACD (12/26/9)',
      'spec': {'name': 'macd', 'fast': 12, 'slow': 26, 'signal': 9},
    },
    {
      'label': 'BB 20',
      'spec': {'name': 'bb', 'period': 20},
    },
    {
      'label': 'Stoch 14',
      'spec': {'name': 'stoch', 'k_period': 14, 'd_period': 3},
    },
    {
      'label': 'VWAP',
      'spec': {'name': 'vwap'},
    },
  ];

  void _showIndicatorDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          bool isActive(Map<String, dynamic> spec) =>
              selectedIndicators.any((s) => s.toString() == spec.toString());

          void toggle(Map<String, dynamic> spec) {
            final current = List<Map<String, dynamic>>.from(selectedIndicators);
            if (isActive(spec)) {
              current.removeWhere((s) => s.toString() == spec.toString());
            } else {
              current.add(Map<String, dynamic>.from(spec));
            }
            onIndicatorsChanged(current);
            setDialogState(() {});
          }

          return AlertDialog(
            title: const Text('Indicators'),
            backgroundColor: const Color(0xFF1E222D),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'OVERLAY (main chart)',
                    style: TextStyle(
                      color: Color(0xFF787B86),
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _indicatorPresets
                        .where(
                          (p) => ![
                            'rsi',
                            'macd',
                            'stoch',
                          ].contains((p['spec'] as Map)['name']),
                        )
                        .map((p) {
                          final spec = Map<String, dynamic>.from(
                            p['spec'] as Map,
                          );
                          final active = isActive(spec);
                          return FilterChip(
                            label: Text(
                              p['label'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: active
                                    ? Colors.black
                                    : const Color(0xFFD9D9D9),
                              ),
                            ),
                            selected: active,
                            onSelected: (_) => toggle(spec),
                            selectedColor: const Color(0xFF26a69a),
                            backgroundColor: const Color(0xFF2B2B43),
                            checkmarkColor: Colors.black,
                            side: BorderSide.none,
                          );
                        })
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'OSCILLATORS (sub-panel)',
                    style: TextStyle(
                      color: Color(0xFF787B86),
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _indicatorPresets
                        .where(
                          (p) => [
                            'rsi',
                            'macd',
                            'stoch',
                          ].contains((p['spec'] as Map)['name']),
                        )
                        .map((p) {
                          final spec = Map<String, dynamic>.from(
                            p['spec'] as Map,
                          );
                          final active = isActive(spec);
                          return FilterChip(
                            label: Text(
                              p['label'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: active
                                    ? Colors.black
                                    : const Color(0xFFD9D9D9),
                              ),
                            ),
                            selected: active,
                            onSelected: (_) => toggle(spec),
                            selectedColor: const Color(0xFFFFD700),
                            backgroundColor: const Color(0xFF2B2B43),
                            checkmarkColor: Colors.black,
                            side: BorderSide.none,
                          );
                        })
                        .toList(),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  onIndicatorsChanged([]);
                  setDialogState(() {});
                },
                child: const Text(
                  'Clear all',
                  style: TextStyle(color: Color(0xFF787B86)),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ConnStatus extends StatelessWidget {
  final ValueNotifier<WsStatus> status;
  final String? error;
  final VoidCallback onRetry;
  const _ConnStatus({
    required this.status,
    required this.error,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<WsStatus>(
      valueListenable: status,
      builder: (ctx, s, _) {
        final (color, label) = switch (s) {
          WsStatus.connected => (const Color(0xFF26a69a), 'Connected'),
          WsStatus.connecting => (const Color(0xFFFFD740), 'Connecting…'),
          WsStatus.reconnecting => (const Color(0xFFFF9800), 'Reconnecting…'),
          WsStatus.disconnected => (const Color(0xFFef5350), 'Offline'),
        };
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error != null) ...[
              Container(
                constraints: const BoxConstraints(maxWidth: 240),
                child: Text(
                  '⚠ $error',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFef5350),
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontSize: 11)),
            if (s == WsStatus.disconnected) ...[
              const SizedBox(width: 4),
              IconButton(
                iconSize: 14,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                tooltip: 'Retry connection',
                icon: const Icon(Icons.refresh, color: Color(0xFFD9D9D9)),
                onPressed: onRetry,
              ),
            ],
          ],
        );
      },
    );
  }
}

class _DropdownChip<T> extends StatelessWidget {
  final T? value;
  final String hint;
  final List<T> items;
  final ValueChanged<T?>? onChanged;

  const _DropdownChip({
    required this.value,
    required this.hint,
    required this.items,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Flutter asserts when value is set but missing from items (e.g. saved
    // symbol before catalog load or empty DB).
    final effectiveValue =
        value != null && items.contains(value) ? value : null;
    return DropdownButton<T>(
      value: effectiveValue,
      hint: Text(
        hint,
        style: const TextStyle(color: Color(0xFF787B86), fontSize: 13),
      ),
      items: items
          .map(
            (e) => DropdownMenuItem(
              value: e,
              child: Text(e.toString(), style: const TextStyle(fontSize: 13)),
            ),
          )
          .toList(),
      onChanged: onChanged,
      underline: const SizedBox(),
      isDense: true,
      style: const TextStyle(color: Color(0xFFD9D9D9)),
      dropdownColor: const Color(0xFF1E222D),
    );
  }
}

// ── Bot param editor ─────────────────────────────────────────────

class _BotParamEditor extends StatefulWidget {
  final String botName;
  final BotParamsResponse spec;
  final Map<String, dynamic> values;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const _BotParamEditor({
    required this.botName,
    required this.spec,
    required this.values,
    required this.onChanged,
  });

  @override
  State<_BotParamEditor> createState() => _BotParamEditorState();
}

class _BotParamEditorState extends State<_BotParamEditor> {
  late Map<String, dynamic> _vals;
  final Map<String, TextEditingController> _controllers = {};

  @override
  void initState() {
    super.initState();
    _vals = {
      for (final e in widget.spec.params.entries)
        e.key: widget.values[e.key] ?? e.value.defaultValue,
    };
    for (final e in widget.spec.params.entries) {
      final key = e.key;
      _controllers[key] = TextEditingController(
        text: (_vals[key] ?? e.value.defaultValue).toString(),
      );
    }
  }

  @override
  void didUpdateWidget(_BotParamEditor old) {
    super.didUpdateWidget(old);
    if (old.values != widget.values) {
      _vals = {
        for (final e in widget.spec.params.entries)
          e.key: widget.values[e.key] ?? e.value.defaultValue,
      };
      for (final e in widget.spec.params.entries) {
        final key = e.key;
        final nextText = (_vals[key] ?? e.value.defaultValue).toString();
        final ctrl = _controllers.putIfAbsent(
          key,
          () => TextEditingController(text: nextText),
        );
        if (ctrl.text != nextText) {
          ctrl.text = nextText;
        }
      }
    }
  }

  void _update(String key, dynamic val) {
    setState(() => _vals[key] = val);
    widget.onChanged(Map<String, dynamic>.from(_vals));
  }

  dynamic _parseBySpec(ParamSpec p, String raw) {
    final txt = raw.trim();
    if (txt.isEmpty) return null;
    if (p.type == 'int') return int.tryParse(txt);
    if (p.type == 'float') return double.tryParse(txt);
    return txt;
  }

  String _boundsHint(ParamSpec p) {
    final parts = <String>[];
    if (p.min != null) parts.add('min ${p.min}');
    if (p.max != null) parts.add('max ${p.max}');
    if (p.step != null) parts.add('step ${p.step}');
    return parts.join(' · ');
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: widget.spec.params.entries.map((e) {
        final key = e.key;
        final p = e.value;
        final isInt = p.type == 'int';
        final ctrl = _controllers.putIfAbsent(
          key,
          () => TextEditingController(
            text: (_vals[key] ?? p.defaultValue).toString(),
          ),
        );

        return SizedBox(
          width: 190,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                key.replaceAll('_', ' '),
                style: const TextStyle(color: Color(0xFF787B86), fontSize: 10),
              ),
              TextFormField(
                controller: ctrl,
                keyboardType: p.type == 'str'
                    ? TextInputType.text
                    : TextInputType.numberWithOptions(
                        decimal: !isInt,
                        signed: true,
                      ),
                style: const TextStyle(
                  color: Color(0xFFD9D9D9),
                  fontSize: 12,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  hintText: p.defaultValue?.toString(),
                  helperText: _boundsHint(p).isEmpty ? null : _boundsHint(p),
                  helperStyle: const TextStyle(
                    color: Color(0xFF787B86),
                    fontSize: 10,
                  ),
                ),
                onChanged: (v) {
                  final parsed = _parseBySpec(p, v);
                  if (parsed != null) _update(key, parsed);
                },
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Presets toolbar ───────────────────────────────────────────

/// Inline dropdown + save button for presets.
/// Manages its own preset list so _TopBar stays stateless.
class _PresetsToolbar extends StatefulWidget {
  final VoidCallback onSavePreset;
  final void Function(BacktestPreset) onApplyPreset;

  /// Optional callback to open the full preset manager dialog (with delete).
  final VoidCallback? onManagePresets;
  const _PresetsToolbar({
    required this.onSavePreset,
    required this.onApplyPreset,
    this.onManagePresets,
  });

  @override
  State<_PresetsToolbar> createState() => _PresetsToolbarState();
}

class _PresetsToolbarState extends State<_PresetsToolbar> {
  final _svc = PresetsService();
  List<BacktestPreset> _presets = [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await _svc.list();
    if (mounted) setState(() => _presets = list);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButton<BacktestPreset>(
          hint: const Text(
            'Preset',
            style: TextStyle(color: Color(0xFF787B86), fontSize: 12),
          ),
          value: null,
          items: _presets
              .map(
                (p) => DropdownMenuItem(
                  value: p,
                  child: Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFD9D9D9),
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (p) {
            if (p != null) widget.onApplyPreset(p);
          },
          onTap: _reload,
          underline: const SizedBox(),
          isDense: true,
          style: const TextStyle(color: Color(0xFFD9D9D9)),
          dropdownColor: const Color(0xFF1E222D),
          iconEnabledColor: const Color(0xFF787B86),
          iconSize: 16,
        ),
        Tooltip(
          message: 'Save current as preset',
          child: IconButton(
            iconSize: 14,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            icon: const Icon(
              Icons.bookmark_add_outlined,
              color: Color(0xFF787B86),
            ),
            onPressed: () {
              widget.onSavePreset();
              // Reload after a brief delay to catch the newly saved preset.
              Future.delayed(const Duration(milliseconds: 500), _reload);
            },
          ),
        ),
        if (widget.onManagePresets != null)
          Tooltip(
            message: 'Manage presets',
            child: IconButton(
              iconSize: 14,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              icon: const Icon(
                Icons.bookmarks_outlined,
                color: Color(0xFF787B86),
              ),
              onPressed: () async {
                widget.onManagePresets!();
                Future.delayed(const Duration(milliseconds: 500), _reload);
              },
            ),
          ),
      ],
    );
  }
}

// ── Transport cluster ──────────────────────────────────────────

/// Run / Pause-Resume / Step / Speed / Stop bar that lives in the TopBar.
class _TransportCluster extends StatelessWidget {
  final _RunState runState;
  final double progress;
  final int selectedSpeedMs;
  final bool canRun;
  final VoidCallback onRun;
  final VoidCallback onPauseResume;
  final VoidCallback onStep;
  final VoidCallback onStop;
  final ValueChanged<int> onSpeedChanged;

  const _TransportCluster({
    required this.runState,
    required this.progress,
    required this.selectedSpeedMs,
    required this.canRun,
    required this.onRun,
    required this.onPauseResume,
    required this.onStep,
    required this.onStop,
    required this.onSpeedChanged,
  });

  bool get _isActive =>
      runState == _RunState.running || runState == _RunState.paused;

  String get _speedLabel => _speedPresets.entries
      .firstWhere(
        (e) => e.value == selectedSpeedMs,
        orElse: () => MapEntry('${selectedSpeedMs}ms', selectedSpeedMs),
      )
      .key;

  @override
  Widget build(BuildContext context) {
    final isMax = selectedSpeedMs == 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Run button ──────────────────────────────────────────
        FilledButton.icon(
          onPressed: (_isActive || !canRun) ? null : onRun,
          icon: (runState == _RunState.running)
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.play_arrow, size: 16),
          label: Text(
            runState == _RunState.running
                ? '${progress.toStringAsFixed(0)}%'
                : 'Run',
          ),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF26a69a),
            minimumSize: const Size(72, 32),
            textStyle: const TextStyle(fontSize: 13),
          ),
        ),
        const SizedBox(width: 4),
        // ── Pause / Resume toggle ───────────────────────────────
        Tooltip(
          message: runState == _RunState.paused ? 'Resume' : 'Pause',
          child: IconButton(
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            icon: Icon(
              runState == _RunState.paused
                  ? Icons.play_circle_outline
                  : Icons.pause_circle_outline,
              color: _isActive
                  ? const Color(0xFFFFD740)
                  : const Color(0xFF2B2B43),
            ),
            onPressed: _isActive ? onPauseResume : null,
          ),
        ),
        // ── PAUSED badge ────────────────────────────────────────
        if (runState == _RunState.paused) ...[
          const SizedBox(width: 2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD740).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFFD740), width: 1),
            ),
            child: const Text(
              'PAUSED',
              style: TextStyle(
                color: Color(0xFFFFD740),
                fontSize: 9,
                letterSpacing: 0.8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 2),
        ],
        // ── Step button ─────────────────────────────────────────
        Tooltip(
          message: 'Step one candle',
          child: IconButton(
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            icon: Icon(
              Icons.skip_next,
              color: runState == _RunState.paused
                  ? const Color(0xFFD9D9D9)
                  : const Color(0xFF2B2B43),
            ),
            onPressed: runState == _RunState.paused ? onStep : null,
          ),
        ),
        const SizedBox(width: 2),
        // ── Speed dropdown ──────────────────────────────────────
        Tooltip(
          message: 'Playback speed (ms/candle)',
          child: DropdownButton<int>(
            value: selectedSpeedMs,
            items: _speedPresets.entries
                .map(
                  (e) => DropdownMenuItem<int>(
                    value: e.value,
                    child: Text(
                      e.key,
                      style: TextStyle(
                        fontSize: 12,
                        color: e.value == 0
                            ? const Color(0xFF787B86)
                            : const Color(0xFFD9D9D9),
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) onSpeedChanged(v);
            },
            hint: Text(
              _speedLabel,
              style: TextStyle(
                fontSize: 12,
                color: isMax
                    ? const Color(0xFF787B86)
                    : const Color(0xFFD9D9D9),
              ),
            ),
            underline: const SizedBox(),
            isDense: true,
            style: TextStyle(
              color: isMax ? const Color(0xFF787B86) : const Color(0xFFD9D9D9),
              fontSize: 12,
            ),
            dropdownColor: const Color(0xFF1E222D),
            iconEnabledColor: const Color(0xFF787B86),
            iconSize: 14,
          ),
        ),
        const SizedBox(width: 2),
        // ── Stop button ─────────────────────────────────────────
        Tooltip(
          message: 'Stop run',
          child: IconButton(
            iconSize: 18,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            icon: Icon(
              Icons.stop_circle_outlined,
              color: _isActive
                  ? const Color(0xFFef5350)
                  : const Color(0xFF2B2B43),
            ),
            onPressed: _isActive ? onStop : null,
          ),
        ),
      ],
    );
  }
}

// ── Download dialog ────────────────────────────────────────────

class _DownloadDialog extends StatefulWidget {
  final ApiService apiService;
  final Function(String, String) onCatalogSelect;
  const _DownloadDialog({
    required this.apiService,
    required this.onCatalogSelect,
  });

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  final _symbolCtrl = TextEditingController(text: 'BTCUSDT');
  String _tf = '1h';
  final _fromCtrl = TextEditingController(text: '${DateTime.now().year}-01-01');
  final _toCtrl = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
  final _yearCtrl = TextEditingController(text: '2025');
  final _monthCtrl = TextEditingController(text: 'all');

  bool _useZip = true;
  bool _loading = false;
  String? _msg;
  double _downloadProgress = 0.0;
  Timer? _pollTimer;
  Map<String, dynamic>? _qualityReport;
  Timer? _healthTimer;

  List<SymbolEntry> _catalog = [];
  int _apiWeight = 0;

  static const _timeframes = ['1m', '5m', '15m', '1h', '4h', '1d'];

  @override
  void initState() {
    super.initState();
    _refreshCatalog();
    _healthTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollWeight(),
    );
  }

  Future<void> _refreshCatalog() async {
    try {
      final syms = await widget.apiService.listSymbols();
      if (mounted) setState(() => _catalog = syms);
    } catch (_) {}
  }

  Future<void> _pollWeight() async {
    try {
      final h = await widget.apiService.checkHealth();
      if (mounted) setState(() => _apiWeight = h.binanceWeight1m);
    } catch (_) {}
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _healthTimer?.cancel();
    super.dispose();
  }

  /// Run data quality validation after a successful download.
  Future<void> _runValidation(String symbol, String timeframe) async {
    try {
      final report = await widget.apiService.validateData(
        symbol: symbol,
        timeframe: timeframe,
      );
      if (mounted) setState(() => _qualityReport = report);
    } catch (e) {
      debugPrint('Data validation error: $e');
    }
  }

  void _download() async {
    setState(() {
      _loading = true;
      _msg = 'Initializing download...';
      _downloadProgress = 0.0;
      _qualityReport = null;
    });
    try {
      if (_useZip) {
        final monthStr = _monthCtrl.text.trim().toLowerCase();
        List<int> months = [];
        if (monthStr == 'all' || monthStr == '1-12') {
          months = List.generate(12, (i) => i + 1);
        } else if (monthStr.contains('-')) {
          final parts = monthStr.split('-');
          int start = int.parse(parts[0].trim());
          int end = int.parse(parts[1].trim());
          months = List.generate(end - start + 1, (i) => start + i);
        } else if (monthStr.contains(',')) {
          months = monthStr.split(',').map((e) => int.parse(e.trim())).toList();
        } else {
          months = [int.parse(monthStr)];
        }

        final year = int.parse(_yearCtrl.text.trim());
        final symbol = _symbolCtrl.text.trim().toUpperCase();

        setState(() {
          _msg = 'Spawning ${months.length} parallel downloads...';
        });

        final jobIds = <String>[];
        for (int m in months) {
          final result = await widget.apiService.downloadCandlesZip(
            symbol: symbol,
            timeframe: _tf,
            year: year,
            month: m,
          );
          jobIds.add(result['id'] as String);
        }

        int completed = 0;
        int totalCandles = 0;
        final Set<String> doneJobs = {};

        _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
          try {
            double totalProgress = 0;
            bool hasError = false;
            String? lastErr;

            for (final id in jobIds) {
              if (doneJobs.contains(id)) {
                totalProgress += 1.0;
                continue;
              }
              final status = await widget.apiService.getJob(id);
              if (status.status == 'done') {
                doneJobs.add(id);
                completed++;
                totalProgress += 1.0;
                totalCandles +=
                    (status.result?['candles_added'] as num?)?.toInt() ?? 0;
              } else if (status.status == 'error') {
                hasError = true;
                lastErr = status.message;
                doneJobs.add(id);
                completed++;
              } else {
                totalProgress += status.progress;
              }
            }

            if (mounted) {
              setState(() {
                _downloadProgress = totalProgress / jobIds.length;
                _msg = 'Downloading... $completed/${jobIds.length} done';
              });
            }

            if (completed == jobIds.length) {
              timer.cancel();
              if (mounted) {
                setState(() {
                  _loading = false;
                  if (hasError) {
                    _msg = '⚠ Finished with some errors. Last: $lastErr';
                  } else {
                    _msg = '✓ Done: $totalCandles candles added.';
                  }
                  _refreshCatalog();
                });
                if (!hasError) {
                  _runValidation(symbol, _tf);
                }
              }
            }
          } catch (e) {
            // Ignore polling errors
          }
        });
      } else {
        final result = await widget.apiService.downloadCandles(
          symbol: _symbolCtrl.text.trim().toUpperCase(),
          timeframe: _tf,
          dateFrom: _fromCtrl.text.trim(),
          dateTo: _toCtrl.text.trim(),
        );
        final jobId = result['id'] as String;

        _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
          try {
            final status = await widget.apiService.getJob(jobId);
            if (mounted) {
              setState(() {
                _downloadProgress = status.progress;
                _msg = status.message ?? 'Downloading...';
              });
              if (status.status == 'done' || status.status == 'error') {
                timer.cancel();
                setState(() {
                  _loading = false;
                  if (status.status == 'done') {
                    _msg =
                        '✓ Done: ${status.result?['candles_added'] ?? 0} candles';
                    _refreshCatalog();
                  } else {
                    _msg = '✗ Error: ${status.message}';
                  }
                });
                if (status.status == 'done') {
                  _runValidation(
                    _symbolCtrl.text.trim().toUpperCase(),
                    _tf,
                  );
                }
              }
            }
          } catch (e) {
            // Ignored, we just poll again
          }
        });
      }
    } on ApiValidationError catch (e) {
      setState(() {
        _loading = false;
      });
      if (mounted) await ValidationErrorDialog.show(context, e);
    } catch (e) {
      setState(() {
        _loading = false;
        _msg = '✗ $e';
      });
    }
  }

  Widget _buildQualityBadge(Map<String, dynamic> report) {
    final isOk = report['summary_ok'] == true;
    final gaps = (report['gaps'] as List?)?.length ?? 0;
    final dupes = (report['duplicates'] as List?)?.length ?? 0;
    final outliers = (report['outliers_iqr'] as List?)?.length ?? 0;
    final ohlcViolations =
        (report['ohlc_consistency_violations'] as List?)?.length ?? 0;
    final completeness =
        (report['completeness_pct'] as num?)?.toStringAsFixed(1) ?? '?';
    final total = report['total_candles'] ?? 0;

    final badgeColor = isOk ? const Color(0xFF26a69a) : const Color(0xFFFFA726);
    final iconData = isOk ? Icons.check_circle : Icons.warning_amber_rounded;

    final chips = <Widget>[];
    if (!isOk) {
      if (gaps > 0) {
        chips.add(_qChip('$gaps gaps', const Color(0xFFFFA726)));
      }
      if (dupes > 0) {
        chips.add(_qChip('$dupes dupes', const Color(0xFFef5350)));
      }
      if (outliers > 0) {
        chips.add(_qChip('$outliers outliers', const Color(0xFFFFD54F)));
      }
      if (ohlcViolations > 0) {
        chips.add(_qChip('$ohlcViolations OHLC', const Color(0xFFef5350)));
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(iconData, color: badgeColor, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  isOk ? 'Data Quality: Clean' : 'Data Quality: Warnings',
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '$total · $completeness%',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    color: Color(0xFF787B86),
                    fontSize: 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: chips),
          ],
        ],
      ),
    );
  }

  Widget _qChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E222D),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('Data Manager'),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'API Weight (1m)',
                style: TextStyle(fontSize: 10, color: Color(0xFF787B86)),
              ),
              const SizedBox(height: 4),
              MiniWeightChart(
                currentWeight: _apiWeight,
                height: 72,
                width: 220,
                timeWindow: const Duration(minutes: 5),
              ),
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 400,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 1,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Download History',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _symbolCtrl,
                      decoration: const InputDecoration(labelText: 'Symbol'),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _tf,
                      items: _timeframes
                          .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _tf = v);
                      },
                      decoration: const InputDecoration(labelText: 'Timeframe'),
                    ),
                    const SizedBox(height: 12),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: true, label: Text('Bulk ZIP')),
                        ButtonSegment(value: false, label: Text('REST API')),
                      ],
                      selected: {_useZip},
                      onSelectionChanged: (Set<bool> newSelection) {
                        setState(() => _useZip = newSelection.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    if (!_useZip)
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _fromCtrl,
                              decoration: const InputDecoration(
                                labelText: 'From (YYYY-MM-DD)',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _toCtrl,
                              decoration: const InputDecoration(
                                labelText: 'To (YYYY-MM-DD)',
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _yearCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Year (YYYY)',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _monthCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Month (e.g. 1, 1-12, all)',
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _download,
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Start Download'),
                    ),
                  if (_loading && _downloadProgress > 0) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: _downloadProgress,
                      backgroundColor: const Color(0xFF2B2B43),
                      color: const Color(0xFF26a69a),
                    ),
                  ],
                  if (_msg != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _msg!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _msg!.startsWith('✓')
                            ? const Color(0xFF26a69a)
                            : (_msg!.startsWith('✗')
                                  ? const Color(0xFFef5350)
                                  : const Color(0xFFD9D9D9)),
                      ),
                    ),
                  ],
                  if (_qualityReport != null) ...[
                    const SizedBox(height: 8),
                    _buildQualityBadge(_qualityReport!),
                  ],
                ],
                ),
              ),
            ),
            const VerticalDivider(width: 24),
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Local Histograms (DuckDB)',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF131722),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: _catalog.length,
                        itemBuilder: (context, index) {
                          final c = _catalog[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              '${c.symbol} • ${c.timeframe}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              '${c.candles} candles',
                              style: const TextStyle(
                                color: Color(0xFF787B86),
                                fontSize: 11,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.play_circle_outline,
                                color: Color(0xFF26a69a),
                              ),
                              tooltip: 'Load in Main Chart',
                              onPressed: () {
                                widget.onCatalogSelect(c.symbol, c.timeframe);
                                Navigator.pop(context);
                              },
                            ),
                            onTap: () {
                              widget.onCatalogSelect(c.symbol, c.timeframe);
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close Manager'),
        ),
      ],
    );
  }
}
