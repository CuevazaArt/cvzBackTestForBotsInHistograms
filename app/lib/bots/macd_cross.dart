import '../core/models/candle.dart';
import '../core/models/order.dart';
import '../core/models/portfolio.dart';
import '../indicators/macd.dart';
import 'bot_base.dart';

/// MACD crossover: BUY when MACD crosses above signal, SELL on cross below.
class MACDCross extends BotBase {
  final int fastPeriod;
  final int slowPeriod;
  final int signalPeriod;
  final double profitFactorPct;
  final double stopLossPct;
  final double riskPerTradePct;

  @override
  final String id;
  @override
  final String name;

  late final MACD _macd;
  double? _prevMacd;
  double? _prevSignal;
  bool _inPosition = false;

  MACDCross({
    this.id = 'macd_cross',
    this.name = 'MACD Crossover',
    this.fastPeriod = 12,
    this.slowPeriod = 26,
    this.signalPeriod = 9,
    this.profitFactorPct = 3.0,
    this.stopLossPct = 5.0,
    this.riskPerTradePct = 2.0,
  }) {
    _macd = MACD(
      fastPeriod: fastPeriod,
      slowPeriod: slowPeriod,
      signalPeriod: signalPeriod,
    );
  }

  @override
  Map<String, dynamic> get params => {
        'fastPeriod': fastPeriod,
        'slowPeriod': slowPeriod,
        'signalPeriod': signalPeriod,
        'profitFactorPct': profitFactorPct,
        'stopLossPct': stopLossPct,
        'riskPerTradePct': riskPerTradePct,
      };

  @override
  List<BotParamSpec> paramSpec() => const [
        BotParamSpec(name: 'fastPeriod', label: 'Fast EMA', type: BotParamType.intParam, defaultValue: 12, min: 2, max: 50, step: 1),
        BotParamSpec(name: 'slowPeriod', label: 'Slow EMA', type: BotParamType.intParam, defaultValue: 26, min: 5, max: 200, step: 1),
        BotParamSpec(name: 'signalPeriod', label: 'Signal', type: BotParamType.intParam, defaultValue: 9, min: 2, max: 50, step: 1),
        BotParamSpec(name: 'profitFactorPct', label: 'Take Profit %', type: BotParamType.percent, defaultValue: 3.0, min: 0.1, max: 50.0, step: 0.1),
        BotParamSpec(name: 'stopLossPct', label: 'Stop Loss %', type: BotParamType.percent, defaultValue: 5.0, min: 0.0, max: 50.0, step: 0.5),
        BotParamSpec(name: 'riskPerTradePct', label: 'Risk per trade %', type: BotParamType.percent, defaultValue: 2.0, min: 0.5, max: 20.0, step: 0.5),
      ];

  @override
  List<OrderRequest> onCandle(Candle candle, Portfolio portfolio) {
    _prevMacd = _macd.value;
    _prevSignal = _macd.signal;
    _macd.update(candle);

    if (_inPosition && portfolio.positionsForBot(id).isEmpty) {
      _inPosition = false;
    }

    if (!_macd.isReady || _prevMacd == null || _prevSignal == null) {
      return const [];
    }

    final macdNow = _macd.value!;
    final signalNow = _macd.signal!;
    final bullishCross = _prevMacd! <= _prevSignal! && macdNow > signalNow;
    final bearishCross = _prevMacd! >= _prevSignal! && macdNow < signalNow;

    if (bullishCross && !_inPosition) {
      final qty = calcQty(portfolio.cash, candle.close, riskPct: riskPerTradePct);
      if (qty <= 0) return const [];
      _inPosition = true;
      return [
        OrderRequest.openLong(
          botId: id,
          qty: qty,
          bracket: BracketSpec(
            stopLossPct: stopLossPct > 0 ? stopLossPct : null,
            takeProfitPct: profitFactorPct > 0 ? profitFactorPct : null,
          ),
        ),
      ];
    }

    if (bearishCross && _inPosition) {
      final qty = maxSellQty(portfolio);
      _inPosition = false;
      if (qty <= 0) return const [];
      return [OrderRequest.closeLong(botId: id, qty: qty)];
    }

    return const [];
  }

  @override
  BotState? state() => BotState(
        phase: _macd.isReady ? 'live' : 'warmup',
        decision: _inPosition ? 'long' : 'flat',
        indicators: {
          if (_macd.value != null) 'macd': _macd.value!,
          if (_macd.signal != null) 'signal': _macd.signal!,
          if (_macd.histogram != null) 'histogram': _macd.histogram!,
        },
      );
}
