import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
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
  ping,
  pong,
  trialCompleted,
  optimizeDone,
  // Playback transport events (server echo)
  paused,
  resumed,
  cancelled,
  speedChanged,
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
      'ping' => WsEventType.ping,
      'pong' => WsEventType.pong,
      'trial_completed' => WsEventType.trialCompleted,
      'optimize_done' => WsEventType.optimizeDone,
      'paused' => WsEventType.paused,
      'resumed' => WsEventType.resumed,
      'cancelled' => WsEventType.cancelled,
      'speed_changed' => WsEventType.speedChanged,
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
  final String apiToken;
  final int maxReconnectAttempts;
  WebSocketChannel? _channel;
  StreamController<WsEvent>? _controller;
  final ValueNotifier<WsStatus> status = ValueNotifier(WsStatus.disconnected);

  int _reconnectAttempts = 0;
  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _heartbeatTimeoutTimer;
  bool _wantConnected = false;

  /// Outgoing messages buffered while the socket is down. Flushed on reconnect.
  final List<Map<String, dynamic>> _outboundBuffer = [];
  static const int _maxBuffer = 128;

  /// If no traffic (server ping or any event) arrives within this window,
  /// force-reconnect to recover from half-open connections.
  static const Duration _heartbeatTimeout = Duration(seconds: 60);

  /// Client-initiated ping cadence to keep the connection warm and exercise
  /// the timeout watchdog.
  static const Duration _clientPingInterval = Duration(seconds: 25);

  WsService({
    this.wsUrl = 'ws://127.0.0.1:8002/ws',
    this.apiToken = '',
    this.maxReconnectAttempts = 8,
  });

  Stream<WsEvent> get events {
    _controller ??= StreamController<WsEvent>.broadcast();
    return _controller!.stream;
  }

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
      _channel = IOWebSocketChannel.connect(
        Uri.parse(wsUrl),
        headers: {if (apiToken.trim().isNotEmpty) 'x-api-key': apiToken.trim()},
      );
      _channel!.stream.listen(
        (raw) {
          _resetHeartbeatTimeout();
          try {
            final json = jsonDecode(raw as String) as Map<String, dynamic>;
            final evt = WsEvent.fromJson(json);
            // Server-initiated ping → reply with pong so server tracks liveness.
            if (evt.type == WsEventType.ping) {
              _rawSend({'action': 'pong'});
            }
            _controller!.add(evt);
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
      _startHeartbeat();
      _flushOutboundBuffer();
    } catch (e) {
      debugPrint('WsService connect failed: $e');
      _onDisconnect(error: e.toString());
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_clientPingInterval, (_) {
      if (status.value == WsStatus.connected) {
        _rawSend({'action': 'ping'});
      }
    });
    _resetHeartbeatTimeout();
  }

  void _resetHeartbeatTimeout() {
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = Timer(_heartbeatTimeout, () {
      debugPrint('WsService: heartbeat timeout — forcing reconnect');
      _onDisconnect(error: 'heartbeat timeout');
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatTimeoutTimer?.cancel();
    _heartbeatTimeoutTimer = null;
  }

  void _flushOutboundBuffer() {
    if (_outboundBuffer.isEmpty) return;
    final drained = List<Map<String, dynamic>>.from(_outboundBuffer);
    _outboundBuffer.clear();
    for (final p in drained) {
      _rawSend(p);
    }
  }

  void _onDisconnect({String? error}) {
    _stopHeartbeat();
    if (status.value == WsStatus.disconnected) return;
    status.value = WsStatus.disconnected;
    _controller?.add(WsEvent(WsEventType.disconnected, {'message': ?error}));

    if (_wantConnected && _reconnectAttempts < maxReconnectAttempts) {
      _scheduleReconnect();
    }
  }

  /// Reconnect delay formula exposed for testing.
  @visibleForTesting
  static int reconnectDelayMs(int attempt) =>
      (500 * (1 << (attempt - 1))).clamp(500, 15000);

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectAttempts++;
    // Exponential backoff: 500ms, 1s, 2s, 4s, 8s, max 15s
    final delayMs = reconnectDelayMs(_reconnectAttempts);
    status.value = WsStatus.reconnecting;
    _controller?.add(
      WsEvent(WsEventType.reconnecting, {
        'attempt': _reconnectAttempts,
        'delay_ms': delayMs,
        'max': maxReconnectAttempts,
      }),
    );
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      if (_wantConnected) _doConnect();
    });
  }

  void send(Map<String, dynamic> payload) {
    if (_channel == null || status.value != WsStatus.connected) {
      // Buffer instead of dropping, flushed on reconnect.
      if (_outboundBuffer.length >= _maxBuffer) {
        debugPrint('WsService.send: outbound buffer full, dropping oldest');
        _outboundBuffer.removeAt(0);
      }
      _outboundBuffer.add(payload);
      return;
    }
    _rawSend(payload);
  }

  /// Send without buffering — used by heartbeat / pong responses.
  void _rawSend(Map<String, dynamic> payload) {
    try {
      _channel?.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('WsService._rawSend failed: $e');
    }
  }

  void ping() => send({'action': 'ping'});

  /// Number of messages waiting for the connection to come back up.
  int get pendingOutbound => _outboundBuffer.length;

  void runBacktest({
    required List<Map<String, dynamic>> bots,
    required String symbol,
    required String timeframe,
    int? startMs,
    int? endMs,
    double initialCash = 10000,
    double takerFeePct = 0.1,
    double slippagePct = 0.05,
    bool fillOnNextOpen = true,
    List<Map<String, dynamic>>? indicators,
    int speedMs = 100,
    String formula = 'ohlc',
  }) {
    send({
      'action': 'backtest',
      'config': {
        'bots': bots,
        'symbol': symbol,
        'timeframe': timeframe,
        'start_ms': ?startMs,
        'end_ms': ?endMs,
        'initial_cash': initialCash,
        'taker_fee_pct': takerFeePct,
        'slippage_pct': slippagePct,
        'fill_on_next_open': fillOnNextOpen,
        'indicators': indicators ?? [],
        'speed_ms': speedMs,
        'formula': formula,
      },
    });
  }

  /// Pause the active backtest run mid-execution.
  void pause() => send({'action': 'pause'});

  /// Resume a paused backtest run.
  void resume() => send({'action': 'resume'});

  /// Advance exactly one candle while paused.
  void step() => send({'action': 'step'});

  /// Change the wall-clock playback speed.
  /// [speedMs] is milliseconds per candle: 200=0.5x, 100=1x, 50=2x,
  /// 20=5x, 10=10x, 0=Max (no delay).
  void setSpeed(int speedMs) =>
      send({'action': 'set_speed', 'speed_ms': speedMs});

  /// Cancel (stop) the active backtest run.
  void cancelRun() => send({'action': 'cancel'});

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
    double validationSplitPct = 0.2,
    int minTrades = 0,
    double? maxDrawdownPctLimit,
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
        'validation_split_pct': validationSplitPct,
        'min_trades': minTrades,
        'max_drawdown_pct_limit': ?maxDrawdownPctLimit,
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
    _stopHeartbeat();
    _outboundBuffer.clear();
    await _closeChannel();
    await _controller?.close();
    _controller = null;
    status.value = WsStatus.disconnected;
  }
}
