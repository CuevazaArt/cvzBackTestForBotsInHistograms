import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/backtest_result.dart';
import '../models/bot_spec.dart';
import '../services/api_client.dart';
import '../services/ws_client.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final apiClientProvider = Provider<ApiClient>((_) => defaultApiClient);

final wsClientProvider = Provider<WsClient>((_) => WsClient());

final botsProvider = FutureProvider<List<BotSpec>>((ref) {
  return ref.read(apiClientProvider).fetchBots();
});

final symbolsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) {
  return ref.read(apiClientProvider).fetchSymbols();
});

// ── Backtest config state ─────────────────────────────────────────────────────

class BacktestConfig {
  final String bot;
  final String symbol;
  final String timeframe;
  final Map<String, dynamic> params;
  final double initialCash;
  final double takerFeePct;
  final double slippagePct;
  final int? startMs;
  final int? endMs;

  const BacktestConfig({
    this.bot = 'EMACross',
    this.symbol = 'BTCUSDT',
    this.timeframe = '1h',
    this.params = const {},
    this.initialCash = 10000.0,
    this.takerFeePct = 0.05,
    this.slippagePct = 0.02,
    this.startMs,
    this.endMs,
  });

  BacktestConfig copyWith({
    String? bot,
    String? symbol,
    String? timeframe,
    Map<String, dynamic>? params,
    double? initialCash,
    double? takerFeePct,
    double? slippagePct,
    int? startMs,
    int? endMs,
  }) =>
      BacktestConfig(
        bot:          bot        ?? this.bot,
        symbol:       symbol     ?? this.symbol,
        timeframe:    timeframe  ?? this.timeframe,
        params:       params     ?? this.params,
        initialCash:  initialCash ?? this.initialCash,
        takerFeePct:  takerFeePct ?? this.takerFeePct,
        slippagePct:  slippagePct ?? this.slippagePct,
        startMs:      startMs    ?? this.startMs,
        endMs:        endMs      ?? this.endMs,
      );

  Map<String, dynamic> toJson() => {
        'bot': bot,
        'symbol': symbol,
        'timeframe': timeframe,
        'params': params,
        'initial_cash': initialCash,
        'taker_fee_pct': takerFeePct,
        'slippage_pct': slippagePct,
        if (startMs != null) 'start_ms': startMs,
        if (endMs != null)   'end_ms':   endMs,
      };
}

class BacktestConfigNotifier extends Notifier<BacktestConfig> {
  @override
  BacktestConfig build() => const BacktestConfig();

  void update(BacktestConfig cfg) => state = cfg;
  void setBot(String bot, [Map<String, dynamic>? params]) =>
      state = state.copyWith(bot: bot, params: params ?? state.params);
  void setSymbol(String s) => state = state.copyWith(symbol: s);
  void setTimeframe(String tf) => state = state.copyWith(timeframe: tf);
  void setParam(String key, dynamic val) =>
      state = state.copyWith(params: {...state.params, key: val});
  void setCash(double v) => state = state.copyWith(initialCash: v);
}

final configProvider =
    NotifierProvider<BacktestConfigNotifier, BacktestConfig>(BacktestConfigNotifier.new);

// ── Run state ─────────────────────────────────────────────────────────────────

enum RunStatus { idle, running, done, error }

class RunState {
  final RunStatus status;
  final BacktestResult? result;
  final String? errorMsg;
  final double progress;

  const RunState({
    this.status = RunStatus.idle,
    this.result,
    this.errorMsg,
    this.progress = 0,
  });

  RunState copyWith({
    RunStatus? status,
    BacktestResult? result,
    String? errorMsg,
    double? progress,
  }) =>
      RunState(
        status:   status   ?? this.status,
        result:   result   ?? this.result,
        errorMsg: errorMsg ?? this.errorMsg,
        progress: progress ?? this.progress,
      );
}

class RunNotifier extends Notifier<RunState> {
  @override
  RunState build() => const RunState();

  Future<void> run() async {
    final cfg = ref.read(configProvider);
    final api = ref.read(apiClientProvider);
    state = const RunState(status: RunStatus.running);
    try {
      final result = await api.runBacktest(
        bot:         cfg.bot,
        params:      cfg.params,
        symbol:      cfg.symbol,
        timeframe:   cfg.timeframe,
        initialCash: cfg.initialCash,
        takerFeePct: cfg.takerFeePct,
        slippagePct: cfg.slippagePct,
        startMs:     cfg.startMs,
        endMs:       cfg.endMs,
      );
      state = RunState(status: RunStatus.done, result: result, progress: 1.0);
    } catch (e) {
      state = RunState(status: RunStatus.error, errorMsg: e.toString());
    }
  }

  void reset() => state = const RunState();
}

final runProvider = NotifierProvider<RunNotifier, RunState>(RunNotifier.new);
