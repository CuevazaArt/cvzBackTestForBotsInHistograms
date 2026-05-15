import 'dart:convert';
import 'dart:io';

class AppSettings {
  String backendUrl;
  String apiToken;
  double defaultCash;
  double defaultFeePct;
  double defaultSlippagePct;

  AppSettings({
    this.backendUrl = 'http://127.0.0.1:8002',
    this.apiToken = '',
    this.defaultCash = 10000.0,
    this.defaultFeePct = 0.1,
    this.defaultSlippagePct = 0.05,
  });

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
        backendUrl: j['backendUrl'] as String? ?? 'http://127.0.0.1:8002',
        apiToken: j['apiToken'] as String? ?? '',
        defaultCash: (j['defaultCash'] as num?)?.toDouble() ?? 10000.0,
        defaultFeePct: (j['defaultFeePct'] as num?)?.toDouble() ?? 0.1,
        defaultSlippagePct: (j['defaultSlippagePct'] as num?)?.toDouble() ?? 0.05,
      );

  Map<String, dynamic> toJson() => {
        'backendUrl': backendUrl,
        'apiToken': apiToken,
        'defaultCash': defaultCash,
        'defaultFeePct': defaultFeePct,
        'defaultSlippagePct': defaultSlippagePct,
      };
}

class AppSettingsService {
  static final _settingsFile = File('${Directory.current.path}/settings.json');

  AppSettings load() {
    try {
      if (_settingsFile.existsSync()) {
        final j = jsonDecode(_settingsFile.readAsStringSync());
        return AppSettings.fromJson(j as Map<String, dynamic>);
      }
    } catch (_) {}
    return AppSettings();
  }

  void save(AppSettings settings) {
    _settingsFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(settings.toJson()),
    );
  }
}
