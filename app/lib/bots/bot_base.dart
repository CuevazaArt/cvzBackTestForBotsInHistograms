import '../core/models/candle.dart';
import '../core/models/order.dart';
import '../core/models/portfolio.dart';
import '../core/models/position.dart';

/// Spec for a single configurable bot parameter (used by UI).
class BotParamSpec {
  final String name;
  final String label;
  final BotParamType type;
  final num defaultValue;
  final num? min;
  final num? max;
  final num? step;

  const BotParamSpec({
    required this.name,
    required this.label,
    required this.type,
    required this.defaultValue,
    this.min,
    this.max,
    this.step,
  });
}

enum BotParamType { intParam, doubleParam, percent }

/// Diagnostic state emitted by a bot for the UI's "bot brain" panel.
class BotState {
  final String phase;
  final String decision;
  final Map<String, double> indicators;

  const BotState({
    required this.phase,
    required this.decision,
    this.indicators = const {},
  });
}

/// Abstract base for all trading strategies.
abstract class BotBase {
  String get id;
  String get name;
  Map<String, dynamic> get params;

  List<BotParamSpec> paramSpec() => const [];

  /// Called once before the run starts so the bot can precompute indicators
  /// over the full candle series if needed.
  void prepareIndicators(List<Candle> candles) {}

  /// Called per candle. Return zero or more OrderRequests to be processed
  /// by the engine in this bar.
  List<OrderRequest> onCandle(Candle candle, Portfolio portfolio);

  /// Diagnostic state for the current bar (optional, used by UI).
  BotState? state() => null;

  /// Default qty: fraction of cash by risk_pct (allocated to this bot).
  double calcQty(double cash, double price, {double riskPct = 100.0}) {
    if (price <= 0) return 0.0;
    return ((cash * riskPct / 100.0) / price);
  }

  /// Returns the total qty of positions owned by this bot (for sell-all).
  double maxSellQty(Portfolio portfolio) =>
      portfolio
          .positionsForBot(id)
          .where((p) => p.side == PositionSide.long)
          .fold(0.0, (s, p) => s + p.qty);

  /// Professional position sizing: qty such that hitting stop = riskPct of equity.
  double sizeByRisk({
    required double equity,
    required double entryPrice,
    required double stopPrice,
    required double riskPct,
  }) {
    final perUnitRisk = (entryPrice - stopPrice).abs();
    if (perUnitRisk <= 0) return 0.0;
    return (equity * riskPct / 100.0) / perUnitRisk;
  }
}
