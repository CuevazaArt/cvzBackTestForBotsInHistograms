import 'package:flutter/material.dart';

/// One row in a parameter sweep — generic enough to feed any optimizer.
class HeatmapTrial {
  final Map<String, num> params;
  final Map<String, double> metrics;
  const HeatmapTrial({required this.params, required this.metrics});
}

/// Interactive 2D heatmap of (paramX, paramY) → metric.
///
/// Builds a grid by binning trial points onto the unique sorted values of
/// each selected axis. Cells with no trials are drawn neutral. Hover/tap
/// surfaces the underlying trial details and the parent can react via
/// [onCellTap].
class OptimizationHeatmap extends StatefulWidget {
  final List<HeatmapTrial> trials;
  final String paramX;
  final String paramY;
  final String metric;
  final ValueChanged<HeatmapTrial>? onCellTap;

  const OptimizationHeatmap({
    super.key,
    required this.trials,
    required this.paramX,
    required this.paramY,
    required this.metric,
    this.onCellTap,
  });

  @override
  State<OptimizationHeatmap> createState() => _OptimizationHeatmapState();
}

class _OptimizationHeatmapState extends State<OptimizationHeatmap> {
  ({int x, int y})? _hover;

  @override
  Widget build(BuildContext context) {
    final trials = widget.trials;
    if (trials.isEmpty) {
      return const Center(child: Text('No trials yet — run an optimization.'));
    }

    final xs = _uniqueSorted(trials.map((t) => t.params[widget.paramX]));
    final ys = _uniqueSorted(trials.map((t) => t.params[widget.paramY]));

    if (xs.length < 2 || ys.length < 2) {
      return Center(
        child: Text(
          'Heatmap needs at least 2 distinct values for both ${widget.paramX} '
          'and ${widget.paramY}.',
          textAlign: TextAlign.center,
        ),
      );
    }

    // Bucket trials onto the (x,y) grid; if multiple land in a cell keep the
    // best one by the selected metric.
    final cells = List.generate(
      ys.length,
      (_) => List<HeatmapTrial?>.filled(xs.length, null),
    );
    double? vMin, vMax;
    for (final t in trials) {
      final px = t.params[widget.paramX];
      final py = t.params[widget.paramY];
      final m = t.metrics[widget.metric];
      if (px == null || py == null || m == null) continue;
      final xi = xs.indexOf(px);
      final yi = ys.indexOf(py);
      if (xi < 0 || yi < 0) continue;
      final existing = cells[yi][xi];
      final existingMetric = existing?.metrics[widget.metric];
      if (existing == null || (existingMetric != null && m > existingMetric)) {
        cells[yi][xi] = t;
      }
      vMin = (vMin == null || m < vMin) ? m : vMin;
      vMax = (vMax == null || m > vMax) ? m : vMax;
    }
    vMin ??= 0;
    vMax ??= 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        const labelGutter = 60.0;
        final gridW = constraints.maxWidth - labelGutter;
        final gridH = constraints.maxHeight - labelGutter - 32;
        final cellW = (gridW / xs.length).clamp(8.0, 80.0);
        final cellH = (gridH / ys.length).clamp(8.0, 80.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${widget.metric}  ·  '
                'min ${vMin!.toStringAsFixed(2)}  /  max ${vMax!.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  _AxisLabels(values: ys.reversed.toList(), cellSize: cellH, axis: Axis.vertical),
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: MouseRegion(
                            onExit: (_) => setState(() => _hover = null),
                            child: GestureDetector(
                              onTapUp: (d) {
                                final xi = (d.localPosition.dx / cellW).floor();
                                final yi =
                                    ys.length - 1 - (d.localPosition.dy / cellH).floor();
                                if (xi < 0 || xi >= xs.length) return;
                                if (yi < 0 || yi >= ys.length) return;
                                final trial = cells[yi][xi];
                                if (trial != null) widget.onCellTap?.call(trial);
                              },
                              child: CustomPaint(
                                size: Size(cellW * xs.length, cellH * ys.length),
                                painter: _HeatmapPainter(
                                  cells: cells,
                                  vMin: vMin!,
                                  vMax: vMax!,
                                  metric: widget.metric,
                                  cellW: cellW,
                                  cellH: cellH,
                                  hover: _hover,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _AxisLabels(values: xs, cellSize: cellW, axis: Axis.horizontal),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                '${widget.paramX}  ↔  ${widget.paramY}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
          ],
        );
      },
    );
  }

  static List<num> _uniqueSorted(Iterable<num?> raw) {
    final s = raw.whereType<num>().toSet().toList();
    s.sort();
    return s;
  }
}

class _AxisLabels extends StatelessWidget {
  final List<num> values;
  final double cellSize;
  final Axis axis;
  const _AxisLabels({required this.values, required this.cellSize, required this.axis});

  @override
  Widget build(BuildContext context) {
    final children = [
      for (final v in values)
        SizedBox(
          width: axis == Axis.horizontal ? cellSize : 56,
          height: axis == Axis.vertical ? cellSize : 18,
          child: Center(
            child: Text(
              _format(v),
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
    ];
    return axis == Axis.horizontal
        ? Row(mainAxisAlignment: MainAxisAlignment.start, children: children)
        : Column(mainAxisAlignment: MainAxisAlignment.start, children: children);
  }

  static String _format(num v) =>
      v is int ? v.toString() : v.toStringAsFixed(v.abs() >= 100 ? 0 : 2);
}

class _HeatmapPainter extends CustomPainter {
  final List<List<HeatmapTrial?>> cells;
  final double vMin;
  final double vMax;
  final String metric;
  final double cellW;
  final double cellH;
  final ({int x, int y})? hover;

  _HeatmapPainter({
    required this.cells,
    required this.vMin,
    required this.vMax,
    required this.metric,
    required this.cellW,
    required this.cellH,
    required this.hover,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rows = cells.length;
    final cols = cells.isEmpty ? 0 : cells.first.length;
    final span = (vMax - vMin).abs() < 1e-9 ? 1.0 : (vMax - vMin);

    for (int yi = 0; yi < rows; yi++) {
      // y=0 at top of grid corresponds to the *largest* Y param (visually higher).
      final invY = rows - 1 - yi;
      for (int xi = 0; xi < cols; xi++) {
        final t = cells[invY][xi];
        final rect = Rect.fromLTWH(xi * cellW, yi * cellH, cellW - 1, cellH - 1);
        final paint = Paint();
        if (t == null) {
          paint.color = Colors.grey.shade800.withValues(alpha: 0.3);
        } else {
          final v = t.metrics[metric] ?? vMin;
          final norm = ((v - vMin) / span).clamp(0.0, 1.0);
          paint.color = _gradient(norm);
        }
        canvas.drawRect(rect, paint);
      }
    }
  }

  Color _gradient(double t) {
    // Viridis-ish: dark purple → teal → yellow.
    final r = (t < 0.5 ? 0 : (t - 0.5) * 510).clamp(0, 255).toInt();
    final g = (t * 220).toInt().clamp(0, 220);
    final b = ((1 - t) * 180).toInt().clamp(0, 255);
    return Color.fromARGB(255, r, g, b);
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      old.cells != cells ||
      old.vMin != vMin ||
      old.vMax != vMax ||
      old.metric != metric ||
      old.cellW != cellW ||
      old.cellH != cellH ||
      old.hover != hover;
}
