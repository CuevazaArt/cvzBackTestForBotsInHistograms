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
        totalReturnPct: (j['total_return_pct'] as num?)?.toDouble() ?? 0,
        trades:         (j['trades'] as num?)?.toInt() ?? 0,
        winners:        (j['winners'] as num?)?.toInt() ?? 0,
        losers:         (j['losers'] as num?)?.toInt() ?? 0,
        winRatePct:     (j['win_rate_pct'] as num?)?.toDouble() ?? 0,
        profitFactor:   (j['profit_factor'] as num?)?.toDouble() ?? 0,
        avgWinUsdt:     (j['avg_win_usdt'] as num?)?.toDouble() ?? 0,
        avgLossUsdt:    (j['avg_loss_usdt'] as num?)?.toDouble() ?? 0,
        maxDrawdownPct: (j['max_drawdown_pct'] as num?)?.toDouble() ?? 0,
        totalFeesUsdt:  (j['total_fees_usdt'] as num?)?.toDouble() ?? 0,
        initialEquity:  (j['initial_equity'] as num?)?.toDouble() ?? 0,
        finalEquity:    (j['final_equity'] as num?)?.toDouble() ?? 0,
        peakEquity:     (j['peak_equity'] as num?)?.toDouble() ?? 0,
        rejectedOrders: (j['rejected_orders'] as num?)?.toInt() ?? 0,
      );
}

class CandleData {
  final int time;   // epoch seconds
  final double open, high, low, close, volume;

  const CandleData({
    required this.time,
    required this.open, required this.high,
    required this.low,  required this.close,
    required this.volume,
  });

  factory CandleData.fromJson(Map<String, dynamic> j) => CandleData(
        time:   (j['time']   as num).toInt(),
        open:   (j['open']   as num).toDouble(),
        high:   (j['high']   as num).toDouble(),
        low:    (j['low']    as num).toDouble(),
        close:  (j['close']  as num).toDouble(),
        volume: (j['volume'] as num).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'time': time, 'open': open, 'high': high,
        'low': low, 'close': close, 'volume': volume,
      };
}

class TradeResult {
  final int entryTime;
  final int? exitTime;     // null if still open
  final double entryPrice;
  final double exitPrice;
  final double qty;
  final double pnl;
  final double pnlPct;
  final double feeUsdt;
  final String? reason;

  const TradeResult({
    required this.entryTime,
    this.exitTime,
    required this.entryPrice,
    required this.exitPrice,
    required this.qty,
    required this.pnl,
    required this.pnlPct,
    required this.feeUsdt,
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
        feeUsdt:    (j['fee_usdt'] as num?)?.toDouble() ?? 0,
        reason:     j['reason'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'entry_time':  entryTime,
        'exit_time':   exitTime,
        'entry_price': entryPrice,
        'exit_price':  exitPrice,
        'qty':         qty,
        'pnl':         pnl,
        'pnl_pct':     pnlPct,
        'reason':      reason,
      };
}

class EquityPoint {
  final int time;
  final double value;
  const EquityPoint({required this.time, required this.value});

  factory EquityPoint.fromJson(Map<String, dynamic> j) =>
      EquityPoint(time: (j['time'] as num).toInt(), value: (j['value'] as num).toDouble());

  Map<String, dynamic> toJson() => {'time': time, 'value': value};
}

class BacktestResult {
  final String bot;
  final Map<String, dynamic> params;
  final BacktestSummary summary;
  final List<CandleData> candles;
  final List<TradeResult> trades;
  final List<EquityPoint> equityCurve;

  const BacktestResult({
    required this.bot,
    required this.params,
    required this.summary,
    required this.candles,
    required this.trades,
    required this.equityCurve,
  });

  factory BacktestResult.fromJson(Map<String, dynamic> j) => BacktestResult(
        bot:        j['bot'] as String? ?? '',
        params:     (j['params'] as Map<String, dynamic>? ?? {}),
        summary:    BacktestSummary.fromJson(j['summary'] as Map<String, dynamic>),
        candles:    ((j['candles'] as List?) ?? [])
            .map((c) => CandleData.fromJson(c as Map<String, dynamic>))
            .toList(),
        trades:     ((j['trades'] as List?) ?? [])
            .map((t) => TradeResult.fromJson(t as Map<String, dynamic>))
            .toList(),
        equityCurve: ((j['equity_curve'] as List?) ?? [])
            .map((e) => EquityPoint.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
