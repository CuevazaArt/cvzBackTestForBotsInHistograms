import 'models/order.dart';
import 'models/position.dart';

/// Generates protective pending orders (SL/TP/trailing) for an entry that
/// just filled. The engine cancels these automatically when the parent
/// position closes.
class BracketManager {
  /// Returns a list of PendingOrder children for [position] using [spec].
  /// [nextId] is a callable returning monotonically increasing IDs.
  static List<PendingOrder> createChildren({
    required Position position,
    required BracketSpec spec,
    required int Function() nextId,
  }) {
    final children = <PendingOrder>[];
    final isLong = position.side == PositionSide.long;
    final exitSide = isLong ? OrderSide.sell : OrderSide.buy;
    final exitAction =
        isLong ? OrderAction.closeLong : OrderAction.closeShort;

    // STOP_LOSS
    final slPrice = _resolveStopLoss(spec, position);
    if (slPrice != null) {
      children.add(PendingOrder(
        id: nextId(),
        side: exitSide,
        action: exitAction,
        qty: position.qty,
        type: OrderType.stop,
        stopPrice: slPrice,
        parentPositionId: position.id,
        fillReason: TriggerReason.stopLoss,
        botId: position.botId,
      ));
    }

    // TAKE_PROFIT
    final tpPrice = _resolveTakeProfit(spec, position);
    if (tpPrice != null) {
      children.add(PendingOrder(
        id: nextId(),
        side: exitSide,
        action: exitAction,
        qty: position.qty,
        type: OrderType.limit,
        limitPrice: tpPrice,
        parentPositionId: position.id,
        fillReason: TriggerReason.takeProfit,
        botId: position.botId,
      ));
    }

    // TRAILING_STOP — initial anchor = entry, will ratchet on each bar.
    if (spec.trailingStopPct != null && spec.trailingStopPct! > 0) {
      final initialStop = isLong
          ? position.entryPrice * (1 - spec.trailingStopPct! / 100)
          : position.entryPrice * (1 + spec.trailingStopPct! / 100);
      children.add(PendingOrder(
        id: nextId(),
        side: exitSide,
        action: exitAction,
        qty: position.qty,
        type: OrderType.trailingStop,
        stopPrice: initialStop,
        trailingPct: spec.trailingStopPct,
        trailingAnchor: position.entryPrice,
        parentPositionId: position.id,
        fillReason: TriggerReason.trailingStop,
        botId: position.botId,
      ));
    }

    return children;
  }

  static double? _resolveStopLoss(BracketSpec spec, Position pos) {
    if (spec.stopLossPrice != null && spec.stopLossPrice! > 0) {
      return spec.stopLossPrice;
    }
    if (spec.stopLossPct != null && spec.stopLossPct! > 0) {
      return pos.side == PositionSide.long
          ? pos.entryPrice * (1 - spec.stopLossPct! / 100)
          : pos.entryPrice * (1 + spec.stopLossPct! / 100);
    }
    return null;
  }

  static double? _resolveTakeProfit(BracketSpec spec, Position pos) {
    if (spec.takeProfitPrice != null && spec.takeProfitPrice! > 0) {
      return spec.takeProfitPrice;
    }
    if (spec.takeProfitPct != null && spec.takeProfitPct! > 0) {
      return pos.side == PositionSide.long
          ? pos.entryPrice * (1 + spec.takeProfitPct! / 100)
          : pos.entryPrice * (1 - spec.takeProfitPct! / 100);
    }
    return null;
  }
}
