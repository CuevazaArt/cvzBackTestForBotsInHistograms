import 'package:flutter_test/flutter_test.dart';
import 'package:cvz_backtester/data/database.dart';
import 'package:cvz_backtester/core/models/candle.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.inMemory();
  });

  tearDown(() async {
    await db.close();
  });

  group('CandlesDao', () {
    Candle makeCandle(int tsMs, double close) => Candle(
          timestampMs: tsMs,
          open: close - 10,
          high: close + 20,
          low: close - 20,
          close: close,
          volume: 100.0,
        );

    test('insertBatch stores candles and queryRange returns them', () async {
      final candles = [
        makeCandle(1_000_000, 100.0),
        makeCandle(2_000_000, 110.0),
        makeCandle(3_000_000, 105.0),
      ];

      await db.candles.insertBatch('BTCUSDT', '1h', candles);
      final result = await db.candles.queryRange('BTCUSDT', '1h');

      expect(result.length, 3);
      expect(result.first.close, 100.0);
      expect(result.last.close, 105.0);
    });

    test('insertBatch is idempotent (duplicate ignored)', () async {
      final candle = makeCandle(1_000_000, 100.0);
      await db.candles.insertBatch('BTCUSDT', '1h', [candle]);
      await db.candles.insertBatch('BTCUSDT', '1h', [candle]); // duplicate

      final result = await db.candles.queryRange('BTCUSDT', '1h');
      expect(result.length, 1);
    });

    test('lastTimestampMs returns the highest timestamp', () async {
      await db.candles.insertBatch('BTCUSDT', '1h', [
        makeCandle(1_000_000, 100.0),
        makeCandle(2_000_000, 110.0),
        makeCandle(3_000_000, 105.0),
      ]);

      final last = await db.candles.lastTimestampMs('BTCUSDT', '1h');
      expect(last, 3_000_000);
    });

    test('lastTimestampMs returns null for unknown symbol', () async {
      final last = await db.candles.lastTimestampMs('UNKNOWN', '1h');
      expect(last, isNull);
    });

    test('queryRange filters by fromMs and toMs', () async {
      await db.candles.insertBatch('BTCUSDT', '1h', [
        makeCandle(1_000_000, 100.0),
        makeCandle(2_000_000, 110.0),
        makeCandle(3_000_000, 105.0),
      ]);

      final result = await db.candles.queryRange(
        'BTCUSDT',
        '1h',
        fromMs: 1_500_000,
        toMs: 2_500_000,
      );
      expect(result.length, 1);
      expect(result.first.close, 110.0);
    });

    test('deleteSymbol removes only matching rows', () async {
      await db.candles.insertBatch('BTCUSDT', '1h', [makeCandle(1_000_000, 100.0)]);
      await db.candles.insertBatch('ETHUSDT', '1h', [makeCandle(1_000_000, 50.0)]);

      await db.candles.deleteSymbol('BTCUSDT', '1h');

      final btc = await db.candles.queryRange('BTCUSDT', '1h');
      final eth = await db.candles.queryRange('ETHUSDT', '1h');
      expect(btc, isEmpty);
      expect(eth.length, 1);
    });

    test('countCandles returns correct count', () async {
      await db.candles.insertBatch('BTCUSDT', '1h', [
        makeCandle(1_000_000, 100.0),
        makeCandle(2_000_000, 110.0),
      ]);

      final count = await db.candles.countCandles('BTCUSDT', '1h');
      expect(count, 2);
    });

    test('availableSymbols lists distinct symbol/timeframe pairs', () async {
      await db.candles.insertBatch('BTCUSDT', '1h', [makeCandle(1_000_000, 100.0)]);
      await db.candles.insertBatch('BTCUSDT', '4h', [makeCandle(1_000_000, 100.0)]);
      await db.candles.insertBatch('ETHUSDT', '1h', [makeCandle(1_000_000, 50.0)]);

      final available = await db.candles.availableSymbols();
      expect(available.keys.toSet(), {'BTCUSDT', 'ETHUSDT'});
      expect(available['BTCUSDT'], containsAll(['1h', '4h']));
    });
  });
}
