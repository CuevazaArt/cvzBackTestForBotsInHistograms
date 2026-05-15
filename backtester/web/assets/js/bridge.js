/**
 * bridge.js — Two-way communication layer between Python/FastAPI WebSocket
 * and the LW Charts modules. Also exposes Flutter ↔ JS handlers when running
 * inside flutter_inappwebview.
 *
 * Public API:
 *   Bridge.log(msg)
 *   Bridge.connectWS(url)         → WebSocket (auto-dispatches events)
 *   Bridge.loadResult(result)     → populate all charts from a full result obj
 *   Bridge.reset()
 *
 * WebSocket events dispatched:
 *   candle   → MainChart.append(c)
 *   trade    → MainChart.marker(t)
 *   equity   → EquityChart.append(e)
 *   result   → Bridge.loadResult(r) (batch populate at end of run)
 *   progress → Bridge._onProgress(p)
 *   error    → Bridge._onError(e)
 */
(function () {
  "use strict";

  // ── Flutter interop (graceful degradation when running in browser) ────────
  const _flutterCall =
    window.flutter_inappwebview && window.flutter_inappwebview.callHandler
      ? (name, ...args) => window.flutter_inappwebview.callHandler(name, ...args)
      : (name, ...args) => Promise.resolve(console.debug("[bridge→flutter]", name, args));

  // ── Internal ──────────────────────────────────────────────────────────────
  let _ws = null;
  let _wsUrl = null;

  function _updateStatus(connected) {
    const dot = document.getElementById("ws-dot");
    const label = document.getElementById("ws-label");
    if (dot)   dot.className = "ws-dot" + (connected ? " connected" : "");
    if (label) label.textContent = connected ? "Connected" : "Disconnected";
  }

  function _onProgress(p) {
    const el = document.getElementById("progress-pct");
    if (el) el.textContent = Math.round(p.percent) + "%";
    _flutterCall("onProgress", p);
  }

  function _onError(e) {
    console.error("[ws]", e.message);
    _flutterCall("onError", e);
  }

  function _dispatch(msg) {
    switch (msg.type) {
      case "ready":    _updateStatus(true);              break;
      case "candle":   window.MainChart?.append(msg.data); break;
      case "trade":    window.MainChart?.marker(msg.data); break;
      case "equity":   window.EquityChart?.append(msg.data); break;
      case "result":   loadResult(msg.data);             break;
      case "progress": _onProgress(msg.data);            break;
      case "error":    _onError(msg.data);               break;
    }
  }

  // ── Public ────────────────────────────────────────────────────────────────

  function log(msg) {
    _flutterCall("flutter_log", msg);
  }

  /**
   * Open a WebSocket to the FastAPI /ws endpoint and start dispatching events.
   * Returns the WebSocket instance so the caller can send() on it.
   */
  function connectWS(url) {
    if (_ws && _ws.readyState <= 1) _ws.close();
    _wsUrl = url;
    _ws = new WebSocket(url);

    _ws.onopen = () => {
      _updateStatus(true);
      log("WS connected: " + url);
    };
    _ws.onmessage = (ev) => {
      try { _dispatch(JSON.parse(ev.data)); } catch (e) { console.error("[bridge] bad msg", e); }
    };
    _ws.onerror = (ev) => {
      _updateStatus(false);
      log("WS error");
    };
    _ws.onclose = () => {
      _updateStatus(false);
      log("WS closed");
    };

    return _ws;
  }

  /**
   * Populate all three charts from a complete BacktestResponse object.
   * Called after a sync HTTP run OR when a streaming run emits its final
   * "result" event.
   *
   * Expected shape:
   *   result.candles     [{time, open, high, low, close, volume}]
   *   result.trades      [{entry_time, exit_time, pnl, reason, ...}]
   *   result.equity_curve [{time, value}]
   *   result.summary     {total_return_pct, max_drawdown_pct, ...}
   */
  function loadResult(result) {
    reset();

    if (result.candles?.length)      window.MainChart?.setSeries(result.candles);
    if (result.trades?.length)       result.trades.forEach((t) => window.MainChart?.marker(t));
    if (result.equity_curve?.length) {
      window.EquityChart?.setSeries(result.equity_curve);
      window.DrawdownChart?.setSeries(result.equity_curve);
    }

    // Push summary stats to status bar
    const s = result.summary || {};
    _setStat("stat-return", s.total_return_pct, "%");
    _setStat("stat-mdd",    s.max_drawdown_pct, "%");
    _setStat("stat-trades", s.trades, "");
    _setStat("stat-wr",     s.win_rate_pct, "%");
    _setStat("stat-pf",     s.profit_factor, "x");

    _flutterCall("onResult", result);
  }

  function _setStat(id, val, suffix) {
    const el = document.getElementById(id);
    if (!el) return;
    if (val === null || val === undefined) { el.textContent = "—"; el.className = "val"; return; }
    const n = typeof val === "number" ? val : parseFloat(val);
    const text = isNaN(n) ? String(val) : (Math.abs(n) >= 100 ? n.toFixed(1) : n.toFixed(2)) + suffix;
    el.textContent = text;
    el.className = "val" + (n > 0 ? " pos" : n < 0 ? " neg" : "");
  }

  function reset() {
    window.MainChart?.reset();
    window.EquityChart?.reset();
    window.DrawdownChart?.reset();
  }

  // Called by Flutter when it sends a backtest config via evaluateJavascript
  window.runBacktest = function (configJson) {
    if (!_ws || _ws.readyState !== 1) {
      console.error("[bridge] WS not connected");
      return;
    }
    reset();
    _ws.send(JSON.stringify({ action: "backtest", config: configJson }));
  };

  window.Bridge = { log, connectWS, loadResult, reset, _onProgress, _onError };
  window.Bridge._ws = () => _ws;
})();
