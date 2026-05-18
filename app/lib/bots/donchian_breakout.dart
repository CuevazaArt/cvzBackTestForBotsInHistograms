import 'dart:collection';
import '../core/models/candle.dart';
import '../core/models/order.dart';
import '../core/models/portfolio.dart';
import 'bot_base.dart';

/// Donchian Channel breakout (turtle-trading style):
/// BUY when price breaks above the N-bar high channel.
/// SELL when price breaks below the M-bar low channel (exit period).
class DonchianBreakout extends BotBase {
  final int entryPeriod;
  final int exitPeriod;
  final double stopLossPct;
  final double riskPerTradePct;

  @override
  final String id;
  @override
  final String name;

  final Queue<double> _highBuffer = Queue<double>();
  final Queue<double> _lowBuffer = Queue<double>();
  bool _inPosition = false;

  DonchianBreakout({
    this.id = 'donchian_breakout',
    this.name = 'Donchian Breakout',
    this.entryPeriod = 20,
    this.exitPeriod = 10,
    this.stopLossPct = 5.0,
    this.riskPerTradePct = 2.0,
  });

  @override
  Map<String, dynamic> get params => {
        'entryPeriod': entryPeriod,
        'exitPeriod': exitPeriod,
        'stopLossPct': stopLossPct,
        'riskPerTradePct': riskPerTradePct,
      };

  @override
  List<BotParamSpec> paramSpec() => const [
        BotParamSpec(name: 'entryPeriod', label: 'Entry Period', type: BotParamType.intParam, defaultValue: 20, min: 5, max: 100, step: 1),
        BotParamSpec(name: 'exitPeriod', label: 'Exit Period', type: BotParamType.intParam, defaultValue: 10, min: 3, max: 50, step: 1),
        BotParamSpec(name: 'stopLossPct', label: 'Stop Loss %', type: BotParamType.percent, defaultValue: 5.0, min: 0.0, max: 50.0, step: 0.5),
        BotParamSpec(name: 'riskPerTradePct', label: 'Risk per trade %', type: BotParamType.percent, defaultValue: 2.0, min: 0.5, max: 20.0, step: 0.5),
      ];

  double _maxOf(Iterable<double> vals, int count) {
    double max = double.negativeInfinity;
    int i = 0;
    for (final v in vals) {
      if (i >= vals.length - count) {
        if (v > max) max = v;
      }
      i++;
    }
    return max;
  }

  double _minOf(Iterable<double> vals, int count) {
    double min = double.infinity;
    int i = 0;
    for (final v in vals) {
      if (i >= vals.length - count) {
        if (v < min) min = v;
      }
      i++;
    }
    return min;
  }

  @override
  List<OrderRequest> onCandle(Candle candle, Portfolio portfolio) {
    _highBuffer.addLast(candle.high);
    _lowBuffer.addLast(candle.low);
    if (_highBuffer.length > entryPeriod) _highBuffer.removeFirst();
    if (_lowBuffer.length > entryPeriod) _lowBuffer.removeFirst();

    if (_inPosition && portfolio.positionsForBot(id).isEmpty) {
      _inPosition = false;
    }

    if (_highBuffer.length < entryPeriod) return const [];

    final upperChannel = _maxOf(_highBuffer, entryPeriod);
    final lowerExit = _minOf(_lowBuffer, exitPeriod);

    if (!_inPosition && candle.close >= upperChannel) {
      final qty = calcQty(portfolio.cash, candle.close, riskPct: riskPerTradePct);
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

    if (_inPosition && candle.close <= lowerExit) {
      final qty = maxSellQty(portfolio);
      _inPosition = false;
      if (qty <= 0) return const [];
      return [OrderRequest.closeLong(botId: id, qty: qty)];
    }

    return const [];
  }

  @override
  BotState? state() => BotState(
        phase: _highBuffer.length >= entryPeriod ? 'live' : 'warmup',
        decision: _inPosition ? 'long' : 'flat',
        indicators: {
          if (_highBuffer.length >= entryPeriod) 'upper': _maxOf(_highBuffer, entryPeriod),
          if (_lowBuffer.length >= exitPeriod) 'lower_exit': _minOf(_lowBuffer, exitPeriod),
        },
      );
}
