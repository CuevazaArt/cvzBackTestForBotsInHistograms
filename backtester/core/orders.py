"""Order types and pending-order machinery.

Backward compatibility: the existing engine API accepts orders as
``{"side": "BUY", "qty": 0.5}`` and treats them as MARKET orders filled at
the close of the current candle. This module extends that to support:

  - LIMIT          : fill only if price reaches `limit_price` intra-bar
  - STOP           : trigger MARKET when price crosses `stop_price`
  - STOP_LIMIT     : trigger LIMIT@limit_price when price crosses `stop_price`
  - TRAILING_STOP  : stop that ratchets up (long) / down (short) by `trail_pct`

Plus *bracket orders*: a MARKET (or LIMIT) entry can carry attached
``stop_loss_*`` / ``take_profit_*`` / ``trailing_stop_pct`` fields. When the
entry fills, the engine automatically creates the corresponding protective
pending orders against the resulting position.

Why intra-bar? Real exchanges fill stops the moment price crosses the trigger
within the candle, not at the next candle's close. Using the candle's
high/low for trigger detection is the industry-standard approximation when
backtesting on OHLC data (it's actually slightly pessimistic for stops,
since real execution may slip *worse* than the stop_price, but slippage_pct
handles that). For LIMIT entries we use the conservative rule "high >=
limit_price" (sell) or "low <= limit_price" (buy) — i.e., the bar must
have actually traded through the limit level.
"""

from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
from enum import Enum
from typing import Optional


class OrderType(str, Enum):
    """Trading order types supported by the engine."""

    MARKET = "MARKET"
    LIMIT = "LIMIT"
    STOP = "STOP"                  # stop-market: triggers MARKET at stop_price
    STOP_LIMIT = "STOP_LIMIT"      # stop-limit: triggers LIMIT@limit_price
    TRAILING_STOP = "TRAILING_STOP"


class OrderSide(str, Enum):
    BUY = "BUY"
    SELL = "SELL"


class TriggerReason(str, Enum):
    """Why an order or position closed — propagated to Trade.reason.

    Allows the UI / analytics to distinguish a planned exit (TAKE_PROFIT)
    from forced ones (STOP_LOSS, TRAILING_STOP, MANUAL_SELL).
    """

    MARKET_ENTRY = "MARKET"
    LIMIT_FILL = "LIMIT"
    STOP_LOSS = "STOP_LOSS"
    TAKE_PROFIT = "TAKE_PROFIT"
    TRAILING_STOP = "TRAILING_STOP"
    MANUAL = "MANUAL"


@dataclass
class PendingOrder:
    """An order waiting for a price condition to be met.

    Lives in ``Portfolio.pending_orders`` until it fills, is cancelled, or
    is detached from a closed position (auto-cancel for bracket children).
    """

    side: OrderSide
    qty: Decimal
    type: OrderType
    stop_price: Optional[Decimal] = None        # for STOP, STOP_LIMIT
    limit_price: Optional[Decimal] = None       # for LIMIT, STOP_LIMIT
    trail_pct: Optional[Decimal] = None         # for TRAILING_STOP
    trail_anchor_price: Optional[Decimal] = None  # auto-updated for trailing
    reason: TriggerReason = TriggerReason.MARKET_ENTRY
    bot_id: str = ""
    # If this order is a protective child of a position, parent_position_id
    # references it so we can cancel the order when the position closes.
    parent_position_id: Optional[int] = None
    # Tag carried for the eventual Trade.reason (e.g. STOP_LOSS, TAKE_PROFIT)
    fill_reason: TriggerReason = TriggerReason.MARKET_ENTRY


def parse_order_dict(d: dict) -> dict:
    """Normalize a bot's order dict into a canonical shape.

    Bots may emit minimal dicts (just side + qty, the legacy format) or rich
    ones with type, limit_price, etc. This function fills in defaults and
    coerces values to Decimal so the engine can be type-strict downstream.
    """
    side = OrderSide(str(d.get("side", "")).upper())
    qty = Decimal(str(d.get("qty", 0)))
    type_str = str(d.get("type", "MARKET")).upper()
    otype = OrderType(type_str) if type_str in OrderType.__members__ else OrderType.MARKET

    def _dec(x):
        return Decimal(str(x)) if x is not None else None

    return {
        "side": side,
        "qty": qty,
        "type": otype,
        "limit_price": _dec(d.get("limit_price")),
        "stop_price": _dec(d.get("stop_price")),
        "trail_pct": _dec(d.get("trail_pct")),
        "stop_loss_price": _dec(d.get("stop_loss_price")),
        "stop_loss_pct": _dec(d.get("stop_loss_pct")),
        "take_profit_price": _dec(d.get("take_profit_price")),
        "take_profit_pct": _dec(d.get("take_profit_pct")),
        "trailing_stop_pct": _dec(d.get("trailing_stop_pct")),
        "reason": d.get("reason") or side.value,
    }


def limit_triggers(po: PendingOrder, high: Decimal, low: Decimal) -> bool:
    """Did this LIMIT order fill on a bar with the given high/low?

    Convention:
      - BUY LIMIT fills if low <= limit_price (price traded down through it)
      - SELL LIMIT fills if high >= limit_price (price traded up through it)
    """
    if po.limit_price is None:
        return False
    if po.side == OrderSide.BUY:
        return low <= po.limit_price
    return high >= po.limit_price


def stop_triggers(po: PendingOrder, high: Decimal, low: Decimal) -> bool:
    """Did this STOP order trigger on a bar with the given high/low?

    Convention:
      - BUY STOP triggers if high >= stop_price (breakout entry)
      - SELL STOP triggers if low <= stop_price (stop-loss exit)
    """
    if po.stop_price is None:
        return False
    if po.side == OrderSide.BUY:
        return high >= po.stop_price
    return low <= po.stop_price


def update_trailing_anchor(po: PendingOrder, high: Decimal, low: Decimal) -> None:
    """Ratchet a TRAILING_STOP's anchor in the favorable direction only.

    For a SELL trailing stop (protective long-exit): anchor = highest high
    seen since order placement. New stop_price = anchor * (1 - trail_pct).

    For a BUY trailing stop (protective short-exit): anchor = lowest low
    seen. New stop_price = anchor * (1 + trail_pct).
    """
    if po.type != OrderType.TRAILING_STOP or po.trail_pct is None:
        return
    if po.side == OrderSide.SELL:
        if po.trail_anchor_price is None or high > po.trail_anchor_price:
            po.trail_anchor_price = high
            po.stop_price = po.trail_anchor_price * (Decimal(1) - po.trail_pct / Decimal(100))
    else:  # BUY
        if po.trail_anchor_price is None or low < po.trail_anchor_price:
            po.trail_anchor_price = low
            po.stop_price = po.trail_anchor_price * (Decimal(1) + po.trail_pct / Decimal(100))
