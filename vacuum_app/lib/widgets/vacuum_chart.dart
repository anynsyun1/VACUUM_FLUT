import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// 실시간 압력 변화 그래프
class VacuumChart extends StatelessWidget {
  final List<double> data;  // pressure diff 리스트
  final int maxPoints;      // X축 최대 포인트 수 (예: 300)

  const VacuumChart({
    super.key,
    required this.data,
    this.maxPoints = 300,
  });

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minX: 0,
        maxX: maxPoints.toDouble(),
        minY: -5,
        maxY: 5,
        gridData: FlGridData(show: true),
        borderData: FlBorderData(
          show: true,
          border: const Border(
            left: BorderSide(),
            bottom: BorderSide(),
            right: BorderSide(),
            top: BorderSide(),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 32),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 28),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            isCurved: false,
            barWidth: 2,
            color: Colors.blue,
            spots: _buildSpots(),
            dotData: FlDotData(show: false),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 0),
    );
  }

  List<FlSpot> _buildSpots() {
    final List<FlSpot> spots = [];
    for (int i = 0; i < data.length; i++) {
      spots.add(FlSpot(i.toDouble(), data[i]));
    }
    return spots;
  }
}
