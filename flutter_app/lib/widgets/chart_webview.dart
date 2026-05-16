import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

/// Public controller — pushes data into the chart from outside.
/// Methods are no-ops while the WebView is still initializing.
class ChartWebViewController {
  _ChartWebViewState? _state;

  void _attach(_ChartWebViewState s) => _state = s;
  void _detach() => _state = null;

  bool get isReady => _state?._jsReady ?? false;

  void addCandle(Map<String, dynamic> d)            => _state?._call('addCandle', d);
  void appendCandles(List<Map<String, dynamic>> d)  => _state?._call('appendCandles', d);
  void setCandles(List<Map<String, dynamic>> d)     => _state?._call('setCandles', d);
  void addTradeMarker(Map<String, dynamic> d)       => _state?._call('addTradeMarker', d);
  void addEquityPoint(Map<String, dynamic> d)       => _state?._call('addEquityPoint', d);
  void initIndicators(List<String> keys)            => _state?._call('initIndicators', keys);
  void initOscillators(List<String> keys)           => _state?._call('initOscillators', keys);
  void initBotSeries(List<String> botIds)           => _state?._call('initBotSeries', botIds);
  void clear()                                      => _state?._call('clearChart', const <String, dynamic>{});
  void forceResize()                                => _state?._call('forceResize', const <String, dynamic>{});

  void setChartFormula(String formula, {double? brickSize}) {
    if (_state == null || !isReady) return;
    final cfg = brickSize != null ? '{"brickSize": $brickSize}' : 'null';
    _state!._wv.executeScript(
      'if(window.setChartFormula) window.setChartFormula(${jsonEncode(formula)}, $cfg);',
    );
  }
}

/// WebView2-backed chart. Mounts the `Webview` widget immediately and overlays
/// a loading indicator until the chart JS bridge is ready, so the native COM
/// control has real on-screen dimensions from the first frame (avoids the
/// 0×0 first-render bug that prevented candles from drawing).
class ChartWebView extends StatefulWidget {
  final ChartWebViewController controller;
  final String chartUrl;
  final VoidCallback? onReady;
  const ChartWebView({
    super.key,
    required this.controller,
    required this.chartUrl,
    this.onReady,
  });

  @override
  State<ChartWebView> createState() => _ChartWebViewState();
}

class _ChartWebViewState extends State<ChartWebView> {
  final WebviewController _wv = WebviewController();

  bool _comReady = false;   // WebView2 COM control initialized
  bool _navDone  = false;   // navigation finished
  bool _jsReady  = false;   // window.__chartReady === true
  bool _failed   = false;
  bool _bootstrapRunning = false;
  String _status = 'Starting WebView2…';

  Timer? _watchdog;
  Timer? _readyPoller;
  StreamSubscription<LoadingState>? _loadSub;
  StreamSubscription<dynamic>? _msgSub;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (_bootstrapRunning) {
      debugPrint('[chart] _bootstrap re-entry blocked');
      return;
    }
    _bootstrapRunning = true;
    setState(() {
      _failed = false; _jsReady = false;
      _status = 'Starting WebView2 runtime…';
    });

    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 20), () {
      if (mounted && !_jsReady) {
        debugPrint('[chart] watchdog tripped — init >20s, marking failed');
        _probeForCrash();
        setState(() => _failed = true);
      }
    });

    try {
      // initialize() can only be called ONCE on a WebviewController — subsequent
      // calls throw "Stream has already been listened to". Skip if already done.
      if (!_wv.value.isInitialized) {
        await _wv.initialize();
      }
      if (!mounted) { _bootstrapRunning = false; return; }
      setState(() { _comReady = true; _status = 'Loading chart page…'; });

      // Primary readiness channel: JS posts 'chart-ready' via webMessage.
      _msgSub?.cancel();
      _msgSub = _wv.webMessage.listen((msg) {
        debugPrint('[chart] webMessage=$msg');
        if (msg == 'chart-ready' && mounted && !_jsReady) {
          _markReady('webMessage');
        }
      });

      _loadSub?.cancel();
      _loadSub = _wv.loadingState.listen((s) {
        debugPrint('[chart] loadingState=$s');
        if (s == LoadingState.navigationCompleted && mounted && !_navDone) {
          setState(() { _navDone = true; _status = 'Waiting for JS…'; });
          // Fallback: polling, in case the webMessage path fails.
          _startReadyPolling();
        }
      });

      await _wv.loadUrl(widget.chartUrl);
    } catch (e, st) {
      debugPrint('[chart] init error: $e\n$st');
      if (mounted) setState(() => _failed = true);
    } finally {
      _bootstrapRunning = false;
    }
  }

  Future<void> _probeForCrash() async {
    try {
      final err = await _wv.executeScript('window.__chartError || null');
      debugPrint('[chart] PROBE-CRASH __chartError=$err');
    } catch (e) {
      debugPrint('[chart] PROBE-CRASH probe error: $e');
    }
  }

  void _markReady(String via) {
    if (_jsReady || !mounted) return;
    _watchdog?.cancel();
    _readyPoller?.cancel();
    setState(() { _jsReady = true; _status = 'Ready'; });
    unawaited(_wv.executeScript('if(window.forceResize) window.forceResize();'));
    debugPrint('[chart] JS bridge ready via $via');
    widget.onReady?.call();
  }

  /// Fallback ready detection — polls `window.__chartReady === true` for ~10s
  /// after nav completes. Used only if the webMessage push never arrives.
  void _startReadyPolling() {
    _readyPoller?.cancel();
    var attempts = 0;

    // One-shot diagnostic dump so we can see what's really inside the WebView.
    () async {
      try {
        final probe = await _wv.executeScript(
          'JSON.stringify({lib: typeof LightweightCharts, ready: !!window.__chartReady, stage: window.__chartStage||"none", err: typeof window.__chartError, hasPost: !!(window.chrome&&window.chrome.webview&&window.chrome.webview.postMessage), scripts: document.getElementsByTagName("script").length})',
        );
        debugPrint('[chart] DIAG probe=$probe');
      } catch (e) {
        debugPrint('[chart] DIAG probe error: $e');
      }
    }();

    _readyPoller = Timer.periodic(const Duration(milliseconds: 300), (t) async {
      attempts++;
      if (!mounted || _jsReady) { t.cancel(); return; }
      try {
        final res = await _wv.executeScript('!!window.__chartReady');
        debugPrint('[chart] poll#$attempts result=$res (type=${res.runtimeType})');
        if (res == true && mounted && !_jsReady) {
          t.cancel();
          _markReady('poll/$attempts');
        }
      } catch (e) {
        debugPrint('[chart] poll error: $e');
      }
      if (attempts >= 30) { // ~9s
        t.cancel();
      }
    });
  }

  void _call(String fn, dynamic data) {
    if (!_jsReady) {
      debugPrint('[chart] _call($fn) skipped — JS not ready');
      return;
    }
    final json = jsonEncode(data);
    _wv.executeScript('if(window.$fn) window.$fn($json);');
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _readyPoller?.cancel();
    _loadSub?.cancel();
    _msgSub?.cancel();
    widget.controller._detach();
    _wv.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, _) {
      // Always render the Webview once the COM control is initialized — that
      // way it has real dimensions from the start. Overlay a status panel
      // until the JS bridge confirms readiness.
      return Stack(
        fit: StackFit.expand,
        children: [
          if (_comReady) Webview(_wv) else Container(color: const Color(0xFF131722)),
          if (!_jsReady && !_failed)
            Container(
              color: const Color(0xFF131722).withValues(alpha: 0.85),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(
                      color: Color(0xFF26a69a),
                      strokeWidth: 2.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(_status, style: const TextStyle(color: Color(0xFF787B86), fontSize: 11)),
                ],
              ),
            ),
          if (_failed)
            Container(
              color: const Color(0xFF131722),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 40),
                  const SizedBox(height: 10),
                  const Text(
                    'Chart engine failed to initialize.',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Backend on :8002 reachable? lightweight-charts vendored?',
                    style: TextStyle(color: Color(0xFF787B86), fontSize: 11),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _bootstrap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF26a69a),
                    ),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ],
              ),
            ),
        ],
      );
    });
  }
}
