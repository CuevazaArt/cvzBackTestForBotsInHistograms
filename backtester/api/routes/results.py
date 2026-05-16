"""Backtest result retrieval + comparison endpoints."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response

from backtester.api.deps import AppContext, get_ctx
from backtester.api.schemas import (
    ComparedRun,
    CompareRunsRequest,
    CompareRunsResponse,
    StressRequest,
    StressResponse,
)
from backtester.analysis import run_stress_battery, stress_matrix_to_dict
from backtester.reporting import build_report

router = APIRouter(tags=["results"])

# Keys we expose from the persisted result blob into the comparator summary.
# Anything missing is filled with None so the Flutter table can show "—".
_COMPARE_SUMMARY_KEYS = (
    "total_return_pct",
    "win_rate_pct",
    "profit_factor",
    "max_drawdown_pct",
    "final_equity",
    "trades",
    "total_fees_usdt",
    "sharpe_ratio",
    "sortino_ratio",
    "cagr_pct",
    "calmar_ratio",
)


def _extract_summary(result_blob: dict[str, Any]) -> dict[str, Any]:
    """Pick the comparison-relevant metrics out of a stored result blob."""
    summary_block = result_blob.get("summary") or {}
    out: dict[str, Any] = {k: summary_block.get(k) for k in _COMPARE_SUMMARY_KEYS}
    # Some blobs (older / from /backtest/run) keep these at the top level.
    for k in ("final_equity", "max_drawdown_pct", "trades"):
        if out.get(k) is None:
            out[k] = result_blob.get(k)
    return out


def _downsample_equity(curve: list[dict], cap: int = 500) -> list[dict]:
    """Reduce an equity curve to at most ``cap`` points, preserving the last
    one so the chart's final value is exact."""
    if not curve or len(curve) <= cap:
        return list(curve)
    step = max(1, len(curve) // cap)
    picked = curve[::step]
    if picked[-1] is not curve[-1]:
        picked.append(curve[-1])
    return picked


@router.get("/backtest/{run_id}")
def get_backtest_result(run_id: str, ctx: AppContext = Depends(get_ctx)) -> dict:
    record = ctx.result_store.get(run_id)
    if record is None:
        raise HTTPException(404, f"Backtest result '{run_id}' not found")
    return record


@router.get("/backtest")
def list_backtest_results(
    symbol: str | None = Query(None),
    timeframe: str | None = Query(None),
    limit: int = Query(50, ge=1, le=500),
    offset: int = Query(0, ge=0),
    ctx: AppContext = Depends(get_ctx),
) -> list[dict]:
    return ctx.result_store.list_recent(
        limit=limit,
        offset=offset,
        symbol=symbol,
        timeframe=timeframe,
    )


@router.delete("/backtest/{run_id}")
def delete_backtest_result(run_id: str, ctx: AppContext = Depends(get_ctx)) -> dict:
    if not ctx.result_store.delete(run_id):
        raise HTTPException(404, f"Backtest result '{run_id}' not found")
    return {"deleted": True}


@router.get("/backtest/{run_id}/report.html", response_class=Response)
def export_backtest_report(run_id: str, ctx: AppContext = Depends(get_ctx)) -> Response:
    """Render a stored backtest run as a self-contained HTML page.

    Useful for sharing on chat or attaching to a journal entry — the
    response is a single HTML document with all assets inlined (Chart.js
    is loaded from a CDN; everything else is inline CSS + JS).
    """
    record = ctx.result_store.get(run_id)
    if record is None:
        raise HTTPException(404, f"Backtest result '{run_id}' not found")
    html = build_report(record)
    return Response(
        content=html,
        media_type="text/html",
        headers={"Content-Disposition": f'inline; filename="backtest_{run_id}.html"'},
    )


@router.post("/backtest/compare", response_model=CompareRunsResponse)
def compare_backtest_runs(
    req: CompareRunsRequest,
    ctx: AppContext = Depends(get_ctx),
) -> CompareRunsResponse:
    """Aggregate several stored runs into one comparable payload.

    Returns the key summary metrics and a downsampled equity curve per run
    so the Flutter Compare tab can render a table + overlaid equity chart
    without re-running anything. Unknown run_ids are reported in ``missing``
    instead of failing the whole request — the UI can grey them out.
    """
    runs: list[ComparedRun] = []
    missing: list[str] = []
    for run_id in req.run_ids:
        record = ctx.result_store.get(run_id)
        if record is None:
            missing.append(run_id)
            continue
        result_blob = record.get("result") or {}
        equity = (
            result_blob.get("equity_curve_downsampled")
            or result_blob.get("equity_curve")
            or []
        )
        # Be defensive: older records may store equity_curve as a plain list
        # of values rather than {time, value} points; convert if needed.
        normalized: list[dict[str, float]] = []
        for pt in equity:
            if isinstance(pt, dict) and "value" in pt:
                normalized.append(
                    {
                        "time": float(pt.get("time", 0)),
                        "value": float(pt["value"]),
                    }
                )
            elif isinstance(pt, (int, float)):
                normalized.append({"time": float(len(normalized)), "value": float(pt)})
        normalized = _downsample_equity(normalized)

        config = record.get("config") or {}
        bots = config.get("bots") or []
        if bots:
            label = ", ".join(b.get("name", "?") for b in bots) or run_id[:8]
        else:
            label = run_id[:8]

        runs.append(
            ComparedRun(
                run_id=run_id,
                symbol=record.get("symbol", ""),
                timeframe=record.get("timeframe", ""),
                label=label,
                created_at=float(record.get("created_at", 0.0)),
                summary=_extract_summary(result_blob),
                equity_curve_downsampled=normalized,
            )
        )
    return CompareRunsResponse(runs=runs, missing=missing)


@router.post("/backtest/{run_id}/stress", response_model=StressResponse)
def stress_backtest_run(
    run_id: str,
    req: StressRequest,
    ctx: AppContext = Depends(get_ctx),
) -> StressResponse:
    record = ctx.result_store.get(run_id)
    if record is None:
        raise HTTPException(404, f"Backtest result '{run_id}' not found")
    result_blob = record.get("result") or {}
    matrix = run_stress_battery(
        result_blob,
        fees_mult=req.fees_mult,
        slippage_mult=req.slippage_mult,
        drop_best_pct=req.drop_best_pct,
    )
    payload = stress_matrix_to_dict(matrix)
    return StressResponse(run_id=run_id, **payload)
