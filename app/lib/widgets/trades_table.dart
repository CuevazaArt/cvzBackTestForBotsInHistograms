import 'package:flutter/material.dart';
import '../core/models/trade.dart';

class TradesTable extends StatefulWidget {
  final List<Trade> trades;
  const TradesTable({super.key, required this.trades});

  @override
  State<TradesTable> createState() => _TradesTableState();
}

class _TradesTableState extends State<TradesTable> {
  int _sortColumnIndex = 0;
  bool _sortAscending = true;

  late List<Trade> _sorted;

  @override
  void initState() {
    super.initState();
    _sorted = List.of(widget.trades);
  }

  @override
  void didUpdateWidget(TradesTable old) {
    super.didUpdateWidget(old);
    if (old.trades != widget.trades) {
      _sorted = List.of(widget.trades);
      _applySort();
    }
  }

  void _sort(int col, bool asc) {
    setState(() {
      _sortColumnIndex = col;
      _sortAscending = asc;
      _applySort();
    });
  }

  void _applySort() {
    final m = _sortAscending ? 1 : -1;
    _sorted.sort((a, b) {
      switch (_sortColumnIndex) {
        case 0: return m * a.id.compareTo(b.id);
        case 1: return m * a.side.name.compareTo(b.side.name);
        case 2: return m * a.entryPrice.compareTo(b.entryPrice);
        case 3: return m * a.exitPrice.compareTo(b.exitPrice);
        case 4: return m * a.qty.compareTo(b.qty);
        case 5: return m * a.pnl.compareTo(b.pnl);
        case 6: return m * a.pnlPct.compareTo(b.pnlPct);
        case 7: return m * a.fees.compareTo(b.fees);
        case 8: return m * a.exitReason.name.compareTo(b.exitReason.name);
        default: return 0;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.trades.isEmpty) {
      return const Center(
        child: Text('No trades yet.', style: TextStyle(color: Colors.grey)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          sortColumnIndex: _sortColumnIndex,
          sortAscending: _sortAscending,
          columnSpacing: 16,
          headingRowHeight: 36,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 32,
          columns: [
            DataColumn(label: const Text('#'), numeric: true, onSort: _sort),
            DataColumn(label: const Text('Side'), onSort: _sort),
            DataColumn(label: const Text('Entry'), numeric: true, onSort: _sort),
            DataColumn(label: const Text('Exit'), numeric: true, onSort: _sort),
            DataColumn(label: const Text('Qty'), numeric: true, onSort: _sort),
            DataColumn(label: const Text('PnL'), numeric: true, onSort: _sort),
            DataColumn(label: const Text('PnL %'), numeric: true, onSort: _sort),
            DataColumn(label: const Text('Fees'), numeric: true, onSort: _sort),
            DataColumn(label: const Text('Exit'), onSort: _sort),
          ],
          rows: [
            for (final t in _sorted)
              DataRow(cells: [
                DataCell(Text('${t.id}', style: const TextStyle(fontSize: 12))),
                DataCell(Text(t.side.name, style: const TextStyle(fontSize: 12))),
                DataCell(Text(t.entryPrice.toStringAsFixed(2), style: const TextStyle(fontSize: 12))),
                DataCell(Text(t.exitPrice.toStringAsFixed(2), style: const TextStyle(fontSize: 12))),
                DataCell(Text(t.qty.toStringAsFixed(4), style: const TextStyle(fontSize: 12))),
                DataCell(Text(
                  t.pnl.toStringAsFixed(2),
                  style: TextStyle(fontSize: 12, color: t.pnl >= 0 ? Colors.green : Colors.red),
                )),
                DataCell(Text(
                  '${t.pnlPct.toStringAsFixed(2)}%',
                  style: TextStyle(fontSize: 12, color: t.pnlPct >= 0 ? Colors.green : Colors.red),
                )),
                DataCell(Text(t.fees.toStringAsFixed(2), style: const TextStyle(fontSize: 12))),
                DataCell(Text(t.exitReason.name, style: const TextStyle(fontSize: 12))),
              ]),
          ],
        ),
      ),
    );
  }
}
