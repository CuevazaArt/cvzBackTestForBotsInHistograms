"""Backtest result retrieval endpoints."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from backtester.api.deps import AppContext, get_ctx

router = APIRouter(tags=["results"])


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
