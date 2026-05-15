"""POST /optimize/run — Optuna-backed hyperparameter optimization."""

from __future__ import annotations

import logging
import threading

from fastapi import APIRouter, Depends, HTTPException

from backtester.api.deps import AppContext, get_ctx
from backtester.api.schemas import JobStatus, OptimizeRequest
from backtester.optimize import Objective, OptimizationConfig

_LOG = logging.getLogger("backtester.api.optimize")

router = APIRouter(tags=["optimize"])


@router.post("/optimize/run", response_model=JobStatus)
def start_optimization(
    req: OptimizeRequest, ctx: AppContext = Depends(get_ctx),
) -> JobStatus:
    if req.bot not in ctx.bot_registry:
        raise HTTPException(400, f"Unknown bot '{req.bot}'")

    # Build the Optuna-compatible search_space dict
    search_space: dict = {}
    for name, param in req.search_space.items():
        entry: dict = {
            "type": param.type,
            "low": param.low,
            "high": param.high,
        }
        if param.step is not None:
            entry["step"] = param.step
        if param.log:
            entry["log"] = True
        if param.choices is not None:
            entry["choices"] = param.choices
        search_space[name] = entry

    job = ctx.jobs.create("optimize")
    ctx.jobs.update(
        job.id,
        status="pending",
        message=f"Queued Optuna {req.sampler} {req.trials} trials for {req.bot}",
    )

    total_trials = req.trials

    def _run() -> None:
        ctx.jobs.update(job.id, status="running", message="Loading candles...")
        try:
            from backtester.optimize.optuna_runner import run_optuna

            opt_cfg = OptimizationConfig(
                symbol=req.symbol.upper(),
                timeframe=req.timeframe,
                bot_class=req.bot,
                search_space=search_space,
                objective=req.objective,
                fixed_params=req.fixed_params,
                initial_cash=req.initial_cash,
                taker_fee_pct=req.taker_fee_pct,
                slippage_pct=req.slippage_pct,
            )
            objective = Objective(opt_cfg, ctx.downloader, ctx.bot_registry)

            collected_trials: list[dict] = []

            def _on_trial(trial_number: int, result) -> None:
                collected_trials.append({
                    "trial": trial_number,
                    "params": result.params,
                    "score": result.score,
                    "metrics": result.metrics,
                })
                ctx.jobs.update(
                    job.id,
                    progress=(trial_number + 1) / total_trials,
                    message=f"Trial {trial_number + 1}/{total_trials} "
                            f"score={result.score:.4f}",
                )

            results = run_optuna(
                objective,
                trials=total_trials,
                sampler=req.sampler,
                on_trial=_on_trial,
            )

            # Build leaderboard-compatible output (sorted best→worst)
            runs = [
                {
                    "bot": req.bot,
                    "params": r.params,
                    "success": True,
                    "metrics": r.metrics,
                    "score": r.score,
                    "error": None,
                }
                for r in results
            ]

            best = results[0] if results else None
            best_msg = (
                f"Best: {req.objective}={best.score:.4f}" if best else "No results"
            )

            ctx.jobs.update(
                job.id,
                status="done",
                progress=1.0,
                message=f"Completed {total_trials} trials. {best_msg}",
                result={
                    "runs": runs,
                    "total": total_trials,
                    "best_params": best.params if best else {},
                    "best_score": best.score if best else 0,
                    "objective": req.objective,
                    "sampler": req.sampler,
                },
            )
        except ImportError as exc:
            _LOG.error("Optuna not installed: %s", exc)
            ctx.jobs.update(
                job.id, status="error",
                message="Optuna not installed. Run: pip install -r backtester/requirements-optimize.txt",
            )
        except Exception as exc:  # noqa: BLE001
            _LOG.exception("Optimization job failed")
            ctx.jobs.update(job.id, status="error", message=str(exc))

    threading.Thread(target=_run, daemon=True).start()
    return JobStatus(**ctx.jobs.get(job.id).to_dict())
