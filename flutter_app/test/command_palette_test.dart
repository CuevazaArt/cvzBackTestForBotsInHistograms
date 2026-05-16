// Widget tests for the command palette overlay.
//
// Covers the four behaviours called out in plan slice S6:
//   1. Tapping the trigger or pressing Ctrl+K opens the palette.
//   2. Typing "back" filters the list to "Navigate to Backtest" only.
//   3. Pressing Esc closes an open palette.
//   4. Pressing Enter invokes the highlighted action's callback.
//
// We pump small, hermetic harnesses (no [BacktesterApp], no backend) so that
// the tests don't pull WebSocket / HTTP timers in.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:backtester_shell/widgets/command_palette.dart';

List<CommandAction> _navActions({Map<String, int>? counters}) {
  void inc(String id) {
    if (counters != null) {
      counters[id] = (counters[id] ?? 0) + 1;
    }
  }

  return [
    CommandAction(
      id: 'nav.backtest',
      label: 'Navigate to Backtest',
      icon: Icons.candlestick_chart,
      onInvoke: () => inc('nav.backtest'),
    ),
    CommandAction(
      id: 'nav.optimize',
      label: 'Navigate to Optimize',
      icon: Icons.science_outlined,
      onInvoke: () => inc('nav.optimize'),
    ),
    CommandAction(
      id: 'nav.analysis',
      label: 'Navigate to Analysis',
      icon: Icons.analytics_outlined,
      onInvoke: () => inc('nav.analysis'),
    ),
    CommandAction(
      id: 'nav.settings',
      label: 'Navigate to Settings',
      icon: Icons.settings_outlined,
      onInvoke: () => inc('nav.settings'),
    ),
  ];
}

void main() {
  group('CommandPalette', () {
    setUp(() {
      // Wider test surface so the palette has room to render.
    });

    testWidgets('tapping the trigger button opens the palette overlay', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final actions = _navActions();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showCommandPalette(ctx, actions: actions),
                  child: const Text('Open palette'),
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byType(CommandPalette), findsNothing);

      await tester.tap(find.text('Open palette'));
      await tester.pumpAndSettle();

      expect(find.byType(CommandPalette), findsOneWidget);
      expect(find.text('Navigate to Backtest'), findsOneWidget);
    });

    testWidgets('Ctrl+K via the global shortcut opens the palette', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final actions = _navActions();

      await tester.pumpWidget(
        MaterialApp(
          shortcuts: <ShortcutActivator, Intent>{
            ...WidgetsApp.defaultShortcuts,
            const SingleActivator(LogicalKeyboardKey.keyK, control: true):
                const OpenCommandPaletteIntent(),
          },
          home: Builder(
            builder: (ctx) => Actions(
              actions: <Type, Action<Intent>>{
                OpenCommandPaletteIntent:
                    CallbackAction<OpenCommandPaletteIntent>(
                      onInvoke: (_) {
                        showCommandPalette(ctx, actions: actions);
                        return null;
                      },
                    ),
              },
              child: const Scaffold(
                body: Focus(
                  autofocus: true,
                  child: Center(child: Text('home')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsNothing);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPalette), findsOneWidget);
    });

    testWidgets(
      'typing "back" filters the list to "Navigate to Backtest" only',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 500,
                  child: CommandPalette(actions: _navActions(), onClose: () {}),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Initially every navigation action is visible.
        expect(find.text('Navigate to Backtest'), findsOneWidget);
        expect(find.text('Navigate to Optimize'), findsOneWidget);
        expect(find.text('Navigate to Analysis'), findsOneWidget);
        expect(find.text('Navigate to Settings'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'back');
        await tester.pumpAndSettle();

        expect(find.text('Navigate to Backtest'), findsOneWidget);
        expect(find.text('Navigate to Optimize'), findsNothing);
        expect(find.text('Navigate to Analysis'), findsNothing);
        expect(find.text('Navigate to Settings'), findsNothing);
      },
    );

    testWidgets('pressing Esc closes the open palette', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final actions = _navActions();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showCommandPalette(ctx, actions: actions),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(CommandPalette), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(CommandPalette), findsNothing);
    });

    testWidgets('pressing Enter invokes the highlighted action', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final invocations = <String>[];
      final actions = [
        CommandAction(
          id: 'go',
          label: 'Run Last Backtest',
          icon: Icons.play_arrow,
          onInvoke: () => invocations.add('go'),
        ),
        CommandAction(
          id: 'no',
          label: 'Should not run',
          icon: Icons.close,
          onInvoke: () => invocations.add('no'),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 500,
                child: CommandPalette(actions: actions, onClose: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // First row is highlighted by default.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(invocations, equals(['go']));
    });

    testWidgets('arrow-down then Enter invokes the SECOND row', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final invocations = <String>[];
      final actions = [
        CommandAction(
          id: 'first',
          label: 'First action',
          icon: Icons.play_arrow,
          onInvoke: () => invocations.add('first'),
        ),
        CommandAction(
          id: 'second',
          label: 'Second action',
          icon: Icons.play_arrow,
          onInvoke: () => invocations.add('second'),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 500,
                child: CommandPalette(actions: actions, onClose: () {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(invocations, equals(['second']));
    });
  });

  group('fuzzy matching', () {
    test('substring match outranks acronym match', () {
      final acts = [
        CommandAction(
          id: 'restart',
          label: 'Restart',
          icon: Icons.refresh,
          onInvoke: () {},
        ),
        CommandAction(
          id: 'rl',
          label: 'Run Last',
          icon: Icons.play_arrow,
          onInvoke: () {},
        ),
      ];
      // "re" is a prefix of "Restart", but only an acronym hit for "Run Last"
      // → Restart should come first.
      final filtered = filterCommandActions(acts, 're');
      expect(filtered.first.id, equals('restart'));
    });

    test('acronym match: "rl" matches "Run Last"', () {
      final acts = [
        CommandAction(
          id: 'rl',
          label: 'Run Last',
          icon: Icons.play_arrow,
          onInvoke: () {},
        ),
        CommandAction(
          id: 'other',
          label: 'Quit Application',
          icon: Icons.close,
          onInvoke: () {},
        ),
      ];
      final filtered = filterCommandActions(acts, 'rl');
      expect(filtered.length, equals(1));
      expect(filtered.first.id, equals('rl'));
    });

    test('empty query returns the original list (preserving order)', () {
      final acts = _navActions();
      final filtered = filterCommandActions(acts, '');
      expect(filtered.length, equals(acts.length));
      expect(filtered.map((a) => a.id), orderedEquals(acts.map((a) => a.id)));
    });

    test('exact label match scores best', () {
      expect(fuzzyScoreLabel('hello', 'hello'), lessThan(-50));
      expect(fuzzyScoreLabel('hello', 'hello world'), lessThan(0));
      expect(fuzzyScoreLabel('xyz', 'hello world'), greaterThan(500));
    });
  });
}
