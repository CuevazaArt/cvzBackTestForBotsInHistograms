"""FastAPI app factory + uvicorn entry point.

Run:
    uvicorn backtester.api.server:app --host 127.0.0.1 --port 8002 --reload
or:
    python -m backtester.api.server
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response

from backtester.api.config import load_api_settings
from backtester.api.deps import AppContext
from backtester.api.routes import (
    analysis,
    backtest,
    bots,
    candles,
    credentials,
    data,
    experiments,
    optimize,
    presets,
    results,
)
from backtester.api.security import require_api_token
from backtester.api.ws import router as ws_router

_LOG = logging.getLogger("backtester.api.server")


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.settings = load_api_settings()
    is_test = getattr(app.state, "is_test", False)
    app.state.ctx = AppContext.build(duckdb_read_only=is_test)
    _LOG.info(
        "AppContext initialized: %s | auth=%s",
        app.state.ctx.base_dir,
        "enabled" if app.state.settings.auth_enabled else "disabled",
    )
    yield


def create_app(is_test: bool = False) -> FastAPI:
    app = FastAPI(title="Backtester API", version="0.1.0", lifespan=lifespan)
    app.state.is_test = is_test

    settings = load_api_settings()
    allow_origins = ["*"] if settings.allow_all_cors else settings.cors_allow_origins
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allow_origins,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    for r in (
        bots.router,
        candles.router,
        backtest.router,
        experiments.router,
        credentials.router,
        data.router,
        optimize.router,
        presets.router,
        results.router,
        analysis.router,
    ):
        app.include_router(r, prefix="/api", dependencies=[Depends(require_api_token)])
    app.include_router(ws_router)

    @app.get("/health", dependencies=[Depends(require_api_token)])
    def health() -> dict[str, str | int]:
        from backtester.core.downloader import get_binance_used_weight_1m

        return {"status": "ok", "binance_weight_1m": get_binance_used_weight_1m()}

    # Static web (Lightweight Charts module). Created in Phase 3.
    web_dir = Path(__file__).resolve().parents[1] / "web"
    if web_dir.is_dir():
        # Prevent WebView2 from serving stale chart HTML / JS lib. The chart
        # bundle is small and changes frequently during development; aggressive
        # caching causes "addCandlestickSeries is not a function" when an old
        # lightweight-charts build lingers across reloads.
        class _NoCacheStatic(BaseHTTPMiddleware):
            async def dispatch(self, request: Request, call_next):  # type: ignore[override]
                response: Response = await call_next(request)
                if request.url.path.startswith("/static"):
                    response.headers["Cache-Control"] = "no-store, max-age=0"
                    response.headers["Pragma"] = "no-cache"
                    response.headers["Expires"] = "0"
                return response

        app.add_middleware(_NoCacheStatic)
        app.mount(
            "/static", StaticFiles(directory=str(web_dir), html=True), name="static"
        )
    else:
        _LOG.warning("web/ directory not found: %s — /static disabled", web_dir)

    return app


app = create_app()


def main() -> None:
    """Run uvicorn programmatically (used by `python -m backtester.api.server`)."""
    import uvicorn

    logging.basicConfig(level=logging.INFO)
    uvicorn.run("backtester.api.server:app", host="127.0.0.1", port=8002, reload=False)


if __name__ == "__main__":
    main()
