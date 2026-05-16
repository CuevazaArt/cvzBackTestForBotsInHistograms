from __future__ import annotations

from backtester.analysis.stress import run_stress_battery


def _result_blob() -> dict:
    return {
        "summary": {"final_equity": 10500.0, "total_return_pct": 5.0},
        "trades": [
            {"pnl": 120.0, "fee_usdt": 1.0},
            {"pnl": -40.0, "fee_usdt": 1.0},
            {"pnl": 60.0, "fee_usdt": 1.0},
            {"pnl": -20.0, "fee_usdt": 1.0},
        ],
    }


def test_stress_battery_returns_all_requested_scenarios():
    matrix = run_stress_battery(
        _result_blob(),
        fees_mult=[1.0, 2.0],
        slippage_mult=[1.0],
        drop_best_pct=[0.0, 10.0],
    )
    assert len(matrix.scenarios) == 4
    assert len(matrix.sharpe) == 4
    assert len(matrix.returns_pct) == 4


def test_drop_best_reduces_or_keeps_return():
    matrix = run_stress_battery(
        _result_blob(), fees_mult=[1.0], slippage_mult=[1.0], drop_best_pct=[0.0, 50.0]
    )
    base = matrix.returns_pct["f1_s1_d0"]
    dropped = matrix.returns_pct["f1_s1_d50"]
    assert dropped <= base


def test_higher_fees_worsen_returns():
    matrix = run_stress_battery(
        _result_blob(), fees_mult=[1.0, 3.0], slippage_mult=[1.0], drop_best_pct=[0.0]
    )
    assert matrix.returns_pct["f3_s1_d0"] <= matrix.returns_pct["f1_s1_d0"]


def test_empty_trades_are_handled():
    matrix = run_stress_battery(
        {"summary": {"final_equity": 10000.0, "total_return_pct": 0.0}, "trades": []}
    )
    assert matrix.scenarios
    for key in matrix.n_trades:
        assert matrix.n_trades[key] == 0
