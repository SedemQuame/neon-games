String formatCurrency(num? value, {String symbol = r'$'}) {
  if (value == null) {
    return '--';
  }
  return '$symbol${value.toDouble().toStringAsFixed(2)}';
}

String formatSignedCurrency(num value, {String symbol = r'$'}) {
  final amount = value.toDouble();
  final prefix = amount >= 0 ? '+' : '-';
  return '$prefix${formatCurrency(amount.abs(), symbol: symbol)}';
}

String formatMinStake(num? value, {String label = 'Min Stake'}) {
  return '$label ${formatCurrency(value)}';
}

String formatFromAmount(num? value, {String label = 'From'}) {
  return '$label ${formatCurrency(value)}';
}
