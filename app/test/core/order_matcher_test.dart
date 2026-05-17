import 'package:flutter_test/flutter_test.dart';
import 'package:cvz_backtester/core/order_matcher.dart';
import 'package:cvz_backtester/core/models/order.dart';

void main() {
  PendingOrder po({
    required OrderSide side,
    required OrderType type,
    double? limitPrice,
    double? stopPrice,
    double? trailingPct,
    double? trailingAnchor,
  }) =>
      PendingOrder(
        id: 1,
        side: side,
        action: OrderAction.openLong,
        qty: 1.0,
        type: type,
        botId: 't',
        limitPrice: limitPrice,
        stopPrice: stopPrice,
        trailingPct: trailingPct,
        trailingAnchor: trailingAnchor,
      );

  group('OrderMatcher.limitTriggers', () {
    test('BUY LIMIT fills when low <= limit_price', () {
      final o = po(side: OrderSide.buy, type: OrderType.limit, limitPrice: 100);
      expect(OrderMatcher.limitTriggers(o, 105, 99), isTrue);
      expect(OrderMatcher.limitTriggers(o, 105, 101), isFalse);
    });

    test('SELL LIMIT fills when high >= limit_price', () {
      final o = po(side: OrderSide.sell, type: OrderType.limit, limitPrice: 100);
      expect(OrderMatcher.limitTriggers(o, 101, 95), isTrue);
      expect(OrderMatcher.limitTriggers(o, 99, 95), isFalse);
    });

    test('returns false when limit_price is null', () {
      final o = po(side: OrderSide.buy, type: OrderType.limit);
      expect(OrderMatcher.limitTriggers(o, 100, 99), isFalse);
    });
  });

  group('OrderMatcher.stopTriggers', () {
    test('BUY STOP triggers when high >= stop_price (breakout)', () {
      final o = po(side: OrderSide.buy, type: OrderType.stop, stopPrice: 100);
      expect(OrderMatcher.stopTriggers(o, 101, 95), isTrue);
      expect(OrderMatcher.stopTriggers(o, 99, 95), isFalse);
    });

    test('SELL STOP triggers when low <= stop_price (stop loss)', () {
      final o = po(side: OrderSide.sell, type: OrderType.stop, stopPrice: 100);
      expect(OrderMatcher.stopTriggers(o, 105, 99), isTrue);
      expect(OrderMatcher.stopTriggers(o, 105, 101), isFalse);
    });
  });

  group('OrderMatcher.updateTrailingAnchor', () {
    test('SELL trailing ratchets up on new high, not down', () {
      final o = po(
        side: OrderSide.sell,
        type: OrderType.trailingStop,
        trailingPct: 5.0,
        trailingAnchor: 100,
        stopPrice: 95,
      );
      // Bar with higher high → anchor up, stop tightens.
      OrderMatcher.updateTrailingAnchor(o, 110, 105);
      expect(o.trailingAnchor, 110);
      expect(o.stopPrice, closeTo(104.5, 0.001));

      // Bar with lower high → anchor unchanged (ratchet only).
      OrderMatcher.updateTrailingAnchor(o, 108, 100);
      expect(o.trailingAnchor, 110);
      expect(o.stopPrice, closeTo(104.5, 0.001));
    });

    test('BUY trailing ratchets down on new low, not up', () {
      final o = po(
        side: OrderSide.buy,
        type: OrderType.trailingStop,
        trailingPct: 5.0,
        trailingAnchor: 100,
        stopPrice: 105,
      );
      OrderMatcher.updateTrailingAnchor(o, 95, 90);
      expect(o.trailingAnchor, 90);
      expect(o.stopPrice, closeTo(94.5, 0.001));
    });

    test('no-op for non-trailing order types', () {
      final o = po(
        side: OrderSide.sell,
        type: OrderType.stop,
        stopPrice: 95,
        trailingPct: 5.0,
      );
      OrderMatcher.updateTrailingAnchor(o, 200, 100);
      expect(o.stopPrice, 95); // unchanged
    });
  });
}
