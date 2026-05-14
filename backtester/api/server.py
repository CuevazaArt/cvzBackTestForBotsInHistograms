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

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from backtester.api.deps import AppContext
from backtester.api.routes import backtest, bots, candles, credentials, experiments
from backtester.api.ws import router as ws_router

_LOG = logging.getLogger("backtester.api.server")


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.ctx = AppContext.build()
    _LOG.info("AppContext initialized: %s", app.state.ctx.base_dir)
    yield


def create_app() -> FastAPI:
    app = FastAPI(title="Backtester API", version="0.1.0", lifespan=lifespan)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],  # local dev — Flutter desktop + browser
        allow_methods=["*"],
        allow_headers=["*"],
    )

    for r in (bots.router, candles.router, backtest.router,
              experiments.router, credentials.router):
        app.include_router(r, prefix="/api")
    app.include_router(ws_router)

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    # Static web (Lightweight Charts module). Created in Phase 3.
    web_dir = Path(__file__).resolve().parents[1] / "web"
    if web_dir.is_dir():
        app.mount("/static", StaticFiles(directory=str(web_dir), html=True), name="static")
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
