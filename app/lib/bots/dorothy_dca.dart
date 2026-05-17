import 'dart:math' as math;
import '../core/models/candle.dart';
import '../core/models/order.dart';
import '../core/models/portfolio.dart';
import 'bot_base.dart';

/// DCA ladder strategy: buy on first opportunity, then buy more on dips
/// from the last anchor (up to maxPositions). Sell all at a profit target.
/// Full liquidation if price drops below avg cost * (1 - stopLossPct).
class DorothyDCA extends BotBase {
  final double profitFactorPct;
  final double marginDropPct;
  final int maxPositions;
  final double stopLossPct;
  final double quoteOrderQty;

  @override
  final String id;
  @override
  final String name;

  double? _lastBuyPrice;
  double? _sellTarget;

  DorothyDCA({
    this.id = 'dorothy_dca',
    this.name = 'Dorothy DCA',
    this.profitFactorPct = 5.0,
    this.marginDropPct = 0.4,
    this.maxPositions = 3,
    this.stopLossPct = 15.0,
    this.quoteOrderQty = 7.0,
  });

  @override
  Map<String, dynamic> get params => {
        'profitFactorPct': profitFactorPct,
        'marginDropPct': marginDropPct,
        'maxPositions': maxPositions,
        'stopLossPct': stopLossPct,
        'quoteOrderQty': quoteOrderQty,
      };

  @override
  List<BotParamSpec> paramSpec() => const [
        BotParamSpec(name: 'profitFactorPct', label: 'Profit Target %', type: BotParamType.percent, defaultValue: 5.0, min: 0.5, max: 50.0, step: 0.5),
        BotParamSpec(name: 'marginDropPct', label: 'Extra Drop %', type: BotParamType.percent, defaultValue: 0.4, min: 0.1, max: 20.0, step: 0.1),
        BotParamSpec(name: 'maxPositions', label: 'Max Positions', type: BotParamType.intParam, defaultValue: 3, min: 1, max: 10, step: 1),
        BotParamSpec(name: 'stopLossPct', label: 'Stop Loss %', type: BotParamType.percent, defaultValue: 15.0, min: 0.0, max: 50.0, step: 1.0),
        BotParamSpec(name: 'quoteOrderQty', label: 'USDT per order', type: BotParamType.doubleParam, defaultValue: 7.0, min: 1.0, max: 1000.0, step: 1.0),
      ];

  @override
  List<OrderRequest> onCandle(Candle candle, Portfolio portfolio) {
    final price = candle.close;
    final myPositions = portfolio.positionsForBot(id);
    final nOpen = myPositions.length;
    final orders = <OrderRequest>[];

    // Stop loss: liquidate all if drawdown vs avg cost is too deep.
    if (nOpen > 0 && stopLossPct > 0) {
      final totalQty = myPositions.fold(0.0, (s, p) => s + p.qty);
      final totalCost =
          myPositions.fold(0.0, (s, p) => s + p.entryPrice * p.qty);
      final avgCost = totalCost / totalQty;
      if (price < avgCost * (1 - stopLossPct / 100)) {
        _lastBuyPrice = null;
        _sellTarget = null;
        if (totalQty > 0) {
          orders.add(OrderRequest.closeLong(botId: id, qty: totalQty));
        }
        return orders;
      }
    }

    // Take profit: sell all when target hit.
    if (nOpen > 0 && _sellTarget != null && price >= _sellTarget!) {
      final qty = maxSellQty(portfolio);
      _lastBuyPrice = null;
      _sellTarget = null;
      if (qty > 0) orders.add(OrderRequest.closeLong(botId: id, qty: qty));
      return orders;
    }

    // Entry: first buy or DCA dip
    if (nOpen < maxPositions) {
      bool shouldBuy = false;
      if (_lastBuyPrice == null) {
        shouldBuy = true;
      } else {
        final dropThreshold = _lastBuyPrice! *
            (1 - (profitFactorPct + marginDropPct) / 100);
        if (price <= dropThreshold) shouldBuy = true;
      }
      if (shouldBuy) {
        final actualUsdt = math.min(portfolio.cash, quoteOrderQty);
        final qty = price > 0 ? actualUsdt / price : 0.0;
        if (qty > 0) {
          orders.add(OrderRequest.openLong(botId: id, qty: qty));
          _lastBuyPrice = price;
          _sellTarget = price * (1 + profitFactorPct / 100);
        }
      }
    }

    return orders;
  }

  @override
  BotState? state() => BotState(
        phase: _lastBuyPrice == null ? 'idle' : 'live',
        decision: _sellTarget != null ? 'awaiting_tp' : 'scanning',
        indicators: {
          'last_buy': ?_lastBuyPrice,
          'sell_target': ?_sellTarget,
        },
      );
}
