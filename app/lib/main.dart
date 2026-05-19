import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'app.dart';
import 'data/database.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await AppDatabase.open();

  final backupDir = _resolveBackupDir();
  await Directory(backupDir).create(recursive: true);
  final imported = await db.candles.importAllCsvs(backupDir);
  if (imported > 0) {
    debugPrint('[startup] Imported $imported candles from CSV backup');
  }

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        candleBackupDirProvider.overrideWithValue(backupDir),
      ],
      child: const CvzBacktesterApp(),
    ),
  );
}

String _resolveBackupDir() {
  final exe = Platform.resolvedExecutable;
  var dir = Directory(p.dirname(exe));
  for (var i = 0; i < 8; i++) {
    if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
      final repoRoot = dir.parent;
      return p.join(repoRoot.path, 'data', 'candles');
    }
    dir = dir.parent;
  }
  return p.join(Directory.current.path, 'data', 'candles');
}
