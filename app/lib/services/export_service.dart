import 'dart:convert';
import '../core/models/backtest_result.dart';
import '../core/models/trade.dart';

/// Serializes a BacktestResult to CSV or JSON. Returns raw text — the caller
/// is responsible for writing to disk via path_provider / share APIs.
class ExportService {
  static String tradesToCsv(List<Trade> trades) {
    final buf = StringBuffer();
    buf.writeln(
        'id,bot_id,side,entry_price,exit_price,qty,entry_time,exit_time,pnl,pnl_pct,fees,mfe,mae,exit_reason');
    for (final t in trades) {
      buf.writeln([
        t.id,
        t.botId,
        t.side.name,
        t.entryPrice.toStringAsFixed(6),
        t.exitPrice.toStringAsFixed(6),
        t.qty.toStringAsFixed(6),
        t.entryTimestampMs,
        t.exitTimestampMs,
        t.pnl.toStringAsFixed(6),
        t.pnlPct.toStringAsFixed(6),
        t.fees.toStringAsFixed(6),
        t.mfe.toStringAsFixed(6),
        t.mae.toStringAsFixed(6),
        t.exitReason.name,
      ].join(','));
    }
    return buf.toString();
  }

  static String resultToJson(BacktestResult result) {
    return jsonEncode({
      'run_id': result.runId,
      'start_ms': result.startTimestampMs,
      'end_ms': result.endTimestampMs,
      'total_candles': result.totalCandles,
      'initial_cash': result.initialCash,
      'final_equity': result.finalEquity,
      'return_pct': result.returnPct,
      'total_trades': result.totalTrades,
      'win_rate': result.winRate,
      'profit_factor': result.profitFactor.isFinite ? result.profitFactor : null,
      'total_fees': result.totalFees,
      'equity_curve': result.equityCurve,
      'trades': result.trades.map((t) => t.toJson()).toList(),
    });
  }
}
