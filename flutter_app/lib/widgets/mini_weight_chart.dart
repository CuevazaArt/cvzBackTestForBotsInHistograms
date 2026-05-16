import 'dart:math' as math;
import 'package:flutter/material.dart';

class ChartSample {
  final DateTime time;
  final double value;
  const ChartSample(this.time, this.value);
}

class MiniWeightChart extends StatefulWidget {
  final int currentWeight;
  final int weightLimit;
  final Duration timeWindow;
  final double height;
  final double width;

  const MiniWeightChart({
    super.key,
    required this.currentWeight,
    this.weightLimit = 6000,
    this.timeWindow = const Duration(minutes: 10),
    this.height = 48,
    this.width = 180,
  });

  @override
  State<MiniWeightChart> createState() => _MiniWeightChartState();
}

class _MiniWeightChartState extends State<MiniWeightChart> {
  final List<ChartSample> _data = [];

  @override
  void initState() {
    super.initState();
    _addDataPoint(widget.currentWeight);
  }

  @override
  void didUpdateWidget(MiniWeightChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Add point if weight changed, or if it's been more than 5 seconds since the last point to keep the chart moving
    if (widget.currentWeight != oldWidget.currentWeight || _data.isEmpty || DateTime.now().difference(_data.last.time).inSeconds >= 5) {
      _addDataPoint(widget.currentWeight);
    }
  }

  void _addDataPoint(int weight) {
    final now = DateTime.now();
    final cutoff = now.subtract(widget.timeWindow);
    setState(() {
      _data.add(ChartSample(now, weight.toDouble()));
      _data.removeWhere((s) => s.time.isBefore(cutoff));
    });
  }

  Color _colorForPct(double pct) {
    if (pct >= 0.80) return const Color(0xFFFF1744);
    if (pct >= 0.60) return const Color(0xFFFF9100);
    if (pct >= 0.40) return const Color(0xFFFFEA00);
    return const Color(0xFF00E5FF);
  }

  @override
  Widget build(BuildContext context) {
    final pct = _data.isEmpty
        ? 0.0
        : (_data.last.value / widget.weightLimit).clamp(0.0, 1.0);
    final color = _colorForPct(pct);
    final pctStr = (pct * 100).toStringAsFixed(1);
    final lastVal = _data.isEmpty ? '--' : _data.last.value.toInt().toString();

    return Container(
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WEIGHT',
                  style: TextStyle(
                    fontSize: 9,
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '$pctStr%',
                  style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$lastVal/${widget.weightLimit}',
                  style: const TextStyle(
                    fontSize: 7,
                    color: Colors.white38,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: CustomPaint(
              painter: SparklinePainter(
                data: _data,
                maxY: widget.weightLimit.toDouble(),
                color: color,
              ),
              size: Size.infinite,
            ),
          ),
        ],
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  final List<ChartSample> data;
  final double? maxY;
  final Color color;

  SparklinePainter({
    required this.data,
    this.maxY,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;

    final effectiveMaxY = maxY ?? data.map((d) => d.value).reduce(math.max) * 1.1;
    final effectiveMinY = maxY != null ? 0.0 : data.map((d) => d.value).reduce(math.min) * 0.95;
    final rangeY = effectiveMaxY - effectiveMinY;
    if (rangeY <= 0) return;

    final firstTime = data.first.time;
    final lastTime = data.last.time;
    final rangeX = lastTime.difference(firstTime).inMilliseconds.toDouble();
    if (rangeX <= 0) return;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < data.length; i++) {
      final x = (data[i].time.difference(firstTime).inMilliseconds / rangeX) * size.width;
      final y = size.height - ((data[i].value - effectiveMinY) / rangeY) * size.height * 0.85 - size.height * 0.05;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.0)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    if (data.isNotEmpty) {
      final last = data.last;
      final lx = size.width;
      final ly = size.height - ((last.value - effectiveMinY) / rangeY) * size.height * 0.85 - size.height * 0.05;
      canvas.drawCircle(Offset(lx, ly), 2.5, Paint()..color = color);
      canvas.drawCircle(Offset(lx, ly), 4, Paint()..color = color.withValues(alpha: 0.3));
    }

    if (maxY != null) {
      final fullY = size.height - (1.0 * size.height * 0.85) - size.height * 0.05;
      final ceilPaint = Paint()
        ..color = const Color(0x66FF1744)
        ..strokeWidth = 1.0;
      canvas.drawLine(Offset(0, fullY), Offset(size.width, fullY), ceilPaint);

      final tp100 = TextPainter(
        text: const TextSpan(
          text: '100%',
          style: TextStyle(fontSize: 7, color: Color(0x88FF1744), fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp100.paint(canvas, Offset(size.width - tp100.width - 1, fullY - tp100.height - 1));

      final thresholds = [
        (0.4, '40%', const Color(0x3300E5FF)),
        (0.6, '60%', const Color(0x33FFEA00)),
        (0.8, '80%', const Color(0x33FF9100)),
      ];
      for (final (t, label, tColor) in thresholds) {
        final ty = size.height - (t * size.height * 0.85) - size.height * 0.05;
        final tp = Paint()
          ..color = tColor
          ..strokeWidth = 0.5;
        canvas.drawLine(Offset(0, ty), Offset(size.width, ty), tp);

        final tpLabel = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(fontSize: 6, color: tColor.withAlpha(180), fontFamily: 'monospace'),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tpLabel.paint(canvas, Offset(size.width - tpLabel.width - 1, ty + 1));
      }
    }
  }

  @override
  bool shouldRepaint(covariant SparklinePainter old) =>
      old.data.length != data.length || old.color != color ||
      (data.isNotEmpty && old.data.isNotEmpty && old.data.last.value != data.last.value);
}
