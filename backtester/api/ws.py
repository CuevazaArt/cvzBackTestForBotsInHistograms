"""WebSocket /ws — live streaming of backtest events.

Phase 2 will wire this to a StreamingEngine that emits candle/trade/equity
events as the bot processes the historical series. For now it accepts a
connection and echoes "ready" so the Flutter shell can be developed against it.
"""

from __future__ import annotations

import asyncio
import json
import logging
from decimal import Decimal

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from backtester.api.schemas import BacktestRequest
from backtester.api.serialization import json_default
from backtester.core.engine import BacktestConfig, Candle

_LOG = logging.getLogger("backtester.api.ws")

router = APIRouter()


@router.websocket("/ws")
async def ws_endpoint(websocket: WebSocket) -> None:
    await websocket.accept()
    ctx = websocket.app.state.ctx
    loop = asyncio.get_running_loop()

    def _send(event_type: str, data: dict | None = None) -> None:
        """Thread-safe send (callable from worker threads)."""
        payload = json.dumps(
            {"type": event_type, "data": data or {}}, default=json_default,
        )
        asyncio.run_coroutine_threadsafe(websocket.send_text(payload), loop)

    _send("ready", {"version": "0.1.0"})

    try:
        while True:
            msg = await websocket.receive_json()
            action = msg.get("action")

            if action == "ping":
                _send("pong", {})

            elif action == "backtest":
                try:
                    req = BacktestRequest(**msg["config"])
                except Exception as exc:  # noqa: BLE001
                    _send("error", {"message": f"Bad config: {exc}"})
                    continue

                # Imported lazily so engine_stream is not required at boot
                from backtester.core.engine_stream import StreamingEngine

                bot_cls = ctx.bot_registry.get(req.bot)
                if bot_cls is None:
                    _send("error", {"message": f"Unknown bot '{req.bot}'"})
                    continue

                rows = ctx.downloader.load_candles(
                    req.symbol.upper(), req.timeframe,
                    start_ms=req.start_ms, end_ms=req.end_ms,
                )
                if not rows:
                    _send("error", {"message": "No candles in range"})
                    continue

                candles = [Candle.from_dict(r) for r in rows]
                cfg = BacktestConfig(
                    initial_cash=Decimal(str(req.initial_cash)),
                    taker_fee_pct=Decimal(str(req.taker_fee_pct)),
                    slippage_pct=Decimal(str(req.slippage_pct)),
                )
                try:
                    bot = bot_cls(**req.params)
                except TypeError as e:
                    _send("error", {"message": f"Invalid params: {e}"})
                    continue

                engine = StreamingEngine(cfg, on_event=_send, total=len(candles))
                # Run the synchronous engine in a worker thread so the WS
                # event loop stays responsive (and pings can fly through).
                await asyncio.to_thread(
                    engine.run, bot, candles, req.symbol.upper(), req.timeframe,
                )

            else:
                _send("error", {"message": f"Unknown action '{action}'"})

    except WebSocketDisconnect:
        _LOG.info("WebSocket disconnected")
    except Exception:  # noqa: BLE001
        _LOG.exception("WebSocket handler crashed")
        try:
            await websocket.close()
        except Exception:  # noqa: BLE001
            pass
