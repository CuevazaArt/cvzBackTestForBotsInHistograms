/**
 * OverlayManager — Pluggable indicator overlays.
 *
 * Price overlays (EMA, SMA, BB) add LineSeries to MainChart.
 * RSI uses a dedicated #rsi-chart panel (display:none by default).
 *
 * window.OverlayManager:
 *   register(factoryName, factory)        — factory(options) → compute(candles) → result
 *   add(name, factoryName, options)       — add("ema20", "ema", {period:20})
 *   remove(name)
 *   clear()
 *   resetData()                           — clear series data without removing series
 *   update(candles)                       — recompute all active overlays
 *   tick(candles, upToIdx)               — called during replay (throttled)
 *   resize(w, h)                          — resize RSI chart
 */
(function () {
  "use strict";

  // ── Math helpers ──────────────────────────────────────────────────────────

  function _ema(vals, period) {
    const k   = 2 / (period + 1);
    const out = new Array(vals.length).fill(null);
    if (vals.length < period) return out;
    let seed = 0;
    for (let i = 0; i < period; i++) seed += vals[i];
    let prev = seed / period;
    out[period - 1] = prev;
    for (let i = period; i < vals.length; i++) {
      prev   = vals[i] * k + prev * (1 - k);
      out[i] = prev;
    }
    return out;
  }

  function _sma(vals, period) {
    return vals.map((_, i) => {
      if (i < period - 1) return null;
      let s = 0;
      for (let j = i - period + 1; j <= i; j++) s += vals[j];
      return s / period;
    });
  }

  function _stddev(vals, period) {
    return vals.map((_, i) => {
      if (i < period - 1) return null;
      let s = 0, ss = 0;
      for (let j = i - period + 1; j <= i; j++) { s += vals[j]; ss += vals[j] * vals[j]; }
      const mean = s / period;
      return Math.sqrt(Math.max(0, ss / period - mean * mean));
    });
  }

  function _rsi(vals, period) {
    if (vals.length <= period) return new Array(vals.length).fill(null);
    const out = new Array(vals.length).fill(null);
    let ag = 0, al = 0;
    for (let i = 1; i <= period; i++) {
      const d = vals[i] - vals[i - 1];
      if (d > 0) ag += d; else al -= d;
    }
    ag /= period; al /= period;
    out[period] = al === 0 ? 100 : 100 - 100 / (1 + ag / al);
    for (let i = period + 1; i < vals.length; i++) {
      const d = vals[i] - vals[i - 1];
      ag = (ag * (period - 1) + Math.max(0,  d)) / period;
      al = (al * (period - 1) + Math.max(0, -d)) / period;
      out[i] = al === 0 ? 100 : 100 - 100 / (1 + ag / al);
    }
    return out;
  }

  // ── Built-in overlay factories ─────────────────────────────────────────────
  // factory(options) → compute(candles) → { series: [...], subplot: bool }
  // series item: { id, type ("Line"), options: LWChartSeriesOptions, data: [{time,value}] }

  const _builtins = {
    ema({ period = 20, color = "#f7cc58" } = {}) {
      return (candles) => {
        const vals = _ema(candles.map((c) => c.close), period);
        return {
          series: [{
            id:      `ema-${period}`,
            type:    "Line",
            options: { color, lineWidth: 1, priceLineVisible: false, lastValueVisible: false },
            data:    candles
              .map((c, i) => vals[i] !== null ? { time: c.time, value: vals[i] } : null)
              .filter(Boolean),
          }],
          subplot: false,
        };
      };
    },

    sma({ period = 20, color = "#4caf50" } = {}) {
      return (candles) => {
        const vals = _sma(candles.map((c) => c.close), period);
        return {
          series: [{
            id:      `sma-${period}`,
            type:    "Line",
            options: { color, lineWidth: 1, priceLineVisible: false, lastValueVisible: false },
            data:    candles
              .map((c, i) => vals[i] !== null ? { time: c.time, value: vals[i] } : null)
              .filter(Boolean),
          }],
          subplot: false,
        };
      };
    },

    bb({ period = 20, stddevs = 2, color = "#9b59b6" } = {}) {
      return (candles) => {
        const closes = candles.map((c) => c.close);
        const mid    = _sma(closes, period);
        const sd     = _stddev(closes, period);
        const mk = (id, fn, lineStyle) => ({
          id,
          type:    "Line",
          options: { color, lineWidth: 1, lineStyle, priceLineVisible: false, lastValueVisible: false },
          data: candles
            .map((c, i) => { const v = fn(i); return v !== null ? { time: c.time, value: v } : null; })
            .filter(Boolean),
        });
        return {
          series: [
            mk("bb-upper", (i) => mid[i] !== null ? mid[i] + stddevs * sd[i] : null, 2),
            mk("bb-mid",   (i) => mid[i],                                              0),
            mk("bb-lower", (i) => mid[i] !== null ? mid[i] - stddevs * sd[i] : null, 2),
          ],
          subplot: false,
        };
      };
    },

    rsi({ period = 14, color = "#e91e63" } = {}) {
      return (candles) => {
        const vals = _rsi(candles.map((c) => c.close), period);
        return {
          series: [{
            id:      "rsi",
            type:    "Line",
            options: { color, lineWidth: 1, priceLineVisible: false, lastValueVisible: true },
            data:    candles
              .map((c, i) => vals[i] !== null ? { time: c.time, value: vals[i] } : null)
              .filter(Boolean),
          }],
          subplot: true,
        };
      };
    },
  };

  // ── OverlayManager state ───────────────────────────────────────────────────

  const _registry = new Map(Object.entries(_builtins));
  // active: name → { compute, factoryName, lwSeries: Map<id, LW series> }
  const _active   = new Map();

  let _rsiChart  = null;
  let _rsiSeries = null;

  function _mainChart() {
    return window.MainChart?.getChart?.();
  }

  function _ensureRsiChart() {
    if (_rsiChart) return;
    const el       = document.getElementById("rsi-chart");
    const chartsEl = document.getElementById("charts");
    if (!el) return;
    if (chartsEl) chartsEl.classList.add("rsi-visible");

    _rsiChart = LightweightCharts.createChart(el, {
      layout: {
        background: { type: "solid", color: "#131722" },
        textColor:  "#d1d4dc",
      },
      grid: {
        vertLines: { color: "#2a2e3944" },
        horzLines: { color: "#2a2e3944" },
      },
      rightPriceScale: { borderColor: "#2a2e39", scaleMargins: { top: 0.1, bottom: 0.1 } },
      timeScale:       { borderColor: "#2a2e39", visible: false },
      handleScale:     false,
      watermark:       { visible: false },
    });

    _rsiSeries = _rsiChart.addSeries(LightweightCharts.LineSeries, {
      color: "#e91e63",
      lineWidth: 1,
      priceLineVisible: false,
      autoscaleInfoProvider: () => ({ priceRange: { minValue: 0, maxValue: 100 } }),
    });
    _rsiSeries.createPriceLine({ price: 70, color: "#ef535066", lineWidth: 1, lineStyle: 2, axisLabelVisible: false });
    _rsiSeries.createPriceLine({ price: 30, color: "#26a69a66", lineWidth: 1, lineStyle: 2, axisLabelVisible: false });

    // Sync RSI time scale with main chart
    const mc = _mainChart();
    if (mc) {
      let _lock = false;
      mc.timeScale().subscribeVisibleLogicalRangeChange((r) => {
        if (_lock || !r) return;
        _lock = true;
        _rsiChart.timeScale().setVisibleLogicalRange(r);
        _lock = false;
      });
      _rsiChart.timeScale().subscribeVisibleLogicalRangeChange((r) => {
        if (_lock || !r) return;
        _lock = true;
        mc.timeScale().setVisibleLogicalRange(r);
        _lock = false;
      });
    }
  }

  function _hideRsiPanel() {
    const chartsEl = document.getElementById("charts");
    if (chartsEl) chartsEl.classList.remove("rsi-visible");
  }

  // ── Public API ────────────────────────────────────────────────────────────

  function register(factoryName, factory) {
    _registry.set(factoryName, factory);
  }

  function add(name, factoryName, options = {}) {
    if (_active.has(name)) remove(name);
    const factory = _registry.get(factoryName);
    if (!factory) { console.warn(`[overlays] unknown factory: ${factoryName}`); return; }
    _active.set(name, { compute: factory(options), factoryName, lwSeries: new Map() });
  }

  function remove(name) {
    const entry = _active.get(name);
    if (!entry) return;
    const mc = _mainChart();
    entry.lwSeries.forEach((s) => {
      try { if (mc)        mc.removeSeries(s);        } catch (_) {}
      try { if (_rsiChart) _rsiChart.removeSeries(s); } catch (_) {}
    });
    _active.delete(name);
    const hasRsi = [..._active.values()].some((e) => e.factoryName === "rsi");
    if (!hasRsi) _hideRsiPanel();
  }

  function clear() {
    [..._active.keys()].forEach(remove);
  }

  /** Clear series data without removing series objects (used on replay rewind). */
  function resetData() {
    const mc = _mainChart();
    _active.forEach((entry) => {
      entry.lwSeries.forEach((s) => {
        try { s.setData([]); } catch (_) {}
      });
    });
    if (_rsiSeries) { try { _rsiSeries.setData([]); } catch (_) {} }
  }

  function update(candles) {
    if (!candles || candles.length === 0) return;
    const mc = _mainChart();
    _active.forEach((entry) => {
      const result = entry.compute(candles);
      for (const s of result.series) {
        if (result.subplot) {
          _ensureRsiChart();
          if (_rsiSeries) {
            _rsiSeries.setData(s.data);
            _rsiChart.timeScale().fitContent();
          }
        } else {
          if (!mc) continue;
          let lws = entry.lwSeries.get(s.id);
          if (!lws) {
            const Ctor = LightweightCharts[s.type + "Series"];
            if (!Ctor) continue;
            lws = mc.addSeries(Ctor, s.options);
            entry.lwSeries.set(s.id, lws);
          }
          lws.setData(s.data);
        }
      }
    });
  }

  /** Throttled update for replay: recompute on first, last, and every 5th candle. */
  function tick(candles, upToIdx) {
    if (_active.size === 0) return;
    const n = upToIdx + 1;
    if (n === 1 || n === candles.length || n % 5 === 0) {
      update(candles.slice(0, n));
    }
  }

  function resize(w, h) {
    if (_rsiChart) _rsiChart.resize(w, h);
  }

  window.OverlayManager = { register, add, remove, clear, resetData, update, tick, resize };
})();
