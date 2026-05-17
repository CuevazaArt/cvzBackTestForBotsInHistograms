import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'daos/candles_dao.dart';
import 'daos/results_dao.dart';
import 'daos/presets_dao.dart';

part 'database.g.dart';

class CandlesTable extends Table {
  TextColumn get symbol => text()();
  TextColumn get timeframe => text()();
  IntColumn get timestampMs => integer()();
  RealColumn get open => real()();
  RealColumn get high => real()();
  RealColumn get low => real()();
  RealColumn get close => real()();
  RealColumn get volume => real()();

  @override
  Set<Column> get primaryKey => {symbol, timeframe, timestampMs};
}

class ResultsTable extends Table {
  TextColumn get runId => text()();
  IntColumn get createdAt => integer()();
  TextColumn get configJson => text()();
  TextColumn get metricsJson => text()();
  TextColumn get tradesJson => text()();

  @override
  Set<Column> get primaryKey => {runId};
}

class PresetsTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get botName => text()();
  TextColumn get paramsYaml => text()();
  IntColumn get updatedAt => integer()();
}

@DriftDatabase(
  tables: [CandlesTable, ResultsTable, PresetsTable],
  daos: [CandlesDao, ResultsDao, PresetsDao],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase._internal(super.e);

  static Future<AppDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    final dbPath = p.join(dir.path, 'cvz_backtester.db');
    final file = File(dbPath);
    return AppDatabase._internal(
      NativeDatabase.createInBackground(file, setup: (db) {
        db.execute('PRAGMA journal_mode=WAL');
        db.execute('PRAGMA synchronous=NORMAL');
        db.execute('PRAGMA foreign_keys=ON');
      }),
    );
  }

  static AppDatabase inMemory() => AppDatabase._internal(
        NativeDatabase.memory(setup: (db) {
          db.execute('PRAGMA foreign_keys=ON');
        }),
      );

  @override
  int get schemaVersion => 1;

  late final CandlesDao candles = CandlesDao(this);
  late final ResultsDao results = ResultsDao(this);
  late final PresetsDao presets = PresetsDao(this);
}
