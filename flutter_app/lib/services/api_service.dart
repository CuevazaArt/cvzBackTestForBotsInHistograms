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

class ParamSpec {
  final String type;
  final dynamic defaultValue;
  final double? min;
  final double? max;
  final double? step;

  const ParamSpec({
    required this.type,
    this.defaultValue,
    this.min,
    this.max,
    this.step,
  });

  factory ParamSpec.fromJson(Map<String, dynamic> j) => ParamSpec(
        type: j['type'] as String,
        defaultValue: j['default'],
        min: (j['min'] as num?)?.toDouble(),
        max: (j['max'] as num?)?.toDouble(),
        step: (j['step'] as num?)?.toDouble(),
      );
}

class BotParamsResponse {
  final String name;
  final Map<String, ParamSpec> params;

  const BotParamsResponse({required this.name, required this.params});

  factory BotParamsResponse.fromJson(Map<String, dynamic> j) {
    final Map<String, dynamic> rawParams = j['params'] ?? {};
    return BotParamsResponse(
      name: j['name'] as String,
      params: rawParams.map((k, v) => MapEntry(k, ParamSpec.fromJson(v))),
    );
  }
}

class HealthStatus {
  final bool ok;
  final int binanceWeight1m;
  const HealthStatus(this.ok, {this.binanceWeight1m = 0});
}

class JobStatus {
  final String id;
  final String status; // "pending" | "running" | "done" | "error"
  final double progress;
  final String? message;
  final Map<String, dynamic>? result;
  
  const JobStatus({
    required this.id,
    required this.status,
    required this.progress,
    this.message,
    this.result,
  });

  factory JobStatus.fromJson(Map<String, dynamic> j) => JobStatus(
        id: j['id'] as String,
        status: j['status'] as String,
        progress: (j['progress'] as num?)?.toDouble() ?? 0.0,
        message: j['message'] as String?,
        result: j['result'] as Map<String, dynamic>?,
      );
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
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return HealthStatus(true, binanceWeight1m: (data['binance_weight_1m'] as num?)?.toInt() ?? 0);
      }
      return const HealthStatus(false);
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

  Future<BotParamsResponse> getBotParams(String botName) async {
    final res = await http.get(Uri.parse('$baseUrl/api/bots/$botName/params'));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return BotParamsResponse.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
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

  Future<Map<String, dynamic>> downloadCandlesZip({
    required String symbol,
    required String timeframe,
    required int year,
    required int month,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/candles/download/zip'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'symbol': symbol,
        'timeframe': timeframe,
        'year': year,
        'month': month,
      }),
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<JobStatus> getJob(String jobId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/jobs/$jobId'));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return JobStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }
}
