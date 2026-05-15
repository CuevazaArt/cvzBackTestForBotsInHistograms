import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

typedef WsEventCallback = void Function(String type, Map<String, dynamic> data);

class WsClient {
  final String baseUrl;
  final String? token;

  WsClient({this.baseUrl = 'ws://127.0.0.1:8000', this.token});

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  final List<WsEventCallback> _listeners = [];

  bool get isConnected => _channel != null;

  void addListener(WsEventCallback cb) => _listeners.add(cb);
  void removeListener(WsEventCallback cb) => _listeners.remove(cb);

  void connect() {
    final url = token != null
        ? '$baseUrl/ws?token=${Uri.encodeComponent(token!)}'
        : '$baseUrl/ws';

    _channel = WebSocketChannel.connect(Uri.parse(url));
    _sub = _channel!.stream.listen(
      _onData,
      onError: (e) => _dispatch('error', {'message': e.toString()}),
      onDone: ()  => _dispatch('closed', {}),
    );
  }

  void disconnect() {
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void runBacktest(Map<String, dynamic> config) {
    send({'action': 'backtest', 'config': config});
  }

  void _onData(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = msg['type'] as String? ?? 'unknown';
      final data = msg['data'] as Map<String, dynamic>? ?? {};
      _dispatch(type, data);
    } catch (_) {}
  }

  void _dispatch(String type, Map<String, dynamic> data) {
    for (final cb in List.of(_listeners)) {
      cb(type, data);
    }
  }
}
