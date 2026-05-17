import '../core/models/candle.dart';
import 'indicator.dart';

/// Simple Moving Average over a ring buffer of the last [period] prices.
/// Maintains a running sum, O(1) per update.
class SMA implements Indicator {
  final int period;
  final double Function(Candle) source;
  final List<double> _buffer;
  int _head = 0;
  int _count = 0;
  double _sum = 0.0;

  SMA({required this.period, double Function(Candle)? source})
      : source = source ?? ((c) => c.close),
        _buffer = List.filled(period, 0.0) {
    if (period <= 0) throw ArgumentError('period must be > 0');
  }

  @override
  String get name => 'SMA($period)';

  @override
  int get warmupBars => period;

  @override
  bool get isReady => _count >= period;

  @override
  double? get value => isReady ? _sum / period : null;

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
    return value;
  }

  @override
  void reset() {
    _head = 0;
    _count = 0;
    _sum = 0.0;
    for (int i = 0; i < period; i++) {
      _buffer[i] = 0.0;
    }
  }
}
