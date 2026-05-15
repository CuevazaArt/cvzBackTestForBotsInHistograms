import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/bot_spec.dart';
import '../../state/backtest_state.dart';

class ParamsEditor extends ConsumerWidget {
  final BotSpec spec;
  const ParamsEditor({super.key, required this.spec});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg  = ref.watch(configProvider);
    final cfgN = ref.read(configProvider.notifier);
    final tt   = Theme.of(context).textTheme;

    if (spec.params.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Parameters', style: tt.bodySmall),
        const SizedBox(height: 8),
        ...spec.params.map((p) {
          final current = cfg.params[p.name] ?? p.defaultValue;
          return _ParamRow(
            param: p,
            value: current,
            onChanged: (v) => cfgN.setParam(p.name, v),
          );
        }),
      ],
    );
  }
}

class _ParamRow extends StatefulWidget {
  final ParamSpec param;
  final dynamic value;
  final void Function(dynamic) onChanged;

  const _ParamRow({
    required this.param,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_ParamRow> createState() => _ParamRowState();
}

class _ParamRowState extends State<_ParamRow> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(_ParamRow old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _ctrl.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.param;
    final isInt = p.type == 'int';
    final isFloat = p.type == 'float';

    // Bool param → switch
    if (p.type == 'bool') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(p.name, style: const TextStyle(fontSize: 11))),
            Switch(
              value: widget.value == true,
              onChanged: widget.onChanged,
            ),
          ],
        ),
      );
    }

    // Numeric with range → slider + text
    if ((isInt || isFloat) && p.min != null && p.max != null) {
      final mn  = (p.min  as num).toDouble();
      final mx  = (p.max  as num).toDouble();
      final cur = (widget.value as num? ?? p.defaultValue as num).toDouble().clamp(mn, mx);
      final div = isInt ? (mx - mn).round() : 0; // 0 = continuous

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(p.name, style: const TextStyle(fontSize: 11))),
                Text(
                  isInt ? cur.round().toString() : cur.toStringAsFixed(3),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF2962FF)),
                ),
              ],
            ),
            Slider(
              value: cur,
              min: mn,
              max: mx,
              divisions: div > 0 ? div : null,
              onChanged: (v) {
                final val = isInt ? v.round() : double.parse(v.toStringAsFixed(4));
                widget.onChanged(val);
              },
            ),
          ],
        ),
      );
    }

    // Free text fallback
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(p.name, style: const TextStyle(fontSize: 11))),
          SizedBox(
            width: 90,
            child: TextFormField(
              controller: _ctrl,
              style: const TextStyle(fontSize: 11),
              onChanged: (v) {
                if (isInt) {
                  final i = int.tryParse(v);
                  if (i != null) widget.onChanged(i);
                } else if (isFloat) {
                  final f = double.tryParse(v);
                  if (f != null) widget.onChanged(f);
                } else {
                  widget.onChanged(v);
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
