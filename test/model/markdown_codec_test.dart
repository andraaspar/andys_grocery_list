import 'package:andys_grocery_list/model/markdown_codec.dart';
import 'package:andys_grocery_list/model/todo_document.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  test('every state round-trips', () {
    const src =
        '# Groceries\n'
        '- [ ] 3x Milk 1.29\n'
        '- [x] Bread 2,49\n'
        '- [x] FAILED 2x Fresh basil 0.99\n'
        '\n'
        '# Work\n'
        '- [ ] Write report\n';
    final d = doc(src);
    expect(d.lists.length, 2);
    expect(d.lists[0].items.map((i) => i.state), [
      ItemState.newItem,
      ItemState.done,
      ItemState.failed,
    ]);
    expect(d.lists[0].items[2].text, '2x Fresh basil 0.99');
    expect(md(d), src);
  });

  test('[X] and CRLF', () {
    final d = doc('# A\r\n- [X] one\r\n- [X] FAILED two\r\n');
    expect(d.lists[0].items[0].state, ItemState.done);
    expect(d.lists[0].items[0].text, 'one');
    expect(d.lists[0].items[1].state, ItemState.failed);
    expect(md(d), '# A\n- [x] one\n- [x] FAILED two\n');
  });

  test('items before the first header, file mode', () {
    final d = doc('- [ ] loose\n# A\n- [ ] a\n');
    expect(d.lists.length, 2);
    expect(d.lists[0].name, '');
    expect(md(d), '# \n- [ ] loose\n\n# A\n- [ ] a\n');
  });

  test('items before the first header, fragment mode', () {
    final f = parseFragment('- [x] loose\nplain\n# A\n- [ ] a\n# B\n');
    expect(f.looseItems.map((i) => (i.state, i.text)), [
      (ItemState.done, 'loose'),
      (ItemState.newItem, 'plain'),
    ]);
    expect(f.lists.map((l) => l.name), ['A', 'B']);
    expect(f.lists[1].items, isEmpty);
  });

  test('lenient lines', () {
    final d = doc('# A\n- dash\n* star\nplain line\n\n   \n');
    expect(d.lists.single.items.map((i) => i.text), [
      'dash',
      'star',
      'plain line',
    ]);
    expect(
      d.lists.single.items.every((i) => i.state == ItemState.newItem),
      isTrue,
    );
  });

  test('empty file', () {
    expect(md(doc('')), '# \n- [ ] \n');
    expect(md(doc('\n\n')), '# \n- [ ] \n');
  });

  test('empty items round-trip; header with no items gets one', () {
    expect(md(doc('# A\n- [ ] \n- [ ] x\n')), '# A\n- [ ] \n- [ ] x\n');
    expect(md(doc('# A\n# B\n- [ ] b\n')), '# A\n- [ ] \n\n# B\n- [ ] b\n');
    expect(md(doc('#\n- [ ]\n')), '# \n- [ ] \n');
  });

  test('quantity of 1 removed on write', () {
    expect(
      md(
        doc(
          '# A\n- [ ] 1x a\n- [ ] 1.0x b\n- [ ] 1,00x c\n- [ ] 3x d\n- [ ] 1.5x e\n',
        ),
      ),
      '# A\n- [ ] a\n- [ ] b\n- [ ] c\n- [ ] 3x d\n- [ ] 1.5x e\n',
    );
  });
}
