import 'package:flutter/material.dart';
import '../../analysis/metrics.dart';
import '../../core/models/backtest_result.dart';
import '../../state/backtest_state.dart';

class ResultsView extends StatelessWidget {
  final BacktestStatus status;
  const ResultsView({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: switch (status) {
          BacktestIdle() => const _EmptyState(message: 'Configure and start a backtest.'),
          BacktestRunning(:final trades, :final lastEquity, :final percent) =>
            _RunningView(tradeCount: trades.length, equity: lastEquity, percent: percent),
          BacktestDone(:final result) => _DoneView(result: result),
          BacktestErrorState(:final message) => _ErrorView(message: message),
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});
  @override
  Widget build(BuildContext context) => Center(
        child: Text(message, style: const TextStyle(color: Colors.grey)),
      );
}

class _RunningView extends StatelessWidget {
  final int tradeCount;
  final double? equity;
  final double percent;
  const _RunningView({required this.tradeCount, required this.equity, required this.percent});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Live', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: percent / 100),
          const SizedBox(height: 8),
          _Metric(label: 'Progress', value: '${percent.toStringAsFixed(1)}%'),
          _Metric(label: 'Trades', value: '$tradeCount'),
          _Metric(label: 'Equity', value: equity != null ? '${equity!.toStringAsFixed(2)} USDT' : '—'),
        ],
      );
}

class _DoneView extends StatelessWidget {
  final BacktestResult result;
  const _DoneView({required this.result});

  @override
  Widget build(BuildContext context) {
    final m = MetricsCalculator.compute(result, timeframe: '1h');
    final theme = Theme.of(context);
    final returnColor = result.returnPct >= 0 ? Colors.green : Colors.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text('Result', style: theme.textTheme.titleMedium),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: returnColor.withAlpha(30),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${result.returnPct >= 0 ? "+" : ""}${result.returnPct.toStringAsFixed(2)}%',
                style: TextStyle(color: returnColor, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const Divider(),
        _SectionHeader(title: 'Performance'),
        _Metric(label: 'Final equity', value: '${result.finalEquity.toStringAsFixed(2)} USDT'),
        _Metric(label: 'Trades', value: '${result.totalTrades}'),
        _Metric(label: 'Win rate', value: '${result.winRate.toStringAsFixed(1)}%'),
        _Metric(
          label: 'Profit factor',
          value: result.profitFactor.isFinite ? result.profitFactor.toStringAsFixed(2) : '∞',
        ),
        _Metric(label: 'Expectancy', value: m.expectancy.toStringAsFixed(2)),
        _Metric(label: 'Total fees', value: '${result.totalFees.toStringAsFixed(2)} USDT'),
        const SizedBox(height: 8),
        _SectionHeader(title: 'Risk'),
        _Metric(label: 'Max drawdown', value: '${m.maxDrawdownPct.toStringAsFixed(2)}%'),
        _Metric(label: 'Sharpe', value: m.sharpe.toStringAsFixed(2)),
        _Metric(label: 'Sortino', value: m.sortino.toStringAsFixed(2)),
        _Metric(label: 'Calmar', value: m.calmar.toStringAsFixed(2)),
        _Metric(label: 'Ulcer index', value: m.ulcerIndex.toStringAsFixed(2)),
        _Metric(label: 'Recovery', value: m.recoveryFactor.toStringAsFixed(2)),
        const SizedBox(height: 8),
        _SectionHeader(title: 'Streaks & MFE/MAE'),
        _Metric(label: 'Win streak', value: '${m.longestWinStreak}'),
        _Metric(label: 'Loss streak', value: '${m.longestLossStreak}'),
        _Metric(label: 'Avg win', value: m.avgWin.toStringAsFixed(2)),
        _Metric(label: 'Avg loss', value: m.avgLoss.toStringAsFixed(2)),
        _Metric(label: 'Avg MFE', value: '${m.avgMfe.toStringAsFixed(2)}%'),
        _Metric(label: 'Avg MAE', value: '${m.avgMae.toStringAsFixed(2)}%'),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('Backtest failed', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(message, style: const TextStyle(fontSize: 12)),
        ],
      );
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(title, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600)),
      );
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      );
}
