import 'package:flutter/material.dart';

class PlaceholderHeatmap extends StatelessWidget {
  const PlaceholderHeatmap({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.grid_view, size: 32, color: Color(0xFF2A2E39)),
        const SizedBox(height: 8),
        const Text('Parameter heatmap — Phase 4',
            style: TextStyle(color: Color(0xFF787B86), fontSize: 12)),
        const SizedBox(height: 4),
        Text('Run /experiments to generate data',
            style: Theme.of(context).textTheme.bodySmall),
      ]),
    );
  }
}
