# cvz-backtester

> **Trading bot backtester — single-binary Flutter Desktop app**
> Engine in pure Dart · SQLite (drift) · embedded chart · no separate server.

## What this is

A desktop application for backtesting crypto trading bots against historical
candle data from Binance. Everything — engine, indicators, bots, storage,
chart, UI — ships in a single `cvz_backtester.exe` (~22 MB + Flutter runtime).

No Python. No FastAPI. No DuckDB. No WebSocket bridge. The backtest engine
runs in a Dart isolate; the UI talks to it through typed sealed messages.

## Features

- **Engine** — candle-by-candle loop with realistic fills, MARKET / LIMIT /
  STOP, bracket orders (SL / TP / trailing), short-selling, MFE/MAE tracking,
  FIFO close, fees + slippage.
- **Indicators** — streaming O(1) per bar: EMA, SMA, RSI (Wilder), MACD,
  Bollinger, Stochastic, VWAP.
- **Bots** — EMA crossover, RSI reversion, MACD cross, Bollinger reversion,
  Dorothy DCA, Elphaba short, Donchian breakout, grid trading, plus a YAML
  DSL for declarative strategies.
- **Data** — Binance REST klines downloader with resume, retry, rate limit;
  SQLite WAL via `drift`; quality validator (gaps, duplicates, OHLC sanity).
- **Analysis** — Sharpe, Sortino, Calmar, Ulcer, profit factor, win rate,
  PSR, DSR; Monte Carlo bootstrap with P5–P95 bands; walk-forward analysis
  with efficiency ratio; stress tests (fee/slippage multipliers, drop best N%).
- **UI** — backtest runner with chart + markers, equity curve, trades table;
  parameter optimization with heatmap; data manager with quality reports;
  results history; command palette (Ctrl+K); light + dark themes.

## Run it

Prereqs: [Flutter SDK](https://docs.flutter.dev/get-started/install) (channel
`stable`), Windows 10/11 with Visual Studio Build Tools (Desktop C++ workload).

```bash
cd app
flutter pub get
flutter run -d windows
```

For a release build:

```bash
flutter build windows --release
# Binary: app/build/windows/x64/runner/Release/cvz_backtester.exe
```

## Repository layout

```
app/                            Flutter desktop app (the only source tree)
├── lib/
│   ├── core/                   Backtest engine (Dart-pure, zero Flutter deps)
│   │   ├── models/             Candle, Position, Trade, Portfolio, Order, …
│   │   ├── engine.dart         BacktestEngine — main loop
│   │   ├── order_matcher.dart  Trigger logic (limit / stop / trailing)
│   │   └── bracket_manager.dart  SL/TP/trailing children
│   ├── indicators/             Streaming O(1) per-bar indicators
│   ├── bots/                   Strategy framework + 8 built-in bots + DSL
│   ├── data/                   drift database + Binance downloader + quality
│   ├── analysis/               Metrics, Monte Carlo, walk-forward, stress
│   ├── state/                  Riverpod providers
│   ├── screens/                UI screens (home / backtest / analysis / …)
│   └── widgets/                Reusable widgets (chart, heatmap, tables, …)
├── assets/chart/               Bundled Lightweight Charts v5.2.0 + index.html
├── test/                       Unit + widget tests
└── windows/                    Windows runner (CMake)
```

## Architecture

```
┌──────────────────────────────────────────────────┐
│                 cvz_backtester.exe                │
│  ┌─────────────────┐       ┌──────────────────┐   │
│  │   Flutter UI    │◄─────►│  Engine Isolate  │   │
│  │  (main thread)  │ ports │   (Dart pure)    │   │
│  └────────┬────────┘       └────────┬─────────┘   │
│           │                          │             │
│           ▼                          ▼             │
│  ┌─────────────────┐       ┌──────────────────┐   │
│  │  WebView chart  │       │  SQLite (drift)  │   │
│  │  v5.2.0 bundled │       │   WAL, indexed   │   │
│  └─────────────────┘       └──────────────────┘   │
└──────────────────────────────────────────────────┘
```

Communication between UI and engine is over typed sealed message classes
through `SendPort`s — no threads, no asyncio, no race conditions.

## Why a rewrite?

The previous architecture (Python FastAPI + Flutter WebView + WebSocket) was
structurally fragile: WAL locks lost data on relative paths, the chart
shipped v4 JS against v5 API calls, and a 3-process model accumulated race
conditions between threading and asyncio. The rewrite collapses that into one
binary with typed boundaries. The old `flutter_app/` and `backtester/`
(Python) trees have been removed — git history preserves them if needed.

## Development

```bash
cd app
flutter pub get
flutter analyze
flutter test

# Regenerate drift / freezed / json / riverpod codegen after schema changes:
dart run build_runner build --delete-conflicting-outputs
```

## License

MIT — see [LICENSE](LICENSE).
