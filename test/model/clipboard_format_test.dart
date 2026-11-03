import 'package:andys_grocery_list/model/clipboard_format.dart';
import 'package:andys_grocery_list/model/number_parser.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  const en = NumberContext.en;
  test('all NEW → dash prefix', () {
    final d = doc('# A\n- [ ] 3x Milk\n- [ ] 1x Bread\n');
    expect(formatItems(d.lists[0].items, en), '- 3x Milk\n- Bread\n');
  });

  test('mixed → backing format', () {
    final d = doc('# A\n- [ ] a\n- [x] b\n- [x] FAILED c\n');
    expect(
      formatItems(d.lists[0].items, en),
      '- [ ] a\n- [x] b\n- [x] FAILED c\n',
    );
  });

  test('copy list includes name and skips empty items', () {
    final d = doc('# Shop\n- [ ] \n- [ ] a\n- [ ] \n');
    expect(formatList(d.lists[0], en), '# Shop\n- a\n');
  });
}
