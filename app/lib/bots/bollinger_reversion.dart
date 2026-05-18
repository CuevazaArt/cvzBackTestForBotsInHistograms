import '../core/models/candle.dart';
import '../core/models/order.dart';
import '../core/models/portfolio.dart';
import '../indicators/bollinger.dart';
import 'bot_base.dart';

/// Mean-reversion on Bollinger Bands: BUY at lower band, SELL at upper band.
class BollingerReversion extends BotBase {
  final int period;
  final double kStd;
  final double stopLossPct;
  final double riskPerTradePct;

  @override
  final String id;
  @override
  final String name;

  late final Bollinger _bb;
  bool _inPosition = false;

  BollingerReversion({
    this.id = 'bollinger_reversion',
    this.name = 'Bollinger Reversion',
    this.period = 20,
    this.kStd = 2.0,
    this.stopLossPct = 5.0,
    this.riskPerTradePct = 2.0,
  }) {
    _bb = Bollinger(period: period, k: kStd);
  }

  @override
  Map<String, dynamic> get params => {
        'period': period,
        'kStd': kStd,
        'stopLossPct': stopLossPct,
        'riskPerTradePct': riskPerTradePct,
      };

  @override
  List<BotParamSpec> paramSpec() => const [
        BotParamSpec(name: 'period', label: 'BB Period', type: BotParamType.intParam, defaultValue: 20, min: 5, max: 100, step: 1),
        BotParamSpec(name: 'kStd', label: 'Std Dev', type: BotParamType.doubleParam, defaultValue: 2.0, min: 0.5, max: 4.0, step: 0.1),
        BotParamSpec(name: 'stopLossPct', label: 'Stop Loss %', type: BotParamType.percent, defaultValue: 5.0, min: 0.0, max: 50.0, step: 0.5),
        BotParamSpec(name: 'riskPerTradePct', label: 'Risk per trade %', type: BotParamType.percent, defaultValue: 2.0, min: 0.5, max: 20.0, step: 0.5),
      ];

  @override
  List<OrderRequest> onCandle(Candle candle, Portfolio portfolio) {
    _bb.update(candle);

    if (_inPosition && portfolio.positionsForBot(id).isEmpty) {
      _inPosition = false;
    }

    if (!_bb.isReady) return const [];

    final price = candle.close;
    final lower = _bb.lower!;
    final upper = _bb.upper!;

    if (!_inPosition && price <= lower) {
      final qty = calcQty(portfolio.cash, price, riskPct: riskPerTradePct);
      if (qty <= 0) return const [];
      _inPosition = true;
      return [
        OrderRequest.openLong(
          botId: id,
          qty: qty,
          bracket: BracketSpec(
            stopLossPct: stopLossPct > 0 ? stopLossPct : null,
          ),
        ),
      ];
    }

    if (_inPosition && price >= upper) {
      final qty = maxSellQty(portfolio);
      _inPosition = false;
      if (qty <= 0) return const [];
      return [OrderRequest.closeLong(botId: id, qty: qty)];
    }

    return const [];
  }

  @override
  BotState? state() => BotState(
        phase: _bb.isReady ? 'live' : 'warmup',
        decision: _inPosition ? 'long' : 'flat',
        indicators: {
          if (_bb.upper != null) 'bb_upper': _bb.upper!,
          if (_bb.middle != null) 'bb_middle': _bb.middle!,
          if (_bb.lower != null) 'bb_lower': _bb.lower!,
          if (_bb.percentB != null) 'percent_b': _bb.percentB!,
        },
      );
}
