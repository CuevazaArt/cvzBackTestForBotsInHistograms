import 'package:flutter/material.dart';
import 'package:backtester_shell/services/api_service.dart';

/// Configuration for a parameter search space
class ParamBound {
  final String type;
  num min;
  num max;
  num? step;
  bool optimize;
  num fixedValue;

  ParamBound({
    required this.type,
    required this.min,
    required this.max,
    this.step,
    this.optimize = true,
    required this.fixedValue,
  });
}

class ParamBoundsEditor extends StatefulWidget {
  final Map<String, ParamSpec> paramSpecs;
  final ValueChanged<Map<String, ParamBound>> onChanged;

  const ParamBoundsEditor({
    super.key,
    required this.paramSpecs,
    required this.onChanged,
  });

  @override
  State<ParamBoundsEditor> createState() => _ParamBoundsEditorState();
}

class _ParamBoundsEditorState extends State<ParamBoundsEditor> {
  late Map<String, ParamBound> _bounds;

  @override
  void initState() {
    super.initState();
    _initBounds();
  }

  @override
  void didUpdateWidget(ParamBoundsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paramSpecs != widget.paramSpecs) {
      _initBounds();
    }
  }

  void _initBounds() {
    _bounds = {};
    for (final entry in widget.paramSpecs.entries) {
      final spec = entry.value;
      _bounds[entry.key] = ParamBound(
        type: spec.type,
        min: spec.min ?? (spec.type == 'int' ? 1 : 0.0),
        max: spec.max ?? (spec.type == 'int' ? 100 : 1.0),
        step: spec.step,
        optimize: true,
        fixedValue: spec.defaultValue ?? (spec.type == 'int' ? 1 : 0.0),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onChanged(_bounds);
    });
  }

  void _notify() => widget.onChanged(_bounds);

  @override
  Widget build(BuildContext context) {
    if (_bounds.isEmpty) {
      return const Center(child: Text('No parameters to optimize', style: TextStyle(color: Color(0xFF787B86))));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _bounds.entries.map((e) => _buildRow(e.key, e.value)).toList(),
      ),
    );
  }

  Widget _buildRow(String name, ParamBound bound) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E222D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Checkbox(
            value: bound.optimize,
            activeColor: const Color(0xFF26a69a),
            onChanged: (v) {
              setState(() => bound.optimize = v ?? false);
              _notify();
            },
          ),
          SizedBox(
            width: 120,
            child: Text(name, style: const TextStyle(color: Color(0xFFD9D9D9), fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 16),
          if (bound.optimize) ...[
            _NumberField(
              label: 'Min',
              value: bound.min,
              isDouble: bound.type == 'float',
              onChanged: (v) {
                bound.min = v;
                _notify();
              },
            ),
            const SizedBox(width: 16),
            _NumberField(
              label: 'Max',
              value: bound.max,
              isDouble: bound.type == 'float',
              onChanged: (v) {
                bound.max = v;
                _notify();
              },
            ),
            if (bound.type == 'float' || bound.step != null) ...[
              const SizedBox(width: 16),
              _NumberField(
                label: 'Step',
                value: bound.step ?? (bound.type == 'float' ? 0.01 : 1),
                isDouble: bound.type == 'float',
                onChanged: (v) {
                  bound.step = v;
                  _notify();
                },
              ),
            ]
          ] else ...[
            _NumberField(
              label: 'Fixed Value',
              value: bound.fixedValue,
              isDouble: bound.type == 'float',
              onChanged: (v) {
                bound.fixedValue = v;
                _notify();
              },
            ),
          ]
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  final String label;
  final num value;
  final bool isDouble;
  final ValueChanged<num> onChanged;

  const _NumberField({
    required this.label,
    required this.value,
    required this.isDouble,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 80,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF787B86), fontSize: 10)),
          TextFormField(
            initialValue: value.toString(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 13),
            decoration: const InputDecoration(isDense: true, border: InputBorder.none),
            onChanged: (v) {
              final parsed = isDouble ? double.tryParse(v) : int.tryParse(v);
              if (parsed != null) onChanged(parsed);
            },
          ),
        ],
      ),
    );
  }
}
