import '../core/models/backtest_result.dart';
import 'metrics.dart';

class StressScenario {
  final String name;
  final double feeMultiplier;
  final double slippageMultiplier;
  final double dropBestPercentile;

  const StressScenario({
    required this.name,
    this.feeMultiplier = 1.0,
    this.slippageMultiplier = 1.0,
    this.dropBestPercentile = 0.0,
  });
}

class StressResult {
  final String scenarioName;
  final double returnPct;
  final double maxDrawdownPct;
  final double sharpe;
  final int totalTrades;

  const StressResult({
    required this.scenarioName,
    required this.returnPct,
    required this.maxDrawdownPct,
    required this.sharpe,
    required this.totalTrades,
  });
}

class StressTester {
  /// Re-computes performance metrics under each [scenario].
  ///
  /// Adjusts the PnL of each trade by the fee/slippage multipliers (a 2x fee
  /// multiplier subtracts an additional 1x fees), then optionally removes the
  /// top N% of trades by PnL before recomputing.
  static List<StressResult> run(
    BacktestResult baseline, {
    required List<StressScenario> scenarios,
    String timeframe = '1d',
  }) {
    final results = <StressResult>[];
    for (final s in scenarios) {
      // Adjusted trade pnls.
      var adjusted = baseline.trades.map((t) {
        // fee adjustment: subtract extra fees.
        final extraFees = t.fees * (s.feeMultiplier - 1);
        // slippage adjustment: assume slippage is fractional of trade gross.
        final extraSlippage =
            (t.exitPrice * t.qty).abs() * 0.001 * (s.slippageMultiplier - 1);
        return _AdjustedTrade(pnl: t.pnl - extraFees - extraSlippage);
      }).toList();

      // Drop best N percentile.
      if (s.dropBestPercentile > 0 && adjusted.isNotEmpty) {
        adjusted.sort((a, b) => b.pnl.compareTo(a.pnl));
        final keep = adjusted.length -
            (adjusted.length * s.dropBestPercentile / 100).round();
        adjusted = adjusted.skip(adjusted.length - keep).toList();
      }

      // Recompute equity curve under adjustment.
      double equity = baseline.initialCash;
      double peak = equity;
      double maxDd = 0.0;
      final equityCurve = <double>[equity];
      final returns = <double>[];
      for (final t in adjusted) {
        final prev = equity;
        equity += t.pnl;
        equityCurve.add(equity);
        if (equity > peak) peak = equity;
        if (peak > 0) {
          final dd = (peak - equity) / peak * 100;
          if (dd > maxDd) maxDd = dd;
        }
        if (prev > 0) returns.add((equity - prev) / prev);
      }

      final scenarioResult = BacktestResult(
        runId: '${baseline.runId}_${s.name}',
        startTimestampMs: baseline.startTimestampMs,
        endTimestampMs: baseline.endTimestampMs,
        totalCandles: baseline.totalCandles,
        initialCash: baseline.initialCash,
        finalEquity: equity,
        trades: const [],
        equityCurve: equityCurve,
        perBot: const {},
      );
      final m = MetricsCalculator.compute(scenarioResult, timeframe: timeframe);

      results.add(StressResult(
        scenarioName: s.name,
        returnPct: (equity - baseline.initialCash) / baseline.initialCash * 100,
        maxDrawdownPct: maxDd,
        sharpe: m.sharpe,
        totalTrades: adjusted.length,
      ));
    }
    return results;
  }
}

class _AdjustedTrade {
  final double pnl;
  const _AdjustedTrade({required this.pnl});
}
