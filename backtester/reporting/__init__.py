"""HTML report generation for backtest results.

Public entry point: :func:`build_report` takes a result blob (the same shape
that :class:`~backtester.core.result_store.ResultStore` persists) and writes
or returns a self-contained HTML page with embedded charts. The page has no
external dependencies so it can be dropped into a chat or shared as a file.
"""

from backtester.reporting.html_report import build_report

__all__ = ["build_report"]
