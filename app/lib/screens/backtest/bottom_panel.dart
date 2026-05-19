import 'package:flutter/material.dart';

import '../../analysis/metrics.dart';
import '../../core/models/backtest_result.dart';
import '../../state/backtest_state.dart';
import '../../widgets/trades_table.dart';
import '../../widgets/equity_curve.dart';

/// Bottom horizontal panel below the chart.
///
/// Shows: [overlay toggles] | [live/done metrics] | [quick actions]
class BottomPanel extends StatelessWidget {
  final BacktestStatus status;
  final String timeframe;
  final bool showMarkers;
  final bool showIndicators;
  final bool showEquity;
  final ValueChanged<bool> onShowMarkersChanged;
  final ValueChanged<bool> onShowIndicatorsChanged;
  final ValueChanged<bool> onShowEquityChanged;

  const BottomPanel({
    super.key,
    required this.status,
    required this.timeframe,
    required this.showMarkers,
    required this.showIndicators,
    required this.showEquity,
    required this.onShowMarkersChanged,
    required this.onShowIndicatorsChanged,
    required this.onShowEquityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: switch (status) {
        BacktestIdle() => _IdleBar(
            showMarkers: showMarkers,
            showIndicators: showIndicators,
            showEquity: showEquity,
            onShowMarkersChanged: onShowMarkersChanged,
            onShowIndicatorsChanged: onShowIndicatorsChanged,
            onShowEquityChanged: onShowEquityChanged,
          ),
        BacktestRunning() => _RunningBar(
            status: status as BacktestRunning,
            showMarkers: showMarkers,
            showIndicators: showIndicators,
            showEquity: showEquity,
            onShowMarkersChanged: onShowMarkersChanged,
            onShowIndicatorsChanged: onShowIndicatorsChanged,
            onShowEquityChanged: onShowEquityChanged,
          ),
        BacktestDone(:final result) => _DoneBar(
            result: result,
            timeframe: timeframe,
            showMarkers: showMarkers,
            showIndicators: showIndicators,
            showEquity: showEquity,
            onShowMarkersChanged: onShowMarkersChanged,
            onShowIndicatorsChanged: onShowIndicatorsChanged,
            onShowEquityChanged: onShowEquityChanged,
          ),
        BacktestErrorState(:final message) => _ErrorBar(message: message),
      },
    );
  }
}

// ─── Overlay toggle chips ──────────────────────────────────────────

class _OverlayToggles extends StatelessWidget {
  final bool showMarkers;
  final bool showIndicators;
  final bool showEquity;
  final ValueChanged<bool> onShowMarkersChanged;
  final ValueChanged<bool> onShowIndicatorsChanged;
  final ValueChanged<bool> onShowEquityChanged;

  const _OverlayToggles({
    required this.showMarkers,
    required this.showIndicators,
    required this.showEquity,
    required this.onShowMarkersChanged,
    required this.onShowIndicatorsChanged,
    required this.onShowEquityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ToggleChip(
          label: 'Markers',
          icon: Icons.place,
          active: showMarkers,
          color: Colors.green,
          onToggle: () => onShowMarkersChanged(!showMarkers),
        ),
        const SizedBox(width: 4),
        _ToggleChip(
          label: 'Indicators',
          icon: Icons.show_chart,
          active: showIndicators,
          color: Colors.amber,
          onToggle: () => onShowIndicatorsChanged(!showIndicators),
        ),
        const SizedBox(width: 4),
        _ToggleChip(
          label: 'Equity',
          icon: Icons.trending_up,
          active: showEquity,
          color: Colors.blue,
          onToggle: () => onShowEquityChanged(!showEquity),
        ),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onToggle;

  const _ToggleChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: active ? color.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: active ? color.withAlpha(100) : Colors.grey.withAlpha(60),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: active ? color : Colors.grey),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: active ? color : Colors.grey,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _MetricPill({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 9, color: Colors.grey)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: SizedBox(
          height: 20,
          child:
              VerticalDivider(width: 1, color: Theme.of(context).dividerColor),
        ),
      );
}

// ─── Bar variants ──────────────────────────────────────────────────

class _IdleBar extends StatelessWidget {
  final bool showMarkers;
  final bool showIndicators;
  final bool showEquity;
  final ValueChanged<bool> onShowMarkersChanged;
  final ValueChanged<bool> onShowIndicatorsChanged;
  final ValueChanged<bool> onShowEquityChanged;

  const _IdleBar({
    required this.showMarkers,
    required this.showIndicators,
    required this.showEquity,
    required this.onShowMarkersChanged,
    required this.onShowIndicatorsChanged,
    required this.onShowEquityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _OverlayToggles(
          showMarkers: showMarkers,
          showIndicators: showIndicators,
          showEquity: showEquity,
          onShowMarkersChanged: onShowMarkersChanged,
          onShowIndicatorsChanged: onShowIndicatorsChanged,
          onShowEquityChanged: onShowEquityChanged,
        ),
        const Spacer(),
        const Text('Ready — configure and run a backtest',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

class _RunningBar extends StatelessWidget {
  final BacktestRunning status;
  final bool showMarkers;
  final bool showIndicators;
  final bool showEquity;
  final ValueChanged<bool> onShowMarkersChanged;
  final ValueChanged<bool> onShowIndicatorsChanged;
  final ValueChanged<bool> onShowEquityChanged;

  const _RunningBar({
    required this.status,
    required this.showMarkers,
    required this.showIndicators,
    required this.showEquity,
    required this.onShowMarkersChanged,
    required this.onShowIndicatorsChanged,
    required this.onShowEquityChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _OverlayToggles(
          showMarkers: showMarkers,
          showIndicators: showIndicators,
          showEquity: showEquity,
          onShowMarkersChanged: onShowMarkersChanged,
          onShowIndicatorsChanged: onShowIndicatorsChanged,
          onShowEquityChanged: onShowEquityChanged,
        ),
        _Divider(),
        _MetricPill(
          label: 'Candle',
          value: '${status.processed} / ${status.total}',
        ),
        _MetricPill(
          label: 'Trades',
          value: '${status.trades.length}',
        ),
        _MetricPill(
          label: 'Equity',
          value: status.lastEquity != null
              ? status.lastEquity!.toStringAsFixed(0)
              : '—',
        ),
        if (status.currentCandle != null) ...[
          _Divider(),
          _MetricPill(
            label: 'O',
            value: status.currentCandle!.open.toStringAsFixed(1),
          ),
          _MetricPill(
            label: 'H',
            value: status.currentCandle!.high.toStringAsFixed(1),
          ),
          _MetricPill(
            label: 'L',
            value: status.currentCandle!.low.toStringAsFixed(1),
          ),
          _MetricPill(
            label: 'C',
            value: status.currentCandle!.close.toStringAsFixed(1),
          ),
        ],
      ],
    );
  }
}

class _DoneBar extends StatelessWidget {
  final BacktestResult result;
  final String timeframe;
  final bool showMarkers;
  final bool showIndicators;
  final bool showEquity;
  final ValueChanged<bool> onShowMarkersChanged;
  final ValueChanged<bool> onShowIndicatorsChanged;
  final ValueChanged<bool> onShowEquityChanged;

  const _DoneBar({
    required this.result,
    required this.timeframe,
    required this.showMarkers,
    required this.showIndicators,
    required this.showEquity,
    required this.onShowMarkersChanged,
    required this.onShowIndicatorsChanged,
    required this.onShowEquityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final m = MetricsCalculator.compute(result, timeframe: timeframe);
    final returnColor = result.returnPct >= 0 ? Colors.green : Colors.red;

    return Row(
      children: [
        _OverlayToggles(
          showMarkers: showMarkers,
          showIndicators: showIndicators,
          showEquity: showEquity,
          onShowMarkersChanged: onShowMarkersChanged,
          onShowIndicatorsChanged: onShowIndicatorsChanged,
          onShowEquityChanged: onShowEquityChanged,
        ),
        _Divider(),
        _MetricPill(
          label: 'Return',
          value:
              '${result.returnPct >= 0 ? "+" : ""}${result.returnPct.toStringAsFixed(2)}%',
          valueColor: returnColor,
        ),
        _MetricPill(
          label: 'Equity',
          value: result.finalEquity.toStringAsFixed(0),
        ),
        _MetricPill(
          label: 'Trades',
          value: '${result.totalTrades}',
        ),
        _MetricPill(
          label: 'Win%',
          value: result.winRate.toStringAsFixed(1),
        ),
        _MetricPill(
          label: 'Sharpe',
          value: m.sharpe.toStringAsFixed(2),
        ),
        _MetricPill(
          label: 'MaxDD',
          value: '${m.maxDrawdownPct.toStringAsFixed(1)}%',
        ),
        _MetricPill(
          label: 'PF',
          value: result.profitFactor.isFinite
              ? result.profitFactor.toStringAsFixed(2)
              : '∞',
        ),
        _Divider(),
        _ActionButton(
          icon: Icons.list_alt,
          label: 'Trades',
          onPressed: () => _showTradesDialog(context),
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: Icons.show_chart,
          label: 'Equity',
          onPressed: () => _showEquityDialog(context),
        ),
        const SizedBox(width: 4),
        _ActionButton(
          icon: Icons.assessment,
          label: 'Full Report',
          onPressed: () => _showFullReport(context),
        ),
      ],
    );
  }

  void _showTradesDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 800,
          height: 500,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('Trades (${result.totalTrades})',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(child: TradesTable(trades: result.trades)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEquityDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: 700,
          height: 400,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Text('Equity Curve',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(child: EquityCurveWidget(equityCurve: result.equityCurve, initialCash: result.initialCash)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFullReport(BuildContext context) {
    final m = MetricsCalculator.compute(result, timeframe: timeframe);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Full Report'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ReportSection(title: 'Performance', items: {
                  'Return': '${result.returnPct.toStringAsFixed(2)}%',
                  'Final equity': '${result.finalEquity.toStringAsFixed(2)} USDT',
                  'Total trades': '${result.totalTrades}',
                  'Win rate': '${result.winRate.toStringAsFixed(1)}%',
                  'Profit factor': result.profitFactor.isFinite
                      ? result.profitFactor.toStringAsFixed(2)
                      : '∞',
                  'Expectancy': m.expectancy.toStringAsFixed(2),
                  'Total fees': '${result.totalFees.toStringAsFixed(2)} USDT',
                }),
                const SizedBox(height: 12),
                _ReportSection(title: 'Risk', items: {
                  'Max drawdown': '${m.maxDrawdownPct.toStringAsFixed(2)}%',
                  'Sharpe': m.sharpe.toStringAsFixed(2),
                  'Sortino': m.sortino.toStringAsFixed(2),
                  'Calmar': m.calmar.toStringAsFixed(2),
                  'Ulcer index': m.ulcerIndex.toStringAsFixed(2),
                  'Recovery factor': m.recoveryFactor.toStringAsFixed(2),
                }),
                const SizedBox(height: 12),
                _ReportSection(title: 'Streaks & MFE/MAE', items: {
                  'Win streak': '${m.longestWinStreak}',
                  'Loss streak': '${m.longestLossStreak}',
                  'Avg win': m.avgWin.toStringAsFixed(2),
                  'Avg loss': m.avgLoss.toStringAsFixed(2),
                  'Avg MFE': '${m.avgMfe.toStringAsFixed(2)}%',
                  'Avg MAE': '${m.avgMae.toStringAsFixed(2)}%',
                }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 13),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: Size.zero,
        ),
      ),
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
        const Icon(Icons.error_outline, size: 16, color: Colors.red),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Error: $message',
            style: const TextStyle(fontSize: 11, color: Colors.red),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ReportSection extends StatelessWidget {
  final String title;
  final Map<String, String> items;

  const _ReportSection({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        for (final e in items.entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(e.key,
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 13)),
                Text(e.value,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
          ),
      ],
    );
  }
}
