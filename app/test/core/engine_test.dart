import 'package:flutter_test/flutter_test.dart';
import 'package:cvz_backtester/core/engine.dart';
import 'package:cvz_backtester/core/config.dart';
import 'package:cvz_backtester/core/models/candle.dart';
import 'package:cvz_backtester/core/models/order.dart';
import 'package:cvz_backtester/core/models/portfolio.dart';
import 'package:cvz_backtester/core/models/position.dart';
import 'package:cvz_backtester/bots/bot_base.dart';

/// Deterministic test bot: emits a single signal at a predetermined bar.
class _ScriptedBot extends BotBase {
  @override
  final String id;
  @override
  final String name;
  @override
  final Map<String, dynamic> params = {};

  // barIndex -> OrderRequest — at each bar, emit if entry exists.
  final Map<int, OrderRequest> _signals;
  int _barCount = 0;

  _ScriptedBot(this.id, this._signals) : name = id;

  @override
  List<OrderRequest> onCandle(Candle c, Portfolio pf) {
    final i = _barCount++;
    final s = _signals[i];
    return s != null ? [s] : const [];
  }
}

void main() {
  Candle bar(int i, {required double o, required double h, required double l, required double c}) =>
      Candle(
        timestampMs: i * 60000,
        open: o,
        high: h,
        low: l,
        close: c,
        volume: 100,
      );

  group('BacktestEngine — basic lifecycle', () {
    test('empty bots returns empty result', () {
      final engine = BacktestEngine();
      final r = engine.run(
        bots: [],
        candles: [bar(0, o: 100, h: 110, l: 95, c: 105)],
      );
      expect(r.totalTrades, 0);
      expect(r.finalEquity, 10000);
    });

    test('empty candles returns empty result', () {
      final engine = BacktestEngine();
      final r = engine.run(bots: [_ScriptedBot('b1', {})], candles: []);
      expect(r.totalTrades, 0);
    });
  });

  group('BacktestEngine — MARKET buy + sell roundtrip', () {
    test('open long at bar 0 and close at bar 5 produces a winning trade', () {
      final candles = [
        for (int i = 0; i < 10; i++)
          bar(i, o: 100.0 + i, h: 105.0 + i, l: 95.0 + i, c: 100.0 + i),
      ];
      final bot = _ScriptedBot('emaT', {
        0: OrderRequest.openLong(botId: 'emaT', qty: 1.0),
        5: OrderRequest.closeLong(botId: 'emaT', qty: 1.0),
      });
      final engine = BacktestEngine(
        config: const BacktestConfig(
          initialCash: 1000,
          takerFeePct: 0.0,
          slippagePct: 0.0,
        ),
      );
      final r = engine.run(bots: [bot], candles: candles);

      expect(r.totalTrades, 1);
      final t = r.trades.first;
      expect(t.entryPrice, 100.0); // close of bar 0
      expect(t.exitPrice, 105.0); // close of bar 5
      expect(t.pnl, closeTo(5.0, 0.0001));
      expect(t.isWin, isTrue);
      expect(t.side, PositionSide.long);
    });

    test('fees + slippage reduce PnL', () {
      final candles = [
        bar(0, o: 100, h: 100, l: 100, c: 100),
        bar(1, o: 110, h: 110, l: 110, c: 110),
      ];
      final bot = _ScriptedBot('b', {
        0: OrderRequest.openLong(botId: 'b', qty: 1.0),
      });
      final engine = BacktestEngine(
        config: const BacktestConfig(
          initialCash: 200,
          takerFeePct: 0.1, // 0.1%
          slippagePct: 0.05, // 0.05%
        ),
      );
      final r = engine.run(bots: [bot], candles: candles);
      expect(r.totalTrades, 1);
      // pnl should be: (110*(1-0.05%) - 100*(1+0.05%)) - fees
      final t = r.trades.first;
      expect(t.pnl, lessThan(10.0));
      expect(t.fees, greaterThan(0));
    });

    test('insufficient cash blocks the open', () {
      final candles = [
        bar(0, o: 100, h: 100, l: 100, c: 100),
        bar(1, o: 110, h: 110, l: 110, c: 110),
      ];
      final bot = _ScriptedBot('b', {
        0: OrderRequest.openLong(botId: 'b', qty: 1000.0), // way too big
      });
      final engine = BacktestEngine(
        config: const BacktestConfig(initialCash: 100, takerFeePct: 0, slippagePct: 0),
      );
      final r = engine.run(bots: [bot], candles: candles);
      expect(r.totalTrades, 0);
    });
  });

  group('BacktestEngine — bracket orders', () {
    test('stopLossPct triggers exit when price drops below SL', () {
      final candles = [
        bar(0, o: 100, h: 100, l: 100, c: 100), // entry
        bar(1, o: 100, h: 100, l: 88, c: 90), // breaches SL at 95
        bar(2, o: 90, h: 92, l: 88, c: 91),
      ];
      final bot = _ScriptedBot('b', {
        0: OrderRequest.openLong(
          botId: 'b',
          qty: 1.0,
          bracket: const BracketSpec(stopLossPct: 5.0), // SL = 95
        ),
      });
      final engine = BacktestEngine(
        config: const BacktestConfig(
            initialCash: 200, takerFeePct: 0, slippagePct: 0),
      );
      final r = engine.run(bots: [bot], candles: candles);
      expect(r.totalTrades, 1);
      expect(r.trades.first.exitReason, TriggerReason.stopLoss);
      // Exit at SL price (95), not at bar close (90).
      expect(r.trades.first.exitPrice, closeTo(95.0, 0.001));
    });

    test('takeProfitPct triggers exit when price hits TP', () {
      final candles = [
        bar(0, o: 100, h: 100, l: 100, c: 100), // entry
        bar(1, o: 100, h: 115, l: 100, c: 110), // hits TP at 110
        bar(2, o: 110, h: 112, l: 108, c: 109),
      ];
      final bot = _ScriptedBot('b', {
        0: OrderRequest.openLong(
          botId: 'b',
          qty: 1.0,
          bracket: const BracketSpec(takeProfitPct: 10.0), // TP = 110
        ),
      });
      final engine = BacktestEngine(
        config: const BacktestConfig(
            initialCash: 200, takerFeePct: 0, slippagePct: 0),
      );
      final r = engine.run(bots: [bot], candles: candles);
      expect(r.totalTrades, 1);
      expect(r.trades.first.exitReason, TriggerReason.takeProfit);
      expect(r.trades.first.exitPrice, closeTo(110.0, 0.001));
    });

    test('trailing stop ratchets up then triggers exit on retracement', () {
      final candles = [
        bar(0, o: 100, h: 100, l: 100, c: 100), // entry; initial trailing stop = 90 (10% pct)
        bar(1, o: 100, h: 120, l: 100, c: 118), // anchor moves to 120, stop = 108
        bar(2, o: 118, h: 119, l: 107, c: 108), // hits stop at 108
      ];
      final bot = _ScriptedBot('b', {
        0: OrderRequest.openLong(
          botId: 'b',
          qty: 1.0,
          bracket: const BracketSpec(trailingStopPct: 10.0),
        ),
      });
      final engine = BacktestEngine(
        config: const BacktestConfig(
            initialCash: 200, takerFeePct: 0, slippagePct: 0),
      );
      final r = engine.run(bots: [bot], candles: candles);
      expect(r.totalTrades, 1);
      expect(r.trades.first.exitReason, TriggerReason.trailingStop);
      // Exit price should be around 108 (the ratcheted stop).
      expect(r.trades.first.exitPrice, closeTo(108.0, 0.5));
    });
  });

  group('BacktestEngine — equity curve', () {
    test('equity curve has one point per candle', () {
      final candles = [for (int i = 0; i < 20; i++) bar(i, o: 100, h: 100, l: 100, c: 100)];
      final r = BacktestEngine().run(
        bots: [_ScriptedBot('b', {})],
        candles: candles,
      );
      expect(r.equityCurve.length, 20);
      expect(r.equityCurve.first, closeTo(10000, 1));
    });
  });

  group('BacktestEngine — MFE/MAE on trades', () {
    test('captures highest favorable and lowest adverse excursion', () {
      final candles = [
        bar(0, o: 100, h: 100, l: 100, c: 100), // entry
        bar(1, o: 100, h: 110, l: 95, c: 105), // high makes MFE
        bar(2, o: 105, h: 108, l: 90, c: 92), // low makes MAE
        bar(3, o: 92, h: 95, l: 90, c: 95),
      ];
      final bot = _ScriptedBot('b', {
        0: OrderRequest.openLong(botId: 'b', qty: 1.0),
        3: OrderRequest.closeLong(botId: 'b', qty: 1.0),
      });
      final r = BacktestEngine(
        config: const BacktestConfig(
            initialCash: 200, takerFeePct: 0, slippagePct: 0),
      ).run(bots: [bot], candles: candles);

      // MFE/MAE are computed using close vs entry; engine updates on each bar.
      // close=105 → +5% MFE; close=92 → -8% MAE
      expect(r.trades.first.mfe, closeTo(5.0, 0.001));
      expect(r.trades.first.mae, closeTo(-8.0, 0.001));
    });
  });

  group('BacktestEngine — circuit breaker', () {
    test('halts new entries when drawdown exceeds threshold', () {
      // Force a 20% drawdown right at bar 1.
      final candles = [
        bar(0, o: 100, h: 100, l: 100, c: 100), // entry at 100
        bar(1, o: 100, h: 100, l: 60, c: 60), // -40% close → triggers halt
        bar(2, o: 60, h: 60, l: 60, c: 60),
      ];
      final bot = _ScriptedBot('b', {
        0: OrderRequest.openLong(botId: 'b', qty: 1.0),
        2: OrderRequest.openLong(botId: 'b', qty: 1.0), // blocked by halt
      });
      final r = BacktestEngine(
        config: const BacktestConfig(
          initialCash: 200,
          takerFeePct: 0,
          slippagePct: 0,
          maxDrawdownHaltPct: 20.0,
        ),
      ).run(bots: [bot], candles: candles);

      // Final force-close → 1 trade total (the second open was rejected).
      expect(r.totalTrades, 1);
    });
  });
}
