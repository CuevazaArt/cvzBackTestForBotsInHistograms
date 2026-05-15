"""POST /backtest/run — synchronous full-history backtest, with CSV/JSON export."""

from __future__ import annotations

import csv
import io
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import JSONResponse, Response

from backtester.api.deps import AppContext, get_ctx
from backtester.api.schemas import BacktestRequest, BacktestResponse
from backtester.api.serialization import result_to_response, unique_bot_names
from backtester.core.engine import BacktestConfig, BacktestEngine, Candle

router = APIRouter(tags=["backtest"])


_CSV_COLUMNS = [
    "bot_id",
    "entry_time",
    "exit_time",
    "entry_price",
    "exit_price",
    "qty",
    "pnl",
    "pnl_pct",
    "fee_usdt",
    "reason",
]


def _execute(req: BacktestRequest, ctx: AppContext) -> BacktestResponse:
    if not req.bots:
        raise HTTPException(400, "At least one bot is required")

    bots_instances = []
    for b in req.bots:
        bot_cls = ctx.bot_registry.get(b.name)
        if bot_cls is None:
            raise HTTPException(404, f"Bot '{b.name}' not found")
        try:
            bots_instances.append(bot_cls(**b.params))
        except TypeError as e:
            raise HTTPException(400, f"Invalid params for {b.name}: {e}")

    rows = ctx.downloader.load_candles(
        req.symbol.upper(), req.timeframe,
        start_ms=req.start_ms, end_ms=req.end_ms,
    )
    if not rows:
        raise HTTPException(
            400, f"No candles for {req.symbol} {req.timeframe} in range. Download first.",
        )

    candles = [Candle.from_dict(r) for r in rows]
    cfg = BacktestConfig(
        initial_cash=Decimal(str(req.initial_cash)),
        taker_fee_pct=Decimal(str(req.taker_fee_pct)),
        slippage_pct=Decimal(str(req.slippage_pct)),
    )

    bot_names = unique_bot_names(req.bots)
    engine = BacktestEngine(cfg)
    indicator_specs = [{"name": i.name, **i.to_kwargs()} for i in req.indicators]
    result = engine.run(
        bots_instances, candles,
        symbol=req.symbol.upper(), timeframe=req.timeframe,
        bot_names=bot_names,
        indicator_specs=indicator_specs,
    )
    return result_to_response([b.model_dump() for b in req.bots], result, candles)


@router.post("/backtest/run", response_model=BacktestResponse)
def run_backtest(
    req: BacktestRequest, ctx: AppContext = Depends(get_ctx),
) -> BacktestResponse:
    return _execute(req, ctx)


@router.post("/backtest/export/trades")
def export_trades(
    req: BacktestRequest,
    fmt: str = Query("csv", alias="format", pattern="^(csv|json)$"),
    ctx: AppContext = Depends(get_ctx),
):
    """Run the backtest and return its trades in the requested format.

    Why stateless: /backtest/run is synchronous and we don't (yet) persist
    full results — re-running with the same request is cheap and avoids a
    server-side cache. Switch to job-id lookup once async backtests land.
    """
    resp = _execute(req, ctx)
    trades = [t.model_dump() for t in resp.trades]

    if fmt == "json":
        return JSONResponse(
            content={
                "symbol": resp.symbol,
                "timeframe": resp.timeframe,
                "trades": trades,
                "summary": resp.summary,
            }
        )

    # CSV
    buf = io.StringIO()
    writer = csv.DictWriter(buf, fieldnames=_CSV_COLUMNS, extrasaction="ignore")
    writer.writeheader()
    for t in trades:
        writer.writerow(t)
    filename = f"trades_{resp.symbol}_{resp.timeframe}.csv"
    return Response(
        content=buf.getvalue(),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
