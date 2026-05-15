import 'package:flutter/material.dart';
import '../../models/backtest_result.dart';

class StatsTab extends StatelessWidget {
  final BacktestResult? result;
  const StatsTab({super.key, this.result});

  @override
  Widget build(BuildContext context) {
    if (result == null) {
      return const Center(
          child: Text('Run a backtest to see stats.',
              style: TextStyle(color: Color(0xFF787B86), fontSize: 12)));
    }
    final s = result!.summary;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [
          _Stat('Return',        '${s.totalReturnPct.toStringAsFixed(2)}%', s.totalReturnPct >= 0),
          _Stat('Max DD',        '${s.maxDrawdownPct.toStringAsFixed(2)}%', s.maxDrawdownPct >= 0),
          _Stat('Trades',        '${s.trades}',                             null),
          _Stat('Win rate',      '${s.winRatePct.toStringAsFixed(1)}%',     s.winRatePct >= 50),
          _Stat('Profit factor', s.profitFactor.toStringAsFixed(2),         s.profitFactor >= 1),
          _Stat('Winners',       '${s.winners}',                             true),
          _Stat('Losers',        '${s.losers}',                              false),
          _Stat('Avg win',       '\$${s.avgWinUsdt.toStringAsFixed(2)}',    true),
          _Stat('Avg loss',      '\$${s.avgLossUsdt.toStringAsFixed(2)}',   false),
          _Stat('Total fees',    '\$${s.totalFeesUsdt.toStringAsFixed(2)}', null),
          _Stat('Final equity',  '\$${s.finalEquity.toStringAsFixed(2)}',   null),
          _Stat('Peak equity',   '\$${s.peakEquity.toStringAsFixed(2)}',    null),
          _Stat('Rejected',      '${s.rejectedOrders}',                     null),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final bool? positive; // null = neutral

  const _Stat(this.label, this.value, this.positive);

  Color _color() {
    if (positive == null) return const Color(0xFFD1D4DC);
    return positive! ? const Color(0xFF26A69A) : const Color(0xFFEF5350);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 130,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF787B86))),
        Text(value,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _color())),
      ]),
    );
  }
}
