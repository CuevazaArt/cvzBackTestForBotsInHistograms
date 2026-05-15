import 'package:flutter/material.dart';
import '../../models/backtest_result.dart';

class TradesTab extends StatelessWidget {
  final List<TradeResult> trades;
  const TradesTab({super.key, required this.trades});

  @override
  Widget build(BuildContext context) {
    if (trades.isEmpty) {
      return const Center(
          child: Text('No trades yet.',
              style: TextStyle(color: Color(0xFF787B86), fontSize: 12)));
    }

    const colWidths = [130.0, 130.0, 90.0, 90.0, 70.0, 80.0, 70.0, 100.0];
    const headers   = ['Entry time', 'Exit time', 'Entry $', 'Exit $', 'Qty', 'PnL', 'PnL %', 'Reason'];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            _Row(
              cells: headers,
              widths: colWidths,
              isHeader: true,
              pnl: 0,
            ),
            const Divider(height: 1),
            // Rows
            ...trades.map((t) => _Row(
                  cells: [
                    _fmtMs(t.entryTime),
                    t.exitTime != null ? _fmtMs(t.exitTime!) : '—',
                    '\$${t.entryPrice.toStringAsFixed(2)}',
                    '\$${t.exitPrice.toStringAsFixed(2)}',
                    t.qty.toStringAsFixed(4),
                    (t.pnl >= 0 ? '+' : '') + '\$${t.pnl.toStringAsFixed(2)}',
                    (t.pnlPct >= 0 ? '+' : '') + '${t.pnlPct.toStringAsFixed(2)}%',
                    t.reason ?? '—',
                  ],
                  widths: colWidths,
                  isHeader: false,
                  pnl: t.pnl,
                )),
          ],
        ),
      ),
    );
  }

  static String _fmtMs(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    return '${dt.year}-${_p(dt.month)}-${_p(dt.day)} ${_p(dt.hour)}:${_p(dt.minute)}';
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}

class _Row extends StatelessWidget {
  final List<String> cells;
  final List<double> widths;
  final bool isHeader;
  final double pnl;

  const _Row({
    required this.cells,
    required this.widths,
    required this.isHeader,
    required this.pnl,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < cells.length; i++)
          SizedBox(
            width: widths[i],
            height: 28,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  cells[i],
                  style: TextStyle(
                    fontSize: isHeader ? 10 : 11,
                    fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
                    color: isHeader
                        ? const Color(0xFF787B86)
                        : i == 5 || i == 6
                            ? (pnl >= 0 ? const Color(0xFF26A69A) : const Color(0xFFEF5350))
                            : const Color(0xFFD1D4DC),
                    fontVariations: const [FontVariation('wght', 400)],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
