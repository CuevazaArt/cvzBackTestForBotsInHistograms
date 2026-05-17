import 'package:flutter/material.dart';
import '../../state/backtest_state.dart';

/// Start / Pause / Resume / Step / Cancel + speed slider.
class RunControls extends StatelessWidget {
  final BacktestStatus status;
  final int speedMs;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStep;
  final VoidCallback onCancel;
  final ValueChanged<int> onSpeedChanged;

  const RunControls({
    super.key,
    required this.status,
    required this.speedMs,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStep,
    required this.onCancel,
    required this.onSpeedChanged,
  });

  @override
  Widget build(BuildContext context) {
    final running = status is BacktestRunning;
    final paused = running && (status as BacktestRunning).paused;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Controls', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (!running)
                  FilledButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start'),
                  )
                else ...[
                  if (paused) ...[
                    IconButton(
                      onPressed: onResume,
                      icon: const Icon(Icons.play_arrow),
                      tooltip: 'Resume',
                    ),
                    IconButton(
                      onPressed: onStep,
                      icon: const Icon(Icons.skip_next),
                      tooltip: 'Step',
                    ),
                  ] else
                    IconButton(
                      onPressed: onPause,
                      icon: const Icon(Icons.pause),
                      tooltip: 'Pause',
                    ),
                  IconButton(
                    onPressed: onCancel,
                    icon: const Icon(Icons.stop),
                    tooltip: 'Cancel',
                    color: Colors.red,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            if (running)
              LinearProgressIndicator(
                value: (status as BacktestRunning).percent / 100,
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Speed:'),
                Expanded(
                  child: Slider(
                    value: speedMs.toDouble(),
                    min: 0,
                    max: 500,
                    divisions: 10,
                    label: speedMs == 0 ? 'max' : '${speedMs}ms',
                    onChanged: (v) => onSpeedChanged(v.toInt()),
                  ),
                ),
                Text(speedMs == 0 ? 'max' : '${speedMs}ms'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
