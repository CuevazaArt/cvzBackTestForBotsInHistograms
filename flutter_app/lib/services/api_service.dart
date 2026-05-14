import 'dart:convert';
import 'package:http/http.dart' as http;

/// Models returned by the API
class SymbolEntry {
  final String symbol;
  final String timeframe;
  final int candles;
  final int? firstMs;
  final int? lastMs;

  const SymbolEntry({
    required this.symbol,
    required this.timeframe,
    required this.candles,
    this.firstMs,
    this.lastMs,
  });

  factory SymbolEntry.fromJson(Map<String, dynamic> j) => SymbolEntry(
        symbol: j['symbol'] as String,
        timeframe: j['timeframe'] as String,
        candles: j['candles'] as int,
        firstMs: j['first_ms'] as int?,
        lastMs: j['last_ms'] as int?,
      );
}

class BotInfo {
  final String name;
  final String? description;
  const BotInfo({required this.name, this.description});

  factory BotInfo.fromJson(Map<String, dynamic> j) =>
      BotInfo(name: j['name'] as String, description: j['description'] as String?);
}

class HealthStatus {
  final bool ok;
  const HealthStatus(this.ok);
}

/// HTTP client for the FastAPI backend
class ApiService {
  final String baseUrl;

  ApiService({this.baseUrl = 'http://127.0.0.1:8002'});

  Future<HealthStatus> checkHealth() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/health')).timeout(
            const Duration(seconds: 3),
          );
      return HealthStatus(res.statusCode == 200);
    } catch (_) {
      return const HealthStatus(false);
    }
  }

  Future<List<SymbolEntry>> listSymbols() async {
    final res = await http.get(Uri.parse('$baseUrl/api/candles'));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => SymbolEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<BotInfo>> listBots() async {
    final res = await http.get(Uri.parse('$baseUrl/api/bots'));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => BotInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, dynamic>> downloadCandles({
    required String symbol,
    required String timeframe,
    required String dateFrom,
    required String dateTo,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/candles/download'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'symbol': symbol,
        'timeframe': timeframe,
        'date_from': dateFrom,
        'date_to': dateTo,
      }),
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
