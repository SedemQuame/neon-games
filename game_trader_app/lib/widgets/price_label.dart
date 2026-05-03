import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../utils/format.dart';

class PriceLabel extends StatelessWidget {
  const PriceLabel({
    super.key,
    required this.value,
    this.label = 'Entry',
    this.emphasis = false,
    this.prefix,
  });

  final num? value;
  final String label;
  final bool emphasis;
  final String? prefix;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final amount = formatCurrency(value);
    final fullLabel = prefix == null ? label : '$label $prefix';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          fullLabel,
          style: context.type.label.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(width: context.space.xs),
        Text(
          amount,
          style: context.type.bodyStrong.copyWith(
            color: emphasis ? colors.primary : colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
