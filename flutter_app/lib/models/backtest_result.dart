class BacktestSummary {
  final double totalReturnPct;
  final int trades;
  final int winners;
  final int losers;
  final double winRatePct;
  final double profitFactor;
  final double avgWinUsdt;
  final double avgLossUsdt;
  final double maxDrawdownPct;
  final double totalFeesUsdt;
  final double initialEquity;
  final double finalEquity;
  final double peakEquity;
  final int rejectedOrders;

  const BacktestSummary({
    required this.totalReturnPct,
    required this.trades,
    required this.winners,
    required this.losers,
    required this.winRatePct,
    required this.profitFactor,
    required this.avgWinUsdt,
    required this.avgLossUsdt,
    required this.maxDrawdownPct,
    required this.totalFeesUsdt,
    required this.initialEquity,
    required this.finalEquity,
    required this.peakEquity,
    required this.rejectedOrders,
  });

  factory BacktestSummary.fromJson(Map<String, dynamic> j) => BacktestSummary(
        totalReturnPct: (j['total_return_pct'] as num).toDouble(),
        trades:         (j['trades'] as num).toInt(),
        winners:        (j['winners'] as num).toInt(),
        losers:         (j['losers'] as num).toInt(),
        winRatePct:     (j['win_rate_pct'] as num).toDouble(),
        profitFactor:   (j['profit_factor'] as num).toDouble(),
        avgWinUsdt:     (j['avg_win_usdt'] as num).toDouble(),
        avgLossUsdt:    (j['avg_loss_usdt'] as num).toDouble(),
        maxDrawdownPct: (j['max_drawdown_pct'] as num).toDouble(),
        totalFeesUsdt:  (j['total_fees_usdt'] as num).toDouble(),
        initialEquity:  (j['initial_equity'] as num).toDouble(),
        finalEquity:    (j['final_equity'] as num).toDouble(),
        peakEquity:     (j['peak_equity'] as num).toDouble(),
        rejectedOrders: (j['rejected_orders'] as num).toInt(),
      );
}

class TradeResult {
  final int entryTime;
  final int? exitTime;
  final double entryPrice;
  final double exitPrice;
  final double qty;
  final double pnl;
  final double pnlPct;
  final String? reason;

  const TradeResult({
    required this.entryTime,
    this.exitTime,
    required this.entryPrice,
    required this.exitPrice,
    required this.qty,
    required this.pnl,
    required this.pnlPct,
    this.reason,
  });

  factory TradeResult.fromJson(Map<String, dynamic> j) => TradeResult(
        entryTime:  (j['entry_time'] as num).toInt(),
        exitTime:   j['exit_time'] == null ? null : (j['exit_time'] as num).toInt(),
        entryPrice: (j['entry_price'] as num).toDouble(),
        exitPrice:  (j['exit_price'] as num).toDouble(),
        qty:        (j['qty'] as num).toDouble(),
        pnl:        (j['pnl'] as num).toDouble(),
        pnlPct:     (j['pnl_pct'] as num).toDouble(),
        reason:     j['reason'] as String?,
      );
}

class EquityPoint {
  final int time;
  final double value;
  const EquityPoint({required this.time, required this.value});
  factory EquityPoint.fromJson(Map<String, dynamic> j) =>
      EquityPoint(time: (j['time'] as num).toInt(), value: (j['value'] as num).toDouble());
}

class BacktestResult {
  final String bot;
  final Map<String, dynamic> params;
  final BacktestSummary summary;
  final List<TradeResult> trades;
  final List<EquityPoint> equityCurve;

  const BacktestResult({
    required this.bot,
    required this.params,
    required this.summary,
    required this.trades,
    required this.equityCurve,
  });

  factory BacktestResult.fromJson(Map<String, dynamic> j) => BacktestResult(
        bot:         j['bot'] as String,
        params:      (j['params'] as Map<String, dynamic>? ?? {}),
        summary:     BacktestSummary.fromJson(j['summary'] as Map<String, dynamic>),
        trades:      ((j['trades'] as List?) ?? [])
            .map((t) => TradeResult.fromJson(t as Map<String, dynamic>))
            .toList(),
        equityCurve: ((j['equity_curve'] as List?) ?? [])
            .map((e) => EquityPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
