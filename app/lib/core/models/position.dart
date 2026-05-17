enum PositionSide { long, short }

class Position {
  final int id;
  final String botId;
  final PositionSide side;
  final double entryPrice;
  final int entryTimestampMs;

  /// Remaining open quantity. Decreases on partial closes.
  double qty;

  /// Accrued entry fee. Reduced proportionally on partial closes.
  double fee;

  /// Max Favorable Excursion (%): best paper gain since entry.
  double mfe;

  /// Max Adverse Excursion (%): worst paper loss since entry.
  double mae;

  Position({
    required this.id,
    required this.botId,
    required this.side,
    required this.entryPrice,
    required this.qty,
    required this.entryTimestampMs,
    required this.fee,
    this.mfe = 0.0,
    this.mae = 0.0,
  });

  void updateExcursion(double currentPrice) {
    final pnlPct = side == PositionSide.long
        ? (currentPrice - entryPrice) / entryPrice * 100
        : (entryPrice - currentPrice) / entryPrice * 100;
    if (pnlPct > mfe) mfe = pnlPct;
    if (pnlPct < mae) mae = pnlPct;
  }
}
