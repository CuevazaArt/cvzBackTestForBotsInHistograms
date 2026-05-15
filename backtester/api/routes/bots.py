"""GET /bots, GET /bots/{name}/params, POST /bots/dsl/validate"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from backtester.api.deps import AppContext, get_ctx
from backtester.api.schemas import (
    BotInfo,
    BotParamsResponse,
    DSLValidateError,
    DSLValidateRequest,
    DSLValidateResponse,
    ParamSpec,
)
from backtester.bots.dsl import DSLParseError, parse_dsl

router = APIRouter(tags=["bots"])


@router.get("/bots", response_model=list[BotInfo])
def list_bots(ctx: AppContext = Depends(get_ctx)) -> list[BotInfo]:
    return [
        BotInfo(name=name, description=(cls.__doc__ or "").strip().split("\n")[0])
        for name, cls in ctx.bot_registry.items()
    ]


@router.get("/bots/{name}/params", response_model=BotParamsResponse)
def get_bot_params(name: str, ctx: AppContext = Depends(get_ctx)) -> BotParamsResponse:
    cls = ctx.bot_registry.get(name)
    if cls is None:
        raise HTTPException(404, f"Bot '{name}' not found")

    raw = cls.param_spec() if hasattr(cls, "param_spec") else {}
    params = {k: ParamSpec(**v) for k, v in raw.items()}
    return BotParamsResponse(name=name, params=params)


@router.post("/bots/dsl/validate", response_model=DSLValidateResponse)
def validate_dsl(req: DSLValidateRequest) -> DSLValidateResponse:
    """Validate a DSL document without running a backtest.

    Returns ``ok=true`` with a summary of the parsed indicators / risk
    block, or ``ok=false`` with a structured error (line, column, context)
    so the UI can highlight the offending part.
    """
    try:
        spec = parse_dsl(req.dsl_text)
    except DSLParseError as exc:
        return DSLValidateResponse(
            ok=False,
            error=DSLValidateError(
                message=str(exc),
                line=exc.line,
                column=exc.column,
                context=exc.context,
            ),
        )
    return DSLValidateResponse(
        ok=True,
        name=spec.name,
        indicators_used=spec.indicators_used(),
        has_entry_long=spec.entry_long is not None,
        has_exit_long=spec.exit_long is not None,
        stop_loss_pct=spec.stop_loss_pct,
        take_profit_pct=spec.take_profit_pct,
        size_pct=spec.size_pct,
    )
