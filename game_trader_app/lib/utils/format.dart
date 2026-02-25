String formatCurrency(double? value) {
  if (value == null) {
    return '--';
  }
  return '\$${value.toStringAsFixed(2)}';
}
