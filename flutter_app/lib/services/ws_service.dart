import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Typed WebSocket events from the StreamingEngine
enum WsEventType {
  ready,
  start,
  candle,
  trade,
  equity,
  progress,
  result,
  error,
  pong,
  trialCompleted,
  optimizeDone,
  // Synthetic (client-side)
  disconnected,
  reconnecting,
  reconnected,
  unknown,
}

class WsEvent {
  final WsEventType type;
  final Map<String, dynamic> data;
  const WsEvent(this.type, this.data);

  factory WsEvent.fromJson(Map<String, dynamic> j) {
    final t = switch (j['type'] as String? ?? '') {
      'ready' => WsEventType.ready,
      'start' => WsEventType.start,
      'candle' => WsEventType.candle,
      'trade' => WsEventType.trade,
      'equity' => WsEventType.equity,
      'progress' => WsEventType.progress,
      'result' => WsEventType.result,
      'error' => WsEventType.error,
      'pong' => WsEventType.pong,
      'trial_completed' => WsEventType.trialCompleted,
      'optimize_done' => WsEventType.optimizeDone,
      _ => WsEventType.unknown,
    };
    return WsEvent(t, (j['data'] as Map<String, dynamic>?) ?? {});
  }
}

/// Connection status for UI
enum WsStatus { disconnected, connecting, connected, reconnecting }

/// Manages the WebSocket connection to /ws with auto-reconnect.
class WsService {
  final String wsUrl;
  final int maxReconnectAttempts;
  WebSocketChannel? _channel;
  StreamController<WsEvent>? _controller;
  final ValueNotifier<WsStatus> status = ValueNotifier(WsStatus.disconnected);

  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  bool _wantConnected = false;

  WsService({
    this.wsUrl = 'ws://127.0.0.1:8002/ws',
    this.maxReconnectAttempts = 8,
  });

  Stream<WsEvent> get events => _controller!.stream;
  bool get isConnected => status.value == WsStatus.connected;

  Future<void> connect() async {
    _wantConnected = true;
    _reconnectAttempts = 0;
    await _doConnect();
  }

  Future<void> _doConnect() async {
    await _closeChannel();
    _controller ??= StreamController<WsEvent>.broadcast();
    status.value = WsStatus.connecting;

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _channel!.stream.listen(
        (raw) {
          try {
            final json = jsonDecode(raw as String) as Map<String, dynamic>;
            _controller!.add(WsEvent.fromJson(json));
          } catch (e) {
            debugPrint('WsService: parse error: $e');
          }
        },
        onError: (e) {
          debugPrint('WsService onError: $e');
          _onDisconnect(error: e.toString());
        },
        onDone: () {
          debugPrint('WsService onDone');
          _onDisconnect();
        },
        cancelOnError: true,
      );
      await _channel!.ready;
      status.value = WsStatus.connected;
      _reconnectAttempts = 0;
      _controller!.add(const WsEvent(WsEventType.reconnected, {}));
    } catch (e) {
      debugPrint('WsService connect failed: $e');
      _onDisconnect(error: e.toString());
    }
  }

  void _onDisconnect({String? error}) {
    if (status.value == WsStatus.disconnected) return;
    status.value = WsStatus.disconnected;
    // ignore: use_null_aware_elements
    _controller?.add(WsEvent(WsEventType.disconnected, {if (error != null) 'message': error}));

    if (_wantConnected && _reconnectAttempts < maxReconnectAttempts) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    // Exponential backoff: 500ms, 1s, 2s, 4s, 8s, max 15s
    final delayMs = (500 * (1 << (_reconnectAttempts - 1))).clamp(500, 15000);
    status.value = WsStatus.reconnecting;
    _controller?.add(WsEvent(
      WsEventType.reconnecting,
      {'attempt': _reconnectAttempts, 'delay_ms': delayMs, 'max': maxReconnectAttempts},
    ));
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_wantConnected) _doConnect();
    });
  }

  void send(Map<String, dynamic> payload) {
    if (_channel == null || status.value != WsStatus.connected) {
      debugPrint('WsService.send: not connected, dropping payload');
      return;
    }
    _channel?.sink.add(jsonEncode(payload));
  }

  void ping() => send({'action': 'ping'});

  void runBacktest({
    required List<Map<String, dynamic>> bots,
    required String symbol,
    required String timeframe,
    int? startMs,
    int? endMs,
    double initialCash = 10000,
    double takerFeePct = 0.1,
    double slippagePct = 0.05,
    List<Map<String, dynamic>>? indicators,
  }) {
    send({
      'action': 'backtest',
      'config': {
        'bots': bots,
        'symbol': symbol,
        'timeframe': timeframe,
        // ignore: use_null_aware_elements
        if (startMs != null) 'start_ms': startMs,
        // ignore: use_null_aware_elements
        if (endMs != null) 'end_ms': endMs,
        'initial_cash': initialCash,
        'taker_fee_pct': takerFeePct,
        'slippage_pct': slippagePct,
        'indicators': indicators ?? [],
      },
    });
  }

  void runOptimize({
    required String bot,
    required String symbol,
    required String timeframe,
    required Map<String, dynamic> searchSpace,
    required Map<String, dynamic> fixedParams,
    required String objective,
    required int trials,
    required String sampler,
    double initialCash = 10000,
    double takerFeePct = 0.1,
    double slippagePct = 0.05,
  }) {
    send({
      'action': 'optimize',
      'config': {
        'bot': bot,
        'symbol': symbol,
        'timeframe': timeframe,
        'search_space': searchSpace,
        'fixed_params': fixedParams,
        'objective': objective,
        'trials': trials,
        'sampler': sampler,
        'initial_cash': initialCash,
        'taker_fee_pct': takerFeePct,
        'slippage_pct': slippagePct,
      },
    });
  }

  Future<void> _closeChannel() async {
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  Future<void> disconnect() async {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _closeChannel();
    await _controller?.close();
    _controller = null;
    status.value = WsStatus.disconnected;
  }
}
