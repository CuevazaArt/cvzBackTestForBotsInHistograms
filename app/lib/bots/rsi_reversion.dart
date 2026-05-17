import '../core/models/candle.dart';
import '../core/models/order.dart';
import '../core/models/portfolio.dart';
import '../indicators/rsi.dart';
import 'bot_base.dart';

/// RSI mean-reversion: BUY when RSI < oversold, SELL when RSI > overbought.
/// Manual SL/TP checked at close (kept for parity with the legacy Python bot).
class RSIReversion extends BotBase {
  final int rsiPeriod;
  final double oversoldLevel;
  final double overboughtLevel;
  final double profitFactorPct;
  final double stopLossPct;
  final double riskPerTradePct;

  @override
  final String id;
  @override
  final String name;

  late final RSI _rsi;
  double? _entryPrice;
  bool _inPosition = false;

  RSIReversion({
    this.id = 'rsi_reversion',
    this.name = 'RSI Reversion',
    this.rsiPeriod = 14,
    this.oversoldLevel = 30.0,
    this.overboughtLevel = 70.0,
    this.profitFactorPct = 3.0,
    this.stopLossPct = 5.0,
    this.riskPerTradePct = 2.0,
  }) {
    _rsi = RSI(period: rsiPeriod);
  }

  @override
  Map<String, dynamic> get params => {
        'rsiPeriod': rsiPeriod,
        'oversoldLevel': oversoldLevel,
        'overboughtLevel': overboughtLevel,
        'profitFactorPct': profitFactorPct,
        'stopLossPct': stopLossPct,
        'riskPerTradePct': riskPerTradePct,
      };

  @override
  List<BotParamSpec> paramSpec() => const [
        BotParamSpec(name: 'rsiPeriod', label: 'RSI Period', type: BotParamType.intParam, defaultValue: 14, min: 2, max: 50, step: 1),
        BotParamSpec(name: 'oversoldLevel', label: 'Oversold', type: BotParamType.doubleParam, defaultValue: 30.0, min: 10.0, max: 50.0, step: 1.0),
        BotParamSpec(name: 'overboughtLevel', label: 'Overbought', type: BotParamType.doubleParam, defaultValue: 70.0, min: 50.0, max: 90.0, step: 1.0),
        BotParamSpec(name: 'profitFactorPct', label: 'Take Profit %', type: BotParamType.percent, defaultValue: 3.0, min: 0.1, max: 50.0, step: 0.1),
        BotParamSpec(name: 'stopLossPct', label: 'Stop Loss %', type: BotParamType.percent, defaultValue: 5.0, min: 0.0, max: 50.0, step: 0.5),
        BotParamSpec(name: 'riskPerTradePct', label: 'Risk per trade %', type: BotParamType.percent, defaultValue: 2.0, min: 0.5, max: 20.0, step: 0.5),
      ];

  @override
  List<OrderRequest> onCandle(Candle candle, Portfolio portfolio) {
    final price = candle.close;
    _rsi.update(candle);

    // Sync state if engine closed us externally.
    if (_inPosition && portfolio.positionsForBot(id).isEmpty) {
      _inPosition = false;
      _entryPrice = null;
    }

    if (!_rsi.isReady) return const [];

    // Manual stop-loss
    if (_inPosition && _entryPrice != null && stopLossPct > 0) {
      final slPrice = _entryPrice! * (1 - stopLossPct / 100);
      if (price < slPrice) {
        final qty = maxSellQty(portfolio);
        _inPosition = false;
        _entryPrice = null;
        if (qty <= 0) return const [];
        return [OrderRequest.closeLong(botId: id, qty: qty)];
      }
    }

    // Manual take-profit
    if (_inPosition && _entryPrice != null) {
      final tpPrice = _entryPrice! * (1 + profitFactorPct / 100);
      if (price >= tpPrice) {
        final qty = maxSellQty(portfolio);
        _inPosition = false;
        _entryPrice = null;
        if (qty <= 0) return const [];
        return [OrderRequest.closeLong(botId: id, qty: qty)];
      }
    }

    // RSI signals
    if (!_inPosition && _rsi.value! < oversoldLevel) {
      final qty = calcQty(portfolio.cash, price, riskPct: riskPerTradePct);
      if (qty <= 0) return const [];
      _inPosition = true;
      _entryPrice = price;
      return [OrderRequest.openLong(botId: id, qty: qty)];
    }

    if (_inPosition && _rsi.value! > overboughtLevel) {
      final qty = maxSellQty(portfolio);
      _inPosition = false;
      _entryPrice = null;
      if (qty <= 0) return const [];
      return [OrderRequest.closeLong(botId: id, qty: qty)];
    }

    return const [];
  }

  @override
  BotState? state() => BotState(
        phase: _rsi.isReady ? 'live' : 'warmup',
        decision: _inPosition ? 'long' : 'flat',
        indicators: {if (_rsi.value != null) 'rsi': _rsi.value!},
      );
}
