import '../core/models/candle.dart';
import 'indicator.dart';

/// Volume-Weighted Average Price: cumulative typical_price * vol / cumulative vol.
///
/// "Cumulative" here is session-wide. Use [reset] to start a new session
/// (e.g. day boundary for intraday charts).
class VWAP implements Indicator {
  double _numerator = 0.0;
  double _denominator = 0.0;
  double? _value;

  @override
  String get name => 'VWAP';

  @override
  int get warmupBars => 1;

  @override
  bool get isReady => _value != null;

  @override
  double? get value => _value;

  @override
  double? update(Candle c) {
    final tp = c.typicalPrice;
    _numerator += tp * c.volume;
    _denominator += c.volume;
    if (_denominator > 0) _value = _numerator / _denominator;
    return _value;
  }

  @override
  void reset() {
    _numerator = 0.0;
    _denominator = 0.0;
    _value = null;
  }
}
