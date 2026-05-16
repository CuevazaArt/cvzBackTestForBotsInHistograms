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

  factory BotInfo.fromJson(Map<String, dynamic> j) => BotInfo(
    name: j['name'] as String,
    description: j['description'] as String?,
  );
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
      final res = await http
          .get(Uri.parse('$baseUrl/health'), headers: _authHeaders)
          .timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return HealthStatus(
          true,
          binanceWeight1m: (data['binance_weight_1m'] as num?)?.toInt() ?? 0,
        );
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
    return data
        .map((e) => SymbolEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<BotInfo>> listBots() async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/bots'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final List<dynamic> data = jsonDecode(res.body) as List<dynamic>;
    return data
        .map((e) => BotInfo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<BotParamsResponse> getBotParams(String botName) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/bots/$botName/params'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    return BotParamsResponse.fromJson(
      jsonDecode(res.body) as Map<String, dynamic>,
    );
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
    if (res.statusCode == 422) throw ApiValidationError.fromBody(res.body);
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
    if (res.statusCode == 422) throw ApiValidationError.fromBody(res.body);
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
    if (res.statusCode != 200) {
      throw Exception('HTTP ${res.statusCode}: ${res.body}');
    }
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
        'max_drawdown_pct_limit': ?maxDrawdownPctLimit,
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

  // ── Phase 3: Results history + decision-support analysis ──────────────

  /// Browse persisted backtest results (newest first).
  Future<List<Map<String, dynamic>>> listResults({
    String? symbol,
    String? timeframe,
    int limit = 50,
    int offset = 0,
  }) async {
    final qp = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (symbol != null && symbol.isNotEmpty) 'symbol': symbol,
      if (timeframe != null && timeframe.isNotEmpty) 'timeframe': timeframe,
    };
    final uri = Uri.parse('$baseUrl/api/backtest').replace(queryParameters: qp);
    final res = await http.get(uri, headers: _authHeaders);
    if (res.statusCode != 200) {
      throw ApiError(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body);
    final list = decoded is List
        ? decoded
        : (decoded as Map<String, dynamic>)['results'] as List? ?? [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Fetch a single persisted result by run_id.
  Future<Map<String, dynamic>> getResult(String runId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/backtest/$runId'),
      headers: _authHeaders,
    );
    if (res.statusCode == 404) {
      throw ApiError(404, 'Run $runId not found');
    }
    if (res.statusCode != 200) {
      throw ApiError(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Delete a persisted result.
  Future<void> deleteResult(String runId) async {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/backtest/$runId'),
      headers: _authHeaders,
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw ApiError(res.statusCode, res.body);
    }
  }

  /// Download the self-contained HTML report for a stored run.
  ///
  /// Returns the raw HTML body so the caller can write it to disk and/or
  /// open it in the user's browser.
  Future<String> downloadReportHtml(String runId) async {
    final res = await http.get(
      Uri.parse('$baseUrl/api/backtest/$runId/report.html'),
      headers: _authHeaders,
    );
    if (res.statusCode == 404) {
      throw ApiError(404, 'Run $runId not found');
    }
    if (res.statusCode != 200) {
      throw ApiError(res.statusCode, res.body);
    }
    return res.body;
  }

  /// Compare up to 10 persisted runs side-by-side.
  ///
  /// Returns a body shaped `{runs: [...], missing: [...]}`. Each entry in
  /// `runs` carries the key metrics plus a downsampled equity curve so the
  /// Compare tab can render its table + overlaid chart without re-running.
  Future<Map<String, dynamic>> compareRuns({
    required List<String> runIds,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/backtest/compare'),
      headers: _jsonHeaders,
      body: jsonEncode({'run_ids': runIds}),
    );
    if (res.statusCode == 422) {
      throw ApiValidationError.fromBody(res.body);
    }
    if (res.statusCode != 200) {
      throw ApiError(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> runStressTests({
    required String runId,
    List<double> feesMult = const [1.0, 2.0, 3.0],
    List<double> slippageMult = const [1.0, 2.0, 3.0],
    List<double> dropBestPct = const [0.0, 5.0, 10.0],
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/backtest/$runId/stress'),
      headers: _jsonHeaders,
      body: jsonEncode({
        'fees_mult': feesMult,
        'slippage_mult': slippageMult,
        'drop_best_pct': dropBestPct,
      }),
    );
    if (res.statusCode == 404) {
      throw ApiError(404, 'Run $runId not found');
    }
    if (res.statusCode == 422) {
      throw ApiValidationError.fromBody(res.body);
    }
    if (res.statusCode != 200) {
      throw ApiError(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> validateData({
    required String symbol,
    required String timeframe,
    int? startMs,
    int? endMs,
  }) async {
    final body = <String, dynamic>{
      'symbol': symbol,
      'timeframe': timeframe,
      'start_ms': ?startMs,
      'end_ms': ?endMs,
    };
    final res = await http.post(
      Uri.parse('$baseUrl/api/data/validate'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode == 404) {
      throw ApiError(404, res.body);
    }
    if (res.statusCode == 422) {
      throw ApiValidationError.fromBody(res.body);
    }
    if (res.statusCode != 200) {
      throw ApiError(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Walk-Forward Analysis — rolling train/test validation.
  Future<Map<String, dynamic>> runWalkForward({
    required String symbol,
    required String timeframe,
    required String bot,
    required Map<String, dynamic> baseParams,
    required Map<String, List<double>> paramRanges,
    required int trainSize,
    required int testSize,
    int? stepSize,
    bool anchored = false,
    int trialsPerWindow = 20,
    String objectiveMetric = 'total_return_pct',
    double initialCash = 10000.0,
    double takerFeePct = 0.1,
    double slippagePct = 0.05,
    int? startMs,
    int? endMs,
  }) async {
    final body = {
      'symbol': symbol,
      'timeframe': timeframe,
      'bot': bot,
      'base_params': baseParams,
      'param_ranges': paramRanges,
      'train_size': trainSize,
      'test_size': testSize,
      'step_size': ?stepSize,
      'anchored': anchored,
      'trials_per_window': trialsPerWindow,
      'objective_metric': objectiveMetric,
      'initial_cash': initialCash,
      'taker_fee_pct': takerFeePct,
      'slippage_pct': slippagePct,
      'start_ms': ?startMs,
      'end_ms': ?endMs,
    };
    final res = await http.post(
      Uri.parse('$baseUrl/api/analysis/walk-forward'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode == 422) {
      throw ApiValidationError.fromBody(res.body);
    }
    if (res.statusCode != 200) {
      throw ApiError(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Monte Carlo simulation — pass either a runId or raw trade PnLs.
  Future<Map<String, dynamic>> runMonteCarlo({
    String? runId,
    List<double>? tradePnls,
    int trials = 1000,
    String method = 'shuffle',
    int? seed,
    double initialEquity = 10000.0,
  }) async {
    final body = <String, dynamic>{
      'run_id': ?runId,
      'trade_pnls': ?tradePnls,
      'trials': trials,
      'method': method,
      'seed': ?seed,
      'initial_equity': initialEquity,
    };
    final res = await http.post(
      Uri.parse('$baseUrl/api/analysis/monte-carlo'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode == 422) {
      throw ApiValidationError.fromBody(res.body);
    }
    if (res.statusCode != 200) {
      throw ApiError(res.statusCode, res.body);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Robustness ranking — pass candidates with metrics, get back ranked list.
  Future<List<Map<String, dynamic>>> rankRobustness({
    required List<Map<String, dynamic>> candidates,
    Map<String, double>? weights,
  }) async {
    final body = {'candidates': candidates, 'weights': ?weights};
    final res = await http.post(
      Uri.parse('$baseUrl/api/analysis/robustness'),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw ApiError(res.statusCode, res.body);
    }
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    return (decoded['ranked'] as List? ?? []).cast<Map<String, dynamic>>();
  }
}

/// One field-level validation issue returned by FastAPI/Pydantic.
class ValidationIssue {
  final List<String> fieldPath;
  final String message;
  final String type;

  const ValidationIssue({
    required this.fieldPath,
    required this.message,
    this.type = '',
  });

  /// Human-friendly field name (last segment, drops 'body' prefix).
  String get field {
    final filtered = fieldPath.where((s) => s != 'body').toList();
    return filtered.isEmpty ? '' : filtered.last;
  }
}

/// Thrown when the backend rejects a request with HTTP 422 (Pydantic validation).
///
/// Holds *every* field-level issue so the UI can render a complete error list.
class ApiValidationError implements Exception {
  final List<ValidationIssue> issues;
  final String rawBody;

  const ApiValidationError(this.issues, [this.rawBody = '']);

  /// First issue's message (for compact banners). Falls back to "Validation error".
  String get message =>
      issues.isEmpty ? 'Validation error' : issues.first.message;

  /// First issue's path (kept for backwards compat with existing call sites).
  List<String> get fieldPath =>
      issues.isEmpty ? const [] : issues.first.fieldPath;

  factory ApiValidationError.fromBody(String body) {
    try {
      final j = jsonDecode(body);
      final detail = j is Map ? j['detail'] : null;
      if (detail is List) {
        final parsed = <ValidationIssue>[];
        for (final raw in detail) {
          if (raw is! Map) continue;
          final loc =
              (raw['loc'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[];
          parsed.add(
            ValidationIssue(
              fieldPath: loc,
              message: raw['msg'] as String? ?? 'Validation error',
              type: raw['type'] as String? ?? '',
            ),
          );
        }
        if (parsed.isNotEmpty) return ApiValidationError(parsed, body);
      }
      if (detail is String) {
        return ApiValidationError([
          ValidationIssue(fieldPath: const [], message: detail),
        ], body);
      }
    } catch (_) {}
    return ApiValidationError([
      ValidationIssue(fieldPath: const [], message: 'Validation error: $body'),
    ], body);
  }

  /// Returns a helpful hint for known field/message combinations. The UI
  /// surfaces this beside the raw API message.
  String hintFor(ValidationIssue issue) {
    final f = issue.field.toLowerCase();
    final m = issue.message.toLowerCase();
    if (f == 'fast_ema' || (m.contains('fast_ema') && m.contains('slow'))) {
      return 'fast_ema must be strictly less than slow_ema.';
    }
    if (m.contains('no candles')) {
      return 'No candles for this symbol/timeframe. Open Data Manager and download a range first.';
    }
    if (m.contains('unknown bot')) {
      return 'Bot name not recognised. Use GET /api/bots to list available strategies.';
    }
    return '';
  }

  @override
  String toString() {
    if (issues.isEmpty) return 'ApiValidationError';
    return issues
        .map(
          (i) => i.fieldPath.isEmpty
              ? i.message
              : '${i.fieldPath.join('.')}: ${i.message}',
        )
        .join('; ');
  }
}

/// Wraps an arbitrary HTTP failure with a user-friendly title and the raw body.
class ApiError implements Exception {
  final int statusCode;
  final String body;
  const ApiError(this.statusCode, this.body);

  String get friendlyMessage {
    if (statusCode == 404) return 'Resource not found (404).';
    if (statusCode == 401 || statusCode == 403) return 'Not authorized.';
    if (statusCode >= 500) {
      return 'Server error ($statusCode). Try again or check API logs.';
    }
    return 'Request failed ($statusCode).';
  }

  @override
  String toString() => 'ApiError($statusCode): $body';
}
