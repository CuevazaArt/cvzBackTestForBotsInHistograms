import 'package:flutter/material.dart';

/// Displays backtest results: global summary strip + per-bot comparison table.
class ResultsPanel extends StatelessWidget {
  final Map<String, dynamic> data;
  final Map<String, dynamic>? perBot; // {bot_id: {metric: value}}

  const ResultsPanel({super.key, required this.data, this.perBot});

  // ── Bot colors (must match JS BOT_COLORS order) ───────────────
  static const _botColors = [
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
  Widget build(BuildContext context) {
    final summary = (data['summary'] as Map<String, dynamic>?) ?? data;

    return Container(
      color: const Color(0xFF1E222D),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Global summary strip ─────────────────────────────
          _GlobalStrip(summary: summary),

          // ── Per-bot table (only when multi-bot) ──────────────
          if (perBot != null && perBot!.length > 1)
            Expanded(child: _PerBotTable(perBot: perBot!)),
        ],
      ),
    );
  }
}

// ── Global strip ──────────────────────────────────────────────────

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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('GLOBAL', style: TextStyle(color: Color(0xFF787B86), fontSize: 10, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 24,
            runSpacing: 6,
            children: metrics.map((m) => _MetricChip(m)).toList(),
          ),
        ],
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

class _PerBotTable extends StatelessWidget {
  final Map<String, dynamic> perBot;
  const _PerBotTable({required this.perBot});

  static const _cols = ['Bot', 'Return', 'Trades', 'Win%', 'PF', 'DD', 'Equity'];

  @override
  Widget build(BuildContext context) {
    final bots = perBot.values
        .map((v) => v as Map<String, dynamic>)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Color(0xFF2B2B43), height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: const Text('BOTS', style: TextStyle(color: Color(0xFF787B86), fontSize: 10, letterSpacing: 1.2)),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowHeight: 28,
                dataRowMinHeight: 28,
                dataRowMaxHeight: 36,
                columnSpacing: 20,
                headingRowColor: WidgetStateProperty.all(const Color(0xFF131722)),
                columns: _cols.map((c) => DataColumn(
                  label: Text(c, style: const TextStyle(
                    color: Color(0xFF787B86), fontSize: 10, letterSpacing: 0.8)),
                )).toList(),
                rows: bots.asMap().entries.map((entry) {
                  final i   = entry.key;
                  final bot = entry.value;
                  final color = ResultsPanel._botColors[(i + 1) % ResultsPanel._botColors.length];
                  final ret = (bot['total_return_pct'] as num?)?.toDouble() ?? 0.0;

                  return DataRow(cells: [
                    // Bot name with color dot
                    DataCell(Row(children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Text(bot['bot_id'] as String? ?? '—',
                          style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 12)),
                    ])),
                    DataCell(Text(
                      '${ret.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: ret >= 0 ? const Color(0xFF26a69a) : const Color(0xFFef5350),
                        fontSize: 12, fontWeight: FontWeight.w600,
                      ),
                    )),
                    DataCell(Text('${bot['trades'] ?? 0}',
                        style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 12))),
                    DataCell(Text(
                      '${(bot['win_rate_pct'] as num?)?.toStringAsFixed(1) ?? '—'}%',
                      style: const TextStyle(color: Color(0xFF26a69a), fontSize: 12),
                    )),
                    DataCell(Text(
                      (bot['profit_factor'] as num?)?.toStringAsFixed(2) ?? '—',
                      style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 12),
                    )),
                    DataCell(Text('—', style: const TextStyle(color: Color(0xFFef5350), fontSize: 12))),
                    DataCell(Text(
                      '\$${(bot['final_equity'] as num?)?.toStringAsFixed(2) ?? '—'}',
                      style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 12),
                    )),
                  ]);
                }).toList(),
              ),
            ),
          ),
        ),
      ],
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
      Text(m.label, style: const TextStyle(color: Color(0xFF787B86), fontSize: 10)),
      const SizedBox(height: 2),
      Text(m.value, style: TextStyle(color: m.color, fontSize: 15, fontWeight: FontWeight.w600)),
    ],
  );
}
