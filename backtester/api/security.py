"""Authentication and audit helpers for API routes."""

from __future__ import annotations

import hmac
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
    # Constant-time compare to prevent timing-based token enumeration.
    provided = (x_api_key or "").encode()
    expected = settings.api_token.encode()
    if not hmac.compare_digest(provided, expected):
        raise HTTPException(status_code=401, detail="Invalid API token")


def validate_ws_token(websocket: WebSocket) -> None:
    settings: ApiSettings | None = getattr(websocket.app.state, "settings", None)
    if settings is None:
        return
    if not settings.auth_enabled:
        return
    token = (websocket.headers.get("x-api-key") or "").encode()
    expected = settings.api_token.encode()
    if not hmac.compare_digest(token, expected):
        raise HTTPException(status_code=401, detail="Invalid API token")


def audit_event(action: str, details: dict[str, Any]) -> None:
    """Emit structured audit logs for sensitive actions."""
    _AUDIT.info("%s | %s", action, details)
