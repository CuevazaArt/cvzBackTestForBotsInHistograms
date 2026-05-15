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

from backtester.api.schemas import BacktestRequest, OptimizeRequest
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

                if not req.bots:
                    _send("error", {"message": "At least one bot is required"})
                    continue

                # Imported lazily so engine_stream is not required at boot
                from backtester.core.engine_stream import StreamingEngine

                bots_instances = []
                has_error = False
                for b in req.bots:
                    bot_cls = ctx.bot_registry.get(b.name)
                    if bot_cls is None:
                        _send("error", {"message": f"Unknown bot '{b.name}'"})
                        has_error = True
                        break
                    try:
                        bot = bot_cls(**b.params)
                        bots_instances.append(bot)
                    except TypeError as e:
                        _send("error", {"message": f"Invalid params for {b.name}: {e}"})
                        has_error = True
                        break
                        
                if has_error:
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

                engine = StreamingEngine(cfg, on_event=_send, total=len(candles))
                # Run the synchronous engine in a worker thread so the WS
                # event loop stays responsive (and pings can fly through).
                bot_names = [b.name for b in req.bots]

                await asyncio.to_thread(
                    engine.run,
                    bots=bots_instances,
                    candles=candles,
                    symbol=req.symbol.upper(),
                    timeframe=req.timeframe,
                    indicator_specs=[{"name": i.name, **i.to_kwargs()} for i in req.indicators],
                    bot_names=bot_names,
                )

            elif action == "optimize":
                try:
                    req_opt = OptimizeRequest(**msg["config"])
                except Exception as exc:  # noqa: BLE001
                    _send("error", {"message": f"Bad config: {exc}"})
                    continue

                if req_opt.bot not in ctx.bot_registry:
                    _send("error", {"message": f"Unknown bot '{req_opt.bot}'"})
                    continue

                search_space: dict = {}
                for name, param in req_opt.search_space.items():
                    entry: dict = {
                        "type": param.type,
                        "low": param.low,
                        "high": param.high,
                    }
                    if param.step is not None:
                        entry["step"] = param.step
                    if param.log:
                        entry["log"] = True
                    if param.choices is not None:
                        entry["choices"] = param.choices
                    search_space[name] = entry

                from backtester.optimize.optuna_runner import run_optuna
                from backtester.optimize import Objective, OptimizationConfig

                opt_cfg = OptimizationConfig(
                    symbol=req_opt.symbol.upper(),
                    timeframe=req_opt.timeframe,
                    bot_class=req_opt.bot,
                    search_space=search_space,
                    objective=req_opt.objective,
                    fixed_params=req_opt.fixed_params,
                    initial_cash=req_opt.initial_cash,
                    taker_fee_pct=req_opt.taker_fee_pct,
                    slippage_pct=req_opt.slippage_pct,
                )
                objective = Objective(opt_cfg, ctx.downloader, ctx.bot_registry)

                def _on_trial(trial_number: int, result) -> None:
                    _send("trial_completed", {
                        "trial": trial_number,
                        "params": result.params,
                        "score": result.score,
                        "metrics": result.metrics,
                    })

                def _run_opt():
                    try:
                        results = run_optuna(
                            objective,
                            trials=req_opt.trials,
                            sampler=req_opt.sampler,
                            on_trial=_on_trial,
                        )
                        runs = [
                            {
                                "bot": req_opt.bot,
                                "params": r.params,
                                "success": True,
                                "metrics": r.metrics,
                                "score": r.score,
                                "error": None,
                            }
                            for r in results
                        ]
                        best = results[0] if results else None
                        _send("optimize_done", {
                            "runs": runs,
                            "best_params": best.params if best else {},
                            "best_score": best.score if best else 0,
                        })
                    except Exception as e:
                        _LOG.exception("Optuna WS failed")
                        _send("error", {"message": str(e)})

                await asyncio.to_thread(_run_opt)

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
