import 'dart:async';
import 'package:flutter/material.dart';
import 'package:backtester_shell/services/api_service.dart';
import 'package:backtester_shell/screens/analysis_screen.dart';
import 'package:backtester_shell/screens/backtest_screen.dart';
import 'package:backtester_shell/screens/optimization_screen.dart';
import 'package:backtester_shell/screens/settings_screen.dart';
import 'package:backtester_shell/services/ws_service.dart';
import 'package:backtester_shell/widgets/status_dot.dart';

/// Main scaffold — sidebar nav + content area.
class HomeScreen extends StatefulWidget {
  final ApiService apiService;
  const HomeScreen({super.key, required this.apiService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _backendOnline = false;
  bool _checking = true;
  int _selectedIndex = 0;

  // Preset handed off from OptimizationScreen → BacktestScreen.
  // Consumed once, then cleared.
  OptimizationResult? _pendingApply;

  // GlobalKey lets us trigger Data Manager from elsewhere if needed.
  final GlobalKey<State<BacktestScreen>> _backtestKey = GlobalKey();

  late final WsService _wsService;
  Timer? _healthTimer;

  @override
  void initState() {
    super.initState();
    _wsService = WsService();
    _wsService.connect();
    _pollHealth();
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    _wsService.disconnect();
    super.dispose();
  }

  Future<void> _pollHealth() async {
    if (!mounted) return;
    final h = await widget.apiService.checkHealth();
    if (!mounted) return;
    setState(() { _backendOnline = h.ok; _checking = false; });
    _healthTimer = Timer(const Duration(seconds: 5), () { _pollHealth(); });
  }

  void _onApplyBest(OptimizationResult result) {
    setState(() {
      _pendingApply = result;
      _selectedIndex = 0; // jump to Backtest
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _Sidebar(
            selectedIndex: _selectedIndex,
            onSelect: (i) => setState(() => _selectedIndex = i),
            backendOnline: _backendOnline,
            checking: _checking,
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: switch (_selectedIndex) {
              0 => BacktestScreen(
                  key: _backtestKey,
                  apiService: widget.apiService,
                  wsService: _wsService,
                  initialApply: _pendingApply,
                  onApplyConsumed: () => setState(() => _pendingApply = null),
                ),
              1 => OptimizationScreen(
                  apiService: widget.apiService,
                  wsService: _wsService,
                  onApplyBest: _onApplyBest,
                ),
              2 => AnalysisScreen(apiService: widget.apiService),
              _ => SettingsScreen(apiService: widget.apiService),
            },
          ),
        ],
      ),
    );
  }
}

// ── Sidebar ────────────────────────────────────────────────────

class _Sidebar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool backendOnline;
  final bool checking;

  const _Sidebar({
    required this.selectedIndex,
    required this.onSelect,
    required this.backendOnline,
    required this.checking,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.candlestick_chart, 'Backtest'),
      (Icons.science_outlined, 'Optimize'),
      (Icons.analytics_outlined, 'Analysis'),
      (Icons.settings_outlined, 'Settings'),
    ];

    return Container(
      width: 64,
      color: const Color(0xFF1E222D),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF26a69a),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.bar_chart, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          ...items.indexed.map((e) {
            final (idx, item) = e;
            final selected = idx == selectedIndex;
            return Tooltip(
              message: item.$2,
              preferBelow: false,
              child: InkWell(
                onTap: () => onSelect(idx),
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color: selected ? const Color(0xFF26a69a).withValues(alpha: 0.15) : Colors.transparent,
                    border: selected
                        ? const Border(left: BorderSide(color: Color(0xFF26a69a), width: 3))
                        : null,
                  ),
                  child: Icon(
                    item.$1,
                    color: selected ? const Color(0xFF26a69a) : const Color(0xFF787B86),
                    size: 22,
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Tooltip(
              message: checking ? 'Checking...' : (backendOnline ? 'Backend online' : 'Backend offline'),
              child: StatusDot(online: backendOnline, checking: checking),
            ),
          ),
        ],
      ),
    );
  }
}
