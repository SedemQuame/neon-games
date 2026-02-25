import 'package:flutter/material.dart';

import '../app_theme.dart';

class StakeAdjuster extends StatelessWidget {
  const StakeAdjuster({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 1,
    this.max = 1000,
    this.step = 1,
    this.label = 'STAKE',
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double min;
  final double max;
  final double step;
  final String label;

  void _update(double delta) {
    final next = (value + delta).clamp(min, max);
    onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94a3b8),
            fontSize: 10,
            letterSpacing: 1.4,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppTheme.surfaceDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.borderDark),
          ),
          child: Row(
            children: [
              _AdjusterButton(icon: Icons.remove, onTap: () => _update(-step)),
              Expanded(
                child: Center(
                  child: Text(
                    '\$${value.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              _AdjusterButton(icon: Icons.add, onTap: () => _update(step)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdjusterButton extends StatelessWidget {
  const _AdjusterButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}
