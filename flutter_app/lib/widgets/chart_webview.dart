import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

/// Controls exposed to BacktestScreen
class ChartWebViewController {
  _ChartWebViewState? _state;

  void _attach(_ChartWebViewState s) => _state = s;
  void _detach() => _state = null;

  void addCandle(Map<String, dynamic> data) => _state?._callJs('addCandle', data);
  void addTradeMarker(Map<String, dynamic> data) => _state?._callJs('addTradeMarker', data);
  void addEquityPoint(Map<String, dynamic> data) => _state?._callJs('addEquityPoint', data);
  void clear() => _state?._callJs('clearChart', {});
  void setChartFormula(String formula, {double? brickSize}) {
    if (_state != null) {
      final configJs = brickSize != null ? '{"brickSize": $brickSize}' : 'null';
      _state!._wv.executeScript('if(window.setChartFormula) window.setChartFormula("$formula", $configJs);');
    }
  }
  void initIndicators(List<String> keys) => _state?._callJs('initIndicators', keys);
}

class ChartWebView extends StatefulWidget {
  final ChartWebViewController controller;
  const ChartWebView({super.key, required this.controller});

  @override
  State<ChartWebView> createState() => _ChartWebViewState();
}

class _ChartWebViewState extends State<ChartWebView> {
  late final WebviewController _wv = WebviewController();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    widget.controller._attach(this);
    _initWebview();
  }

  Future<void> _initWebview() async {
    await _wv.initialize();
    await _wv.loadUrl('http://127.0.0.1:8002/static/index.html');
    if (mounted) setState(() => _initialized = true);
  }

  void _callJs(String fn, dynamic data) {
    if (!_initialized) return;
    final json = jsonEncode(data);
    _wv.executeScript('if(window.$fn) window.$fn($json);');
  }

  @override
  void dispose() {
    widget.controller._detach();
    _wv.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
