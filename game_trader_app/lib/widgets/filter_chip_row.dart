import 'package:flutter/material.dart';

import '../app_theme.dart';
import 'press_scale.dart';

class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
  });

  final List<String> options;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: options.length,
        separatorBuilder: (context, index) => SizedBox(width: context.space.xs),
        itemBuilder: (context, index) {
          final option = options[index];
          final isSelected = option == selected;

          return PressScale(
            child: Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? context.colors.primary
                    : context.colors.bgCard,
                borderRadius: BorderRadius.circular(context.radii.pill),
                border: Border.all(
                  color: isSelected
                      ? context.colors.primary.withValues(alpha: 0.7)
                      : context.colors.border,
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(context.radii.pill),
                  onTap: () => onSelected(option),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.space.md,
                      vertical: context.space.xs,
                    ),
                    child: Center(
                      child: Text(
                        option,
                        style: context.type.chipLabel.copyWith(
                          color: isSelected
                              ? AppTheme.goldText
                              : context.colors.textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
