import '../core/models/candle.dart';
import '../core/models/order.dart';
import '../core/models/portfolio.dart';
import '../indicators/ema.dart';
import 'bot_base.dart';

/// EMA crossover with bracket-order risk management.
///
/// BUY on golden cross with attached SL/TP/optional trailing stop.
/// SELL on death cross (market). Engine handles intra-bar SL/TP firing.
class EMACross extends BotBase {
  final int fastPeriod;
  final int slowPeriod;
  final double profitFactorPct;   // e.g. 2.0 = 2% take profit
  final double stopLossPct;       // e.g. 5.0 = 5% stop loss
  final double trailingStopPct;   // 0.0 = disabled
  final double riskPerTradePct;
  final bool useRiskSizing;

  @override
  final String id;
  @override
  final String name;

  late final EMA _fast;
  late final EMA _slow;
  double? _prevFast;
  double? _prevSlow;
  bool _inPosition = false;

  EMACross({
    this.id = 'ema_cross',
    this.name = 'EMA Crossover',
    this.fastPeriod = 12,
    this.slowPeriod = 26,
    this.profitFactorPct = 2.0,
    this.stopLossPct = 5.0,
    this.trailingStopPct = 0.0,
    this.riskPerTradePct = 2.0,
    this.useRiskSizing = false,
  }) {
    if (fastPeriod >= slowPeriod) {
      throw ArgumentError('fastPeriod must be < slowPeriod');
    }
    _fast = EMA(period: fastPeriod);
    _slow = EMA(period: slowPeriod);
  }

  @override
  Map<String, dynamic> get params => {
        'fastPeriod': fastPeriod,
        'slowPeriod': slowPeriod,
        'profitFactorPct': profitFactorPct,
        'stopLossPct': stopLossPct,
        'trailingStopPct': trailingStopPct,
        'riskPerTradePct': riskPerTradePct,
        'useRiskSizing': useRiskSizing,
      };

  @override
  List<BotParamSpec> paramSpec() => const [
        BotParamSpec(name: 'fastPeriod', label: 'Fast EMA', type: BotParamType.intParam, defaultValue: 12, min: 2, max: 50, step: 1),
        BotParamSpec(name: 'slowPeriod', label: 'Slow EMA', type: BotParamType.intParam, defaultValue: 26, min: 5, max: 200, step: 1),
        BotParamSpec(name: 'profitFactorPct', label: 'Take Profit %', type: BotParamType.percent, defaultValue: 2.0, min: 0.1, max: 50.0, step: 0.1),
        BotParamSpec(name: 'stopLossPct', label: 'Stop Loss %', type: BotParamType.percent, defaultValue: 5.0, min: 0.0, max: 50.0, step: 0.5),
        BotParamSpec(name: 'trailingStopPct', label: 'Trailing Stop %', type: BotParamType.percent, defaultValue: 0.0, min: 0.0, max: 20.0, step: 0.5),
        BotParamSpec(name: 'riskPerTradePct', label: 'Risk per trade %', type: BotParamType.percent, defaultValue: 2.0, min: 0.5, max: 20.0, step: 0.5),
      ];

  @override
  List<OrderRequest> onCandle(Candle candle, Portfolio portfolio) {
    _prevFast = _fast.value;
    _prevSlow = _slow.value;
    _fast.update(candle);
    _slow.update(candle);

    // Sync state if engine closed us via bracket.
    if (_inPosition && portfolio.positionsForBot(id).isEmpty) {
      _inPosition = false;
    }

    // Need both EMAs ready AND at least one prior value to detect a crossing.
    if (!_fast.isReady || !_slow.isReady || _prevFast == null || _prevSlow == null) {
      return const [];
    }

    final fastNow = _fast.value!;
    final slowNow = _slow.value!;
    final golden = _prevFast! <= _prevSlow! && fastNow > slowNow;
    final death = _prevFast! >= _prevSlow! && fastNow < slowNow;

    if (golden && !_inPosition) {
      final qty = useRiskSizing
          ? sizeByRisk(
              equity: portfolio.cash,
              entryPrice: candle.close,
              stopPrice: candle.close * (1 - stopLossPct / 100),
              riskPct: riskPerTradePct,
            )
          : calcQty(portfolio.cash, candle.close, riskPct: riskPerTradePct);
      if (qty <= 0) return const [];
      _inPosition = true;
      return [
        OrderRequest.openLong(
          botId: id,
          qty: qty,
          bracket: BracketSpec(
            stopLossPct: stopLossPct > 0 ? stopLossPct : null,
            takeProfitPct: profitFactorPct > 0 ? profitFactorPct : null,
            trailingStopPct: trailingStopPct > 0 ? trailingStopPct : null,
          ),
        ),
      ];
    }

    if (death && _inPosition) {
      final qty = maxSellQty(portfolio);
      _inPosition = false;
      if (qty <= 0) return const [];
      return [OrderRequest.closeLong(botId: id, qty: qty)];
    }

    return const [];
  }

  @override
  BotState? state() => BotState(
        phase: _fast.isReady ? 'live' : 'warmup',
        decision: _inPosition ? 'long' : 'flat',
        indicators: {
          if (_fast.value != null) 'fast_ema': _fast.value!,
          if (_slow.value != null) 'slow_ema': _slow.value!,
        },
      );
}
