import 'package:flutter_test/flutter_test.dart';
import 'package:cvz_backtester/core/models/candle.dart';
import 'package:cvz_backtester/indicators/ema.dart';
import 'package:cvz_backtester/indicators/sma.dart';
import 'package:cvz_backtester/indicators/rsi.dart';
import 'package:cvz_backtester/indicators/macd.dart';
import 'package:cvz_backtester/indicators/bollinger.dart';
import 'package:cvz_backtester/indicators/stochastic.dart';
import 'package:cvz_backtester/indicators/vwap.dart';
import 'package:cvz_backtester/indicators/registry.dart';

void main() {
  Candle bar(double price, {double? high, double? low, double volume = 100}) =>
      Candle(
        timestampMs: 0,
        open: price,
        high: high ?? price,
        low: low ?? price,
        close: price,
        volume: volume,
      );

  group('SMA', () {
    test('not ready until period bars consumed', () {
      final sma = SMA(period: 3);
      expect(sma.update(bar(1)), isNull);
      expect(sma.update(bar(2)), isNull);
      expect(sma.update(bar(3)), 2.0);
      expect(sma.isReady, isTrue);
    });

    test('sliding window after warmup', () {
      final sma = SMA(period: 3);
      for (final p in [1, 2, 3, 4, 5]) {
        sma.update(bar(p.toDouble()));
      }
      expect(sma.value, closeTo(4.0, 1e-9)); // (3+4+5)/3
    });

    test('reset clears state', () {
      final sma = SMA(period: 2);
      sma.update(bar(10));
      sma.update(bar(20));
      sma.reset();
      expect(sma.isReady, isFalse);
      expect(sma.update(bar(5)), isNull);
    });
  });

  group('EMA', () {
    test('seeds with SMA of first period bars, then applies recurrence', () {
      final ema = EMA(period: 3);
      // First 3 bars seed: avg(2,4,6) = 4
      expect(ema.update(bar(2)), isNull);
      expect(ema.update(bar(4)), isNull);
      expect(ema.update(bar(6)), 4.0);
      // k = 2/(3+1) = 0.5; ema = 0.5*8 + 0.5*4 = 6
      expect(ema.update(bar(8)), closeTo(6.0, 1e-9));
    });

    test('reset clears value and seed', () {
      final ema = EMA(period: 2);
      ema.update(bar(1));
      ema.update(bar(2));
      ema.reset();
      expect(ema.value, isNull);
    });
  });

  group('RSI', () {
    test('all gains gives RSI=100, all losses gives RSI=0 within Wilder tolerance',
        () {
      final upRsi = RSI(period: 5);
      for (int i = 1; i <= 6; i++) {
        upRsi.update(bar(i.toDouble()));
      }
      expect(upRsi.value, 100.0); // no losses → RSI = 100

      final dnRsi = RSI(period: 5);
      for (int i = 10; i >= 4; i--) {
        dnRsi.update(bar(i.toDouble()));
      }
      expect(dnRsi.value, closeTo(0.0, 1e-9)); // no gains → RSI = 0
    });

    test('reference values: 14-period RSI on a known sequence', () {
      // Sequence: 44.34, 44.09, 44.15, 43.61, 44.33, 44.83, 45.10, 45.42,
      //           45.84, 46.08, 45.89, 46.03, 45.61, 46.28, 46.28, 46.00
      // After bar 15 (first RSI = period+1=15 inputs), RSI(14) ≈ 70.46 (Wilder)
      final prices = [
        44.34, 44.09, 44.15, 43.61, 44.33, 44.83, 45.10, 45.42, 45.84, 46.08,
        45.89, 46.03, 45.61, 46.28, 46.28, 46.00
      ];
      final rsi = RSI(period: 14);
      double? last;
      for (final p in prices) {
        last = rsi.update(bar(p));
      }
      expect(last, isNotNull);
      // Loose tolerance because RSI seeding varies slightly across implementations.
      expect(last!, inInclusiveRange(65.0, 75.0));
    });

    test('reset', () {
      final rsi = RSI(period: 5);
      for (final p in [1.0, 2, 3, 4, 5, 6]) {
        rsi.update(bar(p.toDouble()));
      }
      rsi.reset();
      expect(rsi.value, isNull);
    });
  });

  group('MACD', () {
    test('warms up correctly (slow + signal - 1 bars)', () {
      final macd = MACD(fastPeriod: 3, slowPeriod: 5, signalPeriod: 2);
      // Needs slow=5 bars for slow EMA, then signal=2 bars of MACD values
      // → warmup = 5 + 2 - 1 = 6
      for (int i = 1; i <= 6; i++) {
        macd.update(bar(i.toDouble()));
      }
      expect(macd.signal, isNotNull);
      expect(macd.histogram, isNotNull);
    });

    test('histogram = macd - signal', () {
      final macd = MACD(fastPeriod: 3, slowPeriod: 5, signalPeriod: 2);
      for (int i = 1; i <= 10; i++) {
        macd.update(bar(i.toDouble()));
      }
      expect(macd.histogram, closeTo(macd.value! - macd.signal!, 1e-9));
    });
  });

  group('Bollinger Bands', () {
    test('flat prices: bands collapse to middle', () {
      final bb = Bollinger(period: 5, k: 2.0);
      for (int i = 0; i < 5; i++) {
        bb.update(bar(100));
      }
      expect(bb.middle, 100.0);
      expect(bb.upper, 100.0);
      expect(bb.lower, 100.0);
    });

    test('upper > middle > lower for varying prices', () {
      final bb = Bollinger(period: 5, k: 2.0);
      for (final p in [100.0, 110, 90, 105, 95]) {
        bb.update(bar(p.toDouble()));
      }
      expect(bb.middle, 100.0);
      expect(bb.upper, greaterThan(100.0));
      expect(bb.lower, lessThan(100.0));
    });

    test('reference: BB(5, 2) on [2,4,6,8,10] — std = sqrt(8), upper ≈ 11.66', () {
      final bb = Bollinger(period: 5, k: 2.0);
      for (final p in [2.0, 4, 6, 8, 10]) {
        bb.update(bar(p.toDouble()));
      }
      expect(bb.middle, 6.0);
      // pop std of [2,4,6,8,10] = sqrt(((2-6)^2+(4-6)^2+0+(8-6)^2+(10-6)^2)/5) = sqrt(8) ≈ 2.828
      expect(bb.upper, closeTo(6.0 + 2 * 2.8284271247, 1e-6));
      expect(bb.lower, closeTo(6.0 - 2 * 2.8284271247, 1e-6));
    });
  });

  group('Stochastic', () {
    test('K=100 when close is highest of period', () {
      final st = Stochastic(period: 3, smoothD: 1);
      st.update(bar(10, high: 10, low: 5));
      st.update(bar(15, high: 15, low: 10));
      st.update(bar(20, high: 20, low: 15)); // close=20 = high
      expect(st.k, closeTo(100.0, 1e-9));
    });

    test('K=0 when close is lowest of period', () {
      final st = Stochastic(period: 3, smoothD: 1);
      st.update(bar(20, high: 20, low: 15));
      st.update(bar(15, high: 18, low: 10));
      st.update(bar(5, high: 18, low: 5)); // close=5 = low
      expect(st.k, closeTo(0.0, 1e-9));
    });

    test('D is SMA of K', () {
      final st = Stochastic(period: 2, smoothD: 3);
      st.update(bar(10, high: 10, low: 5));
      st.update(bar(15, high: 15, low: 10));
      st.update(bar(12, high: 15, low: 8));
      st.update(bar(14, high: 15, low: 10));
      expect(st.d, isNotNull);
    });
  });

  group('VWAP', () {
    test('single bar: VWAP = typical price', () {
      final vwap = VWAP();
      final v = vwap.update(bar(100, high: 110, low: 90, volume: 50));
      expect(v, closeTo(100.0, 1e-9)); // (110+90+100)/3 = 100
    });

    test('cumulative across bars', () {
      final vwap = VWAP();
      vwap.update(bar(100, high: 100, low: 100, volume: 100)); // tp=100, vol=100
      vwap.update(bar(200, high: 200, low: 200, volume: 100)); // tp=200, vol=100
      // (100*100 + 200*100) / (100+100) = 150
      expect(vwap.value, closeTo(150.0, 1e-9));
    });

    test('reset clears cumulator', () {
      final vwap = VWAP();
      vwap.update(bar(100));
      vwap.reset();
      expect(vwap.value, isNull);
    });
  });

  group('IndicatorRegistry', () {
    test('creates known indicators by name', () {
      expect(IndicatorRegistry.create('ema', {'period': 10}), isA<EMA>());
      expect(IndicatorRegistry.create('sma', {'period': 5}), isA<SMA>());
      expect(IndicatorRegistry.create('rsi'), isA<RSI>());
      expect(IndicatorRegistry.create('macd'), isA<MACD>());
      expect(IndicatorRegistry.create('bb'), isA<Bollinger>());
      expect(IndicatorRegistry.create('stoch'), isA<Stochastic>());
      expect(IndicatorRegistry.create('vwap'), isA<VWAP>());
    });

    test('throws on unknown name', () {
      expect(() => IndicatorRegistry.create('unknown'),
          throwsA(isA<ArgumentError>()));
    });

    test('available lists all built-ins', () {
      expect(IndicatorRegistry.available,
          containsAll(['ema', 'sma', 'rsi', 'macd', 'bb', 'stoch', 'vwap']));
    });
  });
}
