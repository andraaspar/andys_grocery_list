import 'package:andys_grocery_list/ui/sentinel_controller.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Simulates an IME update: [text] uses `|` for the cursor, and the sentinel
/// is written as `^`.
TextEditingValue ime(String text) {
  final cursor = text.indexOf('|');
  final t = text.replaceAll('|', '').replaceAll('^', sentinel);
  return TextEditingValue(
    text: t,
    selection: TextSelection.collapsed(offset: cursor < 0 ? t.length : cursor),
  );
}

void main() {
  late SentinelController c;
  final log = <String>[];

  setUp(() {
    log.clear();
    c = SentinelController(text: 'Milk')
      ..onTextChanged = ((t) => log.add('text $t'))
      ..onEnter = ((t, o) => log.add('enter $t $o'))
      ..onBackspaceAtStart = (() => log.add('backspace'))
      ..onPaste = ((s, e, t) => log.add('paste $s $e $t'));
  });

  test('starts with the sentinel and hides it from the model', () {
    expect(c.text, '${sentinel}Milk');
    expect(c.modelText, 'Milk');
    expect(c.modelSelection, const TextSelection.collapsed(offset: 4));
  });

  test('plain typing reports the model text', () {
    c.value = ime('^Milks|');
    expect(log, ['text Milks']);
    expect(c.modelText, 'Milks');
  });

  test('deleting the sentinel is Backspace at the start', () {
    c.setModelSelection(0);
    c.value = ime('|Milk');
    expect(log, ['backspace']);
    expect(c.text, '${sentinel}Milk');
  });

  test('Backspace in an empty field', () {
    c.setModel('');
    c.value = ime('|');
    expect(log, ['backspace']);
    expect(c.text, sentinel);
  });

  test('an inserted line break is Enter at its offset', () {
    c.setModelSelection(2);
    c.value = ime('^Mi\n|lk');
    expect(log, ['enter Milk 2']);
    expect(c.modelText, 'Milk', reason: 'the edit is not applied');
  });

  test('Enter at the end and at the start', () {
    c.value = ime('^Milk\n|');
    c.setModelSelection(0);
    c.value = ime('^\n|Milk');
    expect(log, ['enter Milk 4', 'enter Milk 0']);
  });

  test('Enter replacing a selection drops the selected text', () {
    c.setModelSelection(1, 3);
    c.value = ime('^M\n|k');
    expect(log, ['enter Mk 1']);
  });

  test('a multi-line insert is a paste over the replaced range', () {
    c.setModelSelection(1, 3);
    c.value = ime('^Ma\nb|k');
    expect(log, ['paste 1 3 a\nb']);
    expect(c.modelText, 'Milk');
  });

  test('a single line with an item prefix is a paste', () {
    c.value = ime('^Milk- [x] Eggs|');
    expect(log, ['paste 4 4 - [x] Eggs']);
  });

  test('a plain single line is inserted as text', () {
    c.value = ime('^Milk 3x eggs|');
    expect(log, ['text Milk 3x eggs']);
  });

  test('a repeated character at the insertion edge is attributed right', () {
    c.setModel('aa', selection: const TextSelection.collapsed(offset: 1));
    c.value = ime('^a\n|a');
    expect(log, ['enter aa 1']);
  });

  test('the selection cannot move before the sentinel', () {
    c.value = const TextEditingValue(
      text: '${sentinel}Milk',
      selection: TextSelection(baseOffset: 0, extentOffset: 5),
    );
    expect(c.selection, const TextSelection(baseOffset: 1, extentOffset: 5));
    expect(log, isEmpty);
  });

  test('stray sentinels are removed from typed text', () {
    c.value = ime('^Mi${sentinel}lk!|');
    expect(log, ['text Milk!']);
    expect(c.text, '${sentinel}Milk!');
  });

  test('setModel does not run callbacks', () {
    c.setModel('Bread');
    expect(log, isEmpty);
    expect(c.modelText, 'Bread');
  });
}
