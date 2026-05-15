"""Candle access: list symbols, fetch series, download new history."""

from __future__ import annotations

import logging
import threading

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException, Query

from backtester.api.deps import AppContext, get_ctx
from backtester.api.security import audit_event
from backtester.api.schemas import (
    CandleDTO,
    DownloadRequest,
    DownloadZipRequest,
    JobStatus,
    SymbolEntry,
)
from backtester.api.serialization import row_to_candle_dto

_LOG = logging.getLogger("backtester.api.candles")

router = APIRouter(tags=["candles"])


@router.get("/candles/symbols", response_model=list[SymbolEntry])
def list_symbols(ctx: AppContext = Depends(get_ctx)) -> list[SymbolEntry]:
    return [SymbolEntry(**row) for row in ctx.downloader.list_symbols()]


@router.post("/candles/download", response_model=JobStatus)
def start_download(
    req: DownloadRequest,
    bg: BackgroundTasks,
    resume_job_id: str | None = Query(
        None, description="Resume a previous download job"
    ),
    ctx: AppContext = Depends(get_ctx),
) -> JobStatus:
    start_from_ms: int | None = None
    if resume_job_id is not None:
        prev = ctx.jobs.get(resume_job_id)
        if prev is None:
            raise HTTPException(404, f"Job '{resume_job_id}' not found")
        if prev.status == "running":
            raise HTTPException(409, f"Job '{resume_job_id}' is still running")
        prev_result = prev.result or {}
        start_from_ms = prev_result.get("last_timestamp_ms")

    job = ctx.jobs.create("download")
    run_id = ctx.jobs.create_run(
        "download",
        {
            "symbol": req.symbol.upper(),
            "timeframe": req.timeframe,
            "date_from": req.date_from,
            "date_to": req.date_to,
        },
    )
    msg = f"Queued {req.symbol} {req.timeframe} {req.date_from}→{req.date_to}" + (
        f" (resuming from {start_from_ms})" if start_from_ms else ""
    )
    ctx.jobs.update(
        job.id,
        status="pending",
        run_id=run_id,
        message=msg,
    )
    audit_event(
        "candles.download_started",
        {
            "job_id": job.id,
            "run_id": run_id,
            "symbol": req.symbol.upper(),
            "timeframe": req.timeframe,
            "date_from": req.date_from,
            "date_to": req.date_to,
        },
    )

    def _run() -> None:
        ctx.jobs.update(job.id, status="running")
        try:
            if ctx.jobs.is_cancel_requested(job.id):
                ctx.jobs.update(
                    job.id,
                    status="cancelled",
                    message="Cancelled before start",
                )
                return

            def _on_progress(candles_added: int, last_ts: int) -> None:
                ctx.jobs.update(
                    job.id,
                    result={
                        "candles_added": candles_added,
                        "last_timestamp_ms": last_ts,
                    },
                )

            count = ctx.downloader.download(
                req.symbol.upper(),
                req.timeframe,
                req.date_from,
                req.date_to,
                start_from_ms=start_from_ms,
                on_progress=_on_progress,
            )
            if ctx.jobs.is_cancel_requested(job.id):
                ctx.jobs.update(
                    job.id,
                    status="cancelled",
                    progress=1.0,
                    message="Cancelled",
                    result={"candles_added": count},
                )
                return
            ctx.jobs.update(
                job.id,
                status="done",
                progress=1.0,
                message=f"Downloaded {count} candles",
                result={"candles_added": count},
            )
        except Exception as exc:  # noqa: BLE001
            _LOG.exception("Download job failed")
            ctx.jobs.update(job.id, status="error", message=str(exc))

    # Use a real thread so the request returns immediately even if
    # BackgroundTasks would otherwise serialize.
    threading.Thread(target=_run, daemon=True).start()
    return JobStatus(**ctx.jobs.get(job.id).to_dict())


@router.post("/candles/download/zip", response_model=JobStatus)
def start_download_zip(
    req: DownloadZipRequest,
    bg: BackgroundTasks,
    ctx: AppContext = Depends(get_ctx),
) -> JobStatus:
    job = ctx.jobs.create("download_zip")
    run_id = ctx.jobs.create_run(
        "download_zip",
        {
            "symbol": req.symbol.upper(),
            "timeframe": req.timeframe,
            "year": req.year,
            "month": req.month,
        },
    )
    ctx.jobs.update(
        job.id,
        status="pending",
        run_id=run_id,
        message=f"Queued ZIP {req.symbol} {req.timeframe} {req.year}-{req.month:02d}",
    )
    audit_event(
        "candles.download_zip_started",
        {
            "job_id": job.id,
            "run_id": run_id,
            "symbol": req.symbol.upper(),
            "timeframe": req.timeframe,
            "year": req.year,
            "month": req.month,
        },
    )

    def _run() -> None:
        ctx.jobs.update(job.id, status="running")
        try:
            if ctx.jobs.is_cancel_requested(job.id):
                ctx.jobs.update(
                    job.id,
                    status="cancelled",
                    message="Cancelled before start",
                )
                return
            count = ctx.downloader.download_vision_zip(
                req.symbol.upper(),
                req.timeframe,
                req.year,
                req.month,
            )
            if ctx.jobs.is_cancel_requested(job.id):
                ctx.jobs.update(
                    job.id,
                    status="cancelled",
                    progress=1.0,
                    message="Cancelled",
                    result={"candles_added": count},
                )
                return
            ctx.jobs.update(
                job.id,
                status="done",
                progress=1.0,
                message=f"Downloaded {count} candles via ZIP",
                result={"candles_added": count},
            )
        except Exception as exc:  # noqa: BLE001
            _LOG.exception("Download zip job failed")
            ctx.jobs.update(job.id, status="error", message=str(exc))

    threading.Thread(target=_run, daemon=True).start()
    return JobStatus(**ctx.jobs.get(job.id).to_dict())


@router.get("/candles/{symbol}/{timeframe}", response_model=list[CandleDTO])
def get_candles(
    symbol: str,
    timeframe: str,
    start_ms: int | None = Query(None),
    end_ms: int | None = Query(None),
    limit: int | None = Query(None, ge=1, le=100_000),
    ctx: AppContext = Depends(get_ctx),
) -> list[CandleDTO]:
    rows = ctx.downloader.load_candles(
        symbol.upper(),
        timeframe,
        start_ms=start_ms,
        end_ms=end_ms,
        limit=limit,
    )
    if not rows:
        raise HTTPException(404, f"No candles for {symbol} {timeframe}")
    return [row_to_candle_dto(r) for r in rows]


@router.get("/jobs/{job_id}", response_model=JobStatus)
def get_job(job_id: str, ctx: AppContext = Depends(get_ctx)) -> JobStatus:
    job = ctx.jobs.get(job_id)
    if job is None:
        raise HTTPException(404, f"Job '{job_id}' not found")
    return JobStatus(**job.to_dict())


@router.get("/jobs", response_model=list[JobStatus])
def list_jobs(
    kind: str | None = Query(None, description="Filter by job kind"),
    status: str | None = Query(None, description="Filter by job status"),
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    ctx: AppContext = Depends(get_ctx),
) -> list[JobStatus]:
    return [
        JobStatus(**d)
        for d in ctx.jobs.list_filtered(
            kind=kind, status=status, limit=limit, offset=offset
        )
    ]


@router.post("/jobs/{job_id}/cancel", response_model=JobStatus)
def cancel_job(job_id: str, ctx: AppContext = Depends(get_ctx)) -> JobStatus:
    job = ctx.jobs.get(job_id)
    if job is None:
        raise HTTPException(404, f"Job '{job_id}' not found")
    if job.status in ("done", "error", "cancelled"):
        return JobStatus(**job.to_dict())
    ctx.jobs.request_cancel(job_id)
    ctx.jobs.update(job_id, message="Cancellation requested")
    audit_event("jobs.cancel_requested", {"job_id": job_id})
    updated = ctx.jobs.get(job_id)
    if updated is None:
        raise HTTPException(404, f"Job '{job_id}' not found")
    return JobStatus(**updated.to_dict())


@router.delete("/jobs/{job_id}")
def delete_job(job_id: str, ctx: AppContext = Depends(get_ctx)) -> dict[str, bool]:
    if not ctx.jobs.delete(job_id):
        raise HTTPException(404, f"Job '{job_id}' not found")
    return {"deleted": True}


@router.post("/jobs/cleanup")
def cleanup_jobs(
    older_than_seconds: int = Query(7 * 86400, ge=60),
    ctx: AppContext = Depends(get_ctx),
) -> dict[str, int]:
    return {"deleted": ctx.jobs.cleanup_older_than(older_than_seconds)}
