import 'package:flutter_test/flutter_test.dart';
import 'package:anbarban/number_parser.dart';

void main() {
  group('tryParseNumber', () {
    test('parses Persian digits and decimal separator', () {
      expect(tryParseNumber('۱۲۳۴٫۵'), 1234.5);
    });

    test('parses Arabic-Indic digits', () {
      expect(tryParseNumber('١٢٫٥'), 12.5);
    });

    test('removes Persian thousands separator', () {
      expect(tryParseNumber('۱٬۲۳۴٫۵'), 1234.5);
    });

    test('removes comma thousands separators', () {
      expect(tryParseNumber('1,234.5'), 1234.5);
    });

    test('returns null for empty or invalid input', () {
      expect(tryParseNumber(''), isNull);
      expect(tryParseNumber('   '), isNull);
      expect(tryParseNumber('abc'), isNull);
    });

    test('rejects non-finite values', () {
      expect(tryParseNumber('NaN'), isNull);
      expect(tryParseNumber('Infinity'), isNull);
    });
  });

  group('parseNumber', () {
    test('preserves legacy behavior for invalid input', () {
      expect(parseNumber('abc'), 0);
    });

    test('parses Persian digits', () {
      expect(parseNumber('۱۲۳'), 123);
    });
  });
}
