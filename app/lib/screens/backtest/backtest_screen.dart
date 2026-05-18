import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bots/registry.dart';
import '../../core/config.dart';
import '../../services/engine_messages.dart';
import '../../state/backtest_state.dart';
import '../../state/providers.dart';
import '../../widgets/chart/chart_controller.dart';
import '../../widgets/chart/chart_widget.dart';
import 'bot_config_panel.dart';
import 'run_controls.dart';
import 'results_view.dart';

/// Orchestrator screen — composes 4 focused widgets and wires them to state.
/// Total LOC kept under 200, unlike the legacy backtest_screen.dart (3,212 LOC).
class BacktestScreen extends ConsumerStatefulWidget {
  const BacktestScreen({super.key});

  @override
  ConsumerState<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends ConsumerState<BacktestScreen> {
  final ChartController _chartCtrl = ChartController();

  // User-selectable params (kept in this stateful widget for simplicity).
  String _selectedSymbol = 'BTCUSDT';
  String _selectedTimeframe = '1h';
  String _selectedBot = 'ema_cross';
  Map<String, dynamic> _botParams = {};
  double _initialCash = 10000;
  double _takerFeePct = 0.1;
  double _slippagePct = 0.05;
  int _speedMs = 0;

  @override
  void initState() {
    super.initState();
    _botParams = Map<String, dynamic>.from(
        BotRegistry.info(_selectedBot).defaultParams);
  }

  @override
  void dispose() {
    _chartCtrl.dispose();
    super.dispose();
  }

  Future<void> _onStart() async {
    final db = ref.read(databaseProvider);
    final candles = await db.candles.queryRange(_selectedSymbol, _selectedTimeframe);
    if (!mounted) return;

    if (candles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No candles for $_selectedSymbol $_selectedTimeframe — download data first.')));
      return;
    }

    await _chartCtrl.clear();
    await _chartCtrl.setCandles(candles);
    await _chartCtrl.fitContent();

    final ctrl = ref.read(backtestControllerProvider.notifier);
    await ctrl.start(
      candles: candles,
      bots: [BotSpec(name: _selectedBot, params: _botParams)],
      config: BacktestConfig(
        initialCash: _initialCash,
        takerFeePct: _takerFeePct,
        slippagePct: _slippagePct,
      ),
      initialSpeedMs: _speedMs,
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(backtestControllerProvider);
    final ctrl = ref.read(backtestControllerProvider.notifier);

    // When trades come in, push them to the chart as markers.
    ref.listen<BacktestStatus>(backtestControllerProvider, (prev, next) {
      if (next is BacktestRunning && prev is BacktestRunning) {
        if (next.trades.length > prev.trades.length) {
          for (final t in next.trades.skip(prev.trades.length)) {
            _chartCtrl.addMarker(ChartMarker.entry(t));
            _chartCtrl.addMarker(ChartMarker.exit(t));
          }
        }
      } else if (next is BacktestDone) {
        _chartCtrl.setEquityCurve([
          for (int i = 0; i < next.result.equityCurve.length; i++)
            (t: next.result.startTimestampMs + i * 60000, v: next.result.equityCurve[i]),
        ]);
      }
    });

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left column: configuration + controls + results
          SizedBox(
            width: 340,
            child: ListView(
              children: [
                BotConfigPanel(
                  symbol: _selectedSymbol,
                  timeframe: _selectedTimeframe,
                  selectedBot: _selectedBot,
                  initialCash: _initialCash,
                  feePct: _takerFeePct,
                  slippagePct: _slippagePct,
                  onSymbolChanged: (v) => setState(() => _selectedSymbol = v),
                  onTimeframeChanged: (v) => setState(() => _selectedTimeframe = v),
                  onBotChanged: (v) {
                    setState(() {
                      _selectedBot = v;
                      _botParams = Map<String, dynamic>.from(BotRegistry.info(v).defaultParams);
                    });
                  },
                  onInitialCashChanged: (v) => setState(() => _initialCash = v),
                  onFeeChanged: (v) => setState(() => _takerFeePct = v),
                  onSlippageChanged: (v) => setState(() => _slippagePct = v),
                ),
                const SizedBox(height: 12),
                RunControls(
                  status: status,
                  speedMs: _speedMs,
                  onStart: _onStart,
                  onPause: ctrl.pause,
                  onResume: ctrl.resume,
                  onStep: ctrl.step,
                  onCancel: ctrl.cancel,
                  onSpeedChanged: (v) {
                    setState(() => _speedMs = v);
                    ctrl.setSpeed(v);
                  },
                ),
                const SizedBox(height: 12),
                ResultsView(status: status),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Right column: chart
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ChartWidget(
                controller: _chartCtrl,
                onDiagnostic: (msg) =>
                    debugPrint('[chart] $msg'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
