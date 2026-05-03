import 'package:flutter/material.dart';

class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = 0.985,
    this.duration = const Duration(milliseconds: 110),
  });

  final Widget child;
  final bool enabled;
  final double pressedScale;
  final Duration duration;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!widget.enabled) {
      if (_pressed) {
        setState(() => _pressed = false);
      }
      return;
    }
    if (_pressed != value) {
      setState(() => _pressed = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        duration: widget.duration,
        curve: Curves.easeOut,
        scale: _pressed && widget.enabled ? widget.pressedScale : 1,
        child: widget.child,
      ),
    );
  }
}
