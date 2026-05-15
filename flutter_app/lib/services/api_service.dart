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
  final String apiToken;

  ApiService({this.baseUrl = 'http://127.0.0.1:8002', this.apiToken = ''});

  Map<String, String> get _authHeaders => {
        if (apiToken.trim().isNotEmpty) 'x-api-key': apiToken.trim(),
      };

  Map<String, String> get _jsonHeaders => {
        'Content-Type': 'application/json',
        ..._authHeaders,
      };

  Future<HealthStatus> checkHealth() async {
    try {
      final res = await http.get(
        Uri.parse('$baseUrl/health'),
        headers: _authHeaders,
      ).timeout(
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

  // ── Credentials ──

  Future<bool> credentialsExist() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/credentials/exists'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return data['exists'] as bool? ?? false;
  }

  Future<void> saveCredentials(String apiKey, String apiSecret) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/credentials'),
      headers: _jsonHeaders,
      body: jsonEncode({'api_key': apiKey, 'api_secret': apiSecret}),
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  }

  Future<void> deleteCredentials() async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/credentials'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
  }

  Future<List<SymbolEntry>> listSymbols() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/candles/symbols'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => SymbolEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<List<BotInfo>> listBots() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/bots'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data.map((e) => BotInfo.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<BotParamsResponse> getBotParams(String botName) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/bots/$botName/params'),
      headers: _authHeaders,
    );
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
      headers: _jsonHeaders,
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
      headers: _jsonHeaders,
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
    final res = await http.get(
      Uri.parse('$baseUrl/api/jobs/$jobId'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return JobStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<JobStatus> cancelJob(String jobId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/jobs/$jobId/cancel'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}: ${res.body}');
    return JobStatus.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Launch a parameter sweep (`POST /api/experiments/run`).
  ///
  /// `bots` shape: `[{name: "EMACross", configs: [{fast_ema:5, slow_ema:20}, ...]}]`.
  /// Returns the job id used for polling via [getJob].
  /// Throws [ApiValidationError] on HTTP 422 (Pydantic validation) so the UI can
  /// show field-level feedback.
  Future<String> runOptimization({
    required String symbol,
    required String timeframe,
    required List<Map<String, dynamic>> bots,
    int workers = 4,
    double initialCash = 10000.0,
    double takerFeePct = 0.1,
    double slippagePct = 0.05,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/experiments/run'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'symbol': symbol,
        'timeframe': timeframe,
        'bots': bots,
        'workers': workers,
        'initial_cash': initialCash,
        'taker_fee_pct': takerFeePct,
        'slippage_pct': slippagePct,
      }),
    );
    if (res.statusCode == 422) {
      throw ApiValidationError.fromBody(res.body);
    }
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['id'] as String;
  }

  /// Launch an Optuna-backed optimization (`POST /api/optimize/run`).
  ///
  /// `searchSpace` shape: `{"fast_ema": {"type": "int", "low": 3, "high": 50, "step": 1}, ...}`.
  /// Returns the job id used for polling via [getJob].
  Future<String> runOptunaOptimization({
    required String symbol,
    required String timeframe,
    required String bot,
    required Map<String, Map<String, dynamic>> searchSpace,
    Map<String, dynamic> fixedParams = const {},
    String objective = 'total_return_pct',
    int trials = 100,
    String sampler = 'tpe',
    double initialCash = 10000.0,
    double takerFeePct = 0.1,
    double slippagePct = 0.05,
    double validationSplitPct = 0.2,
    int minTrades = 0,
    double? maxDrawdownPctLimit,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/optimize/run'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'symbol': symbol,
        'timeframe': timeframe,
        'bot': bot,
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
        if (maxDrawdownPctLimit != null) 'max_drawdown_pct_limit': maxDrawdownPctLimit,
      }),
    );
    if (res.statusCode == 422) {
      throw ApiValidationError.fromBody(res.body);
    }
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return body['id'] as String;
  }
}

/// Thrown when the backend rejects a request with HTTP 422 (Pydantic validation).
///
/// The Flutter UI uses [message] for a friendly banner.
class ApiValidationError implements Exception {
  final String message;
  final List<String> fieldPath;
  const ApiValidationError(this.message, this.fieldPath);

  factory ApiValidationError.fromBody(String body) {
    try {
      final j = jsonDecode(body);
      final detail = j is Map ? j['detail'] : null;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first as Map<String, dynamic>;
        final loc = (first['loc'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
        final msg = first['msg'] as String? ?? 'Validation error';
        return ApiValidationError(msg, loc);
      }
      if (detail is String) return ApiValidationError(detail, const []);
    } catch (_) {}
    return ApiValidationError('Validation error: $body', const []);
  }

  @override
  String toString() => fieldPath.isEmpty
      ? message
      : '${fieldPath.join('.')}: $message';
}
