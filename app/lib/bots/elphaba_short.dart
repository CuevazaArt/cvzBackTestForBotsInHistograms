import '../core/models/candle.dart';
import '../core/models/order.dart';
import '../core/models/portfolio.dart';
import '../core/models/position.dart';
import '../indicators/rsi.dart';
import '../indicators/ema.dart';
import 'bot_base.dart';

/// Short-selling bot: opens short when RSI is overbought AND price is below
/// a slow EMA (confirming downtrend). Covers when RSI becomes oversold or
/// when stop-loss / take-profit hit.
class ElphabaShort extends BotBase {
  final int rsiPeriod;
  final int emaPeriod;
  final double overboughtLevel;
  final double oversoldLevel;
  final double profitFactorPct;
  final double stopLossPct;
  final double riskPerTradePct;

  @override
  final String id;
  @override
  final String name;

  late final RSI _rsi;
  late final EMA _ema;
  bool _inPosition = false;

  ElphabaShort({
    this.id = 'elphaba_short',
    this.name = 'Elphaba Short',
    this.rsiPeriod = 14,
    this.emaPeriod = 50,
    this.overboughtLevel = 70.0,
    this.oversoldLevel = 30.0,
    this.profitFactorPct = 3.0,
    this.stopLossPct = 5.0,
    this.riskPerTradePct = 2.0,
  }) {
    _rsi = RSI(period: rsiPeriod);
    _ema = EMA(period: emaPeriod);
  }

  @override
  Map<String, dynamic> get params => {
        'rsiPeriod': rsiPeriod,
        'emaPeriod': emaPeriod,
        'overboughtLevel': overboughtLevel,
        'oversoldLevel': oversoldLevel,
        'profitFactorPct': profitFactorPct,
        'stopLossPct': stopLossPct,
        'riskPerTradePct': riskPerTradePct,
      };

  @override
  List<BotParamSpec> paramSpec() => const [
        BotParamSpec(name: 'rsiPeriod', label: 'RSI Period', type: BotParamType.intParam, defaultValue: 14, min: 2, max: 50, step: 1),
        BotParamSpec(name: 'emaPeriod', label: 'EMA Period', type: BotParamType.intParam, defaultValue: 50, min: 10, max: 200, step: 1),
        BotParamSpec(name: 'overboughtLevel', label: 'Overbought', type: BotParamType.doubleParam, defaultValue: 70.0, min: 50.0, max: 90.0, step: 1.0),
        BotParamSpec(name: 'oversoldLevel', label: 'Oversold', type: BotParamType.doubleParam, defaultValue: 30.0, min: 10.0, max: 50.0, step: 1.0),
        BotParamSpec(name: 'profitFactorPct', label: 'Take Profit %', type: BotParamType.percent, defaultValue: 3.0, min: 0.1, max: 50.0, step: 0.1),
        BotParamSpec(name: 'stopLossPct', label: 'Stop Loss %', type: BotParamType.percent, defaultValue: 5.0, min: 0.0, max: 50.0, step: 0.5),
        BotParamSpec(name: 'riskPerTradePct', label: 'Risk per trade %', type: BotParamType.percent, defaultValue: 2.0, min: 0.5, max: 20.0, step: 0.5),
      ];

  double _maxShortSellQty(Portfolio portfolio) =>
      portfolio
          .positionsForBot(id)
          .where((p) => p.side == PositionSide.short)
          .fold(0.0, (s, p) => s + p.qty);

  @override
  List<OrderRequest> onCandle(Candle candle, Portfolio portfolio) {
    _rsi.update(candle);
    _ema.update(candle);

    if (_inPosition && portfolio.positionsForBot(id).isEmpty) {
      _inPosition = false;
    }

    if (!_rsi.isReady || !_ema.isReady) return const [];

    final price = candle.close;
    final rsiVal = _rsi.value!;
    final emaVal = _ema.value!;

    if (!_inPosition && rsiVal > overboughtLevel && price < emaVal) {
      final qty = calcQty(portfolio.cash, price, riskPct: riskPerTradePct);
      if (qty <= 0) return const [];
      _inPosition = true;
      return [
        OrderRequest.openShort(
          botId: id,
          qty: qty,
          bracket: BracketSpec(
            stopLossPct: stopLossPct > 0 ? stopLossPct : null,
            takeProfitPct: profitFactorPct > 0 ? profitFactorPct : null,
          ),
        ),
      ];
    }

    if (_inPosition && rsiVal < oversoldLevel) {
      final qty = _maxShortSellQty(portfolio);
      _inPosition = false;
      if (qty <= 0) return const [];
      return [OrderRequest.closeShort(botId: id, qty: qty)];
    }

    return const [];
  }

  @override
  BotState? state() => BotState(
        phase: _rsi.isReady && _ema.isReady ? 'live' : 'warmup',
        decision: _inPosition ? 'short' : 'flat',
        indicators: {
          if (_rsi.value != null) 'rsi': _rsi.value!,
          if (_ema.value != null) 'ema': _ema.value!,
        },
      );
}
