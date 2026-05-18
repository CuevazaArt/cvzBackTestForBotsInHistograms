import 'package:flutter/material.dart';

import '../bots/dsl/dsl_bot.dart';
import '../bots/registry.dart';

class DSLEditorDialog extends StatefulWidget {
  const DSLEditorDialog({super.key});

  @override
  State<DSLEditorDialog> createState() => _DSLEditorDialogState();
}

class _DSLEditorDialogState extends State<DSLEditorDialog> {
  final _ctrl = TextEditingController(text: _defaultYaml);
  String? _error;
  String? _successMsg;

  static const _defaultYaml = '''id: my_custom_bot
name: My Custom Bot
indicators:
  fast: { type: ema, period: 12 }
  slow: { type: ema, period: 26 }
  rsi:  { type: rsi, period: 14 }
entry: "fast > slow AND rsi < 70"
exit:  "fast < slow OR rsi > 80"
risk:
  stop_loss_pct: 5
  take_profit_pct: 10
  risk_per_trade_pct: 2
''';

  void _validate() {
    try {
      DSLBot.fromYaml(_ctrl.text);
      setState(() {
        _error = null;
        _successMsg = 'YAML is valid!';
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _successMsg = null;
      });
    }
  }

  void _register() {
    try {
      final bot = DSLBot.fromYaml(_ctrl.text);
      BotRegistry.register(
        name: bot.id,
        displayName: bot.name,
        description: 'Custom DSL bot: ${bot.name}',
        factory: (_) => DSLBot.fromYaml(_ctrl.text),
        defaultParams: bot.params,
      );
      setState(() {
        _error = null;
        _successMsg = 'Registered "${bot.name}" (id: ${bot.id})';
      });
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) Navigator.pop(context, bot.id);
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _successMsg = null;
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.code),
                  const SizedBox(width: 8),
                  Text('DSL Bot Editor', style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Define a custom bot using YAML. Indicators: ema, sma, rsi, macd, bollinger, stochastic, vwap. '
                'Expressions: AND, OR, NOT, <, <=, >, >=, ==, !=',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(color: Colors.red, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              if (_successMsg != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_successMsg!,
                            style: const TextStyle(color: Colors.green, fontSize: 12)),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Validate'),
                    onPressed: _validate,
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Register Bot'),
                    onPressed: _register,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<String?> showDSLEditor(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const DSLEditorDialog(),
  );
}
