import 'package:backtester_shell/widgets/param_bounds_editor.dart';

/// Result of expanding parameter bounds into a grid.
class ParamGrid {
  /// All combinations as a list of `{paramName: value}` maps.
  final List<Map<String, dynamic>> combos;

  /// Per-param step count for diagnostics.
  final Map<String, int> stepsPerParam;

  /// True if the grid was capped (some combinations dropped).
  final bool capped;

  /// Total combinations that *would* have been generated without the cap.
  final int wouldHaveBeen;

  const ParamGrid({
    required this.combos,
    required this.stepsPerParam,
    required this.capped,
    required this.wouldHaveBeen,
  });
}

/// Expand `ParamBound` configuration into a list of concrete param combinations.
///
/// - Params with `optimize=false` contribute a single fixed value.
/// - Params with `optimize=true` are stepped from min..max inclusive.
///   * `int` params step by 1 if `step` is null, otherwise by `step.round()`.
///   * `float` params step by `step ?? (max-min)/10`. If step <= 0, falls back to /10.
/// - `cap` defaults to 200; if the cartesian product exceeds it, returns the first
///   `cap` combinations and sets `capped=true`.
ParamGrid expandBounds(Map<String, ParamBound> bounds, {int cap = 200}) {
  final paramValues = <String, List<num>>{};
  final stepsPerParam = <String, int>{};

  for (final entry in bounds.entries) {
    final name = entry.key;
    final b = entry.value;

    if (!b.optimize) {
      paramValues[name] = [b.fixedValue];
      stepsPerParam[name] = 1;
      continue;
    }

    final values = _stepRange(b);
    paramValues[name] = values;
    stepsPerParam[name] = values.length;
  }

  // Compute total combinations.
  int totalCombos = 1;
  for (final v in paramValues.values) {
    totalCombos *= v.isEmpty ? 1 : v.length;
  }

  // Cartesian product with cap.
  final result = <Map<String, dynamic>>[];
  _cartesian(
    paramValues.entries.toList(),
    0,
    <String, dynamic>{},
    result,
    cap,
  );

  return ParamGrid(
    combos: result,
    stepsPerParam: stepsPerParam,
    capped: totalCombos > cap,
    wouldHaveBeen: totalCombos,
  );
}

List<num> _stepRange(ParamBound b) {
  final isInt = b.type == 'int';
  num min = b.min;
  num max = b.max;
  if (min > max) {
    final tmp = min;
    min = max;
    max = tmp;
  }
  if (min == max) return [isInt ? min.round() : min.toDouble()];

  num step;
  if (b.step != null && b.step! > 0) {
    step = b.step!;
  } else {
    step = isInt ? 1 : (max - min) / 10;
    if (step <= 0) step = isInt ? 1 : 0.01;
  }

  final values = <num>[];
  num v = min;
  // Use a generous epsilon for float comparisons.
  final eps = isInt ? 0 : step * 0.0001;
  while (v <= max + eps) {
    values.add(isInt ? v.round() : double.parse(v.toStringAsFixed(6)));
    v = v + step;
    // Safety cap to avoid runaway loops on degenerate inputs.
    if (values.length > 500) break;
  }
  return values;
}

void _cartesian(
  List<MapEntry<String, List<num>>> entries,
  int idx,
  Map<String, dynamic> current,
  List<Map<String, dynamic>> output,
  int cap,
) {
  if (output.length >= cap) return;
  if (idx == entries.length) {
    output.add(Map<String, dynamic>.from(current));
    return;
  }
  final entry = entries[idx];
  for (final v in entry.value) {
    if (output.length >= cap) return;
    current[entry.key] = v;
    _cartesian(entries, idx + 1, current, output, cap);
  }
  current.remove(entry.key);
}
