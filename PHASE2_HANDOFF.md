# Phase 3+ Handoff Prompt for Next Agent

## Project Status (2026-05-15)

**Phase 2 Complete:** All 7 deliverables merged to main (tag: `phase2-complete`)
- Backend (Track A): IndicatorCache, Resumable Downloads, Result Persistence
- Frontend (Track B): OptimizationHeatmap, ValidationErrorDialog, Presets UI, fakeAsync Migration
- **CI/CD:** All checks green. pytest (64 tests ✓), ruff, mypy, flutter analyze passing

**Test Coverage:**
- Backend: 64 unit/integration tests
- Frontend: 10+ flutter widget tests
- API: Full HTTP integration tests

**Production Readiness:** ~75% (core features solid, needs Phase 3 polish)

---

## Architecture Overview

### Critical Design Decisions (Phase 2)

#### 1. **IndicatorCache (A1)**
- LRU cache keyed by `(symbol, timeframe, candles_fingerprint, spec_hash)`
- Integrated into StreamingEngine, Objective, ExperimentRunner
- Files: `backtester/core/cache.py`, wired in `backtester/api/deps.py`
- Tests: `backtester/tests/test_runner_cache.py` (4 tests)

#### 2. **Resumable Downloads (A2)**
- Track `last_timestamp_ms`; accept `?resume_job_id` to restart from checkpoint
- Files: `backtester/core/downloader.py`, `backtester/api/routes/candles.py`
- Tests: `backtester/tests/test_download_resume.py` (4 tests)

#### 3. **Result Persistence (A3)**
- SQLite ResultStore with run_id UUID; /ws captures and persists final result
- Files: `backtester/core/result_store.py`, `backtester/api/routes/results.py`, `backtester/api/ws.py`
- Tests: `backtester/tests/test_result_store.py` (8 tests)
- Endpoints: GET/DELETE/LIST /api/backtest

#### 4. **OptimizationHeatmap (B1)**
- 2D grid widget with cell tap detection and leaderboard sync
- File: `flutter_app/lib/widgets/optimization_heatmap.dart`
- Integrated in `optimization_screen.dart`

#### 5. **ValidationErrorDialog (B2)**
- Parses HTTP 422 Pydantic errors into structured modal
- File: `flutter_app/lib/widgets/validation_error_dialog.dart`
- Wired in optimization_screen.dart and backtest_screen.dart

#### 6. **Presets UI (B3)**
- Inline dropdown for save/load backtest configs
- Widget: `flutter_app/lib/screens/backtest_screen.dart:_PresetsToolbar`
- API: POST/GET/DELETE /api/presets

#### 7. **fakeAsync Migration (B5)**
- Replaced Future.delayed() with cancellable Timer in home_screen.dart
- Added fakeAsync tests in ws_service_test.dart
- Flutter tests now required in ci-gate

---

## Critical Files & Entry Points

### Backend Core
- `backtester/api/server.py` — FastAPI app factory
- `backtester/api/deps.py` — AppContext (IndicatorCache + ResultStore)
- `backtester/core/engine_stream.py` — StreamingEngine (cache-aware backtest loop)
- `backtester/core/result_store.py` — SQLite result persistence
- `backtester/core/cache.py` — LRU indicator cache

### Frontend Core
- `flutter_app/lib/screens/backtest_screen.dart` — Main UI
- `flutter_app/lib/screens/optimization_screen.dart` — Parameter sweep
- `flutter_app/lib/services/api_service.dart` — HTTP client
- `flutter_app/lib/widgets/optimization_heatmap.dart` — 2D sweep viz
- `flutter_app/lib/widgets/validation_error_dialog.dart` — Error modal

---

## Test Execution

```bash
# All backend tests
python -m pytest backtester/tests/ -v
# → 64 tests pass (Windows + Ubuntu, Python 3.11/3.12)

# Lint & type check
ruff check backtester/
mypy backtester/

# Flutter tests
cd flutter_app && flutter test
# → All widget tests pass; flutter analyze clean
```

---

## Phase 3 Priorities

- [ ] Advanced Charting: Lightweight Charts JavaScript integration
- [ ] Real-Time Streaming: Binance WebSocket live candles
- [ ] Multi-Bot Battles: Side-by-side comparison scoreboard
- [ ] PnL Analytics: Detailed trade log + win rate stats
- [ ] Alert System: Email/SMS on signal triggers

---

## Git Workflow

1. **Branch:** `feature/<description>` or `fix/<description>`
2. **Commits:** Squash when ready; include `Co-Authored-By: Claude <noreply@anthropic.com>`
3. **PR Format:** Title + summary + test plan
4. **Merge:** Squash to main after CI passes (all checks required)

---

## Quick Start (Next Agent)

```bash
# Backend
cd backtester
python -m venv ..\.venv
..\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn backtester.api.server:app --reload

# Frontend
cd flutter_app
flutter pub get
flutter run -d windows

# Tests
python -m pytest backtester/tests/ -v
cd ../flutter_app && flutter test
```

---

## Key Decisions

1. **AppContext Dataclass:** Both IndicatorCache and ResultStore are optional fields, lazy-initialized in __post_init__
2. **Result Tracking:** run_id UUID assigned at backtest start; final result persisted with all metadata
3. **Cache Strategy:** LRU by spec hash + candles fingerprint; backward compatible (cache=None defaults to no-op)
4. **Preset Storage:** Server-side SQLite; client loads on dropdown open (lazy loading)
5. **Flutter Timers:** All async operations now use cancellable Timer + fakeAsync in tests

---

**Status:** Phase 2 complete, all PRs merged, CI green.
**Next:** Phase 3 advanced features (charting, streaming, multi-bot battles).
**Generated:** 2026-05-15
