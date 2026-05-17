import 'package:flutter/material.dart';
import '../../state/backtest_state.dart';

/// Compact results panel — shows summary metrics for the current run.
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
        children: [
          Text('Live', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Metric(label: 'Progress', value: '${percent.toStringAsFixed(1)}%'),
          _Metric(label: 'Trades', value: '$tradeCount'),
          _Metric(label: 'Equity', value: equity != null ? '${equity!.toStringAsFixed(2)} USDT' : '—'),
        ],
      );
}

class _DoneView extends StatelessWidget {
  final dynamic result;
  const _DoneView({required this.result});
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Result', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _Metric(label: 'Return', value: '${result.returnPct.toStringAsFixed(2)}%'),
            _Metric(label: 'Trades', value: '${result.totalTrades}'),
            _Metric(label: 'Win rate', value: '${result.winRate.toStringAsFixed(1)}%'),
            _Metric(label: 'Profit factor', value: result.profitFactor.isFinite ? result.profitFactor.toStringAsFixed(2) : '∞'),
            _Metric(label: 'Total fees', value: '${result.totalFees.toStringAsFixed(2)} USDT'),
            _Metric(label: 'Final equity', value: '${result.finalEquity.toStringAsFixed(2)} USDT'),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  final String message;
  const _ErrorView({required this.message});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
