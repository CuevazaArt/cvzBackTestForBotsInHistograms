import 'dart:math' as math;
import '../core/models/candle.dart';
import 'indicator.dart';

/// Bollinger Bands: middle = SMA(period), upper/lower = middle ± k * stdev.
///
/// Uses a sliding window with population stdev (matches pandas default rolling.std(ddof=0)
/// when ddof=0 is requested; common Bollinger convention is population stdev).
/// O(period) per update for the stdev because computing it via Welford on a
/// sliding window requires more state; for typical period <= 50 this is fine.
class Bollinger implements Indicator {
  final int period;
  final double k;
  final double Function(Candle) source;
  final List<double> _buffer;
  int _head = 0;
  int _count = 0;
  double _sum = 0.0;

  double? _middle;
  double? _upper;
  double? _lower;

  Bollinger({
    this.period = 20,
    this.k = 2.0,
    double Function(Candle)? source,
  })  : source = source ?? ((c) => c.close),
        _buffer = List.filled(period, 0.0) {
    if (period <= 1) throw ArgumentError('period must be > 1');
  }

  @override
  String get name => 'BB($period,$k)';

  @override
  int get warmupBars => period;

  @override
  bool get isReady => _middle != null;

  @override
  double? get value => _middle;

  double? get middle => _middle;
  double? get upper => _upper;
  double? get lower => _lower;

  /// Position of price inside the bands: 0 = at lower, 1 = at upper.
  double? get percentB {
    if (_upper == null || _lower == null || _upper == _lower) return null;
    final last = _buffer[(_head - 1 + period) % period];
    return (last - _lower!) / (_upper! - _lower!);
  }

  @override
  double? update(Candle c) {
    final price = source(c);
    if (_count < period) {
      _buffer[_head] = price;
      _sum += price;
      _count++;
    } else {
      _sum += price - _buffer[_head];
      _buffer[_head] = price;
    }
    _head = (_head + 1) % period;

    if (_count >= period) {
      _middle = _sum / period;
      double sqSum = 0.0;
      for (int i = 0; i < period; i++) {
        final d = _buffer[i] - _middle!;
        sqSum += d * d;
      }
      final std = math.sqrt(sqSum / period);
      _upper = _middle! + k * std;
      _lower = _middle! - k * std;
    }
    return _middle;
  }

  @override
  void reset() {
    _head = 0;
    _count = 0;
    _sum = 0.0;
    _middle = null;
    _upper = null;
    _lower = null;
    for (int i = 0; i < period; i++) {
      _buffer[i] = 0.0;
    }
  }
}
