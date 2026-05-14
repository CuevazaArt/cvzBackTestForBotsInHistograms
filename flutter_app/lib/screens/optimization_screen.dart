import 'dart:async';
import 'package:flutter/material.dart';
import 'package:backtester_shell/services/api_service.dart';
import 'package:backtester_shell/widgets/param_bounds_editor.dart';

class OptimizationScreen extends StatefulWidget {
  final ApiService apiService;
  const OptimizationScreen({super.key, required this.apiService});

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
  double _progress = 0;
  
  final _trialsCtrl = TextEditingController(text: '50');

  @override
  void initState() {
    super.initState();
    _loadCatalog();
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

  void _runOptimization() {
    // TODO: implement REST/WebSocket calls to run Optuna in the backend
    setState(() {
      _running = true;
      _error = 'Backend Optuna integration pending...';
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _running = false);
    });
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
          progress: _progress,
          trialsCtrl: _trialsCtrl,
          onSymbolChanged: (v) => setState(() => _selectedSymbol = v),
          onTimeframeChanged: (v) => setState(() => _selectedTimeframe = v),
          onBotChanged: (v) {
            setState(() {
              _selectedBot = v;
              _paramSpecs = {};
            });
            if (v != null) _loadBotParams(v);
          },
          onRun: _runOptimization,
        ),
        if (_error != null)
          Container(
            color: const Color(0xFFef5350).withOpacity(0.1),
            padding: const EdgeInsets.all(8),
            width: double.infinity,
            child: Text('⚠ $_error', style: const TextStyle(color: Color(0xFFef5350))),
          ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Parameter Setup
              Expanded(
                flex: 2,
                child: Container(
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Color(0xFF2B2B43))),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Search Space', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      Expanded(
                        child: ParamBoundsEditor(
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
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Leaderboard (Top Trials)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'Waiting for optimization to start...',
                          style: TextStyle(color: const Color(0xFF787B86).withOpacity(0.5)),
                        ),
                      ),
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

class _OptTopBar extends StatelessWidget {
  final List<SymbolEntry> symbols;
  final List<BotInfo> bots;
  final String? selectedSymbol;
  final String selectedTimeframe;
  final String? selectedBot;
  final bool running;
  final double progress;
  final TextEditingController trialsCtrl;
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
    required this.trialsCtrl,
    required this.onSymbolChanged,
    required this.onTimeframeChanged,
    required this.onBotChanged,
    required this.onRun,
  });

  static const _timeframes = ['1m', '5m', '15m', '1h', '4h', '1d'];

  @override
  Widget build(BuildContext context) {
    final distinctSymbols = symbols.map((s) => s.symbol).toSet().toList()..sort();
    return Container(
      height: 48,
      color: const Color(0xFF1E222D),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _DropdownChip<String>(
            value: selectedSymbol,
            hint: 'Symbol',
            items: distinctSymbols,
            onChanged: onSymbolChanged,
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
            value: selectedBot,
            hint: 'Bot',
            items: bots.map((b) => b.name).toList(),
            onChanged: onBotChanged,
          ),
          const SizedBox(width: 16),
          const Text('Trials:', style: TextStyle(color: Color(0xFF787B86), fontSize: 12)),
          const SizedBox(width: 4),
          SizedBox(
            width: 40,
            child: TextField(
              controller: trialsCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(isDense: true, border: InputBorder.none),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: running || selectedSymbol == null || selectedBot == null ? null : onRun,
            icon: running
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.science, size: 16),
            label: Text(running ? '${progress.toStringAsFixed(0)}%' : 'Run Optuna'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFb388ff), // Purple for optimization
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
