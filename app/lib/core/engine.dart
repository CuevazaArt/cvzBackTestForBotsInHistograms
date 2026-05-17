import 'models/candle.dart';
import 'models/order.dart';
import 'models/portfolio.dart';
import 'models/position.dart';
import 'models/trade.dart';
import 'models/backtest_result.dart';
import 'config.dart';
import 'order_matcher.dart';
import 'bracket_manager.dart';
import '../bots/bot_base.dart';

class BacktestEngine {
  final BacktestConfig config;

  int _positionIdSeq = 0;
  int _orderIdSeq = 0;
  int _tradeIdSeq = 0;
  double _peakEquity = 0;
  bool _haltedByCircuit = false;

  BacktestEngine({BacktestConfig? config})
      : config = config ?? const BacktestConfig();

  int _nextPositionId() => ++_positionIdSeq;
  int _nextOrderId() => ++_orderIdSeq;
  int _nextTradeId() => ++_tradeIdSeq;

  /// Runs [bots] over [candles] and returns the final BacktestResult.
  ///
  /// If [perCandle] is provided, it's invoked after each bar with
  /// the current bar index — used by the streaming layer to emit events.
  BacktestResult run({
    required List<BotBase> bots,
    required List<Candle> candles,
    void Function(int index, Portfolio portfolio)? perCandle,
  }) {
    if (candles.isEmpty || bots.isEmpty) {
      return _emptyResult(candles);
    }

    // One portfolio per bot — capital split equally for now.
    final capitalPerBot = config.initialCash / bots.length;
    final portfolios = <String, Portfolio>{
      for (final b in bots) b.id: Portfolio(cash: capitalPerBot),
    };

    // Let each bot precompute indicators over the full series.
    for (final bot in bots) {
      bot.prepareIndicators(candles);
    }

    _peakEquity = config.initialCash;
    _haltedByCircuit = false;

    // Combined equity curve (sum across bots).
    final aggregateEquity = <double>[];

    for (int i = 0; i < candles.length; i++) {
      final candle = candles[i];

      // 1) Update MFE/MAE + trailing anchors on every position.
      for (final pf in portfolios.values) {
        for (final pos in pf.positions) {
          pos.updateExcursion(candle.close);
        }
        for (final po in pf.pendingOrders) {
          OrderMatcher.updateTrailingAnchor(po, candle.high, candle.low);
        }
      }

      // 2) Process pending orders (limit/stop fills) BEFORE bot decisions.
      for (final entry in portfolios.entries) {
        _processPendingOrders(entry.value, candle);
      }

      // 3) Check circuit breaker (halt new entries if drawdown exceeds threshold).
      final aggregateCurrent = portfolios.values
          .fold(0.0, (s, pf) => s + pf.equity(candle.close));
      if (aggregateCurrent > _peakEquity) _peakEquity = aggregateCurrent;
      final ddPct =
          (_peakEquity - aggregateCurrent) / _peakEquity * 100;
      if (config.maxDrawdownHaltPct != null &&
          ddPct >= config.maxDrawdownHaltPct!) {
        _haltedByCircuit = true;
      }

      // 4) Each bot decides on the bar.
      if (!_haltedByCircuit) {
        for (final bot in bots) {
          final pf = portfolios[bot.id]!;
          final orders = bot.onCandle(candle, pf);
          for (final req in orders) {
            _routeOrder(req, pf, candle);
          }
        }
      }

      aggregateEquity.add(aggregateCurrent);
      perCandle?.call(i, portfolios.values.first);
    }

    // Force-close remaining open positions at the final candle's close.
    final lastCandle = candles.last;
    for (final pf in portfolios.values) {
      final openPositions = List<Position>.from(pf.positions);
      for (final pos in openPositions) {
        _closePosition(
          pf: pf,
          position: pos,
          exitPrice: lastCandle.close,
          exitTsMs: lastCandle.timestampMs,
          reason: TriggerReason.manual,
        );
      }
    }

    return _aggregateResult(
      bots: bots,
      candles: candles,
      portfolios: portfolios,
      equityCurve: aggregateEquity,
    );
  }

  // ─── Order routing ────────────────────────────────────────────────────────

  void _routeOrder(OrderRequest req, Portfolio pf, Candle bar) {
    if (req.qty <= 0) return;

    if (req.type == OrderType.market) {
      // Fill immediately. fillOnNextOpen handled by caller (engine_stream).
      _fillMarket(req, pf, bar);
      return;
    }

    // Non-market orders go to pending queue.
    pf.pendingOrders.add(PendingOrder(
      id: _nextOrderId(),
      side: req.side,
      action: req.action,
      qty: req.qty,
      type: req.type,
      limitPrice: req.limitPrice,
      stopPrice: req.stopPrice,
      trailingPct: req.trailingPct,
      trailingAnchor: req.type == OrderType.trailingStop ? bar.close : null,
      botId: req.botId,
      fillReason: req.type == OrderType.limit
          ? TriggerReason.limitFill
          : TriggerReason.marketEntry,
      bracket: req.bracket,
    ));
  }

  void _fillMarket(OrderRequest req, Portfolio pf, Candle bar) {
    final refPrice = bar.close;
    switch (req.action) {
      case OrderAction.openLong:
        _openPosition(
          pf: pf,
          botId: req.botId,
          side: PositionSide.long,
          qty: req.qty,
          refPrice: refPrice,
          entryTsMs: bar.timestampMs,
          bracket: req.bracket,
        );
        break;
      case OrderAction.closeLong:
        _closeLongFifo(pf, req.qty, refPrice, bar.timestampMs,
            TriggerReason.manual);
        break;
      case OrderAction.openShort:
        _openPosition(
          pf: pf,
          botId: req.botId,
          side: PositionSide.short,
          qty: req.qty,
          refPrice: refPrice,
          entryTsMs: bar.timestampMs,
          bracket: req.bracket,
        );
        break;
      case OrderAction.closeShort:
        _closeShortFifo(pf, req.qty, refPrice, bar.timestampMs,
            TriggerReason.manual);
        break;
    }
  }

  // ─── Pending order processing ─────────────────────────────────────────────

  void _processPendingOrders(Portfolio pf, Candle bar) {
    final toRemove = <PendingOrder>[];
    for (final po in List<PendingOrder>.from(pf.pendingOrders)) {
      final triggers = _checkTrigger(po, bar);
      if (!triggers) continue;

      final fillPrice = _resolveFillPrice(po, bar);
      _fillPending(po, pf, fillPrice, bar.timestampMs);
      toRemove.add(po);
    }
    pf.pendingOrders.removeWhere(toRemove.contains);
  }

  bool _checkTrigger(PendingOrder po, Candle bar) {
    switch (po.type) {
      case OrderType.limit:
        return OrderMatcher.limitTriggers(po, bar.high, bar.low);
      case OrderType.stop:
      case OrderType.trailingStop:
        return OrderMatcher.stopTriggers(po, bar.high, bar.low);
      case OrderType.stopLimit:
        // Trigger phase only; once triggered, fill at limit if reachable.
        if (!OrderMatcher.stopTriggers(po, bar.high, bar.low)) return false;
        return OrderMatcher.limitTriggers(po, bar.high, bar.low);
      case OrderType.market:
        return true;
    }
  }

  double _resolveFillPrice(PendingOrder po, Candle bar) {
    switch (po.type) {
      case OrderType.limit:
      case OrderType.stopLimit:
        return po.limitPrice ?? bar.close;
      case OrderType.stop:
      case OrderType.trailingStop:
        return po.stopPrice ?? bar.close;
      case OrderType.market:
        return bar.close;
    }
  }

  void _fillPending(
      PendingOrder po, Portfolio pf, double refPrice, int tsMs) {
    switch (po.action) {
      case OrderAction.openLong:
        _openPosition(
          pf: pf,
          botId: po.botId,
          side: PositionSide.long,
          qty: po.qty,
          refPrice: refPrice,
          entryTsMs: tsMs,
          bracket: po.bracket,
        );
        break;
      case OrderAction.closeLong:
        _closeLongFifo(pf, po.qty, refPrice, tsMs, po.fillReason);
        break;
      case OrderAction.openShort:
        _openPosition(
          pf: pf,
          botId: po.botId,
          side: PositionSide.short,
          qty: po.qty,
          refPrice: refPrice,
          entryTsMs: tsMs,
          bracket: po.bracket,
        );
        break;
      case OrderAction.closeShort:
        _closeShortFifo(pf, po.qty, refPrice, tsMs, po.fillReason);
        break;
    }
  }

  // ─── Position lifecycle ───────────────────────────────────────────────────

  void _openPosition({
    required Portfolio pf,
    required String botId,
    required PositionSide side,
    required double qty,
    required double refPrice,
    required int entryTsMs,
    BracketSpec? bracket,
  }) {
    final fillPrice = side == PositionSide.long
        ? config.applyBuySlippage(refPrice)
        : config.applySellSlippage(refPrice);
    final notional = fillPrice * qty;
    final fee = config.computeFee(notional);

    // For long positions, must have cash. Shorts are simulated (no margin
    // model in this baseline — they post the same notional as collateral).
    if (pf.cash < notional + fee) return;
    pf.cash -= notional + fee;

    final pos = Position(
      id: _nextPositionId(),
      botId: botId,
      side: side,
      entryPrice: fillPrice,
      qty: qty,
      entryTimestampMs: entryTsMs,
      fee: fee,
    );
    pf.positions.add(pos);

    // Attach bracket children if specified.
    if (bracket != null && !bracket.isEmpty) {
      final children = BracketManager.createChildren(
        position: pos,
        spec: bracket,
        nextId: _nextOrderId,
      );
      pf.pendingOrders.addAll(children);
    }
  }

  void _closeLongFifo(
      Portfolio pf, double qty, double refPrice, int tsMs, TriggerReason reason) {
    double remaining = qty;
    final longs = pf.positions.where((p) => p.side == PositionSide.long).toList();
    for (final pos in longs) {
      if (remaining <= 0) break;
      final closeQty = remaining >= pos.qty ? pos.qty : remaining;
      _closePartial(
        pf: pf,
        position: pos,
        closeQty: closeQty,
        exitPrice: refPrice,
        exitTsMs: tsMs,
        reason: reason,
      );
      remaining -= closeQty;
    }
  }

  void _closeShortFifo(
      Portfolio pf, double qty, double refPrice, int tsMs, TriggerReason reason) {
    double remaining = qty;
    final shorts = pf.positions.where((p) => p.side == PositionSide.short).toList();
    for (final pos in shorts) {
      if (remaining <= 0) break;
      final closeQty = remaining >= pos.qty ? pos.qty : remaining;
      _closePartial(
        pf: pf,
        position: pos,
        closeQty: closeQty,
        exitPrice: refPrice,
        exitTsMs: tsMs,
        reason: reason,
      );
      remaining -= closeQty;
    }
  }

  void _closePartial({
    required Portfolio pf,
    required Position position,
    required double closeQty,
    required double exitPrice,
    required int exitTsMs,
    required TriggerReason reason,
  }) {
    final fillPrice = position.side == PositionSide.long
        ? config.applySellSlippage(exitPrice)
        : config.applyBuySlippage(exitPrice);
    final notional = fillPrice * closeQty;
    final exitFee = config.computeFee(notional);

    // PnL: positive if long & exit > entry; if short & exit < entry.
    final pnl = position.side == PositionSide.long
        ? (fillPrice - position.entryPrice) * closeQty - exitFee - position.fee
        : (position.entryPrice - fillPrice) * closeQty - exitFee - position.fee;
    final pnlPct = position.entryPrice > 0
        ? (position.side == PositionSide.long
                ? (fillPrice - position.entryPrice) / position.entryPrice
                : (position.entryPrice - fillPrice) / position.entryPrice) *
            100
        : 0.0;

    // Return notional + pnl to cash (for shorts: original notional was held).
    pf.cash += notional - exitFee;
    if (position.side == PositionSide.short) {
      // Short P/L is realized vs the entry notional we held as collateral.
      // Adjustment: we already deducted entry notional on open; pnl is added on top.
      pf.cash += pnl;
    }

    final trade = Trade(
      id: _nextTradeId(),
      botId: position.botId,
      side: position.side,
      entryPrice: position.entryPrice,
      exitPrice: fillPrice,
      qty: closeQty,
      entryTimestampMs: position.entryTimestampMs,
      exitTimestampMs: exitTsMs,
      pnl: pnl,
      pnlPct: pnlPct,
      fees: position.fee + exitFee,
      mfe: position.mfe,
      mae: position.mae,
      exitReason: reason,
    );
    pf.trades.add(trade);

    // Partial vs full close.
    if (closeQty >= position.qty) {
      pf.positions.remove(position);
      // Cancel bracket children attached to this position.
      pf.pendingOrders.removeWhere(
          (po) => po.parentPositionId == position.id);
    } else {
      final remainingFraction = (position.qty - closeQty) / position.qty;
      position.fee *= remainingFraction;
      position.qty -= closeQty;
    }
  }

  void _closePosition({
    required Portfolio pf,
    required Position position,
    required double exitPrice,
    required int exitTsMs,
    required TriggerReason reason,
  }) {
    _closePartial(
      pf: pf,
      position: position,
      closeQty: position.qty,
      exitPrice: exitPrice,
      exitTsMs: exitTsMs,
      reason: reason,
    );
  }

  // ─── Result aggregation ───────────────────────────────────────────────────

  BacktestResult _aggregateResult({
    required List<BotBase> bots,
    required List<Candle> candles,
    required Map<String, Portfolio> portfolios,
    required List<double> equityCurve,
  }) {
    final allTrades = <Trade>[];
    final perBot = <String, BotBreakdown>{};
    double finalEquity = 0;
    for (final entry in portfolios.entries) {
      allTrades.addAll(entry.value.trades);
      final botPnl =
          entry.value.trades.fold(0.0, (s, t) => s + t.pnl);
      final botWins = entry.value.trades.where((t) => t.isWin).length;
      final botCount = entry.value.trades.length;
      perBot[entry.key] = BotBreakdown(
        botId: entry.key,
        tradeCount: botCount,
        pnl: botPnl,
        winRate: botCount > 0 ? botWins / botCount * 100 : 0,
      );
      finalEquity += entry.value.cash;
    }

    return BacktestResult(
      runId: 'run_${DateTime.now().millisecondsSinceEpoch}',
      startTimestampMs: candles.first.timestampMs,
      endTimestampMs: candles.last.timestampMs,
      totalCandles: candles.length,
      initialCash: config.initialCash,
      finalEquity: finalEquity,
      trades: allTrades,
      equityCurve: equityCurve,
      perBot: perBot,
    );
  }

  BacktestResult _emptyResult(List<Candle> candles) => BacktestResult(
        runId: 'run_empty',
        startTimestampMs: candles.isEmpty ? 0 : candles.first.timestampMs,
        endTimestampMs: candles.isEmpty ? 0 : candles.last.timestampMs,
        totalCandles: candles.length,
        initialCash: config.initialCash,
        finalEquity: config.initialCash,
        trades: const [],
        equityCurve: const [],
        perBot: const {},
      );
}
