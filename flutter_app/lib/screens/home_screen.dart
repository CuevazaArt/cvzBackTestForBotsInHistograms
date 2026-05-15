import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/backtest_state.dart';
import '../widgets/topbar.dart';
import '../widgets/chart_webview.dart';
import '../widgets/sidebar/sidebar.dart';
import '../widgets/bottom_tabs/stats_tab.dart';
import '../widgets/bottom_tabs/trades_tab.dart';
import '../widgets/bottom_tabs/placeholder_heatmap.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _chartKey = GlobalKey<ChartWebViewState>();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _onRun() async {
    final cfg = ref.read(configProvider);
    _chartKey.currentState?.setTopbar(
      cfg.symbol, cfg.timeframe, cfg.bot,
      cfg.startMs != null ? '${cfg.startMs}–${cfg.endMs}' : '',
    );

    await ref.read(runProvider.notifier).run();

    final result = ref.read(runProvider).result;
    if (result != null && _chartKey.currentState != null) {
      _chartKey.currentState!.loadResult(result);
      _tabCtrl.animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final runState = ref.watch(runProvider);

    return Scaffold(
      body: Column(
        children: [
          // Top bar
          AppTopBar(onRun: _onRun, isRunning: runState.status == RunStatus.running),

          // Main content: sidebar | charts + stats
          Expanded(
            child: Row(
              children: [
                // Sidebar
                SizedBox(
                  width: 260,
                  child: Sidebar(onRun: _onRun),
                ),

                const VerticalDivider(width: 1),

                // Right pane: charts on top, tabs on bottom
                Expanded(
                  child: Column(
                    children: [
                      // Chart WebView (LW Charts)
                      Expanded(
                        flex: 3,
                        child: ChartWebView(key: _chartKey),
                      ),

                      const Divider(height: 1),

                      // Bottom tab panel
                      SizedBox(
                        height: 220,
                        child: Column(
                          children: [
                            TabBar(
                              controller: _tabCtrl,
                              isScrollable: false,
                              indicatorColor: Theme.of(context).colorScheme.primary,
                              labelStyle: const TextStyle(fontSize: 12),
                              tabs: const [
                                Tab(text: 'Stats'),
                                Tab(text: 'Trades'),
                                Tab(text: 'Heatmap'),
                              ],
                            ),
                            Expanded(
                              child: TabBarView(
                                controller: _tabCtrl,
                                children: [
                                  StatsTab(result: runState.result),
                                  TradesTab(
                                    trades: runState.result?.trades ?? [],
                                  ),
                                  const PlaceholderHeatmap(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Error snackbar
          if (runState.status == RunStatus.error)
            Material(
              color: const Color(0xFFEF5350),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(runState.errorMsg ?? 'Unknown error',
                            style: const TextStyle(color: Colors.white, fontSize: 12))),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 16),
                      onPressed: () => ref.read(runProvider.notifier).reset(),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
