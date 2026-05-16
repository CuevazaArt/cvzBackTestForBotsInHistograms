"""End-to-end integration tests for the backtester API.

Covers:
  - Pydantic validators reject bad payloads (EMA pair, cash, time range, empty bots).
  - POST /api/backtest/run produces metrics on synthetic candles.
  - ExperimentRunner runs multiple configs and returns finite metrics.
  - Engine isolates bot exceptions (one bot crash does not kill the run).

Run:
    cd C:/Users/Dell/Desktop/cvzBackTestForBotsInHistograms
    python -m pytest backtester/tests/test_integration.py -v
"""

from __future__ import annotations

import math
import os
import tempfile
from decimal import Decimal
from pathlib import Path

import pytest
from fastapi.testclient import TestClient


# ── Helpers ──────────────────────────────────────────────────────


def _synthetic_klines(n: int = 300) -> list[list]:
    """Generate synthetic 1h klines (Binance format) with a sine-wave trend.

    Produces clear crossovers so trend-following bots will trigger trades.
    Returns the raw binance kline list shape expected by `_save_batch`.
    """
    klines = []
    base = 100.0
    for i in range(n):
        # Slow sine wave with a slight upward drift.
        offset = 30 * math.sin(i / 18.0) + i * 0.05
        close = base + offset
        # Small intra-candle range:
        o = base + 30 * math.sin((i - 1) / 18.0) + (i - 1) * 0.05 if i > 0 else close
        h = max(o, close) + 0.3
        low_p = min(o, close) - 0.3
        ts_ms = i * 3_600_000  # 1h candles, starting at epoch
        # Binance kline shape: [open_time, open, high, low, close, vol, close_time, quote_vol, ...]
        klines.append([ts_ms, o, h, low_p, close, 100.0, ts_ms + 3_599_999, 10000.0])
    return klines


@pytest.fixture
def app_with_synthetic_data():
    """FastAPI app whose AppContext points at a temp DuckDB pre-loaded with synthetic candles."""
    from backtester.api.deps import AppContext
    from backtester.api.server import create_app
    from backtester.core import BinanceDownloader

    tmpdir = tempfile.mkdtemp(prefix="backtester_test_")
    root = Path(tmpdir)
    data_dir = root / "data"
    vault_dir = root / ".vault"
    data_dir.mkdir(parents=True, exist_ok=True)
    vault_dir.mkdir(parents=True, exist_ok=True)

    downloader = BinanceDownloader(data_dir / "candles.duckdb")
    klines = _synthetic_klines(300)
    downloader._save_batch("TESTUSDT", "1h", klines)

    app = create_app()
    # Replace the lifespan-built context with our test context.
    from backtester.api.deps import BOT_REGISTRY
    from backtester.api.jobs import JobRegistry
    from backtester.core import CredentialManager
    from backtester.core.preset_store import PresetStore
    from backtester.core.result_store import ResultStore

    from backtester.core.cache import IndicatorCache

    app.state.ctx = AppContext(
        base_dir=root,
        downloader=downloader,
        credentials=CredentialManager(vault_dir),
        bot_registry=dict(BOT_REGISTRY),
        jobs=JobRegistry(data_dir / "jobs.sqlite"),
        presets=PresetStore(data_dir / "presets.sqlite"),
        indicator_cache=IndicatorCache(max_entries=512),
        result_store=ResultStore(data_dir / "results.sqlite"),
    )
    return app


# ── Schema validation tests ──────────────────────────────────────


def test_validator_rejects_inverted_ema_pair():
    from backtester.api.schemas import BotRunSpec

    with pytest.raises(Exception) as e:
        BotRunSpec(name="EMACross", params={"fast_ema": 30, "slow_ema": 10})
    assert "fast_ema" in str(e.value) and "slow_ema" in str(e.value)


def test_validator_accepts_valid_ema_pair():
    from backtester.api.schemas import BotRunSpec

    # Should not raise
    spec = BotRunSpec(name="EMACross", params={"fast_ema": 12, "slow_ema": 26})
    assert spec.params["fast_ema"] == 12


def test_validator_bypasses_non_ema_bots():
    from backtester.api.schemas import BotRunSpec

    # DorothyDCA doesn't use fast/slow EMA so should not validate them.
    spec = BotRunSpec(name="DorothyDCA", params={"fast_ema": 30, "slow_ema": 10})
    assert spec.params["fast_ema"] == 30


def test_validator_rejects_zero_cash():
    from backtester.api.schemas import BacktestRequest, BotRunSpec

    with pytest.raises(Exception):
        BacktestRequest(
            symbol="X",
            timeframe="1h",
            bots=[BotRunSpec(name="EMACross", params={})],
            initial_cash=0.0,
        )


def test_validator_rejects_negative_fees():
    from backtester.api.schemas import BacktestRequest, BotRunSpec

    with pytest.raises(Exception):
        BacktestRequest(
            symbol="X",
            timeframe="1h",
            bots=[BotRunSpec(name="EMACross", params={})],
            taker_fee_pct=-1.0,
        )


def test_validator_rejects_inverted_time_range():
    from backtester.api.schemas import BacktestRequest, BotRunSpec

    with pytest.raises(Exception):
        BacktestRequest(
            symbol="X",
            timeframe="1h",
            bots=[BotRunSpec(name="EMACross", params={})],
            start_ms=2000,
            end_ms=1000,
        )


def test_validator_rejects_empty_bots():
    from backtester.api.schemas import BacktestRequest

    with pytest.raises(Exception):
        BacktestRequest(symbol="X", timeframe="1h", bots=[])


def test_experiment_validator_rejects_bad_configs():
    from backtester.api.schemas import ExperimentSpec

    with pytest.raises(Exception):
        ExperimentSpec(
            name="EMACross",
            configs=[{"fast_ema": 30, "slow_ema": 10}],
        )


def test_experiment_validator_caps_total_combos():
    from backtester.api.schemas import ExperimentsRequest, ExperimentSpec

    # Build a request that exceeds the 1000-combo cap.
    configs = [{"fast_ema": i, "slow_ema": i + 10} for i in range(1001)]
    with pytest.raises(Exception) as e:
        ExperimentsRequest(
            symbol="X",
            timeframe="1h",
            bots=[ExperimentSpec(name="EMACross", configs=configs)],
        )
    assert "1000" in str(e.value) or "too many" in str(e.value)


# ── End-to-end HTTP backtest ─────────────────────────────────────


def test_post_backtest_run_returns_metrics(app_with_synthetic_data):
    client = TestClient(app_with_synthetic_data)
    payload = {
        "symbol": "TESTUSDT",
        "timeframe": "1h",
        "bots": [{"name": "EMACross", "params": {"fast_ema": 5, "slow_ema": 15}}],
        "initial_cash": 10000.0,
    }
    res = client.post("/api/backtest/run", json=payload)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["symbol"] == "TESTUSDT"
    assert body["timeframe"] == "1h"
    # 300 candles with EMA crossovers should produce at least one closed trade.
    assert body["summary"]["trades"] >= 1
    # Total return must be finite.
    ret = body["summary"]["total_return_pct"]
    assert isinstance(ret, (int, float))
    assert not math.isnan(ret) and not math.isinf(ret)


def test_post_backtest_run_rejects_bad_ema_with_422(app_with_synthetic_data):
    client = TestClient(app_with_synthetic_data)
    payload = {
        "symbol": "TESTUSDT",
        "timeframe": "1h",
        "bots": [{"name": "EMACross", "params": {"fast_ema": 30, "slow_ema": 10}}],
    }
    res = client.post("/api/backtest/run", json=payload)
    assert res.status_code == 422, res.text
    body = res.json()
    detail = str(body)
    assert "fast_ema" in detail and "slow_ema" in detail


def test_post_backtest_run_rejects_missing_candles(app_with_synthetic_data):
    client = TestClient(app_with_synthetic_data)
    payload = {
        "symbol": "NOEXIST",
        "timeframe": "1h",
        "bots": [{"name": "EMACross", "params": {"fast_ema": 5, "slow_ema": 15}}],
    }
    res = client.post("/api/backtest/run", json=payload)
    assert res.status_code == 400
    assert "no candles" in res.text.lower() or "download" in res.text.lower()


# ── ExperimentRunner parallel sweep ──────────────────────────────


def test_experiment_runner_processes_multiple_configs():
    """ExperimentRunner should process several configs and return finite metrics for each."""
    from backtester.bots.ema_cross import EMACross
    from backtester.core import BacktestConfig, BinanceDownloader
    from backtester.experiments import Experiment, ExperimentRunner

    with tempfile.TemporaryDirectory() as tmp:
        downloader = BinanceDownloader(Path(tmp) / "candles.duckdb")
        downloader._save_batch("TESTUSDT", "1h", _synthetic_klines(300))

        bot_registry = {"EMACross": EMACross}
        runner = ExperimentRunner(
            downloader=downloader,
            bot_registry=bot_registry,
            engine_config=BacktestConfig(initial_cash=Decimal("10000")),
        )

        experiments = [
            Experiment(
                symbol="TESTUSDT",
                timeframe="1h",
                bot_class="EMACross",
                bot_params={"fast_ema": 5, "slow_ema": 15},
            ),
            Experiment(
                symbol="TESTUSDT",
                timeframe="1h",
                bot_class="EMACross",
                bot_params={"fast_ema": 8, "slow_ema": 21},
            ),
            Experiment(
                symbol="TESTUSDT",
                timeframe="1h",
                bot_class="EMACross",
                bot_params={"fast_ema": 12, "slow_ema": 26},
            ),
        ]
        # Workers=1 → keeps the test single-process; multiprocessing on Windows
        # with pytest fixtures can be flaky due to pickling.
        results = runner.run_batch(experiments, workers=1)

        assert len(results) == 3
        for r in results:
            assert r.success, f"Experiment failed: {r.error}"
            assert r.metrics is not None
            ret = r.metrics.get("total_return_pct")
            assert ret is not None
            assert not math.isnan(ret)


# ── Engine isolates bot exceptions ───────────────────────────────


def test_engine_isolates_bot_crash():
    """A bot that raises in on_candle should not abort the whole backtest."""
    from backtester.bots.ema_cross import EMACross
    from backtester.core import BacktestConfig, BacktestEngine
    from backtester.core.engine import Candle

    class CrashBot:
        """Always raises — should be quarantined by the engine."""

        def on_candle(self, candle, portfolio):  # noqa: ARG002
            raise RuntimeError("boom")

    candles = [
        Candle.from_dict(
            {
                "timestamp_ms": i * 3_600_000,
                "open": 100.0 + i,
                "high": 100.5 + i,
                "low": 99.5 + i,
                "close": 100.0 + i,
                "volume": 100.0,
            }
        )
        for i in range(50)
    ]

    eng = BacktestEngine(BacktestConfig(initial_cash=Decimal("10000")))
    result = eng.run(
        [CrashBot(), EMACross(fast_ema=5, slow_ema=15)],
        candles,
        symbol="X",
        timeframe="1h",
        bot_names=["Crasher", "Healthy"],
    )

    # Healthy bot's portfolio survives and is reported.
    assert "Healthy" in result.per_bot
    # Crashed bot gets a zero-trade entry, not a propagation of the error.
    assert "Crasher" in result.per_bot
    assert result.per_bot["Crasher"]["trades"] == 0
    assert isinstance(result.per_bot["Crasher"]["total_return_pct"], float)


# ── DorothyDCA validation ────────────────────────────────────────


def _downtrend_recovery_klines(n: int = 200) -> list[list]:
    """Synthetic klines with a dip then recovery — ideal for DCA."""
    klines = []
    base = 100.0
    for i in range(n):
        # Drop 40% in first half, recover fully in second half
        if i < n // 2:
            offset = -40.0 * (i / (n // 2))
        else:
            offset = -40.0 + 40.0 * ((i - n // 2) / (n // 2))
        close = base + offset + (i * 0.01)  # tiny drift
        o = close - 0.2
        h = max(o, close) + 0.3
        low_p = min(o, close) - 0.3
        ts_ms = i * 3_600_000
        klines.append([ts_ms, o, h, low_p, close, 150.0, ts_ms + 3_599_999, 15000.0])
    return klines


def test_dorothy_dca_runs_end_to_end():
    """DorothyDCA should buy on dips and take profit on recovery."""
    from backtester.bots.dorothy_dca import DorothyDCA
    from backtester.core import BacktestConfig, BacktestEngine
    from backtester.core.engine import Candle

    candles = [
        Candle.from_dict(
            {
                "timestamp_ms": k[0],
                "open": k[1],
                "high": k[2],
                "low": k[3],
                "close": k[4],
                "volume": k[5],
            }
        )
        for k in _downtrend_recovery_klines(200)
    ]

    bot = DorothyDCA(
        profit_factor=0.05,
        margin_drop_factor=0.004,
        max_positions=3,
        stop_loss_pct=0.15,
        risk_per_trade_pct=5.0,
    )
    eng = BacktestEngine(BacktestConfig(initial_cash=Decimal("10000")))
    result = eng.run(
        [bot], candles, symbol="TESTUSDT", timeframe="1h", bot_names=["DorothyDCA"]
    )

    assert "DorothyDCA" in result.per_bot
    metrics = result.per_bot["DorothyDCA"]
    # Must have at least one trade (initial buy) and the metrics should be finite
    assert metrics["trades"] >= 1
    ret = metrics["total_return_pct"]
    assert not math.isnan(ret) and not math.isinf(ret)


def test_dorothy_dca_via_http(app_with_synthetic_data):
    """DorothyDCA should work through the REST API."""
    # First insert some data with the downtrend pattern

    ctx = app_with_synthetic_data.state.ctx
    ctx.downloader._save_batch("TESTUSDT", "1h", _downtrend_recovery_klines(200))

    client = TestClient(app_with_synthetic_data)
    payload = {
        "symbol": "TESTUSDT",
        "timeframe": "1h",
        "bots": [
            {
                "name": "DorothyDCA",
                "params": {
                    "profit_factor": 0.05,
                    "margin_drop_factor": 0.004,
                    "max_positions": 3,
                },
            }
        ],
        "initial_cash": 10000.0,
    }
    res = client.post("/api/backtest/run", json=payload)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["summary"]["trades"] >= 1
    ret = body["summary"]["total_return_pct"]
    assert not math.isnan(ret)


def test_advanced_metrics_present_in_response(app_with_synthetic_data):
    """HTTP response summary should include Sharpe, Sortino, Calmar, etc."""
    # Insert synthetic data first
    ctx = app_with_synthetic_data.state.ctx
    ctx.downloader._save_batch("TESTUSDT", "1h", _downtrend_recovery_klines(200))

    client = TestClient(app_with_synthetic_data)
    payload = {
        "symbol": "TESTUSDT",
        "timeframe": "1h",
        "bots": [{"name": "EMACross", "params": {"fast_ema": 5, "slow_ema": 20}}],
        "initial_cash": 10000.0,
    }
    res = client.post("/api/backtest/run", json=payload)
    assert res.status_code == 200, f"Expected 200, got {res.status_code}: {res.text}"
    summary = res.json()["summary"]

    # All new keys must exist and be finite
    for key in (
        "sharpe_ratio",
        "sortino_ratio",
        "calmar_ratio",
        "avg_win_pnl",
        "avg_loss_pnl",
        "expectancy",
        "avg_trade_duration_hrs",
    ):
        assert key in summary, f"Missing metric: {key}"
        val = summary[key]
        assert isinstance(
            val, (int, float)
        ), f"{key} should be numeric, got {type(val)}"
        assert not math.isnan(val) and not math.isinf(
            val
        ), f"{key} is not finite: {val}"


def test_job_cancel_unknown_returns_404(app_with_synthetic_data):
    client = TestClient(app_with_synthetic_data)
    res = client.post("/api/jobs/does-not-exist/cancel")
    assert res.status_code == 404


def test_health_requires_token_when_configured(app_with_synthetic_data):
    os.environ["BACKTESTER_API_TOKEN"] = "abc123"
    app_with_synthetic_data.state.settings = type(
        "S", (), {"auth_enabled": True, "api_token": "abc123"}
    )()
    client = TestClient(app_with_synthetic_data)
    unauthorized = client.get("/health")
    assert unauthorized.status_code == 401
    authorized = client.get("/health", headers={"x-api-key": "abc123"})
    assert authorized.status_code == 200
    os.environ.pop("BACKTESTER_API_TOKEN", None)


# ── Sprint 6: trade export ───────────────────────────────────────


def test_export_trades_csv(app_with_synthetic_data):
    client = TestClient(app_with_synthetic_data)
    payload = {
        "symbol": "TESTUSDT",
        "timeframe": "1h",
        "bots": [{"name": "EMACross", "params": {"fast_ema": 5, "slow_ema": 15}}],
        "initial_cash": 10000.0,
    }
    res = client.post("/api/backtest/export/trades?format=csv", json=payload)
    assert res.status_code == 200, res.text
    assert res.headers["content-type"].startswith("text/csv")
    assert "attachment" in res.headers["content-disposition"]
    lines = res.text.strip().splitlines()
    header = lines[0].split(",")
    for col in (
        "bot_id",
        "entry_time",
        "exit_time",
        "entry_price",
        "exit_price",
        "qty",
        "pnl",
        "pnl_pct",
        "fee_usdt",
        "reason",
    ):
        assert col in header, f"Missing CSV column {col}"
    # At least the header + one trade row.
    assert len(lines) >= 2


def test_export_trades_json(app_with_synthetic_data):
    client = TestClient(app_with_synthetic_data)
    payload = {
        "symbol": "TESTUSDT",
        "timeframe": "1h",
        "bots": [{"name": "EMACross", "params": {"fast_ema": 5, "slow_ema": 15}}],
        "initial_cash": 10000.0,
    }
    res = client.post("/api/backtest/export/trades?format=json", json=payload)
    assert res.status_code == 200
    body = res.json()
    assert body["symbol"] == "TESTUSDT"
    assert isinstance(body["trades"], list)
    assert body["summary"]["trades"] >= 1


def test_export_trades_rejects_invalid_format(app_with_synthetic_data):
    client = TestClient(app_with_synthetic_data)
    payload = {
        "symbol": "TESTUSDT",
        "timeframe": "1h",
        "bots": [{"name": "EMACross", "params": {"fast_ema": 5, "slow_ema": 15}}],
    }
    res = client.post("/api/backtest/export/trades?format=xml", json=payload)
    assert res.status_code == 422


# ── Run comparator ────────────────────────────────────────────────


def _seed_compare_run(app, run_id: str, *, label: str, final_eq: float) -> None:
    """Insert a synthetic backtest result into the store for compare tests."""
    ctx = app.state.ctx
    equity_curve = [
        {"time": 1_000 + i, "value": 10_000 + (final_eq - 10_000) * (i / 9)}
        for i in range(10)
    ]
    ctx.result_store.save(
        run_id,
        "TESTUSDT",
        "1h",
        {"bots": [{"name": label, "params": {}}]},
        {
            "symbol": "TESTUSDT",
            "timeframe": "1h",
            "summary": {
                "total_return_pct": (final_eq - 10000) / 100,
                "win_rate_pct": 55.0,
                "profit_factor": 1.4,
                "max_drawdown_pct": 8.2,
                "final_equity": final_eq,
                "trades": 7,
            },
            "final_equity": final_eq,
            "peak_equity": final_eq * 1.05,
            "max_drawdown_pct": 8.2,
            "equity_curve_downsampled": equity_curve,
        },
    )


def test_compare_runs_returns_structure_for_known_ids(app_with_synthetic_data):
    """POST /api/backtest/compare aggregates stored runs."""
    app = app_with_synthetic_data
    _seed_compare_run(app, "run-a", label="EMACross", final_eq=11000)
    _seed_compare_run(app, "run-b", label="RSIReversion", final_eq=10300)
    _seed_compare_run(app, "run-c", label="MACDCross", final_eq=9500)

    client = TestClient(app)
    res = client.post(
        "/api/backtest/compare",
        json={"run_ids": ["run-a", "run-b", "run-c"]},
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["missing"] == []
    assert len(body["runs"]) == 3
    labels = {r["label"] for r in body["runs"]}
    assert labels == {"EMACross", "RSIReversion", "MACDCross"}
    for run in body["runs"]:
        assert run["symbol"] == "TESTUSDT"
        assert run["timeframe"] == "1h"
        assert "summary" in run
        assert "final_equity" in run["summary"]
        assert isinstance(run["equity_curve_downsampled"], list)
        assert len(run["equity_curve_downsampled"]) > 0
        for pt in run["equity_curve_downsampled"]:
            assert "time" in pt and "value" in pt


def test_compare_runs_reports_missing_ids(app_with_synthetic_data):
    """Unknown run_ids end up in `missing` but the rest is returned."""
    app = app_with_synthetic_data
    _seed_compare_run(app, "run-exists", label="EMACross", final_eq=10500)

    client = TestClient(app)
    res = client.post(
        "/api/backtest/compare",
        json={"run_ids": ["run-exists", "run-ghost"]},
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert [r["run_id"] for r in body["runs"]] == ["run-exists"]
    assert body["missing"] == ["run-ghost"]


def test_compare_runs_rejects_too_many(app_with_synthetic_data):
    client = TestClient(app_with_synthetic_data)
    res = client.post(
        "/api/backtest/compare",
        json={"run_ids": [f"r{i}" for i in range(11)]},
    )
    assert res.status_code == 422


# ── HTML report ────────────────────────────────────────────────────


def test_html_report_endpoint_returns_self_contained_html(app_with_synthetic_data):
    """GET /api/backtest/{run_id}/report.html returns a renderable HTML page."""
    app = app_with_synthetic_data
    _seed_compare_run(app, "run-html", label="EMACross", final_eq=10500)
    client = TestClient(app)

    res = client.get("/api/backtest/run-html/report.html")
    assert res.status_code == 200, res.text
    assert res.headers["content-type"].startswith("text/html")
    body = res.text
    # Run ID + symbol appear so the user can identify the report.
    assert "run-html" in body
    assert "TESTUSDT" in body
    # Chart wiring and trades pagination scripts are present.
    assert "equity-chart" in body
    assert "trades-body" in body


def test_html_report_endpoint_returns_404_for_unknown_run(app_with_synthetic_data):
    client = TestClient(app_with_synthetic_data)
    res = client.get("/api/backtest/does-not-exist/report.html")
    assert res.status_code == 404


def test_stress_endpoint_returns_matrix(app_with_synthetic_data):
    app = app_with_synthetic_data
    app.state.ctx.result_store.save(
        "run-stress",
        "TESTUSDT",
        "1h",
        {"bots": [{"name": "EMACross", "params": {}}]},
        {
            "symbol": "TESTUSDT",
            "timeframe": "1h",
            "summary": {"total_return_pct": 5.0, "final_equity": 10500.0},
            "trades": [
                {"pnl": 120.0, "fee_usdt": 1.0},
                {"pnl": -50.0, "fee_usdt": 1.0},
                {"pnl": 60.0, "fee_usdt": 1.0},
            ],
        },
    )
    client = TestClient(app)
    res = client.post(
        "/api/backtest/run-stress/stress",
        json={"fees_mult": [1, 2], "slippage_mult": [1], "drop_best_pct": [0, 10]},
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["run_id"] == "run-stress"
    assert len(body["scenarios"]) == 4
    assert len(body["sharpe"]) == 4


def test_stress_endpoint_404_for_unknown_run(app_with_synthetic_data):
    client = TestClient(app_with_synthetic_data)
    res = client.post("/api/backtest/unknown-run/stress", json={})
    assert res.status_code == 404


def test_data_validate_endpoint_returns_quality_report(app_with_synthetic_data):
    client = TestClient(app_with_synthetic_data)
    res = client.post(
        "/api/data/validate", json={"symbol": "TESTUSDT", "timeframe": "1h"}
    )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["total_candles"] == 300
    assert body["expected_candles"] == 300
    assert body["completeness_pct"] == 100.0
    assert body["gaps"] == []
    assert body["duplicates"] == []
    assert body["monotonic_ok"] is True
    assert body["ohlc_consistency_violations"] == []
    assert body["summary_ok"] is True
    assert body["timeframe_seconds"] == 3600


def test_data_validate_endpoint_returns_404_for_unknown_symbol(app_with_synthetic_data):
    client = TestClient(app_with_synthetic_data)
    res = client.post(
        "/api/data/validate", json={"symbol": "NOEXIST", "timeframe": "1h"}
    )
    assert res.status_code == 404
