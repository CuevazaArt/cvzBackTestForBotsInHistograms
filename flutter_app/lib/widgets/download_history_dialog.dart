import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/backtest_state.dart';

/// Dialog that triggers a historical-candles download and polls the backend
/// for live job progress. The download flow is the **primary entry point**
/// for the tool — without local candles, no backtest can run — so this dialog
/// is intentionally robust:
///
///  • inputs are validated before submission (symbol uppercase, dates parseable,
///    from ≤ to);
///  • the dialog stays open during the download so the user can watch progress
///    and copy error messages;
///  • polling uses a Timer rather than recursive Futures so cancelling on
///    dispose is trivial and there is no leak risk;
///  • when the job finishes (done or error) we refresh the symbols provider
///    so the sidebar dropdown immediately reflects the new data.
class DownloadHistoryDialog extends ConsumerStatefulWidget {
  const DownloadHistoryDialog({super.key});

  @override
  ConsumerState<DownloadHistoryDialog> createState() =>
      _DownloadHistoryDialogState();

  /// Convenience wrapper — `await DownloadHistoryDialog.show(context)`.
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const DownloadHistoryDialog(),
    );
  }
}

class _DownloadHistoryDialogState extends ConsumerState<DownloadHistoryDialog> {
  static const _timeframes = ['1m', '5m', '15m', '1h', '4h', '1d'];

  final _symbolCtrl = TextEditingController(text: 'BTCUSDT');
  String _timeframe = '1h';
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();

  String? _jobId;
  String _status = 'idle';       // idle | running | done | error
  double _progress = 0.0;
  String? _message;
  int? _candlesAdded;
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    _symbolCtrl.dispose();
    super.dispose();
  }

  String get _fromStr =>
      '${_from.year.toString().padLeft(4, '0')}-${_from.month.toString().padLeft(2, '0')}-${_from.day.toString().padLeft(2, '0')}';
  String get _toStr =>
      '${_to.year.toString().padLeft(4, '0')}-${_to.month.toString().padLeft(2, '0')}-${_to.day.toString().padLeft(2, '0')}';

  bool get _isBusy => _status == 'running' || _status == 'pending';

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _from : _to;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2017, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = picked;
        if (_from.isAfter(_to)) _from = _to;
      }
    });
  }

  Future<void> _start() async {
    final symbol = _symbolCtrl.text.trim().toUpperCase();
    if (symbol.isEmpty) {
      _showError('Symbol cannot be empty');
      return;
    }
    if (_from.isAfter(_to)) {
      _showError('"From" must be on or before "To"');
      return;
    }

    setState(() {
      _status = 'pending';
      _progress = 0;
      _message = 'Submitting…';
      _candlesAdded = null;
    });

    try {
      final api = ref.read(apiClientProvider);
      final jobId = await api.downloadCandles(
        symbol: symbol,
        timeframe: _timeframe,
        dateFrom: _fromStr,
        dateTo: _toStr,
      );
      if (!mounted) return;
      setState(() {
        _jobId = jobId;
        _status = 'running';
        _message = 'Job $jobId queued…';
      });
      _startPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'error';
        _message = e.toString();
      });
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 800), (_) => _pollOnce());
    // Fire one immediately so the user sees status flip from "queued" fast.
    _pollOnce();
  }

  Future<void> _pollOnce() async {
    final id = _jobId;
    if (id == null) return;
    try {
      final api = ref.read(apiClientProvider);
      final data = await api.fetchJobStatus(id);
      if (!mounted) return;

      final status = (data['status'] as String?) ?? 'unknown';
      final progress = (data['progress'] as num?)?.toDouble() ?? 0.0;
      final message = data['message'] as String?;
      final result = data['result'] as Map<String, dynamic>?;
      final added = result?['candles_added'] as int?;

      setState(() {
        _status = status;
        _progress = progress;
        _message = message;
        _candlesAdded = added;
      });

      if (status == 'done' || status == 'error') {
        _poll?.cancel();
        // Refresh sidebar symbols list — new data is now queryable.
        ref.invalidate(symbolsProvider);
      }
    } catch (e) {
      // Don't kill the poller on transient errors — backend may briefly
      // hiccup. Show the error in the message field but keep polling.
      if (!mounted) return;
      setState(() => _message = 'Poll error: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFEF5350),
        content: Text(msg, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final canClose = !_isBusy;

    return AlertDialog(
      backgroundColor: const Color(0xFF1E222D),
      title: Row(
        children: [
          const Icon(Icons.cloud_download_outlined,
              size: 18, color: Color(0xFF2962FF)),
          const SizedBox(width: 8),
          Text('Download history', style: tt.titleMedium),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Symbol ──
            Text('Symbol', style: tt.bodySmall),
            const SizedBox(height: 4),
            TextFormField(
              controller: _symbolCtrl,
              enabled: !_isBusy,
              textCapitalization: TextCapitalization.characters,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'BTCUSDT',
                hintStyle: TextStyle(fontSize: 12, color: Color(0xFF6E7079)),
              ),
            ),
            const SizedBox(height: 12),

            // ── Timeframe ──
            Text('Timeframe', style: tt.bodySmall),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: _timeframe,
              isDense: true,
              dropdownColor: const Color(0xFF1E222D),
              style: const TextStyle(fontSize: 12, color: Color(0xFFD1D4DC)),
              decoration: const InputDecoration(isDense: true),
              items: _timeframes
                  .map((tf) => DropdownMenuItem(value: tf, child: Text(tf)))
                  .toList(),
              onChanged: _isBusy ? null : (v) => setState(() => _timeframe = v!),
            ),
            const SizedBox(height: 12),

            // ── Dates ──
            Row(
              children: [
                Expanded(child: _dateField('From', _fromStr, isFrom: true)),
                const SizedBox(width: 8),
                Expanded(child: _dateField('To', _toStr, isFrom: false)),
              ],
            ),
            const SizedBox(height: 16),

            // ── Progress ──
            if (_status != 'idle') ...[
              LinearProgressIndicator(
                value: _status == 'done'
                    ? 1.0
                    : (_status == 'error' ? null : _progress),
                color: _status == 'error'
                    ? const Color(0xFFEF5350)
                    : (_status == 'done'
                        ? const Color(0xFF26A69A)
                        : const Color(0xFF2962FF)),
                backgroundColor: const Color(0xFF2A2E39),
                minHeight: 4,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _statusBadge(),
                  const SizedBox(width: 8),
                  if (_jobId != null)
                    Text('job ${_jobId!.substring(0, _jobId!.length.clamp(0, 8))}',
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF6E7079))),
                  const Spacer(),
                  if (_candlesAdded != null)
                    Text('+${_candlesAdded!} candles',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF26A69A))),
                ],
              ),
              if (_message != null) ...[
                const SizedBox(height: 4),
                Text(_message!,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFB2B5BE))),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: canClose ? () => Navigator.of(context).pop() : null,
          child: Text(_status == 'done' ? 'Close' : 'Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isBusy ? null : _start,
          icon: _isBusy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download, size: 16),
          label: Text(_status == 'done' ? 'Download again' : 'Download'),
        ),
      ],
    );
  }

  Widget _dateField(String label, String value, {required bool isFrom}) {
    return InkWell(
      onTap: _isBusy ? null : () => _pickDate(isFrom: isFrom),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          labelStyle: const TextStyle(fontSize: 11),
        ),
        child: Text(value, style: const TextStyle(fontSize: 12)),
      ),
    );
  }

  Widget _statusBadge() {
    Color color;
    String text;
    switch (_status) {
      case 'pending':
      case 'running':
        color = const Color(0xFF2962FF);
        text = _status.toUpperCase();
        break;
      case 'done':
        color = const Color(0xFF26A69A);
        text = 'DONE';
        break;
      case 'error':
        color = const Color(0xFFEF5350);
        text = 'ERROR';
        break;
      default:
        color = const Color(0xFF6E7079);
        text = _status.toUpperCase();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}
