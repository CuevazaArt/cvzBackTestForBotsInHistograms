import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bots/registry.dart';
import '../../core/config.dart';
import '../../core/models/candle.dart';
import '../../indicators/registry.dart';
import '../../services/engine_messages.dart';
import '../../state/backtest_state.dart';
import '../../state/providers.dart';
import '../../widgets/chart/chart_controller.dart';
import '../../widgets/chart/chart_widget.dart';
import 'bot_config_panel.dart';
import 'run_controls.dart';
import 'results_view.dart';

class BacktestScreen extends ConsumerStatefulWidget {
  const BacktestScreen({super.key});

  @override
  ConsumerState<BacktestScreen> createState() => _BacktestScreenState();
}

class _BacktestScreenState extends ConsumerState<BacktestScreen> {
  final ChartController _chartCtrl = ChartController();

  String _selectedSymbol = 'BTCUSDT';
  String _selectedTimeframe = '1h';
  String _selectedBot = 'ema_cross';
  Map<String, dynamic> _botParams = {};
  double _initialCash = 10000;
  double _takerFeePct = 0.1;
  double _slippagePct = 0.05;
  int _speedMs = 0;
  bool _stepMode = false;

  String _markersMode = 'full';
  bool _indicatorsVisible = true;
  bool _equityVisible = true;

  List<Candle>? _lastCandles;

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

    _lastCandles = candles;
    await _chartCtrl.clear();
    await _chartCtrl.setCandles(candles);
    await _chartCtrl.fitContent();

    // Reset chart toggle state on new run
    setState(() {
      _markersMode = 'full';
      _indicatorsVisible = true;
      _equityVisible = true;
    });

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

    if (_stepMode) {
      await Future.delayed(const Duration(milliseconds: 100));
      ctrl.pause();
    }
  }

  Map<String, dynamic> get _configMeta => {
    'bot': _selectedBot,
    'bot_display': BotRegistry.info(_selectedBot).displayName,
    'params': _botParams,
    'symbol': _selectedSymbol,
    'timeframe': _selectedTimeframe,
    'initial_cash': _initialCash,
    'taker_fee_pct': _takerFeePct,
    'slippage_pct': _slippagePct,
  };

  void _autoSave(BacktestDone done) {
    final db = ref.read(databaseProvider);
    db.results.saveResult(done.result, config: _configMeta);
  }

  void _pushIndicatorOverlays(BacktestDone done) {
    final candles = _lastCandles;
    if (candles == null || candles.isEmpty) return;

    if (_selectedBot == 'ema_cross') {
      _computeAndPushIndicator('EMA Fast', 'ema',
          {'period': _botParams['fastPeriod'] ?? 12}, candles, '#fbbf24');
      _computeAndPushIndicator('EMA Slow', 'ema',
          {'period': _botParams['slowPeriod'] ?? 26}, candles, '#60a5fa');
    } else if (_selectedBot == 'macd_cross') {
      _computeAndPushIndicator('EMA Fast', 'ema',
          {'period': _botParams['fastPeriod'] ?? 12}, candles, '#fbbf24');
      _computeAndPushIndicator('EMA Slow', 'ema',
          {'period': _botParams['slowPeriod'] ?? 26}, candles, '#60a5fa');
    } else if (_selectedBot == 'bollinger_reversion') {
      _computeAndPushIndicator('BB Mid', 'sma',
          {'period': _botParams['period'] ?? 20}, candles, '#a78bfa');
    } else if (_selectedBot == 'elphaba_short') {
      _computeAndPushIndicator('EMA', 'ema',
          {'period': _botParams['emaPeriod'] ?? 50}, candles, '#60a5fa');
    }

    _chartCtrl.setEquityCurve([
      for (int i = 0; i < done.result.equityCurve.length; i++)
        (t: done.result.startTimestampMs + i * 60000, v: done.result.equityCurve[i]),
    ]);
  }

  void _computeAndPushIndicator(String key, String type,
      Map<String, dynamic> params, List<Candle> candles, String color) {
    final indicator = IndicatorRegistry.create(type, params);
    final points = <({int t, double v})>[];
    for (final c in candles) {
      indicator.update(c);
      if (indicator.isReady && indicator.value != null) {
        points.add((t: c.timestampMs, v: indicator.value!));
      }
    }
    if (points.isNotEmpty) {
      _chartCtrl.setIndicator(key, points, color: color);
    }
  }

  void _onMarkersModeChanged(String mode) {
    setState(() => _markersMode = mode);
    _chartCtrl.setMarkersMode(mode);
  }

  void _onIndicatorsVisibleChanged(bool visible) {
    setState(() => _indicatorsVisible = visible);
    _chartCtrl.setIndicatorsVisible(visible);
  }

  void _onEquityVisibleChanged(bool visible) {
    setState(() => _equityVisible = visible);
    _chartCtrl.setEquityVisible(visible);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(backtestControllerProvider);
    final ctrl = ref.read(backtestControllerProvider.notifier);

    ref.listen<BacktestStatus>(backtestControllerProvider, (prev, next) {
      if (next is BacktestRunning && prev is BacktestRunning) {
        if (next.trades.length > prev.trades.length) {
          for (final t in next.trades.skip(prev.trades.length)) {
            _chartCtrl.addMarker(ChartMarker.entry(t));
            _chartCtrl.addMarker(ChartMarker.exit(t));
          }
        }
      } else if (next is BacktestDone) {
        _autoSave(next);
        _pushIndicatorOverlays(next);
      }
    });

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          // ─── Top bar: config + controls ───────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  BotConfigToolbar(
                    symbol: _selectedSymbol,
                    timeframe: _selectedTimeframe,
                    selectedBot: _selectedBot,
                    botParams: _botParams,
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
                    onBotParamsChanged: (v) => setState(() => _botParams = v),
                    onInitialCashChanged: (v) => setState(() => _initialCash = v),
                    onFeeChanged: (v) => setState(() => _takerFeePct = v),
                    onSlippageChanged: (v) => setState(() => _slippagePct = v),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: SizedBox(height: 20, child: VerticalDivider(width: 1, color: Theme.of(context).dividerColor)),
                  ),
                  RunControlsInline(
                    status: status,
                    speedMs: _speedMs,
                    stepMode: _stepMode,
                    onStart: _onStart,
                    onPause: ctrl.pause,
                    onResume: ctrl.resume,
                    onStep: ctrl.step,
                    onCancel: ctrl.cancel,
                    onSpeedChanged: (v) {
                      setState(() => _speedMs = v);
                      ctrl.setSpeed(v);
                    },
                    onStepModeChanged: (v) => setState(() => _stepMode = v),
                  ),
                  if (status is BacktestRunning) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: SizedBox(height: 20, child: VerticalDivider(width: 1, color: Theme.of(context).dividerColor)),
                    ),
                    _LiveBadge(status: status),
                  ],
                ],
              ),
            ),
          ),
          // ─── Chart (takes all remaining space) ────────────────
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: ChartWidget(
                controller: _chartCtrl,
                onDiagnostic: (msg) => debugPrint('[chart] $msg'),
              ),
            ),
          ),
          // ─── Bottom bar: metrics + chart toggles ──────────────
          Container(
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            child: ResultsBar(
              status: status,
              markersMode: _markersMode,
              indicatorsVisible: _indicatorsVisible,
              equityVisible: _equityVisible,
              onMarkersModeChanged: _onMarkersModeChanged,
              onIndicatorsVisibleChanged: _onIndicatorsVisibleChanged,
              onEquityVisibleChanged: _onEquityVisibleChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  final BacktestRunning status;
  const _LiveBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${status.percent.toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${status.trades.length} trades',
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        if (status.lastEquity != null) ...[
          const SizedBox(width: 8),
          Text(
            '${status.lastEquity!.toStringAsFixed(0)} USDT',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ],
        if (status.paused) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.orange.withAlpha(30),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Text('PAUSED', style: TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }
}
