/// WsService unit tests — B5 fakeAsync suite.
///
/// Tests that can run without a live WebSocket server:
///   - Outbound buffer (capacity, overflow/drop policy)
///   - Exponential reconnect-delay formula
///   - Status lifecycle on explicit disconnect
///
/// Timer-sensitive tests use [fakeAsync] so they never block on real I/O
/// or wall-clock delays; the clock is advanced deterministically.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:backtester_shell/services/ws_service.dart';

void main() {
  // ── Status lifecycle ──────────────────────────────────────────

  test('initial status is disconnected', () {
    final svc = WsService();
    expect(svc.status.value, WsStatus.disconnected);
    expect(svc.pendingOutbound, 0);
  });

  test('disconnect() resets status and clears buffer', () async {
    final svc = WsService();
    svc.send({'action': 'backtest'});
    expect(svc.pendingOutbound, 1);
    await svc.disconnect();
    expect(svc.status.value, WsStatus.disconnected);
    expect(svc.pendingOutbound, 0);
  });

  // ── Outbound buffer ───────────────────────────────────────────

  test('send() while disconnected buffers the message', () {
    fakeAsync((_) {
      final svc = WsService();
      svc.send({'action': 'ping'});
      expect(svc.pendingOutbound, 1);
    });
  });

  test('buffer capacity is 128 and drops oldest on overflow', () {
    fakeAsync((_) {
      final svc = WsService();
      for (int i = 0; i < 130; i++) {
        svc.send({'seq': i});
      }
      // Oldest 2 messages were dropped; 128 remain.
      expect(svc.pendingOutbound, 128);
    });
  });

  test('events stream is lazy-initialised before connect()', () {
    final svc = WsService();
    // Accessing .events before connect() must not throw.
    final stream = svc.events;
    expect(stream, isNotNull);
  });

  // ── Reconnect backoff formula ─────────────────────────────────

  test('reconnect delay follows exponential backoff', () {
    // 500 × 2^(attempt-1), clamped to [500, 15000] ms
    expect(WsService.reconnectDelayMs(1), 500);
    expect(WsService.reconnectDelayMs(2), 1000);
    expect(WsService.reconnectDelayMs(3), 2000);
    expect(WsService.reconnectDelayMs(4), 4000);
    expect(WsService.reconnectDelayMs(5), 8000);
    expect(WsService.reconnectDelayMs(6), 15000); // 16 000 → clamped
    expect(WsService.reconnectDelayMs(10), 15000); // far beyond cap
  });

  test('first reconnect delay is under 1 second', () {
    expect(WsService.reconnectDelayMs(1), lessThan(1000));
  });

  test('reconnect delay is always at least 500 ms', () {
    for (int i = 1; i <= 12; i++) {
      expect(WsService.reconnectDelayMs(i), greaterThanOrEqualTo(500));
    }
  });

  // ── fakeAsync: buffer/status interaction with Timer ──────────

  test('disconnect inside fakeAsync clears timer state', () {
    fakeAsync((async) {
      final svc = WsService();
      // Fill the buffer.
      for (int i = 0; i < 5; i++) {
        svc.send({'i': i});
      }
      expect(svc.pendingOutbound, 5);

      // Disconnect (sync + cancels reconnect timer if any).
      svc.disconnect();
      async.flushMicrotasks();

      expect(svc.status.value, WsStatus.disconnected);
      expect(svc.pendingOutbound, 0);
    });
  });
}
