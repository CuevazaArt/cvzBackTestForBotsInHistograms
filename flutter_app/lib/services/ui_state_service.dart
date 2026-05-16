import 'dart:convert';
import 'dart:io';

class UiStateService {
  static final _file = File('${Directory.current.path}/ui_state.json');

  Map<String, dynamic> load() {
    try {
      if (_file.existsSync()) {
        return jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {};
  }

  void save(Map<String, dynamic> state) {
    try {
      _file.writeAsStringSync(jsonEncode(state));
    } catch (_) {}
  }
}
