// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $CandlesTableTable extends CandlesTable
    with TableInfo<$CandlesTableTable, CandlesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CandlesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _symbolMeta = const VerificationMeta('symbol');
  @override
  late final GeneratedColumn<String> symbol = GeneratedColumn<String>(
    'symbol',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timeframeMeta = const VerificationMeta(
    'timeframe',
  );
  @override
  late final GeneratedColumn<String> timeframe = GeneratedColumn<String>(
    'timeframe',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMsMeta = const VerificationMeta(
    'timestampMs',
  );
  @override
  late final GeneratedColumn<int> timestampMs = GeneratedColumn<int>(
    'timestamp_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _openMeta = const VerificationMeta('open');
  @override
  late final GeneratedColumn<double> open = GeneratedColumn<double>(
    'open',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _highMeta = const VerificationMeta('high');
  @override
  late final GeneratedColumn<double> high = GeneratedColumn<double>(
    'high',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lowMeta = const VerificationMeta('low');
  @override
  late final GeneratedColumn<double> low = GeneratedColumn<double>(
    'low',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _closeMeta = const VerificationMeta('close');
  @override
  late final GeneratedColumn<double> close = GeneratedColumn<double>(
    'close',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _volumeMeta = const VerificationMeta('volume');
  @override
  late final GeneratedColumn<double> volume = GeneratedColumn<double>(
    'volume',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    symbol,
    timeframe,
    timestampMs,
    open,
    high,
    low,
    close,
    volume,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'candles_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<CandlesTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('symbol')) {
      context.handle(
        _symbolMeta,
        symbol.isAcceptableOrUnknown(data['symbol']!, _symbolMeta),
      );
    } else if (isInserting) {
      context.missing(_symbolMeta);
    }
    if (data.containsKey('timeframe')) {
      context.handle(
        _timeframeMeta,
        timeframe.isAcceptableOrUnknown(data['timeframe']!, _timeframeMeta),
      );
    } else if (isInserting) {
      context.missing(_timeframeMeta);
    }
    if (data.containsKey('timestamp_ms')) {
      context.handle(
        _timestampMsMeta,
        timestampMs.isAcceptableOrUnknown(
          data['timestamp_ms']!,
          _timestampMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_timestampMsMeta);
    }
    if (data.containsKey('open')) {
      context.handle(
        _openMeta,
        open.isAcceptableOrUnknown(data['open']!, _openMeta),
      );
    } else if (isInserting) {
      context.missing(_openMeta);
    }
    if (data.containsKey('high')) {
      context.handle(
        _highMeta,
        high.isAcceptableOrUnknown(data['high']!, _highMeta),
      );
    } else if (isInserting) {
      context.missing(_highMeta);
    }
    if (data.containsKey('low')) {
      context.handle(
        _lowMeta,
        low.isAcceptableOrUnknown(data['low']!, _lowMeta),
      );
    } else if (isInserting) {
      context.missing(_lowMeta);
    }
    if (data.containsKey('close')) {
      context.handle(
        _closeMeta,
        close.isAcceptableOrUnknown(data['close']!, _closeMeta),
      );
    } else if (isInserting) {
      context.missing(_closeMeta);
    }
    if (data.containsKey('volume')) {
      context.handle(
        _volumeMeta,
        volume.isAcceptableOrUnknown(data['volume']!, _volumeMeta),
      );
    } else if (isInserting) {
      context.missing(_volumeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {symbol, timeframe, timestampMs};
  @override
  CandlesTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CandlesTableData(
      symbol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}symbol'],
      )!,
      timeframe: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}timeframe'],
      )!,
      timestampMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}timestamp_ms'],
      )!,
      open: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}open'],
      )!,
      high: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}high'],
      )!,
      low: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}low'],
      )!,
      close: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}close'],
      )!,
      volume: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}volume'],
      )!,
    );
  }

  @override
  $CandlesTableTable createAlias(String alias) {
    return $CandlesTableTable(attachedDatabase, alias);
  }
}

class CandlesTableData extends DataClass
    implements Insertable<CandlesTableData> {
  final String symbol;
  final String timeframe;
  final int timestampMs;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  const CandlesTableData({
    required this.symbol,
    required this.timeframe,
    required this.timestampMs,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['symbol'] = Variable<String>(symbol);
    map['timeframe'] = Variable<String>(timeframe);
    map['timestamp_ms'] = Variable<int>(timestampMs);
    map['open'] = Variable<double>(open);
    map['high'] = Variable<double>(high);
    map['low'] = Variable<double>(low);
    map['close'] = Variable<double>(close);
    map['volume'] = Variable<double>(volume);
    return map;
  }

  CandlesTableCompanion toCompanion(bool nullToAbsent) {
    return CandlesTableCompanion(
      symbol: Value(symbol),
      timeframe: Value(timeframe),
      timestampMs: Value(timestampMs),
      open: Value(open),
      high: Value(high),
      low: Value(low),
      close: Value(close),
      volume: Value(volume),
    );
  }

  factory CandlesTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CandlesTableData(
      symbol: serializer.fromJson<String>(json['symbol']),
      timeframe: serializer.fromJson<String>(json['timeframe']),
      timestampMs: serializer.fromJson<int>(json['timestampMs']),
      open: serializer.fromJson<double>(json['open']),
      high: serializer.fromJson<double>(json['high']),
      low: serializer.fromJson<double>(json['low']),
      close: serializer.fromJson<double>(json['close']),
      volume: serializer.fromJson<double>(json['volume']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'symbol': serializer.toJson<String>(symbol),
      'timeframe': serializer.toJson<String>(timeframe),
      'timestampMs': serializer.toJson<int>(timestampMs),
      'open': serializer.toJson<double>(open),
      'high': serializer.toJson<double>(high),
      'low': serializer.toJson<double>(low),
      'close': serializer.toJson<double>(close),
      'volume': serializer.toJson<double>(volume),
    };
  }

  CandlesTableData copyWith({
    String? symbol,
    String? timeframe,
    int? timestampMs,
    double? open,
    double? high,
    double? low,
    double? close,
    double? volume,
  }) => CandlesTableData(
    symbol: symbol ?? this.symbol,
    timeframe: timeframe ?? this.timeframe,
    timestampMs: timestampMs ?? this.timestampMs,
    open: open ?? this.open,
    high: high ?? this.high,
    low: low ?? this.low,
    close: close ?? this.close,
    volume: volume ?? this.volume,
  );
  CandlesTableData copyWithCompanion(CandlesTableCompanion data) {
    return CandlesTableData(
      symbol: data.symbol.present ? data.symbol.value : this.symbol,
      timeframe: data.timeframe.present ? data.timeframe.value : this.timeframe,
      timestampMs: data.timestampMs.present
          ? data.timestampMs.value
          : this.timestampMs,
      open: data.open.present ? data.open.value : this.open,
      high: data.high.present ? data.high.value : this.high,
      low: data.low.present ? data.low.value : this.low,
      close: data.close.present ? data.close.value : this.close,
      volume: data.volume.present ? data.volume.value : this.volume,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CandlesTableData(')
          ..write('symbol: $symbol, ')
          ..write('timeframe: $timeframe, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('open: $open, ')
          ..write('high: $high, ')
          ..write('low: $low, ')
          ..write('close: $close, ')
          ..write('volume: $volume')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    symbol,
    timeframe,
    timestampMs,
    open,
    high,
    low,
    close,
    volume,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CandlesTableData &&
          other.symbol == this.symbol &&
          other.timeframe == this.timeframe &&
          other.timestampMs == this.timestampMs &&
          other.open == this.open &&
          other.high == this.high &&
          other.low == this.low &&
          other.close == this.close &&
          other.volume == this.volume);
}

class CandlesTableCompanion extends UpdateCompanion<CandlesTableData> {
  final Value<String> symbol;
  final Value<String> timeframe;
  final Value<int> timestampMs;
  final Value<double> open;
  final Value<double> high;
  final Value<double> low;
  final Value<double> close;
  final Value<double> volume;
  final Value<int> rowid;
  const CandlesTableCompanion({
    this.symbol = const Value.absent(),
    this.timeframe = const Value.absent(),
    this.timestampMs = const Value.absent(),
    this.open = const Value.absent(),
    this.high = const Value.absent(),
    this.low = const Value.absent(),
    this.close = const Value.absent(),
    this.volume = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CandlesTableCompanion.insert({
    required String symbol,
    required String timeframe,
    required int timestampMs,
    required double open,
    required double high,
    required double low,
    required double close,
    required double volume,
    this.rowid = const Value.absent(),
  }) : symbol = Value(symbol),
       timeframe = Value(timeframe),
       timestampMs = Value(timestampMs),
       open = Value(open),
       high = Value(high),
       low = Value(low),
       close = Value(close),
       volume = Value(volume);
  static Insertable<CandlesTableData> custom({
    Expression<String>? symbol,
    Expression<String>? timeframe,
    Expression<int>? timestampMs,
    Expression<double>? open,
    Expression<double>? high,
    Expression<double>? low,
    Expression<double>? close,
    Expression<double>? volume,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (symbol != null) 'symbol': symbol,
      if (timeframe != null) 'timeframe': timeframe,
      if (timestampMs != null) 'timestamp_ms': timestampMs,
      if (open != null) 'open': open,
      if (high != null) 'high': high,
      if (low != null) 'low': low,
      if (close != null) 'close': close,
      if (volume != null) 'volume': volume,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CandlesTableCompanion copyWith({
    Value<String>? symbol,
    Value<String>? timeframe,
    Value<int>? timestampMs,
    Value<double>? open,
    Value<double>? high,
    Value<double>? low,
    Value<double>? close,
    Value<double>? volume,
    Value<int>? rowid,
  }) {
    return CandlesTableCompanion(
      symbol: symbol ?? this.symbol,
      timeframe: timeframe ?? this.timeframe,
      timestampMs: timestampMs ?? this.timestampMs,
      open: open ?? this.open,
      high: high ?? this.high,
      low: low ?? this.low,
      close: close ?? this.close,
      volume: volume ?? this.volume,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (symbol.present) {
      map['symbol'] = Variable<String>(symbol.value);
    }
    if (timeframe.present) {
      map['timeframe'] = Variable<String>(timeframe.value);
    }
    if (timestampMs.present) {
      map['timestamp_ms'] = Variable<int>(timestampMs.value);
    }
    if (open.present) {
      map['open'] = Variable<double>(open.value);
    }
    if (high.present) {
      map['high'] = Variable<double>(high.value);
    }
    if (low.present) {
      map['low'] = Variable<double>(low.value);
    }
    if (close.present) {
      map['close'] = Variable<double>(close.value);
    }
    if (volume.present) {
      map['volume'] = Variable<double>(volume.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CandlesTableCompanion(')
          ..write('symbol: $symbol, ')
          ..write('timeframe: $timeframe, ')
          ..write('timestampMs: $timestampMs, ')
          ..write('open: $open, ')
          ..write('high: $high, ')
          ..write('low: $low, ')
          ..write('close: $close, ')
          ..write('volume: $volume, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ResultsTableTable extends ResultsTable
    with TableInfo<$ResultsTableTable, ResultsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ResultsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  @override
  late final GeneratedColumn<String> runId = GeneratedColumn<String>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _configJsonMeta = const VerificationMeta(
    'configJson',
  );
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
    'config_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _metricsJsonMeta = const VerificationMeta(
    'metricsJson',
  );
  @override
  late final GeneratedColumn<String> metricsJson = GeneratedColumn<String>(
    'metrics_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tradesJsonMeta = const VerificationMeta(
    'tradesJson',
  );
  @override
  late final GeneratedColumn<String> tradesJson = GeneratedColumn<String>(
    'trades_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    runId,
    createdAt,
    configJson,
    metricsJson,
    tradesJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'results_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<ResultsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('config_json')) {
      context.handle(
        _configJsonMeta,
        configJson.isAcceptableOrUnknown(data['config_json']!, _configJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_configJsonMeta);
    }
    if (data.containsKey('metrics_json')) {
      context.handle(
        _metricsJsonMeta,
        metricsJson.isAcceptableOrUnknown(
          data['metrics_json']!,
          _metricsJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_metricsJsonMeta);
    }
    if (data.containsKey('trades_json')) {
      context.handle(
        _tradesJsonMeta,
        tradesJson.isAcceptableOrUnknown(data['trades_json']!, _tradesJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_tradesJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {runId};
  @override
  ResultsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ResultsTableData(
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}run_id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      configJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_json'],
      )!,
      metricsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}metrics_json'],
      )!,
      tradesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}trades_json'],
      )!,
    );
  }

  @override
  $ResultsTableTable createAlias(String alias) {
    return $ResultsTableTable(attachedDatabase, alias);
  }
}

class ResultsTableData extends DataClass
    implements Insertable<ResultsTableData> {
  final String runId;
  final int createdAt;
  final String configJson;
  final String metricsJson;
  final String tradesJson;
  const ResultsTableData({
    required this.runId,
    required this.createdAt,
    required this.configJson,
    required this.metricsJson,
    required this.tradesJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['run_id'] = Variable<String>(runId);
    map['created_at'] = Variable<int>(createdAt);
    map['config_json'] = Variable<String>(configJson);
    map['metrics_json'] = Variable<String>(metricsJson);
    map['trades_json'] = Variable<String>(tradesJson);
    return map;
  }

  ResultsTableCompanion toCompanion(bool nullToAbsent) {
    return ResultsTableCompanion(
      runId: Value(runId),
      createdAt: Value(createdAt),
      configJson: Value(configJson),
      metricsJson: Value(metricsJson),
      tradesJson: Value(tradesJson),
    );
  }

  factory ResultsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ResultsTableData(
      runId: serializer.fromJson<String>(json['runId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      configJson: serializer.fromJson<String>(json['configJson']),
      metricsJson: serializer.fromJson<String>(json['metricsJson']),
      tradesJson: serializer.fromJson<String>(json['tradesJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'runId': serializer.toJson<String>(runId),
      'createdAt': serializer.toJson<int>(createdAt),
      'configJson': serializer.toJson<String>(configJson),
      'metricsJson': serializer.toJson<String>(metricsJson),
      'tradesJson': serializer.toJson<String>(tradesJson),
    };
  }

  ResultsTableData copyWith({
    String? runId,
    int? createdAt,
    String? configJson,
    String? metricsJson,
    String? tradesJson,
  }) => ResultsTableData(
    runId: runId ?? this.runId,
    createdAt: createdAt ?? this.createdAt,
    configJson: configJson ?? this.configJson,
    metricsJson: metricsJson ?? this.metricsJson,
    tradesJson: tradesJson ?? this.tradesJson,
  );
  ResultsTableData copyWithCompanion(ResultsTableCompanion data) {
    return ResultsTableData(
      runId: data.runId.present ? data.runId.value : this.runId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      configJson: data.configJson.present
          ? data.configJson.value
          : this.configJson,
      metricsJson: data.metricsJson.present
          ? data.metricsJson.value
          : this.metricsJson,
      tradesJson: data.tradesJson.present
          ? data.tradesJson.value
          : this.tradesJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ResultsTableData(')
          ..write('runId: $runId, ')
          ..write('createdAt: $createdAt, ')
          ..write('configJson: $configJson, ')
          ..write('metricsJson: $metricsJson, ')
          ..write('tradesJson: $tradesJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(runId, createdAt, configJson, metricsJson, tradesJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ResultsTableData &&
          other.runId == this.runId &&
          other.createdAt == this.createdAt &&
          other.configJson == this.configJson &&
          other.metricsJson == this.metricsJson &&
          other.tradesJson == this.tradesJson);
}

class ResultsTableCompanion extends UpdateCompanion<ResultsTableData> {
  final Value<String> runId;
  final Value<int> createdAt;
  final Value<String> configJson;
  final Value<String> metricsJson;
  final Value<String> tradesJson;
  final Value<int> rowid;
  const ResultsTableCompanion({
    this.runId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.configJson = const Value.absent(),
    this.metricsJson = const Value.absent(),
    this.tradesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ResultsTableCompanion.insert({
    required String runId,
    required int createdAt,
    required String configJson,
    required String metricsJson,
    required String tradesJson,
    this.rowid = const Value.absent(),
  }) : runId = Value(runId),
       createdAt = Value(createdAt),
       configJson = Value(configJson),
       metricsJson = Value(metricsJson),
       tradesJson = Value(tradesJson);
  static Insertable<ResultsTableData> custom({
    Expression<String>? runId,
    Expression<int>? createdAt,
    Expression<String>? configJson,
    Expression<String>? metricsJson,
    Expression<String>? tradesJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (runId != null) 'run_id': runId,
      if (createdAt != null) 'created_at': createdAt,
      if (configJson != null) 'config_json': configJson,
      if (metricsJson != null) 'metrics_json': metricsJson,
      if (tradesJson != null) 'trades_json': tradesJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ResultsTableCompanion copyWith({
    Value<String>? runId,
    Value<int>? createdAt,
    Value<String>? configJson,
    Value<String>? metricsJson,
    Value<String>? tradesJson,
    Value<int>? rowid,
  }) {
    return ResultsTableCompanion(
      runId: runId ?? this.runId,
      createdAt: createdAt ?? this.createdAt,
      configJson: configJson ?? this.configJson,
      metricsJson: metricsJson ?? this.metricsJson,
      tradesJson: tradesJson ?? this.tradesJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (runId.present) {
      map['run_id'] = Variable<String>(runId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    if (metricsJson.present) {
      map['metrics_json'] = Variable<String>(metricsJson.value);
    }
    if (tradesJson.present) {
      map['trades_json'] = Variable<String>(tradesJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ResultsTableCompanion(')
          ..write('runId: $runId, ')
          ..write('createdAt: $createdAt, ')
          ..write('configJson: $configJson, ')
          ..write('metricsJson: $metricsJson, ')
          ..write('tradesJson: $tradesJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PresetsTableTable extends PresetsTable
    with TableInfo<$PresetsTableTable, PresetsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PresetsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _botNameMeta = const VerificationMeta(
    'botName',
  );
  @override
  late final GeneratedColumn<String> botName = GeneratedColumn<String>(
    'bot_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paramsYamlMeta = const VerificationMeta(
    'paramsYaml',
  );
  @override
  late final GeneratedColumn<String> paramsYaml = GeneratedColumn<String>(
    'params_yaml',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    botName,
    paramsYaml,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'presets_table';
  @override
  VerificationContext validateIntegrity(
    Insertable<PresetsTableData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('bot_name')) {
      context.handle(
        _botNameMeta,
        botName.isAcceptableOrUnknown(data['bot_name']!, _botNameMeta),
      );
    } else if (isInserting) {
      context.missing(_botNameMeta);
    }
    if (data.containsKey('params_yaml')) {
      context.handle(
        _paramsYamlMeta,
        paramsYaml.isAcceptableOrUnknown(data['params_yaml']!, _paramsYamlMeta),
      );
    } else if (isInserting) {
      context.missing(_paramsYamlMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PresetsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PresetsTableData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      botName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}bot_name'],
      )!,
      paramsYaml: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}params_yaml'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $PresetsTableTable createAlias(String alias) {
    return $PresetsTableTable(attachedDatabase, alias);
  }
}

class PresetsTableData extends DataClass
    implements Insertable<PresetsTableData> {
  final int id;
  final String name;
  final String botName;
  final String paramsYaml;
  final int updatedAt;
  const PresetsTableData({
    required this.id,
    required this.name,
    required this.botName,
    required this.paramsYaml,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['bot_name'] = Variable<String>(botName);
    map['params_yaml'] = Variable<String>(paramsYaml);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  PresetsTableCompanion toCompanion(bool nullToAbsent) {
    return PresetsTableCompanion(
      id: Value(id),
      name: Value(name),
      botName: Value(botName),
      paramsYaml: Value(paramsYaml),
      updatedAt: Value(updatedAt),
    );
  }

  factory PresetsTableData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PresetsTableData(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      botName: serializer.fromJson<String>(json['botName']),
      paramsYaml: serializer.fromJson<String>(json['paramsYaml']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'botName': serializer.toJson<String>(botName),
      'paramsYaml': serializer.toJson<String>(paramsYaml),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  PresetsTableData copyWith({
    int? id,
    String? name,
    String? botName,
    String? paramsYaml,
    int? updatedAt,
  }) => PresetsTableData(
    id: id ?? this.id,
    name: name ?? this.name,
    botName: botName ?? this.botName,
    paramsYaml: paramsYaml ?? this.paramsYaml,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  PresetsTableData copyWithCompanion(PresetsTableCompanion data) {
    return PresetsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      botName: data.botName.present ? data.botName.value : this.botName,
      paramsYaml: data.paramsYaml.present
          ? data.paramsYaml.value
          : this.paramsYaml,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PresetsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('botName: $botName, ')
          ..write('paramsYaml: $paramsYaml, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, botName, paramsYaml, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PresetsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.botName == this.botName &&
          other.paramsYaml == this.paramsYaml &&
          other.updatedAt == this.updatedAt);
}

class PresetsTableCompanion extends UpdateCompanion<PresetsTableData> {
  final Value<int> id;
  final Value<String> name;
  final Value<String> botName;
  final Value<String> paramsYaml;
  final Value<int> updatedAt;
  const PresetsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.botName = const Value.absent(),
    this.paramsYaml = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  PresetsTableCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    required String botName,
    required String paramsYaml,
    required int updatedAt,
  }) : name = Value(name),
       botName = Value(botName),
       paramsYaml = Value(paramsYaml),
       updatedAt = Value(updatedAt);
  static Insertable<PresetsTableData> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<String>? botName,
    Expression<String>? paramsYaml,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (botName != null) 'bot_name': botName,
      if (paramsYaml != null) 'params_yaml': paramsYaml,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  PresetsTableCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<String>? botName,
    Value<String>? paramsYaml,
    Value<int>? updatedAt,
  }) {
    return PresetsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      botName: botName ?? this.botName,
      paramsYaml: paramsYaml ?? this.paramsYaml,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (botName.present) {
      map['bot_name'] = Variable<String>(botName.value);
    }
    if (paramsYaml.present) {
      map['params_yaml'] = Variable<String>(paramsYaml.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PresetsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('botName: $botName, ')
          ..write('paramsYaml: $paramsYaml, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CandlesTableTable candlesTable = $CandlesTableTable(this);
  late final $ResultsTableTable resultsTable = $ResultsTableTable(this);
  late final $PresetsTableTable presetsTable = $PresetsTableTable(this);
  late final CandlesDao candlesDao = CandlesDao(this as AppDatabase);
  late final ResultsDao resultsDao = ResultsDao(this as AppDatabase);
  late final PresetsDao presetsDao = PresetsDao(this as AppDatabase);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    candlesTable,
    resultsTable,
    presetsTable,
  ];
}

typedef $$CandlesTableTableCreateCompanionBuilder =
    CandlesTableCompanion Function({
      required String symbol,
      required String timeframe,
      required int timestampMs,
      required double open,
      required double high,
      required double low,
      required double close,
      required double volume,
      Value<int> rowid,
    });
typedef $$CandlesTableTableUpdateCompanionBuilder =
    CandlesTableCompanion Function({
      Value<String> symbol,
      Value<String> timeframe,
      Value<int> timestampMs,
      Value<double> open,
      Value<double> high,
      Value<double> low,
      Value<double> close,
      Value<double> volume,
      Value<int> rowid,
    });

class $$CandlesTableTableFilterComposer
    extends Composer<_$AppDatabase, $CandlesTableTable> {
  $$CandlesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get timeframe => $composableBuilder(
    column: $table.timeframe,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get open => $composableBuilder(
    column: $table.open,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get high => $composableBuilder(
    column: $table.high,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get low => $composableBuilder(
    column: $table.low,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get close => $composableBuilder(
    column: $table.close,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CandlesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $CandlesTableTable> {
  $$CandlesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get symbol => $composableBuilder(
    column: $table.symbol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get timeframe => $composableBuilder(
    column: $table.timeframe,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get open => $composableBuilder(
    column: $table.open,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get high => $composableBuilder(
    column: $table.high,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get low => $composableBuilder(
    column: $table.low,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get close => $composableBuilder(
    column: $table.close,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get volume => $composableBuilder(
    column: $table.volume,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CandlesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $CandlesTableTable> {
  $$CandlesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get symbol =>
      $composableBuilder(column: $table.symbol, builder: (column) => column);

  GeneratedColumn<String> get timeframe =>
      $composableBuilder(column: $table.timeframe, builder: (column) => column);

  GeneratedColumn<int> get timestampMs => $composableBuilder(
    column: $table.timestampMs,
    builder: (column) => column,
  );

  GeneratedColumn<double> get open =>
      $composableBuilder(column: $table.open, builder: (column) => column);

  GeneratedColumn<double> get high =>
      $composableBuilder(column: $table.high, builder: (column) => column);

  GeneratedColumn<double> get low =>
      $composableBuilder(column: $table.low, builder: (column) => column);

  GeneratedColumn<double> get close =>
      $composableBuilder(column: $table.close, builder: (column) => column);

  GeneratedColumn<double> get volume =>
      $composableBuilder(column: $table.volume, builder: (column) => column);
}

class $$CandlesTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CandlesTableTable,
          CandlesTableData,
          $$CandlesTableTableFilterComposer,
          $$CandlesTableTableOrderingComposer,
          $$CandlesTableTableAnnotationComposer,
          $$CandlesTableTableCreateCompanionBuilder,
          $$CandlesTableTableUpdateCompanionBuilder,
          (
            CandlesTableData,
            BaseReferences<_$AppDatabase, $CandlesTableTable, CandlesTableData>,
          ),
          CandlesTableData,
          PrefetchHooks Function()
        > {
  $$CandlesTableTableTableManager(_$AppDatabase db, $CandlesTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CandlesTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CandlesTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CandlesTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> symbol = const Value.absent(),
                Value<String> timeframe = const Value.absent(),
                Value<int> timestampMs = const Value.absent(),
                Value<double> open = const Value.absent(),
                Value<double> high = const Value.absent(),
                Value<double> low = const Value.absent(),
                Value<double> close = const Value.absent(),
                Value<double> volume = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CandlesTableCompanion(
                symbol: symbol,
                timeframe: timeframe,
                timestampMs: timestampMs,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String symbol,
                required String timeframe,
                required int timestampMs,
                required double open,
                required double high,
                required double low,
                required double close,
                required double volume,
                Value<int> rowid = const Value.absent(),
              }) => CandlesTableCompanion.insert(
                symbol: symbol,
                timeframe: timeframe,
                timestampMs: timestampMs,
                open: open,
                high: high,
                low: low,
                close: close,
                volume: volume,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CandlesTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CandlesTableTable,
      CandlesTableData,
      $$CandlesTableTableFilterComposer,
      $$CandlesTableTableOrderingComposer,
      $$CandlesTableTableAnnotationComposer,
      $$CandlesTableTableCreateCompanionBuilder,
      $$CandlesTableTableUpdateCompanionBuilder,
      (
        CandlesTableData,
        BaseReferences<_$AppDatabase, $CandlesTableTable, CandlesTableData>,
      ),
      CandlesTableData,
      PrefetchHooks Function()
    >;
typedef $$ResultsTableTableCreateCompanionBuilder =
    ResultsTableCompanion Function({
      required String runId,
      required int createdAt,
      required String configJson,
      required String metricsJson,
      required String tradesJson,
      Value<int> rowid,
    });
typedef $$ResultsTableTableUpdateCompanionBuilder =
    ResultsTableCompanion Function({
      Value<String> runId,
      Value<int> createdAt,
      Value<String> configJson,
      Value<String> metricsJson,
      Value<String> tradesJson,
      Value<int> rowid,
    });

class $$ResultsTableTableFilterComposer
    extends Composer<_$AppDatabase, $ResultsTableTable> {
  $$ResultsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get runId => $composableBuilder(
    column: $table.runId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get metricsJson => $composableBuilder(
    column: $table.metricsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tradesJson => $composableBuilder(
    column: $table.tradesJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ResultsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $ResultsTableTable> {
  $$ResultsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get runId => $composableBuilder(
    column: $table.runId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get metricsJson => $composableBuilder(
    column: $table.metricsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tradesJson => $composableBuilder(
    column: $table.tradesJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ResultsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $ResultsTableTable> {
  $$ResultsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get runId =>
      $composableBuilder(column: $table.runId, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get metricsJson => $composableBuilder(
    column: $table.metricsJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get tradesJson => $composableBuilder(
    column: $table.tradesJson,
    builder: (column) => column,
  );
}

class $$ResultsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ResultsTableTable,
          ResultsTableData,
          $$ResultsTableTableFilterComposer,
          $$ResultsTableTableOrderingComposer,
          $$ResultsTableTableAnnotationComposer,
          $$ResultsTableTableCreateCompanionBuilder,
          $$ResultsTableTableUpdateCompanionBuilder,
          (
            ResultsTableData,
            BaseReferences<_$AppDatabase, $ResultsTableTable, ResultsTableData>,
          ),
          ResultsTableData,
          PrefetchHooks Function()
        > {
  $$ResultsTableTableTableManager(_$AppDatabase db, $ResultsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ResultsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ResultsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ResultsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> runId = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String> configJson = const Value.absent(),
                Value<String> metricsJson = const Value.absent(),
                Value<String> tradesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ResultsTableCompanion(
                runId: runId,
                createdAt: createdAt,
                configJson: configJson,
                metricsJson: metricsJson,
                tradesJson: tradesJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String runId,
                required int createdAt,
                required String configJson,
                required String metricsJson,
                required String tradesJson,
                Value<int> rowid = const Value.absent(),
              }) => ResultsTableCompanion.insert(
                runId: runId,
                createdAt: createdAt,
                configJson: configJson,
                metricsJson: metricsJson,
                tradesJson: tradesJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ResultsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ResultsTableTable,
      ResultsTableData,
      $$ResultsTableTableFilterComposer,
      $$ResultsTableTableOrderingComposer,
      $$ResultsTableTableAnnotationComposer,
      $$ResultsTableTableCreateCompanionBuilder,
      $$ResultsTableTableUpdateCompanionBuilder,
      (
        ResultsTableData,
        BaseReferences<_$AppDatabase, $ResultsTableTable, ResultsTableData>,
      ),
      ResultsTableData,
      PrefetchHooks Function()
    >;
typedef $$PresetsTableTableCreateCompanionBuilder =
    PresetsTableCompanion Function({
      Value<int> id,
      required String name,
      required String botName,
      required String paramsYaml,
      required int updatedAt,
    });
typedef $$PresetsTableTableUpdateCompanionBuilder =
    PresetsTableCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<String> botName,
      Value<String> paramsYaml,
      Value<int> updatedAt,
    });

class $$PresetsTableTableFilterComposer
    extends Composer<_$AppDatabase, $PresetsTableTable> {
  $$PresetsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get botName => $composableBuilder(
    column: $table.botName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paramsYaml => $composableBuilder(
    column: $table.paramsYaml,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PresetsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $PresetsTableTable> {
  $$PresetsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get botName => $composableBuilder(
    column: $table.botName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paramsYaml => $composableBuilder(
    column: $table.paramsYaml,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PresetsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $PresetsTableTable> {
  $$PresetsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get botName =>
      $composableBuilder(column: $table.botName, builder: (column) => column);

  GeneratedColumn<String> get paramsYaml => $composableBuilder(
    column: $table.paramsYaml,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$PresetsTableTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PresetsTableTable,
          PresetsTableData,
          $$PresetsTableTableFilterComposer,
          $$PresetsTableTableOrderingComposer,
          $$PresetsTableTableAnnotationComposer,
          $$PresetsTableTableCreateCompanionBuilder,
          $$PresetsTableTableUpdateCompanionBuilder,
          (
            PresetsTableData,
            BaseReferences<_$AppDatabase, $PresetsTableTable, PresetsTableData>,
          ),
          PresetsTableData,
          PrefetchHooks Function()
        > {
  $$PresetsTableTableTableManager(_$AppDatabase db, $PresetsTableTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PresetsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PresetsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PresetsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> botName = const Value.absent(),
                Value<String> paramsYaml = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => PresetsTableCompanion(
                id: id,
                name: name,
                botName: botName,
                paramsYaml: paramsYaml,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                required String botName,
                required String paramsYaml,
                required int updatedAt,
              }) => PresetsTableCompanion.insert(
                id: id,
                name: name,
                botName: botName,
                paramsYaml: paramsYaml,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PresetsTableTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PresetsTableTable,
      PresetsTableData,
      $$PresetsTableTableFilterComposer,
      $$PresetsTableTableOrderingComposer,
      $$PresetsTableTableAnnotationComposer,
      $$PresetsTableTableCreateCompanionBuilder,
      $$PresetsTableTableUpdateCompanionBuilder,
      (
        PresetsTableData,
        BaseReferences<_$AppDatabase, $PresetsTableTable, PresetsTableData>,
      ),
      PresetsTableData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CandlesTableTableTableManager get candlesTable =>
      $$CandlesTableTableTableManager(_db, _db.candlesTable);
  $$ResultsTableTableTableManager get resultsTable =>
      $$ResultsTableTableTableManager(_db, _db.resultsTable);
  $$PresetsTableTableTableManager get presetsTable =>
      $$PresetsTableTableTableManager(_db, _db.presetsTable);
}
