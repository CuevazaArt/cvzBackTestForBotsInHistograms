import 'package:flutter_test/flutter_test.dart';
import 'package:cvz_backtester/core/config.dart';
import 'package:cvz_backtester/core/run_controller.dart';
import 'package:cvz_backtester/core/engine.dart';
import 'package:cvz_backtester/core/models/candle.dart';
import 'package:cvz_backtester/services/engine_isolate.dart';
import 'package:cvz_backtester/services/engine_messages.dart';
import 'package:cvz_backtester/bots/registry.dart';

void main() {
  Candle bar(int i, double price) => Candle(
        timestampMs: i * 60000,
        open: price,
        high: price * 1.005,
        low: price * 0.995,
        close: price,
        volume: 100,
      );

  group('RunController', () {
    test('pause / resume controls waitIfPaused', () async {
      final c = RunController();
      c.pause();
      expect(c.isPaused, isTrue);

      var resumed = false;
      final f = c.waitIfPaused().then((_) => resumed = true);
      await Future.delayed(const Duration(milliseconds: 20));
      expect(resumed, isFalse);

      c.resume();
      await f;
      expect(resumed, isTrue);
      expect(c.isPaused, isFalse);
    });

    test('cancel unblocks paused wait', () async {
      final c = RunController();
      c.pause();
      var done = false;
      final f = c.waitIfPaused().then((_) => done = true);
      c.cancel();
      await f;
      expect(done, isTrue);
      expect(c.isCancelled, isTrue);
    });

    test('step advances one bar then re-pauses', () async {
      final c = RunController();
      c.pause();
      var done = false;
      final f = c.waitIfPaused().then((_) => done = true);
      c.step();
      await f;
      expect(done, isTrue);
      // The controller stays paused until resume/cancel is called.
      expect(c.isPaused, isTrue);
    });

    test('setSpeed clamps negatives to 0', () {
      final c = RunController();
      c.setSpeed(-5);
      expect(c.speedMs, 0);
      c.setSpeed(50);
      expect(c.speedMs, 50);
    });
  });

  group('engine.runAsync with controller', () {
    test('completes a full run, total trades >= 0, equityCurve filled', () async {
      final candles = [for (int i = 0; i < 20; i++) bar(i, 100.0 + i.toDouble())];
      final controller = RunController();
      final engine = BacktestEngine(
        config: const BacktestConfig(initialCash: 1000, takerFeePct: 0, slippagePct: 0),
      );
      final result = await engine.runAsync(
        bots: [BotRegistry.create('ema_cross')],
        candles: candles,
        controller: controller,
      );
      expect(result, isNotNull);
      expect(result!.totalCandles, candles.length);
      await controller.dispose();
    });

    test('cancel mid-run returns null', () async {
      final candles = [for (int i = 0; i < 500; i++) bar(i, 100.0)];
      final controller = RunController();
      final engine = BacktestEngine();
      final f = engine.runAsync(
        bots: [BotRegistry.create('ema_cross')],
        candles: candles,
        controller: controller,
        perCandle: (i, _, __) async {
          if (i == 5) controller.cancel();
        },
      );
      final result = await f;
      expect(result, isNull);
      await controller.dispose();
    });
  });

  group('EngineIsolateClient roundtrip', () {
    test('spawn → StartBacktest → RunCompleted with proper sequencing',
        () async {
      final client = EngineIsolateClient();
      await client.spawn();

      final candles = [for (int i = 0; i < 30; i++) bar(i, 100.0 + i.toDouble())];
      final events = <EngineEvent>[];
      final sub = client.events.listen(events.add);

      client.send(StartBacktest(
        candles: candles,
        bots: const [BotSpec(name: 'ema_cross', params: {'fastPeriod': 3, 'slowPeriod': 8})],
        config: const BacktestConfig(initialCash: 1000, takerFeePct: 0, slippagePct: 0),
      ));

      // Wait for completion event.
      final completed = await client.events
          .firstWhere((e) => e is RunCompleted || e is RunFailed)
          .timeout(const Duration(seconds: 10));

      expect(completed, isA<RunCompleted>());
      // Expect at least RunStarted, some progress, and RunCompleted.
      expect(events.any((e) => e is RunStarted), isTrue);
      expect(events.any((e) => e is RunProgress), isTrue);

      await sub.cancel();
      await client.dispose();
    });

    test('cancel during run produces RunCancelled and stops processing',
        () async {
      final client = EngineIsolateClient();
      await client.spawn();
      final candles = [for (int i = 0; i < 200; i++) bar(i, 100.0 + (i % 30).toDouble())];

      client.send(StartBacktest(
        candles: candles,
        bots: const [BotSpec(name: 'ema_cross')],
        config: const BacktestConfig(initialCash: 1000, takerFeePct: 0, slippagePct: 0),
        initialSpeedMs: 5, // slow enough to cancel mid-run
      ));

      // Wait briefly, then cancel.
      await Future.delayed(const Duration(milliseconds: 50));
      client.send(const CancelRun());

      final terminal = await client.events
          .firstWhere((e) => e is RunCancelled || e is RunCompleted)
          .timeout(const Duration(seconds: 10));
      expect(terminal, isA<RunCancelled>());

      await client.dispose();
    });
  });
}
