import 'position.dart';
import 'order.dart';

class Trade {
  final int id;
  final String botId;
  final PositionSide side;
  final double entryPrice;
  final double exitPrice;
  final double qty;
  final int entryTimestampMs;
  final int exitTimestampMs;
  final double pnl;
  final double pnlPct;
  final double fees;
  final double mfe;
  final double mae;
  final TriggerReason exitReason;

  const Trade({
    required this.id,
    required this.botId,
    required this.side,
    required this.entryPrice,
    required this.exitPrice,
    required this.qty,
    required this.entryTimestampMs,
    required this.exitTimestampMs,
    required this.pnl,
    required this.pnlPct,
    required this.fees,
    required this.mfe,
    required this.mae,
    required this.exitReason,
  });

  bool get isWin => pnl > 0;
  Duration get duration => Duration(
      milliseconds: exitTimestampMs - entryTimestampMs);

  Map<String, dynamic> toJson() => {
        'id': id,
        'bot_id': botId,
        'side': side.name,
        'entry_price': entryPrice,
        'exit_price': exitPrice,
        'qty': qty,
        'entry_time': entryTimestampMs,
        'exit_time': exitTimestampMs,
        'pnl': pnl,
        'pnl_pct': pnlPct,
        'fees': fees,
        'mfe': mfe,
        'mae': mae,
        'exit_reason': exitReason.name,
      };
}
