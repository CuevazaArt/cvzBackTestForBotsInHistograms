/**
 * bridge.js — Two-way communication layer between Python/FastAPI WebSocket
 * and the LW Charts modules.  Also exposes Flutter ↔ JS handlers when running
 * inside flutter_inappwebview.
 *
 * Public API:
 *   Bridge.connectWS(url)       → WebSocket (auto-dispatches events)
 *   Bridge.loadResult(result)   → populate all charts from a full result obj
 *   Bridge.reset()
 *   Bridge.log(msg)
 *   Bridge.getCandles()         → current candle array (for overlays / replay)
 *   Bridge.getTrades()          → current trades array
 *   Bridge.getEquity()          → current equity_curve array
 *
 * WebSocket events dispatched from server:
 *   ready    → update status indicator
 *   start    → reset charts
 *   candle   → MainChart.append + accumulate
 *   trade    → MainChart.marker + accumulate
 *   equity   → EquityChart.append + accumulate
 *   progress → update progress bar
 *   result   → Bridge.loadResult + load replay
 *   error    → log + dispatch to Flutter
 *   pong     → silently ignored
 */
(function () {
  "use strict";

  // ── Flutter interop (graceful degradation in plain browser) ──────────────
  const _flutter = window.flutter_inappwebview &&
    typeof window.flutter_inappwebview.callHandler === "function"
    ? (name, ...args) => window.flutter_inappwebview.callHandler(name, ...args)
    : () => Promise.resolve();

  // ── State ─────────────────────────────────────────────────────────────────
  let _ws      = null;
  let _candles = [];
  let _trades  = [];
  let _equity  = [];

  // ── Internal helpers ──────────────────────────────────────────────────────

  function _setStatus(connected) {
    const dot   = document.getElementById("ws-dot");
    const label = document.getElementById("ws-label");
    if (dot)   dot.className    = "ws-dot" + (connected ? " connected" : "");
    if (label) label.textContent = connected ? "Connected" : "Disconnected";
  }

  function _setProgress(pct) {
    const el = document.getElementById("progress-pct");
    if (el) el.textContent = pct > 0 && pct < 100 ? Math.round(pct) + "%" : "";
  }

  function _setStat(id, val, sfx, positiveIsGood) {
    const el = document.getElementById(id);
    if (!el) return;
    if (val === null || val === undefined) {
      el.textContent = "—"; el.className = "val"; return;
    }
    const n   = typeof val === "number" ? val : parseFloat(val);
    const abs = Math.abs(n);
    const text = isNaN(n)
      ? String(val)
      : (abs >= 1000 ? n.toFixed(0) : abs >= 10 ? n.toFixed(1) : n.toFixed(2)) + sfx;
    let cls = "val";
    if (positiveIsGood === true)  cls += n > 0 ? " pos" : n < 0 ? " neg" : "";
    if (positiveIsGood === false) cls += " neg";
    el.textContent = text;
    el.className   = cls;
  }

  function _dispatch(msg) {
    switch (msg.type) {
      case "ready":
        _setStatus(true);
        _flutter("onReady", msg.data);
        break;

      case "start":
        reset();
        if (window.setTopbar && msg.data && msg.data.symbol) {
          window.setTopbar(msg.data.symbol, msg.data.timeframe || "—", "—", "");
        }
        break;

      case "candle":
        _candles.push(msg.data);
        window.MainChart?.append(msg.data);
        break;

      case "trade":
        _trades.push(msg.data);
        window.MainChart?.marker(msg.data);
        break;

      case "equity":
        _equity.push(msg.data);
        window.EquityChart?.append(msg.data);
        break;

      case "result":
        // WS streaming complete — load replay with accumulated data, then populate stats.
        window.ChartReplay?.load(_candles, _trades, _equity);
        window.OverlayManager?.update(_candles);
        loadResult(msg.data);
        _flutter("onResult", msg.data);
        break;

      case "progress":
        _setProgress(msg.data.percent ?? 0);
        _flutter("onProgress", msg.data);
        break;

      case "error":
        console.error("[ws error]", msg.data.message);
        _flutter("onError", msg.data);
        break;

      case "pong":
        break;

      default:
        console.debug("[ws unknown]", msg.type, msg.data);
    }
  }

  // ── Public ────────────────────────────────────────────────────────────────

  function log(msg) {
    _flutter("flutter_log", String(msg));
  }

  function connectWS(url) {
    if (_ws && _ws.readyState <= 1) _ws.close();
    _ws = new WebSocket(url);
    _ws.onopen    = () => { _setStatus(true);  log("WS connected: " + url); };
    _ws.onmessage = (ev) => {
      try { _dispatch(JSON.parse(ev.data)); }
      catch (e) { console.error("[bridge] bad WS message", e, ev.data); }
    };
    _ws.onerror   = () => { _setStatus(false); log("WS error");  };
    _ws.onclose   = () => { _setStatus(false); log("WS closed"); };
    return _ws;
  }

  /**
   * Populate all charts from a BacktestResponse object.
   * Called from Flutter evaluateJavascript (HTTP path) or from _dispatch "result" (WS path).
   * On the WS path, candles/trades/equity were already drawn live and accumulated in _candles etc.;
   * isBatch will be false (candles absent from the result event) so we skip setSeries.
   */
  function loadResult(result) {
    const isBatch = Array.isArray(result.candles) && result.candles.length > 0;
    if (isBatch) {
      reset();
      _candles = result.candles;
      window.MainChart?.setSeries(result.candles);
    }

    if (Array.isArray(result.trades) && result.trades.length > 0) {
      if (isBatch) _trades = result.trades;
      result.trades.forEach((t) => window.MainChart?.marker(t));
    }

    if (Array.isArray(result.equity_curve) && result.equity_curve.length > 0) {
      if (isBatch) _equity = result.equity_curve;
      window.EquityChart?.setSeries(result.equity_curve);
      window.DrawdownChart?.setSeries(result.equity_curve);
    }

    // Load replay and overlays when we have a full dataset
    if (isBatch) {
      window.ChartReplay?.load(_candles, _trades, _equity);
      window.OverlayManager?.update(_candles);
    }

    const s = result.summary || {};
    _setStat("stat-return", s.total_return_pct,         "%",  true);
    _setStat("stat-mdd",    -(s.max_drawdown_pct || 0), "%",  true);
    _setStat("stat-trades", s.trades,                   "",   null);
    _setStat("stat-wr",     s.win_rate_pct,             "%",  true);
    _setStat("stat-pf",     s.profit_factor,            "x",  true);

    _setProgress(0);
  }

  function reset() {
    _candles = []; _trades = []; _equity = [];
    window.MainChart?.reset();
    window.EquityChart?.reset();
    window.DrawdownChart?.reset();
  }

  // Called by Flutter evaluateJavascript to trigger a WS backtest run
  window.runBacktest = function (configJson) {
    if (!_ws || _ws.readyState !== 1) {
      console.error("[bridge] WS not open — cannot run backtest");
      return;
    }
    reset();
    _ws.send(JSON.stringify({ action: "backtest", config: configJson }));
  };

  window.Bridge = {
    connectWS,
    loadResult,
    reset,
    log,
    getCandles: () => _candles,
    getTrades:  () => _trades,
    getEquity:  () => _equity,
    _ws: () => _ws,
  };
})();
