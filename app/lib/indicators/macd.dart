import '../core/models/candle.dart';
import 'indicator.dart';
import 'ema.dart';

/// MACD = EMA(fast) - EMA(slow); signal = EMA(signal) of MACD; hist = MACD - signal.
///
/// Default Gerald Appel parameters: (12, 26, 9).
class MACD implements Indicator {
  final int fastPeriod;
  final int slowPeriod;
  final int signalPeriod;
  final double Function(Candle) source;

  late final EMA _fastEma;
  late final EMA _slowEma;
  late final double _signalK;

  double? _macd;
  double? _signal;
  final List<double> _signalSeed = [];

  MACD({
    this.fastPeriod = 12,
    this.slowPeriod = 26,
    this.signalPeriod = 9,
    double Function(Candle)? source,
  }) : source = source ?? ((c) => c.close) {
    if (fastPeriod >= slowPeriod) {
      throw ArgumentError('fastPeriod must be < slowPeriod');
    }
    _fastEma = EMA(period: fastPeriod, source: source);
    _slowEma = EMA(period: slowPeriod, source: source);
    _signalK = 2.0 / (signalPeriod + 1);
  }

  @override
  String get name => 'MACD($fastPeriod,$slowPeriod,$signalPeriod)';

  /// Reliable once both EMAs are warm AND the signal line has [signalPeriod] samples.
  @override
  int get warmupBars => slowPeriod + signalPeriod - 1;

  @override
  bool get isReady => _signal != null;

  /// Returns MACD line; use [signal] / [histogram] for the other two outputs.
  @override
  double? get value => _macd;

  double? get signal => _signal;

  double? get histogram =>
      _macd != null && _signal != null ? _macd! - _signal! : null;

  @override
  double? update(Candle c) {
    _fastEma.update(c);
    _slowEma.update(c);
    if (!_fastEma.isReady || !_slowEma.isReady) {
      _macd = null;
      return null;
    }
    _macd = _fastEma.value! - _slowEma.value!;

    if (_signal == null) {
      _signalSeed.add(_macd!);
      if (_signalSeed.length >= signalPeriod) {
        _signal = _signalSeed.reduce((a, b) => a + b) / _signalSeed.length;
      }
    } else {
      _signal = _signalK * _macd! + (1 - _signalK) * _signal!;
    }
    return _macd;
  }

  @override
  void reset() {
    _fastEma.reset();
    _slowEma.reset();
    _macd = null;
    _signal = null;
    _signalSeed.clear();
  }
}
