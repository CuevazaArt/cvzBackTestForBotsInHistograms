import 'package:flutter_test/flutter_test.dart';
import 'package:cvz_backtester/data/data_quality.dart';
import 'package:cvz_backtester/core/models/candle.dart';

void main() {
  late DataQualityValidator validator;
  const barMs = 3600000; // 1h

  setUp(() => validator = DataQualityValidator());

  Candle makeCandle(int tsMs, {double close = 100.0}) => Candle(
        timestampMs: tsMs,
        open: close - 1,
        high: close + 2,
        low: close - 2,
        close: close,
        volume: 10.0,
      );

  test('clean data returns no violations', () {
    final candles = [
      makeCandle(0),
      makeCandle(barMs),
      makeCandle(barMs * 2),
    ];
    final report = validator.validate(candles, expectedBarMs: barMs);
    expect(report.isClean, isTrue);
    expect(report.missingBars, 0);
    expect(report.completenessPercect, 100.0);
  });

  test('detects duplicate timestamps', () {
    final candles = [makeCandle(0), makeCandle(0), makeCandle(barMs)];
    final report = validator.validate(candles, expectedBarMs: barMs);
    expect(
      report.violations.any((v) => v.type == ViolationType.duplicateTimestamp),
      isTrue,
    );
  });

  test('detects missing bars', () {
    final candles = [makeCandle(0), makeCandle(barMs * 3)]; // bar 1 and 2 missing
    final report = validator.validate(candles, expectedBarMs: barMs);
    expect(report.missingBars, 2);
    expect(
      report.violations.any((v) => v.type == ViolationType.missingBar),
      isTrue,
    );
  });

  test('detects invalid OHLC (high < low)', () {
    final bad = Candle(
      timestampMs: 0,
      open: 100,
      high: 90, // high < low — invalid
      low: 95,
      close: 100,
      volume: 10,
    );
    final report = validator.validate([bad], expectedBarMs: barMs);
    expect(
      report.violations.any((v) => v.type == ViolationType.invalidOhlc),
      isTrue,
    );
  });

  test('completeness is correct with missing bars', () {
    // 2 actual, 2 missing = 50% completeness
    final candles = [makeCandle(0), makeCandle(barMs * 3)];
    final report = validator.validate(candles, expectedBarMs: barMs);
    expect(report.completenessPercect, closeTo(50.0, 0.1));
  });

  test('empty candle list returns clean report', () {
    final report = validator.validate([], expectedBarMs: barMs);
    expect(report.isClean, isTrue);
    expect(report.totalCandles, 0);
  });

  test('detects non-monotonic timestamps', () {
    final candles = [makeCandle(barMs), makeCandle(0)]; // reversed order
    final report = validator.validate(candles, expectedBarMs: barMs);
    expect(
      report.violations.any((v) => v.type == ViolationType.nonMonotonicTimestamp),
      isTrue,
    );
  });
}
