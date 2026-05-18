import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/backtest_result.dart';
import '../data/database.dart';
import '../data/downloader.dart';

/// Database provider — initialized once at startup via overrideWithValue
/// in main.dart. Synchronous access throughout the app.
final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('Override databaseProvider in main.dart');
});

/// Singleton Binance downloader. Disposed when the provider goes away.
final downloaderProvider = Provider<BinanceDownloader>((ref) {
  final d = BinanceDownloader();
  ref.onDispose(d.dispose);
  return d;
});

/// Theme mode provider.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

/// Viewed result from history (used by Analysis screen when no live result).
final viewedResultProvider = StateProvider<BacktestResult?>((ref) => null);
