import 'package:flutter_test/flutter_test.dart';
import 'package:anbarban/number_parser.dart';
import 'package:anbarban/formatters.dart';

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

  group('formatNumber', () {
    test('groups thousands and uses Persian digits', () {
      expect(formatNumber(1234567), '۱٬۲۳۴٬۵۶۷');
    });

    test('formats decimal values without trailing zeros', () {
      expect(formatNumber(1234567.5), '۱٬۲۳۴٬۵۶۷٫۵');
      expect(formatNumber(12.34), '۱۲٫۳۴');
      expect(formatNumber(12.0), '۱۲');
    });

    test('formats negative values', () {
      expect(formatNumber(-1234.5), '-۱٬۲۳۴٫۵');
    });

    test('rounds to the requested decimal precision', () {
      expect(formatNumber(12.345, maxDecimals: 2), '۱۲٫۳۵');
      expect(formatNumber(12.345, maxDecimals: 1), '۱۲٫۳');
    });

    test('handles non-finite values safely', () {
      expect(formatNumber(double.nan), '۰');
      expect(formatNumber(double.infinity), '۰');
    });

    test('rejects invalid decimal precision', () {
      expect(() => formatNumber(1, maxDecimals: -1), throwsArgumentError);
      expect(() => formatNumber(1, maxDecimals: 11), throwsArgumentError);
    });
  });

  group('formatMoney', () {
    test('adds the currency after a grouped amount', () {
      expect(formatMoney(1234567.5), '۱٬۲۳۴٬۵۶۷٫۵ تومان');
    });

    test('supports a custom currency label', () {
      expect(formatMoney(2500, currency: 'ریال'), '۲٬۵۰۰ ریال');
    });
  });
}
