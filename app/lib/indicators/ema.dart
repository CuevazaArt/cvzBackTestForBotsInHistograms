import '../core/models/candle.dart';
import 'indicator.dart';

/// Exponential Moving Average — matches pandas `ewm(span=n, adjust=False).mean()`.
///
/// Initialization: seed with SMA of the first [period] bars, then apply
/// the standard EMA recurrence `ema = k * price + (1-k) * ema_prev` with
/// `k = 2 / (period + 1)`.
class EMA implements Indicator {
  final int period;
  final double Function(Candle) source;

  late final double _k;
  double? _value;
  final List<double> _seed = [];

  EMA({required this.period, double Function(Candle)? source})
      : source = source ?? ((c) => c.close) {
    if (period <= 0) throw ArgumentError('period must be > 0');
    _k = 2.0 / (period + 1);
  }

  @override
  String get name => 'EMA($period)';

  @override
  int get warmupBars => period;

  @override
  bool get isReady => _value != null;

  @override
  double? get value => _value;

  @override
  double? update(Candle c) {
    final price = source(c);
    if (_value == null) {
      _seed.add(price);
      if (_seed.length >= period) {
        _value = _seed.reduce((a, b) => a + b) / _seed.length;
      }
    } else {
      _value = _k * price + (1 - _k) * _value!;
    }
    return _value;
  }

  @override
  void reset() {
    _value = null;
    _seed.clear();
  }
}
