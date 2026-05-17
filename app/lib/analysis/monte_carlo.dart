import 'dart:math' as math;
import '../core/models/backtest_result.dart';

class MonteCarloResult {
  final int simulations;
  final double medianReturn;
  final double p5Return;
  final double p95Return;
  final double medianMaxDrawdown;
  final double worstMaxDrawdown;
  final double probProfit;
  final double probRuin; // probability of hitting [ruinDrawdownPct]
  final double valueAtRisk95;

  const MonteCarloResult({
    required this.simulations,
    required this.medianReturn,
    required this.p5Return,
    required this.p95Return,
    required this.medianMaxDrawdown,
    required this.worstMaxDrawdown,
    required this.probProfit,
    required this.probRuin,
    required this.valueAtRisk95,
  });
}

class MonteCarloSimulator {
  /// Bootstraps [simulations] equity curves by resampling trade PnLs with
  /// replacement. Returns aggregate risk statistics.
  static MonteCarloResult simulate(
    BacktestResult result, {
    int simulations = 1000,
    double ruinDrawdownPct = 50.0,
    int? seed,
  }) {
    if (result.trades.isEmpty) {
      return const MonteCarloResult(
        simulations: 0,
        medianReturn: 0,
        p5Return: 0,
        p95Return: 0,
        medianMaxDrawdown: 0,
        worstMaxDrawdown: 0,
        probProfit: 0,
        probRuin: 0,
        valueAtRisk95: 0,
      );
    }

    final rng = math.Random(seed);
    final pnls = result.trades.map((t) => t.pnl).toList();
    final initial = result.initialCash;

    final finalReturns = <double>[];
    final maxDrawdowns = <double>[];
    int profitable = 0;
    int ruined = 0;

    for (int s = 0; s < simulations; s++) {
      double equity = initial;
      double peak = initial;
      double maxDd = 0.0;
      for (int t = 0; t < pnls.length; t++) {
        equity += pnls[rng.nextInt(pnls.length)];
        if (equity > peak) peak = equity;
        if (peak > 0) {
          final dd = (peak - equity) / peak * 100;
          if (dd > maxDd) maxDd = dd;
        }
      }
      final ret = (equity - initial) / initial * 100;
      finalReturns.add(ret);
      maxDrawdowns.add(maxDd);
      if (ret > 0) profitable++;
      if (maxDd >= ruinDrawdownPct) ruined++;
    }

    finalReturns.sort();
    maxDrawdowns.sort();
    final p5 = finalReturns[(simulations * 0.05).floor()];
    final p50 = finalReturns[(simulations * 0.5).floor()];
    final p95 = finalReturns[(simulations * 0.95).floor()];
    final medDd = maxDrawdowns[(simulations * 0.5).floor()];
    final worstDd = maxDrawdowns.last;
    final var95 = -finalReturns[(simulations * 0.05).floor()];

    return MonteCarloResult(
      simulations: simulations,
      medianReturn: p50,
      p5Return: p5,
      p95Return: p95,
      medianMaxDrawdown: medDd,
      worstMaxDrawdown: worstDd,
      probProfit: profitable / simulations * 100,
      probRuin: ruined / simulations * 100,
      valueAtRisk95: var95,
    );
  }
}
