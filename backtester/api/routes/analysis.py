"""Decision-support analysis endpoints (Phase 3).

Provides three POST endpoints that help users choose the best bot setup:

  POST /api/analysis/walk-forward   - rolling train/test validation
  POST /api/analysis/monte-carlo    - trade-order randomization for risk CIs
  POST /api/analysis/robustness     - multi-metric ranking of candidate runs

All endpoints are synchronous (return on completion). For long-running WFA
the engine internally optimizes per-window using Optuna with a small trial
budget; users can switch to /ws actions if they need streaming progress.
"""

from __future__ import annotations

import logging
from decimal import Decimal
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field

from backtester.analysis import (
    MonteCarloConfig,
    WalkForwardConfig,
    run_monte_carlo,
    run_walk_forward,
    score_runs,
)
from backtester.api.deps import AppContext, get_ctx
from backtester.core.engine import BacktestConfig, Candle
from backtester.core.metrics import compute_metrics

_LOG = logging.getLogger("backtester.api.analysis")

router = APIRouter(prefix="/analysis", tags=["analysis"])


# ── Walk-Forward ────────────────────────────────────────────────────


class WalkForwardRequest(BaseModel):
    symbol: str
    timeframe: str
    bot: str
    base_params: dict[str, Any] = Field(default_factory=dict)
    # Param ranges to optimize on each IS window: {param_name: [low, high]}
    param_ranges: dict[str, list[float]] = Field(default_factory=dict)
    train_size: int = Field(..., gt=0, description="In-sample candles")
    test_size: int = Field(..., gt=0, description="Out-of-sample candles")
    step_size: int | None = None
    anchored: bool = False
    trials_per_window: int = Field(20, ge=5, le=200)
    objective_metric: str = "total_return_pct"
    initial_cash: float = 10_000.0
    taker_fee_pct: float = 0.1
    slippage_pct: float = 0.05
    start_ms: int | None = None
    end_ms: int | None = None


@router.post("/walk-forward")
def walk_forward_run(
    req: WalkForwardRequest,
    ctx: AppContext = Depends(get_ctx),
) -> dict[str, Any]:
    """Run walk-forward analysis.

    For each rolling window we run a small Optuna optimization on the IS
    portion and validate the best params on the OOS portion. Reports per-
    window efficiency and an aggregate verdict (robust/weak/overfit).
    """
    bot_cls = ctx.bot_registry.get(req.bot)
    if bot_cls is None:
        raise HTTPException(status_code=404, detail=f"Unknown bot '{req.bot}'")

    rows = ctx.downloader.load_candles(
        req.symbol.upper(), req.timeframe,
        start_ms=req.start_ms, end_ms=req.end_ms,
    )
    if not rows:
        raise HTTPException(status_code=404, detail="No candles in range")
    candles = [Candle.from_dict(r) for r in rows]
    n = len(candles)
    if n < req.train_size + req.test_size:
        raise HTTPException(
            status_code=422,
            detail=f"Not enough candles ({n}) for train_size={req.train_size} + test_size={req.test_size}",
        )

    bcfg = BacktestConfig(
        initial_cash=Decimal(str(req.initial_cash)),
        taker_fee_pct=Decimal(str(req.taker_fee_pct)),
        slippage_pct=Decimal(str(req.slippage_pct)),
    )

    def _backtest(params: dict[str, Any], lo: int, hi: int) -> dict[str, Any]:
        from backtester.core.engine import BacktestEngine
        slice_ = candles[lo:hi]
        merged = {**req.base_params, **params}
        try:
            bot = bot_cls(**merged)
        except TypeError as e:
            raise HTTPException(status_code=422, detail=f"Invalid params: {e}") from e
        engine = BacktestEngine(bcfg)
        result = engine.run([bot], slice_, symbol=req.symbol, timeframe=req.timeframe)
        return compute_metrics(result)

    def _train(is_start: int, is_end: int, idx: int) -> tuple[dict[str, Any], dict[str, Any]]:
        # Lazy import — Optuna is heavy
        import optuna
        optuna.logging.set_verbosity(optuna.logging.WARNING)

        def objective(trial: "optuna.Trial") -> float:
            params: dict[str, Any] = {}
            for name, rng in req.param_ranges.items():
                lo, hi = float(rng[0]), float(rng[1])
                # Heuristic: integer if both bounds are whole numbers
                if lo.is_integer() and hi.is_integer():
                    params[name] = trial.suggest_int(name, int(lo), int(hi))
                else:
                    params[name] = trial.suggest_float(name, lo, hi)
            metrics = _backtest(params, is_start, is_end)
            return float(metrics.get(req.objective_metric, 0.0))

        study = optuna.create_study(
            direction="maximize" if req.objective_metric != "max_drawdown_pct" else "minimize",
            sampler=optuna.samplers.TPESampler(seed=42 + idx),
        )
        study.optimize(objective, n_trials=req.trials_per_window, show_progress_bar=False)
        best = dict(study.best_params)
        is_metrics = _backtest(best, is_start, is_end)
        return best, is_metrics

    def _test(params: dict[str, Any], oos_start: int, oos_end: int, idx: int) -> dict[str, Any]:
        return _backtest(params, oos_start, oos_end)

    cfg = WalkForwardConfig(
        train_size=req.train_size,
        test_size=req.test_size,
        step_size=req.step_size,
        anchored=req.anchored,
        objective_metric=req.objective_metric,
    )
    result = run_walk_forward(n_candles=n, config=cfg, train_fn=_train, test_fn=_test)
    return result.to_dict()


# ── Monte Carlo ─────────────────────────────────────────────────────


class MonteCarloRequest(BaseModel):
    # Option A: load trades from a saved run_id
    run_id: str | None = None
    # Option B: provide raw PnLs directly (useful for what-if analysis)
    trade_pnls: list[float] | None = None
    trials: int = Field(1000, ge=10, le=100_000)
    method: str = "shuffle"   # "shuffle" | "bootstrap"
    seed: int | None = None
    initial_equity: float = 10_000.0


@router.post("/monte-carlo")
def monte_carlo_run(
    req: MonteCarloRequest,
    ctx: AppContext = Depends(get_ctx),
) -> dict[str, Any]:
    """Run Monte Carlo simulation on trade PnLs.

    Either supply `run_id` (load trades from ResultStore) or `trade_pnls`
    directly. Returns percentile distributions for return, drawdown, and
    losing streaks plus probability-of-profit and Value-at-Risk.
    """
    pnls: list[float]
    if req.trade_pnls is not None and req.trade_pnls:
        pnls = req.trade_pnls
    elif req.run_id:
        record = ctx.result_store.get(req.run_id)
        if record is None:
            raise HTTPException(status_code=404, detail=f"Run '{req.run_id}' not found")
        # ResultStore stores trades as list of dicts under "trades" or in payload
        payload = record.get("payload", record)
        trades = payload.get("trades", [])
        if isinstance(trades, list) and trades and isinstance(trades[0], dict):
            pnls = [float(t.get("pnl", 0.0)) for t in trades]
        else:
            pnls = []
    else:
        raise HTTPException(status_code=422, detail="Provide trade_pnls or run_id")

    if not pnls:
        raise HTTPException(status_code=422, detail="No trades available for simulation")

    cfg = MonteCarloConfig(
        trials=req.trials,
        method=req.method,
        seed=req.seed,
        initial_equity=req.initial_equity,
    )
    result = run_monte_carlo(pnls, cfg)
    return result.to_dict()


# ── Robustness Score ────────────────────────────────────────────────


class RobustnessCandidate(BaseModel):
    params: dict[str, Any]
    metrics: dict[str, Any]


class RobustnessRequest(BaseModel):
    candidates: list[RobustnessCandidate]
    weights: dict[str, float] | None = None


@router.post("/robustness")
def robustness_score(req: RobustnessRequest) -> dict[str, Any]:
    """Score and rank a batch of candidate configurations.

    Input is a list of {params, metrics} dicts (typically from optimization
    results). Returns the candidates sorted by composite score with component
    breakdown so the user can see why a config ranked where it did.
    """
    if not req.candidates:
        return {"ranked": []}
    cands = [{"params": c.params, "metrics": c.metrics} for c in req.candidates]

    def _label(c: dict) -> str:
        items = ", ".join(f"{k}={v}" for k, v in c["params"].items())
        return items or "default"

    scored = score_runs(cands, weights=req.weights, label_fn=_label)
    return {"ranked": [s.to_dict() for s in scored]}
