import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/backtest_result.dart';

class ChartWebView extends StatefulWidget {
  const ChartWebView({super.key});

  @override
  State<ChartWebView> createState() => ChartWebViewState();
}

class ChartWebViewState extends State<ChartWebView> {
  InAppWebViewController? _ctrl;
  bool _ready = false;

  static const _chartUrl = 'http://127.0.0.1:8000/static/index.html';

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(_chartUrl)),
          initialSettings: InAppWebViewSettings(
            transparentBackground: true,
            javaScriptEnabled: true,
            disableHorizontalScroll: true,
            disableVerticalScroll: true,
          ),
          onWebViewCreated: (ctrl) {
            _ctrl = ctrl;

            ctrl.addJavaScriptHandler(
              handlerName: 'flutter_log',
              callback: (args) {
                debugPrint('[webview] ${args.firstOrNull}');
                return {'ok': true};
              },
            );
            // Bridge signals page ready via either handler name
            ctrl.addJavaScriptHandler(
              handlerName: 'onReady',
              callback: (_) { _onReady(); return {'ok': true}; },
            );
            ctrl.addJavaScriptHandler(
              handlerName: 'onPageReady',
              callback: (_) { _onReady(); return {'ok': true}; },
            );
            ctrl.addJavaScriptHandler(
              handlerName: 'onProgress',
              callback: (args) {
                debugPrint('[progress] ${(args.firstOrNull as Map?)?['percent']}%');
                return {'ok': true};
              },
            );
            ctrl.addJavaScriptHandler(handlerName: 'onResult', callback: (_) => {'ok': true});
            ctrl.addJavaScriptHandler(
              handlerName: 'onError',
              callback: (args) { debugPrint('[ws-error] ${args.firstOrNull}'); return {'ok': true}; },
            );
          },
          onLoadStop: (ctrl, url) { if (!_ready) _onReady(); },
        ),

        if (!_ready)
          const Center(
            child: SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      ],
    );
  }

  void _onReady() {
    if (!mounted) return;
    setState(() => _ready = true);
    _ctrl?.evaluateJavascript(
        source: "if(window.Bridge) Bridge.connectWS('ws://127.0.0.1:8000');");
  }

  /// Push a completed HTTP backtest result into the charts.
  void loadResult(BacktestResult result) {
    final payload = jsonEncode({
      'bot':          result.bot,
      'summary':      _summaryJson(result.summary),
      'candles':      result.candles.map((c) => c.toJson()).toList(),
      'trades':       result.trades.map((t) => t.toJson()).toList(),
      'equity_curve': result.equityCurve.map((e) => e.toJson()).toList(),
    });
    _ctrl?.evaluateJavascript(source: "Bridge.loadResult($payload)");
  }

  /// Update the topbar labels inside the WebView.
  void setTopbar(String symbol, String tf, String bot, String dateRange) {
    String esc(String s) => s.replaceAll("'", r"\'");
    _ctrl?.evaluateJavascript(
        source: "if(window.setTopbar) setTopbar('${esc(symbol)}','${esc(tf)}','${esc(bot)}','${esc(dateRange)}')");
  }

  Map<String, dynamic> _summaryJson(BacktestSummary s) => {
        'total_return_pct':  s.totalReturnPct,
        'max_drawdown_pct':  s.maxDrawdownPct,
        'trades':            s.trades,
        'winners':           s.winners,
        'losers':            s.losers,
        'win_rate_pct':      s.winRatePct,
        'profit_factor':     s.profitFactor,
        'total_fees_usdt':   s.totalFeesUsdt,
        'avg_win_usdt':      s.avgWinUsdt,
        'avg_loss_usdt':     s.avgLossUsdt,
        'initial_equity':    s.initialEquity,
        'final_equity':      s.finalEquity,
        'peak_equity':       s.peakEquity,
        'rejected_orders':   s.rejectedOrders,
      };
}
