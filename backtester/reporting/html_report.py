"""Build a self-contained HTML report from a stored backtest result.

The report renders three sections:

1. **Header** — symbol, timeframe, bot + params, run timestamp.
2. **Metrics table** — return, drawdown, Sharpe, profit factor, etc.
3. **Equity curve chart** — drawn with Chart.js loaded from a CDN. Falls
   back to a static SVG placeholder when the curve is empty.
4. **Trades table** — paginated client-side via a tiny inline script.

Everything is rendered into a single ``<html>`` document so the user can
drag-and-drop the file into a browser or share it on chat. No external
files are produced.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from jinja2 import Environment, FileSystemLoader, select_autoescape


_TEMPLATES_DIR = Path(__file__).resolve().parent / "templates"


def _env() -> Environment:
    return Environment(
        loader=FileSystemLoader(str(_TEMPLATES_DIR)),
        autoescape=select_autoescape(["html"]),
        trim_blocks=True,
        lstrip_blocks=True,
    )


def _coerce_equity_series(result: dict[str, Any]) -> list[dict[str, float]]:
    """Best-effort extraction of {time, value} points from a result blob."""
    raw = result.get("equity_curve_downsampled") or result.get("equity_curve") or []
    out: list[dict[str, float]] = []
    for i, pt in enumerate(raw):
        if isinstance(pt, dict):
            t = pt.get("time", i)
            v = pt.get("value", pt.get("equity"))
            if v is None:
                continue
            out.append({"time": float(t), "value": float(v)})
        else:
            try:
                out.append({"time": float(i), "value": float(pt)})
            except (TypeError, ValueError):
                continue
    return out


def _coerce_trades(result: dict[str, Any]) -> list[dict[str, Any]]:
    raw = result.get("trades")
    if not isinstance(raw, list):
        return []
    out: list[dict[str, Any]] = []
    for t in raw:
        if not isinstance(t, dict):
            continue
        out.append(
            {
                "entry_time": t.get("entry_time"),
                "exit_time": t.get("exit_time"),
                "entry_price": t.get("entry_price"),
                "exit_price": t.get("exit_price"),
                "qty": t.get("qty"),
                "pnl": t.get("pnl"),
                "pnl_pct": t.get("pnl_pct"),
                "fee_usdt": t.get("fee_usdt"),
                "reason": t.get("reason"),
                "bot_id": t.get("bot_id"),
                "mfe_pct": t.get("mfe_pct"),
                "mae_pct": t.get("mae_pct"),
                "duration_bars": t.get("duration_bars"),
            }
        )
    return out


# Ordered list of metrics rendered in the summary table. Each tuple is
# (display label, key in result.summary, format, suffix).
_SUMMARY_FIELDS = [
    ("Total return", "total_return_pct", "{:.2f}", "%"),
    ("Final equity", "final_equity", "{:.2f}", ""),
    ("Max drawdown", "max_drawdown_pct", "{:.2f}", "%"),
    ("Win rate", "win_rate_pct", "{:.2f}", "%"),
    ("Profit factor", "profit_factor", "{:.3f}", ""),
    ("Trades", "trades", "{:.0f}", ""),
    ("Sharpe", "sharpe_ratio", "{:.3f}", ""),
    ("Sortino", "sortino_ratio", "{:.3f}", ""),
    ("Calmar", "calmar_ratio", "{:.3f}", ""),
    ("CAGR", "cagr_pct", "{:.2f}", "%"),
    ("Total fees", "total_fees_usdt", "{:.2f}", ""),
]


def _format_metric(value: Any, fmt: str, suffix: str) -> str:
    if value is None:
        return "—"
    try:
        return fmt.format(float(value)) + suffix
    except (TypeError, ValueError):
        return str(value)


def build_report(
    record: dict[str, Any],
    *,
    output_path: Path | str | None = None,
) -> str:
    """Render a stored backtest record as an HTML page.

    Parameters
    ----------
    record:
        Dict from :class:`backtester.core.result_store.ResultStore.get` or
        an equivalent shape: ``{run_id, symbol, timeframe, config, result,
        created_at}``.
    output_path:
        If provided, the HTML is also written to that path (parent dirs
        are created). The rendered string is always returned.
    """
    run_id = record.get("run_id") or "(unknown)"
    symbol = record.get("symbol", "")
    timeframe = record.get("timeframe", "")
    config = record.get("config") or {}
    result = record.get("result") or {}
    created_at = record.get("created_at")

    summary = result.get("summary") or {}
    metrics_rows = []
    for label, key, fmt, suffix in _SUMMARY_FIELDS:
        value = summary.get(key)
        if value is None and key in ("trades", "max_drawdown_pct", "final_equity"):
            value = result.get(key)
        metrics_rows.append(
            {
                "label": label,
                "value": _format_metric(value, fmt, suffix),
                "raw": value,
            }
        )

    equity_points = _coerce_equity_series(result)
    trades = _coerce_trades(result)
    bots = config.get("bots") or []

    created_text = ""
    if created_at:
        try:
            created_text = datetime.fromtimestamp(
                float(created_at), tz=timezone.utc
            ).strftime("%Y-%m-%d %H:%M UTC")
        except (TypeError, ValueError):
            created_text = str(created_at)

    template = _env().get_template("report.html")
    html = template.render(
        run_id=run_id,
        symbol=symbol,
        timeframe=timeframe,
        created_text=created_text,
        bots=bots,
        config=config,
        metrics_rows=metrics_rows,
        equity_json=json.dumps(equity_points),
        trades=trades,
        trades_json=json.dumps(trades),
        has_equity=bool(equity_points),
    )
    if output_path is not None:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(html, encoding="utf-8")
    return html


def build_report_from_engine_result(
    backtest_result: Any,
    *,
    symbol: str,
    timeframe: str,
    config: Optional[dict[str, Any]] = None,
    output_path: Path | str | None = None,
) -> str:
    """Convenience wrapper for the SDK: feed a :class:`BacktestResult`.

    Useful from notebooks / scripts where the user just ran ``engine.run``
    and wants to share an HTML report without going through the API.
    """
    equity = [
        {"time": i, "value": float(v)}
        for i, v in enumerate(backtest_result.equity_curve)
    ]
    trades = [
        {
            "entry_time": t.entry_time,
            "exit_time": t.exit_time,
            "entry_price": float(t.entry_price),
            "exit_price": float(t.exit_price),
            "qty": float(t.qty),
            "pnl": float(t.pnl),
            "pnl_pct": float(t.pnl_pct),
            "fee_usdt": float(t.fee_usdt),
            "reason": t.reason,
            "bot_id": t.bot_id,
            "mfe_pct": float(t.mfe_pct),
            "mae_pct": float(t.mae_pct),
            "duration_bars": t.duration_bars,
        }
        for t in backtest_result.trades
    ]
    record = {
        "run_id": "sdk-export",
        "symbol": symbol,
        "timeframe": timeframe,
        "config": config or {},
        "created_at": datetime.now(tz=timezone.utc).timestamp(),
        "result": {
            "summary": backtest_result.summary(),
            "equity_curve_downsampled": equity,
            "trades": trades,
            "final_equity": float(backtest_result.final_equity),
            "max_drawdown_pct": float(backtest_result.max_drawdown_pct),
        },
    }
    return build_report(record, output_path=output_path)
