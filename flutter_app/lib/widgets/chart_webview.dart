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
    });
    
    _initTimer?.cancel();
    _initTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_initialized) {
        setState(() => _timeout = true);
      }
    });

    try {
      if (!_wv.value.isInitialized) {
        await _wv.initialize();
      }
      await _wv.loadUrl(widget.chartUrl);
      if (mounted) {
        _initTimer?.cancel();
        setState(() => _initialized = true);
        widget.onReady?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _timeout = true);
      }
    }
  }

  void _callJs(String fn, dynamic data) {
    if (!_initialized) return;
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
            const Text('Chart took too long to load or crashed.', style: TextStyle(color: Colors.white, fontSize: 14)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _initWebview,
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF26a69a)),
              child: const Text('Retry'),
            )
          ],
        ),
      );
    }
    if (!_initialized) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF26a69a)),
            SizedBox(height: 12),
            Text('Loading chart…', style: TextStyle(color: Color(0xFF787B86), fontSize: 13)),
          ],
        ),
      );
    }
    return Webview(_wv);
  }
}
