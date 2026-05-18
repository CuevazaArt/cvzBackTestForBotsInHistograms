import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CommandPaletteAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const CommandPaletteAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });
}

class CommandPalette extends StatefulWidget {
  final List<CommandPaletteAction> actions;
  const CommandPalette({super.key, required this.actions});

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  String _query = '';

  List<CommandPaletteAction> get _filtered {
    if (_query.isEmpty) return widget.actions;
    final lower = _query.toLowerCase();
    return widget.actions
        .where((a) => a.label.toLowerCase().contains(lower))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Type a command...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final action in _filtered)
                    ListTile(
                      leading: Icon(action.icon),
                      title: Text(action.label),
                      onTap: () {
                        Navigator.pop(context);
                        action.onTap();
                      },
                    ),
                  if (_filtered.isEmpty)
                    const ListTile(
                      title: Text('No matching commands', style: TextStyle(color: Colors.grey)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void showCommandPalette(BuildContext context, List<CommandPaletteAction> actions) {
  showDialog(
    context: context,
    builder: (_) => CommandPalette(actions: actions),
  );
}

class CommandPaletteShortcut extends StatelessWidget {
  final Widget child;
  final List<CommandPaletteAction> actions;
  const CommandPaletteShortcut({super.key, required this.child, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
            const _OpenPaletteIntent(),
      },
      child: Actions(
        actions: {
          _OpenPaletteIntent: CallbackAction<_OpenPaletteIntent>(
            onInvoke: (_) {
              showCommandPalette(context, actions);
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: child),
      ),
    );
  }
}

class _OpenPaletteIntent extends Intent {
  const _OpenPaletteIntent();
}
