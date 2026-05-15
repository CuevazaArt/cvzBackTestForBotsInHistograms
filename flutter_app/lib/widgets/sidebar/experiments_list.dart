import 'package:flutter/material.dart';

class ExperimentsList extends StatelessWidget {
  const ExperimentsList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Experiments', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF131722),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'Experiment sweeps available via\n/api/experiments/run\n(Phase 4 UI)',
            style: TextStyle(color: Color(0xFF787B86), fontSize: 11),
          ),
        ),
      ],
    );
  }
}
