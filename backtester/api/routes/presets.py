"""Bot preset management: save/load named param sets per strategy."""

from __future__ import annotations

from typing import Any, Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field

from backtester.api.deps import AppContext, get_ctx

router = APIRouter(tags=["presets"])


class PresetIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=64)
    bot_name: str = Field(..., min_length=1)
    params: dict[str, Any]
    description: Optional[str] = Field(None, max_length=500)


class PresetOut(BaseModel):
    name: str
    bot_name: str
    params: dict[str, Any]
    description: Optional[str] = None
    created_at: float
    updated_at: float


@router.get("/presets", response_model=list[PresetOut])
def list_presets(
    bot_name: Optional[str] = Query(None),
    ctx: AppContext = Depends(get_ctx),
) -> list[PresetOut]:
    return [PresetOut(**p) for p in ctx.presets.list_all(bot_name=bot_name)]


@router.get("/presets/{name}", response_model=PresetOut)
def get_preset(name: str, ctx: AppContext = Depends(get_ctx)) -> PresetOut:
    p = ctx.presets.get(name)
    if p is None:
        raise HTTPException(404, f"Preset '{name}' not found")
    return PresetOut(**p.to_dict())


@router.post("/presets", response_model=PresetOut)
def save_preset(
    req: PresetIn,
    ctx: AppContext = Depends(get_ctx),
) -> PresetOut:
    if req.bot_name not in ctx.bot_registry:
        raise HTTPException(422, f"Unknown bot '{req.bot_name}'")
    p = ctx.presets.upsert(
        name=req.name,
        bot_name=req.bot_name,
        params=req.params,
        description=req.description,
    )
    return PresetOut(**p.to_dict())


@router.delete("/presets/{name}")
def delete_preset(name: str, ctx: AppContext = Depends(get_ctx)) -> dict[str, bool]:
    if not ctx.presets.delete(name):
        raise HTTPException(404, f"Preset '{name}' not found")
    return {"deleted": True}
