import 'dart:async';
import 'dart:convert';

import '../../core/models/candle.dart';
import '../../core/models/trade.dart';
import '../../core/models/position.dart';

/// Typed marker for the chart bridge.
class ChartMarker {
  final int timeMs;
  final String shape; // arrowUp | arrowDown | circle | square
  final String position; // belowBar | aboveBar | inBar
  final String color;
  final String text;
  final String? botId;

  const ChartMarker({
    required this.timeMs,
    required this.shape,
    required this.position,
    required this.color,
    this.text = '',
    this.botId,
  });

  Map<String, dynamic> toJson() => {
        'time': timeMs,
        'shape': shape,
        'position': position,
        'color': color,
        'text': text,
        if (botId != null) 'botId': botId,
      };

  factory ChartMarker.entry(Trade t, {String? botId}) => ChartMarker(
        timeMs: t.entryTimestampMs,
        shape: t.side == PositionSide.long ? 'arrowUp' : 'arrowDown',
        position: t.side == PositionSide.long ? 'belowBar' : 'aboveBar',
        color: t.side == PositionSide.long ? '#22c55e' : '#ef4444',
        text: 'B@${t.entryPrice.toStringAsFixed(2)}',
        botId: botId ?? t.botId,
      );

  factory ChartMarker.exit(Trade t, {String? botId}) => ChartMarker(
        timeMs: t.exitTimestampMs,
        shape: t.side == PositionSide.long ? 'arrowDown' : 'arrowUp',
        position: t.side == PositionSide.long ? 'aboveBar' : 'belowBar',
        color: t.isWin ? '#22c55e' : '#ef4444',
        text: 'S@${t.exitPrice.toStringAsFixed(2)} (${t.pnl.toStringAsFixed(2)})',
        botId: botId ?? t.botId,
      );
}

/// A single command to send to the JS bridge.
///
/// Stored as a Dart object so we can replay it after the WebView becomes
/// ready, instead of silently dropping (which the old implementation did).
sealed class _ChartCommand {
  String toJs();
}

class _SetCandlesCmd extends _ChartCommand {
  final List<Candle> candles;
  _SetCandlesCmd(this.candles);
  @override
  String toJs() {
    final arr = candles.map((c) => {
          't': c.timestampMs,
          'o': c.open,
          'h': c.high,
          'l': c.low,
          'c': c.close,
        }).toList();
    return 'window.setCandles(${jsonEncode(arr)});';
  }
}

class _UpsertCandleCmd extends _ChartCommand {
  final Candle candle;
  _UpsertCandleCmd(this.candle);
  @override
  String toJs() {
    final obj = {
      't': candle.timestampMs,
      'o': candle.open,
      'h': candle.high,
      'l': candle.low,
      'c': candle.close,
    };
    return 'window.upsertCandle(${jsonEncode(obj)});';
  }
}

class _AddMarkerCmd extends _ChartCommand {
  final ChartMarker marker;
  _AddMarkerCmd(this.marker);
  @override
  String toJs() => 'window.addMarker(${jsonEncode(marker.toJson())});';
}

class _SetIndicatorCmd extends _ChartCommand {
  final String key;
  final List<({int t, double v})> points;
  final String color;
  _SetIndicatorCmd(this.key, this.points, this.color);
  @override
  String toJs() {
    final arr = points.map((p) => {'t': p.t, 'v': p.v}).toList();
    return 'window.setIndicator(${jsonEncode(key)}, ${jsonEncode(arr)}, ${jsonEncode(color)});';
  }
}

class _RemoveIndicatorCmd extends _ChartCommand {
  final String key;
  _RemoveIndicatorCmd(this.key);
  @override
  String toJs() => 'window.removeIndicator(${jsonEncode(key)});';
}

class _SetEquityCmd extends _ChartCommand {
  final List<({int t, double v})> points;
  _SetEquityCmd(this.points);
  @override
  String toJs() {
    final arr = points.map((p) => {'t': p.t, 'v': p.v}).toList();
    return 'window.setEquityCurve(${jsonEncode(arr)});';
  }
}

class _ClearChartCmd extends _ChartCommand {
  @override
  String toJs() => 'window.clearChart();';
}

class _FitContentCmd extends _ChartCommand {
  @override
  String toJs() => 'window.fitContent();';
}

class _SetMarkersModeCmd extends _ChartCommand {
  final String mode; // 'full' | 'minimal' | 'off'
  _SetMarkersModeCmd(this.mode);
  @override
  String toJs() => 'window.setMarkersMode(${jsonEncode(mode)});';
}

class _SetIndicatorsVisibleCmd extends _ChartCommand {
  final bool visible;
  _SetIndicatorsVisibleCmd(this.visible);
  @override
  String toJs() => 'window.setIndicatorsVisible($visible);';
}

class _SetEquityVisibleCmd extends _ChartCommand {
  final bool visible;
  _SetEquityVisibleCmd(this.visible);
  @override
  String toJs() => 'window.setEquityVisible($visible);';
}

/// Typed wrapper over the WebView's JS bridge.
///
/// Critical guarantee: commands sent BEFORE the chart is ready are buffered
/// (not silently dropped, unlike the legacy chart_webview.dart). When the
/// WebView fires `chart:ready`, the buffer is flushed in order.
class ChartController {
  /// Caller plugs this in to actually execute JS in the WebView.
  /// Returns `null` if execution is impossible right now (e.g. WebView
  /// not initialized), in which case the command stays buffered.
  Future<void> Function(String js)? executor;

  bool _ready = false;
  final List<_ChartCommand> _buffer = [];
  final _readyController = StreamController<void>.broadcast();
  Stream<void> get onReady => _readyController.stream;
  bool get isReady => _ready;
  int get bufferedCount => _buffer.length;

  /// Mark the chart ready and flush the buffer in order.
  Future<void> markReady() async {
    if (_ready) return;
    _ready = true;
    _readyController.add(null);
    final pending = List<_ChartCommand>.from(_buffer);
    _buffer.clear();
    for (final cmd in pending) {
      await _execute(cmd);
    }
  }

  /// Reset state — used when WebView reloads.
  void resetReady() {
    _ready = false;
  }

  Future<void> _execute(_ChartCommand cmd) async {
    if (!_ready || executor == null) {
      _buffer.add(cmd);
      return;
    }
    await executor!(cmd.toJs());
  }

  // ─── Public typed API ───────────────────────────────────────────────────

  Future<void> setCandles(List<Candle> candles) =>
      _execute(_SetCandlesCmd(candles));

  Future<void> upsertCandle(Candle candle) =>
      _execute(_UpsertCandleCmd(candle));

  Future<void> addMarker(ChartMarker marker) =>
      _execute(_AddMarkerCmd(marker));

  Future<void> setIndicator(
    String key,
    List<({int t, double v})> points, {
    String color = '#fbbf24',
  }) =>
      _execute(_SetIndicatorCmd(key, points, color));

  Future<void> removeIndicator(String key) =>
      _execute(_RemoveIndicatorCmd(key));

  Future<void> setEquityCurve(List<({int t, double v})> points) =>
      _execute(_SetEquityCmd(points));

  Future<void> clear() => _execute(_ClearChartCmd());

  Future<void> fitContent() => _execute(_FitContentCmd());

  Future<void> setMarkersMode(String mode) =>
      _execute(_SetMarkersModeCmd(mode));

  Future<void> setIndicatorsVisible(bool visible) =>
      _execute(_SetIndicatorsVisibleCmd(visible));

  Future<void> setEquityVisible(bool visible) =>
      _execute(_SetEquityVisibleCmd(visible));

  Future<void> dispose() => _readyController.close();
}
