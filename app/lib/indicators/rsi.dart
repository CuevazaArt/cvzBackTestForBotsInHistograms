import '../core/models/candle.dart';
import 'indicator.dart';

/// Wilder's RSI: SMMA (smoothed MA) of gains/losses with alpha = 1/period.
///
/// First [period+1] bars: accumulate gain/loss SMA.
/// After that: SMMA recurrence
///   avg_gain = (avg_gain_prev * (period-1) + gain) / period
///   avg_loss = (avg_loss_prev * (period-1) + loss) / period
///   RS = avg_gain / avg_loss
///   RSI = 100 - 100 / (1 + RS)
class RSI implements Indicator {
  final int period;
  final double Function(Candle) source;

  double? _prevPrice;
  double _avgGain = 0.0;
  double _avgLoss = 0.0;
  int _seedCount = 0;
  double _seedGainSum = 0.0;
  double _seedLossSum = 0.0;
  double? _rsi;

  RSI({this.period = 14, double Function(Candle)? source})
      : source = source ?? ((c) => c.close) {
    if (period <= 0) throw ArgumentError('period must be > 0');
  }

  @override
  String get name => 'RSI($period)';

  @override
  int get warmupBars => period + 1;

  @override
  bool get isReady => _rsi != null;

  @override
  double? get value => _rsi;

  @override
  double? update(Candle c) {
    final price = source(c);
    if (_prevPrice == null) {
      _prevPrice = price;
      return null;
    }

    final delta = price - _prevPrice!;
    final gain = delta > 0 ? delta : 0.0;
    final loss = delta < 0 ? -delta : 0.0;
    _prevPrice = price;

    if (_seedCount < period) {
      _seedGainSum += gain;
      _seedLossSum += loss;
      _seedCount++;
      if (_seedCount == period) {
        _avgGain = _seedGainSum / period;
        _avgLoss = _seedLossSum / period;
        _rsi = _computeRsi();
      }
    } else {
      _avgGain = (_avgGain * (period - 1) + gain) / period;
      _avgLoss = (_avgLoss * (period - 1) + loss) / period;
      _rsi = _computeRsi();
    }
    return _rsi;
  }

  double _computeRsi() {
    if (_avgLoss == 0) return 100.0;
    final rs = _avgGain / _avgLoss;
    return 100.0 - 100.0 / (1 + rs);
  }

  @override
  void reset() {
    _prevPrice = null;
    _avgGain = 0;
    _avgLoss = 0;
    _seedCount = 0;
    _seedGainSum = 0;
    _seedLossSum = 0;
    _rsi = null;
  }
}
