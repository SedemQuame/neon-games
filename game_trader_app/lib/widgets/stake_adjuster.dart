import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_theme.dart';

class StakeAdjuster extends StatefulWidget {
  const StakeAdjuster({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 1000,
    this.step = 1,
    this.label = 'STAKE',
    this.enabled = true,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double step;
  final String label;
  final bool enabled;

  @override
  State<StakeAdjuster> createState() => _StakeAdjusterState();
}

class _StakeAdjusterState extends State<StakeAdjuster> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _formatValue(widget.value));
    _focusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant StakeAdjuster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus && oldWidget.value != widget.value) {
      _controller.text = _formatValue(widget.value);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _update(double delta) {
    if (!widget.enabled) return;
    final next = (widget.value + delta)
        .clamp(widget.min, widget.max)
        .toDouble();
    widget.onChanged(next);
  }

  void _commitInput([String? raw]) {
    final parsed = _tryParse(raw ?? _controller.text);
    if (parsed == null) {
      _controller.text = _formatValue(widget.value);
      return;
    }
    final next = parsed.clamp(widget.min, widget.max).toDouble();
    widget.onChanged(next);
    _controller
      ..text = _formatValue(next)
      ..selection = TextSelection.collapsed(offset: _controller.text.length);
  }

  String _formatValue(double value) => value.toStringAsFixed(2);

  double? _tryParse(String raw) {
    final normalized = raw.replaceAll(RegExp(r'[^0-9.]'), '');
    if (normalized.isEmpty) {
      return null;
    }
    return double.tryParse(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.bgCard,
        borderRadius: BorderRadius.circular(context.radii.xl),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.label.toUpperCase(),
                  style: context.type.label.copyWith(
                    color: colors.textSecondary,
                    letterSpacing: 0,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: widget.enabled,
                    textAlign: TextAlign.left,
                    textInputAction: TextInputAction.done,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                    ],
                    onChanged: (raw) {
                      final parsed = _tryParse(raw);
                      if (parsed != null) {
                        final next = parsed
                            .clamp(widget.min, widget.max)
                            .toDouble();
                        widget.onChanged(next);
                      }
                    },
                    onSubmitted: _commitInput,
                    onEditingComplete: _commitInput,
                    onTapOutside: (_) {
                      _focusNode.unfocus();
                      _commitInput();
                    },
                    style: context.type.bodyStrong.copyWith(
                      color: colors.textPrimary,
                      fontSize: 34,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                    cursorColor: colors.primary,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      errorBorder: InputBorder.none,
                      focusedErrorBorder: InputBorder.none,
                      prefixText: r'$',
                      prefixStyle: context.type.bodyStrong.copyWith(
                        color: colors.textPrimary,
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                      hintText: '0.00',
                      hintStyle: context.type.bodyStrong.copyWith(
                        color: colors.textSecondary,
                        fontSize: 34,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          _AdjusterButton(
            icon: Icons.remove,
            enabled: widget.enabled,
            onTap: () => _update(-widget.step),
          ),
          const SizedBox(width: 8),
          _AdjusterButton(
            icon: Icons.add,
            enabled: widget.enabled,
            onTap: () => _update(widget.step),
          ),
        ],
      ),
    );
  }
}

class _AdjusterButton extends StatelessWidget {
  const _AdjusterButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.goldButtonTop, AppTheme.goldButtonBottom],
            ),
            shape: BoxShape.circle,
            border: Border.all(
              color: AppTheme.primarySoft.withValues(alpha: 0.4),
            ),
          ),
          child: Icon(
            icon,
            color: AppTheme.goldText.withValues(alpha: enabled ? 1 : 0.4),
            size: 20,
          ),
        ),
      ),
    );
  }
}
