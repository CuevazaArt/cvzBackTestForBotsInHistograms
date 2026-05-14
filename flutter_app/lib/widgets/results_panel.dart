import 'package:flutter/material.dart';
import 'package:backtester_shell/widgets/trades_table.dart';

/// Displays backtest results in tabs: Summary / Trades / Per-Bot.
class ResultsPanel extends StatefulWidget {
  final Map<String, dynamic> data;
  final Map<String, dynamic>? perBot; // {bot_id: {metric: value}}
  final List<TradeRow> trades;
  final VoidCallback? onExportAll;
  final VoidCallback? onSavePreset;

  const ResultsPanel({
    super.key,
    required this.data,
    this.perBot,
    this.trades = const [],
    this.onExportAll,
    this.onSavePreset,
  });

  // ── Bot colors (must match JS BOT_COLORS order) ───────────────
  static const botColors = [
    Color(0xFF2196F3), // total / blue
    Color(0xFFFF9800), // orange
    Color(0xFFE040FB), // purple
    Color(0xFF00E676), // green
    Color(0xFFFF5252), // red
    Color(0xFFFFD740), // amber
    Color(0xFF40C4FF), // light blue
    Color(0xFF69F0AE), // teal
  ];

  @override
  State<ResultsPanel> createState() => _ResultsPanelState();
}

class _ResultsPanelState extends State<ResultsPanel> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Map<String, Color> _botColorMap() {
    final perBot = widget.perBot ?? {};
    final ids = perBot.keys.toList();
    final m = <String, Color>{'total': ResultsPanel.botColors[0]};
    for (int i = 0; i < ids.length; i++) {
      m[ids[i]] = ResultsPanel.botColors[(i + 1) % ResultsPanel.botColors.length];
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final summary = (widget.data['summary'] as Map<String, dynamic>?) ?? widget.data;

    return Container(
      color: const Color(0xFF1E222D),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Tabs + actions ────────────────────────────────────
          Container(
            color: const Color(0xFF131722),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    controller: _tab,
                    isScrollable: true,
                    indicatorColor: const Color(0xFF26a69a),
                    indicatorSize: TabBarIndicatorSize.label,
                    labelColor: const Color(0xFF26a69a),
                    unselectedLabelColor: const Color(0xFF787B86),
                    labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8),
                    tabs: [
                      const Tab(height: 28, text: 'SUMMARY'),
                      Tab(height: 28, text: 'TRADES (${widget.trades.length})'),
                      const Tab(height: 28, text: 'PER-BOT'),
                    ],
                  ),
                ),
                if (widget.onSavePreset != null)
                  IconButton(
                    iconSize: 16,
                    tooltip: 'Save current config as preset',
                    icon: const Icon(Icons.bookmark_add_outlined, color: Color(0xFF787B86)),
                    onPressed: widget.onSavePreset,
                  ),
                if (widget.onExportAll != null)
                  IconButton(
                    iconSize: 16,
                    tooltip: 'Export all (CSV bundle)',
                    icon: const Icon(Icons.archive_outlined, color: Color(0xFF787B86)),
                    onPressed: widget.onExportAll,
                  ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          // ── Tab content ───────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _GlobalStrip(summary: summary),
                TradesTable(trades: widget.trades, botColors: _botColorMap()),
                _PerBotTable(perBot: widget.perBot ?? {}),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Global summary strip ──────────────────────────────────────────

class _GlobalStrip extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _GlobalStrip({required this.summary});

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _Metric('Return',   _pct(summary['total_return_pct']), _retColor(summary['total_return_pct'])),
      _Metric('Trades',   '${summary['trades'] ?? 0}',       const Color(0xFFD9D9D9)),
      _Metric('Win Rate', _pct(summary['win_rate_pct']),     const Color(0xFF26a69a)),
      _Metric('Pf',       _f2(summary['profit_factor']),     const Color(0xFFD9D9D9)),
      _Metric('Max DD',   _pct(summary['max_drawdown_pct']), const Color(0xFFef5350)),
      _Metric('Fees',     '\$${_f2(summary['total_fees_usdt'])}', const Color(0xFF787B86)),
      _Metric('Equity',   '\$${_f2(summary['final_equity'])}',    const Color(0xFFD9D9D9)),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
        child: Wrap(
          spacing: 28,
          runSpacing: 12,
          children: metrics.map((m) => _MetricChip(m)).toList(),
        ),
      ),
    );
  }

  String _pct(dynamic v) => v == null ? '—' : '${(v as num).toStringAsFixed(2)}%';
  String _f2(dynamic v)  => v == null ? '—' : (v as num).toStringAsFixed(2);
  Color _retColor(dynamic v) {
    if (v == null) return const Color(0xFFD9D9D9);
    return (v as num) >= 0 ? const Color(0xFF26a69a) : const Color(0xFFef5350);
  }
}

// ── Per-bot comparison table ──────────────────────────────────────

class _PerBotTable extends StatefulWidget {
  final Map<String, dynamic> perBot;
  const _PerBotTable({required this.perBot});

  @override
  State<_PerBotTable> createState() => _PerBotTableState();
}

class _PerBotTableState extends State<_PerBotTable> {
  int _sortCol = 1; // default: Return
  bool _sortAsc = false;

  static const _colKeys = ['bot_id', 'total_return_pct', 'trades', 'win_rate_pct', 'profit_factor', 'final_equity', 'total_pnl', 'total_fees_usdt'];
  static const _colLabels = ['BOT', 'RETURN', 'TRADES', 'WIN%', 'PF', 'EQUITY', 'P&L', 'FEES'];

  @override
  Widget build(BuildContext context) {
    if (widget.perBot.isEmpty) {
      return const Center(child: Text('No per-bot data', style: TextStyle(color: Color(0xFF787B86), fontSize: 12)));
    }

    final bots = widget.perBot.values.map((v) => v as Map<String, dynamic>).toList();
    final key = _colKeys[_sortCol];
    bots.sort((a, b) {
      final av = a[key];
      final bv = b[key];
      int r;
      if (av is num && bv is num) {
        r = av.compareTo(bv);
      } else {
        r = (av?.toString() ?? '').compareTo(bv?.toString() ?? '');
      }
      return _sortAsc ? r : -r;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: const Color(0xFF131722),
          child: Row(
            children: List.generate(_colLabels.length, (i) => _headerCell(i)),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: bots.length,
            itemBuilder: (ctx, i) => _row(bots[i], i),
          ),
        ),
      ],
    );
  }

  Widget _headerCell(int idx) {
    final isSort = _sortCol == idx;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() {
          if (_sortCol == idx) {
            _sortAsc = !_sortAsc;
          } else {
            _sortCol = idx;
            _sortAsc = false;
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              Text(_colLabels[idx],
                  style: TextStyle(
                    color: isSort ? const Color(0xFF26a69a) : const Color(0xFF787B86),
                    fontSize: 10,
                    letterSpacing: 0.8,
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

  Widget _row(Map<String, dynamic> bot, int rowIdx) {
    final color = ResultsPanel.botColors[(rowIdx + 1) % ResultsPanel.botColors.length];
    final ret = (bot['total_return_pct'] as num?)?.toDouble() ?? 0.0;
    final retColor = ret >= 0 ? const Color(0xFF26a69a) : const Color(0xFFef5350);
    final pnl = (bot['total_pnl'] as num?)?.toDouble() ?? 0.0;
    final pnlColor = pnl >= 0 ? const Color(0xFF26a69a) : const Color(0xFFef5350);

    Widget cell(String text, {Color color = const Color(0xFFD9D9D9), FontWeight? weight}) {
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(text,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: weight,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
        ),
      );
    }

    return Container(
      color: rowIdx.isEven ? const Color(0xFF1A1D26) : const Color(0xFF1E222D),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(bot['bot_id']?.toString() ?? '—',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 11)),
                ),
              ]),
            ),
          ),
          cell('${ret.toStringAsFixed(2)}%', color: retColor, weight: FontWeight.w600),
          cell('${bot['trades'] ?? 0}'),
          cell('${(bot['win_rate_pct'] as num?)?.toStringAsFixed(1) ?? '—'}%', color: const Color(0xFF26a69a)),
          cell((bot['profit_factor'] as num?)?.toStringAsFixed(2) ?? '—'),
          cell('\$${(bot['final_equity'] as num?)?.toStringAsFixed(2) ?? '—'}'),
          cell('${pnl >= 0 ? '+' : ''}\$${pnl.toStringAsFixed(2)}', color: pnlColor),
          cell('\$${(bot['total_fees_usdt'] as num?)?.toStringAsFixed(2) ?? '—'}',
              color: const Color(0xFF787B86)),
        ],
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────

class _Metric {
  final String label;
  final String value;
  final Color color;
  const _Metric(this.label, this.value, this.color);
}

class _MetricChip extends StatelessWidget {
  final _Metric m;
  const _MetricChip(this.m);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(m.label, style: const TextStyle(color: Color(0xFF787B86), fontSize: 10, letterSpacing: 0.8)),
      const SizedBox(height: 4),
      Text(m.value, style: TextStyle(color: m.color, fontSize: 17, fontWeight: FontWeight.w700)),
    ],
  );
}
