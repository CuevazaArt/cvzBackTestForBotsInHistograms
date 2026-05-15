"""FastAPI app factory + uvicorn entry point.

Run:
    uvicorn backtester.api.server:app --host 127.0.0.1 --port 8000 --reload
or:
    python -m backtester.api.server

Optional auth — set env var before starting:
    $env:BACKTESTER_API_TOKEN = "your-secret-token"
All /api/* routes and /ws require  Authorization: Bearer <token>
when the var is set.  /health and /static are always open.
"""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

from backtester.api.deps import AppContext
from backtester.api.routes import backtest, bots, candles, credentials, experiments
from backtester.api.ws import router as ws_router

_LOG = logging.getLogger("backtester.api.server")

# Paths exempt from token auth (WebSocket is protected differently — token
# can be passed as ?token=... query param since WS headers are browser-limited)
_OPEN_PREFIXES = ("/health", "/static", "/docs", "/openapi.json", "/redoc")


class _TokenAuth(BaseHTTPMiddleware):
    """Optional bearer-token guard for all /api/* routes.

    Activate by setting BACKTESTER_API_TOKEN env var.
    When not set the middleware is a no-op.
    """

    def __init__(self, app, token: str | None) -> None:
        super().__init__(app)
        self._token = token

    async def dispatch(self, request: Request, call_next):
        if self._token is None:
            return await call_next(request)

        path = request.url.path
        if any(path == p or path.startswith(p) for p in _OPEN_PREFIXES):
            return await call_next(request)

        # WebSocket upgrade: accept token via query param as fallback
        if request.headers.get("upgrade", "").lower() == "websocket":
            token_qs = request.query_params.get("token", "")
            if token_qs == self._token:
                return await call_next(request)
            return JSONResponse({"detail": "Unauthorized"}, status_code=401)

        auth = request.headers.get("Authorization", "")
        if auth.startswith("Bearer ") and auth[7:] == self._token:
            return await call_next(request)

        return JSONResponse({"detail": "Unauthorized"}, status_code=401)


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.ctx = AppContext.build()
    _LOG.info("AppContext initialized: %s", app.state.ctx.base_dir)
    yield


def create_app() -> FastAPI:
    app = FastAPI(title="Backtester API", version="0.1.0", lifespan=lifespan)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # Flutter Desktop + browser dev
        allow_methods=["*"],
        allow_headers=["*"],
    )

    api_token = os.environ.get("BACKTESTER_API_TOKEN")
    if api_token:
        app.add_middleware(_TokenAuth, token=api_token)
        _LOG.info("Token auth enabled (BACKTESTER_API_TOKEN is set)")
    else:
        _LOG.warning(
            "BACKTESTER_API_TOKEN not set — API is open. "
            "Set the env var if you expose beyond 127.0.0.1."
        )

    for r in (bots.router, candles.router, backtest.router,
              experiments.router, credentials.router):
        app.include_router(r, prefix="/api")
    app.include_router(ws_router)

    @app.get("/health", tags=["meta"])
    def health() -> dict[str, str]:
        return {"status": "ok"}

    web_dir = Path(__file__).resolve().parents[1] / "web"
    if web_dir.is_dir():
        app.mount("/static", StaticFiles(directory=str(web_dir), html=True), name="static")
    else:
        _LOG.warning("web/ not found — /static disabled. Run Phase 3 setup.")

    return app


app = create_app()


def main() -> None:
    import uvicorn
    logging.basicConfig(level=logging.INFO)
    uvicorn.run("backtester.api.server:app", host="127.0.0.1", port=8000, reload=False)


if __name__ == "__main__":
    main()
