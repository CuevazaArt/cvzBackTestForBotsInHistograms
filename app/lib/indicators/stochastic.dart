import '../core/models/candle.dart';
import 'indicator.dart';

/// Stochastic Oscillator:
///   K = 100 * (close - low_min(period)) / (high_max(period) - low_min(period))
///   D = SMA(K, smoothD)
class Stochastic implements Indicator {
  final int period;
  final int smoothD;
  final List<double> _highBuffer;
  final List<double> _lowBuffer;
  final List<double> _closeBuffer;
  final List<double> _kBuffer;
  int _head = 0;
  int _count = 0;
  int _kHead = 0;
  int _kCount = 0;
  double _kSum = 0.0;
  double? _k;
  double? _d;

  Stochastic({this.period = 14, this.smoothD = 3})
      : _highBuffer = List.filled(period, 0.0),
        _lowBuffer = List.filled(period, 0.0),
        _closeBuffer = List.filled(period, 0.0),
        _kBuffer = List.filled(smoothD, 0.0) {
    if (period <= 0 || smoothD <= 0) {
      throw ArgumentError('period and smoothD must be > 0');
    }
  }

  @override
  String get name => 'Stoch($period,$smoothD)';

  @override
  int get warmupBars => period + smoothD - 1;

  @override
  bool get isReady => _d != null;

  /// Returns %K (use [d] for %D).
  @override
  double? get value => _k;

  double? get k => _k;
  double? get d => _d;

  @override
  double? update(Candle c) {
    if (_count < period) {
      _highBuffer[_head] = c.high;
      _lowBuffer[_head] = c.low;
      _closeBuffer[_head] = c.close;
      _count++;
    } else {
      _highBuffer[_head] = c.high;
      _lowBuffer[_head] = c.low;
      _closeBuffer[_head] = c.close;
    }
    _head = (_head + 1) % period;

    if (_count >= period) {
      double maxH = _highBuffer[0], minL = _lowBuffer[0];
      for (int i = 1; i < period; i++) {
        if (_highBuffer[i] > maxH) maxH = _highBuffer[i];
        if (_lowBuffer[i] < minL) minL = _lowBuffer[i];
      }
      final range = maxH - minL;
      _k = range == 0 ? 50.0 : 100.0 * (c.close - minL) / range;

      if (_kCount < smoothD) {
        _kBuffer[_kHead] = _k!;
        _kSum += _k!;
        _kCount++;
      } else {
        _kSum += _k! - _kBuffer[_kHead];
        _kBuffer[_kHead] = _k!;
      }
      _kHead = (_kHead + 1) % smoothD;
      if (_kCount >= smoothD) _d = _kSum / smoothD;
    }
    return _k;
  }

  @override
  void reset() {
    _head = 0;
    _count = 0;
    _kHead = 0;
    _kCount = 0;
    _kSum = 0;
    _k = null;
    _d = null;
    for (int i = 0; i < period; i++) {
      _highBuffer[i] = 0;
      _lowBuffer[i] = 0;
      _closeBuffer[i] = 0;
    }
    for (int i = 0; i < smoothD; i++) {
      _kBuffer[i] = 0;
    }
  }
}
