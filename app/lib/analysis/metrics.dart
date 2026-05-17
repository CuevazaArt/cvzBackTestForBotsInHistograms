import 'dart:math' as math;
import '../core/models/backtest_result.dart';
import '../core/models/trade.dart';

/// Bars per year by timeframe — used to annualize Sharpe et al.
const Map<String, int> _annualBars = {
  '1m': 525600,
  '5m': 105120,
  '15m': 35040,
  '30m': 17520,
  '1h': 8760,
  '4h': 2190,
  '1d': 365,
  '1w': 52,
};

class AdvancedMetrics {
  final double sharpe;
  final double sortino;
  final double calmar;
  final double ulcerIndex;
  final double recoveryFactor;
  final double maxDrawdownPct;
  final double avgWin;
  final double avgLoss;
  final double expectancy;
  final int longestWinStreak;
  final int longestLossStreak;
  final double avgMfe;
  final double avgMae;

  const AdvancedMetrics({
    required this.sharpe,
    required this.sortino,
    required this.calmar,
    required this.ulcerIndex,
    required this.recoveryFactor,
    required this.maxDrawdownPct,
    required this.avgWin,
    required this.avgLoss,
    required this.expectancy,
    required this.longestWinStreak,
    required this.longestLossStreak,
    required this.avgMfe,
    required this.avgMae,
  });
}

class MetricsCalculator {
  /// Computes the full set of advanced metrics for a finished BacktestResult.
  static AdvancedMetrics compute(BacktestResult result, {String timeframe = '1d'}) {
    final returns = _barReturns(result.equityCurve);
    final annual = _annualBars[timeframe] ?? 365;

    return AdvancedMetrics(
      sharpe: _sharpe(returns, annual),
      sortino: _sortino(returns, annual),
      calmar: _calmar(result, annual),
      ulcerIndex: _ulcerIndex(result.equityCurve),
      recoveryFactor: _recoveryFactor(result),
      maxDrawdownPct: _maxDrawdownPct(result.equityCurve),
      avgWin: _avgPnl(result.trades.where((t) => t.isWin).toList()),
      avgLoss: _avgPnl(result.trades.where((t) => !t.isWin).toList()),
      expectancy: _expectancy(result.trades),
      longestWinStreak: _longestStreak(result.trades, win: true),
      longestLossStreak: _longestStreak(result.trades, win: false),
      avgMfe: _avgMetric(result.trades, (t) => t.mfe),
      avgMae: _avgMetric(result.trades, (t) => t.mae),
    );
  }

  static List<double> _barReturns(List<double> equity) {
    if (equity.length < 2) return const [];
    final out = <double>[];
    for (int i = 1; i < equity.length; i++) {
      if (equity[i - 1] > 0) {
        out.add((equity[i] - equity[i - 1]) / equity[i - 1]);
      }
    }
    return out;
  }

  static double _sharpe(List<double> returns, int barsPerYear) {
    if (returns.isEmpty) return 0.0;
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    final variance = returns.fold(0.0, (s, r) => s + (r - mean) * (r - mean)) /
        returns.length;
    final std = math.sqrt(variance);
    if (std == 0) return 0.0;
    return (mean / std) * math.sqrt(barsPerYear);
  }

  static double _sortino(List<double> returns, int barsPerYear) {
    if (returns.isEmpty) return 0.0;
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    final downside = returns.where((r) => r < 0).toList();
    if (downside.isEmpty) return 0.0;
    final dVar = downside.fold(0.0, (s, r) => s + r * r) / returns.length;
    final dStd = math.sqrt(dVar);
    if (dStd == 0) return 0.0;
    return (mean / dStd) * math.sqrt(barsPerYear);
  }

  static double _calmar(BacktestResult r, int barsPerYear) {
    final maxDd = _maxDrawdownPct(r.equityCurve);
    if (maxDd == 0) return 0.0;
    final years = r.equityCurve.length / barsPerYear;
    if (years <= 0) return 0.0;
    final cagr = math.pow(r.finalEquity / r.initialCash, 1 / years) - 1;
    return (cagr * 100) / maxDd;
  }

  static double _ulcerIndex(List<double> equity) {
    if (equity.isEmpty) return 0.0;
    double peak = equity[0];
    double sqSum = 0.0;
    for (final e in equity) {
      if (e > peak) peak = e;
      final ddPct = peak > 0 ? (e - peak) / peak * 100 : 0.0;
      sqSum += ddPct * ddPct;
    }
    return math.sqrt(sqSum / equity.length);
  }

  static double _recoveryFactor(BacktestResult r) {
    final totalReturn = r.finalEquity - r.initialCash;
    final maxDd = _maxDrawdownPct(r.equityCurve) / 100 * r.initialCash;
    if (maxDd == 0) return 0.0;
    return totalReturn / maxDd.abs();
  }

  static double _maxDrawdownPct(List<double> equity) {
    if (equity.isEmpty) return 0.0;
    double peak = equity[0];
    double maxDd = 0.0;
    for (final e in equity) {
      if (e > peak) peak = e;
      if (peak > 0) {
        final dd = (peak - e) / peak * 100;
        if (dd > maxDd) maxDd = dd;
      }
    }
    return maxDd;
  }

  static double _avgPnl(List<Trade> trades) =>
      trades.isEmpty ? 0.0 : trades.fold(0.0, (s, t) => s + t.pnl) / trades.length;

  static double _expectancy(List<Trade> trades) {
    if (trades.isEmpty) return 0.0;
    final wins = trades.where((t) => t.isWin).toList();
    final losses = trades.where((t) => !t.isWin).toList();
    final winRate = wins.length / trades.length;
    final avgWin = wins.isEmpty ? 0.0 : wins.fold(0.0, (s, t) => s + t.pnl) / wins.length;
    final avgLoss =
        losses.isEmpty ? 0.0 : losses.fold(0.0, (s, t) => s + t.pnl) / losses.length;
    return winRate * avgWin + (1 - winRate) * avgLoss;
  }

  static int _longestStreak(List<Trade> trades, {required bool win}) {
    int longest = 0;
    int current = 0;
    for (final t in trades) {
      if (t.isWin == win) {
        current++;
        if (current > longest) longest = current;
      } else {
        current = 0;
      }
    }
    return longest;
  }

  static double _avgMetric(List<Trade> trades, double Function(Trade) getter) =>
      trades.isEmpty
          ? 0.0
          : trades.fold(0.0, (s, t) => s + getter(t)) / trades.length;
}
