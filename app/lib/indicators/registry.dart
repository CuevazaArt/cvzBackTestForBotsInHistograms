import 'indicator.dart';
import 'ema.dart';
import 'sma.dart';
import 'rsi.dart';
import 'macd.dart';
import 'bollinger.dart';
import 'stochastic.dart';
import 'vwap.dart';

/// Factory function: builds an indicator from a params map.
typedef IndicatorFactory = Indicator Function(Map<String, dynamic> params);

/// Centralized name → factory lookup. Lets bots and the DSL spawn indicators
/// by string without hard-coding constructors.
class IndicatorRegistry {
  static final Map<String, IndicatorFactory> _registry = {
    'ema': (p) => EMA(period: (p['period'] as num).toInt()),
    'sma': (p) => SMA(period: (p['period'] as num).toInt()),
    'rsi': (p) => RSI(period: (p['period'] as num?)?.toInt() ?? 14),
    'macd': (p) => MACD(
          fastPeriod: (p['fast'] as num?)?.toInt() ?? 12,
          slowPeriod: (p['slow'] as num?)?.toInt() ?? 26,
          signalPeriod: (p['signal'] as num?)?.toInt() ?? 9,
        ),
    'bb': (p) => Bollinger(
          period: (p['period'] as num?)?.toInt() ?? 20,
          k: (p['k'] as num?)?.toDouble() ?? 2.0,
        ),
    'stoch': (p) => Stochastic(
          period: (p['period'] as num?)?.toInt() ?? 14,
          smoothD: (p['smoothD'] as num?)?.toInt() ?? 3,
        ),
    'vwap': (_) => VWAP(),
  };

  static Indicator create(String name, [Map<String, dynamic>? params]) {
    final factory = _registry[name.toLowerCase()];
    if (factory == null) {
      throw ArgumentError('Unknown indicator: $name');
    }
    return factory(params ?? const {});
  }

  static List<String> get available => _registry.keys.toList();

  static void register(String name, IndicatorFactory factory) {
    _registry[name.toLowerCase()] = factory;
  }
}
