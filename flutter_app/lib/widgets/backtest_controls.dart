import 'package:flutter/material.dart';

/// Placeholder widget — parameter editor for bot params.
/// Populated dynamically from bot.param_spec() in a future iteration.
class BacktestControls extends StatelessWidget {
  final Map<String, dynamic> paramSpec;
  final Map<String, dynamic> values;
  final ValueChanged<Map<String, dynamic>> onChanged;

  const BacktestControls({
    super.key,
    required this.paramSpec,
    required this.values,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (paramSpec.isEmpty) return const SizedBox.shrink();

    return Container(
      color: const Color(0xFF1E222D),
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        children: paramSpec.entries.map((entry) {
          final spec = entry.value as Map<String, dynamic>;
          final current = values[entry.key] ?? spec['default'];
          return SizedBox(
            width: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.key, style: const TextStyle(color: Color(0xFF787B86), fontSize: 10)),
                TextFormField(
                  initialValue: current.toString(),
                  style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 13),
                  decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                  onChanged: (v) {
                    final type = spec['type'] as String? ?? 'float';
                    final parsed = type == 'int' ? int.tryParse(v) : double.tryParse(v);
                    if (parsed != null) {
                      onChanged({...values, entry.key: parsed});
                    }
                  },
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
