"""POST /experiments/run — fan-out parameter sweep with ProcessPool."""

from __future__ import annotations

import logging
import threading

from fastapi import APIRouter, Depends, HTTPException

from backtester.api.deps import AppContext, get_ctx
from backtester.api.schemas import ExperimentsRequest, JobStatus
from backtester.experiments import Experiment, ExperimentRunner

_LOG = logging.getLogger("backtester.api.experiments")

router = APIRouter(tags=["experiments"])


@router.post("/experiments/run", response_model=JobStatus)
def start_experiments(
    req: ExperimentsRequest, ctx: AppContext = Depends(get_ctx),
) -> JobStatus:
    experiments: list[Experiment] = []
    for bot_cfg in req.bots:
        if bot_cfg.name not in ctx.bot_registry:
            raise HTTPException(400, f"Unknown bot '{bot_cfg.name}'")
        for params in bot_cfg.configs:
            experiments.append(Experiment(
                symbol=req.symbol.upper(),
                timeframe=req.timeframe,
                bot_class=bot_cfg.name,
                bot_params=params,
            ))

    if not experiments:
        raise HTTPException(400, "No experiment configs provided")

    job = ctx.jobs.create("experiment")
    ctx.jobs.update(job.id, message=f"Running {len(experiments)} experiments")
    total = len(experiments)

    def _run() -> None:
        ctx.jobs.update(job.id, status="running")
        runner = ExperimentRunner(ctx.downloader, ctx.bot_registry, cache=ctx.indicator_cache)

        def _progress(done: int, total: int) -> None:
            ctx.jobs.update(
                job.id,
                progress=done / total if total else 1.0,
                message=f"{done}/{total} done",
            )

        try:
            results = runner.run_batch(experiments, workers=req.workers,
                                       progress_callback=_progress)
            serialized = [
                {
                    "bot": r.experiment.bot_class,
                    "params": r.experiment.bot_params,
                    "success": r.success,
                    "metrics": r.metrics if r.success else None,
                    "error": r.error,
                }
                for r in results
            ]
            cache_stats = runner._cache.stats() if runner._cache is not None else None
            ctx.jobs.update(
                job.id, status="done", progress=1.0,
                message=f"Completed {total} experiments",
                result={"runs": serialized, "total": total, "cache_stats": cache_stats},
            )
        except Exception as exc:  # noqa: BLE001
            _LOG.exception("Experiment job failed")
            ctx.jobs.update(job.id, status="error", message=str(exc))

    threading.Thread(target=_run, daemon=True).start()
    return JobStatus(**ctx.jobs.get(job.id).to_dict())
