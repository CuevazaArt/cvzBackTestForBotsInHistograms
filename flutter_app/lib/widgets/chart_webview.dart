import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:webview_windows/webview_windows.dart';

import '../models/backtest_result.dart';

/// Lightweight Charts host (WebView2 wrapper).
///
/// We deliberately use `webview_windows` rather than `flutter_inappwebview`
/// because the 6.x line of inappwebview ships with broken Windows headers.
/// The chart bridge only needs three things:
///   1. load a static URL served by FastAPI under /static/index.html
///   2. evaluate JS to push payloads (Bridge.loadResult / setTopbar)
///   3. receive postMessage strings back (used for diagnostics today, may be
///      wired to interactive crosshair callbacks later).
///
/// State machine: `loading` → `ready` (after WebView finishes initial load
/// AND has had a moment to register its global Bridge). A 20 s watchdog
/// flips the panel to an error overlay so the user is never stuck staring
/// at a spinner that never resolves.
class ChartWebView extends StatefulWidget {
  const ChartWebView({super.key});

  @override
  State<ChartWebView> createState() => ChartWebViewState();
}

enum _ChartState { loading, ready, failed }

class ChartWebViewState extends State<ChartWebView> {
  static const _chartUrl = 'http://127.0.0.1:8000/static/index.html';
  static const _watchdog = Duration(seconds: 20);

  final _ctrl = WebviewController();
  StreamSubscription<dynamic>? _msgSub;
  _ChartState _state = _ChartState.loading;
  String? _errorMsg;
  Timer? _watchdogTimer;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      await _ctrl.initialize();
      await _ctrl.setBackgroundColor(const Color(0xFF131722));
      await _ctrl.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      _msgSub = _ctrl.webMessage.listen((m) {
        debugPrint('[chart bridge] $m');
      });

      await _ctrl.loadUrl(_chartUrl);
      if (!mounted) return;
      setState(() => _state = _ChartState.ready);

      _watchdogTimer = Timer(_watchdog, () {
        if (!mounted) return;
        if (_state != _ChartState.ready) {
          setState(() {
            _state = _ChartState.failed;
            _errorMsg = 'Chart did not respond in 20 s';
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _state = _ChartState.failed;
        _errorMsg = e.toString();
      });
    }
  }

  @override
  void dispose() {
    _watchdogTimer?.cancel();
    _msgSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  // ── Public API (called from HomeScreen via GlobalKey) ────────────────────

  /// Push a completed backtest payload into the in-page Bridge object.
  void loadResult(BacktestResult result) {
    final payload = jsonEncode({
      'bot':          result.bot,
      'summary':      _summaryJson(result.summary),
      'candles':      result.candles.map((c) => c.toJson()).toList(),
      'trades':       result.trades.map((t) => t.toJson()).toList(),
      'equity_curve': result.equityCurve.map((e) => e.toJson()).toList(),
    });
    _runJs('window.Bridge && Bridge.loadResult($payload);');
  }

  /// Update the topbar labels inside the WebView (the chart page has its
  /// own header so the breadcrumb stays visible while panning).
  void setTopbar(String symbol, String tf, String bot, String dateRange) {
    String esc(String s) => s.replaceAll(r"\", r"\\").replaceAll("'", r"\'");
    _runJs(
      "if (window.setTopbar) setTopbar('${esc(symbol)}','${esc(tf)}',"
      "'${esc(bot)}','${esc(dateRange)}');",
    );
  }

  Future<void> _runJs(String src) async {
    if (_state != _ChartState.ready) return;
    try {
      await _ctrl.executeScript(src);
    } catch (e) {
      debugPrint('[chart] executeScript failed: $e');
    }
  }

  // ── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF131722),
      child: Stack(
        children: [
          if (_state != _ChartState.failed) Webview(_ctrl),
          if (_state == _ChartState.loading)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_state == _ChartState.failed)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Color(0xFFEF5350), size: 28),
                    const SizedBox(height: 8),
                    Text(
                      'Chart failed to load',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _errorMsg ?? 'Unknown error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFFB2B5BE)),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _state = _ChartState.loading;
                          _errorMsg = null;
                        });
                        _bootstrap();
                      },
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
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
