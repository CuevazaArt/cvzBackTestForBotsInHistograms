import 'package:yaml/yaml.dart';
import '../../core/models/candle.dart';
import '../../core/models/order.dart';
import '../../core/models/portfolio.dart';
import '../../indicators/indicator.dart';
import '../../indicators/registry.dart';
import '../bot_base.dart';
import 'expression.dart';
import 'expression_parser.dart';

/// Declarative bot defined from a YAML spec.
///
/// Example YAML:
/// ```yaml
/// id: my_dsl
/// name: My DSL Bot
/// indicators:
///   fast: { type: ema, period: 12 }
///   slow: { type: ema, period: 26 }
///   rsi:  { type: rsi, period: 14 }
/// entry: "fast > slow AND rsi < 70"
/// exit:  "fast < slow OR rsi > 80"
/// risk:
///   stop_loss_pct: 5
///   take_profit_pct: 10
///   risk_per_trade_pct: 2
/// ```
class DSLBot extends BotBase {
  @override
  final String id;
  @override
  final String name;
  @override
  final Map<String, dynamic> params;

  final Map<String, Indicator> _indicators;
  final Expr _entryExpr;
  final Expr _exitExpr;
  final double _stopLossPct;
  final double _takeProfitPct;
  final double _trailingStopPct;
  final double _riskPerTradePct;

  bool _inPosition = false;

  DSLBot._({
    required this.id,
    required this.name,
    required this.params,
    required Map<String, Indicator> indicators,
    required Expr entry,
    required Expr exit,
    required double stopLossPct,
    required double takeProfitPct,
    required double trailingStopPct,
    required double riskPerTradePct,
  })  : _indicators = indicators,
        _entryExpr = entry,
        _exitExpr = exit,
        _stopLossPct = stopLossPct,
        _takeProfitPct = takeProfitPct,
        _trailingStopPct = trailingStopPct,
        _riskPerTradePct = riskPerTradePct;

  factory DSLBot.fromYaml(String yamlSource) {
    final doc = loadYaml(yamlSource);
    if (doc is! YamlMap) {
      throw ArgumentError('DSL root must be a map');
    }
    return DSLBot.fromMap(_yamlToMap(doc));
  }

  factory DSLBot.fromMap(Map<String, dynamic> spec) {
    final id = (spec['id'] as String?) ?? 'dsl_bot';
    final name = (spec['name'] as String?) ?? id;

    // Indicators
    final indSpec = spec['indicators'];
    if (indSpec is! Map) {
      throw ArgumentError('indicators block required');
    }
    final indicators = <String, Indicator>{};
    indSpec.forEach((k, v) {
      final p = Map<String, dynamic>.from(v as Map);
      final type = (p.remove('type') as String?) ?? 'ema';
      indicators[k as String] = IndicatorRegistry.create(type, p);
    });

    // Expressions
    final entry = ExpressionParser((spec['entry'] as String?) ?? 'false').parse();
    final exit = ExpressionParser((spec['exit'] as String?) ?? 'false').parse();

    // Risk block
    final risk = (spec['risk'] as Map?) ?? const {};
    final sl = (risk['stop_loss_pct'] as num?)?.toDouble() ?? 0.0;
    final tp = (risk['take_profit_pct'] as num?)?.toDouble() ?? 0.0;
    final ts = (risk['trailing_stop_pct'] as num?)?.toDouble() ?? 0.0;
    final r = (risk['risk_per_trade_pct'] as num?)?.toDouble() ?? 2.0;

    return DSLBot._(
      id: id,
      name: name,
      params: Map<String, dynamic>.from(spec),
      indicators: indicators,
      entry: entry,
      exit: exit,
      stopLossPct: sl,
      takeProfitPct: tp,
      trailingStopPct: ts,
      riskPerTradePct: r,
    );
  }

  static Map<String, dynamic> _yamlToMap(YamlMap m) {
    final result = <String, dynamic>{};
    m.forEach((k, v) {
      if (v is YamlMap) {
        result[k.toString()] = _yamlToMap(v);
      } else if (v is YamlList) {
        result[k.toString()] = v.map((e) => e).toList();
      } else {
        result[k.toString()] = v;
      }
    });
    return result;
  }

  Map<String, double?> _buildContext(Candle c) {
    final ctx = <String, double?>{
      'close': c.close,
      'open': c.open,
      'high': c.high,
      'low': c.low,
      'volume': c.volume,
    };
    for (final entry in _indicators.entries) {
      ctx[entry.key] = entry.value.value;
    }
    return ctx;
  }

  @override
  List<OrderRequest> onCandle(Candle candle, Portfolio portfolio) {
    // Update all indicators with this bar.
    for (final ind in _indicators.values) {
      ind.update(candle);
    }

    // Sync state if engine closed us via bracket.
    if (_inPosition && portfolio.positionsForBot(id).isEmpty) {
      _inPosition = false;
    }

    // Wait until all indicators are ready.
    if (_indicators.values.any((i) => !i.isReady)) return const [];

    final ctx = _buildContext(candle);

    // ENTRY: only when flat.
    if (!_inPosition) {
      final v = _entryExpr.eval(ctx);
      if (v is bool && v) {
        final qty = calcQty(portfolio.cash, candle.close, riskPct: _riskPerTradePct);
        if (qty <= 0) return const [];
        _inPosition = true;
        return [
          OrderRequest.openLong(
            botId: id,
            qty: qty,
            bracket: (_stopLossPct > 0 || _takeProfitPct > 0 || _trailingStopPct > 0)
                ? BracketSpec(
                    stopLossPct: _stopLossPct > 0 ? _stopLossPct : null,
                    takeProfitPct: _takeProfitPct > 0 ? _takeProfitPct : null,
                    trailingStopPct: _trailingStopPct > 0 ? _trailingStopPct : null,
                  )
                : null,
          ),
        ];
      }
    }

    // EXIT: only when in position.
    if (_inPosition) {
      final v = _exitExpr.eval(ctx);
      if (v is bool && v) {
        final qty = maxSellQty(portfolio);
        _inPosition = false;
        if (qty <= 0) return const [];
        return [OrderRequest.closeLong(botId: id, qty: qty)];
      }
    }

    return const [];
  }

  @override
  BotState? state() => BotState(
        phase: _indicators.values.every((i) => i.isReady) ? 'live' : 'warmup',
        decision: _inPosition ? 'long' : 'flat',
        indicators: {
          for (final e in _indicators.entries)
            if (e.value.value != null) e.key: e.value.value!,
        },
      );
}
