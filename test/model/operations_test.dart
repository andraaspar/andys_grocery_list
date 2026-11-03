import 'package:andys_grocery_list/model/number_parser.dart';
import 'package:andys_grocery_list/model/operations.dart';
import 'package:andys_grocery_list/model/todo_document.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void expectInvariants(TodoDocument d) {
  expect(d.lists, isNotEmpty);
  for (final l in d.lists) {
    expect(l.items, isNotEmpty);
  }
}

void main() {
  group('Enter', () {
    test('at the end of a non-empty line inserts an empty NEW item below', () {
      final d = doc('# A\n- [x] milk\n- [ ] b\n');
      final r = enter(d, idAt(d, 0, 0), 4);
      expect(md(r.doc), '# A\n- [x] milk\n- [ ] \n- [ ] b\n');
      expect(r.cursor, CursorTarget.item(idAt(r.doc, 0, 1), 0));
    });

    test('in the middle splits; the second part is NEW', () {
      final d = doc('# A\n- [x] milkbread\n');
      final r = enter(d, idAt(d, 0, 0), 4);
      expect(md(r.doc), '# A\n- [x] milk\n- [ ] bread\n');
      expect(r.cursor, CursorTarget.item(idAt(r.doc, 0, 1), 0));
    });

    test('at the start inserts an empty item above and keeps focus', () {
      final d = doc('# A\n- [x] milk\n');
      final id = idAt(d, 0, 0);
      final r = enter(d, id, 0);
      expect(md(r.doc), '# A\n- [ ] \n- [x] milk\n');
      expect(r.cursor, CursorTarget.item(id, 0));
    });

    test('on an empty item creates a new list with the items below', () {
      final d = doc('# A\n- [ ] a\n- [ ] \n- [ ] b\n- [ ] c\n');
      final r = enter(d, idAt(d, 0, 1), 0);
      expect(md(r.doc), '# A\n- [ ] a\n\n# \n- [ ] b\n- [ ] c\n');
      expect(r.cursor, CursorTarget.listName(r.doc.lists[1].id, 0, 0));
    });

    test('on the only (empty) item of a list', () {
      final d = doc('# A\n- [ ] \n\n# B\n- [ ] b\n');
      final r = enter(d, idAt(d, 0, 0), 0);
      expect(md(r.doc), '# A\n- [ ] \n\n# \n- [ ] \n\n# B\n- [ ] b\n');
      expectInvariants(r.doc);
    });
  });

  group('Backspace at start', () {
    test('merges with the previous item, which keeps its state', () {
      final d = doc('# A\n- [x] milk\n- [ ] bread\n');
      final r = backspaceAtStart(d, idAt(d, 0, 1))!;
      expect(md(r.doc), '# A\n- [x] milkbread\n');
      expect(r.cursor, CursorTarget.item(idAt(d, 0, 0), 4));
    });

    test('on an empty item deletes it', () {
      final d = doc('# A\n- [ ] milk\n- [ ] \n');
      final r = backspaceAtStart(d, idAt(d, 0, 1))!;
      expect(md(r.doc), '# A\n- [ ] milk\n');
    });

    test('on the first item merges the list into the previous one', () {
      final d = doc('# A\n- [ ] a\n\n# B\n- [x] b\n- [ ] c\n');
      final id = idAt(d, 1, 0);
      final r = backspaceAtStart(d, id)!;
      expect(md(r.doc), '# A\n- [ ] a\n- [x] b\n- [ ] c\n');
      expect(r.cursor, CursorTarget.item(id, 0));
    });

    test('merging drops the previous list\'s only empty item', () {
      final d = doc('# A\n- [ ] \n\n# B\n- [ ] b\n');
      final r = backspaceAtStart(d, idAt(d, 1, 0))!;
      expect(md(r.doc), '# A\n- [ ] b\n');
    });

    test('on the first item of the first list does nothing', () {
      final d = doc('# A\n- [ ] a\n');
      expect(backspaceAtStart(d, idAt(d, 0, 0)), isNull);
    });
  });

  group('paste', () {
    test('plain detection', () {
      expect(isPlainPaste('3x eggs'), isTrue);
      expect(isPlainPaste('eggs\n'), isTrue);
      expect(isPlainPaste('a\nb'), isFalse);
      expect(isPlainPaste('- eggs'), isFalse);
      expect(isPlainPaste('# List'), isFalse);
    });

    test('multi-line plain text in the middle of an item', () {
      final d = doc('# A\n- [x] abcd\n- [ ] z\n');
      final r = paste(d, idAt(d, 0, 0), 2, 2, 'x\ny\n')!;
      expect(md(r.doc), '# A\n- [x] ab\n- [ ] x\n- [ ] y\n- [ ] cd\n- [ ] z\n');
      expect(r.cursor, CursorTarget.item(idAt(r.doc, 0, 2), 1));
    });

    test('lines with state prefixes and quantities', () {
      final d = doc('# A\n- [ ] a\n');
      final r = paste(
        d,
        idAt(d, 0, 0),
        1,
        1,
        '- [x] 3x milk\n- [x] FAILED basil\n',
      )!;
      expect(md(r.doc), '# A\n- [ ] a\n- [x] 3x milk\n- [x] FAILED basil\n');
    });

    test('into an empty item replaces it', () {
      final d = doc('# A\n- [ ] \n');
      final r = paste(d, idAt(d, 0, 0), 0, 0, 'x\ny')!;
      expect(md(r.doc), '# A\n- [ ] x\n- [ ] y\n');
    });

    test('replaces the selection', () {
      final d = doc('# A\n- [ ] aXXb\n');
      final r = paste(d, idAt(d, 0, 0), 1, 3, 'x\ny')!;
      expect(md(r.doc), '# A\n- [ ] a\n- [ ] x\n- [ ] y\n- [ ] b\n');
    });

    test(
      'lists pasted into the middle: the rest goes to the last pasted list',
      () {
        final d = doc('# A\n- [ ] a1\n- [ ] a2cut\n- [ ] a3\n\n# Z\n- [ ] z\n');
        final r = paste(
          d,
          idAt(d, 0, 1),
          2,
          2,
          'loose\n# P\n- p\n# Q\n- [x] q\n',
        )!;
        expect(
          md(r.doc),
          '# A\n- [ ] a1\n- [ ] a2\n- [ ] loose\n\n'
          '# P\n- [ ] p\n\n'
          '# Q\n- [x] q\n- [ ] cut\n- [ ] a3\n\n'
          '# Z\n- [ ] z\n',
        );
        expect(r.cursor, CursorTarget.item(r.doc.lists[2].items[0].id, 1));
      },
    );

    test('only an empty header', () {
      final d = doc('# A\n- [ ] \n');
      final r = paste(d, idAt(d, 0, 0), 0, 0, '# P\n')!;
      expect(md(r.doc), '# A\n- [ ] \n\n# P\n- [ ] \n');
      expect(r.cursor, CursorTarget.item(r.doc.lists[1].items[0].id, 0));
      expectInvariants(r.doc);
    });

    test('blank text does nothing', () {
      final d = doc('# A\n- [ ] a\n');
      expect(paste(d, idAt(d, 0, 0), 0, 0, '\n\n'), isNull);
    });
  });

  test('cycle state', () {
    var d = doc('# A\n- [ ] a\n');
    final id = idAt(d, 0, 0);
    final states = <ItemState>[];
    for (var i = 0; i < 3; i++) {
      d = cycleState(d, id).doc;
      states.add(d.itemById(id)!.state);
    }
    expect(states, [ItemState.done, ItemState.failed, ItemState.newItem]);
  });

  test('increment quantity selects the number', () {
    final d = doc('# A\n- [ ] 2x milk\n');
    final id = idAt(d, 0, 0);
    final r = incrementQuantity(d, id, NumberContext.en);
    expect(r.doc.itemById(id)!.text, '3x milk');
    expect(r.cursor, CursorTarget.item(id, 0, 1));
  });

  test('normalize quantity on blur', () {
    final d = doc('# A\n- [ ] 1x milk\n');
    final r = normalizeQuantityOnBlur(d, idAt(d, 0, 0), NumberContext.en);
    expect(r.doc.lists[0].items[0].text, 'milk');
  });

  test('reset keeps quantities', () {
    final d = doc('# A\n- [x] 3x a\n- [x] FAILED b\n');
    expect(md(resetList(d, d.lists[0].id).doc), '# A\n- [ ] 3x a\n- [ ] b\n');
  });

  test('delete done keeps FAILED', () {
    final d = doc('# A\n- [x] a\n- [x] FAILED b\n- [ ] c\n');
    expect(
      md(deleteDone(d, d.lists[0].id).doc),
      '# A\n- [x] FAILED b\n- [ ] c\n',
    );
    final d2 = doc('# A\n- [x] a\n');
    expect(md(deleteDone(d2, d2.lists[0].id).doc), '# A\n- [ ] \n');
  });

  test('delete the last list', () {
    final d = doc('# A\n- [ ] a\n');
    expect(md(deleteList(d, d.lists[0].id).doc), '# \n- [ ] \n');
  });

  test('delete items across lists, including the last item', () {
    final d = doc('# A\n- [ ] a\n- [ ] b\n\n# B\n- [ ] c\n');
    final r = deleteItems(d, {idAt(d, 0, 0), idAt(d, 1, 0)});
    expect(md(r.doc), '# A\n- [ ] b\n\n# B\n- [ ] \n');
  });

  test('rename replaces line breaks', () {
    final d = doc('# A\n- [ ] a\n');
    expect(renameList(d, d.lists[0].id, 'x\ny').doc.lists[0].name, 'x y');
  });

  test('restoreStates undoes a reset and keeps later edits', () {
    final d = doc('# A\n- [x] a\n- [x] FAILED b\n- [ ] c\n');
    final previous = {for (final it in d.lists[0].items) it.id: it.state};
    final reset = resetList(d, d.lists[0].id).doc;
    final edited = setItemText(reset, idAt(reset, 0, 2), 'c2').doc;
    final gone = deleteItems(edited, {idAt(edited, 0, 0)}).doc;
    expect(
      md(restoreStates(gone, previous).doc),
      '# A\n- [x] FAILED b\n- [ ] c2\n',
    );
  });

  group('moveItem', () {
    test('moves down within a list', () {
      final d = doc('# A\n- [ ] a\n- [ ] b\n- [ ] c\n');
      final r = moveItem(d, idAt(d, 0, 0), d.lists[0].id, 2);
      expect(md(r.doc), '# A\n- [ ] b\n- [ ] a\n- [ ] c\n');
    });

    test('moves up within a list', () {
      final d = doc('# A\n- [ ] a\n- [ ] b\n- [ ] c\n');
      final r = moveItem(d, idAt(d, 0, 2), d.lists[0].id, 0);
      expect(md(r.doc), '# A\n- [ ] c\n- [ ] a\n- [ ] b\n');
    });

    test('in front of or behind itself changes nothing', () {
      final d = doc('# A\n- [ ] a\n- [ ] b\n');
      expect(moveItem(d, idAt(d, 0, 0), d.lists[0].id, 0).doc, same(d));
      expect(moveItem(d, idAt(d, 0, 0), d.lists[0].id, 1).doc, same(d));
    });

    test('moves to another list, keeping its state', () {
      final d = doc('# A\n- [x] a\n- [ ] b\n# B\n- [ ] c\n');
      final r = moveItem(d, idAt(d, 0, 0), d.lists[1].id, 1);
      expect(md(r.doc), '# A\n- [ ] b\n\n# B\n- [ ] c\n- [x] a\n');
    });

    test('a list left empty gets an empty item', () {
      final d = doc('# A\n- [ ] a\n# B\n- [ ] c\n');
      final r = moveItem(d, idAt(d, 0, 0), d.lists[1].id, 0);
      expect(md(r.doc), '# A\n- [ ] \n\n# B\n- [ ] a\n- [ ] c\n');
      expectInvariants(r.doc);
    });

    test("replaces the target list's only empty item", () {
      final d = doc('# A\n- [ ] a\n- [ ] b\n# B\n- [ ] \n');
      final r = moveItem(d, idAt(d, 0, 0), d.lists[1].id, 1);
      expect(md(r.doc), '# A\n- [ ] b\n\n# B\n- [ ] a\n');
    });
  });

  group('moveList', () {
    test('moves a list down and up', () {
      final d = doc('# A\n- [ ] a\n# B\n- [ ] b\n# C\n- [ ] c\n');
      expect(
        md(moveList(d, d.lists[0].id, 3).doc),
        '# B\n- [ ] b\n\n# C\n- [ ] c\n\n# A\n- [ ] a\n',
      );
      expect(
        md(moveList(d, d.lists[2].id, 1).doc),
        '# A\n- [ ] a\n\n# C\n- [ ] c\n\n# B\n- [ ] b\n',
      );
    });

    test('in front of or behind itself changes nothing', () {
      final d = doc('# A\n- [ ] a\n# B\n- [ ] b\n');
      expect(moveList(d, d.lists[0].id, 0).doc, same(d));
      expect(moveList(d, d.lists[0].id, 1).doc, same(d));
    });
  });
}
