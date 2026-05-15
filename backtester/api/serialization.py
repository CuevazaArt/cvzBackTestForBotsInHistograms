"""Convert backtester domain objects → JSON-friendly DTOs."""

from __future__ import annotations

from typing import Any

from backtester.api.schemas import (
    BacktestResponse,
    CandleDTO,
    EquityPoint,
    TradeDTO,
)
from backtester.core.engine import BacktestResult, Candle, Trade


def ms_to_s(ms: int | None) -> int | None:
    """Convert epoch ms → epoch seconds (Lightweight Charts time unit).
    Returns None if ms is None (open trades with no exit).
    """
    if ms is None:
        return None
    return int(ms) // 1000


def candle_to_dto(c: Candle) -> CandleDTO:
    """Engine Candle → Lightweight Charts candle (time in seconds)."""
    return CandleDTO(
        time=int(c.timestamp_ms) // 1000,
        open=c.open, high=c.high, low=c.low, close=c.close, volume=c.volume,
    )


def row_to_candle_dto(row: dict) -> CandleDTO:
    """SQLite row → Lightweight Charts candle (time in seconds)."""
    return CandleDTO(
        time=int(row["timestamp_ms"]) // 1000,
        open=float(row["open"]),
        high=float(row["high"]),
        low=float(row["low"]),
        close=float(row["close"]),
        volume=float(row["volume"]),
    )


def trade_to_dto(t: Trade) -> TradeDTO:
    return TradeDTO(
        entry_time=int(t.entry_time) // 1000,
        exit_time=int(t.exit_time) // 1000 if t.exit_time else None,
        entry_price=float(t.entry_price),
        exit_price=float(t.exit_price),
        qty=float(t.qty),
        pnl=float(t.pnl),
        pnl_pct=float(t.pnl_pct),
        fee_usdt=float(t.fee_usdt),
        reason=t.reason or None,
    )


def equity_curve_to_dtos(result: BacktestResult, candles: list[Candle]) -> list[EquityPoint]:
    """Align equity curve samples to candle timestamps (one-to-one)."""
    n = min(len(result.equity_curve), len(candles))
    return [
        EquityPoint(time=int(candles[i].timestamp_ms) // 1000, value=result.equity_curve[i])
        for i in range(n)
    ]


def result_to_response(
    bot_name: str,
    params: dict[str, Any],
    result: BacktestResult,
    candles: list[Candle],
) -> BacktestResponse:
    return BacktestResponse(
        symbol=result.symbol,
        timeframe=result.timeframe,
        bot=bot_name,
        params=params,
        summary=result.summary(),
        candles=[candle_to_dto(c) for c in candles],       # ← main chart OHLCV
        trades=[trade_to_dto(t) for t in result.trades],
        equity_curve=equity_curve_to_dtos(result, candles),
    )


def json_default(o: Any) -> Any:
    """Custom JSON encoder for types that aren't JSON-native."""
    if isinstance(o, float):
        # Guard against inf/nan which break JSON spec
        if o != o:        return None  # NaN
        if o == float("inf"):   return 1e308
        if o == float("-inf"):  return -1e308
        return o
    raise TypeError(f"Object of type {type(o).__name__} is not JSON serializable")
