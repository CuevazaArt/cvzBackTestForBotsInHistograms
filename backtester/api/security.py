"""Authentication and audit helpers for API routes."""

from __future__ import annotations

import logging
from typing import Any

from fastapi import Header, HTTPException, Request, WebSocket

from backtester.api.config import ApiSettings

_AUDIT = logging.getLogger("backtester.audit")


def require_api_token(
    request: Request,
    x_api_key: str | None = Header(default=None),
) -> None:
    settings: ApiSettings | None = getattr(request.app.state, "settings", None)
    if settings is None:
        return
    if not settings.auth_enabled:
        return
    if x_api_key != settings.api_token:
        raise HTTPException(status_code=401, detail="Invalid API token")


def validate_ws_token(websocket: WebSocket) -> None:
    settings: ApiSettings | None = getattr(websocket.app.state, "settings", None)
    if settings is None:
        return
    if not settings.auth_enabled:
        return
    token = websocket.headers.get("x-api-key")
    if token != settings.api_token:
        raise HTTPException(status_code=401, detail="Invalid API token")


def audit_event(action: str, details: dict[str, Any]) -> None:
    """Emit structured audit logs for sensitive actions."""
    _AUDIT.info("%s | %s", action, details)
