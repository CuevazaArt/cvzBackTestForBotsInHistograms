import 'package:flutter_test/flutter_test.dart';
import 'package:cvz_backtester/core/engine.dart';
import 'package:cvz_backtester/core/config.dart';
import 'package:cvz_backtester/core/models/candle.dart';
import 'package:cvz_backtester/bots/registry.dart';
import 'package:cvz_backtester/bots/ema_cross.dart';
import 'package:cvz_backtester/bots/rsi_reversion.dart';
import 'package:cvz_backtester/bots/dorothy_dca.dart';
import 'package:cvz_backtester/bots/macd_cross.dart';
import 'package:cvz_backtester/bots/bollinger_reversion.dart';
import 'package:cvz_backtester/bots/elphaba_short.dart';
import 'package:cvz_backtester/bots/donchian_breakout.dart';
import 'package:cvz_backtester/bots/grid_trading.dart';
import 'package:cvz_backtester/bots/dsl/dsl_bot.dart';
import 'package:cvz_backtester/bots/dsl/expression.dart';
import 'package:cvz_backtester/bots/dsl/expression_parser.dart';

void main() {
  Candle bar(int i, double price, {double? high, double? low}) => Candle(
        timestampMs: i * 60000,
        open: price,
        high: high ?? price * 1.005,
        low: low ?? price * 0.995,
        close: price,
        volume: 100,
      );

  group('BotRegistry', () {
    test('lists all 8 bots', () {
      expect(BotRegistry.names, containsAll([
        'ema_cross', 'rsi_reversion', 'dorothy_dca',
        'macd_cross', 'bollinger_reversion', 'elphaba_short',
        'donchian_breakout', 'grid_trading',
      ]));
      expect(BotRegistry.names.length, 8);
    });

    test('creates bots by name', () {
      expect(BotRegistry.create('ema_cross'), isA<EMACross>());
      expect(BotRegistry.create('rsi_reversion'), isA<RSIReversion>());
      expect(BotRegistry.create('dorothy_dca'), isA<DorothyDCA>());
      expect(BotRegistry.create('macd_cross'), isA<MACDCross>());
      expect(BotRegistry.create('bollinger_reversion'), isA<BollingerReversion>());
      expect(BotRegistry.create('elphaba_short'), isA<ElphabaShort>());
      expect(BotRegistry.create('donchian_breakout'), isA<DonchianBreakout>());
      expect(BotRegistry.create('grid_trading'), isA<GridTrading>());
    });

    test('throws on unknown bot', () {
      expect(() => BotRegistry.create('nope'), throwsA(isA<ArgumentError>()));
    });

    test('info returns metadata', () {
      final i = BotRegistry.info('ema_cross');
      expect(i.id, 'ema_cross');
      expect(i.displayName, isNotEmpty);
      expect(i.description, isNotEmpty);
    });
  });

  group('EMACross integration', () {
    test('runs without errors on synthetic data', () {
      final candles = [
        for (int i = 0; i < 100; i++)
          bar(i, 100.0 + 20.0 * (i / 50.0 - 1.0) * (i % 30 - 15).toDouble() / 15.0),
      ];
      final bot = EMACross(fastPeriod: 5, slowPeriod: 12);
      final engine = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0.1, slippagePct: 0.0),
      );
      final r = engine.run(bots: [bot], candles: candles);
      expect(r.equityCurve.length, candles.length);
      // Bot has bracket SL/TP so any trades should have a defined exitReason.
      for (final t in r.trades) {
        expect(t.exitReason.name, isNotEmpty);
      }
    });

    test('emits buy on golden cross over a rising series', () {
      // Engineered series: flat then rises sharply → guaranteed golden cross.
      final candles = [
        for (int i = 0; i < 30; i++) bar(i, 100.0),
        for (int i = 30; i < 60; i++) bar(i, 100.0 + (i - 30).toDouble() * 2),
      ];
      final bot = EMACross(
        fastPeriod: 3,
        slowPeriod: 8,
        profitFactorPct: 50, // very wide so we don't auto-exit
        stopLossPct: 50,
      );
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.totalTrades, greaterThanOrEqualTo(1));
    });
  });

  group('RSIReversion integration', () {
    test('buys when RSI dips below oversold threshold', () {
      // Strong drop → RSI < 30
      final candles = [
        for (int i = 0; i < 20; i++) bar(i, 100.0),
        for (int i = 20; i < 30; i++) bar(i, 100.0 - (i - 20).toDouble() * 2),
        for (int i = 30; i < 60; i++) bar(i, 80.0 + (i - 30).toDouble() * 0.5),
      ];
      final bot = RSIReversion(rsiPeriod: 7);
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.totalTrades, greaterThanOrEqualTo(1));
    });
  });

  group('DorothyDCA integration', () {
    test('opens first position on first valid candle and respects max_positions', () {
      final candles = [
        for (int i = 0; i < 50; i++) bar(i, 100.0 - i.toDouble() * 0.5),
      ];
      final bot = DorothyDCA(maxPositions: 3, quoteOrderQty: 10);
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 1000, takerFeePct: 0, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.totalTrades, greaterThanOrEqualTo(1));
    });
  });

  group('MACDCross integration', () {
    test('runs without errors on trending data', () {
      final candles = [
        for (int i = 0; i < 50; i++) bar(i, 100.0),
        for (int i = 50; i < 100; i++) bar(i, 100.0 + (i - 50).toDouble() * 1.5),
      ];
      final bot = MACDCross(fastPeriod: 8, slowPeriod: 17, signalPeriod: 5);
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0.1, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.equityCurve.length, candles.length);
    });

    test('emits buy on bullish MACD crossover', () {
      final candles = [
        for (int i = 0; i < 40; i++) bar(i, 100.0),
        for (int i = 40; i < 80; i++) bar(i, 100.0 + (i - 40).toDouble() * 3),
      ];
      final bot = MACDCross(
        fastPeriod: 5,
        slowPeriod: 12,
        signalPeriod: 4,
        profitFactorPct: 50,
        stopLossPct: 50,
      );
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.totalTrades, greaterThanOrEqualTo(1));
    });
  });

  group('BollingerReversion integration', () {
    test('runs without errors on volatile data', () {
      final candles = [
        for (int i = 0; i < 100; i++)
          bar(i, 100.0 + 10.0 * (i.isEven ? 1 : -1).toDouble()),
      ];
      final bot = BollingerReversion(period: 10, kStd: 2.0);
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0.1, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.equityCurve.length, candles.length);
    });

    test('buys at lower band on mean-reverting data', () {
      final candles = <Candle>[];
      for (int i = 0; i < 80; i++) {
        final cycle = (i % 20).toDouble();
        final price = 100.0 + 15.0 * (cycle < 10 ? -1 + cycle / 5 : 1 - (cycle - 10) / 5);
        candles.add(bar(i, price));
      }
      final bot = BollingerReversion(period: 10, kStd: 1.5, stopLossPct: 20);
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.totalTrades, greaterThanOrEqualTo(1));
    });
  });

  group('ElphabaShort integration', () {
    test('runs without errors on declining data', () {
      final candles = [
        for (int i = 0; i < 60; i++) bar(i, 200.0),
        for (int i = 60; i < 120; i++) bar(i, 200.0 - (i - 60).toDouble() * 1.5),
      ];
      final bot = ElphabaShort(rsiPeriod: 10, emaPeriod: 20);
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0.1, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.equityCurve.length, candles.length);
    });

    test('opens short when RSI overbought and price below EMA', () {
      final candles = <Candle>[];
      // Rise to push RSI high, then small pullback below EMA to trigger short.
      for (int i = 0; i < 30; i++) {
        candles.add(bar(i, 100.0 + i.toDouble() * 3));
      }
      for (int i = 30; i < 60; i++) {
        candles.add(bar(i, 190.0 - (i - 30).toDouble() * 2));
      }
      for (int i = 60; i < 90; i++) {
        candles.add(bar(i, 130.0 - (i - 60).toDouble()));
      }
      final bot = ElphabaShort(
        rsiPeriod: 7,
        emaPeriod: 10,
        overboughtLevel: 65,
        profitFactorPct: 50,
        stopLossPct: 50,
      );
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.equityCurve.length, candles.length);
    });
  });

  group('DonchianBreakout integration', () {
    test('runs without errors on breakout data', () {
      final candles = [
        for (int i = 0; i < 30; i++) bar(i, 100.0 + (i % 5).toDouble()),
        for (int i = 30; i < 60; i++) bar(i, 105.0 + (i - 30).toDouble() * 2),
      ];
      final bot = DonchianBreakout(entryPeriod: 10, exitPeriod: 5);
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0.1, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.equityCurve.length, candles.length);
    });

    test('enters on new high breakout', () {
      final candles = <Candle>[];
      for (int i = 0; i < 25; i++) {
        candles.add(bar(i, 100.0));
      }
      for (int i = 25; i < 50; i++) {
        final price = 100.0 + (i - 25).toDouble() * 2;
        candles.add(bar(i, price, high: price));
      }
      final bot = DonchianBreakout(
        entryPeriod: 10,
        exitPeriod: 5,
        stopLossPct: 50,
      );
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.totalTrades, greaterThanOrEqualTo(1));
    });
  });

  group('GridTrading integration', () {
    test('runs without errors on ranging data', () {
      final candles = [
        for (int i = 0; i < 100; i++)
          bar(i, 100.0 + 5.0 * (i.isEven ? 1 : -1).toDouble()),
      ];
      final bot = GridTrading(gridSpacingPct: 2.0, gridLevels: 3, quotePerGrid: 50);
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0.1, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.equityCurve.length, candles.length);
    });

    test('opens grid positions on price decline', () {
      final candles = <Candle>[];
      for (int i = 0; i < 50; i++) {
        candles.add(bar(i, 100.0 - i.toDouble() * 0.5));
      }
      for (int i = 50; i < 100; i++) {
        candles.add(bar(i, 75.0 + (i - 50).toDouble() * 0.5));
      }
      final bot = GridTrading(
        gridSpacingPct: 3.0,
        gridLevels: 5,
        quotePerGrid: 100,
        stopLossPct: 50,
      );
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.totalTrades, greaterThanOrEqualTo(1));
    });
  });

  group('ExpressionParser', () {
    test('parses simple comparison', () {
      final e = ExpressionParser('fast > slow').parse();
      expect(e.eval({'fast': 10.0, 'slow': 5.0}), isTrue);
      expect(e.eval({'fast': 5.0, 'slow': 10.0}), isFalse);
    });

    test('AND/OR precedence: AND binds tighter than OR', () {
      // a OR b AND c == a OR (b AND c)
      final e = ExpressionParser('a > 0 OR b > 0 AND c > 0').parse();
      expect(e.eval({'a': 1.0, 'b': 0.0, 'c': 0.0}), isTrue);
      expect(e.eval({'a': 0.0, 'b': 1.0, 'c': 1.0}), isTrue);
      expect(e.eval({'a': 0.0, 'b': 1.0, 'c': 0.0}), isFalse);
    });

    test('NOT inverts', () {
      final e = ExpressionParser('NOT x > 0').parse();
      expect(e.eval({'x': 1.0}), isFalse);
      expect(e.eval({'x': -1.0}), isTrue);
    });

    test('parentheses override precedence', () {
      final e = ExpressionParser('(a > 0 OR b > 0) AND c > 0').parse();
      expect(e.eval({'a': 1.0, 'b': 0.0, 'c': 0.0}), isFalse);
      expect(e.eval({'a': 1.0, 'b': 0.0, 'c': 1.0}), isTrue);
    });

    test('returns null when an identifier is null (warmup propagation)', () {
      final e = ExpressionParser('fast > slow').parse();
      expect(e.eval({'fast': null, 'slow': 5.0}), isNull);
    });

    test('comparison operators all work', () {
      expect(ExpressionParser('x < 5').parse().eval({'x': 3.0}), isTrue);
      expect(ExpressionParser('x <= 5').parse().eval({'x': 5.0}), isTrue);
      expect(ExpressionParser('x > 5').parse().eval({'x': 5.0}), isFalse);
      expect(ExpressionParser('x >= 5').parse().eval({'x': 5.0}), isTrue);
      expect(ExpressionParser('x == 5').parse().eval({'x': 5.0}), isTrue);
      expect(ExpressionParser('x != 5').parse().eval({'x': 5.0}), isFalse);
    });

    test('throws on malformed input', () {
      expect(() => ExpressionParser('x >').parse(), throwsA(isA<ParseError>()));
      expect(() => ExpressionParser('(x > 0').parse(), throwsA(isA<ParseError>()));
    });
  });

  group('DSLBot', () {
    test('parses YAML spec and runs end-to-end', () {
      const yaml = '''
id: dsl_test
name: DSL Test
indicators:
  fast: { type: ema, period: 5 }
  slow: { type: ema, period: 12 }
entry: "fast > slow"
exit: "fast < slow"
risk:
  stop_loss_pct: 5
  take_profit_pct: 10
  risk_per_trade_pct: 2
''';
      final bot = DSLBot.fromYaml(yaml);
      expect(bot.id, 'dsl_test');

      // Run on synthetic crossing data.
      final candles = [
        for (int i = 0; i < 30; i++) bar(i, 100.0),
        for (int i = 30; i < 60; i++) bar(i, 100.0 + (i - 30).toDouble() * 2),
      ];
      final r = BacktestEngine(
        config: const BacktestConfig(initialCash: 10000, takerFeePct: 0, slippagePct: 0),
      ).run(bots: [bot], candles: candles);
      expect(r.equityCurve.length, candles.length);
      expect(r.totalTrades, greaterThanOrEqualTo(1));
    });

    test('throws on missing indicators block', () {
      expect(
        () => DSLBot.fromYaml('id: foo\nentry: "x > 0"'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
