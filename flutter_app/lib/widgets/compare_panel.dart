// CompareePanel — side-by-side comparison of multiple stored backtest runs.
//
// Renders two widgets stacked vertically:
//
//   1. A metrics table where each row is a metric and each column is a run.
//      The best value in each row is highlighted to make rankings obvious.
//   2. An overlaid equity curve plot drawn with CustomPainter, each run a
//      different color, normalized to a shared time axis so curves with
//      different lengths still line up.
//
// The widget is fed a list of `runs` maps with the exact shape returned by
// `POST /api/backtest/compare`, so the parent screen only needs to call the
// API and forward the result.

import 'package:flutter/material.dart';


/// One row in the compare metrics table. ``bestIsLowest`` is true for
/// drawdown-like metrics where a smaller value is "better" — we use it to
/// pick which run gets the highlight in that row.
class CompareMetric {
  final String label;
  final String key;
  final bool bestIsLowest;
  final int decimals;
  final String suffix;
  const CompareMetric({
    required this.label,
    required this.key,
    this.bestIsLowest = false,
    this.decimals = 2,
    this.suffix = '',
  });
}


/// Default metric ordering used when the parent does not override.
const List<CompareMetric> kDefaultCompareMetrics = [
  CompareMetric(label: 'Final equity',  key: 'final_equity',      decimals: 2),
  CompareMetric(label: 'Total return %',key: 'total_return_pct',  decimals: 2, suffix: '%'),
  CompareMetric(label: 'Max DD %',      key: 'max_drawdown_pct',  decimals: 2, suffix: '%', bestIsLowest: true),
  CompareMetric(label: 'Win rate %',    key: 'win_rate_pct',      decimals: 2, suffix: '%'),
  CompareMetric(label: 'Profit factor', key: 'profit_factor',     decimals: 3),
  CompareMetric(label: 'Trades',        key: 'trades',            decimals: 0),
  CompareMetric(label: 'Sharpe',        key: 'sharpe_ratio',      decimals: 3),
  CompareMetric(label: 'Sortino',       key: 'sortino_ratio',     decimals: 3),
  CompareMetric(label: 'Calmar',        key: 'calmar_ratio',      decimals: 3),
  CompareMetric(label: 'CAGR %',        key: 'cagr_pct',          decimals: 2, suffix: '%'),
];


class ComparePanel extends StatelessWidget {
  /// Exactly the `runs` list from `/api/backtest/compare`.
  final List<Map<String, dynamic>> runs;
  final List<CompareMetric> metrics;
  final VoidCallback? onAddRun;
  final ValueChanged<String>? onRemoveRun;

  const ComparePanel({
    super.key,
    required this.runs,
    this.metrics = kDefaultCompareMetrics,
    this.onAddRun,
    this.onRemoveRun,
  });

  /// Fixed palette so two runs in different positions get the same color
  /// each time (helps the eye lock onto a strategy across re-renders).
  static const _palette = <Color>[
    Color(0xFF4F8EF7),
    Color(0xFFE45858),
    Color(0xFF34C77B),
    Color(0xFFE0A227),
    Color(0xFF9C6FDB),
    Color(0xFFE57FB1),
    Color(0xFF26C6DA),
    Color(0xFFFF8A65),
    Color(0xFF8D6E63),
    Color(0xFF7A8B98),
  ];

  Color _colorFor(int i) => _palette[i % _palette.length];

  @override
  Widget build(BuildContext context) {
    if (runs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          const Icon(Icons.compare, size: 32, color: Colors.grey),
          const SizedBox(height: 8),
          const Text(
            'No runs selected.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 8),
          if (onAddRun != null)
            ElevatedButton.icon(
              onPressed: onAddRun,
              icon: const Icon(Icons.add),
              label: const Text('Add run'),
            ),
        ]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 8),
        _MetricsTable(
          runs: runs,
          metrics: metrics,
          colorFor: _colorFor,
        ),
        const SizedBox(height: 16),
        const Text(
          'Equity curves',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 260,
          child: _EquityOverlayChart(runs: runs, colorFor: _colorFor),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Text(
          '${runs.length} run${runs.length == 1 ? '' : 's'} compared',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        if (onAddRun != null)
          OutlinedButton.icon(
            onPressed: onAddRun,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add run'),
          ),
      ],
    );
  }
}


// ──────────────────────────────────────────────────────────────────────────
// Metrics table
// ──────────────────────────────────────────────────────────────────────────


class _MetricsTable extends StatelessWidget {
  final List<Map<String, dynamic>> runs;
  final List<CompareMetric> metrics;
  final Color Function(int) colorFor;

  const _MetricsTable({
    required this.runs,
    required this.metrics,
    required this.colorFor,
  });

  double? _value(Map<String, dynamic> run, String key) {
    final summary = (run['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final raw = summary[key];
    if (raw is num) return raw.toDouble();
    return null;
  }

  /// Index of the "winning" run for a metric, or null if every value missing.
  int? _bestIndex(CompareMetric m) {
    int? best;
    double? bestVal;
    for (int i = 0; i < runs.length; i++) {
      final v = _value(runs[i], m.key);
      if (v == null) continue;
      if (bestVal == null) {
        best = i;
        bestVal = v;
        continue;
      }
      final isBetter = m.bestIsLowest ? v < bestVal : v > bestVal;
      if (isBetter) {
        best = i;
        bestVal = v;
      }
    }
    return best;
  }

  String _fmt(double? v, CompareMetric m) {
    if (v == null) return '—';
    return '${v.toStringAsFixed(m.decimals)}${m.suffix}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowHeight: 32,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 28,
          columns: [
            const DataColumn(label: Text('Metric')),
            for (int i = 0; i < runs.length; i++)
              DataColumn(
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 10, height: 10,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: colorFor(i),
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    runs[i]['label']?.toString() ?? 'Run ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ]),
              ),
          ],
          rows: metrics.map((m) {
            final best = _bestIndex(m);
            return DataRow(cells: [
              DataCell(Text(
                m.label,
                style: const TextStyle(fontSize: 12),
              )),
              for (int i = 0; i < runs.length; i++)
                DataCell(_metricCell(runs[i], m, isBest: i == best)),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _metricCell(Map<String, dynamic> run, CompareMetric m,
      {required bool isBest}) {
    final v = _value(run, m.key);
    final text = _fmt(v, m);
    final style = TextStyle(
      fontFamily: 'monospace',
      fontSize: 12,
      fontWeight: isBest ? FontWeight.bold : FontWeight.normal,
      color: isBest ? Colors.green.shade700 : null,
    );
    return Text(text, style: style);
  }
}


// ──────────────────────────────────────────────────────────────────────────
// Overlaid equity chart
// ──────────────────────────────────────────────────────────────────────────


class _EquityOverlayChart extends StatelessWidget {
  final List<Map<String, dynamic>> runs;
  final Color Function(int) colorFor;
  const _EquityOverlayChart({required this.runs, required this.colorFor});

  /// Extract `{time, value}` series for each run; entries with missing data
  /// are filtered out so the painter doesn't have to defend against them.
  List<List<Offset>> _seriesFor(BuildContext context) {
    final out = <List<Offset>>[];
    for (final run in runs) {
      final raw = (run['equity_curve_downsampled'] as List?) ?? const [];
      final series = <Offset>[];
      for (final p in raw) {
        if (p is Map) {
          final t = (p['time'] as num?)?.toDouble();
          final v = (p['value'] as num?)?.toDouble();
          if (t != null && v != null) {
            series.add(Offset(t, v));
          }
        }
      }
      out.add(series);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final series = _seriesFor(context);
    final hasData = series.any((s) => s.isNotEmpty);
    if (!hasData) {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No equity curve in the stored runs. Re-run the backtest '
            'to populate it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(6),
      ),
      child: CustomPaint(
        painter: _EquityOverlayPainter(
          series: series,
          colors: List<Color>.generate(series.length, colorFor),
        ),
        size: const Size(double.infinity, 260),
      ),
    );
  }
}


class _EquityOverlayPainter extends CustomPainter {
  final List<List<Offset>> series;
  final List<Color> colors;
  _EquityOverlayPainter({required this.series, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    // Compute global value range to fit the y-axis.
    double minV = double.infinity, maxV = -double.infinity;
    double minT = double.infinity, maxT = -double.infinity;
    for (final s in series) {
      for (final p in s) {
        if (p.dy < minV) minV = p.dy;
        if (p.dy > maxV) maxV = p.dy;
        if (p.dx < minT) minT = p.dx;
        if (p.dx > maxT) maxT = p.dx;
      }
    }
    if (maxV == minV || maxT == minT) return;
    const padding = 8.0;
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;

    // Reference horizontal line at the starting equity of each run helps the
    // eye spot which run is in profit at any given x.
    final basePaint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 0.6;
    for (int i = 0; i < series.length; i++) {
      if (series[i].isEmpty) continue;
      final v0 = series[i].first.dy;
      final y = padding + h - ((v0 - minV) / (maxV - minV)) * h;
      canvas.drawLine(
        Offset(padding, y),
        Offset(padding + w, y),
        basePaint..color = colors[i].withValues(alpha: 0.18),
      );
    }

    for (int i = 0; i < series.length; i++) {
      final s = series[i];
      if (s.isEmpty) continue;
      final paint = Paint()
        ..color = colors[i]
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (int k = 0; k < s.length; k++) {
        final p = s[k];
        final x = padding + ((p.dx - minT) / (maxT - minT)) * w;
        final y = padding + h - ((p.dy - minV) / (maxV - minV)) * h;
        if (k == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_EquityOverlayPainter old) =>
      old.series != series || old.colors != colors;
}
