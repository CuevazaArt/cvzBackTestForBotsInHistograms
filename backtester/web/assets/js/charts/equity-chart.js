/**
 * EquityChart — Area line of portfolio equity over time.
 *
 * Exposed as window.EquityChart:
 *   EquityChart.init(containerId)
 *   EquityChart.setSeries(points)  // [{time, value}, ...]  time in ms
 *   EquityChart.append(point)      // single point (live streaming)
 *   EquityChart.reset()
 *   EquityChart.resize(w, h)
 */
(function () {
  "use strict";

  let _chart, _series;

  function _toTime(ms) {
    return Math.floor(ms / 1000);
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
      crosshair: { mode: LightweightCharts.CrosshairMode.Normal },
    });

    _series = _chart.addSeries(LightweightCharts.AreaSeries, {
      lineColor: "#2962ff",
      topColor: "#2962ff44",
      bottomColor: "#2962ff00",
      lineWidth: 2,
      priceLineVisible: false,
    });
  }

  function setSeries(points) {
    if (!_series) return;
    _series.setData(points.map((p) => ({ time: _toTime(p.time), value: p.value })));
    _chart.timeScale().fitContent();
  }

  function append(point) {
    if (!_series) return;
    _series.update({ time: _toTime(point.time), value: point.value });
  }

  function reset() {
    if (_series) _series.setData([]);
  }

  function resize(w, h) {
    if (_chart) _chart.resize(w, h);
  }

  window.EquityChart = { init, setSeries, append, reset, resize };
})();
