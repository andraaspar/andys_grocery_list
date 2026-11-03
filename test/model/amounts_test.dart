import 'package:andys_grocery_list/model/amounts.dart';
import 'package:andys_grocery_list/model/number_parser.dart';
import 'package:andys_grocery_list/model/todo_document.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

const en = NumberContext.en;
Decimal d(String s) => Decimal.parse(s);

void main() {
  group('quantity', () {
    test('parsing', () {
      expect(parseQuantity('3x Milk', en)!.value, d('3'));
      expect(parseQuantity('1,5x', en)!.value, d('1.5'));
      expect(parseQuantity('0.25x Butter', en)!.value, d('0.25'));
      expect(parseQuantity('Milk', en), isNull);
      expect(quantityOf('Milk', en), Decimal.one);
      expect(parseQuantity('2x', en)!.value, d('2'));
      expect(parseQuantity('0x', en)!.value, Decimal.zero);
      expect(parseQuantity('.5x', en), isNull);
      expect(parseQuantity('3xMilk', en), isNull);
      final q = parseQuantity('12x  spaced', en)!;
      expect(q.value, d('12'));
      expect((q.start, q.end), (0, 2));
    });

    test('increment', () {
      void check(String input, String output, String number) {
        final r = incrementQuantity(input, en);
        expect(r.text, output);
        expect(r.text.substring(r.start, r.end), number);
      }

      check('Milk', '2x Milk', '2');
      check('9x', '10x', '10');
      check('1,5x Cheese', '2,5x Cheese', '2,5');
      check('0.25x', '1.25x', '1.25');
      check('', '2x ', '2');
    });

    test('strip quantity of one', () {
      expect(stripQuantityOne('1x Milk', en), 'Milk');
      expect(stripQuantityOne('1.0x Milk', en), 'Milk');
      expect(stripQuantityOne('1,00x Milk', en), 'Milk');
      expect(stripQuantityOne('1x', en), '');
      expect(stripQuantityOne('3x Milk', en), '3x Milk');
      expect(stripQuantityOne('1.5x Milk', en), '1.5x Milk');
    });
  });

  group('price', () {
    Decimal? price(String s) => parsePrice(s, en)?.value;
    test('parsing', () {
      expect(price('Milk 1.29'), d('1.29'));
      expect(price('Bread 2,49'), d('2.49'));
      expect(price('Machine 1.299,00'), d('1299'));
      expect(price('TV 1,299.00'), d('1299'));
      expect(price('Coupon -1'), d('-1'));
      expect(price('5'), d('5'));
      expect(price('3x 2'), d('2'));
      expect(price('2x'), isNull);
      expect(price('Room 12b'), isNull);
      expect(price('5€'), isNull);
      expect(price('Milk  -0.5'), d('-0.5'));
      expect(price('Milk'), isNull);
      expect(price(''), isNull);
      expect(price('   '), isNull);
    });
    test('trailing whitespace is ignored', () {
      expect(price('Milk 1.29 '), d('1.29'));
      expect(price('Milk 1.29\t  '), d('1.29'));
      expect(price('Milk 1.29\u00A0'), d('1.29'));
      expect(price('5 '), d('5'));
      expect(price('Milk 1.29 .'), isNull);
      expect(price('Milk 1.29 x '), isNull);
      final m = parsePrice('Milk 1.29  ', en)!;
      expect((m.start, m.end), (5, 9));
    });
    test('range', () {
      final m = parsePrice('3x Milk 1.29', en)!;
      expect((m.start, m.end), (8, 12));
    });
  });

  group('totals', () {
    TodoList list(List<(ItemState, String)> items) => TodoList(
      items: [for (final (s, t) in items) TodoItem(state: s, text: t)],
    );

    test('only DONE items count, quantity × price, negatives', () {
      final t = listTotal(
        list([
          (ItemState.done, '3x Milk 1.29'),
          (ItemState.newItem, 'Bread 2.49'),
          (ItemState.failed, 'Basil 0.99'),
          (ItemState.done, 'Coupon -1'),
          (ItemState.done, 'No price'),
        ]),
        en,
      )!;
      expect(t.sum, d('2.87'));
      expect(t.fractionDigits, 2);
    });

    test('exact decimals', () {
      final t = listTotal(list([(ItemState.done, '3x Thing 0.1')]), en)!;
      expect(t.sum, d('0.3'));
      expect(lineTotal(TodoItem(text: '1.5x X 1.99'), en), d('2.985'));
    });

    test('no prices → no total; prices but none done → 0', () {
      expect(listTotal(list([(ItemState.done, 'Milk')]), en), isNull);
      expect(
        listTotal(list([(ItemState.newItem, 'Milk 1')]), en)!.sum,
        Decimal.zero,
      );
    });

    test('formatting per locale', () {
      final t = ListTotal(d('1317.825'), 2);
      expect(formatTotal(t, 'en_US'), '1,317.83');
      expect(formatTotal(t, 'de_DE'), '1.317,83');
      expect(formatTotal(t, 'hu_HU'), matches(RegExp(r'^1\s317,83$')));
      expect(formatTotal(ListTotal(d('-1.5'), 1), 'en_US'), '-1.5');
      expect(formatTotal(ListTotal(d('-0.25'), 1), 'en_US'), '-0.3');
      expect(formatTotal(ListTotal(d('0'), 0), 'en_US'), '0');
      expect(formatTotal(ListTotal(d('2.5'), 0), 'en_US'), '3');
    });
  });
}
