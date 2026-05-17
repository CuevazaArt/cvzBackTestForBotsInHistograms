import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:webview_windows/webview_windows.dart';

import 'chart_controller.dart';

/// Embeds the chart HTML+JS via webview_windows on Windows desktop.
///
/// Lifecycle:
///   1. initState: create WebViewController, listen for `chart:ready` postMessage
///   2. didChangeDependencies: extract bundled assets to temp dir
///   3. initialize + loadUrl(file://temp/index.html)
///   4. On `chart:ready` → controller.markReady() → buffer flushes
///
/// The widget never silently drops commands — see ChartController.
class ChartWidget extends StatefulWidget {
  final ChartController controller;
  final VoidCallback? onReady;
  final void Function(String diagMessage)? onDiagnostic;

  const ChartWidget({
    super.key,
    required this.controller,
    this.onReady,
    this.onDiagnostic,
  });

  @override
  State<ChartWidget> createState() => _ChartWidgetState();
}

class _ChartWidgetState extends State<ChartWidget> {
  final WebviewController _webview = WebviewController();
  bool _initialized = false;
  String? _error;
  StreamSubscription? _msgSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // Bundle the asset to a real file:// URL the WebView can load.
      final indexUrl = await _extractAssetsToTemp();

      await _webview.initialize();
      widget.controller.executor = (js) async {
        try {
          await _webview.executeScript(js);
        } catch (e) {
          widget.onDiagnostic?.call('exec error: $e');
        }
      };

      _msgSub = _webview.webMessage.listen((msg) {
        final s = msg.toString();
        widget.onDiagnostic?.call(s);
        if (s == 'chart:ready') {
          widget.controller.markReady();
          widget.onReady?.call();
        }
      });

      await _webview.loadUrl(indexUrl);
      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  /// Copies `assets/chart/*` to a writable temp directory so the WebView
  /// can resolve relative URLs (e.g. the lightweight-charts.js script tag).
  /// Returns the file:// URL of the index.html.
  Future<String> _extractAssetsToTemp() async {
    final tmpRoot = await getTemporaryDirectory();
    final chartDir = Directory(p.join(tmpRoot.path, 'cvz_chart'));
    if (!chartDir.existsSync()) chartDir.createSync(recursive: true);

    // Always overwrite — keeps in sync with dev builds.
    for (final assetName in [
      'index.html',
      'lightweight-charts.standalone.production.js',
    ]) {
      final data = await rootBundle.load('assets/chart/$assetName');
      final outFile = File(p.join(chartDir.path, assetName));
      await outFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    final indexPath = p.join(chartDir.path, 'index.html');
    return Uri.file(indexPath).toString();
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    widget.controller.executor = null;
    // _webview may have failed to initialize in headless / non-Windows envs;
    // its dispose can throw both sync (LateInitializationError) and async.
    if (_initialized) {
      try {
        _webview.dispose().catchError((_) {});
      } catch (_) { /* swallow */ }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows && !kIsWeb) {
      return const _ChartPlaceholder(
        message: 'Chart is currently supported on Windows desktop only.',
      );
    }
    if (_error != null) {
      return _ChartPlaceholder(message: 'Chart init failed:\n$_error');
    }
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return Webview(_webview);
  }
}

class _ChartPlaceholder extends StatelessWidget {
  final String message;
  const _ChartPlaceholder({required this.message});

  @override
  Widget build(BuildContext context) => Container(
        color: Colors.black87,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: const TextStyle(color: Colors.white70, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
}
