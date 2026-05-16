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
from uuid import uuid4

from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect

from backtester.api.schemas import BacktestRequest, OptimizeRequest
from backtester.api.security import validate_ws_token
from backtester.api.serialization import json_default, unique_bot_names
from backtester.core.engine import BacktestConfig, Candle
from backtester.core.run_control import RunController

_LOG = logging.getLogger("backtester.api.ws")

router = APIRouter()


@router.websocket("/ws")
async def ws_endpoint(websocket: WebSocket) -> None:
    try:
        validate_ws_token(websocket)
    except HTTPException:
        await websocket.close(code=1008)
        return
    await websocket.accept()
    ctx = websocket.app.state.ctx
    loop = asyncio.get_running_loop()

    def _send(event_type: str, data: dict | None = None) -> None:
        """Thread-safe send (callable from worker threads)."""
        payload = json.dumps(
            {"type": event_type, "data": data or {}},
            default=json_default,
        )
        asyncio.run_coroutine_threadsafe(websocket.send_text(payload), loop)

    _send("ready", {"version": "0.1.0"})

    # Server-initiated heartbeat: emits {"type": "ping"} every 30s so clients
    # can detect a half-open connection (no traffic, but socket still "open").
    async def _heartbeat() -> None:
        try:
            while True:
                await asyncio.sleep(30)
                _send("ping", {"ts": int(asyncio.get_event_loop().time() * 1000)})
        except asyncio.CancelledError:
            raise

    heartbeat_task = asyncio.create_task(_heartbeat())

    # Active RunController for the current backtest run (None when idle).
    active_controller: RunController | None = None
    # asyncio.Task wrapping the engine thread — kept so we can await it.
    _run_task: asyncio.Task | None = None  # type: ignore[type-arg]

    try:
        while True:
            msg = await websocket.receive_json()
            action = msg.get("action")

            if action in ("ping", "pong"):
                # Client liveness probe — reply with pong so the client can
                # cancel its dead-connection timer.
                _send("pong", {})

            elif action == "backtest":
                # Reject concurrent runs on the same socket.
                # NOTE: We check the asyncio task — not just the controller's
                # is_cancelled flag — because cancel() flips that flag instantly
                # while the engine thread keeps running until its next
                # wait_if_paused checkpoint. Allowing a new backtest in that
                # window would race two engine threads on the same WS sink
                # and let the older task's `finally` clobber the new
                # active_controller back to None.
                if _run_task is not None and not _run_task.done():
                    _send(
                        "error",
                        {
                            "message": (
                                "A backtest is already running on this connection. "
                                "Send 'cancel' first and wait for the 'cancelled' "
                                "event before starting a new run."
                            )
                        },
                    )
                    continue

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
                    req.symbol.upper(),
                    req.timeframe,
                    start_ms=req.start_ms,
                    end_ms=req.end_ms,
                )
                if not rows:
                    _send("error", {"message": "No candles in range"})
                    continue

                candles = [Candle.from_dict(r) for r in rows]
                cfg = BacktestConfig(
                    initial_cash=Decimal(str(req.initial_cash)),
                    taker_fee_pct=Decimal(str(req.taker_fee_pct)),
                    slippage_pct=Decimal(str(req.slippage_pct)),
                    fill_on_next_open=req.fill_on_next_open,
                )

                # Build controller — initial speed from payload or default 100 ms.
                # Accept ``speed_ms`` either at the top level of the message
                # (programmatic clients) or nested inside ``config`` (Flutter
                # client). BacktestRequest silently drops unknown fields, so we
                # have to read it from the raw msg before any consumption.
                _raw_speed = msg.get("speed_ms")
                if _raw_speed is None and isinstance(msg.get("config"), dict):
                    _raw_speed = msg["config"].get("speed_ms")
                speed_ms: int = (
                    int(_raw_speed)
                    if _raw_speed is not None
                    else RunController.DEFAULT_SPEED_MS
                )
                controller = RunController()
                controller.set_speed(speed_ms)
                active_controller = controller

                # Assign a stable run_id so the client can retrieve stored results.
                run_id = str(uuid4())
                _last_result: dict | None = None

                def _send_with_capture(
                    event_type: str, data: dict | None = None
                ) -> None:
                    nonlocal _last_result
                    if event_type == "result":
                        _last_result = data
                        # Attach run_id so the Flutter client can reference it.
                        data = {**(data or {}), "run_id": run_id}
                    _send(event_type, data)

                engine = StreamingEngine(
                    cfg,
                    on_event=_send_with_capture,
                    total=len(candles),
                    cache=ctx.indicator_cache,
                    controller=controller,
                )
                bot_names = unique_bot_names(req.bots)

                run_config = {
                    "symbol": req.symbol.upper(),
                    "timeframe": req.timeframe,
                    "bots": [{"name": b.name, "params": b.params} for b in req.bots],
                    "initial_cash": req.initial_cash,
                    "taker_fee_pct": req.taker_fee_pct,
                    "slippage_pct": req.slippage_pct,
                    "fill_on_next_open": req.fill_on_next_open,
                }

                async def _do_run() -> None:
                    nonlocal active_controller, _last_result
                    try:
                        await asyncio.to_thread(
                            engine.run,
                            bots=bots_instances,
                            candles=candles,
                            symbol=req.symbol.upper(),
                            timeframe=req.timeframe,
                            indicator_specs=[
                                {"name": i.name, **i.to_kwargs()}
                                for i in req.indicators
                            ],
                            bot_names=bot_names,
                        )
                        if _last_result is not None:
                            ctx.result_store.save(
                                run_id,
                                req.symbol.upper(),
                                req.timeframe,
                                run_config,
                                _last_result,
                            )
                    finally:
                        # Only clear if we still own the slot — a later run
                        # may have replaced us if the loop allowed it.
                        if active_controller is controller:
                            active_controller = None

                _run_task = asyncio.create_task(_do_run())

            # ── Transport controls ────────────────────────────────────────────

            elif action == "pause":
                if active_controller is None:
                    _send("error", {"message": "No active run to pause"})
                else:
                    active_controller.pause()
                    _send("paused", {})

            elif action == "resume":
                if active_controller is None:
                    _send("error", {"message": "No active run to resume"})
                else:
                    active_controller.resume()
                    _send("resumed", {})

            elif action == "step":
                if active_controller is None:
                    _send("error", {"message": "No active run to step"})
                else:
                    active_controller.step()
                    _send("paused", {})

            elif action == "set_speed":
                if active_controller is None:
                    _send("error", {"message": "No active run to set speed on"})
                else:
                    try:
                        speed_ms_val = int(msg["speed_ms"])
                    except (KeyError, ValueError, TypeError):
                        _send(
                            "error",
                            {"message": "set_speed requires integer field 'speed_ms'"},
                        )
                        continue
                    active_controller.set_speed(speed_ms_val)
                    _send("speed_changed", {"speed_ms": speed_ms_val})

            elif action == "cancel":
                if active_controller is None:
                    _send("error", {"message": "No active run to cancel"})
                else:
                    active_controller.cancel()
                    # 'cancelled' event is emitted by the engine loop itself;
                    # no echo needed here to avoid duplicate events.

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
                    validation_split_pct=req_opt.validation_split_pct,
                    min_trades=req_opt.min_trades,
                    max_drawdown_pct_limit=req_opt.max_drawdown_pct_limit,
                )
                objective = Objective(opt_cfg, ctx.downloader, ctx.bot_registry)

                def _on_trial(trial_number: int, result) -> None:
                    _send(
                        "trial_completed",
                        {
                            "trial": trial_number,
                            "params": result.params,
                            "score": result.score,
                            "metrics": result.metrics,
                        },
                    )

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
                        _send(
                            "optimize_done",
                            {
                                "runs": runs,
                                "best_params": best.params if best else {},
                                "best_score": best.score if best else 0,
                            },
                        )
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
    finally:
        # Cancel any in-flight run so the thread doesn't linger.
        if active_controller is not None:
            active_controller.cancel()
        if _run_task is not None and not _run_task.done():
            _run_task.cancel()
            try:
                await _run_task
            except (asyncio.CancelledError, Exception):  # noqa: BLE001
                pass
        heartbeat_task.cancel()
        try:
            await heartbeat_task
        except (asyncio.CancelledError, Exception):  # noqa: BLE001
            pass
