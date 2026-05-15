import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/backtest_result.dart';
import '../models/bot_spec.dart';

class ApiClient {
  final String baseUrl;
  final String? token;

  const ApiClient({this.baseUrl = 'http://127.0.0.1:8000', this.token});

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<T> _get<T>(String path, T Function(dynamic) parse) async {
    final resp = await http.get(Uri.parse('$baseUrl$path'), headers: _headers);
    _check(resp);
    return parse(jsonDecode(resp.body));
  }

  Future<T> _post<T>(String path, Map<String, dynamic> body, T Function(dynamic) parse) async {
    final resp = await http.post(
      Uri.parse('$baseUrl$path'),
      headers: _headers,
      body: jsonEncode(body),
    );
    _check(resp);
    return parse(jsonDecode(resp.body));
  }

  void _check(http.Response r) {
    if (r.statusCode >= 400) {
      throw ApiException(r.statusCode, r.body);
    }
  }

  // ── Bots ─────────────────────────────────────────────────────────────────
  // GET /api/bots now returns [{name, description, params: {key: ParamSpec}}]

  Future<List<BotSpec>> fetchBots() => _get(
        '/api/bots',
        (j) => (j as List)
            .map((b) => BotSpec.fromJson(b as Map<String, dynamic>))
            .toList(),
      );

  // ── Candles ───────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchSymbols() => _get(
        '/api/candles/symbols',
        (j) => (j as List).cast<Map<String, dynamic>>(),
      );

  Future<String> downloadCandles({
    required String symbol,
    required String timeframe,
    required String dateFrom,
    required String dateTo,
  }) =>
      _post(
        '/api/candles/download',
        {'symbol': symbol, 'timeframe': timeframe, 'date_from': dateFrom, 'date_to': dateTo},
        (j) => (j as Map<String, dynamic>)['job_id'] as String,
      );

  Future<Map<String, dynamic>> fetchJobStatus(String jobId) =>
      _get('/api/candles/download/$jobId', (j) => (j as Map<String, dynamic>));

  // ── Backtest ──────────────────────────────────────────────────────────────

  Future<BacktestResult> runBacktest({
    required String bot,
    required Map<String, dynamic> params,
    required String symbol,
    required String timeframe,
    double initialCash = 10000.0,
    double takerFeePct = 0.1,
    double slippagePct = 0.05,
    int? startMs,
    int? endMs,
  }) =>
      _post(
        '/api/backtest/run',
        {
          'bot':           bot,
          'params':        params,
          'symbol':        symbol,
          'timeframe':     timeframe,
          'initial_cash':  initialCash,
          'taker_fee_pct': takerFeePct,
          'slippage_pct':  slippagePct,
          if (startMs != null) 'start_ms': startMs,
          if (endMs != null)   'end_ms':   endMs,
        },
        (j) => BacktestResult.fromJson(j as Map<String, dynamic>),
      );

  // ── Credentials ───────────────────────────────────────────────────────────

  Future<bool> credentialsExist() => _get(
        '/api/credentials',
        (j) => (j as Map<String, dynamic>)['exists'] as bool,
      );

  Future<void> saveCredentials(String apiKey, String apiSecret) => _post(
        '/api/credentials',
        {'api_key': apiKey, 'api_secret': apiSecret},
        (_) {},
      );
}

class ApiException implements Exception {
  final int statusCode;
  final String body;
  ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode): $body';
}

final _defaultClient = ApiClient();
ApiClient get defaultApiClient => _defaultClient;
