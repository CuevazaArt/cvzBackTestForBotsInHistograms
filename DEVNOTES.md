# Developer notes

Living notes for things that are useful to know but don't belong in the README,
the changelog, or a code comment. Keep it terse — one section per topic.

## Branch topology (post 2026-05-17)

```
origin/main    ←  ACTIVE, real project. 5-screen UI, DuckDB, port 8002.
                  Tag v3.0-main-baseline marks the start of post-cleanup work.

origin/master  ←  DEPRECATED. Replay+overlay prototype ("blue UI"). Kept as
                  historical reference behind tag v2.0-mvp-functional. README
                  carries a deprecation banner. Do not target new work here.
```

### Why two divergent histories?

A "master" branch and a "main" branch evolved in parallel without sharing a
common ancestor:

- `origin/main` grew the production-grade stack: DuckDB downloader with resume
  & cancel, 5 dedicated screens (Backtest / Analysis / Optimization /
  Settings / Home), ZIP ingestion, walk-forward + monte carlo, deflated
  Sharpe, command palette, weight-monitor middleware, and a 564-line
  embedded chart bridge (`backtester/web/index.html`) driven by an
  11-method controller in `chart_webview.dart`.
- `origin/master` was an earlier prototype that focused on step-by-step
  candle replay and a pluggable overlay system (`backtester/web/assets/js/
  charts/{replay,overlays,main-chart}.js`). It used SQLite, port 8000, and
  a `flutter_inappwebview`-based chart that never compiled cleanly on
  Windows (the package shipped with broken headers in 6.x).

A short session in May 2026 tried to operate on master:

1. Started backend on the wrong port for master's code (`8002` instead of
   `8000`) — the chart panel sat on a spinner forever.
2. Diagnosed the chart panel as a runtime bug, then realised the WebView
   plugin itself wouldn't compile. Swapped `flutter_inappwebview` for
   `webview_windows`.
3. Added a topbar "Download history" button with live progress polling so
   the user could actually populate a candle DB before running a backtest.
4. Squash-merged the work into master as PR #13 and tagged
   `v2.0-mvp-functional` to mark the first end-to-end working state of the
   blue UI.
5. Realised origin/main was the real project, switched the worktree to it,
   confirmed it has more mature equivalents of everything PR #13 added,
   and marked master as deprecated.

194 files differ between origin/main and origin/master. There is no
shared merge base.

### What's salvageable from master?

After auditing each "master-only" file against main's equivalents:

| Master artifact | Main equivalent | Decision |
|---|---|---|
| `download_history_dialog.dart` | Download flow inside BacktestScreen | Skip — main's is integrated |
| `chart_webview.dart` with 20 s watchdog | `chart_webview.dart` with watchdog + ready polling + DIAG probe + 11-method controller | Skip — main's is more sophisticated |
| `downloader.py` with `progress_callback` | `downloader.py` with `on_progress` + resume + cancel + ZIP path | Skip — main's is a superset |
| `HomeScreen` + sidebar + 3 bottom tabs | 5 dedicated screens with command palette | Skip — main's separation is cleaner |
| `topbar.dart` with chips + download button | Per-screen topbars + Ctrl/Cmd+K command palette | Skip — main covers the same surface |
| `web/assets/js/charts/replay.js` (157 LOC) | Replay equivalents live inside the inline bridge in `index.html` | **Look closer** — see "open follow-ups" below |
| `web/assets/js/charts/overlays.js` (277 LOC) | `initIndicators` / `initOscillators` / `initBotSeries` controller methods | **Look closer** — see "open follow-ups" below |
| Tag `v1.6.2-timestamp-migration` | DuckDB on main avoids the μs/ms drift entirely | Skip — different storage |

The only genuinely interesting things in master are `replay.js` and
`overlays.js`. Before deciding whether to port any of their ideas, audit
main's `index.html` (`window.setChartFormula`, `window.addCandle`,
`window.setCandles`, `window.addTradeMarker`) — chances are the same
behaviour is already covered.

## Open follow-ups

- Decide whether step-by-step replay (advance one candle at a time, show
  bot state at every bar) is a feature worth adding to main. If yes, draw
  from master's `replay.js` as a reference but reimplement on top of main's
  bridge, not by porting the file.
- Decide whether "pluggable overlays" (user-defined indicator scripts
  loaded at runtime) is worth carrying over. Today main has a fixed set
  of indicators/oscillators wired via `initIndicators` / `initOscillators`.
