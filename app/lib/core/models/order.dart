enum OrderType { market, limit, stop, stopLimit, trailingStop }

enum OrderSide { buy, sell }

enum OrderAction { openLong, closeLong, openShort, closeShort }

enum TriggerReason {
  marketEntry,
  limitFill,
  stopLoss,
  takeProfit,
  trailingStop,
  manual,
}

/// Bracket spec attached to an entry order — engine creates protective
/// pending children (STOP_LOSS, TAKE_PROFIT, TRAILING_STOP) on fill.
class BracketSpec {
  final double? stopLossPct;
  final double? stopLossPrice;
  final double? takeProfitPct;
  final double? takeProfitPrice;
  final double? trailingStopPct;

  const BracketSpec({
    this.stopLossPct,
    this.stopLossPrice,
    this.takeProfitPct,
    this.takeProfitPrice,
    this.trailingStopPct,
  });

  bool get isEmpty =>
      stopLossPct == null &&
      stopLossPrice == null &&
      takeProfitPct == null &&
      takeProfitPrice == null &&
      trailingStopPct == null;
}

/// Canonical order request emitted by a bot's onCandle.
class OrderRequest {
  final OrderSide side;
  final OrderAction action;
  final double qty;
  final OrderType type;
  final double? limitPrice;
  final double? stopPrice;
  final double? trailingPct;
  final BracketSpec? bracket;
  final String botId;

  const OrderRequest({
    required this.side,
    required this.action,
    required this.qty,
    required this.botId,
    this.type = OrderType.market,
    this.limitPrice,
    this.stopPrice,
    this.trailingPct,
    this.bracket,
  });

  /// Convenience: long-side market buy with optional bracket.
  factory OrderRequest.openLong({
    required String botId,
    required double qty,
    BracketSpec? bracket,
  }) =>
      OrderRequest(
        side: OrderSide.buy,
        action: OrderAction.openLong,
        qty: qty,
        botId: botId,
        bracket: bracket,
      );

  factory OrderRequest.closeLong({
    required String botId,
    required double qty,
  }) =>
      OrderRequest(
        side: OrderSide.sell,
        action: OrderAction.closeLong,
        qty: qty,
        botId: botId,
      );

  factory OrderRequest.openShort({
    required String botId,
    required double qty,
    BracketSpec? bracket,
  }) =>
      OrderRequest(
        side: OrderSide.sell,
        action: OrderAction.openShort,
        qty: qty,
        botId: botId,
        bracket: bracket,
      );

  factory OrderRequest.closeShort({
    required String botId,
    required double qty,
  }) =>
      OrderRequest(
        side: OrderSide.buy,
        action: OrderAction.closeShort,
        qty: qty,
        botId: botId,
      );
}

/// Order living in the pending queue until a price condition is met.
class PendingOrder {
  final int id;
  final OrderSide side;
  final OrderAction action;
  final double qty;
  final OrderType type;
  double? limitPrice;
  double? stopPrice;
  final double? trailingPct;
  double? trailingAnchor;
  final int? parentPositionId;
  final TriggerReason fillReason;
  final String botId;
  final BracketSpec? bracket;

  PendingOrder({
    required this.id,
    required this.side,
    required this.action,
    required this.qty,
    required this.type,
    required this.botId,
    this.limitPrice,
    this.stopPrice,
    this.trailingPct,
    this.trailingAnchor,
    this.parentPositionId,
    this.fillReason = TriggerReason.marketEntry,
    this.bracket,
  });
}
