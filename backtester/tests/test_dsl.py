"""Tests for the strategy DSL.

Covers parsing (valid / invalid), expression evaluation (AND / OR / NOT),
and an end-to-end backtest that proves a DSL strategy generates real
trades when its conditions are met. The HTTP validate endpoint is
exercised too so the Flutter editor's contract is locked.
"""

from __future__ import annotations

import math
from decimal import Decimal

import pytest

from backtester.bots.dsl import DSLBot, DSLParseError, parse_dsl
from backtester.bots.dsl.evaluator import evaluate
from backtester.core.engine import BacktestConfig, BacktestEngine, Candle


# ── Parsing ──────────────────────────────────────────────────────


_VALID_DSL = """
name: ema cross
indicators:
  - ema(close, 12) as fast
  - ema(close, 26) as slow
entry:
  long: fast > slow
exit:
  long: fast < slow
risk:
  stop_loss_pct: 0.05
  take_profit_pct: 0.10
  size_pct: 2.0
"""


def test_parse_valid_dsl_extracts_indicators_and_rules():
    spec = parse_dsl(_VALID_DSL)
    assert spec.name == "ema cross"
    assert spec.indicators_used() == ["fast", "slow"]
    assert spec.stop_loss_pct == 0.05
    assert spec.take_profit_pct == 0.10
    assert spec.size_pct == 2.0
    assert spec.entry_long is not None
    assert spec.exit_long is not None


def test_parse_dsl_with_dict_input_works():
    """`parse_dsl` should accept an already-decoded dict, not only YAML text."""
    spec = parse_dsl(
        {
            "name": "dict input",
            "indicators": ["ema(close, 5) as fast", "ema(close, 20) as slow"],
            "entry": {"long": "fast > slow"},
            "exit": {"long": "fast < slow"},
            "risk": {"size_pct": 1.0},
        }
    )
    assert spec.indicators_used() == ["fast", "slow"]
    assert spec.size_pct == 1.0


def test_parse_rejects_unknown_indicator():
    with pytest.raises(DSLParseError, match="unsupported indicator"):
        parse_dsl(
            """
            indicators:
              - frobnitz(close, 14) as foo
            entry:
              long: foo > 50
            exit:
              long: foo < 50
            """
        )


def test_parse_rejects_unknown_alias_in_rule():
    with pytest.raises(DSLParseError, match="unknown alias"):
        parse_dsl(
            """
            indicators:
              - ema(close, 12) as fast
            entry:
              long: fast > slow
            exit:
              long: fast < slow
            """
        )


def test_parse_rejects_duplicate_aliases():
    with pytest.raises(DSLParseError, match="duplicate"):
        parse_dsl(
            """
            indicators:
              - ema(close, 12) as fast
              - ema(close, 26) as fast
            entry:
              long: fast > 0
            exit:
              long: fast < 0
            """
        )


def test_parse_rejects_missing_entry_long():
    with pytest.raises(DSLParseError, match="entry.long"):
        parse_dsl(
            """
            indicators:
              - ema(close, 12) as fast
            entry: {}
            exit:
              long: fast < 0
            """
        )


def test_parse_rejects_disallowed_python_construct():
    """The expression compiler must reject anything beyond the whitelist."""
    # Function calls like ``len(fast)`` should not be allowed.
    with pytest.raises(DSLParseError, match="disallowed"):
        parse_dsl(
            """
            indicators:
              - ema(close, 12) as fast
            entry:
              long: len(fast) > 0
            exit:
              long: fast < 0
            """
        )


# ── Evaluator (AND / OR / NOT, missing values) ──────────────────


def _expr(text: str):
    """Convenience: parse a tiny DSL with one indicator and return its
    entry AST so we can poke the evaluator directly."""
    src = f"""
    indicators:
      - ema(close, 12) as fast
      - ema(close, 26) as slow
      - rsi(close, 14) as r
    entry:
      long: {text}
    exit:
      long: fast < slow
    """
    return parse_dsl(src).entry_long


def test_evaluator_and():
    tree = _expr("fast > slow AND r < 70")
    assert evaluate(tree, {"fast": 5, "slow": 4, "r": 50}) is True
    assert evaluate(tree, {"fast": 5, "slow": 4, "r": 80}) is False
    assert evaluate(tree, {"fast": 3, "slow": 4, "r": 50}) is False


def test_evaluator_or():
    tree = _expr("fast > slow OR r < 30")
    assert evaluate(tree, {"fast": 5, "slow": 4, "r": 50}) is True  # left
    assert evaluate(tree, {"fast": 3, "slow": 4, "r": 20}) is True  # right
    assert evaluate(tree, {"fast": 3, "slow": 4, "r": 50}) is False


def test_evaluator_not():
    tree = _expr("NOT (fast > slow)")
    assert evaluate(tree, {"fast": 3, "slow": 4, "r": 50}) is True
    assert evaluate(tree, {"fast": 5, "slow": 4, "r": 50}) is False


def test_evaluator_short_circuits_when_indicator_is_none():
    """A None value (warm-up) collapses the whole expression to False
    so the bot doesn't act on missing data."""
    tree = _expr("fast > slow")
    assert evaluate(tree, {"fast": None, "slow": 4, "r": 50}) is False
    assert evaluate(tree, {"fast": 5, "slow": None, "r": 50}) is False


# ── End-to-end backtest via DSLBot ───────────────────────────────


def _sine_candles(n: int = 200) -> list[Candle]:
    """Synthetic 1h candles that swing predictably so EMA crossovers fire."""
    out = []
    base = 100.0
    for i in range(n):
        offset = 25 * math.sin(i / 14.0)
        close = base + offset
        open_ = base + 25 * math.sin((i - 1) / 14.0) if i > 0 else close
        high = max(open_, close) + 0.5
        low = min(open_, close) - 0.5
        out.append(
            Candle(
                timestamp_ms=i * 3_600_000,
                open=Decimal(str(open_)),
                high=Decimal(str(high)),
                low=Decimal(str(low)),
                close=Decimal(str(close)),
                volume=Decimal("100"),
            )
        )
    return out


def test_dsl_bot_runs_end_to_end_and_produces_trades():
    """A DSLBot with a classic EMA-cross definition must produce real
    trades on a synthetic dataset with clear crossovers."""
    bot = DSLBot(dsl_text=_VALID_DSL)
    engine = BacktestEngine(
        BacktestConfig(
            initial_cash=Decimal("10000"),
            taker_fee_pct=Decimal("0"),
            slippage_pct=Decimal("0"),
        )
    )
    result = engine.run(
        bot,
        _sine_candles(200),
        symbol="TESTUSDT",
        timeframe="1h",
        bot_names=["DSL"],
    )

    assert result.candles_processed == 200
    assert len(result.trades) >= 1, "DSL bot should fire at least one trade"
    # Every trade either entered via DSL_ENTRY and exited via DSL_EXIT or
    # via the engine's bracket triggers (STOP_LOSS / TAKE_PROFIT names from
    # TriggerReason).
    for t in result.trades:
        assert t.bot_id == "DSL"
        assert t.reason in {
            "DSL_EXIT",
            "STOP_LOSS",
            "TAKE_PROFIT",
            "TRAILING_STOP",
            "LIMIT_FILL",
        }
    # Summary metrics must be finite.
    summary = result.summary()
    for key in ("total_return_pct", "profit_factor", "max_drawdown_pct"):
        val = summary[key]
        assert not math.isnan(val) and not math.isinf(val)


def test_two_dsl_bots_same_config_produce_identical_results():
    """Determinism check: a second DSLBot with the same YAML must produce
    the same trades, equity curve, and summary as the first."""
    candles = _sine_candles(200)
    cfg = BacktestConfig(
        initial_cash=Decimal("10000"),
        taker_fee_pct=Decimal("0"),
        slippage_pct=Decimal("0"),
    )

    r1 = BacktestEngine(cfg).run(
        DSLBot(dsl_text=_VALID_DSL),
        candles,
        symbol="X",
        timeframe="1h",
        bot_names=["DSL"],
    )
    r2 = BacktestEngine(cfg).run(
        DSLBot(dsl_text=_VALID_DSL),
        candles,
        symbol="X",
        timeframe="1h",
        bot_names=["DSL"],
    )

    assert len(r1.trades) == len(r2.trades)
    assert r1.final_equity == r2.final_equity
    assert r1.max_drawdown_pct == r2.max_drawdown_pct
    for t1, t2 in zip(r1.trades, r2.trades):
        assert t1.entry_price == t2.entry_price
        assert t1.exit_price == t2.exit_price
        assert t1.reason == t2.reason


# ── HTTP /api/bots/dsl/validate ──────────────────────────────────


def test_validate_endpoint_accepts_valid_dsl():
    from fastapi.testclient import TestClient

    from backtester.api.server import create_app

    with TestClient(create_app()) as client:
        res = client.post(
            "/api/bots/dsl/validate",
            json={"dsl_text": _VALID_DSL},
        )
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["ok"] is True
    assert body["indicators_used"] == ["fast", "slow"]
    assert body["has_entry_long"] is True
    assert body["has_exit_long"] is True
    assert body["stop_loss_pct"] == 0.05


def test_validate_endpoint_returns_structured_error():
    from fastapi.testclient import TestClient

    from backtester.api.server import create_app

    bad_dsl = """
    indicators:
      - frobnitz(close, 1) as foo
    entry:
      long: foo > 0
    exit:
      long: foo < 0
    """
    with TestClient(create_app()) as client:
        res = client.post("/api/bots/dsl/validate", json={"dsl_text": bad_dsl})
    assert res.status_code == 200
    body = res.json()
    assert body["ok"] is False
    assert body["error"] is not None
    assert "unsupported indicator" in body["error"]["message"]
