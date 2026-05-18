import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../analysis/metrics.dart';
import '../../core/models/backtest_result.dart';
import '../../core/models/candle.dart';
import '../../core/models/trade.dart';
import '../../state/backtest_state.dart';

class ResultsBar extends StatelessWidget {
  final BacktestStatus status;
  final String timeframe;
  final String markersMode;
  final bool indicatorsVisible;
  final bool equityVisible;
  final ValueChanged<String> onMarkersModeChanged;
  final ValueChanged<bool> onIndicatorsVisibleChanged;
  final ValueChanged<bool> onEquityVisibleChanged;

  const ResultsBar({
    super.key,
    required this.status,
    required this.timeframe,
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
            timeframe: timeframe,
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
  final String timeframe;
  final String markersMode;
  final bool indicatorsVisible;
  final bool equityVisible;
  final ValueChanged<String> onMarkersModeChanged;
  final ValueChanged<bool> onIndicatorsVisibleChanged;
  final ValueChanged<bool> onEquityVisibleChanged;

  const _DoneBar({
    required this.result,
    required this.timeframe,
    required this.markersMode,
    required this.indicatorsVisible,
    required this.equityVisible,
    required this.onMarkersModeChanged,
    required this.onIndicatorsVisibleChanged,
    required this.onEquityVisibleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final m = MetricsCalculator.compute(result, timeframe: timeframe);
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
        // Trades table button
        IconButton(
          icon: const Icon(Icons.table_rows_outlined, size: 18),
          tooltip: 'Trade log',
          visualDensity: VisualDensity.compact,
          onPressed: () => _showTradesDialog(context, result),
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

  void _showTradesDialog(BuildContext context, BacktestResult result) {
    showDialog(
      context: context,
      builder: (_) => TradesTableDialog(trades: result.trades),
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

// ─── Sortable Trades Table Dialog ──────────────────────────────────────────

enum _TradeSort { id, entryTime, exitTime, pnl, pnlPct, side, duration }

class TradesTableDialog extends StatefulWidget {
  final List<Trade> trades;
  const TradesTableDialog({super.key, required this.trades});
  @override
  State<TradesTableDialog> createState() => _TradesTableDialogState();
}

class _TradesTableDialogState extends State<TradesTableDialog> {
  _TradeSort _sortBy = _TradeSort.id;
  bool _ascending = true;
  final _tf = DateFormat('MM-dd HH:mm');

  List<Trade> get _sorted {
    final list = List<Trade>.from(widget.trades);
    list.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case _TradeSort.id:
          cmp = a.id.compareTo(b.id);
        case _TradeSort.entryTime:
          cmp = a.entryTimestampMs.compareTo(b.entryTimestampMs);
        case _TradeSort.exitTime:
          cmp = a.exitTimestampMs.compareTo(b.exitTimestampMs);
        case _TradeSort.pnl:
          cmp = a.pnl.compareTo(b.pnl);
        case _TradeSort.pnlPct:
          cmp = a.pnlPct.compareTo(b.pnlPct);
        case _TradeSort.side:
          cmp = a.side.name.compareTo(b.side.name);
        case _TradeSort.duration:
          cmp = a.duration.compareTo(b.duration);
      }
      return _ascending ? cmp : -cmp;
    });
    return list;
  }

  void _onSort(_TradeSort col) {
    setState(() {
      if (_sortBy == col) {
        _ascending = !_ascending;
      } else {
        _sortBy = col;
        _ascending = col == _TradeSort.id || col == _TradeSort.entryTime;
      }
    });
  }

  Widget _header(String label, _TradeSort col, {double? width}) {
    final active = _sortBy == col;
    return InkWell(
      onTap: () => _onSort(col),
      child: SizedBox(
        width: width,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(
              fontSize: 11,
              fontWeight: active ? FontWeight.bold : FontWeight.w600,
              color: active ? Theme.of(context).colorScheme.primary : null,
            )),
            if (active)
              Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward, size: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final trades = _sorted;
    final wins = trades.where((t) => t.isWin).length;
    final totalPnl = trades.fold(0.0, (s, t) => s + t.pnl);

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Trade Log', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 12),
                  Text(
                    '${trades.length} trades  |  $wins W / ${trades.length - wins} L  |  PnL: ${totalPnl.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Column headers
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                ),
                child: Row(
                  children: [
                    SizedBox(width: 36, child: _header('#', _TradeSort.id)),
                    SizedBox(width: 48, child: _header('Side', _TradeSort.side)),
                    SizedBox(width: 90, child: _header('Entry', _TradeSort.entryTime)),
                    SizedBox(width: 90, child: _header('Exit', _TradeSort.exitTime)),
                    const SizedBox(width: 80, child: Text('Entry \$', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                    const SizedBox(width: 80, child: Text('Exit \$', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                    SizedBox(width: 80, child: _header('PnL', _TradeSort.pnl)),
                    SizedBox(width: 60, child: _header('PnL%', _TradeSort.pnlPct)),
                    const SizedBox(width: 50, child: Text('MFE%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                    const SizedBox(width: 50, child: Text('MAE%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
                    SizedBox(width: 70, child: _header('Dur', _TradeSort.duration)),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Scrollable trade rows
              Expanded(
                child: ListView.builder(
                  itemCount: trades.length,
                  itemExtent: 26,
                  itemBuilder: (context, i) {
                    final t = trades[i];
                    final entryDt = DateTime.fromMillisecondsSinceEpoch(t.entryTimestampMs, isUtc: true);
                    final exitDt = DateTime.fromMillisecondsSinceEpoch(t.exitTimestampMs, isUtc: true);
                    final pnlColor = t.isWin ? Colors.green : Colors.red;
                    final dur = t.duration;
                    final durStr = dur.inHours > 0
                        ? '${dur.inHours}h${dur.inMinutes.remainder(60)}m'
                        : '${dur.inMinutes}m';

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      color: i.isEven ? Colors.transparent : Theme.of(context).colorScheme.surfaceContainerLow,
                      child: Row(
                        children: [
                          SizedBox(width: 36, child: Text('${t.id}', style: const TextStyle(fontSize: 10, color: Colors.grey))),
                          SizedBox(
                            width: 48,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: t.side.name == 'long' ? Colors.green.withAlpha(20) : Colors.red.withAlpha(20),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(
                                t.side.name.toUpperCase(),
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: t.side.name == 'long' ? Colors.green : Colors.red),
                              ),
                            ),
                          ),
                          SizedBox(width: 90, child: Text(_tf.format(entryDt), style: const TextStyle(fontSize: 10, fontFamily: 'monospace'))),
                          SizedBox(width: 90, child: Text(_tf.format(exitDt), style: const TextStyle(fontSize: 10, fontFamily: 'monospace'))),
                          SizedBox(width: 80, child: Text(t.entryPrice.toStringAsFixed(2), style: const TextStyle(fontSize: 10, fontFamily: 'monospace'))),
                          SizedBox(width: 80, child: Text(t.exitPrice.toStringAsFixed(2), style: const TextStyle(fontSize: 10, fontFamily: 'monospace'))),
                          SizedBox(
                            width: 80,
                            child: Text(
                              '${t.pnl >= 0 ? "+" : ""}${t.pnl.toStringAsFixed(2)}',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: pnlColor, fontFamily: 'monospace'),
                            ),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text(
                              '${t.pnlPct >= 0 ? "+" : ""}${t.pnlPct.toStringAsFixed(1)}%',
                              style: TextStyle(fontSize: 10, color: pnlColor),
                            ),
                          ),
                          SizedBox(width: 50, child: Text('${t.mfe.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 10))),
                          SizedBox(width: 50, child: Text('${t.mae.toStringAsFixed(1)}%', style: const TextStyle(fontSize: 10))),
                          SizedBox(width: 70, child: Text(durStr, style: const TextStyle(fontSize: 10, color: Colors.grey))),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
