import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:backtester_shell/screens/home_screen.dart';
import 'package:backtester_shell/widgets/command_palette.dart';

/// Intent: trigger the currently registered "run backtest" hook.
class RunBacktestIntent extends Intent {
  const RunBacktestIntent();
}

/// Intent: trigger the currently registered "export HTML" hook.
class ExportHtmlIntent extends Intent {
  const ExportHtmlIntent();
}

/// Intent: dismiss any open palette / dialog (used by the global Esc binding).
class DismissOverlayIntent extends Intent {
  const DismissOverlayIntent();
}

/// Root widget. Owns:
///   * theme-mode (`ValueNotifier<ThemeMode>`),
///   * shared [ShortcutHooks] registry,
///   * global keyboard shortcuts (`Ctrl+K`, `Ctrl+R`, `Ctrl+E`, `Esc`),
///   * global [Actions] dispatch from the shortcut intents to the hooks.
class BacktesterApp extends StatefulWidget {
  const BacktesterApp({super.key});

  @override
  State<BacktesterApp> createState() => _BacktesterAppState();
}

class _BacktesterAppState extends State<BacktesterApp> {
  final ShortcutHooks _hooks = ShortcutHooks();
  final ValueNotifier<ThemeMode> _themeMode = ValueNotifier<ThemeMode>(
    ThemeMode.dark,
  );
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  bool _paletteOpen = false;

  @override
  void initState() {
    super.initState();
    _hooks.openPalette = _openPalette;
    _hooks.toggleTheme = _toggleTheme;
  }

  @override
  void dispose() {
    _themeMode.dispose();
    super.dispose();
  }

  // ── Actions implementations ────────────────────────────────

  void _toggleTheme() {
    _themeMode.value = _themeMode.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
  }

  Future<void> _openPalette() async {
    if (_paletteOpen) return;
    final ctx = _navKey.currentContext;
    if (ctx == null) return;
    _paletteOpen = true;
    try {
      await showCommandPalette(ctx, actions: _buildPaletteActions());
    } finally {
      _paletteOpen = false;
    }
  }

  void _showSnack(String message) {
    final m = _messengerKey.currentState;
    if (m == null) return;
    m.clearSnackBars();
    m.showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF1E222D),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 12),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _runBacktest() {
    final cb = _hooks.runBacktest;
    if (cb != null) {
      cb();
    } else {
      _showSnack('No backtest screen available to run.');
    }
  }

  void _exportHtml() {
    final cb = _hooks.exportHtml;
    if (cb != null) {
      cb();
    } else {
      _showSnack('No backtest run available to export.');
    }
  }

  Future<void> _copyRunId() async {
    final id = _hooks.currentRunId?.call();
    if (id == null || id.isEmpty) {
      _showSnack('No active run to copy.');
      return;
    }
    await Clipboard.setData(ClipboardData(text: id));
    _showSnack('Run ID copied: $id');
  }

  void _navigateTo(int index) {
    final cb = _hooks.navigateTo;
    if (cb != null) {
      cb(index);
    } else {
      _showSnack('Navigation hook not registered yet.');
    }
  }

  Future<void> _openWorkplan() async {
    const path = 'WORKPLAN.md';
    await Clipboard.setData(const ClipboardData(text: path));
    if (!mounted) return;
    final ctx = _navKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    showDialog<void>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E222D),
        title: const Text(
          'Workplan',
          style: TextStyle(color: Color(0xFFD9D9D9), fontSize: 14),
        ),
        content: const Text(
          'See WORKPLAN.md at the repo root.\n'
          'The path was copied to your clipboard.',
          style: TextStyle(color: Color(0xFFD9D9D9), fontSize: 12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Palette action list ────────────────────────────────────

  List<CommandAction> _buildPaletteActions() {
    return <CommandAction>[
      CommandAction(
        id: 'nav.backtest',
        label: 'Navigate to Backtest',
        icon: Icons.candlestick_chart,
        shortcut: 'Alt+1',
        onInvoke: () => _navigateTo(0),
      ),
      CommandAction(
        id: 'nav.optimize',
        label: 'Navigate to Optimize',
        icon: Icons.science_outlined,
        shortcut: 'Alt+2',
        onInvoke: () => _navigateTo(1),
      ),
      CommandAction(
        id: 'nav.analysis',
        label: 'Navigate to Analysis',
        icon: Icons.analytics_outlined,
        shortcut: 'Alt+3',
        onInvoke: () => _navigateTo(2),
      ),
      CommandAction(
        id: 'nav.settings',
        label: 'Navigate to Settings',
        icon: Icons.settings_outlined,
        shortcut: 'Alt+4',
        onInvoke: () => _navigateTo(3),
      ),
      CommandAction(
        id: 'run.last',
        label: 'Run Last Backtest',
        icon: Icons.play_arrow,
        shortcut: 'Ctrl+R',
        onInvoke: _runBacktest,
      ),
      CommandAction(
        id: 'run.copy_id',
        label: 'Copy Current Run ID',
        icon: Icons.content_copy_outlined,
        onInvoke: _copyRunId,
      ),
      CommandAction(
        id: 'run.export_html',
        label: 'Export Current Run as HTML',
        icon: Icons.description_outlined,
        shortcut: 'Ctrl+E',
        onInvoke: _exportHtml,
      ),
      CommandAction(
        id: 'doc.workplan',
        label: 'Open WORKPLAN Doc',
        icon: Icons.menu_book_outlined,
        onInvoke: _openWorkplan,
      ),
      CommandAction(
        id: 'theme.toggle',
        label: 'Toggle Light / Dark Theme',
        icon: Icons.brightness_6_outlined,
        onInvoke: _toggleTheme,
      ),
    ];
  }

  // ── Theme defs ─────────────────────────────────────────────

  ThemeData get _darkTheme => ThemeData.dark().copyWith(
    scaffoldBackgroundColor: const Color(0xFF131722),
    colorScheme: const ColorScheme.dark(
      primary: Color(0xFF26a69a),
      secondary: Color(0xFFef5350),
      surface: Color(0xFF1E222D),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E222D),
      elevation: 0,
      titleTextStyle: TextStyle(
        color: Color(0xFFD9D9D9),
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    textTheme: const TextTheme(
      bodyMedium: TextStyle(color: Color(0xFFD9D9D9)),
      bodySmall: TextStyle(color: Color(0xFF787B86)),
    ),
    dividerColor: const Color(0xFF2B2B43),
    cardColor: const Color(0xFF1E222D),
  );

  ThemeData get _lightTheme => ThemeData.light().copyWith(
    scaffoldBackgroundColor: const Color(0xFFF5F7FA),
    colorScheme: const ColorScheme.light(
      primary: Color(0xFF00897B),
      secondary: Color(0xFFD32F2F),
      surface: Color(0xFFFFFFFF),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFFFFFFF),
      elevation: 0,
      titleTextStyle: TextStyle(
        color: Color(0xFF1E222D),
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    dividerColor: const Color(0xFFE0E0E0),
    cardColor: const Color(0xFFFFFFFF),
  );

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeMode,
      builder: (context, mode, _) {
        return MaterialApp(
          title: 'Backtester Shell',
          debugShowCheckedModeBanner: false,
          themeMode: mode,
          theme: _lightTheme,
          darkTheme: _darkTheme,
          navigatorKey: _navKey,
          scaffoldMessengerKey: _messengerKey,
          shortcuts: <ShortcutActivator, Intent>{
            ...WidgetsApp.defaultShortcuts,
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                const OpenCommandPaletteIntent(),
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
                const OpenCommandPaletteIntent(),
            const SingleActivator(LogicalKeyboardKey.keyR, control: true):
                const RunBacktestIntent(),
            const SingleActivator(LogicalKeyboardKey.keyE, control: true):
                const ExportHtmlIntent(),
            const SingleActivator(LogicalKeyboardKey.escape):
                const DismissOverlayIntent(),
          },
          builder: (ctx, child) {
            return ShortcutHooksProvider(
              hooks: _hooks,
              child: Actions(
                actions: <Type, Action<Intent>>{
                  OpenCommandPaletteIntent:
                      CallbackAction<OpenCommandPaletteIntent>(
                        onInvoke: (_) {
                          _openPalette();
                          return null;
                        },
                      ),
                  RunBacktestIntent: CallbackAction<RunBacktestIntent>(
                    onInvoke: (_) {
                      _runBacktest();
                      return null;
                    },
                  ),
                  ExportHtmlIntent: CallbackAction<ExportHtmlIntent>(
                    onInvoke: (_) {
                      _exportHtml();
                      return null;
                    },
                  ),
                  DismissOverlayIntent: CallbackAction<DismissOverlayIntent>(
                    onInvoke: (_) {
                      final nav = _navKey.currentState;
                      if (nav != null && nav.canPop()) nav.maybePop();
                      return null;
                    },
                  ),
                },
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const HomeScreen(),
        );
      },
    );
  }
}
