import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TradeRow {
  final int entryTime;
  final int exitTime;
  final double entryPrice;
  final double exitPrice;
  final double qty;
  final double pnl;
  final double pnlPct;
  final double feeUsdt;
  final String reason;
  final String botId;

  const TradeRow({
    required this.entryTime,
    required this.exitTime,
    required this.entryPrice,
    required this.exitPrice,
    required this.qty,
    required this.pnl,
    required this.pnlPct,
    required this.feeUsdt,
    required this.reason,
    required this.botId,
  });

  factory TradeRow.fromWs(Map<String, dynamic> j) => TradeRow(
        entryTime: (j['entry_time'] as num).toInt(),
        exitTime: (j['exit_time'] as num).toInt(),
        entryPrice: (j['entry_price'] as num).toDouble(),
        exitPrice: (j['exit_price'] as num).toDouble(),
        qty: (j['qty'] as num).toDouble(),
        pnl: (j['pnl'] as num).toDouble(),
        pnlPct: (j['pnl_pct'] as num?)?.toDouble() ?? 0.0,
        feeUsdt: (j['fee_usdt'] as num?)?.toDouble() ?? 0.0,
        reason: j['reason'] as String? ?? '',
        botId: j['bot_id'] as String? ?? 'total',
      );
}

class TradesTable extends StatefulWidget {
  final List<TradeRow> trades;
  final Map<String, Color> botColors;

  const TradesTable({super.key, required this.trades, this.botColors = const {}});

  @override
  State<TradesTable> createState() => _TradesTableState();
}

class _TradesTableState extends State<TradesTable> {
  int _sortCol = 1; // default: entry time
  bool _sortAsc = false; // newest first
  String? _botFilter;

  List<TradeRow> get _sorted {
    final list = _botFilter == null
        ? List<TradeRow>.from(widget.trades)
        : widget.trades.where((t) => t.botId == _botFilter).toList();

    int cmp(TradeRow a, TradeRow b) {
      int r;
      switch (_sortCol) {
        case 0: r = a.botId.compareTo(b.botId); break;
        case 1: r = a.entryTime.compareTo(b.entryTime); break;
        case 2: r = a.exitTime.compareTo(b.exitTime); break;
        case 3: r = a.entryPrice.compareTo(b.entryPrice); break;
        case 4: r = a.exitPrice.compareTo(b.exitPrice); break;
        case 5: r = a.qty.compareTo(b.qty); break;
        case 6: r = a.pnl.compareTo(b.pnl); break;
        case 7: r = a.pnlPct.compareTo(b.pnlPct); break;
        case 8: r = a.reason.compareTo(b.reason); break;
        default: r = 0;
      }
      return _sortAsc ? r : -r;
    }

    list.sort(cmp);
    return list;
  }

  void _setSort(int col) {
    setState(() {
      if (_sortCol == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortCol = col;
        _sortAsc = false;
      }
    });
  }

  String _fmtTime(int unixSec) {
    final dt = DateTime.fromMillisecondsSinceEpoch(unixSec * 1000, isUtc: true);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _exportCsv() async {
    final csv = StringBuffer()
      ..writeln('bot_id,entry_time,exit_time,entry_price,exit_price,qty,pnl,pnl_pct,fee_usdt,reason');
    for (final t in _sorted) {
      csv.writeln([
        t.botId,
        _fmtTime(t.entryTime),
        _fmtTime(t.exitTime),
        t.entryPrice.toStringAsFixed(6),
        t.exitPrice.toStringAsFixed(6),
        t.qty.toStringAsFixed(8),
        t.pnl.toStringAsFixed(4),
        t.pnlPct.toStringAsFixed(4),
        t.feeUsdt.toStringAsFixed(4),
        t.reason,
      ].join(','));
    }

    final dir = Directory('${Directory.current.path}/exports');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final ts = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final path = '${dir.path}/trades_$ts.csv';
    await File(path).writeAsString(csv.toString());

    await Clipboard.setData(ClipboardData(text: path));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF26a69a),
        content: Text('Exported ${_sorted.length} trades → $path (path copied)',
            style: const TextStyle(color: Colors.black, fontSize: 12)),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final trades = _sorted;
    final bots = widget.trades.map((t) => t.botId).toSet().toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Toolbar ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
          child: Row(
            children: [
              Text('${trades.length} trades',
                  style: const TextStyle(color: Color(0xFF787B86), fontSize: 11, letterSpacing: 0.5)),
              const SizedBox(width: 16),
              if (bots.length > 1) ...[
                const Text('Bot:', style: TextStyle(color: Color(0xFF787B86), fontSize: 11)),
                const SizedBox(width: 4),
                DropdownButton<String?>(
                  value: _botFilter,
                  isDense: true,
                  underline: const SizedBox(),
                  style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 11),
                  dropdownColor: const Color(0xFF1E222D),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All')),
                    ...bots.map((b) => DropdownMenuItem(value: b, child: Text(b))),
                  ],
                  onChanged: (v) => setState(() => _botFilter = v),
                ),
              ],
              const Spacer(),
              if (trades.isNotEmpty)
                TextButton.icon(
                  onPressed: _exportCsv,
                  icon: const Icon(Icons.file_download_outlined, size: 14),
                  label: const Text('Export CSV', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF26a69a)),
                ),
            ],
          ),
        ),
        // ── Table ───────────────────────────────────────────────
        Expanded(
          child: trades.isEmpty
              ? const Center(
                  child: Text('No trades yet',
                      style: TextStyle(color: Color(0xFF787B86), fontSize: 12)),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width,
                    child: ListView.builder(
                      itemCount: trades.length + 1,
                      itemBuilder: (ctx, i) {
                        if (i == 0) return _header();
                        return _row(trades[i - 1], i.isEven);
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _header() {
    Widget col(String label, int idx, {double width = 90, TextAlign align = TextAlign.left}) {
      final isSort = _sortCol == idx;
      return InkWell(
        onTap: () => _setSort(idx),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisAlignment: align == TextAlign.right ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                      color: isSort ? const Color(0xFF26a69a) : const Color(0xFF787B86),
                      fontSize: 10,
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w600,
                    )),
                if (isSort)
                  Icon(_sortAsc ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      size: 14, color: const Color(0xFF26a69a)),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF131722),
      child: Row(
        children: [
          col('BOT', 0, width: 110),
          col('ENTRY', 1, width: 130),
          col('EXIT', 2, width: 130),
          col('ENTRY \$', 3, width: 90, align: TextAlign.right),
          col('EXIT \$', 4, width: 90, align: TextAlign.right),
          col('QTY', 5, width: 80, align: TextAlign.right),
          col('P&L', 6, width: 90, align: TextAlign.right),
          col('P&L %', 7, width: 70, align: TextAlign.right),
          col('REASON', 8, width: 110),
        ],
      ),
    );
  }

  Widget _row(TradeRow t, bool alt) {
    final pnlColor = t.pnl >= 0 ? const Color(0xFF26a69a) : const Color(0xFFef5350);
    final botColor = widget.botColors[t.botId] ?? const Color(0xFF787B86);

    Widget cell(String text, {double width = 90, Color? color, TextAlign align = TextAlign.left, FontWeight? weight}) {
      return SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(text,
              textAlign: align,
              style: TextStyle(
                color: color ?? const Color(0xFFD9D9D9),
                fontSize: 11,
                fontWeight: weight,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
      );
    }

    return Container(
      color: alt ? const Color(0xFF1A1D26) : const Color(0xFF1E222D),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: botColor, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(t.botId,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 11)),
                  ),
                ],
              ),
            ),
          ),
          cell(_fmtTime(t.entryTime), width: 130),
          cell(_fmtTime(t.exitTime), width: 130),
          cell(t.entryPrice.toStringAsFixed(2), width: 90, align: TextAlign.right),
          cell(t.exitPrice.toStringAsFixed(2), width: 90, align: TextAlign.right),
          cell(t.qty.toStringAsFixed(4), width: 80, align: TextAlign.right),
          cell('${t.pnl >= 0 ? '+' : ''}${t.pnl.toStringAsFixed(2)}',
              width: 90, align: TextAlign.right, color: pnlColor, weight: FontWeight.w600),
          cell('${t.pnlPct >= 0 ? '+' : ''}${t.pnlPct.toStringAsFixed(2)}%',
              width: 70, align: TextAlign.right, color: pnlColor),
          cell(t.reason, width: 110, color: const Color(0xFF787B86)),
        ],
      ),
    );
  }
}
