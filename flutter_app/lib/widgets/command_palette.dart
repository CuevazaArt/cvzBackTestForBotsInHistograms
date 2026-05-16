// Command palette: a centered modal overlay (VS Code / Linear / Slack style)
// with a search field, fuzzy-matched action list, and full keyboard control.
//
// Typical usage:
//
//   await showCommandPalette(context, actions: [
//     CommandAction(
//       id: 'nav.backtest',
//       label: 'Navigate to Backtest',
//       icon: Icons.candlestick_chart,
//       shortcut: 'Ctrl+1',
//       onInvoke: () => navigator.go(0),
//     ),
//     ...
//   ]);
//
// The palette also defines [OpenCommandPaletteIntent] for wiring to a
// global `Ctrl+K` / `Cmd+K` shortcut at the [MaterialApp] level, plus a
// lightweight [ShortcutHooks] / [ShortcutHooksProvider] registry so screens
// can plug in handlers (run, export, navigate) without importing `app.dart`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Public types ──────────────────────────────────────────────

/// One row in the command palette.
@immutable
class CommandAction {
  /// Stable identifier (used as a ValueKey, useful for golden tests).
  final String id;

  /// Human-readable label shown in the list.
  final String label;

  /// Leading icon displayed in the row.
  final IconData icon;

  /// Optional human-readable hint (e.g. "Ctrl+R") rendered on the right.
  final String? shortcut;

  /// Callback fired when the row is invoked (Enter or tap).
  final VoidCallback onInvoke;

  const CommandAction({
    required this.id,
    required this.label,
    required this.icon,
    this.shortcut,
    required this.onInvoke,
  });
}

/// Intent dispatched by the global `Ctrl+K` / `Cmd+K` shortcut.
class OpenCommandPaletteIntent extends Intent {
  const OpenCommandPaletteIntent();
}

/// Mutable hook registry. Screens register callbacks here so global keyboard
/// shortcuts and palette actions can hand off work without holding direct
/// references to the screens.
class ShortcutHooks {
  /// Opens the palette overlay. Set by [BacktesterApp].
  VoidCallback? openPalette;

  /// Triggers the currently visible "Run backtest" button if one exists.
  VoidCallback? runBacktest;

  /// Exports the currently selected run as HTML if any.
  VoidCallback? exportHtml;

  /// Returns the currently selected run id, or null if none.
  String? Function()? currentRunId;

  /// Switches the home screen tab. 0=Backtest, 1=Optimize, 2=Analysis,
  /// 3=Settings.
  void Function(int index)? navigateTo;

  /// Toggles light / dark theme.
  VoidCallback? toggleTheme;

  ShortcutHooks();
}

/// Inherited container that exposes a single [ShortcutHooks] instance
/// to descendants of [BacktesterApp].
class ShortcutHooksProvider extends InheritedWidget {
  final ShortcutHooks hooks;

  const ShortcutHooksProvider({
    super.key,
    required this.hooks,
    required super.child,
  });

  static ShortcutHooks? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShortcutHooksProvider>()?.hooks;

  static ShortcutHooks of(BuildContext context) {
    final h = maybeOf(context);
    assert(h != null, 'ShortcutHooksProvider missing in context');
    return h!;
  }

  @override
  bool updateShouldNotify(covariant ShortcutHooksProvider old) =>
      hooks != old.hooks;
}

// ── Modal opener ──────────────────────────────────────────────

/// Shows the command palette as a centered modal overlay.
///
/// Returns when the user dismisses or invokes a command.
Future<void> showCommandPalette(
  BuildContext context, {
  required List<CommandAction> actions,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    barrierDismissible: true,
    builder: (ctx) => SafeArea(
      child: Align(
        alignment: const Alignment(0, -0.4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: SizedBox(
            width: 500,
            child: CommandPalette(
              actions: actions,
              onClose: () => Navigator.of(ctx).maybePop(),
            ),
          ),
        ),
      ),
    ),
  );
}

// ── Main widget ───────────────────────────────────────────────

/// The visual + behavioural body of the palette: search input, filtered list,
/// and a small keyboard-hint bar.
///
/// Designed to be embeddable: drop it inside a [Dialog], [Card] or [Scaffold]
/// — sizing is handled internally with sensible max-bounds.
class CommandPalette extends StatefulWidget {
  /// Available actions. The component does not mutate this list.
  final List<CommandAction> actions;

  /// Called when the user dismisses the palette (Esc) or after invoking
  /// an action. Defaults to `Navigator.maybePop` if not provided.
  final VoidCallback? onClose;

  /// Optional initial query (mainly for tests).
  final String initialQuery;

  const CommandPalette({
    super.key,
    required this.actions,
    this.onClose,
    this.initialQuery = '',
  });

  @override
  State<CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<CommandPalette> {
  late final TextEditingController _ctrl;
  late final FocusNode _searchFocus;
  late final ScrollController _listCtrl;
  String _query = '';
  int _highlightIdx = 0;
  late List<CommandAction> _filtered;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery;
    _ctrl = TextEditingController(text: widget.initialQuery);
    _searchFocus = FocusNode(debugLabel: 'CommandPalette.search');
    _listCtrl = ScrollController();
    _filtered = filterCommandActions(widget.actions, _query);
    _ctrl.addListener(_onQueryChanged);
  }

  @override
  void didUpdateWidget(covariant CommandPalette old) {
    super.didUpdateWidget(old);
    if (old.actions != widget.actions) {
      _filtered = filterCommandActions(widget.actions, _query);
      _highlightIdx = _highlightIdx.clamp(
        0,
        _filtered.isEmpty ? 0 : _filtered.length - 1,
      );
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onQueryChanged);
    _ctrl.dispose();
    _searchFocus.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    if (_ctrl.text == _query) return;
    setState(() {
      _query = _ctrl.text;
      _filtered = filterCommandActions(widget.actions, _query);
      _highlightIdx = 0;
    });
  }

  void _moveDown() {
    if (_filtered.isEmpty) return;
    setState(() {
      _highlightIdx = (_highlightIdx + 1) % _filtered.length;
    });
    _ensureHighlightVisible();
  }

  void _moveUp() {
    if (_filtered.isEmpty) return;
    setState(() {
      _highlightIdx = (_highlightIdx - 1 + _filtered.length) % _filtered.length;
    });
    _ensureHighlightVisible();
  }

  void _ensureHighlightVisible() {
    if (!_listCtrl.hasClients) return;
    const rowH = 40.0;
    final target = _highlightIdx * rowH;
    final viewport = _listCtrl.position.viewportDimension;
    final offset = _listCtrl.offset;
    if (target < offset) {
      _listCtrl.jumpTo(target);
    } else if (target > offset + viewport - rowH) {
      _listCtrl.jumpTo(target - viewport + rowH);
    }
  }

  void _invoke() {
    if (_filtered.isEmpty) return;
    final action = _filtered[_highlightIdx];
    _close();
    action.onInvoke();
  }

  void _invokeAt(int idx) {
    if (idx < 0 || idx >= _filtered.length) return;
    final action = _filtered[idx];
    _close();
    action.onInvoke();
  }

  void _close() {
    final cb = widget.onClose;
    if (cb != null) {
      cb();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.arrowDown): _MovePaletteDownIntent(),
        SingleActivator(LogicalKeyboardKey.arrowUp): _MovePaletteUpIntent(),
        SingleActivator(LogicalKeyboardKey.escape): _DismissPaletteIntent(),
        SingleActivator(LogicalKeyboardKey.enter): _InvokePaletteIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _InvokePaletteIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _MovePaletteDownIntent: CallbackAction<_MovePaletteDownIntent>(
            onInvoke: (_) {
              _moveDown();
              return null;
            },
          ),
          _MovePaletteUpIntent: CallbackAction<_MovePaletteUpIntent>(
            onInvoke: (_) {
              _moveUp();
              return null;
            },
          ),
          _DismissPaletteIntent: CallbackAction<_DismissPaletteIntent>(
            onInvoke: (_) {
              _close();
              return null;
            },
          ),
          _InvokePaletteIntent: CallbackAction<_InvokePaletteIntent>(
            onInvoke: (_) {
              _invoke();
              return null;
            },
          ),
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500, maxHeight: 480),
          child: Material(
            color: const Color(0xFF1E222D),
            elevation: 12,
            shadowColor: Colors.black,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSearchField(),
                const Divider(height: 1, color: Color(0xFF2B2B43)),
                Flexible(
                  child: _filtered.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 28),
                          child: Center(
                            child: Text(
                              'No matching commands',
                              style: TextStyle(
                                color: Color(0xFF787B86),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _listCtrl,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _filtered.length,
                          itemBuilder: (ctx, i) {
                            final a = _filtered[i];
                            return _PaletteRow(
                              key: ValueKey('palette-row-${a.id}'),
                              action: a,
                              highlighted: i == _highlightIdx,
                              onTap: () => _invokeAt(i),
                            );
                          },
                        ),
                ),
                const Divider(height: 1, color: Color(0xFF2B2B43)),
                const _PaletteFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: TextField(
        controller: _ctrl,
        focusNode: _searchFocus,
        autofocus: true,
        style: const TextStyle(color: Color(0xFFD9D9D9), fontSize: 14),
        cursorColor: const Color(0xFF26a69a),
        decoration: const InputDecoration(
          hintText: 'Type a command…',
          hintStyle: TextStyle(color: Color(0xFF787B86), fontSize: 13),
          prefixIcon: Icon(Icons.search, size: 18, color: Color(0xFF787B86)),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          filled: true,
          fillColor: Color(0xFF131722),
          border: OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF26a69a), width: 1),
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  final CommandAction action;
  final bool highlighted;
  final VoidCallback onTap;

  const _PaletteRow({
    super.key,
    required this.action,
    required this.highlighted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: highlighted
            ? const Color(0xFF26a69a).withValues(alpha: 0.18)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(
              action.icon,
              size: 16,
              color: highlighted
                  ? const Color(0xFF26a69a)
                  : const Color(0xFF787B86),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                action.label,
                style: TextStyle(
                  color: highlighted ? Colors.white : const Color(0xFFD9D9D9),
                  fontSize: 13,
                  fontWeight: highlighted ? FontWeight.w500 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (action.shortcut != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF131722),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF2B2B43)),
                ),
                child: Text(
                  action.shortcut!,
                  style: const TextStyle(
                    color: Color(0xFF787B86),
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaletteFooter extends StatelessWidget {
  const _PaletteFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: const [
          _Hint(label: '↑↓', text: 'Navigate'),
          SizedBox(width: 12),
          _Hint(label: '↵', text: 'Invoke'),
          SizedBox(width: 12),
          _Hint(label: 'esc', text: 'Close'),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String label;
  final String text;
  const _Hint({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: const Color(0xFF131722),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: const Color(0xFF2B2B43)),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Color(0xFFD9D9D9),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(color: Color(0xFF787B86), fontSize: 10),
        ),
      ],
    );
  }
}

// ── Fuzzy filter ──────────────────────────────────────────────

/// Returns the subset of [all] whose label loosely matches [query], sorted
/// by relevance (best match first). Empty / whitespace queries return all.
@visibleForTesting
List<CommandAction> filterCommandActions(
  List<CommandAction> all,
  String query,
) {
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return List.of(all);
  final scored = <_Scored>[];
  for (final a in all) {
    final s = fuzzyScoreLabel(q, a.label);
    if (s < 999) scored.add(_Scored(a, s));
  }
  scored.sort((a, b) => a.score.compareTo(b.score));
  return [for (final e in scored) e.action];
}

/// Lower scores are better matches. ≥ 999 means no match.
///
/// Strategy:
/// * exact match            → -100
/// * label starts with q    → -50
/// * substring match        → indexOf (the earlier the better)
/// * acronym match          → 200 (e.g. "rl" matches "Run Last")
/// * otherwise              → 1000 (drop)
@visibleForTesting
double fuzzyScoreLabel(String query, String label) {
  final q = query.toLowerCase().trim();
  if (q.isEmpty) return 0;
  final l = label.toLowerCase();
  if (l == q) return -100;
  if (l.startsWith(q)) return -50;
  final idx = l.indexOf(q);
  if (idx >= 0) return idx.toDouble();
  // Acronym: collapse to first letter of each word/segment.
  final acronym = label
      .split(RegExp(r'[\s_\-/]+'))
      .where((w) => w.isNotEmpty)
      .map((w) => w[0])
      .join()
      .toLowerCase();
  if (acronym.contains(q)) return 200.0;
  return 1000.0;
}

class _Scored {
  final CommandAction action;
  final double score;
  _Scored(this.action, this.score);
}

// ── Internal intents ──────────────────────────────────────────

class _MovePaletteDownIntent extends Intent {
  const _MovePaletteDownIntent();
}

class _MovePaletteUpIntent extends Intent {
  const _MovePaletteUpIntent();
}

class _DismissPaletteIntent extends Intent {
  const _DismissPaletteIntent();
}

class _InvokePaletteIntent extends Intent {
  const _InvokePaletteIntent();
}
