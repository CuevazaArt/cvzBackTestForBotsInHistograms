"""POST /backtest/run — synchronous full-history backtest."""

from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException

from backtester.api.deps import AppContext, get_ctx
from backtester.api.schemas import BacktestRequest, BacktestResponse
from backtester.api.serialization import result_to_response
from backtester.core.engine import BacktestConfig, BacktestEngine, Candle

router = APIRouter(tags=["backtest"])


@router.post("/backtest/run", response_model=BacktestResponse)
def run_backtest(
    req: BacktestRequest, ctx: AppContext = Depends(get_ctx),
) -> BacktestResponse:
    if not req.bots:
        raise HTTPException(400, "At least one bot is required")
        
    bots_instances = []
    for b in req.bots:
        bot_cls = ctx.bot_registry.get(b.name)
        if bot_cls is None:
            raise HTTPException(404, f"Bot '{b.name}' not found")
        try:
            bot = bot_cls(**b.params)
            bots_instances.append(bot)
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

    engine = BacktestEngine(cfg)
    result = engine.run(bots_instances, candles, symbol=req.symbol.upper(), timeframe=req.timeframe)
    return result_to_response([b.model_dump() for b in req.bots], result, candles)
