import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/play_mode.dart';

class PlayModeToggle extends StatelessWidget {
  const PlayModeToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final PlayMode value;
  final ValueChanged<PlayMode> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.gameSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gameBorder),
      ),
      child: Row(
        children: [
          _ModeSegment(
            label: 'Demo',
            icon: Icons.sports_esports_rounded,
            selected: value == PlayMode.demo,
            enabled: enabled,
            onTap: () => onChanged(PlayMode.demo),
          ),
          const SizedBox(width: 4),
          _ModeSegment(
            label: 'Real',
            icon: Icons.account_balance_wallet_rounded,
            selected: value == PlayMode.real,
            enabled: enabled,
            onTap: () => onChanged(PlayMode.real),
          ),
        ],
      ),
    );
  }
}

class _ModeSegment extends StatelessWidget {
  const _ModeSegment({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppTheme.goldText : AppTheme.textPrimary;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled && !selected ? onTap : null,
          borderRadius: BorderRadius.circular(10),
          child: Ink(
            height: 38,
            decoration: BoxDecoration(
              color: selected ? AppTheme.goldButtonBottom : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: foreground.withValues(alpha: enabled ? 1 : 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: foreground.withValues(alpha: enabled ? 1 : 0.5),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
