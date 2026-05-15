"""FastAPI server exposing the backtester core to Flutter / web clients.

Run with:
    uvicorn backtester.api.server:app --host 127.0.0.1 --port 8000 --reload
"""

from backtester.api.server import create_app, app

__all__ = ["create_app", "app"]
