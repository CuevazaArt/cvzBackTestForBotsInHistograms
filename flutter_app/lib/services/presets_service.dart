import 'dart:convert';
import 'dart:io';

class BacktestPreset {
  final String name;
  final String symbol;
  final String timeframe;
  final double initialCash;
  final List<String> botNames;
  final Map<String, Map<String, dynamic>> botsParams;
  final List<Map<String, dynamic>> indicators;
  final String createdAt;

  const BacktestPreset({
    required this.name,
    required this.symbol,
    required this.timeframe,
    required this.initialCash,
    required this.botNames,
    required this.botsParams,
    required this.indicators,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'symbol': symbol,
        'timeframe': timeframe,
        'initial_cash': initialCash,
        'bot_names': botNames,
        'bots_params': botsParams,
        'indicators': indicators,
        'created_at': createdAt,
      };

  factory BacktestPreset.fromJson(Map<String, dynamic> j) {
    final rawParams = (j['bots_params'] as Map?) ?? {};
    final params = <String, Map<String, dynamic>>{};
    rawParams.forEach((k, v) {
      params[k as String] = Map<String, dynamic>.from(v as Map);
    });
    return BacktestPreset(
      name: j['name'] as String,
      symbol: j['symbol'] as String,
      timeframe: j['timeframe'] as String,
      initialCash: (j['initial_cash'] as num).toDouble(),
      botNames: List<String>.from(j['bot_names'] as List),
      botsParams: params,
      indicators: List<Map<String, dynamic>>.from(
          (j['indicators'] as List).map((e) => Map<String, dynamic>.from(e as Map))),
      createdAt: j['created_at'] as String? ?? '',
    );
  }
}

/// Stores presets as JSON in `<cwd>/presets/<name>.json`.
class PresetsService {
  Directory get _dir {
    final d = Directory('${Directory.current.path}/presets');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  String _sanitize(String name) => name.replaceAll(RegExp(r'[^\w\-]+'), '_');

  Future<List<BacktestPreset>> list() async {
    if (!_dir.existsSync()) return [];
    final files = _dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json'));
    final results = <BacktestPreset>[];
    for (final f in files) {
      try {
        final raw = await f.readAsString();
        results.add(BacktestPreset.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {}
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }

  Future<File> save(BacktestPreset preset) async {
    final name = _sanitize(preset.name);
    final file = File('${_dir.path}/$name.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(preset.toJson()));
    return file;
  }

  Future<void> delete(String name) async {
    final file = File('${_dir.path}/${_sanitize(name)}.json');
    if (file.existsSync()) await file.delete();
  }

  String get dirPath => _dir.path;
}
