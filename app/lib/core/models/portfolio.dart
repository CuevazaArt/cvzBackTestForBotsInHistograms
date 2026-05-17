import 'position.dart';
import 'trade.dart';
import 'order.dart';

class Portfolio {
  double cash;
  final List<Position> positions;
  final List<Trade> trades;
  final List<PendingOrder> pendingOrders;
  final List<double> equityCurve;

  Portfolio({
    required this.cash,
    List<Position>? positions,
    List<Trade>? trades,
    List<PendingOrder>? pendingOrders,
    List<double>? equityCurve,
  })  : positions = positions ?? [],
        trades = trades ?? [],
        pendingOrders = pendingOrders ?? [],
        equityCurve = equityCurve ?? [];

  double get positionsValue => positions.fold(
      0.0, (sum, p) => sum + p.qty * p.entryPrice);

  double equity(double currentPrice) =>
      cash +
      positions.fold(0.0, (sum, p) {
        if (p.side == PositionSide.long) {
          return sum + p.qty * currentPrice;
        } else {
          return sum + p.qty * (2 * p.entryPrice - currentPrice);
        }
      });

  List<Position> positionsForBot(String botId) =>
      positions.where((p) => p.botId == botId).toList();
}
