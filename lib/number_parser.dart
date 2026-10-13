double parseNumber(String value) {
  const faDigits = '۰۱۲۳۴۵۶۷۸۹';
  const arDigits = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(faDigits[i], '$i');
    value = value.replaceAll(arDigits[i], '$i');
  }
  value = value.replaceAll(',', '').replaceAll('٬', '').trim();
  return double.tryParse(value) ?? 0;
}

double? tryParseNumber(String value) {
  const faDigits = '۰۱۲۳۴۵۶۷۸۹';
  const arDigits = '٠١٢٣٤٥٦٧٨٩';

  value = value.trim();
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(faDigits[i], '$i');
    value = value.replaceAll(arDigits[i], '$i');
  }

  value = value
      .replaceAll('٫', '.')
      .replaceAll(',', '')
      .replaceAll('٬', '')
      .trim();

  if (value.isEmpty) return null;

  final result = double.tryParse(value);
  if (result == null || !result.isFinite) return null;
  return result;
}
