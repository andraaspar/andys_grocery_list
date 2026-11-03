import 'package:andys_grocery_list/model/markdown_codec.dart';
import 'package:andys_grocery_list/model/number_parser.dart';
import 'package:andys_grocery_list/model/operations.dart' show CursorTarget;
import 'package:andys_grocery_list/state/document_controller.dart';
import 'package:andys_grocery_list/ui/home_page.dart';
import 'package:andys_grocery_list/ui/sentinel_controller.dart';
import 'package:flutter/material.dart';
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
}
