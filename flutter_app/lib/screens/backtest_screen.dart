import 'dart:async';
import 'package:flutter/material.dart';
import 'package:backtester_shell/services/api_service.dart';
import 'package:backtester_shell/services/ws_service.dart';
import 'package:backtester_shell/widgets/chart_webview.dart';
import 'package:backtester_shell/widgets/results_panel.dart';
import 'package:backtester_shell/widgets/mini_weight_chart.dart';

/// Main backtest workspace: controls + chart + results.
class BacktestScreen extends StatefulWidget {
  final ApiService apiService;
  const BacktestScreen({super.key, required this.apiService});

  @override
  State<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends State<BacktestScreen> {
  final WsService _ws = WsService();
  final ChartWebViewController _chartCtrl = ChartWebViewController();

  List<SymbolEntry> _symbols = [];
  List<BotInfo> _bots = [];
  String? _selectedSymbol;
  String _selectedTimeframe = '1h';
  String? _selectedBot;
  Map<String, dynamic> _botParams = {};

  bool _running = false;
  double _progress = 0;
  Map<String, dynamic>? _lastResult;
  String? _wsError;

  StreamSubscription<WsEvent>? _wsSub;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
    _connectWs();
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

  Future<void> _connectWs() async {
    try {
      await _ws.connect();
      _wsSub = _ws.events.listen(
        _onWsEvent,
        onError: (e) {
          if (mounted) setState(() => _wsError = e.toString());
        },
      );
    } catch (e) {
      if (mounted) setState(() => _wsError = e.toString());
    }
  }

  void _onWsEvent(WsEvent ev) {
    switch (ev.type) {
      case WsEventType.candle:
        _chartCtrl.addCandle(ev.data);
      case WsEventType.trade:
        _chartCtrl.addTradeMarker(ev.data);
      case WsEventType.equity:
        _chartCtrl.addEquityPoint(ev.data);
      case WsEventType.progress:
        if (mounted) {
          setState(() => _progress = (ev.data['percent'] as num).toDouble());
        }
      case WsEventType.result:
        if (mounted) {
          setState(() {
            _running = false;
            _lastResult = ev.data;
            _progress = 100;
          });
        }
      case WsEventType.error:
        if (mounted) {
          setState(() {
            _running = false;
            _wsError = ev.data['message'] as String?;
          });
        }
      default:
        break;
    }
  }

  void _runBacktest() {
    if (_selectedSymbol == null || _selectedBot == null || _running) return;
    setState(() {
      _running = true;
      _progress = 0;
      _lastResult = null;
      _wsError = null;
    });
    _chartCtrl.clear();
    _ws.runBacktest(
      bot: _selectedBot!,
      symbol: _selectedSymbol!,
      timeframe: _selectedTimeframe,
      params: _botParams,
    );
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _ws.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Top bar ─────────────────────────────────────────────
        _TopBar(
          symbols: _symbols,
          bots: _bots,
          selectedSymbol: _selectedSymbol,
          selectedTimeframe: _selectedTimeframe,
          selectedBot: _selectedBot,
          running: _running,
          progress: _progress,
          wsError: _wsError,
          onSymbolChanged: (v) => setState(() => _selectedSymbol = v),
          onTimeframeChanged: (v) => setState(() => _selectedTimeframe = v),
          onBotChanged: (v) => setState(() {
            _selectedBot = v;
            _botParams = {};
          }),
          onRun: _runBacktest,
          onDownload: () => _showDownloadDialog(context),
        ),
        // ── Chart (main area) ────────────────────────────────────
        Expanded(flex: 3, child: ChartWebView(controller: _chartCtrl)),
        const Divider(height: 1),
        // ── Results panel ────────────────────────────────────────
        if (_lastResult != null)
          SizedBox(height: 150, child: ResultsPanel(data: _lastResult!)),
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
    );
  }
}

// ── Top control bar ────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final List<SymbolEntry> symbols;
  final List<BotInfo> bots;
  final String? selectedSymbol;
  final String selectedTimeframe;
  final String? selectedBot;
  final bool running;
  final double progress;
  final String? wsError;
  final ValueChanged<String?> onSymbolChanged;
  final ValueChanged<String> onTimeframeChanged;
  final ValueChanged<String?> onBotChanged;
  final VoidCallback onRun;
  final VoidCallback onDownload;

  const _TopBar({
    required this.symbols,
    required this.bots,
    required this.selectedSymbol,
    required this.selectedTimeframe,
    required this.selectedBot,
    required this.running,
    required this.progress,
    this.wsError,
    required this.onSymbolChanged,
    required this.onTimeframeChanged,
    required this.onBotChanged,
    required this.onRun,
    required this.onDownload,
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
      child: Row(
        children: [
          // Symbol
          _DropdownChip<String>(
            value: selectedSymbol,
            hint: 'Symbol',
            items: distinctSymbols,
            onChanged: onSymbolChanged,
          ),
          const SizedBox(width: 8),
          // Timeframe
          _DropdownChip<String>(
            value: selectedTimeframe,
            hint: 'TF',
            items: _timeframes,
            onChanged: (v) {
              if (v != null) onTimeframeChanged(v);
            },
          ),
          const SizedBox(width: 8),
          // Bot
          _DropdownChip<String>(
            value: selectedBot,
            hint: 'Bot',
            items: bots.map((b) => b.name).toList(),
            onChanged: onBotChanged,
          ),
          const SizedBox(width: 12),
          // Run
          FilledButton.icon(
            onPressed: running || selectedSymbol == null || selectedBot == null
                ? null
                : onRun,
            icon: running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.play_arrow, size: 16),
            label: Text(running ? '${progress.toStringAsFixed(0)}%' : 'Run'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF26a69a),
              minimumSize: const Size(80, 32),
              textStyle: const TextStyle(fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          // Download
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
          const Spacer(),
          if (wsError != null)
            Text(
              '⚠ $wsError',
              style: const TextStyle(color: Color(0xFFef5350), fontSize: 11),
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

  const _DropdownChip({
    required this.value,
    required this.hint,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButton<T>(
      value: value,
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

// ── Download dialog ────────────────────────────────────────────

class _DownloadDialog extends StatefulWidget {
  final ApiService apiService;
  final Function(String, String) onCatalogSelect;
  const _DownloadDialog({required this.apiService, required this.onCatalogSelect});

  @override
  State<_DownloadDialog> createState() => _DownloadDialogState();
}

class _DownloadDialogState extends State<_DownloadDialog> {
  final _symbolCtrl = TextEditingController(text: 'BTCUSDT');
  String _tf = '1h';
  final _fromCtrl = TextEditingController(text: '2024-01-01');
  final _toCtrl = TextEditingController(text: '2024-12-31');
  final _yearCtrl = TextEditingController(text: '2024');
  final _monthCtrl = TextEditingController(text: '1');
  
  bool _useZip = true;
  bool _loading = false;
  String? _msg;
  double _downloadProgress = 0.0;
  Timer? _pollTimer;
  Timer? _healthTimer;
  
  List<SymbolEntry> _catalog = [];
  int _apiWeight = 0;

  static const _timeframes = ['1m', '5m', '15m', '1h', '4h', '1d'];

  @override
  void initState() {
    super.initState();
    _refreshCatalog();
    _healthTimer = Timer.periodic(const Duration(seconds: 5), (_) => _pollWeight());
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

  void _download() async {
    setState(() {
      _loading = true; // Still keep loading to show progress bar, but we can allow triggering again
      _msg = 'Initializing download...';
      _downloadProgress = 0.0;
    });
    try {
      if (_useZip) {
        // Parse month range
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

        // Start all downloads in parallel
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

        // Poll all jobs until done
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
                totalCandles += (status.result?['candles_added'] as num?)?.toInt() ?? 0;
              } else if (status.status == 'error') {
                hasError = true;
                lastErr = status.message;
                doneJobs.add(id); // Treat as done to stop polling it
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
              }
            }
          } catch (e) {
            // Ignore temporary network errors during polling
          }
        });

      } else {
        // REST API mode (single job)
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
                    _msg = '✓ Done: ${status.result?['candles_added'] ?? 0} candles';
                    _refreshCatalog();
                  } else {
                    _msg = '✗ Error: ${status.message}';
                  }
                });
              }
            }
          } catch (e) {}
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _msg = '✗ $e';
      });
    }
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
              const Text('API Weight (1m)', style: TextStyle(fontSize: 10, color: Color(0xFF787B86))),
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
            // Left Side: Download Form
            Expanded(
              flex: 1,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Download History', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                            decoration: const InputDecoration(labelText: 'From (YYYY-MM-DD)'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _toCtrl,
                            decoration: const InputDecoration(labelText: 'To (YYYY-MM-DD)'),
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
                            decoration: const InputDecoration(labelText: 'Year (YYYY)'),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _monthCtrl,
                            decoration: const InputDecoration(labelText: 'Month (e.g. 1, 1-12, all)'),
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
                            : (_msg!.startsWith('✗') ? const Color(0xFFef5350) : const Color(0xFFD9D9D9)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const VerticalDivider(width: 24),
            // Right Side: Catalog
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Local Histograms (DuckDB)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                            title: Text('${c.symbol} • ${c.timeframe}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                            subtitle: Text('${c.candles} candles', style: const TextStyle(color: Color(0xFF787B86), fontSize: 11)),
                            trailing: IconButton(
                              icon: const Icon(Icons.play_circle_outline, color: Color(0xFF26a69a)),
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

