import 'package:flutter/material.dart';

class HeatmapData {
  final List<double> xValues;
  final List<double> yValues;
  final Map<(double, double), double> cells;
  final double minValue;
  final double maxValue;

  const HeatmapData({
    required this.xValues,
    required this.yValues,
    required this.cells,
    required this.minValue,
    required this.maxValue,
  });
}

class HeatmapWidget extends StatelessWidget {
  final HeatmapData data;
  final String xLabel;
  final String yLabel;
  final String metricLabel;

  const HeatmapWidget({
    super.key,
    required this.data,
    required this.xLabel,
    required this.yLabel,
    required this.metricLabel,
  });

  @override
  Widget build(BuildContext context) {
    if (data.xValues.isEmpty || data.yValues.isEmpty) {
      return const Center(child: Text('No data', style: TextStyle(color: Colors.grey)));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const labelW = 50.0;
        const labelH = 30.0;
        const legendW = 60.0;
        final plotW = constraints.maxWidth - labelW - legendW;
        final plotH = constraints.maxHeight - labelH - 20;

        return CustomPaint(
          size: Size(constraints.maxWidth, constraints.maxHeight),
          painter: _HeatmapPainter(
            data: data,
            xLabel: xLabel,
            yLabel: yLabel,
            metricLabel: metricLabel,
            plotOffset: const Offset(labelW, 10),
            plotSize: Size(plotW, plotH),
            legendOffset: Offset(labelW + plotW + 8, 10),
            legendSize: Size(legendW - 16, plotH),
            labelH: labelH,
            isDark: Theme.of(context).brightness == Brightness.dark,
          ),
        );
      },
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final HeatmapData data;
  final String xLabel;
  final String yLabel;
  final String metricLabel;
  final Offset plotOffset;
  final Size plotSize;
  final Offset legendOffset;
  final Size legendSize;
  final double labelH;
  final bool isDark;

  _HeatmapPainter({
    required this.data,
    required this.xLabel,
    required this.yLabel,
    required this.metricLabel,
    required this.plotOffset,
    required this.plotSize,
    required this.legendOffset,
    required this.legendSize,
    required this.labelH,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final textColor = isDark ? Colors.white70 : Colors.black87;
    final cellW = plotSize.width / data.xValues.length;
    final cellH = plotSize.height / data.yValues.length;
    final range = data.maxValue - data.minValue;

    for (int yi = 0; yi < data.yValues.length; yi++) {
      for (int xi = 0; xi < data.xValues.length; xi++) {
        final key = (data.xValues[xi], data.yValues[yi]);
        final value = data.cells[key];
        if (value == null) continue;

        final norm = range > 0 ? (value - data.minValue) / range : 0.5;
        final color = _colorForNorm(norm);

        final rect = Rect.fromLTWH(
          plotOffset.dx + xi * cellW,
          plotOffset.dy + (data.yValues.length - 1 - yi) * cellH,
          cellW,
          cellH,
        );
        canvas.drawRect(rect, Paint()..color = color);

        if (cellW > 30 && cellH > 16) {
          final tp = TextPainter(
            text: TextSpan(
              text: value.toStringAsFixed(1),
              style: TextStyle(
                fontSize: 9,
                color: norm > 0.5 ? Colors.white : Colors.black,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout(maxWidth: cellW);
          tp.paint(canvas, Offset(
            rect.center.dx - tp.width / 2,
            rect.center.dy - tp.height / 2,
          ));
        }
      }
    }

    final labelStyle = TextStyle(fontSize: 10, color: textColor);
    for (int xi = 0; xi < data.xValues.length; xi++) {
      if (xi % _skipFactor(data.xValues.length, cellW) != 0) continue;
      final tp = TextPainter(
        text: TextSpan(text: _fmt(data.xValues[xi]), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: cellW + 10);
      tp.paint(canvas, Offset(
        plotOffset.dx + xi * cellW + cellW / 2 - tp.width / 2,
        plotOffset.dy + plotSize.height + 2,
      ));
    }

    for (int yi = 0; yi < data.yValues.length; yi++) {
      if (yi % _skipFactor(data.yValues.length, cellH) != 0) continue;
      final tp = TextPainter(
        text: TextSpan(text: _fmt(data.yValues[yi]), style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 48);
      tp.paint(canvas, Offset(
        plotOffset.dx - tp.width - 4,
        plotOffset.dy + (data.yValues.length - 1 - yi) * cellH + cellH / 2 - tp.height / 2,
      ));
    }

    final axisLabelStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: textColor);
    final xTp = TextPainter(
      text: TextSpan(text: xLabel, style: axisLabelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    xTp.paint(canvas, Offset(
      plotOffset.dx + plotSize.width / 2 - xTp.width / 2,
      plotOffset.dy + plotSize.height + labelH - 4,
    ));

    const steps = 10;
    final legendCellH = legendSize.height / steps;
    for (int i = 0; i < steps; i++) {
      final norm = 1.0 - i / (steps - 1);
      final rect = Rect.fromLTWH(
        legendOffset.dx,
        legendOffset.dy + i * legendCellH,
        12,
        legendCellH,
      );
      canvas.drawRect(rect, Paint()..color = _colorForNorm(norm));
    }

    final topTp = TextPainter(
      text: TextSpan(text: _fmt(data.maxValue), style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    topTp.paint(canvas, Offset(legendOffset.dx + 14, legendOffset.dy));

    final botTp = TextPainter(
      text: TextSpan(text: _fmt(data.minValue), style: labelStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    botTp.paint(canvas, Offset(legendOffset.dx + 14, legendOffset.dy + legendSize.height - botTp.height));
  }

  Color _colorForNorm(double norm) {
    if (norm < 0.5) {
      return Color.lerp(const Color(0xFFEF4444), const Color(0xFFFBBF24), norm * 2)!;
    }
    return Color.lerp(const Color(0xFFFBBF24), const Color(0xFF22C55E), (norm - 0.5) * 2)!;
  }

  int _skipFactor(int count, double cellSize) {
    if (cellSize >= 30) return 1;
    if (cellSize >= 15) return 2;
    return (30 / cellSize).ceil();
  }

  String _fmt(double v) => v == v.truncateToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  bool shouldRepaint(covariant _HeatmapPainter old) =>
      data != old.data || isDark != old.isDark;
}
