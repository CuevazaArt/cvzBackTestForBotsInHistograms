import 'package:flutter/material.dart';

/// Animated dot showing backend connection status.
class StatusDot extends StatefulWidget {
  final bool online;
  final bool checking;
  const StatusDot({super.key, required this.online, required this.checking});

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() { _anim.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (widget.checking) {
      return FadeTransition(
        opacity: _anim,
        child: _dot(const Color(0xFF787B86)),
      );
    }
    return _dot(widget.online ? const Color(0xFF26a69a) : const Color(0xFFef5350));
  }

  Widget _dot(Color c) => Container(
    width: 10, height: 10,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );
}
