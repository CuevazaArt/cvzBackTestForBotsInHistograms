import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
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

  Future<void> exportCsv(String symbol, String timeframe, String dirPath) async {
    final candles = await queryRange(symbol, timeframe);
    if (candles.isEmpty) return;
    final file = File(p.join(dirPath, '${symbol}_$timeframe.csv'));
    final sink = file.openWrite();
    try {
      sink.writeln('timestamp_ms,open,high,low,close,volume');
      for (final c in candles) {
        sink.writeln('${c.timestampMs},${c.open},${c.high},${c.low},${c.close},${c.volume}');
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
  }

  Future<int> importCsv(File file) async {
    final name = p.basenameWithoutExtension(file.path);
    final parts = name.split('_');
    if (parts.length < 2) return 0;
    final timeframe = parts.last;
    final symbol = parts.sublist(0, parts.length - 1).join('_');

    final lines = await file.readAsLines();
    if (lines.length <= 1) return 0;

    final candles = <Candle>[];
    for (final line in lines.skip(1)) {
      final cols = line.split(',');
      if (cols.length < 6) continue;
      final ts = int.tryParse(cols[0]);
      final o = double.tryParse(cols[1]);
      final h = double.tryParse(cols[2]);
      final l = double.tryParse(cols[3]);
      final c = double.tryParse(cols[4]);
      final v = double.tryParse(cols[5]);
      if (ts == null || o == null || h == null || l == null || c == null || v == null) continue;
      candles.add(Candle(timestampMs: ts, open: o, high: h, low: l, close: c, volume: v));
    }
    if (candles.isEmpty) return 0;
    return insertBatch(symbol, timeframe, candles);
  }

  Future<int> importAllCsvs(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return 0;
    int total = 0;
    await for (final entity in dir.list()) {
      if (entity is File && entity.path.endsWith('.csv')) {
        total += await importCsv(entity);
      }
    }
    return total;
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
