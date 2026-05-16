import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

/// Controls exposed to BacktestScreen
class ChartWebViewController {
  _ChartWebViewState? _state;

  void _attach(_ChartWebViewState s) => _state = s;
  void _detach() => _state = null;

  void addCandle(Map<String, dynamic> data) => _state?._callJs('addCandle', data);
  void appendCandles(List<Map<String, dynamic>> data) => _state?._callJs('appendCandles', data);
  void setCandles(List<Map<String, dynamic>> data) => _state?._callJs('setCandles', data);
  void addTradeMarker(Map<String, dynamic> data) => _state?._callJs('addTradeMarker', data);
  void addEquityPoint(Map<String, dynamic> data) => _state?._callJs('addEquityPoint', data);
  void clear() => _state?._callJs('clearChart', {});
  void initIndicators(List<String> keys) => _state?._callJs('initIndicators', keys);
  void initOscillators(List<String> keys) => _state?._callJs('initOscillators', keys);
  void initBotSeries(List<String> botIds) => _state?._callJs('initBotSeries', botIds);
  bool get isReady => _state?._initialized ?? false;

  void setChartFormula(String formula, {double? brickSize}) {
    if (_state != null && isReady) {
      final configJs = brickSize != null ? '{"brickSize": $brickSize}' : 'null';
      _state!._wv.executeScript('if(window.setChartFormula) window.setChartFormula("$formula", $configJs);');
    }
  }
}

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
  late final WebviewController _wv = WebviewController();
  bool _initialized = false;
  bool _timeout = false;
  String _statusMsg = 'Initializing chart engine…';
  Timer? _initTimer;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    _initWebview();
  }

  Future<void> _initWebview() async {
    setState(() {
      _timeout = false;
      _initialized = false;
      _statusMsg = 'Initializing WebView2 engine…';
    });

    _initTimer?.cancel();
    _initTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && !_initialized) {
        debugPrint('ChartWebView: initialization timed out');
        setState(() => _timeout = true);
      }
    });

    try {
      // Step 1: Initialize WebView2 COM component
      if (!_wv.value.isInitialized) {
        if (mounted) setState(() => _statusMsg = 'Starting WebView2 runtime…');
        await _wv.initialize();
      }

      // Step 2: Subscribe to navigation events BEFORE loading
      if (mounted) setState(() => _statusMsg = 'Loading chart page…');
      final completer = Completer<void>();
      late final StreamSubscription sub;
      sub = _wv.loadingState.listen((state) {
        debugPrint('ChartWebView loadingState: $state');
        if (state == LoadingState.navigationCompleted && !completer.isCompleted) {
          completer.complete();
          sub.cancel();
        }
      });

      // Step 3: Load the chart URL
      await _wv.loadUrl(widget.chartUrl);

      // Step 4: Wait for navigation to complete, with a fallback timeout
      // The navigationCompleted event may not fire on cached pages, so we
      // add a 3-second fallback.
      if (mounted) setState(() => _statusMsg = 'Waiting for chart JS engine…');
      await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          debugPrint('ChartWebView: navigationCompleted timeout — using fallback');
          sub.cancel();
        },
      );

      // Step 5: Give the inline <script> a moment to execute
      await Future.delayed(const Duration(milliseconds: 200));

      if (mounted) {
        _initTimer?.cancel();
        setState(() {
          _initialized = true;
          _statusMsg = 'Chart ready';
        });
        debugPrint('ChartWebView: initialized — JS bridge ready');
        widget.onReady?.call();
      }
    } catch (e) {
      debugPrint('ChartWebView init error: $e');
      if (mounted) {
        setState(() => _timeout = true);
      }
    }
  }

  void _callJs(String fn, dynamic data) {
    if (!_initialized) {
      debugPrint('ChartWebView._callJs($fn): skipped — not initialized');
      return;
    }
    final json = jsonEncode(data);
    _wv.executeScript('if(window.$fn) window.$fn($json);');
  }

  @override
  void dispose() {
    _initTimer?.cancel();
    widget.controller._detach();
    _wv.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_timeout) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Chart engine failed to initialize.',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
            const SizedBox(height: 4),
            const Text(
              'Verify the backend is running and try again.',
              style: TextStyle(color: Color(0xFF787B86), fontSize: 11),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _initWebview,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF26a69a)),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (!_initialized) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                color: Color(0xFF26a69a),
                strokeWidth: 2.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _statusMsg,
              style: const TextStyle(color: Color(0xFF787B86), fontSize: 12),
            ),
          ],
        ),
      );
    }
    return Webview(_wv);
  }
}
