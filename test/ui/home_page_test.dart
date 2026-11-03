import 'package:andys_grocery_list/model/markdown_codec.dart';
import 'package:andys_grocery_list/model/number_parser.dart';
import 'package:andys_grocery_list/model/operations.dart' show CursorTarget;
import 'package:andys_grocery_list/state/document_controller.dart';
import 'package:andys_grocery_list/ui/home_page.dart';
import 'package:andys_grocery_list/ui/sentinel_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

Future<DocumentController> pump(WidgetTester tester, String md) async {
  final doc = DocumentController(parseDocument(md));
  addTearDown(doc.dispose);
  await tester.pumpWidget(MaterialApp(home: HomePage(document: doc)));
  return doc;
}

String serialized(DocumentController d) =>
    serializeDocument(d.doc, NumberContext.en);

Finder itemField(String text) => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      w.controller is SentinelController &&
      (w.controller! as SentinelController).modelText == text,
);

Finder nameField(String name) => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      w.controller is! SentinelController &&
      w.controller!.text == name,
);

TextField fieldOf(WidgetTester tester, Finder f) => tester.widget<TextField>(f);

SentinelController controllerOf(WidgetTester tester, Finder f) =>
    fieldOf(tester, f).controller! as SentinelController;

/// Focuses the item field with [text] and puts the cursor at model [offset].
Future<SentinelController> focusItem(
  WidgetTester tester,
  String text,
  int offset,
) async {
  final f = itemField(text);
  await tester.showKeyboard(f);
  final c = controllerOf(tester, f);
  c.setModelSelection(offset);
  await tester.pump();
  return c;
}

/// Sends an IME update for the focused field: [model] is the model text, with
/// `|` marking the cursor. The sentinel is added in front, unless
/// [dropSentinel].
Future<void> imeUpdate(
  WidgetTester tester,
  String model, {
  bool dropSentinel = false,
}) async {
  final cursor = model.indexOf('|');
  final text = model.replaceAll('|', '');
  final prefix = dropSentinel ? '' : sentinel;
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: prefix + text,
      selection: TextSelection.collapsed(offset: prefix.length + cursor),
    ),
  );
  await tester.pumpAndSettle();
}

bool hasFocus(WidgetTester tester, Finder f) =>
    fieldOf(tester, f).focusNode!.hasFocus;

void main() {
  testWidgets('typing updates the document', (tester) async {
    final doc = await pump(tester, '# L\n- [ ] Milk\n');
    await focusItem(tester, 'Milk', 4);
    await imeUpdate(tester, 'Milks|');
    expect(serialized(doc), '# L\n- [ ] Milks\n');
  });

  testWidgets('Enter in the middle splits and focuses the new item', (
    tester,
  ) async {
    final doc = await pump(tester, '# L\n- [x] Milkshake\n');
    await focusItem(tester, 'Milkshake', 4);
    await imeUpdate(tester, 'Milk\n|shake');

    expect(serialized(doc), '# L\n- [x] Milk\n- [ ] shake\n');
    expect(hasFocus(tester, itemField('shake')), isTrue);
    expect(
      controllerOf(tester, itemField('shake')).modelSelection,
      const TextSelection.collapsed(offset: 0),
    );
  });

  testWidgets('Enter at the end inserts an empty item and focuses it', (
    tester,
  ) async {
    final doc = await pump(tester, '# L\n- [ ] Milk\n');
    await focusItem(tester, 'Milk', 4);
    await imeUpdate(tester, 'Milk\n|');

    expect(serialized(doc), '# L\n- [ ] Milk\n- [ ] \n');
    expect(hasFocus(tester, itemField('')), isTrue);
  });

  testWidgets('Backspace at the start merges with the previous item', (
    tester,
  ) async {
    final doc = await pump(tester, '# L\n- [x] Milk\n- [ ] shake\n');
    await focusItem(tester, 'shake', 0);
    await imeUpdate(tester, '|shake', dropSentinel: true);

    expect(serialized(doc), '# L\n- [x] Milkshake\n');
    final merged = itemField('Milkshake');
    expect(hasFocus(tester, merged), isTrue);
    expect(
      controllerOf(tester, merged).modelSelection,
      const TextSelection.collapsed(offset: 4),
    );
  });

  testWidgets('Backspace in an empty item deletes it', (tester) async {
    final doc = await pump(tester, '# L\n- [ ] Milk\n- [ ] \n');
    await focusItem(tester, '', 0);
    await imeUpdate(tester, '|', dropSentinel: true);

    expect(serialized(doc), '# L\n- [ ] Milk\n');
    expect(hasFocus(tester, itemField('Milk')), isTrue);
  });

  testWidgets('Backspace on the first item merges the list into the previous', (
    tester,
  ) async {
    final doc = await pump(tester, '# A\n- [ ] a\n\n# B\n- [ ] b\n');
    await focusItem(tester, 'b', 0);
    await imeUpdate(tester, '|b', dropSentinel: true);

    expect(serialized(doc), '# A\n- [ ] a\n- [ ] b\n');
    expect(hasFocus(tester, itemField('b')), isTrue);
  });

  testWidgets('Enter on an empty item starts a new list and focuses its name', (
    tester,
  ) async {
    final doc = await pump(tester, '# L\n- [ ] a\n- [ ] \n- [ ] b\n');
    await focusItem(tester, '', 0);
    await imeUpdate(tester, '\n|');

    expect(serialized(doc), '# L\n- [ ] a\n\n# New list\n- [ ] b\n');
    final name = nameField('New list');
    expect(hasFocus(tester, name), isTrue);
    expect(
      fieldOf(tester, name).controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 8),
    );
  });

  testWidgets('Enter in a list name focuses the first item', (tester) async {
    await pump(tester, '# L\n- [ ] Milk\n- [ ] Eggs\n');
    await tester.showKeyboard(nameField('L'));
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();

    expect(hasFocus(tester, itemField('Milk')), isTrue);
    expect(
      controllerOf(tester, itemField('Milk')).modelSelection,
      const TextSelection.collapsed(offset: 0),
    );
  });

  testWidgets('editing the list name renames the list', (tester) async {
    final doc = await pump(tester, '# L\n- [ ] Milk\n');
    await tester.enterText(nameField('L'), 'Shop');
    expect(serialized(doc), '# Shop\n- [ ] Milk\n');
  });

  testWidgets('a multi-line paste creates items', (tester) async {
    final doc = await pump(tester, '# L\n- [ ] ab\n');
    await focusItem(tester, 'ab', 1);
    await imeUpdate(tester, 'a- [x] x\ny|b');

    expect(serialized(doc), '# L\n- [ ] a\n- [x] x\n- [ ] y\n- [ ] b\n');
    expect(hasFocus(tester, itemField('y')), isTrue);
  });

  testWidgets('a paste with lists moves the rest into the last list', (
    tester,
  ) async {
    final doc = await pump(tester, '# L\n- [ ] ab\n- [ ] c\n');
    await focusItem(tester, 'ab', 1);
    await imeUpdate(tester, 'a# M\n- x|b');

    expect(serialized(doc), '# L\n- [ ] a\n\n# M\n- [ ] x\n- [ ] b\n- [ ] c\n');
  });

  testWidgets('tapping the state icon cycles the state', (tester) async {
    final doc = await pump(tester, '# L\n- [ ] Milk\n');
    await tester.tap(find.byIcon(Icons.check_box_outline_blank));
    await tester.pump();
    expect(serialized(doc), '# L\n- [x] Milk\n');
    await tester.tap(find.byIcon(Icons.check_box));
    await tester.pump();
    expect(serialized(doc), '# L\n- [x] FAILED Milk\n');
  });

  testWidgets('a quantity of 1 is removed when the item loses focus', (
    tester,
  ) async {
    final doc = await pump(tester, '# L\n- [ ] Milk\n- [ ] Eggs\n');
    await focusItem(tester, 'Milk', 0);
    await imeUpdate(tester, '1x |Milk');
    expect(doc.doc.lists[0].items[0].text, '1x Milk');
    await tester.showKeyboard(itemField('Eggs'));
    await tester.pumpAndSettle();
    expect(doc.doc.lists[0].items[0].text, 'Milk');
  });

  testWidgets('the last item can be scrolled to the top of the viewport', (
    tester,
  ) async {
    final lines = [for (var i = 0; i < 30; i++) '- [ ] item $i'].join('\n');
    await pump(tester, '# L\n$lines\n');
    final scrollable = find.byType(SuperListView);
    await tester.drag(scrollable, const Offset(0, -100000));
    await tester.pumpAndSettle();

    final listTop = tester.getTopLeft(scrollable).dy;
    final lastTop = tester.getTopLeft(itemField('item 29')).dy;
    expect(lastTop - listTop, lessThan(itemRowHeight));
  });

  testWidgets('tapping the blank space focuses the last item at its end', (
    tester,
  ) async {
    await pump(tester, '# A\n- [ ] a\n\n# B\n- [ ] b\n- [ ] last\n');
    await tester.tapAt(
      tester.getBottomLeft(find.byType(SuperListView)) + const Offset(20, -20),
    );
    await tester.pumpAndSettle();

    final last = itemField('last');
    expect(hasFocus(tester, last), isTrue);
    expect(
      controllerOf(tester, last).modelSelection,
      const TextSelection.collapsed(offset: 4),
    );
  });

  testWidgets('focusing an item that is scrolled far away brings it in view', (
    tester,
  ) async {
    final lines = [for (var i = 0; i < 80; i++) '- [ ] item $i'].join('\n');
    final doc = await pump(tester, '# L\n$lines\n');
    final last = doc.doc.lists.last.items.last;
    doc.focus(CursorTarget.item(last.id, last.text.length));
    await tester.pumpAndSettle();
    expect(hasFocus(tester, itemField('item 79')), isTrue);
  });

  group('the + button', () {
    Finder plusOf(String text) => find.descendant(
      of: find.ancestor(of: itemField(text), matching: find.byType(Row)).first,
      matching: find.byIcon(Icons.add),
    );

    testWidgets('increments, focuses the field and selects the number', (
      tester,
    ) async {
      final doc = await pump(tester, '# L\n- [ ] Milk\n- [ ] Eggs\n');
      await tester.tap(plusOf('Milk'));
      await tester.pumpAndSettle();

      expect(doc.doc.lists[0].items[0].text, '2x Milk');
      final f = itemField('2x Milk');
      expect(hasFocus(tester, f), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
      expect(
        controllerOf(tester, f).modelSelection,
        const TextSelection(baseOffset: 0, extentOffset: 1),
      );
    });

    testWidgets('repeated presses keep the number selected', (tester) async {
      final doc = await pump(tester, '# L\n- [ ] 8x Milk\n');
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();
      }
      expect(doc.doc.lists[0].items[0].text, '11x Milk');
      final f = itemField('11x Milk');
      expect(hasFocus(tester, f), isTrue);
      expect(
        controllerOf(tester, f).modelSelection,
        const TextSelection(baseOffset: 0, extentOffset: 2),
      );
    });

    testWidgets('typing replaces the selected number', (tester) async {
      final doc = await pump(tester, '# L\n- [ ] 1,5x Cheese\n');
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(doc.doc.lists[0].items[0].text, '2,5x Cheese');
      expect(
        controllerOf(tester, itemField('2,5x Cheese')).modelSelection,
        const TextSelection(baseOffset: 0, extentOffset: 3),
      );
      await imeUpdate(tester, '6|x Cheese');
      expect(doc.doc.lists[0].items[0].text, '6x Cheese');
    });

    testWidgets('moves focus from another item', (tester) async {
      final doc = await pump(tester, '# L\n- [ ] Milk\n- [ ] \n');
      await focusItem(tester, 'Milk', 2);
      await tester.tap(plusOf(''));
      await tester.pumpAndSettle();
      expect(doc.doc.lists[0].items[1].text, '2x ');
      expect(hasFocus(tester, itemField('2x ')), isTrue);
      expect(hasFocus(tester, itemField('Milk')), isFalse);
    });
  });

  group('the total line', () {
    Finder total(String text) => find.text('Total: $text');

    testWidgets('is hidden when no item has a price', (tester) async {
      await pump(tester, '# L\n- [x] Milk\n');
      expect(find.textContaining('Total:'), findsNothing);
    });

    testWidgets('sums DONE items and updates when one is checked off', (
      tester,
    ) async {
      await pump(
        tester,
        '# L\n- [ ] 3x Milk 1.29\n- [x] 1.5x Cheese 8.00\n'
        '- [x] FAILED Basil 0.99\n- [x] Coffee machine 1.299,00\n',
      );
      expect(total('1,311.00'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.check_box_outline_blank));
      await tester.pump();
      expect(total('1,314.87'), findsOneWidget);
    });

    testWidgets('is formatted with the document locale', (tester) async {
      final doc = DocumentController(
        parseDocument('# L\n- [x] Machine 1.299,5\n'),
        locale: 'de_DE',
      );
      addTearDown(doc.dispose);
      await tester.pumpWidget(MaterialApp(home: HomePage(document: doc)));
      expect(total('1.299,5'), findsOneWidget);
    });

    testWidgets('appearing does not move the focused item', (tester) async {
      await pump(tester, '# L\n- [x] Milk\n- [ ] Eggs\n');
      await focusItem(tester, 'Milk', 4);
      final before = tester.getTopLeft(itemField('Milk'));
      await imeUpdate(tester, 'Milk 2|');
      expect(total('2'), findsOneWidget);
      expect(tester.getTopLeft(itemField('Milk 2')), before);
      expect(
        tester.getTopLeft(total('2')).dy,
        greaterThan(tester.getTopLeft(itemField('Eggs')).dy),
      );
    });
  });

  group('the ⋯ menu', () {
    Future<void> choose(
      WidgetTester tester,
      String entry, {
      int list = 0,
    }) async {
      await tester.tap(find.byIcon(Icons.more_horiz).at(list));
      await tester.pumpAndSettle();
      await tester.tap(find.text(entry));
      await tester.pumpAndSettle();
    }

    testWidgets('Reset sets every item to NEW and can be undone', (
      tester,
    ) async {
      final doc = await pump(tester, '# L\n- [x] 3x a\n- [x] FAILED b\n');
      await choose(tester, 'Reset');
      expect(serialized(doc), '# L\n- [ ] 3x a\n- [ ] b\n');
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(serialized(doc), '# L\n- [x] 3x a\n- [x] FAILED b\n');
    });

    testWidgets('Copy list copies the list to the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await pump(tester, '# A\n- [ ] 2x a\n- [ ] \n\n# B\n- [x] b\n');
      await choose(tester, 'Copy list');
      expect(copied, '# A\n- 2x a\n');
      expect(find.text('List copied'), findsOneWidget);
    });

    testWidgets('Delete done removes DONE items only', (tester) async {
      final doc = await pump(tester, '# L\n- [x] a\n- [x] FAILED b\n- [ ] c\n');
      await choose(tester, 'Delete done');
      expect(serialized(doc), '# L\n- [x] FAILED b\n- [ ] c\n');
    });

    testWidgets('Delete list asks first', (tester) async {
      final doc = await pump(tester, '# A\n- [ ] a\n\n# B\n- [ ] b\n- [ ] c\n');
      await choose(tester, 'Delete list', list: 1);
      expect(find.text('Delete list "B" and its 2 items?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(serialized(doc), '# A\n- [ ] a\n\n# B\n- [ ] b\n- [ ] c\n');

      await choose(tester, 'Delete list', list: 1);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(serialized(doc), '# A\n- [ ] a\n');
    });

    testWidgets('deleting the only list leaves an empty TODO list', (
      tester,
    ) async {
      final doc = await pump(tester, '# A\n- [ ] a\n');
      await choose(tester, 'Delete list');
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(serialized(doc), '# TODO\n- [ ] \n');
    });
  });

  group('selection mode', selectionTests);
}

/// Captures text written to the clipboard. Read the latest value with the
/// returned function.
String? Function() captureClipboard(WidgetTester tester) {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return () => copied;
}

void selectionTests() {
  /// Long-presses the state icon of the item with [text].
  Future<void> longPressIcon(WidgetTester tester, String text) async {
    final row = find.ancestor(of: itemField(text), matching: find.byType(Row));
    await tester.longPress(
      find.descendant(of: row.first, matching: find.byType(IconButton)).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapRow(WidgetTester tester, String text) async {
    // The text field ignores pointers in selection mode; the row gets the tap.
    await tester.tap(
      find.ancestor(of: itemField(text), matching: find.byType(InkWell)).first,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('long-pressing a state icon enters selection mode', (
    tester,
  ) async {
    final doc = await pump(tester, '# L\n- [ ] a\n- [ ] b\n');
    await focusItem(tester, 'b', 0);
    expect(find.byIcon(Icons.add), findsNWidgets(2));

    await longPressIcon(tester, 'a');
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(hasFocus(tester, itemField('b')), isFalse);
    expect(serialized(doc), '# L\n- [ ] a\n- [ ] b\n');
  });

  testWidgets('tapping icons and rows toggles selection, not state', (
    tester,
  ) async {
    final doc = await pump(tester, '# A\n- [ ] a\n\n# B\n- [x] b\n- [ ] c\n');
    await longPressIcon(tester, 'a');
    await tapRow(tester, 'b');
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('New').last);
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);
    expect(serialized(doc), '# A\n- [ ] a\n\n# B\n- [x] b\n- [ ] c\n');
    expect(tester.testTextInput.isVisible, isFalse);

    await tapRow(tester, 'b');
    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('deselecting the last item leaves selection mode', (
    tester,
  ) async {
    await pump(tester, '# L\n- [ ] a\n');
    await longPressIcon(tester, 'a');
    await tapRow(tester, 'a');
    expect(find.text('1 selected'), findsNothing);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('Close and the back button leave selection mode', (tester) async {
    await pump(tester, '# L\n- [ ] a\n');
    await longPressIcon(tester, 'a');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);

    await longPressIcon(tester, 'a');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
    expect(find.byType(HomePage), findsOneWidget);
  });

  testWidgets('Copy of NEW items uses the dash prefix, in document order', (
    tester,
  ) async {
    final copied = captureClipboard(tester);
    await pump(tester, '# A\n- [ ] 1x a\n\n# B\n- [ ] 3x b\n- [ ] c\n');
    await longPressIcon(tester, 'c');
    await tapRow(tester, '1x a');
    await tester.tap(find.byTooltip('Copy'));
    await tester.pumpAndSettle();
    expect(copied(), '- a\n- c\n');
    expect(find.text('Copied 2 items'), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget);
  });

  testWidgets('Copy of mixed items uses the backing format', (tester) async {
    final copied = captureClipboard(tester);
    await pump(tester, '# L\n- [ ] a\n- [x] b\n- [x] FAILED c\n');
    await longPressIcon(tester, 'a');
    await tapRow(tester, 'b');
    await tapRow(tester, 'c');
    await tester.tap(find.byTooltip('Copy'));
    await tester.pumpAndSettle();
    expect(copied(), '- [ ] a\n- [x] b\n- [x] FAILED c\n');
    expect(find.text('Copied 3 items'), findsOneWidget);
  });

  testWidgets('Delete of one item does not ask', (tester) async {
    final doc = await pump(tester, '# L\n- [ ] a\n- [ ] b\n');
    await longPressIcon(tester, 'a');
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(serialized(doc), '# L\n- [ ] b\n');
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets('Delete of several items asks first', (tester) async {
    final doc = await pump(tester, '# A\n- [ ] a\n\n# B\n- [ ] b\n- [ ] c\n');
    await longPressIcon(tester, 'a');
    await tapRow(tester, 'b');
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 selected items?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();
    expect(serialized(doc), '# A\n- [ ] \n\n# B\n- [ ] c\n');
    expect(find.text('2 selected'), findsNothing);
  });
}
