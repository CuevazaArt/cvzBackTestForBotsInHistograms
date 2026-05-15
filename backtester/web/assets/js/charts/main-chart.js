/**
 * MainChart — Candlestick + volume bars + trade markers.
 *
 * Exposed as window.MainChart:
 *   MainChart.init(containerId)
 *   MainChart.setSeries(candles)   // [{time,open,high,low,close,volume}, ...]
 *   MainChart.append(candle)       // single candle (live streaming)
 *   MainChart.marker(trade)        // {entry_time, exit_time, pnl, reason}
 *   MainChart.reset()
 *   MainChart.resize(w, h)
 */
(function () {
  "use strict";

  const GREEN = "#26a69a";
  const RED   = "#ef5350";
  const MUTED = "#787b86";

  let _chart, _candleSeries, _volSeries;
  const _markers = [];

  // Input is already epoch-seconds (API converts ms→s before sending).
  // LW Charts v5 expects seconds; no further division needed.
  function _toTime(s) {
    return Math.trunc(s);
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
        vertLines: { color: "#2a2e39" },
        horzLines: { color: "#2a2e39" },
      },
      crosshair: { mode: LightweightCharts.CrosshairMode.Normal },
      rightPriceScale: { borderColor: "#2a2e39" },
      timeScale: { borderColor: "#2a2e39", timeVisible: true },
      watermark: { visible: false },
    });

    _candleSeries = _chart.addSeries(LightweightCharts.CandlestickSeries, {
      upColor: GREEN,
      downColor: RED,
      borderUpColor: GREEN,
      borderDownColor: RED,
      wickUpColor: GREEN,
      wickDownColor: RED,
    });

    // Volume histogram on secondary scale
    _volSeries = _chart.addSeries(LightweightCharts.HistogramSeries, {
      priceFormat: { type: "volume" },
      priceScaleId: "vol",
    });
    _chart.priceScale("vol").applyOptions({
      scaleMargins: { top: 0.8, bottom: 0 },
    });
  }

  function setSeries(candles) {
    if (!_candleSeries) return;
    _markers.length = 0;

    const ohlcv = candles.map((c) => ({
      time: _toTime(c.time),
      open: c.open, high: c.high, low: c.low, close: c.close,
    }));
    const vol = candles.map((c) => ({
      time: _toTime(c.time),
      value: c.volume,
      color: c.close >= c.open ? GREEN + "88" : RED + "88",
    }));

    _candleSeries.setData(ohlcv);
    _volSeries.setData(vol);
    _chart.timeScale().fitContent();
  }

  function append(candle) {
    if (!_candleSeries) return;
    const t = _toTime(candle.time);
    _candleSeries.update({ time: t, open: candle.open, high: candle.high, low: candle.low, close: candle.close });
    _volSeries.update({
      time: t,
      value: candle.volume,
      color: candle.close >= candle.open ? GREEN + "88" : RED + "88",
    });
  }

  function marker(trade) {
    if (!_candleSeries) return;

    _markers.push({
      time: _toTime(trade.entry_time),
      position: "belowBar",
      color: "#2962ff",
      shape: "arrowUp",
      text: "B",
    });

    if (trade.exit_time) {
      _markers.push({
        time: _toTime(trade.exit_time),
        position: "aboveBar",
        color: trade.pnl >= 0 ? GREEN : RED,
        shape: "arrowDown",
        text: trade.pnl >= 0 ? `+${trade.pnl.toFixed(1)}` : trade.pnl.toFixed(1),
      });
    }

    // Sort markers by time (LW Charts requirement)
    _markers.sort((a, b) => a.time - b.time);
    _candleSeries.setMarkers(_markers);
  }

  function reset() {
    if (_candleSeries) { _candleSeries.setData([]); _candleSeries.setMarkers([]); }
    if (_volSeries)    _volSeries.setData([]);
    _markers.length = 0;
  }

  function resize(w, h) {
    if (_chart) _chart.resize(w, h);
  }

  window.MainChart = { init, setSeries, append, marker, reset, resize };
})();
