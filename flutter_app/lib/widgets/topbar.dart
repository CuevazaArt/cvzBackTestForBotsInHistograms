import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/backtest_state.dart';
import 'download_history_dialog.dart';

class AppTopBar extends ConsumerWidget implements PreferredSizeWidget {
  final VoidCallback onRun;
  final bool isRunning;

  const AppTopBar({super.key, required this.onRun, this.isRunning = false});

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configProvider);

    return Container(
      height: 44,
      color: const Color(0xFF1E222D),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          // Logo / brand
          const Text('Backtester',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF2962FF))),
          const SizedBox(width: 16),

          // Symbol chip
          _Chip(cfg.symbol),
          const SizedBox(width: 6),

          // Timeframe chip
          _Chip(cfg.timeframe),
          const SizedBox(width: 6),

          // Bot chip
          _Chip(cfg.bot, color: const Color(0xFF2962FF)),

          const Spacer(),

          // ── Download history button (always visible) ────────────────
          // The download flow is the primary entry point for the tool — no
          // local candles means no backtest can run — so this is intentionally
          // surfaced at the top level and is not gated by any other action.
          SizedBox(
            height: 30,
            child: OutlinedButton.icon(
              onPressed: () => DownloadHistoryDialog.show(context),
              icon: const Icon(Icons.cloud_download_outlined, size: 16),
              label: const Text('Download history'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFD1D4DC),
                side: const BorderSide(color: Color(0xFF2A2E39)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // ── Run button ──────────────────────────────────────────────
          SizedBox(
            height: 30,
            child: isRunning
                ? const Row(children: [
                    SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Running…', style: TextStyle(fontSize: 12)),
                  ])
                : ElevatedButton.icon(
                    onPressed: onRun,
                    icon: const Icon(Icons.play_arrow, size: 16),
                    label: const Text('Run'),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color? color;
  const _Chip(this.label, {this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2E39),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, color: color ?? const Color(0xFFD1D4DC))),
    );
  }
}
