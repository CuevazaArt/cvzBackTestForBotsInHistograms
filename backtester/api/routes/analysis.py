"""Decision-support analysis endpoints (Phase 3).

Walk-Forward and Monte Carlo run as background jobs (same pattern as
experiments/optimize) so they never block the FastAPI thread. Robustness
scoring is cheap enough to remain synchronous.

  POST /api/analysis/walk-forward  → JobStatus (poll /api/jobs/{id})
  POST /api/analysis/monte-carlo   → JobStatus (poll /api/jobs/{id})
  POST /api/analysis/robustness    → ranked list (synchronous)
"""

from __future__ import annotations

import logging
import threading
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
from backtester.api.schemas import JobStatus
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


@router.post("/walk-forward", response_model=JobStatus)
def walk_forward_run(
    req: WalkForwardRequest,
    ctx: AppContext = Depends(get_ctx),
) -> JobStatus:
    """Launch walk-forward analysis as a background job.

    Returns a JobStatus immediately. Poll GET /api/jobs/{id} until
    status is 'done' or 'error'. The full WFA result is in job.result.
    """
    bot_cls = ctx.bot_registry.get(req.bot)
    if bot_cls is None:
        raise HTTPException(status_code=404, detail=f"Unknown bot '{req.bot}'")

    for name, rng in req.param_ranges.items():
        if not isinstance(rng, list) or len(rng) != 2:
            raise HTTPException(
                status_code=422,
                detail=f"param_ranges['{name}'] must be [low, high], got {rng}",
            )
        if rng[0] >= rng[1]:
            raise HTTPException(
                status_code=422,
                detail=f"param_ranges['{name}']: low ({rng[0]}) must be < high ({rng[1]})",
            )

    rows = ctx.downloader.load_candles(
        req.symbol.upper(),
        req.timeframe,
        start_ms=req.start_ms,
        end_ms=req.end_ms,
    )
    if not rows:
        raise HTTPException(status_code=404, detail="No candles in range")
    candles = [Candle.from_dict(r) for r in rows]
    n = len(candles)
    if n < req.train_size + req.test_size:
        raise HTTPException(
            status_code=422,
            detail=(
                f"Not enough candles ({n}) for "
                f"train_size={req.train_size} + test_size={req.test_size}"
            ),
        )

    job = ctx.jobs.create("walk_forward")
    ctx.jobs.update(
        job.id,
        status="pending",
        message=f"Queued WFA {req.bot} {req.symbol} {req.timeframe}",
    )

    bcfg = BacktestConfig(
        initial_cash=Decimal(str(req.initial_cash)),
        taker_fee_pct=Decimal(str(req.taker_fee_pct)),
        slippage_pct=Decimal(str(req.slippage_pct)),
    )

    def _run() -> None:
        ctx.jobs.update(
            job.id, status="running", message="Running walk-forward windows…"
        )

        def _backtest(params: dict[str, Any], lo: int, hi: int) -> dict[str, Any]:
            from backtester.core.engine import BacktestEngine

            merged = {**req.base_params, **params}
            try:
                bot = bot_cls(**merged)
            except TypeError as e:
                raise ValueError(f"Invalid params: {e}") from e
            engine = BacktestEngine(bcfg)
            result = engine.run(
                [bot], candles[lo:hi], symbol=req.symbol, timeframe=req.timeframe
            )
            return compute_metrics(result)

        def _train(
            is_start: int, is_end: int, idx: int
        ) -> tuple[dict[str, Any], dict[str, Any]]:
            import optuna  # noqa: PLC0415

            optuna.logging.set_verbosity(optuna.logging.WARNING)

            def objective(trial: "optuna.Trial") -> float:
                params: dict[str, Any] = {}
                for name, rng in req.param_ranges.items():
                    lo, hi = float(rng[0]), float(rng[1])
                    if lo.is_integer() and hi.is_integer():
                        params[name] = trial.suggest_int(name, int(lo), int(hi))
                    else:
                        params[name] = trial.suggest_float(name, lo, hi)
                metrics = _backtest(params, is_start, is_end)
                return float(metrics.get(req.objective_metric, 0.0))

            study = optuna.create_study(
                direction="maximize"
                if req.objective_metric != "max_drawdown_pct"
                else "minimize",
                sampler=optuna.samplers.TPESampler(seed=42 + idx),
            )
            study.optimize(
                objective, n_trials=req.trials_per_window, show_progress_bar=False
            )
            best = dict(study.best_params)
            is_metrics = _backtest(best, is_start, is_end)
            return best, is_metrics

        def _test(
            params: dict[str, Any], oos_start: int, oos_end: int, _idx: int
        ) -> dict[str, Any]:
            return _backtest(params, oos_start, oos_end)

        total_windows = max(1, (n - req.train_size) // (req.step_size or req.test_size))
        completed_windows = [0]

        def _on_window(w: Any) -> None:
            if ctx.jobs.is_cancel_requested(job.id):
                raise RuntimeError("Job cancelled by user")
            completed_windows[0] += 1
            ctx.jobs.update(
                job.id,
                progress=min(0.99, completed_windows[0] / total_windows),
                message=f"Window {completed_windows[0]}/{total_windows} done",
            )

        try:
            cfg = WalkForwardConfig(
                train_size=req.train_size,
                test_size=req.test_size,
                step_size=req.step_size,
                anchored=req.anchored,
                objective_metric=req.objective_metric,
            )
            result = run_walk_forward(
                n_candles=n,
                config=cfg,
                train_fn=_train,
                test_fn=_test,
                on_window=_on_window,
            )
            ctx.jobs.update(
                job.id,
                status="done",
                progress=1.0,
                message=f"Walk-forward complete: {result.verdict}",
                result=result.to_dict(),
            )
        except ImportError:
            ctx.jobs.update(
                job.id,
                status="error",
                message="Optuna not installed. Run: pip install -r backtester/requirements-optimize.txt",
            )
        except Exception as exc:  # noqa: BLE001
            if "cancelled" in str(exc).lower():
                ctx.jobs.update(job.id, status="cancelled", message="Cancelled")
            else:
                _LOG.exception("Walk-forward job failed")
                ctx.jobs.update(job.id, status="error", message=str(exc))

    threading.Thread(target=_run, daemon=True).start()
    return JobStatus(**ctx.jobs.get(job.id).to_dict())


# ── Monte Carlo ─────────────────────────────────────────────────────


class MonteCarloRequest(BaseModel):
    run_id: str | None = None
    trade_pnls: list[float] | None = None
    trials: int = Field(1000, ge=10, le=100_000)
    method: str = "shuffle"
    seed: int | None = None
    initial_equity: float = 10_000.0
    ruin_drawdown_pct: float = Field(
        50.0,
        gt=0,
        le=100,
        description="Drawdown % considered 'ruin' for prob_ruin metric",
    )


@router.post("/monte-carlo", response_model=JobStatus)
def monte_carlo_run(
    req: MonteCarloRequest,
    ctx: AppContext = Depends(get_ctx),
) -> JobStatus:
    """Launch Monte Carlo simulation as a background job.

    Supply `run_id` to load trades from ResultStore, or `trade_pnls` directly.
    Poll GET /api/jobs/{id} for results.
    """
    pnls: list[float]
    if req.trade_pnls is not None and req.trade_pnls:
        pnls = req.trade_pnls
    elif req.run_id:
        record = ctx.result_store.get(req.run_id)
        if record is None:
            raise HTTPException(status_code=404, detail=f"Run '{req.run_id}' not found")
        payload = record.get("payload", record)
        trades = payload.get("trades", [])
        if isinstance(trades, list) and trades and isinstance(trades[0], dict):
            pnls = [float(t.get("pnl", 0.0)) for t in trades]
        else:
            pnls = []
    else:
        raise HTTPException(status_code=422, detail="Provide trade_pnls or run_id")

    if not pnls:
        raise HTTPException(
            status_code=422, detail="No trades available for simulation"
        )

    job = ctx.jobs.create("monte_carlo")
    ctx.jobs.update(
        job.id,
        status="pending",
        message=f"Queued Monte Carlo ({req.method}, {req.trials} trials)",
    )

    def _run() -> None:
        ctx.jobs.update(job.id, status="running", message="Simulating…")

        def _on_trial(trial_idx: int, total: int) -> None:
            if ctx.jobs.is_cancel_requested(job.id):
                raise RuntimeError("Job cancelled by user")
            ctx.jobs.update(
                job.id,
                progress=trial_idx / total,
                message=f"Trial {trial_idx}/{total}",
            )

        try:
            cfg = MonteCarloConfig(
                trials=req.trials,
                method=req.method,
                seed=req.seed,
                initial_equity=req.initial_equity,
                ruin_drawdown_pct=req.ruin_drawdown_pct,
            )
            result = run_monte_carlo(pnls, cfg, on_trial=_on_trial)
            ctx.jobs.update(
                job.id,
                status="done",
                progress=1.0,
                message=(
                    f"P(profit)={result.prob_profit:.1%} "
                    f"VaR95={result.var_95_pct:.2f}%"
                ),
                result=result.to_dict(),
            )
        except Exception as exc:  # noqa: BLE001
            if "cancelled" in str(exc).lower():
                ctx.jobs.update(job.id, status="cancelled", message="Cancelled")
            else:
                _LOG.exception("Monte Carlo job failed")
                ctx.jobs.update(job.id, status="error", message=str(exc))

    threading.Thread(target=_run, daemon=True).start()
    return JobStatus(**ctx.jobs.get(job.id).to_dict())


# ── Robustness Score ────────────────────────────────────────────────


class RobustnessCandidate(BaseModel):
    params: dict[str, Any]
    metrics: dict[str, Any]


class RobustnessRequest(BaseModel):
    candidates: list[RobustnessCandidate]
    weights: dict[str, float] | None = None


@router.post("/robustness")
def robustness_score(req: RobustnessRequest) -> dict[str, Any]:
    """Score and rank candidates synchronously (cheap CPU operation).

    Returns candidates sorted by composite score with component breakdown.
    """
    if not req.candidates:
        return {"ranked": []}
    cands = [{"params": c.params, "metrics": c.metrics} for c in req.candidates]

    def _label(c: dict) -> str:
        items = ", ".join(f"{k}={v}" for k, v in c["params"].items())
        return items or "default"

    scored = score_runs(cands, weights=req.weights, label_fn=_label)
    return {"ranked": [s.to_dict() for s in scored]}
