import 'models/order.dart';

/// Intra-bar trigger logic for pending orders.
///
/// Convention (industry-standard OHLC approximation):
///   - BUY  LIMIT fills if `low <= limit_price`
///   - SELL LIMIT fills if `high >= limit_price`
///   - BUY  STOP triggers if `high >= stop_price` (breakout)
///   - SELL STOP triggers if `low <= stop_price`  (stop-loss)
///   - TRAILING anchor ratchets in the favorable direction only.
class OrderMatcher {
  /// True if a LIMIT order would fill given this bar's high/low.
  static bool limitTriggers(PendingOrder po, double high, double low) {
    if (po.limitPrice == null) return false;
    if (po.side == OrderSide.buy) return low <= po.limitPrice!;
    return high >= po.limitPrice!;
  }

  /// True if a STOP order would trigger given this bar's high/low.
  static bool stopTriggers(PendingOrder po, double high, double low) {
    if (po.stopPrice == null) return false;
    if (po.side == OrderSide.buy) return high >= po.stopPrice!;
    return low <= po.stopPrice!;
  }

  /// Mutates the trailing-stop's anchor in-place, only in the favorable
  /// direction. Idempotent if the price didn't move favorably.
  static void updateTrailingAnchor(PendingOrder po, double high, double low) {
    if (po.type != OrderType.trailingStop || po.trailingPct == null) return;
    if (po.side == OrderSide.sell) {
      // Protective long-exit: anchor = highest high seen.
      if (po.trailingAnchor == null || high > po.trailingAnchor!) {
        po.trailingAnchor = high;
        po.stopPrice = po.trailingAnchor! * (1 - po.trailingPct! / 100);
      }
    } else {
      // Protective short-exit: anchor = lowest low seen.
      if (po.trailingAnchor == null || low < po.trailingAnchor!) {
        po.trailingAnchor = low;
        po.stopPrice = po.trailingAnchor! * (1 + po.trailingPct! / 100);
      }
    }
  }
}
