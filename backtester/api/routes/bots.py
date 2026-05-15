"""GET /bots — list all registered bots with their param specs."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from backtester.api.deps import AppContext, get_ctx
from backtester.api.schemas import BotInfo, BotParamsResponse, ParamSpec

router = APIRouter(tags=["bots"])


@router.get("/bots", response_model=list[BotInfo])
def list_bots(ctx: AppContext = Depends(get_ctx)) -> list[BotInfo]:
    """Return every registered bot with its description and full param spec.

    Clients get everything they need in a single call — no need to hit
    /bots/{name}/params separately.
    """
    out: list[BotInfo] = []
    for name, cls in ctx.bot_registry.items():
        description = (cls.__doc__ or "").strip().split("\n")[0]
        raw = cls.param_spec() if hasattr(cls, "param_spec") else {}
        params = {k: ParamSpec(**v) for k, v in raw.items()}
        out.append(BotInfo(name=name, description=description, params=params))
    return out


@router.get("/bots/{name}/params", response_model=BotParamsResponse)
def get_bot_params(name: str, ctx: AppContext = Depends(get_ctx)) -> BotParamsResponse:
    """Get param spec for a single bot (convenience endpoint)."""
    cls = ctx.bot_registry.get(name)
    if cls is None:
        raise HTTPException(404, f"Bot '{name}' not found")
    raw = cls.param_spec() if hasattr(cls, "param_spec") else {}
    return BotParamsResponse(name=name, params={k: ParamSpec(**v) for k, v in raw.items()})
