"""GET /bots, GET /bots/{name}/params"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from backtester.api.deps import AppContext, get_ctx
from backtester.api.schemas import BotInfo, BotParamsResponse, ParamSpec

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
