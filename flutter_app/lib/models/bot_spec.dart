class ParamSpec {
  final String name;
  final String type; // "int" | "float" | "bool"
  final dynamic defaultValue;
  final dynamic min;
  final dynamic max;
  final dynamic step;

  const ParamSpec({
    required this.name,
    required this.type,
    required this.defaultValue,
    this.min,
    this.max,
    this.step,
  });

  factory ParamSpec.fromEntry(String name, Map<String, dynamic> j) => ParamSpec(
        name:         name,
        type:         j['type'] as String? ?? 'float',
        defaultValue: j['default'],
        min:          j['min'],
        max:          j['max'],
        step:         j['step'],
      );
}

class BotSpec {
  final String name;
  final String description;
  final List<ParamSpec> params;

  const BotSpec({
    required this.name,
    required this.description,
    required this.params,
  });

  factory BotSpec.fromJson(Map<String, dynamic> j) {
    final rawParams = j['params'] as Map<String, dynamic>? ?? {};
    return BotSpec(
      name:        j['name'] as String,
      description: j['description'] as String? ?? '',
      params:      rawParams.entries
          .map((e) => ParamSpec.fromEntry(e.key, e.value as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> defaultParams() {
    return {for (final p in params) p.name: p.defaultValue};
  }
}
