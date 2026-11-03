import 'package:andys_grocery_list/model/number_parser.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

const locales = ['en_US', 'de_DE', 'fr_FR', 'hu_HU', 'de_CH'];

Decimal? p(String s, String locale) =>
    parseNumberToken(s, NumberContext.forLocale(locale))?.value;

Decimal d(String s) => Decimal.parse(s);

void main() {
  test('locale contexts', () {
    expect(NumberContext.forLocale('en_US').decimalSep, '.');
    expect(NumberContext.forLocale('de_DE').decimalSep, ',');
    expect(NumberContext.forLocale('de_DE').groupSep, '.');
    expect(NumberContext.forLocale('xx_YY').decimalSep, '.');
  });

  for (final l in locales) {
    group(l, () {
      test('both separators', () {
        expect(p('1.234,50', l), d('1234.5'));
        expect(p('1,234.50', l), d('1234.5'));
      });
      test('repeated separator', () {
        expect(p('1.234.567', l), d('1234567'));
        expect(p('1,234,567', l), d('1234567'));
      });
      test('single separator, not 3 digits', () {
        expect(p('2,49', l), d('2.49'));
        expect(p('1.5', l), d('1.5'));
      });
      test('other grouping', () {
        expect(p("1'234.50", l), d('1234.5'));
        expect(p('1 234,50', l), d('1234.5'));
        expect(p('1 234,50', l), d('1234.5'));
        expect(p('1 234', l), isNull);
      });
      test('malformed', () {
        for (final s in [
          '12.34.5',
          '1,23,456',
          '.5',
          '5.',
          '',
          '-',
          '1..2',
          'a1',
          '1€',
          '1.2,3.4',
        ]) {
          expect(p(s, l), isNull, reason: s);
        }
      });
      test('signs', () {
        expect(p('-5', l), d('-5'));
        expect(p('−5', l), d('-5'));
        expect(
          parseNumberToken('-5', NumberContext.forLocale(l), signed: false),
          isNull,
        );
      });
    });
  }

  test('single separator with 3 digits depends on locale', () {
    expect(p('1,234', 'en_US'), d('1234'));
    expect(p('1,234', 'de_DE'), d('1.234'));
    expect(p('1.234', 'en_US'), d('1.234'));
    expect(p('1.234', 'de_DE'), d('1234'));
  });

  test('reports decimal char and fraction digits', () {
    final n = parseNumberToken('1.299,00', NumberContext.en)!;
    expect(n.decimalChar, ',');
    expect(n.fractionDigits, 2);
  });
}
