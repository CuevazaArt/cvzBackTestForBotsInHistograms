"""Smoke tests for the backtester core modules.

Run with:
    python -m pytest backtester/tests/ -v
"""

from decimal import Decimal
from pathlib import Path
import tempfile


# ── DuckDB downloader ──────────────────────────────────────────


def test_downloader_init_creates_duckdb():
    """BinanceDownloader should create a .duckdb file and candles table."""
    from backtester.core import BinanceDownloader

    with tempfile.TemporaryDirectory() as tmp:
        db_path = Path(tmp) / "test_candles.duckdb"
        dl = BinanceDownloader(db_path)
        assert dl.db_path.suffix == ".duckdb"
        assert dl.db_path.exists()


def test_downloader_legacy_db_suffix_redirects():
    """Passing a .db path should auto-redirect to .duckdb."""
    from backtester.core import BinanceDownloader

    with tempfile.TemporaryDirectory() as tmp:
        dl = BinanceDownloader(Path(tmp) / "candles.db")
        assert dl.db_path.suffix == ".duckdb"


def test_downloader_list_symbols_empty():
    """Empty database should return an empty list."""
    from backtester.core import BinanceDownloader

    with tempfile.TemporaryDirectory() as tmp:
        dl = BinanceDownloader(Path(tmp) / "test.duckdb")
        assert dl.list_symbols() == []


# ── Engine ──────────────────────────────────────────────────────


def test_engine_empty_candles():
    """Engine should handle an empty candle list gracefully."""
    from backtester.core import BacktestEngine, BacktestConfig
    from backtester.core.engine import BacktestBot

    class NoopBot(BacktestBot):
        def on_candle(self, candle, portfolio):
            return []

    engine = BacktestEngine(BacktestConfig(initial_cash=Decimal("1000")))
    result = engine.run(NoopBot(), [], symbol="TEST", timeframe="1h")
    assert result.candles_processed == 0
    assert result.trades == []
    assert result.final_equity == Decimal("0")


def test_engine_single_candle_no_orders():
    """Engine with one candle and no orders should preserve initial cash."""
    from backtester.core import BacktestEngine, BacktestConfig
    from backtester.core.engine import BacktestBot, Candle

    class NoopBot(BacktestBot):
        def on_candle(self, candle, portfolio):
            return []

    candles = [
        Candle(
            timestamp_ms=1700000000000,
            open=Decimal("100"),
            high=Decimal("105"),
            low=Decimal("95"),
            close=Decimal("102"),
            volume=Decimal("500"),
        )
    ]

    engine = BacktestEngine(BacktestConfig(initial_cash=Decimal("10000")))
    result = engine.run(NoopBot(), candles, symbol="TEST", timeframe="1h")
    assert result.final_equity == Decimal("10000")
    assert result.max_drawdown_pct == Decimal("0")
    assert len(result.equity_curve) == 1


def test_engine_max_drawdown_peak_to_trough():
    """Max drawdown should capture the worst peak-to-trough, not just final."""
    from backtester.core import BacktestEngine, BacktestConfig
    from backtester.core.engine import BacktestBot, Candle

    class BuyThenHold(BacktestBot):
        """Buys 1 unit on the first candle, then holds."""

        def __init__(self):
            self._bought = False

        def on_candle(self, candle, portfolio):
            if not self._bought:
                self._bought = True
                return [{"side": "BUY", "qty": 1}]
            return []

    # Price: 100 → 50 → 100  (50% drawdown mid-run, but recovers)
    candles = [
        Candle(
            1000,
            Decimal("100"),
            Decimal("100"),
            Decimal("100"),
            Decimal("100"),
            Decimal("10"),
        ),
        Candle(
            2000,
            Decimal("100"),
            Decimal("100"),
            Decimal("50"),
            Decimal("50"),
            Decimal("10"),
        ),
        Candle(
            3000,
            Decimal("50"),
            Decimal("100"),
            Decimal("50"),
            Decimal("100"),
            Decimal("10"),
        ),
    ]

    engine = BacktestEngine(
        BacktestConfig(
            initial_cash=Decimal("10000"),
            taker_fee_pct=Decimal("0"),
            slippage_pct=Decimal("0"),
        )
    )
    result = engine.run(BuyThenHold(), candles, "TEST", "1h")

    # The mid-run drawdown when price hit 50 should be captured
    assert result.max_drawdown_pct > Decimal("0")
    # Final equity recovered, so the OLD (broken) algorithm would report ~0%
    assert result.final_equity == Decimal("10000")


# ── Bot param_spec ──────────────────────────────────────────────


def test_ema_cross_param_spec():
    """EMACross.param_spec() should expose 4 editable parameters."""
    from backtester.bots import EMACross

    spec = EMACross.param_spec()
    assert "fast_ema" in spec
    assert "slow_ema" in spec
    assert "profit_factor" in spec
    assert "stop_loss_pct" in spec
    assert spec["fast_ema"]["type"] == "int"


def test_rsi_reversion_param_spec():
    """RSIReversion.param_spec() should expose editable parameters."""
    from backtester.bots import RSIReversion

    spec = RSIReversion.param_spec()
    assert "rsi_period" in spec


# ── Credentials ─────────────────────────────────────────────────


def test_credential_manager_roundtrip():
    """Save and load credentials should return the same values."""
    from backtester.core import CredentialManager

    with tempfile.TemporaryDirectory() as tmp:
        mgr = CredentialManager(Path(tmp) / "vault")
        assert not mgr.exists()

        mgr.save("test_key_123", "test_secret_456")
        assert mgr.exists()

        loaded = mgr.load()
        assert loaded == ("test_key_123", "test_secret_456")

        mgr.delete()
        assert not mgr.exists()


# ── Metrics ─────────────────────────────────────────────────────


def test_compute_metrics_returns_dict():
    """compute_metrics should return a dict with expected keys."""
    from backtester.core import BacktestEngine, compute_metrics
    from backtester.core.engine import BacktestBot, Candle

    class NoopBot(BacktestBot):
        def on_candle(self, candle, portfolio):
            return []

    candles = [
        Candle(
            1000,
            Decimal("100"),
            Decimal("100"),
            Decimal("100"),
            Decimal("100"),
            Decimal("10"),
        ),
    ]
    result = BacktestEngine().run(NoopBot(), candles)
    metrics = compute_metrics(result)

    assert "total_return_pct" in metrics
    assert "win_rate_pct" in metrics
    assert "max_drawdown_pct" in metrics
    assert "final_equity" in metrics


# ── P0 bug regressions (WORKPLAN C3 / C4 / C5) ──────────────────


def test_summary_profit_factor_uses_gross_profit_over_gross_loss():
    """Regression for WORKPLAN C3.

    ``BacktestResult.summary()`` must report ``gross_profit / gross_loss``
    (the standard definition), not ``avg_win / |avg_loss|``. We construct
    a result with three hand-picked trades whose averages and gross totals
    diverge so the two formulas yield clearly different numbers.
    """
    from backtester.core.engine import BacktestResult, Trade

    def _t(pnl: str) -> Trade:
        return Trade(
            entry_price=Decimal("100"),
            exit_price=Decimal("100"),
            qty=Decimal("1"),
            entry_idx=0,
            exit_idx=1,
            entry_time=0,
            exit_time=1,
            pnl=Decimal(pnl),
            pnl_pct=Decimal("0"),
            fee_usdt=Decimal("0"),
            reason="x",
        )

    # 2 winners totalling +30 (avg +15), 1 loser of -20.
    # Gross profit / gross loss = 30 / 20 = 1.5
    # Old (incorrect) avg_win / |avg_loss| = 15 / 20 = 0.75
    trades = [_t("10"), _t("20"), _t("-20")]
    result = BacktestResult(
        symbol="X",
        timeframe="1h",
        candles_processed=1,
        trades=trades,
        equity_curve=[Decimal("10000")],
        final_equity=Decimal("10010"),
    )
    summary = result.summary()
    assert summary["profit_factor"] == 1.5


def test_total_equity_with_no_positions_is_decimal_not_int():
    """Regression for WORKPLAN C4.

    Empty ``sum(...)`` on a Decimal iterable previously returned ``int(0)``
    which silently breaks downstream Decimal arithmetic. With
    ``start=Decimal("0")`` the result type stays Decimal.
    """
    from backtester.core.engine import Portfolio

    p = Portfolio(cash=Decimal("123.45"))
    eq = p.total_equity(Decimal("999"))
    # Stays Decimal, value equals cash since no positions.
    assert isinstance(eq, Decimal)
    assert eq == Decimal("123.45")
    # And open_position_cost() too.
    cost = p.open_position_cost()
    assert isinstance(cost, Decimal)
    assert cost == Decimal("0")


def test_max_drawdown_uses_first_point_as_initial_peak():
    """Regression for WORKPLAN C5.

    ``compute_max_drawdown_pct`` must seed the running peak with the first
    equity-curve point. With the old ``Decimal("0")`` seed, a curve that
    starts positive and dips slightly was computed correctly only by
    accident; the semantics were ambiguous for curves that start, never
    grow, and only decay (e.g. a strategy that loses from bar 1).
    """
    from backtester.core.engine import compute_max_drawdown_pct

    # Curve: 1000 -> 900 -> 800. Only goes down. With the fix, the running
    # peak starts at 1000 and max DD = (1000 - 800) / 1000 = 20 %.
    curve = [Decimal("1000"), Decimal("900"), Decimal("800")]
    dd = compute_max_drawdown_pct(curve)
    assert dd == Decimal("20")
