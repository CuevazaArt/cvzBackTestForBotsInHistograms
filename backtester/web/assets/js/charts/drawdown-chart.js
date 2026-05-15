/**
 * DrawdownChart — Histogram of running drawdown (always ≤ 0).
 *
 * Exposed as window.DrawdownChart:
 *   DrawdownChart.init(containerId)
 *   DrawdownChart.setSeries(points)  // [{time, value}, ...]  value in %  (negative)
 *   DrawdownChart.reset()
 *   DrawdownChart.resize(w, h)
 */
(function () {
  "use strict";

  let _chart, _series;

  // Input is already epoch-seconds (API converts ms→s before sending).
  function _toTime(s) {
    return Math.trunc(s);
  }

  /** Compute running drawdown pct from equity array. */
  function equityToDrawdown(equityPoints) {
    let peak = -Infinity;
    return equityPoints.map((p) => {
      if (p.value > peak) peak = p.value;
      const dd = peak > 0 ? ((p.value - peak) / peak) * 100 : 0;
      return { time: p.time, value: dd };
    });
  }

  function init(containerId) {
    const el = document.getElementById(containerId);
    if (!el) return;

    _chart = LightweightCharts.createChart(el, {
      layout: {
        background: { type: "solid", color: "#131722" },
        textColor: "#d1d4dc",
      },
      grid: {
        vertLines: { color: "#2a2e3944" },
        horzLines: { color: "#2a2e3944" },
      },
      rightPriceScale: { borderColor: "#2a2e39" },
      timeScale: { borderColor: "#2a2e39", timeVisible: true },
    });

    _series = _chart.addSeries(LightweightCharts.HistogramSeries, {
      color: "#ef535088",
      priceFormat: { type: "percent" },
    });
  }

  function setSeries(points) {
    if (!_series) return;
    const dd = equityToDrawdown(points);
    _series.setData(dd.map((p) => ({ time: _toTime(p.time), value: p.value })));
    _chart.timeScale().fitContent();
  }

  function reset() {
    if (_series) _series.setData([]);
  }

  function resize(w, h) {
    if (_chart) _chart.resize(w, h);
  }

  window.DrawdownChart = { init, setSeries, reset, resize, equityToDrawdown };
})();
