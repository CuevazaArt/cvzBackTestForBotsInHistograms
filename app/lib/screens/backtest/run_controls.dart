import 'package:flutter/material.dart';
import '../../state/backtest_state.dart';

class RunControlsInline extends StatelessWidget {
  final BacktestStatus status;
  final int speedMs;
  final bool stepMode;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onStep;
  final VoidCallback onCancel;
  final ValueChanged<int> onSpeedChanged;
  final ValueChanged<bool> onStepModeChanged;

  const RunControlsInline({
    super.key,
    required this.status,
    required this.speedMs,
    required this.stepMode,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onStep,
    required this.onCancel,
    required this.onSpeedChanged,
    required this.onStepModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final running = status is BacktestRunning;
    final paused = running && (status as BacktestRunning).paused;
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!running) ...[
          SizedBox(
            height: 32,
            child: FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow, size: 16),
              label: const Text('Start', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ] else ...[
          if (paused) ...[
            IconButton(
              onPressed: onResume,
              icon: const Icon(Icons.play_arrow, size: 18),
              tooltip: 'Resume',
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.primary,
            ),
            IconButton(
              onPressed: onStep,
              icon: const Icon(Icons.skip_next, size: 18),
              tooltip: 'Step (1 candle)',
              visualDensity: VisualDensity.compact,
              color: theme.colorScheme.primary,
            ),
          ] else
            IconButton(
              onPressed: onPause,
              icon: const Icon(Icons.pause, size: 18),
              tooltip: 'Pause',
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            onPressed: onCancel,
            icon: const Icon(Icons.stop, size: 18),
            tooltip: 'Cancel',
            visualDensity: VisualDensity.compact,
            color: Colors.red,
          ),
        ],
        const SizedBox(width: 4),
        Tooltip(
          message: 'Step mode: start paused',
          child: SizedBox(
            height: 28,
            child: FilterChip(
              label: const Text('Step', style: TextStyle(fontSize: 10)),
              selected: stepMode,
              onSelected: onStepModeChanged,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            ),
          ),
        ),
        const SizedBox(width: 4),
        Tooltip(
          message: speedMs == 0 ? 'Speed: max' : 'Speed: ${speedMs}ms/bar',
          child: SizedBox(
            width: 80,
            child: SliderTheme(
              data: SliderThemeData(
                trackHeight: 2,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Slider(
                value: speedMs.toDouble(),
                min: 0,
                max: 500,
                divisions: 10,
                onChanged: (v) => onSpeedChanged(v.toInt()),
              ),
            ),
          ),
        ),
        Text(
          speedMs == 0 ? 'max' : '${speedMs}ms',
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }
}
