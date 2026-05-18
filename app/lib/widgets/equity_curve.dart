import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class EquityCurveWidget extends StatelessWidget {
  final List<double> equityCurve;
  final double initialCash;
  const EquityCurveWidget({super.key, required this.equityCurve, required this.initialCash});

  @override
  Widget build(BuildContext context) {
    if (equityCurve.length < 2) {
      return const Center(child: Text('Not enough data', style: TextStyle(color: Colors.grey)));
    }

    final spots = <FlSpot>[
      for (int i = 0; i < equityCurve.length; i++)
        FlSpot(i.toDouble(), equityCurve[i]),
    ];

    final minY = equityCurve.reduce((a, b) => a < b ? a : b);
    final maxY = equityCurve.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.05;

    return LineChart(
      LineChartData(
        minY: minY - padding,
        maxY: maxY + padding,
        gridData: FlGridData(
          show: true,
          horizontalInterval: (maxY - minY) / 4,
          getDrawingHorizontalLine: (v) => FlLine(
            color: Colors.grey.withAlpha(30),
            strokeWidth: 1,
          ),
          getDrawingVerticalLine: (v) => FlLine(
            color: Colors.grey.withAlpha(30),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (v, _) => Text(
                v.toStringAsFixed(0),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
          ),
          bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: equityCurve.last >= initialCash ? Colors.green : Colors.red,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: (equityCurve.last >= initialCash ? Colors.green : Colors.red).withAlpha(20),
            ),
          ),
          LineChartBarData(
            spots: [FlSpot(0, initialCash), FlSpot(equityCurve.length - 1, initialCash)],
            isCurved: false,
            color: Colors.grey.withAlpha(80),
            barWidth: 1,
            dotData: const FlDotData(show: false),
            dashArray: [4, 4],
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots.map((s) {
              if (s.barIndex == 1) return null;
              return LineTooltipItem(
                s.y.toStringAsFixed(2),
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
