# Changelog

## v1.0.0 — Flutter Desktop rewrite (single-binary)

**Breaking**: full rewrite. The Python FastAPI backend (`backtester/`) and the
legacy Flutter WebView shell (`flutter_app/`) are gone. The whole tool now
ships as one Flutter desktop binary under `app/`.

### Added
- `app/` — Flutter desktop app, single binary, no separate server.
- Dart-pure backtest engine (`app/lib/core/`): candle loop, order matcher,
  bracket manager, MFE/MAE, FIFO close, fees + slippage.
- Streaming O(1) indicators: EMA, SMA, RSI (Wilder), MACD, Bollinger,
  Stochastic, VWAP.
- Bot framework + 8 bots ported (EMA cross, RSI reversion, MACD cross,
  Bollinger reversion, Dorothy DCA, Elphaba short, Donchian breakout, grid)
  plus YAML DSL.
- SQLite storage via `drift` (WAL, typed migrations) with absolute path via
  `path_provider` — no more relative-path data loss.
- Isolate-based engine worker with typed sealed message protocol — no
  thread/asyncio races.
- WebView chart with v5.2.0 Lightweight Charts bundled as asset and a command
  buffer that retries pre-ready calls.
- Riverpod state for downloads, backtests, theme.
- Screens: home, backtest, analysis, optimization (with heatmap), download,
  settings. Command palette (Ctrl+K).
- Analytics: Sharpe, Sortino, Calmar, Ulcer, PSR, DSR, Monte Carlo bootstrap,
  walk-forward with efficiency ratio, stress battery.
- Auto-save results + bot presets + DSL editor + data quality UI.

### Removed
- `backtester/` — Python FastAPI + DuckDB backend.
- `flutter_app/` — old Flutter WebView shell.
- `Dockerfile`, `docker-compose.yml`, `.dockerignore`, `pyproject.toml`,
  `.pre-commit-config.yaml`, `examples/` (Python notebooks),
  `scratch_test.py`, `.env.example`.
- CI: Python lint / typecheck / pytest / SDK packaging / Docker smoke jobs.
- Historic planning docs (`WORKPLAN.md`, `BACKLOG.md`, `DEVNOTES.md`,
  `PHASE2_HANDOFF.md`, `PHASE3_HANDOFF.md`).

### CI
Replaced Python-centric pipeline with two Flutter jobs: `flutter pub get
&& flutter analyze && flutter test` on Linux, plus a Windows release build
that uploads `cvz_backtester.exe` as an artifact.

---

## v0.6.0 (last Python release — preserved in git history)

- Engine realism: `fill_on_next_open` for MARKET execution and short-selling
  lifecycle with short-aware equity and bracket exits.
- Advanced analytics: probabilistic / deflated Sharpe + stress battery
  endpoint (`POST /api/backtest/{run_id}/stress`).
- Strategy set expanded with `DonchianBreakout` and `GridTrading`.
- Data quality vertical slice: `validate_ohlcv`, thread-safe Binance weight
  tracker, `POST /api/data/validate`.
- DevEx: added `Dockerfile`, `docker-compose.yml`, `.dockerignore`,
  `.pre-commit-config.yaml`, and CI jobs.
- UX: command palette (`Ctrl/Cmd+K`) with keyboard actions and data
  validation action from Backtest screen.
- Quality: property-based tests (`hypothesis`) and opt-in benchmark tests
  (`pytest-benchmark`).
