import 'bot_base.dart';
import 'ema_cross.dart';
import 'rsi_reversion.dart';
import 'dorothy_dca.dart';
import 'macd_cross.dart';
import 'bollinger_reversion.dart';
import 'elphaba_short.dart';
import 'donchian_breakout.dart';
import 'grid_trading.dart';

typedef BotFactory = BotBase Function(Map<String, dynamic> params);

/// Centralized catalog of available trading bots, shared by UI + tests + isolate.
class BotRegistry {
  static final Map<String, _BotEntry> _entries = {
    'ema_cross': _BotEntry(
      displayName: 'EMA Crossover',
      description: 'BUY on golden cross with bracket SL/TP. SELL on death cross.',
      factory: (p) => EMACross(
        fastPeriod: (p['fastPeriod'] as num?)?.toInt() ?? 12,
        slowPeriod: (p['slowPeriod'] as num?)?.toInt() ?? 26,
        profitFactorPct: (p['profitFactorPct'] as num?)?.toDouble() ?? 2.0,
        stopLossPct: (p['stopLossPct'] as num?)?.toDouble() ?? 5.0,
        trailingStopPct: (p['trailingStopPct'] as num?)?.toDouble() ?? 0.0,
        riskPerTradePct: (p['riskPerTradePct'] as num?)?.toDouble() ?? 2.0,
        useRiskSizing: (p['useRiskSizing'] as bool?) ?? false,
      ),
      defaultParams: const {
        'fastPeriod': 12,
        'slowPeriod': 26,
        'profitFactorPct': 2.0,
        'stopLossPct': 5.0,
      },
    ),
    'rsi_reversion': _BotEntry(
      displayName: 'RSI Reversion',
      description: 'Mean-reversion: BUY oversold, SELL overbought.',
      factory: (p) => RSIReversion(
        rsiPeriod: (p['rsiPeriod'] as num?)?.toInt() ?? 14,
        oversoldLevel: (p['oversoldLevel'] as num?)?.toDouble() ?? 30.0,
        overboughtLevel: (p['overboughtLevel'] as num?)?.toDouble() ?? 70.0,
        profitFactorPct: (p['profitFactorPct'] as num?)?.toDouble() ?? 3.0,
        stopLossPct: (p['stopLossPct'] as num?)?.toDouble() ?? 5.0,
        riskPerTradePct: (p['riskPerTradePct'] as num?)?.toDouble() ?? 2.0,
      ),
      defaultParams: const {
        'rsiPeriod': 14,
        'oversoldLevel': 30.0,
        'overboughtLevel': 70.0,
      },
    ),
    'dorothy_dca': _BotEntry(
      displayName: 'Dorothy DCA',
      description: 'Ladder strategy with DCA on dips and fixed profit target.',
      factory: (p) => DorothyDCA(
        profitFactorPct: (p['profitFactorPct'] as num?)?.toDouble() ?? 5.0,
        marginDropPct: (p['marginDropPct'] as num?)?.toDouble() ?? 0.4,
        maxPositions: (p['maxPositions'] as num?)?.toInt() ?? 3,
        stopLossPct: (p['stopLossPct'] as num?)?.toDouble() ?? 15.0,
        quoteOrderQty: (p['quoteOrderQty'] as num?)?.toDouble() ?? 7.0,
      ),
      defaultParams: const {
        'profitFactorPct': 5.0,
        'marginDropPct': 0.4,
        'maxPositions': 3,
      },
    ),
    'macd_cross': _BotEntry(
      displayName: 'MACD Crossover',
      description: 'BUY on MACD/signal bullish cross, SELL on bearish cross.',
      factory: (p) => MACDCross(
        fastPeriod: (p['fastPeriod'] as num?)?.toInt() ?? 12,
        slowPeriod: (p['slowPeriod'] as num?)?.toInt() ?? 26,
        signalPeriod: (p['signalPeriod'] as num?)?.toInt() ?? 9,
        profitFactorPct: (p['profitFactorPct'] as num?)?.toDouble() ?? 3.0,
        stopLossPct: (p['stopLossPct'] as num?)?.toDouble() ?? 5.0,
        riskPerTradePct: (p['riskPerTradePct'] as num?)?.toDouble() ?? 2.0,
      ),
      defaultParams: const {
        'fastPeriod': 12,
        'slowPeriod': 26,
        'signalPeriod': 9,
      },
    ),
    'bollinger_reversion': _BotEntry(
      displayName: 'Bollinger Reversion',
      description: 'Mean-reversion: BUY at lower band, SELL at upper band.',
      factory: (p) => BollingerReversion(
        period: (p['period'] as num?)?.toInt() ?? 20,
        kStd: (p['kStd'] as num?)?.toDouble() ?? 2.0,
        stopLossPct: (p['stopLossPct'] as num?)?.toDouble() ?? 5.0,
        riskPerTradePct: (p['riskPerTradePct'] as num?)?.toDouble() ?? 2.0,
      ),
      defaultParams: const {
        'period': 20,
        'kStd': 2.0,
      },
    ),
    'elphaba_short': _BotEntry(
      displayName: 'Elphaba Short',
      description: 'Short-selling: RSI overbought + price below EMA confirms downtrend.',
      factory: (p) => ElphabaShort(
        rsiPeriod: (p['rsiPeriod'] as num?)?.toInt() ?? 14,
        emaPeriod: (p['emaPeriod'] as num?)?.toInt() ?? 50,
        overboughtLevel: (p['overboughtLevel'] as num?)?.toDouble() ?? 70.0,
        oversoldLevel: (p['oversoldLevel'] as num?)?.toDouble() ?? 30.0,
        profitFactorPct: (p['profitFactorPct'] as num?)?.toDouble() ?? 3.0,
        stopLossPct: (p['stopLossPct'] as num?)?.toDouble() ?? 5.0,
        riskPerTradePct: (p['riskPerTradePct'] as num?)?.toDouble() ?? 2.0,
      ),
      defaultParams: const {
        'rsiPeriod': 14,
        'emaPeriod': 50,
      },
    ),
    'donchian_breakout': _BotEntry(
      displayName: 'Donchian Breakout',
      description: 'Turtle-trading: BUY on N-bar high breakout, SELL on M-bar low break.',
      factory: (p) => DonchianBreakout(
        entryPeriod: (p['entryPeriod'] as num?)?.toInt() ?? 20,
        exitPeriod: (p['exitPeriod'] as num?)?.toInt() ?? 10,
        stopLossPct: (p['stopLossPct'] as num?)?.toDouble() ?? 5.0,
        riskPerTradePct: (p['riskPerTradePct'] as num?)?.toDouble() ?? 2.0,
      ),
      defaultParams: const {
        'entryPeriod': 20,
        'exitPeriod': 10,
      },
    ),
    'grid_trading': _BotEntry(
      displayName: 'Grid Trading',
      description: 'Grid of buy/sell levels for sideways markets.',
      factory: (p) => GridTrading(
        gridSpacingPct: (p['gridSpacingPct'] as num?)?.toDouble() ?? 1.0,
        gridLevels: (p['gridLevels'] as num?)?.toInt() ?? 5,
        quotePerGrid: (p['quotePerGrid'] as num?)?.toDouble() ?? 100.0,
        stopLossPct: (p['stopLossPct'] as num?)?.toDouble() ?? 10.0,
      ),
      defaultParams: const {
        'gridSpacingPct': 1.0,
        'gridLevels': 5,
        'quotePerGrid': 100.0,
      },
    ),
  };

  static List<String> get names => _entries.keys.toList();

  static BotInfo info(String name) {
    final e = _entries[name];
    if (e == null) throw ArgumentError('Unknown bot: $name');
    return BotInfo(
      id: name,
      displayName: e.displayName,
      description: e.description,
      defaultParams: e.defaultParams,
    );
  }

  static List<BotInfo> get all =>
      _entries.keys.map((n) => info(n)).toList();

  static BotBase create(String name, [Map<String, dynamic>? params]) {
    final e = _entries[name];
    if (e == null) throw ArgumentError('Unknown bot: $name');
    return e.factory(params ?? const {});
  }

  /// Register a new bot at runtime (used by tests + extensions).
  static void register({
    required String name,
    required String displayName,
    required String description,
    required BotFactory factory,
    required Map<String, dynamic> defaultParams,
  }) {
    _entries[name] = _BotEntry(
      displayName: displayName,
      description: description,
      factory: factory,
      defaultParams: defaultParams,
    );
  }
}

class _BotEntry {
  final String displayName;
  final String description;
  final BotFactory factory;
  final Map<String, dynamic> defaultParams;

  const _BotEntry({
    required this.displayName,
    required this.description,
    required this.factory,
    required this.defaultParams,
  });
}

class BotInfo {
  final String id;
  final String displayName;
  final String description;
  final Map<String, dynamic> defaultParams;

  const BotInfo({
    required this.id,
    required this.displayName,
    required this.description,
    required this.defaultParams,
  });
}
