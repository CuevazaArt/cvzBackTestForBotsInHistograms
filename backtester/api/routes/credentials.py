"""POST /credentials, GET /credentials/exists, DELETE /credentials"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from backtester.api.deps import AppContext, get_ctx
from backtester.api.schemas import CredentialsRequest, CredentialsStatus
from backtester.api.security import audit_event

router = APIRouter(tags=["credentials"])


@router.get("/credentials/exists", response_model=CredentialsStatus)
def credentials_exists(ctx: AppContext = Depends(get_ctx)) -> CredentialsStatus:
    return CredentialsStatus(exists=ctx.credentials.exists())


@router.post("/credentials", response_model=CredentialsStatus)
def save_credentials(
    req: CredentialsRequest, ctx: AppContext = Depends(get_ctx),
) -> CredentialsStatus:
    if not req.api_key.strip() or not req.api_secret.strip():
        raise HTTPException(400, "api_key and api_secret cannot be empty")
    ctx.credentials.save(req.api_key, req.api_secret)
    audit_event("credentials.saved", {"base_dir": str(ctx.base_dir)})
    return CredentialsStatus(exists=True)


@router.delete("/credentials", response_model=CredentialsStatus)
def delete_credentials(ctx: AppContext = Depends(get_ctx)) -> CredentialsStatus:
    ctx.credentials.delete()
    audit_event("credentials.deleted", {"base_dir": str(ctx.base_dir)})
    return CredentialsStatus(exists=False)
