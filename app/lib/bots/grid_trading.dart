import 'dart:math' as math;
import '../core/models/candle.dart';
import '../core/models/order.dart';
import '../core/models/portfolio.dart';
import 'bot_base.dart';

/// Grid trading: places buy orders at evenly-spaced levels below current price
/// and sells at the next grid level above. Profits from sideways oscillation.
class GridTrading extends BotBase {
  final double gridSpacingPct;
  final int gridLevels;
  final double quotePerGrid;
  final double stopLossPct;

  @override
  final String id;
  @override
  final String name;

  double? _basePrice;
  final Set<int> _filledBuyLevels = {};

  GridTrading({
    this.id = 'grid_trading',
    this.name = 'Grid Trading',
    this.gridSpacingPct = 1.0,
    this.gridLevels = 5,
    this.quotePerGrid = 100.0,
    this.stopLossPct = 10.0,
  });

  @override
  Map<String, dynamic> get params => {
        'gridSpacingPct': gridSpacingPct,
        'gridLevels': gridLevels,
        'quotePerGrid': quotePerGrid,
        'stopLossPct': stopLossPct,
      };

  @override
  List<BotParamSpec> paramSpec() => const [
        BotParamSpec(name: 'gridSpacingPct', label: 'Grid Spacing %', type: BotParamType.percent, defaultValue: 1.0, min: 0.1, max: 10.0, step: 0.1),
        BotParamSpec(name: 'gridLevels', label: 'Grid Levels', type: BotParamType.intParam, defaultValue: 5, min: 2, max: 20, step: 1),
        BotParamSpec(name: 'quotePerGrid', label: 'USDT per grid', type: BotParamType.doubleParam, defaultValue: 100.0, min: 10.0, max: 10000.0, step: 10.0),
        BotParamSpec(name: 'stopLossPct', label: 'Stop Loss %', type: BotParamType.percent, defaultValue: 10.0, min: 0.0, max: 50.0, step: 1.0),
      ];

  double _gridPrice(int level) =>
      _basePrice! * (1 - gridSpacingPct / 100 * level);

  @override
  List<OrderRequest> onCandle(Candle candle, Portfolio portfolio) {
    final price = candle.close;
    final orders = <OrderRequest>[];

    if (_basePrice == null) {
      _basePrice = price;
      return const [];
    }

    // Global stop-loss: liquidate everything
    if (stopLossPct > 0) {
      final lowestGrid = _gridPrice(gridLevels);
      final slPrice = lowestGrid * (1 - stopLossPct / 100);
      if (price < slPrice && _filledBuyLevels.isNotEmpty) {
        final qty = maxSellQty(portfolio);
        if (qty > 0) {
          orders.add(OrderRequest.closeLong(botId: id, qty: qty));
        }
        _filledBuyLevels.clear();
        _basePrice = price;
        return orders;
      }
    }

    // Check each grid level
    for (int level = 1; level <= gridLevels; level++) {
      final gridPx = _gridPrice(level);
      final sellPx = _gridPrice(level - 1);

      // Buy at grid level
      if (!_filledBuyLevels.contains(level) && price <= gridPx) {
        final actualUsdt = math.min(portfolio.cash, quotePerGrid);
        final qty = price > 0 ? actualUsdt / price : 0.0;
        if (qty > 0) {
          orders.add(OrderRequest.openLong(botId: id, qty: qty));
          _filledBuyLevels.add(level);
        }
      }

      // Sell at the grid level above
      if (_filledBuyLevels.contains(level) && price >= sellPx) {
        final posQty = price > 0 ? quotePerGrid / _gridPrice(level) : 0.0;
        final sellQty = math.min(posQty, maxSellQty(portfolio));
        if (sellQty > 0) {
          orders.add(OrderRequest.closeLong(botId: id, qty: sellQty));
          _filledBuyLevels.remove(level);
        }
      }
    }

    return orders;
  }

  @override
  BotState? state() => BotState(
        phase: _basePrice == null ? 'idle' : 'live',
        decision: _filledBuyLevels.isEmpty ? 'flat' : 'grid_active',
        indicators: {
          'filled_levels': _filledBuyLevels.length.toDouble(),
          'base_price': ?_basePrice,
        },
      );
}
