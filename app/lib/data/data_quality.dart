import '../core/models/candle.dart';

enum ViolationType {
  duplicateTimestamp,
  nonMonotonicTimestamp,
  missingBar,
  invalidOhlc,
  outlierReturn,
}

class Violation {
  final ViolationType type;
  final int index;
  final String detail;

  const Violation(this.type, this.index, this.detail);

  @override
  String toString() => '[${type.name}] bar $index: $detail';
}

class QualityReport {
  final int totalCandles;
  final int missingBars;
  final double completenessPercect;
  final List<Violation> violations;

  const QualityReport({
    required this.totalCandles,
    required this.missingBars,
    required this.completenessPercect,
    required this.violations,
  });

  bool get isClean => violations.isEmpty;

  @override
  String toString() =>
      'QualityReport(candles=$totalCandles, missing=$missingBars, '
      'completeness=${completenessPercect.toStringAsFixed(1)}%, '
      'violations=${violations.length})';
}

class DataQualityValidator {
  static const double _outlierIqrFactor = 5.0;

  /// Validates OHLCV candles for a given timeframe (e.g. "1h").
  /// [expectedBarMs] is the milliseconds between consecutive bars.
  QualityReport validate(
    List<Candle> candles, {
    required int expectedBarMs,
  }) {
    if (candles.isEmpty) {
      return const QualityReport(
        totalCandles: 0,
        missingBars: 0,
        completenessPercect: 100.0,
        violations: [],
      );
    }

    final violations = <Violation>[];
    final seenTs = <int>{};
    int missingBars = 0;

    // Compute returns for outlier detection
    final returns = <double>[];
    for (int i = 1; i < candles.length; i++) {
      final prev = candles[i - 1].close;
      if (prev != 0) returns.add((candles[i].close - prev) / prev);
    }
    final (q1, q3) = _iqr(returns);
    final iqrBound = (q3 - q1) * _outlierIqrFactor;

    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];

      // Duplicate timestamps
      if (!seenTs.add(c.timestampMs)) {
        violations.add(Violation(
          ViolationType.duplicateTimestamp,
          i,
          'timestamp ${c.timestampMs} already seen',
        ));
        continue;
      }

      // Non-monotonic
      if (i > 0 && c.timestampMs <= candles[i - 1].timestampMs) {
        violations.add(Violation(
          ViolationType.nonMonotonicTimestamp,
          i,
          '${c.timestampMs} <= ${candles[i - 1].timestampMs}',
        ));
      }

      // Gap detection (missing bars)
      if (i > 0) {
        final expected = candles[i - 1].timestampMs + expectedBarMs;
        final actual = c.timestampMs;
        if (actual > expected) {
          final gap = (actual - expected) ~/ expectedBarMs;
          missingBars += gap;
          violations.add(Violation(
            ViolationType.missingBar,
            i,
            '$gap bar(s) missing between bar ${i - 1} and $i',
          ));
        }
      }

      // OHLC consistency
      if (c.high < c.low ||
          c.open > c.high ||
          c.open < c.low ||
          c.close > c.high ||
          c.close < c.low) {
        violations.add(Violation(
          ViolationType.invalidOhlc,
          i,
          'O=${c.open} H=${c.high} L=${c.low} C=${c.close}',
        ));
      }

      // Return outlier
      if (i > 0 && returns.isNotEmpty) {
        final ret = returns[i - 1];
        if (ret.abs() > iqrBound && iqrBound > 0) {
          violations.add(Violation(
            ViolationType.outlierReturn,
            i,
            'return ${(ret * 100).toStringAsFixed(2)}% exceeds ${(_outlierIqrFactor)}x IQR',
          ));
        }
      }
    }

    final expectedTotal = missingBars + candles.length;
    final completeness = expectedTotal > 0
        ? candles.length / expectedTotal * 100
        : 100.0;

    return QualityReport(
      totalCandles: candles.length,
      missingBars: missingBars,
      completenessPercect: completeness,
      violations: violations,
    );
  }

  /// Returns (Q1, Q3) of a list.
  (double, double) _iqr(List<double> data) {
    if (data.isEmpty) return (0.0, 0.0);
    final sorted = List<double>.from(data)..sort();
    final q1 = sorted[(sorted.length * 0.25).floor()];
    final q3 = sorted[(sorted.length * 0.75).floor()];
    return (q1, q3);
  }
}
