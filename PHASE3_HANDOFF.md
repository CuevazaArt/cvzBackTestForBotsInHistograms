# Phase 3 Handoff — Decision-Support Tools

**Status:** ✅ Complete and merged to main
**Tag:** `phase3-decision-tools` → commit `ef7df2b`
**PR:** [#9](https://github.com/CuevazaArt/cvzBackTestForBotsInHistograms/pull/9) — MERGED 2026-05-15

---

## What shipped

The project went from "you can run a backtest" to "you can decide whether to deploy this bot config with statistical evidence". Five capabilities added:

### 1. Walk-Forward Analysis (`backtester/analysis/walk_forward.py`)
**The question it answers:** "Is this setup actually robust, or did I overfit to one period?"

- Rolling in-sample (IS) / out-of-sample (OOS) windows with configurable train/test sizes and anchored or rolling modes
- Per-window Optuna optimization on IS, frozen-params evaluation on OOS
- Automatic verdict heuristic with 4 outcomes:
  - **robust** — OOS positive + efficiency >0.5 + >60% windows profitable + consistent
  - **weak** — OOS positive but unstable; re-tune or reduce size
  - **overfit** — IS optimization doesn't generalize; DO NOT deploy
  - **inconclusive** — Not enough data
- `efficiency_ratio` = mean(OOS) / mean(IS), clamped to [-2, 2]
- `consistency` = 1 - CV (coefficient of variation) of OOS returns

**API:** `POST /api/analysis/walk-forward`

### 2. Monte Carlo Simulation (`backtester/analysis/monte_carlo.py`)
**The question it answers:** "What's the worst credible drawdown I should plan for?"

- Two resampling methods:
  - **shuffle** — randomize trade order (preserves distribution, tests path-dependency)
  - **bootstrap** — sample with replacement (tests "if I'd had a different sample from this distribution")
- 1000+ trials with configurable seed for reproducibility
- Reports P5/P25/P50/P75/P95 for return %, max drawdown %, worst losing streak
- `prob_profit`, `prob_ruin` (configurable threshold default 50%, validated to (0,100])
- VaR 95% (Value-at-Risk) and CVaR 95% (Expected Shortfall) for sizing decisions
- Sample equity curves for visualization

**API:** `POST /api/analysis/monte-carlo` (accepts `run_id` or raw `trade_pnls`)

### 3. Robustness Score (`backtester/analysis/robustness.py`)
**The question it answers:** "Of N candidates, which one is most stable across multiple metrics?"

- Weighted composite (default):
  - Sharpe ratio: 35%
  - Profit Factor: 20%
  - Recovery Factor: 20%
  - Win Rate: 15%
  - Trade count penalty (<30 = unreliable): 10%
- Min-max normalization across candidate set
- Configurable weights via API
- Sorted leaderboard with per-component breakdown

**API:** `POST /api/analysis/robustness`

### 4. MAE/MFE per trade (engine.py + engine_stream.py)
**The question it answers:** "Did I exit too early? Are my stops in the right place?"

- `Position.update_excursion(high, low)` tracks running max favorable/adverse price
- `Trade` dataclass exposes:
  - `mfe_pct` — Max Favorable Excursion %
  - `mae_pct` — Max Adverse Excursion % (≤0)
  - `duration_bars` — how long the position was held
- Critical correctness fix (from PR review): excursions update BEFORE `bot.on_candle` so trades closed on the current bar capture that bar's full high/low range
- `_process_buy` seeds the excursion with the entry candle's range for same-candle exits
- Aggregate stats in `compute_metrics`:
  - `avg_mfe_pct`, `avg_mae_pct`, `max_mfe_pct`, `max_mae_pct`
  - `mfe_to_pnl_ratio` — exit-quality indicator (>2 ⟹ exits leave profit on the table)

### 5. Advanced metrics (metrics.py)
- **Ulcer Index** — RMS of % drawdowns at every bar; penalizes deep AND prolonged drawdowns
- **Recovery Factor** — total return / max DD; >2 strong, <1 concerning
- **Streak analysis** — max/avg consecutive wins and losses
- **Median trade duration** — complement to existing avg

### Frontend (flutter_app/lib/screens/analysis_screen.dart)
New "Analysis" sidebar tab with 4 sub-tabs:
- **History** — Browse persisted runs, filter by symbol/timeframe, detail panel with trade table including MFE%/MAE% columns
- **Walk-Forward** — Config form, JSON param ranges, verdict card (color-coded), per-window IS/OOS table
- **Monte Carlo** — Select a run, percentile tables, big risk metrics (P(profit), P(ruin), VaR, CVaR), sample equity curves rendered via CustomPainter
- **Robustness** — Gold/silver/bronze leaderboard ranking all saved runs

All UI uses the existing `ApiService` (with `x-api-key` auth from Phase 2.5).

---

## Code review fixes (gemini-code-assist[bot])

4 comments addressed before merge:

1. **High** — engine.py MFE/MAE update ran AFTER orders, so exit candle's high/low was excluded from the trade. Fixed by moving update before `bot.on_candle` + seeding from entry candle in `_process_buy`. New regression test `test_mfe_mae_includes_exit_candle_range` verifies a position closed on a 130/70 candle reports MFE≥29% and MAE≤-29%.
2. **High** — Same bug in StreamingEngine, same fix.
3. **Medium** — Hardcoded 50% ruin threshold made configurable via `MonteCarloConfig.ruin_drawdown_pct` (validated to (0,100]). Tests verify conservative threshold → higher prob_ruin.
4. **Medium** — `param_ranges` could raise IndexError on malformed input. Added validation in `POST /api/analysis/walk-forward` that returns HTTP 422 with a clear message if any entry isn't exactly `[low, high]` with `low < high`.

All 4 review threads resolved via GraphQL.

---

## Tests & quality

| Metric | Phase 2 end | Phase 3 end |
|---|---|---|
| Backend tests | 64 | **92** (+18 new in `test_analysis.py`) |
| Ruff lint | clean | clean |
| Flutter analyze | clean | clean (only pre-existing info-level warnings) |
| CI matrix | all green | all green (Ubuntu+Windows × Py 3.11/3.12 + Flutter) |

Test highlights in `backtester/tests/test_analysis.py`:
- MAE/MFE recording on closed trades
- Regression test for exit-bar inclusion (would have caught the high-priority bug)
- Window generation (rolling vs anchored)
- Verdict logic for `overfit` and `robust` scenarios
- MC determinism: shuffle preserves mean, bootstrap widens variance, percentiles ordered
- MC configurable ruin threshold + invalid threshold rejection
- Robustness ranking ordering + low-trade-count penalty

---

## File-level map

### Backend (new)
- `backtester/analysis/__init__.py`
- `backtester/analysis/walk_forward.py` (~280 LOC)
- `backtester/analysis/monte_carlo.py` (~255 LOC)
- `backtester/analysis/robustness.py` (~155 LOC)
- `backtester/api/routes/analysis.py` (~255 LOC)
- `backtester/tests/test_analysis.py` (~365 LOC)

### Backend (modified)
- `backtester/core/engine.py` — Position MFE/MAE, Trade fields, update_excursion timing
- `backtester/core/engine_stream.py` — same fields, WS event payload includes them
- `backtester/core/metrics.py` — Ulcer, recovery, streaks, excursion aggregates
- `backtester/api/routes/__init__.py`, `backtester/api/server.py` — register analysis router

### Frontend (new)
- `flutter_app/lib/screens/analysis_screen.dart` (~1200 LOC, 4 tabs)

### Frontend (modified)
- `flutter_app/lib/services/api_service.dart` — listResults, getResult, deleteResult, runWalkForward, runMonteCarlo, rankRobustness (all auth-aware)
- `flutter_app/lib/screens/home_screen.dart` — Analysis tab in sidebar

---

## Quick start

```powershell
# Backend
cd backtester
..\.venv\Scripts\Activate.ps1
uvicorn backtester.api.server:app --host 127.0.0.1 --port 8002

# Frontend
cd flutter_app
flutter run -d windows
```

Open **Analysis** in the sidebar. Run a backtest first from the **Backtest** tab — it persists via the `ResultStore`. Then go to Analysis → History to see it; click a run to use it as the basis for Monte Carlo. Rank all your runs in the Robustness tab.

For Walk-Forward, supply the param ranges as JSON:
```json
{"fast_ema": [5, 20], "slow_ema": [21, 50]}
```

---

## Phase 4 candidates (future work)

Already strong, but if you want more:

- **Walk-Forward streaming** — currently synchronous; add a `/ws` action for live per-window progress
- **Monte Carlo with stop-loss override** — "what if I had a 5% trailing stop?"
- **Trade clustering** — bucket trades by hour-of-day / day-of-week to detect regime dependencies
- **Multi-symbol portfolio** — current engine is single-symbol; correlation-aware portfolio analytics would extend it
- **Benchmark comparison** — alpha/beta vs buy-and-hold BTC
- **Live paper trading** — wire the engine to a Binance WebSocket and run a strategy on live candles
- **Real-time alerts** — email/SMS on signal triggers
