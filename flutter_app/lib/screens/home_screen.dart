import 'package:flutter/material.dart';
import 'package:backtester_shell/services/api_service.dart';
import 'package:backtester_shell/screens/backtest_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _pollHealth();
  }

  Future<void> _pollHealth() async {
    while (mounted) {
      final h = await widget.apiService.checkHealth();
      if (mounted) setState(() { _backendOnline = h.ok; _checking = false; });
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // ── Sidebar ──────────────────────────────────────────
          _Sidebar(
            selectedIndex: _selectedIndex,
            onSelect: (i) => setState(() => _selectedIndex = i),
            backendOnline: _backendOnline,
            checking: _checking,
          ),
          const VerticalDivider(width: 1),
          // ── Content ──────────────────────────────────────────
          Expanded(
            child: _selectedIndex == 0
                ? BacktestScreen(apiService: widget.apiService)
                : const _PlaceholderPage(label: 'Coming soon'),
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
      (Icons.settings_outlined, 'Settings'),
    ];

    return Container(
      width: 64,
      color: const Color(0xFF1E222D),
      child: Column(
        children: [
          const SizedBox(height: 12),
          // Logo
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
          // Backend status
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

class _PlaceholderPage extends StatelessWidget {
  final String label;
  const _PlaceholderPage({required this.label});

  @override
  Widget build(BuildContext context) => Center(
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      );
}
