/**
 * ChartReplay — Step-by-step OHLC candle playback controller.
 *
 * window.ChartReplay:
 *   load(candles, trades, equityCurve)   — load data (does not reset charts)
 *   play()                               — start / resume playback
 *   pause()                              — pause without resetting position
 *   stop()                               — pause + rewind to 0
 *   seek(index)                          — jump to candle index (redraws to that point)
 *   setSpeed(level)                      — 0 = Slow … 5 = Turbo
 *   _setSeeking(bool)                    — internal: suppress seekbar sync while dragging
 *   onTick   = null                      — (candle, idx, total) callback
 *   onDone   = null                      — () callback when last candle played
 *   SPEED_MS, SPEED_LABELS              — speed configuration arrays
 *   isPlaying, currentIndex, totalCandles (getters)
 */
(function () {
  "use strict";

  const SPEED_MS     = [1000, 400, 150, 50, 16, 4];
  const SPEED_LABELS = ["Slow", "0.5×", "1×", "2×", "4×", "Turbo"];

  let _candles   = [];
  let _trades    = [];
  let _eqMap     = new Map();   // time(s) → equity value
  let _idx       = 0;
  let _playing   = false;
  let _speedLvl  = 2;           // default 1× = 150 ms/candle
  let _timer     = null;
  let _rafId     = null;
  let _isSeeking = false;

  // ── Callbacks (set by index.html) ─────────────────────────────────────────
  const _pub = { onTick: null, onDone: null };

  // ── Helpers ───────────────────────────────────────────────────────────────

  function _clearTimer() {
    clearTimeout(_timer);
    cancelAnimationFrame(_rafId);
  }

  function _syncUI() {
    const seekbar  = document.getElementById("replay-seekbar");
    const counter  = document.getElementById("replay-counter");
    const playBtn  = document.getElementById("btn-replay-play");
    const pauseBtn = document.getElementById("btn-replay-pause");

    if (seekbar && !_isSeeking) {
      seekbar.max   = _candles.length;
      seekbar.value = _idx;
    }
    if (counter)  counter.textContent  = `${_idx} / ${_candles.length}`;
    if (playBtn)  playBtn.disabled     = _playing;
    if (pauseBtn) pauseBtn.disabled    = !_playing;
  }

  // ── Core loop ─────────────────────────────────────────────────────────────

  function _tick() {
    if (!_playing || _idx >= _candles.length) {
      _playing = false;
      _syncUI();
      if (_pub.onDone) _pub.onDone();
      return;
    }

    const c = _candles[_idx];

    window.MainChart?.append(c);

    const eqVal = _eqMap.get(c.time);
    if (eqVal !== undefined) {
      window.EquityChart?.append({ time: c.time, value: eqVal });
    }

    for (const t of _trades) {
      if (t.entry_time === c.time || t.exit_time === c.time) {
        window.MainChart?.marker(t);
      }
    }

    window.OverlayManager?.tick(_candles, _idx);

    if (_pub.onTick) _pub.onTick(c, _idx, _candles.length);

    _idx++;
    _syncUI();

    const ms = SPEED_MS[_speedLvl];
    if (ms <= 8) {
      _rafId = requestAnimationFrame(_tick);
    } else {
      _timer = setTimeout(_tick, ms);
    }
  }

  // ── Public API ────────────────────────────────────────────────────────────

  function load(candles, trades, equityCurve) {
    _clearTimer();
    _playing = false;
    _candles = candles || [];
    _trades  = trades  || [];
    _eqMap.clear();
    for (const p of (equityCurve || [])) _eqMap.set(p.time, p.value);
    _idx = 0;
    _syncUI();
  }

  function play() {
    if (_playing) return;
    if (_idx >= _candles.length) {
      // Auto-rewind
      _idx = 0;
      window.MainChart?.reset();
      window.EquityChart?.reset();
      window.DrawdownChart?.reset();
      window.OverlayManager?.resetData();
    }
    _playing = true;
    _syncUI();
    _tick();
  }

  function pause() {
    _playing = false;
    _clearTimer();
    _syncUI();
  }

  function stop() {
    _playing = false;
    _clearTimer();
    _idx = 0;
    _syncUI();
  }

  function seek(idx) {
    const wasPlaying = _playing;
    pause();
    _idx = Math.max(0, Math.min(idx, _candles.length));

    window.MainChart?.reset();
    window.EquityChart?.reset();
    window.DrawdownChart?.reset();
    window.OverlayManager?.resetData();

    if (_idx > 0) {
      const slice = _candles.slice(0, _idx);
      window.MainChart?.setSeries(slice);

      const eqSlice = [];
      for (const c of slice) {
        const v = _eqMap.get(c.time);
        if (v !== undefined) eqSlice.push({ time: c.time, value: v });
      }
      if (eqSlice.length) {
        window.EquityChart?.setSeries(eqSlice);
        window.DrawdownChart?.setSeries(eqSlice);
      }

      const lastTime = slice[slice.length - 1].time;
      for (const t of _trades) {
        if (t.entry_time <= lastTime) window.MainChart?.marker(t);
      }

      window.OverlayManager?.update(slice);
    }

    _syncUI();
    if (wasPlaying) play();
  }

  function setSpeed(level) {
    _speedLvl = Math.max(0, Math.min(level, SPEED_MS.length - 1));
  }

  Object.assign(_pub, {
    load, play, pause, stop, seek, setSpeed,
    SPEED_MS, SPEED_LABELS,
    get isPlaying()    { return _playing;        },
    get currentIndex() { return _idx;            },
    get totalCandles() { return _candles.length; },
    _setSeeking(v)     { _isSeeking = v;         },
  });

  window.ChartReplay = _pub;
})();
