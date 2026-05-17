import 'package:drift/drift.dart';
import '../database.dart';
import '../../core/models/candle.dart';

part 'candles_dao.g.dart';

@DriftAccessor(tables: [CandlesTable])
class CandlesDao extends DatabaseAccessor<AppDatabase>
    with _$CandlesDaoMixin {
  CandlesDao(super.db);

  Future<int> insertBatch(
    String symbol,
    String timeframe,
    List<Candle> candles,
  ) async {
    int inserted = 0;
    await batch((b) {
      for (final c in candles) {
        b.insert(
          db.candlesTable,
          CandlesTableCompanion.insert(
            symbol: symbol,
            timeframe: timeframe,
            timestampMs: c.timestampMs,
            open: c.open,
            high: c.high,
            low: c.low,
            close: c.close,
            volume: c.volume,
          ),
          mode: InsertMode.insertOrIgnore,
        );
        inserted++;
      }
    });
    return inserted;
  }

  Future<List<Candle>> queryRange(
    String symbol,
    String timeframe, {
    int? fromMs,
    int? toMs,
  }) async {
    var q = select(db.candlesTable)
      ..where((t) => t.symbol.equals(symbol) & t.timeframe.equals(timeframe));
    if (fromMs != null) {
      q = q..where((t) => t.timestampMs.isBiggerOrEqualValue(fromMs));
    }
    if (toMs != null) {
      q = q..where((t) => t.timestampMs.isSmallerOrEqualValue(toMs));
    }
    q = q..orderBy([(t) => OrderingTerm.asc(t.timestampMs)]);
    final rows = await q.get();
    return rows.map(_rowToCandle).toList();
  }

  Future<int?> lastTimestampMs(String symbol, String timeframe) async {
    final q = selectOnly(db.candlesTable)
      ..addColumns([db.candlesTable.timestampMs])
      ..where(
        db.candlesTable.symbol.equals(symbol) &
            db.candlesTable.timeframe.equals(timeframe),
      )
      ..orderBy([
        OrderingTerm.desc(db.candlesTable.timestampMs),
      ])
      ..limit(1);
    final row = await q.getSingleOrNull();
    return row?.read(db.candlesTable.timestampMs);
  }

  Future<Map<String, List<String>>> availableSymbols() async {
    final q = selectOnly(db.candlesTable, distinct: true)
      ..addColumns([db.candlesTable.symbol, db.candlesTable.timeframe]);
    final rows = await q.get();
    final result = <String, List<String>>{};
    for (final row in rows) {
      final sym = row.read(db.candlesTable.symbol)!;
      final tf = row.read(db.candlesTable.timeframe)!;
      result.putIfAbsent(sym, () => []).add(tf);
    }
    return result;
  }

  Future<int> deleteSymbol(String symbol, String timeframe) async {
    return (delete(db.candlesTable)
          ..where(
            (t) => t.symbol.equals(symbol) & t.timeframe.equals(timeframe),
          ))
        .go();
  }

  Future<int> countCandles(String symbol, String timeframe) async {
    final count = db.candlesTable.timestampMs.count();
    final q = selectOnly(db.candlesTable)
      ..addColumns([count])
      ..where(
        db.candlesTable.symbol.equals(symbol) &
            db.candlesTable.timeframe.equals(timeframe),
      );
    return await q.map((r) => r.read(count)!).getSingle();
  }

  Candle _rowToCandle(CandlesTableData row) => Candle(
        timestampMs: row.timestampMs,
        open: row.open,
        high: row.high,
        low: row.low,
        close: row.close,
        volume: row.volume,
      );
}
