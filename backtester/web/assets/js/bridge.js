/**
 * bridge.js — Two-way communication layer between Python/FastAPI WebSocket
 * and the LW Charts modules.  Also exposes Flutter ↔ JS handlers when running
 * inside flutter_inappwebview.
 *
 * Public API:
 *   Bridge.connectWS(url)         → WebSocket (auto-dispatches events)
 *   Bridge.loadResult(result)     → populate all charts from a full result obj
 *   Bridge.reset()
 *   Bridge.log(msg)
 *
 * WebSocket events dispatched from server:
 *   ready    → update status indicator
 *   start    → reset charts, update topbar
 *   candle   → MainChart.append(c)
 *   trade    → MainChart.marker(t)
 *   equity   → EquityChart.append(e)
 *   progress → update progress bar
 *   result   → Bridge.loadResult(r)  (batch populate at end of run)
 *   error    → log + dispatch to Flutter
 *   pong     → silently ignored
 *
 * Shape expected by loadResult():
 *   result.candles      [{time(s), open, high, low, close, volume}]  (may be absent during streaming)
 *   result.trades       [{entry_time(s), exit_time(s)|null, pnl, reason, …}]
 *   result.equity_curve [{time(s), value}]
 *   result.summary      {total_return_pct, max_drawdown_pct, trades, win_rate_pct, profit_factor, …}
 */
(function () {
  "use strict";

  // ── Flutter interop (graceful degradation in plain browser) ──────────────
  const _flutter = window.flutter_inappwebview &&
    typeof window.flutter_inappwebview.callHandler === "function"
    ? (name, ...args) => window.flutter_inappwebview.callHandler(name, ...args)
    : (name, ...args) => Promise.resolve();

  // ── State ────────────────────────────────────────────────────────────────
  let _ws = null;

  // ── Internal helpers ─────────────────────────────────────────────────────

  function _setStatus(connected) {
    const dot   = document.getElementById("ws-dot");
    const label = document.getElementById("ws-label");
    if (dot)   dot.className  = "ws-dot" + (connected ? " connected" : "");
    if (label) label.textContent = connected ? "Connected" : "Disconnected";
  }

  function _setProgress(pct) {
    const el = document.getElementById("progress-pct");
    if (el) el.textContent = pct > 0 && pct < 100 ? Math.round(pct) + "%" : "";
  }

  /**
   * Update a status-bar stat chip.
   * @param {string} id   - element id
   * @param {number} val  - numeric value
   * @param {string} sfx  - suffix ("%", "x", "")
   * @param {boolean|null} positiveIsGood
   *   true  → green when val > 0
   *   false → always red (e.g. MDD, avg_loss)
   *   null  → neutral colour
   */
  function _setStat(id, val, sfx, positiveIsGood) {
    const el = document.getElementById(id);
    if (!el) return;
    if (val === null || val === undefined) {
      el.textContent = "—";
      el.className   = "val";
      return;
    }
    const n    = typeof val === "number" ? val : parseFloat(val);
    const abs  = Math.abs(n);
    const text = isNaN(n)
      ? String(val)
      : (abs >= 1000 ? n.toFixed(0) : abs >= 10 ? n.toFixed(1) : n.toFixed(2)) + sfx;

    let cls = "val";
    if (positiveIsGood === true)  cls += n > 0 ? " pos" : n < 0 ? " neg" : "";
    if (positiveIsGood === false) cls += " neg";   // always red (loss metric)
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
        // Clear charts at the beginning of a new streaming run
        reset();
        // Update topbar if present in the start event
        if (window.setTopbar && msg.data.symbol) {
          window.setTopbar(msg.data.symbol, msg.data.timeframe || "—", "—", "");
        }
        break;

      case "candle":
        window.MainChart?.append(msg.data);
        break;

      case "trade":
        window.MainChart?.marker(msg.data);
        break;

      case "equity":
        window.EquityChart?.append(msg.data);
        // Drawdown needs the running series, so we recompute lazily from equity chart
        // (full drawdown populates on final `result` event)
        break;

      case "result":
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

  /**
   * Open a WebSocket to /ws and start dispatching events.
   * @param {string} url - ws:// or wss:// URL
   * @returns {WebSocket}
   */
  function connectWS(url) {
    if (_ws && _ws.readyState <= 1) _ws.close();
    _ws = new WebSocket(url);
    _ws.onopen    = () => { _setStatus(true);  log("WS connected: " + url); };
    _ws.onmessage = (ev) => {
      try { _dispatch(JSON.parse(ev.data)); }
      catch (e) { console.error("[bridge] bad WS message", e, ev.data); }
    };
    _ws.onerror   = ()  => { _setStatus(false); log("WS error");  };
    _ws.onclose   = ()  => { _setStatus(false); log("WS closed"); };
    return _ws;
  }

  /**
   * Populate all three charts from a BacktestResponse object.
   *
   * Called:
   *  - From Flutter via evaluateJavascript("Bridge.loadResult(…)")  [HTTP path]
   *  - From dispatch() when WS sends the final "result" event       [WS path]
   *
   * The `candles` array may be absent in the WS streaming case
   * (they were already drawn vela-a-vela) — that's fine.
   */
  function loadResult(result) {
    // Only reset if this is a batch load (candles present),
    // not an incremental WS completion where chart already has live data.
    const isBatch = Array.isArray(result.candles) && result.candles.length > 0;
    if (isBatch) {
      reset();
      window.MainChart?.setSeries(result.candles);
    }

    if (Array.isArray(result.trades) && result.trades.length > 0) {
      result.trades.forEach((t) => window.MainChart?.marker(t));
    }

    if (Array.isArray(result.equity_curve) && result.equity_curve.length > 0) {
      window.EquityChart?.setSeries(result.equity_curve);
      window.DrawdownChart?.setSeries(result.equity_curve);
    }

    // Status-bar stats
    const s = result.summary || {};
    _setStat("stat-return", s.total_return_pct,  "%",  true);
    _setStat("stat-mdd",    -(s.max_drawdown_pct || 0), "%", true);  // negate: engine gives positive %
    _setStat("stat-trades", s.trades,             "",   null);
    _setStat("stat-wr",     s.win_rate_pct,       "%",  true);
    _setStat("stat-pf",     s.profit_factor,      "x",  true);

    _setProgress(0); // clear progress bar
  }

  function reset() {
    window.MainChart?.reset();
    window.EquityChart?.reset();
    window.DrawdownChart?.reset();
  }

  // Called by Flutter evaluateJavascript when it sends a backtest config via WS
  window.runBacktest = function (configJson) {
    if (!_ws || _ws.readyState !== 1) {
      console.error("[bridge] WS not open — cannot run backtest");
      return;
    }
    reset();
    _ws.send(JSON.stringify({ action: "backtest", config: configJson }));
  };

  window.Bridge = { connectWS, loadResult, reset, log };
  // Expose internal for debugging
  window.Bridge._ws = () => _ws;
})();
