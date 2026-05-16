"""Stress battery over persisted backtest trades."""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any


@dataclass
class StressScenario:
    fees_mult: float
    slippage_mult: float
    drop_best_pct: float


@dataclass
class StressMatrix:
    scenarios: list[StressScenario]
    sharpe: dict[str, float]
    returns_pct: dict[str, float]
    max_dd_pct: dict[str, float]
    n_trades: dict[str, int]


def _scenario_key(fees_mult: float, slippage_mult: float, drop_best_pct: float) -> str:
    return f"f{fees_mult:g}_s{slippage_mult:g}_d{drop_best_pct:g}"


def _safe_initial_equity(result_blob: dict[str, Any]) -> float:
    summary = result_blob.get("summary") or {}
    final_eq = float(summary.get("final_equity", 0.0) or 0.0)
    total_return_pct = float(summary.get("total_return_pct", 0.0) or 0.0)
    denom = 1.0 + (total_return_pct / 100.0)
    if final_eq > 0 and denom > 1e-9:
        return final_eq / denom
    return 10_000.0


def _trade_pnls(result_blob: dict[str, Any]) -> list[float]:
    trades = result_blob.get("trades") or []
    out: list[float] = []
    for t in trades:
        if isinstance(t, dict):
            out.append(float(t.get("pnl", 0.0) or 0.0))
        else:
            out.append(float(getattr(t, "pnl", 0.0)))
    return out


def _trade_fees(result_blob: dict[str, Any]) -> list[float]:
    trades = result_blob.get("trades") or []
    out: list[float] = []
    for t in trades:
        if isinstance(t, dict):
            out.append(float(t.get("fee_usdt", 0.0) or 0.0))
        else:
            out.append(float(getattr(t, "fee_usdt", 0.0)))
    return out


def _calc_sharpe(values: list[float]) -> float:
    if len(values) < 2:
        return 0.0
    mean_v = sum(values) / len(values)
    var_v = sum((v - mean_v) ** 2 for v in values) / len(values)
    if var_v <= 0:
        return 0.0
    return mean_v / (var_v**0.5)


def _max_drawdown_pct_from_equity(equity_curve: list[float]) -> float:
    if not equity_curve:
        return 0.0
    peak = equity_curve[0]
    max_dd = 0.0
    for eq in equity_curve:
        peak = max(peak, eq)
        if peak > 0:
            max_dd = max(max_dd, (peak - eq) / peak)
    return max_dd * 100.0


def run_stress_battery(
    result_blob: dict[str, Any],
    fees_mult: list[float] | None = None,
    slippage_mult: list[float] | None = None,
    drop_best_pct: list[float] | None = None,
) -> StressMatrix:
    """Apply deterministic stress scenarios over observed trades."""
    fees_mult = fees_mult or [1.0, 2.0, 3.0]
    slippage_mult = slippage_mult or [1.0, 2.0, 3.0]
    drop_best_pct = drop_best_pct or [0.0, 5.0, 10.0]

    base_pnls = _trade_pnls(result_blob)
    base_fees = _trade_fees(result_blob)
    initial_equity = _safe_initial_equity(result_blob)

    scenarios: list[StressScenario] = []
    sharpe: dict[str, float] = {}
    returns_pct: dict[str, float] = {}
    max_dd_pct: dict[str, float] = {}
    n_trades: dict[str, int] = {}

    for f_mult in fees_mult:
        for s_mult in slippage_mult:
            for drop_pct in drop_best_pct:
                stressed: list[float] = []
                for pnl, fee in zip(base_pnls, base_fees):
                    extra_fee = fee * max(0.0, f_mult - 1.0)
                    if pnl >= 0:
                        slippage_drag = abs(pnl) * max(0.0, s_mult - 1.0) * 0.5
                    else:
                        slippage_drag = abs(pnl) * max(0.0, s_mult - 1.0)
                    stressed.append(pnl - extra_fee - slippage_drag)

                if stressed and drop_pct > 0:
                    winners = sorted((v for v in stressed if v > 0), reverse=True)
                    k = int(len(winners) * (drop_pct / 100.0))
                    if k > 0:
                        cut = set(winners[:k])
                        kept: list[float] = []
                        for v in stressed:
                            if v > 0 and v in cut:
                                cut.remove(v)
                                continue
                            kept.append(v)
                        stressed = kept

                key = _scenario_key(f_mult, s_mult, drop_pct)
                scenarios.append(
                    StressScenario(
                        fees_mult=float(f_mult),
                        slippage_mult=float(s_mult),
                        drop_best_pct=float(drop_pct),
                    )
                )

                eq = initial_equity
                eq_curve: list[float] = []
                for p in stressed:
                    eq += p
                    eq_curve.append(eq)

                ret_pct = (
                    ((eq - initial_equity) / initial_equity * 100.0)
                    if initial_equity > 0
                    else 0.0
                )
                sharpe[key] = float(round(_calc_sharpe(stressed), 6))
                returns_pct[key] = float(round(ret_pct, 6))
                max_dd_pct[key] = float(
                    round(_max_drawdown_pct_from_equity(eq_curve), 6)
                )
                n_trades[key] = len(stressed)

    return StressMatrix(
        scenarios=scenarios,
        sharpe=sharpe,
        returns_pct=returns_pct,
        max_dd_pct=max_dd_pct,
        n_trades=n_trades,
    )


def stress_matrix_to_dict(matrix: StressMatrix) -> dict[str, Any]:
    return {
        "scenarios": [asdict(s) for s in matrix.scenarios],
        "sharpe": matrix.sharpe,
        "returns_pct": matrix.returns_pct,
        "max_dd_pct": matrix.max_dd_pct,
        "n_trades": matrix.n_trades,
    }
