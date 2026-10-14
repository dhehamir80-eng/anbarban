String fa(String value) {
  const en = '0123456789';
  const faDigits = '۰۱۲۳۴۵۶۷۸۹';

  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(en[i], faDigits[i]);
  }

  return value;
}

/// Formats numeric values with Persian digits and standard separators.
/// Non-finite values are displayed as zero to avoid invalid UI output.
String formatNumber(
  num value, {
  int maxDecimals = 2,
}) {
  if (!value.isFinite) return '۰';
  if (maxDecimals < 0 || maxDecimals > 10) {
    throw ArgumentError.value(maxDecimals, 'maxDecimals');
  }

  final negative = value < 0;
  final absolute = value.abs();
  var raw = absolute.toStringAsFixed(maxDecimals);

  if (raw.contains('.')) {
    raw = raw.replaceFirst(RegExp(r'0+$'), '');
    raw = raw.replaceFirst(RegExp(r'\.$'), '');
  }

  final parts = raw.split('.');
  final integer = parts.first;
  final grouped = integer.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '٬',
  );

  final decimal = parts.length > 1 ? '٫${parts[1]}' : '';
  final sign = negative && absolute != 0 ? '-' : '';

  return fa('$sign$grouped$decimal');
}

/// Formats a monetary value in Iranian tomans.
String formatMoney(
  num value, {
  String currency = 'تومان',
  int maxDecimals = 2,
}) {
  return '${formatNumber(value, maxDecimals: maxDecimals)} $currency';
}
