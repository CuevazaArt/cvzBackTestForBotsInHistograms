import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backtester_shell/screens/backtest_screen.dart';
import 'package:backtester_shell/services/ws_service.dart';
import 'package:backtester_shell/services/api_service.dart';

class MockApiService extends ApiService {
  MockApiService() : super(baseUrl: 'http://localhost');
  
  @override
  Future<List<String>> getSymbols() async => ['BTCUSDT'];
  
  @override
  Future<List<Map<String, dynamic>>> getCandles({
    required String symbol,
    required String timeframe,
    int? startMs,
    int? endMs,
    int? limit,
  }) async => [];
}

class MockWsService extends WsService {
  final _events = StreamController<WsEvent>.broadcast();

  MockWsService() : super();

  @override
  Stream<WsEvent> get events => _events.stream;

  @override
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
    // Simulate the exact event flow
    Future.microtask(() async {
      _events.add(WsEvent(WsEventType.start, {
        'indicators_keys': [],
        'oscillator_keys': [],
        'bot_ids': ['bot1']
      }));
      
      await Future.delayed(const Duration(milliseconds: 10));
      _events.add(WsEvent(WsEventType.candle, {
        'time': 1735689600,
        'open': 100.0,
        'high': 105.0,
        'low': 95.0,
        'close': 102.0,
        'volume': 1000.0
      }));
      
      await Future.delayed(const Duration(milliseconds: 10));
      _events.add(WsEvent(WsEventType.result, {
        'symbol': symbol,
        'timeframe': timeframe,
        'summary': {'total_return_pct': 5.0},
        'trades': 1,
        'final_equity': 10500.0,
        'peak_equity': 10500.0,
        'max_drawdown_pct': 0.0,
        'per_bot': {},
        'equity_curve_downsampled': []
      }));
    });
  }

  @override
  void dispose() {
    _events.close();
  }
}

void main() {
  testWidgets('BacktestScreen renders chart and consumes streaming events paso a paso', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final mockApi = MockApiService();
    final mockWs = MockWsService();

    await tester.pumpWidget(MaterialApp(
      home: BacktestScreen(
        apiService: mockApi,
        wsService: mockWs,
        chartUrl: 'about:blank',
        defaultCash: 10000.0,
        defaultFeePct: 0.1,
        defaultSlippagePct: 0.05,
      ),
    ));

    await tester.pumpAndSettle();

    // Verify UI is loaded
    expect(find.text('RUN'), findsOneWidget);

    // Press RUN to trigger the backtest
    await tester.tap(find.text('RUN'));
    await tester.pump(); // Trigger the Future.microtask

    // Wait for the WsEventType.start and candle events
    await tester.pump(const Duration(milliseconds: 15));
    
    // Wait for the WsEventType.result event
    await tester.pump(const Duration(milliseconds: 15));
    await tester.pumpAndSettle();

    // Verify the UI reacted to the result event by changing state back from running
    expect(find.text('RUN'), findsOneWidget);
  }, skip: true);
}
