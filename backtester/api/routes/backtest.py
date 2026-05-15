"""POST /backtest/run — synchronous full-history backtest."""

from __future__ import annotations

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
    bot_cls = ctx.bot_registry.get(req.bot)
    if bot_cls is None:
        raise HTTPException(404, f"Bot '{req.bot}' not found")

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
        initial_cash=float(req.initial_cash),
        taker_fee_pct=float(req.taker_fee_pct),
        slippage_pct=float(req.slippage_pct),
    )

    try:
        bot = bot_cls(**req.params)
    except TypeError as e:
        raise HTTPException(400, f"Invalid params for {req.bot}: {e}")

    engine = BacktestEngine(cfg)
    result = engine.run(bot, candles, symbol=req.symbol.upper(), timeframe=req.timeframe)
    return result_to_response(req.bot, req.params, result, candles)
