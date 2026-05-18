import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../analysis/metrics.dart';
import '../../core/models/backtest_result.dart';
import '../../core/models/candle.dart';
import '../../state/backtest_state.dart';

class ResultsBar extends StatelessWidget {
  final BacktestStatus status;
  final String markersMode;
  final bool indicatorsVisible;
  final bool equityVisible;
  final ValueChanged<String> onMarkersModeChanged;
  final ValueChanged<bool> onIndicatorsVisibleChanged;
  final ValueChanged<bool> onEquityVisibleChanged;

  const ResultsBar({
    super.key,
    required this.status,
    required this.markersMode,
    required this.indicatorsVisible,
    required this.equityVisible,
    required this.onMarkersModeChanged,
    required this.onIndicatorsVisibleChanged,
    required this.onEquityVisibleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: switch (status) {
        BacktestIdle() => _IdleBar(
            markersMode: markersMode,
            indicatorsVisible: indicatorsVisible,
            equityVisible: equityVisible,
            onMarkersModeChanged: onMarkersModeChanged,
            onIndicatorsVisibleChanged: onIndicatorsVisibleChanged,
            onEquityVisibleChanged: onEquityVisibleChanged,
          ),
        BacktestRunning() => _RunningBar(
            status: status as BacktestRunning,
            markersMode: markersMode,
            indicatorsVisible: indicatorsVisible,
            equityVisible: equityVisible,
            onMarkersModeChanged: onMarkersModeChanged,
            onIndicatorsVisibleChanged: onIndicatorsVisibleChanged,
            onEquityVisibleChanged: onEquityVisibleChanged,
          ),
        BacktestDone(:final result) => _DoneBar(
            result: result,
            markersMode: markersMode,
            indicatorsVisible: indicatorsVisible,
            equityVisible: equityVisible,
            onMarkersModeChanged: onMarkersModeChanged,
            onIndicatorsVisibleChanged: onIndicatorsVisibleChanged,
            onEquityVisibleChanged: onEquityVisibleChanged,
          ),
        BacktestErrorState(:final message) => _ErrorBar(message: message),
      },
    );
  }
}

class _ChartToggles extends StatelessWidget {
  final String markersMode;
  final bool indicatorsVisible;
  final bool equityVisible;
  final ValueChanged<String> onMarkersModeChanged;
  final ValueChanged<bool> onIndicatorsVisibleChanged;
  final ValueChanged<bool> onEquityVisibleChanged;

  const _ChartToggles({
    required this.markersMode,
    required this.indicatorsVisible,
    required this.equityVisible,
    required this.onMarkersModeChanged,
    required this.onIndicatorsVisibleChanged,
    required this.onEquityVisibleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          tooltip: 'Marker labels',
          initialValue: markersMode,
          onSelected: onMarkersModeChanged,
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'full', child: Text('Full labels')),
            PopupMenuItem(value: 'minimal', child: Text('Arrows only')),
            PopupMenuItem(value: 'off', child: Text('Hidden')),
          ],
          child: Chip(
            avatar: Icon(
              markersMode == 'off' ? Icons.label_off : Icons.label,
              size: 14,
            ),
            label: Text(
              markersMode == 'full' ? 'Labels' : markersMode == 'minimal' ? 'Arrows' : 'Off',
              style: const TextStyle(fontSize: 10),
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            labelPadding: const EdgeInsets.only(right: 4),
          ),
        ),
        const SizedBox(width: 4),
        FilterChip(
          label: const Text('Ind', style: TextStyle(fontSize: 10)),
          avatar: const Icon(Icons.show_chart, size: 14),
          selected: indicatorsVisible,
          onSelected: onIndicatorsVisibleChanged,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.only(right: 4),
        ),
        const SizedBox(width: 4),
        FilterChip(
          label: const Text('Eq', style: TextStyle(fontSize: 10)),
          avatar: const Icon(Icons.area_chart, size: 14),
          selected: equityVisible,
          onSelected: onEquityVisibleChanged,
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          labelPadding: const EdgeInsets.only(right: 4),
        ),
      ],
    );
  }
}

class _IdleBar extends StatelessWidget {
  final String markersMode;
  final bool indicatorsVisible;
  final bool equityVisible;
  final ValueChanged<String> onMarkersModeChanged;
  final ValueChanged<bool> onIndicatorsVisibleChanged;
  final ValueChanged<bool> onEquityVisibleChanged;

  const _IdleBar({
    required this.markersMode,
    required this.indicatorsVisible,
    required this.equityVisible,
    required this.onMarkersModeChanged,
    required this.onIndicatorsVisibleChanged,
    required this.onEquityVisibleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Text('Configure and start a backtest',
              style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
        _ChartToggles(
          markersMode: markersMode,
          indicatorsVisible: indicatorsVisible,
          equityVisible: equityVisible,
          onMarkersModeChanged: onMarkersModeChanged,
          onIndicatorsVisibleChanged: onIndicatorsVisibleChanged,
          onEquityVisibleChanged: onEquityVisibleChanged,
        ),
      ],
    );
  }
}

class _RunningBar extends StatelessWidget {
  final BacktestRunning status;
  final String markersMode;
  final bool indicatorsVisible;
  final bool equityVisible;
  final ValueChanged<String> onMarkersModeChanged;
  final ValueChanged<bool> onIndicatorsVisibleChanged;
  final ValueChanged<bool> onEquityVisibleChanged;

  const _RunningBar({
    required this.status,
    required this.markersMode,
    required this.indicatorsVisible,
    required this.equityVisible,
    required this.onMarkersModeChanged,
    required this.onIndicatorsVisibleChanged,
    required this.onEquityVisibleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final candle = status.currentCandle;
    final tf = DateFormat('yyyy-MM-dd HH:mm');

    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: status.percent / 100),
              const SizedBox(height: 2),
              Text(
                '${status.percent.toStringAsFixed(1)}%  |  ${status.trades.length} trades  |  ${status.lastEquity?.toStringAsFixed(0) ?? "-"}',
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ],
          ),
        ),
        if (status.paused && candle != null) ...[
          const SizedBox(width: 12),
          _CandleInfo(candle: candle, index: status.processed, tf: tf),
        ],
        const Spacer(),
        _ChartToggles(
          markersMode: markersMode,
          indicatorsVisible: indicatorsVisible,
          equityVisible: equityVisible,
          onMarkersModeChanged: onMarkersModeChanged,
          onIndicatorsVisibleChanged: onIndicatorsVisibleChanged,
          onEquityVisibleChanged: onEquityVisibleChanged,
        ),
      ],
    );
  }
}

class _CandleInfo extends StatelessWidget {
  final Candle candle;
  final int index;
  final DateFormat tf;
  const _CandleInfo({required this.candle, required this.index, required this.tf});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.fromMillisecondsSinceEpoch(candle.timestampMs, isUtc: true);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blue.withAlpha(20),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.blue.withAlpha(50)),
      ),
      child: Text(
        'Bar #$index  |  ${tf.format(dt)}  |  O:${candle.open.toStringAsFixed(1)} H:${candle.high.toStringAsFixed(1)} L:${candle.low.toStringAsFixed(1)} C:${candle.close.toStringAsFixed(1)} V:${candle.volume.toStringAsFixed(0)}',
        style: const TextStyle(fontSize: 10, fontFamily: 'monospace'),
      ),
    );
  }
}

class _DoneBar extends StatelessWidget {
  final BacktestResult result;
  final String markersMode;
  final bool indicatorsVisible;
  final bool equityVisible;
  final ValueChanged<String> onMarkersModeChanged;
  final ValueChanged<bool> onIndicatorsVisibleChanged;
  final ValueChanged<bool> onEquityVisibleChanged;

  const _DoneBar({
    required this.result,
    required this.markersMode,
    required this.indicatorsVisible,
    required this.equityVisible,
    required this.onMarkersModeChanged,
    required this.onIndicatorsVisibleChanged,
    required this.onEquityVisibleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final m = MetricsCalculator.compute(result, timeframe: '1h');
    final retColor = result.returnPct >= 0 ? Colors.green : Colors.red;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Return badge
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: retColor.withAlpha(30),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '${result.returnPct >= 0 ? "+" : ""}${result.returnPct.toStringAsFixed(2)}%',
            style: TextStyle(color: retColor, fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        const SizedBox(width: 12),
        // Performance column
        Expanded(
          child: _MetricCol(items: [
            ('Equity', result.finalEquity.toStringAsFixed(0)),
            ('Trades', '${result.totalTrades} (${result.winRate.toStringAsFixed(0)}%W)'),
            ('PF', result.profitFactor.isFinite ? result.profitFactor.toStringAsFixed(2) : '-'),
            ('Expect', m.expectancy.toStringAsFixed(2)),
          ]),
        ),
        // Risk column
        Expanded(
          child: _MetricCol(items: [
            ('MaxDD', '${m.maxDrawdownPct.toStringAsFixed(1)}%'),
            ('Sharpe', m.sharpe.toStringAsFixed(2)),
            ('Sortino', m.sortino.toStringAsFixed(2)),
            ('Calmar', m.calmar.toStringAsFixed(2)),
          ]),
        ),
        // Streaks column
        Expanded(
          child: _MetricCol(items: [
            ('WinStr', '${m.longestWinStreak}'),
            ('LossStr', '${m.longestLossStreak}'),
            ('AvgW', m.avgWin.toStringAsFixed(2)),
            ('AvgL', m.avgLoss.toStringAsFixed(2)),
          ]),
        ),
        // Fees & MFE/MAE column
        Expanded(
          child: _MetricCol(items: [
            ('Fees', result.totalFees.toStringAsFixed(1)),
            ('Ulcer', m.ulcerIndex.toStringAsFixed(2)),
            ('MFE', '${m.avgMfe.toStringAsFixed(2)}%'),
            ('MAE', '${m.avgMae.toStringAsFixed(2)}%'),
          ]),
        ),
        _ChartToggles(
          markersMode: markersMode,
          indicatorsVisible: indicatorsVisible,
          equityVisible: equityVisible,
          onMarkersModeChanged: onMarkersModeChanged,
          onIndicatorsVisibleChanged: onIndicatorsVisibleChanged,
          onEquityVisibleChanged: onEquityVisibleChanged,
        ),
      ],
    );
  }
}

class _MetricCol extends StatelessWidget {
  final List<(String, String)> items;
  const _MetricCol({required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (label, value) in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              children: [
                SizedBox(
                  width: 48,
                  child: Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ),
                Flexible(
                  child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 10)),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ErrorBar extends StatelessWidget {
  final String message;
  const _ErrorBar({required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.error_outline, color: Colors.red, size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Error: $message',
              style: const TextStyle(color: Colors.red, fontSize: 11),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
