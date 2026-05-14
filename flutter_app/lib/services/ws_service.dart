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
      _ => WsEventType.unknown,
    };
    return WsEvent(t, (j['data'] as Map<String, dynamic>?) ?? {});
  }
}

/// Manages the WebSocket connection to /ws
class WsService {
  final String wsUrl;
  WebSocketChannel? _channel;
  StreamController<WsEvent>? _controller;

  WsService({this.wsUrl = 'ws://127.0.0.1:8002/ws'});

  Stream<WsEvent> get events => _controller!.stream;
  bool get isConnected => _channel != null;

  Future<void> connect() async {
    await disconnect();
    _controller = StreamController<WsEvent>.broadcast();
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
      onError: (e) => _controller!.addError(e),
      onDone: () => _controller!.close(),
    );
    await _channel!.ready;
  }

  void send(Map<String, dynamic> payload) {
    _channel?.sink.add(jsonEncode(payload));
  }

  void ping() => send({'action': 'ping'});

  void runBacktest({
    required String bot,
    required String symbol,
    required String timeframe,
    Map<String, dynamic>? params,
    int? startMs,
    int? endMs,
    double initialCash = 10000,
    double takerFeePct = 0.1,
    double slippagePct = 0.05,
  }) {
    send({
      'action': 'backtest',
      'config': {
        'bot': bot,
        'symbol': symbol,
        'timeframe': timeframe,
        'params': params ?? {},
        'start_ms': ?startMs,
        'end_ms': ?endMs,
        'initial_cash': initialCash,
        'taker_fee_pct': takerFeePct,
        'slippage_pct': slippagePct,
      },
    });
  }

  Future<void> disconnect() async {
    await _channel?.sink.close();
    await _controller?.close();
    _channel = null;
    _controller = null;
  }
}
