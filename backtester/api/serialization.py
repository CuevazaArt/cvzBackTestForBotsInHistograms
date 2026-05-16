"""Convert backtester domain objects → JSON-friendly DTOs."""

from __future__ import annotations

from collections import Counter
from decimal import Decimal
from typing import Any, cast

from backtester.api.schemas import (
    BacktestResponse,
    BotRunSpec,
    CandleDTO,
    EquityPoint,
    TradeDTO,
)
from backtester.core.engine import BacktestResult, Trade
from backtester.core.metrics import compute_metrics


def unique_bot_names(bots: list) -> list[str]:
    """Return stable unique names; appends _N suffix on duplicates.

    Accepts both BotRunSpec instances and plain dicts so it works from
    both the REST route (Pydantic models) and the WS handler.
    """

    def _name(b) -> str:
        return b["name"] if isinstance(b, dict) else b.name

    counts: Counter = Counter(_name(b) for b in bots)
    seen: dict[str, int] = {}
    names: list[str] = []
    for b in bots:
        n = _name(b)
        if counts[n] > 1:
            names.append(f"{n}_{seen.get(n, 0)}")
            seen[n] = seen.get(n, 0) + 1
        else:
            names.append(n)
    return names


def ms_to_s(ms: int) -> int:
    """Convert epoch ms → epoch seconds (Lightweight Charts time unit)."""
    return int(ms) // 1000


def row_to_candle_dto(row: dict) -> CandleDTO:
    """SQLite row → Lightweight Charts candle."""
    return CandleDTO(
        time=ms_to_s(row["timestamp_ms"]),
        open=float(row["open"]),
        high=float(row["high"]),
        low=float(row["low"]),
        close=float(row["close"]),
        volume=float(row["volume"]),
    )


def trade_to_dto(t: Trade) -> TradeDTO:
    return TradeDTO(
        entry_time=ms_to_s(t.entry_time),
        exit_time=ms_to_s(t.exit_time),
        entry_price=float(t.entry_price),
        exit_price=float(t.exit_price),
        qty=float(t.qty),
        pnl=float(t.pnl),
        pnl_pct=float(t.pnl_pct),
        fee_usdt=float(t.fee_usdt),
        reason=t.reason,
        side=t.side,
        bot_id=t.bot_id,
    )


def equity_curve_dto(result: BacktestResult, candles: list) -> list[EquityPoint]:
    """Align equity curve to candle timestamps."""
    out: list[EquityPoint] = []
    n = min(len(result.equity_curve), len(candles))
    for i in range(n):
        out.append(
            EquityPoint(
                time=ms_to_s(candles[i].timestamp_ms),
                value=float(result.equity_curve[i]),
            )
        )
    return out


def result_to_response(
    bots: list[Any],
    result: BacktestResult,
    candles: list,
) -> BacktestResponse:
    # Pydantic accepts plain dicts and coerces them into BotRunSpec instances
    # (see ``BacktestResponse.bots``). The cast keeps mypy quiet without
    # forcing every caller to instantiate ``BotRunSpec`` up-front.
    return BacktestResponse(
        symbol=result.symbol,
        timeframe=result.timeframe,
        bots=cast("list[BotRunSpec]", bots),
        summary=compute_metrics(result),
        trades=[trade_to_dto(t) for t in result.trades],
        equity_curve=equity_curve_dto(result, candles),
        per_bot=result.per_bot,
    )


def json_default(o: Any):
    """Custom JSON encoder for Decimal etc. (used in WS streaming)."""
    if isinstance(o, Decimal):
        return float(o)
    raise TypeError(f"Object of type {type(o).__name__} is not JSON serializable")
