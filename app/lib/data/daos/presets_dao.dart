import 'package:drift/drift.dart';
import '../database.dart';

part 'presets_dao.g.dart';

class BotPreset {
  final int? id;
  final String name;
  final String botName;
  final String paramsYaml;
  final DateTime updatedAt;

  const BotPreset({
    this.id,
    required this.name,
    required this.botName,
    required this.paramsYaml,
    required this.updatedAt,
  });
}

@DriftAccessor(tables: [PresetsTable])
class PresetsDao extends DatabaseAccessor<AppDatabase>
    with _$PresetsDaoMixin {
  PresetsDao(super.db);

  Future<List<BotPreset>> listAll() async {
    final rows = await (select(db.presetsTable)
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
    return rows.map(_rowToPreset).toList();
  }

  Future<List<BotPreset>> listForBot(String botName) async {
    final rows = await (select(db.presetsTable)
          ..where((t) => t.botName.equals(botName))
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .get();
    return rows.map(_rowToPreset).toList();
  }

  Future<int> upsert(BotPreset preset) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (preset.id != null) {
      await (update(db.presetsTable)
            ..where((t) => t.id.equals(preset.id!)))
          .write(PresetsTableCompanion(
        name: Value(preset.name),
        botName: Value(preset.botName),
        paramsYaml: Value(preset.paramsYaml),
        updatedAt: Value(now),
      ));
      return preset.id!;
    }
    return into(db.presetsTable).insert(PresetsTableCompanion.insert(
      name: preset.name,
      botName: preset.botName,
      paramsYaml: preset.paramsYaml,
      updatedAt: now,
    ));
  }

  Future<int> deletePreset(int id) async =>
      (delete(db.presetsTable)..where((t) => t.id.equals(id))).go();

  BotPreset _rowToPreset(PresetsTableData row) => BotPreset(
        id: row.id,
        name: row.name,
        botName: row.botName,
        paramsYaml: row.paramsYaml,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      );
}
