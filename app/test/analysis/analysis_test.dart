import 'package:flutter_test/flutter_test.dart';
import 'package:cvz_backtester/analysis/metrics.dart';
import 'package:cvz_backtester/analysis/monte_carlo.dart';
import 'package:cvz_backtester/analysis/stress.dart';
import 'package:cvz_backtester/core/models/backtest_result.dart';
import 'package:cvz_backtester/core/models/trade.dart';
import 'package:cvz_backtester/core/models/position.dart';
import 'package:cvz_backtester/core/models/order.dart';
import 'package:cvz_backtester/services/export_service.dart';

void main() {
  Trade makeTrade({
    required double pnl,
    required int id,
    double mfe = 0.0,
    double mae = 0.0,
  }) =>
      Trade(
        id: id,
        botId: 'b',
        side: PositionSide.long,
        entryPrice: 100,
        exitPrice: 100 + pnl,
        qty: 1,
        entryTimestampMs: id * 1000,
        exitTimestampMs: id * 1000 + 500,
        pnl: pnl,
        pnlPct: pnl,
        fees: 0.5,
        mfe: mfe,
        mae: mae,
        exitReason: TriggerReason.manual,
      );

  BacktestResult makeResult({
    required List<Trade> trades,
    required List<double> equity,
    double initial = 10000,
  }) =>
      BacktestResult(
        runId: 'r1',
        startTimestampMs: 0,
        endTimestampMs: 1000000,
        totalCandles: equity.length,
        initialCash: initial,
        finalEquity: equity.isNotEmpty ? equity.last : initial,
        trades: trades,
        equityCurve: equity,
        perBot: const {},
      );

  group('MetricsCalculator', () {
    test('Sharpe is 0 for flat equity', () {
      final r = makeResult(trades: [], equity: List.filled(50, 10000));
      final m = MetricsCalculator.compute(r);
      expect(m.sharpe, 0.0);
    });

    test('max drawdown is 0 when only rising', () {
      final r = makeResult(trades: [], equity: [10000, 11000, 12000, 13000]);
      final m = MetricsCalculator.compute(r);
      expect(m.maxDrawdownPct, 0.0);
    });

    test('max drawdown detects 30% drop from peak', () {
      final r = makeResult(
        trades: [],
        equity: [10000, 11000, 12000, 8400], // 12000 → 8400 = 30% drop
      );
      final m = MetricsCalculator.compute(r);
      expect(m.maxDrawdownPct, closeTo(30.0, 0.001));
    });

    test('expectancy = winRate * avgWin + (1-winRate) * avgLoss', () {
      final trades = [
        makeTrade(pnl: 10, id: 1),
        makeTrade(pnl: 20, id: 2),
        makeTrade(pnl: -5, id: 3),
      ];
      final r = makeResult(trades: trades, equity: [10000, 10010, 10030, 10025]);
      final m = MetricsCalculator.compute(r);
      // 2/3 * 15 + 1/3 * -5 = 10 - 1.667 = 8.333
      expect(m.expectancy, closeTo(8.333, 0.01));
    });

    test('longest streak detection', () {
      final trades = [
        makeTrade(pnl: 10, id: 1),  // W
        makeTrade(pnl: 10, id: 2),  // W
        makeTrade(pnl: -5, id: 3),  // L
        makeTrade(pnl: -5, id: 4),  // L
        makeTrade(pnl: -5, id: 5),  // L
        makeTrade(pnl: 10, id: 6),  // W
      ];
      final r = makeResult(trades: trades, equity: [10000, 10010, 10020]);
      final m = MetricsCalculator.compute(r);
      expect(m.longestWinStreak, 2);
      expect(m.longestLossStreak, 3);
    });
  });

  group('MonteCarloSimulator', () {
    test('empty trades returns zero result', () {
      final r = makeResult(trades: [], equity: [10000]);
      final mc = MonteCarloSimulator.simulate(r);
      expect(mc.simulations, 0);
    });

    test('positive-skewed trades produce probProfit > 50%', () {
      final trades = [
        for (int i = 0; i < 20; i++) makeTrade(pnl: 10, id: i),
        makeTrade(pnl: -5, id: 99),
      ];
      final r = makeResult(trades: trades, equity: [10000, 10195]);
      final mc = MonteCarloSimulator.simulate(r, simulations: 500, seed: 42);
      expect(mc.probProfit, greaterThan(50));
    });

    test('reproducible with seed', () {
      final trades = [
        makeTrade(pnl: 10, id: 1),
        makeTrade(pnl: -5, id: 2),
        makeTrade(pnl: 20, id: 3),
      ];
      final r = makeResult(trades: trades, equity: [10000]);
      final mc1 = MonteCarloSimulator.simulate(r, simulations: 100, seed: 42);
      final mc2 = MonteCarloSimulator.simulate(r, simulations: 100, seed: 42);
      expect(mc1.medianReturn, mc2.medianReturn);
    });
  });

  group('StressTester', () {
    test('2x fees reduces return', () {
      final trades = [
        makeTrade(pnl: 10, id: 1),
        makeTrade(pnl: 10, id: 2),
      ];
      final r = makeResult(trades: trades, equity: [10000, 10010, 10020]);
      final results = StressTester.run(r, scenarios: const [
        StressScenario(name: 'baseline'),
        StressScenario(name: '2x_fees', feeMultiplier: 2.0),
      ]);
      expect(results.length, 2);
      expect(results[1].returnPct, lessThan(results[0].returnPct));
    });

    test('drop best 50% trades makes return worse', () {
      final trades = [
        makeTrade(pnl: 100, id: 1),  // best
        makeTrade(pnl: 1, id: 2),
        makeTrade(pnl: 1, id: 3),
        makeTrade(pnl: 1, id: 4),
      ];
      final r = makeResult(trades: trades, equity: [10000, 10103]);
      final results = StressTester.run(r, scenarios: const [
        StressScenario(name: 'drop50', dropBestPercentile: 50.0),
      ]);
      // Drop the top 2 trades (100, 1) → only 1+1 = 2 remain
      expect(results.first.returnPct, lessThan(1.0));
    });
  });

  group('ExportService', () {
    test('CSV has correct header and one row per trade', () {
      final trades = [
        makeTrade(pnl: 10, id: 1),
        makeTrade(pnl: -5, id: 2),
      ];
      final csv = ExportService.tradesToCsv(trades);
      final lines = csv.trim().split('\n');
      expect(lines.length, 3); // header + 2 trades
      expect(lines.first, startsWith('id,bot_id,side'));
      expect(lines[1], contains('10.000000'));
      expect(lines[2], contains('-5.000000'));
    });

    test('JSON round-trip preserves key metrics', () {
      final r = makeResult(
        trades: [makeTrade(pnl: 50, id: 1)],
        equity: [10000, 10049.5],
      );
      final json = ExportService.resultToJson(r);
      expect(json, contains('"run_id":"r1"'));
      expect(json, contains('"total_trades":1'));
    });
  });
}
