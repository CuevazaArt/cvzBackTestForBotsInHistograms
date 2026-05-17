import 'dart:convert';
import 'package:drift/drift.dart';
import '../database.dart';
import '../../core/models/backtest_result.dart';
import '../../core/models/trade.dart';
import '../../core/models/position.dart';
import '../../core/models/order.dart';

part 'results_dao.g.dart';

@DriftAccessor(tables: [ResultsTable])
class ResultsDao extends DatabaseAccessor<AppDatabase>
    with _$ResultsDaoMixin {
  ResultsDao(super.db);

  Future<void> saveResult(BacktestResult result) async {
    final metricsJson = jsonEncode({
      'return_pct': result.returnPct,
      'total_trades': result.totalTrades,
      'win_rate': result.winRate,
      'profit_factor': result.profitFactor,
      'total_fees': result.totalFees,
      'final_equity': result.finalEquity,
      'initial_cash': result.initialCash,
      'total_candles': result.totalCandles,
      'equity_curve': result.equityCurve,
    });
    final tradesJson = jsonEncode(
      result.trades.map((t) => t.toJson()).toList(),
    );
    await into(db.resultsTable).insertOnConflictUpdate(
      ResultsTableCompanion.insert(
        runId: result.runId,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        configJson: '{}',
        metricsJson: metricsJson,
        tradesJson: tradesJson,
      ),
    );
  }

  Future<List<ResultSummary>> listRecent({int limit = 50}) async {
    final rows = await (select(db.resultsTable)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
    return rows.map((r) {
      final metrics = jsonDecode(r.metricsJson) as Map<String, dynamic>;
      return ResultSummary(
        runId: r.runId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
        returnPct: (metrics['return_pct'] as num).toDouble(),
        totalTrades: metrics['total_trades'] as int,
        winRate: (metrics['win_rate'] as num).toDouble(),
      );
    }).toList();
  }

  Future<BacktestResult?> loadResult(String runId) async {
    final row = await (select(db.resultsTable)
          ..where((t) => t.runId.equals(runId)))
        .getSingleOrNull();
    if (row == null) return null;
    final metrics = jsonDecode(row.metricsJson) as Map<String, dynamic>;
    final tradesRaw = jsonDecode(row.tradesJson) as List<dynamic>;
    final trades = tradesRaw
        .map((j) => _tradeFromJson(j as Map<String, dynamic>))
        .toList();
    final equityCurveRaw = metrics['equity_curve'] as List<dynamic>;
    return BacktestResult(
      runId: row.runId,
      startTimestampMs: 0,
      endTimestampMs: 0,
      totalCandles: metrics['total_candles'] as int,
      initialCash: (metrics['initial_cash'] as num).toDouble(),
      finalEquity: (metrics['final_equity'] as num).toDouble(),
      trades: trades,
      equityCurve: equityCurveRaw.map((e) => (e as num).toDouble()).toList(),
      perBot: {},
    );
  }

  Future<int> deleteResult(String runId) async =>
      (delete(db.resultsTable)..where((t) => t.runId.equals(runId))).go();

  Trade _tradeFromJson(Map<String, dynamic> j) => Trade(
        id: j['id'] as int,
        botId: j['bot_id'] as String,
        side: PositionSide.values.byName(j['side'] as String),
        entryPrice: (j['entry_price'] as num).toDouble(),
        exitPrice: (j['exit_price'] as num).toDouble(),
        qty: (j['qty'] as num).toDouble(),
        entryTimestampMs: j['entry_time'] as int,
        exitTimestampMs: j['exit_time'] as int,
        pnl: (j['pnl'] as num).toDouble(),
        pnlPct: (j['pnl_pct'] as num).toDouble(),
        fees: (j['fees'] as num).toDouble(),
        mfe: (j['mfe'] as num).toDouble(),
        mae: (j['mae'] as num).toDouble(),
        exitReason: TriggerReason.values.byName(j['exit_reason'] as String),
      );
}

class ResultSummary {
  final String runId;
  final DateTime createdAt;
  final double returnPct;
  final int totalTrades;
  final double winRate;

  const ResultSummary({
    required this.runId,
    required this.createdAt,
    required this.returnPct,
    required this.totalTrades,
    required this.winRate,
  });
}
