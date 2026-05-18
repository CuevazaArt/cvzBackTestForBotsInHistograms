import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../state/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _dbPath = 'loading...';

  @override
  void initState() {
    super.initState();
    _loadPath();
  }

  Future<void> _loadPath() async {
    final dir = await getApplicationSupportDirectory();
    if (!mounted) return;
    setState(() => _dbPath = p.join(dir.path, 'cvz_backtester.db'));
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 24),
          Card(
            child: SwitchListTile(
              secondary: Icon(themeMode == ThemeMode.dark ? Icons.dark_mode : Icons.light_mode),
              title: const Text('Dark mode'),
              subtitle: const Text('Toggle between light and dark theme'),
              value: themeMode == ThemeMode.dark,
              onChanged: (v) {
                ref.read(themeModeProvider.notifier).state =
                    v ? ThemeMode.dark : ThemeMode.light;
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('Database path'),
              subtitle: SelectableText(_dbPath),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Version'),
              subtitle: const Text('v5.0.0 — Dart rewrite'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.code),
              title: const Text('Architecture'),
              subtitle: const Text('Flutter Desktop + Dart Engine + SQLite/drift + Riverpod'),
            ),
          ),
        ],
      ),
    );
  }
}
