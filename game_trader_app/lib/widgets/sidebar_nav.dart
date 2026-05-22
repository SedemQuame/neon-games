import 'package:flutter/material.dart';

import '../app_theme.dart';

class SidebarNav extends StatelessWidget {
  const SidebarNav({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 240,
      color: AppTheme.navBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const _SidebarItem(icon: Icons.casino_outlined, label: 'Casino', active: true),
          const _SidebarItem(icon: Icons.sports_baseball_outlined, label: 'Sports'),
          const _SidebarItem(icon: Icons.star_border, label: 'VIP'),
          const _SidebarItem(icon: Icons.support_agent_outlined, label: 'Live Support'),
          const Spacer(),
          const _SidebarItem(icon: Icons.language, label: 'English'),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.label,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final bool active;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final activeColor = AppTheme.primaryColor;
    final inactiveColor = AppTheme.textSecondary;
    final hoverColor = Colors.white;

    final color = widget.active
        ? activeColor
        : (_hovering ? hoverColor : inactiveColor);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: InkWell(
        onTap: () {},
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: widget.active ? AppTheme.surfaceDark.withValues(alpha: 0.5) : Colors.transparent,
            border: Border(
              left: BorderSide(
                color: widget.active ? AppTheme.primaryColor : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(widget.icon, color: color, size: 20),
              const SizedBox(width: 16),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.active ? Colors.white : color,
                  fontWeight: widget.active ? FontWeight.bold : FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
