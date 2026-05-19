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

    final bot = BotRegistry.create(_selectedBot, _botParams);
    final specs = bot.paramSpec();

    final overlays = <String, String>{};
    for (final s in specs) {
      if (s.name.contains('Period') || s.name.contains('period')) {
        final paramVal = _botParams[s.name] ?? s.defaultValue;
        if (paramVal is num && paramVal > 0) {
          overlays[s.name] = 'ema';
        }
      }
    }

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
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 340,
            child: ListView(
              children: [
                BotConfigPanel(
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
