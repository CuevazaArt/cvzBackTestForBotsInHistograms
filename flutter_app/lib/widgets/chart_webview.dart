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

            // Flutter → JS handlers
            ctrl.addJavaScriptHandler(
              handlerName: 'flutter_log',
              callback: (args) {
                debugPrint('[webview] ${args.firstOrNull}');
                return {'ok': true};
              },
            );
            ctrl.addJavaScriptHandler(
              handlerName: 'onPageReady',
              callback: (_) {
                setState(() => _ready = true);
                _connectWS();
                return {'ok': true};
              },
            );
            ctrl.addJavaScriptHandler(
              handlerName: 'onProgress',
              callback: (args) {
                final pct = (args.firstOrNull as Map?)?['percent'] ?? 0;
                debugPrint('[progress] $pct%');
                return {'ok': true};
              },
            );
            ctrl.addJavaScriptHandler(
              handlerName: 'onResult',
              callback: (_) => {'ok': true},
            );
            ctrl.addJavaScriptHandler(
              handlerName: 'onError',
              callback: (args) {
                debugPrint('[wserror] ${args.firstOrNull}');
                return {'ok': true};
              },
            );
          },
          onLoadStop: (ctrl, url) async {
            // Fallback: connect WS if onPageReady wasn't fired
            if (!_ready) _connectWS();
          },
        ),

        // Loading overlay
        if (!_ready)
          const Center(
            child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      ],
    );
  }

  void _connectWS() {
    _ctrl?.evaluateJavascript(
        source: "if(window.initBridge) initBridge('ws://127.0.0.1:8000');");
  }

  /// Call after a successful HTTP backtest run — pushes result to charts.
  void loadResult(BacktestResult result) {
    final json = jsonEncode({
      'bot':          result.bot,
      'summary':      _summaryJson(result.summary),
      'trades':       result.trades.map(_tradeJson).toList(),
      'equity_curve': result.equityCurve.map((e) => {'time': e.time, 'value': e.value}).toList(),
    });
    _ctrl?.evaluateJavascript(source: "Bridge.loadResult($json)");
  }

  /// Update the topbar labels shown inside the WebView.
  void setTopbar(String symbol, String tf, String bot, String dateRange) {
    _ctrl?.evaluateJavascript(
        source: "if(window.setTopbar) setTopbar('$symbol','$tf','$bot','$dateRange')");
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
      };

  Map<String, dynamic> _tradeJson(TradeResult t) => {
        'entry_time':  t.entryTime,
        'exit_time':   t.exitTime,
        'entry_price': t.entryPrice,
        'exit_price':  t.exitPrice,
        'qty':         t.qty,
        'pnl':         t.pnl,
        'pnl_pct':     t.pnlPct,
        'reason':      t.reason,
      };
}
