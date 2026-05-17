import 'trade.dart';

class BacktestResult {
  final String runId;
  final int startTimestampMs;
  final int endTimestampMs;
  final int totalCandles;
  final double initialCash;
  final double finalEquity;
  final List<Trade> trades;
  final List<double> equityCurve;
  final Map<String, BotBreakdown> perBot;

  const BacktestResult({
    required this.runId,
    required this.startTimestampMs,
    required this.endTimestampMs,
    required this.totalCandles,
    required this.initialCash,
    required this.finalEquity,
    required this.trades,
    required this.equityCurve,
    required this.perBot,
  });

  double get returnPct => (finalEquity - initialCash) / initialCash * 100;
  int get totalTrades => trades.length;
  int get wins => trades.where((t) => t.isWin).length;
  double get winRate => totalTrades > 0 ? wins / totalTrades * 100 : 0;

  double get grossProfit =>
      trades.where((t) => t.pnl > 0).fold(0.0, (s, t) => s + t.pnl);
  double get grossLoss =>
      trades.where((t) => t.pnl < 0).fold(0.0, (s, t) => s + t.pnl);
  double get profitFactor =>
      grossLoss != 0 ? grossProfit / grossLoss.abs() : double.infinity;
  double get totalFees => trades.fold(0.0, (s, t) => s + t.fees);
}

class BotBreakdown {
  final String botId;
  final int tradeCount;
  final double pnl;
  final double winRate;

  const BotBreakdown({
    required this.botId,
    required this.tradeCount,
    required this.pnl,
    required this.winRate,
  });
}
