import 'package:flutter/material.dart';

/// Displays a backtest result summary as a horizontal metric strip.
class ResultsPanel extends StatelessWidget {
  final Map<String, dynamic> data;
  const ResultsPanel({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final summary = (data['summary'] as Map<String, dynamic>?) ?? data;

    final metrics = [
      _Metric('Return', _pct(summary['total_return_pct']), _returnColor(summary['total_return_pct'])),
      _Metric('Trades', '${summary['trades'] ?? 0}', const Color(0xFFD9D9D9)),
      _Metric('Win Rate', _pct(summary['win_rate_pct']), const Color(0xFF26a69a)),
      _Metric('Profit Factor', _f2(summary['profit_factor']), const Color(0xFFD9D9D9)),
      _Metric('Max DD', _pct(summary['max_drawdown_pct']), const Color(0xFFef5350)),
      _Metric('Fees', '\$${_f2(summary['total_fees_usdt'])}', const Color(0xFF787B86)),
      _Metric('Final Equity', '\$${_f2(summary['final_equity'])}', const Color(0xFFD9D9D9)),
    ];

    return Container(
      color: const Color(0xFF1E222D),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('RESULTS', style: TextStyle(color: Color(0xFF787B86), fontSize: 10, letterSpacing: 1.2)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 24,
            runSpacing: 8,
            children: metrics.map((m) => _MetricChip(m)).toList(),
          ),
        ],
      ),
    );
  }

  String _pct(dynamic v) => v == null ? '—' : '${(v as num).toStringAsFixed(2)}%';
  String _f2(dynamic v) => v == null ? '—' : (v as num).toStringAsFixed(2);

  Color _returnColor(dynamic v) {
    if (v == null) return const Color(0xFFD9D9D9);
    return (v as num) >= 0 ? const Color(0xFF26a69a) : const Color(0xFFef5350);
  }
}

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
