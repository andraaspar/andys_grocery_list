import 'package:andys_grocery_list/model/markdown_codec.dart';
import 'package:andys_grocery_list/state/document_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../model/test_helpers.dart';
import '../storage/fake_storage.dart';

const uri = 'content://todo.md';

Future<(FakeStorage, DocumentController)> open(String content) async {
  final storage = FakeStorage({uri: content});
  final c = await DocumentController.open(storage, uri);
  addTearDown(c.dispose);
  return (storage, c);
}

String idOf(DocumentController c, String text) =>
    c.doc.lists.expand((l) => l.items).firstWhere((i) => i.text == text).id;

void main() {
  testWidgets('opening reads and parses the file', (tester) async {
    final (_, c) = await open('# L\n- [x] Milk\n');
    expect(md(c.doc), '# L\n- [x] Milk\n');
    expect(c.hasUnsavedChanges, isFalse);
  });

  testWidgets('autosaves 500 ms after the last change', (tester) async {
    final (storage, c) = await open('# L\n- [ ] Milk\n');
    c.setItemText(idOf(c, 'Milk'), 'Milk 1');
    await tester.pump(const Duration(milliseconds: 300));
    c.setItemText(idOf(c, 'Milk 1'), 'Milk 12');
    await tester.pump(const Duration(milliseconds: 400));
    expect(storage.writes, isEmpty);
    await tester.pump(const Duration(milliseconds: 100));
    expect(storage.writes, ['# L\n- [ ] Milk 12\n']);
    expect(c.hasUnsavedChanges, isFalse);
  });

  testWidgets('skips the write when the content is unchanged', (tester) async {
    final (storage, c) = await open('# L\n- [ ] Milk\n');
    c.setItemText(idOf(c, 'Milk'), 'Milks');
    c.setItemText(idOf(c, 'Milks'), 'Milk');
    await c.save();
    expect(storage.writes, isEmpty);
    expect(c.hasUnsavedChanges, isFalse);
  });

  testWidgets('save writes immediately, e.g. on pause', (tester) async {
    final (storage, c) = await open('# L\n- [ ] Milk\n');
    c.cycleState(idOf(c, 'Milk'));
    await c.save();
    expect(storage.files[uri], '# L\n- [x] Milk\n');
  });

  testWidgets('an external change is reloaded when there are no local edits, '
      'keeping the ids of matching items', (tester) async {
    final (storage, c) = await open('# L\n- [ ] Milk\n- [ ] Bread\n');
    final milk = idOf(c, 'Milk');
    final listId = c.doc.lists.single.id;
    storage.externalWrite(uri, '# L\n- [ ] Eggs\n- [x] Milk\n# M\n- [ ] A\n');
    var reloads = 0;
    c.addListener(() {
      if (c.reloading) reloads++;
    });
    await c.checkExternalChange();
    expect(reloads, 1);
    expect(md(c.doc), '# L\n- [ ] Eggs\n- [x] Milk\n\n# M\n- [ ] A\n');
    expect(idOf(c, 'Milk'), milk);
    expect(c.doc.lists.first.id, listId);
    expect(storage.writes, isEmpty);
  });

  testWidgets('an unchanged file is not reloaded', (tester) async {
    final (storage, c) = await open('# L\n- [ ] Milk\n');
    var notified = 0;
    c.addListener(() => notified++);
    await c.checkExternalChange();
    storage.externalWrite(uri, '# L\n- [ ] Milk\n'); // Same content, new time.
    await c.checkExternalChange();
    expect(notified, 0);
  });

  testWidgets('works when the provider reports no modification time', (
    tester,
  ) async {
    final (storage, c) = await open('# L\n- [ ] Milk\n');
    storage.reportsModified = false;
    await c.checkExternalChange();
    expect(md(c.doc), '# L\n- [ ] Milk\n');
    storage.externalWrite(uri, '# L\n- [x] Milk\n');
    await c.checkExternalChange();
    expect(md(c.doc), '# L\n- [x] Milk\n');
  });

  testWidgets('with unsaved edits, the check leaves them alone; the save then '
      'finds the external change and reloads instead of writing', (
    tester,
  ) async {
    final (storage, c) = await open('# L\n- [ ] Milk\n');
    var reloadedBeforeSave = 0;
    c.onReloadedBeforeSave = () => reloadedBeforeSave++;
    c.setItemText(idOf(c, 'Milk'), 'Milk 2');
    storage.externalWrite(uri, '# L\n- [ ] Eggs\n');
    await c.checkExternalChange();
    expect(md(c.doc), '# L\n- [ ] Milk 2\n');
    await c.save();
    expect(storage.writes, isEmpty);
    expect(md(c.doc), '# L\n- [ ] Eggs\n');
    expect(reloadedBeforeSave, 1);
    expect(c.hasUnsavedChanges, isFalse);
  });

  testWidgets('polls every 5 s', (tester) async {
    final (storage, c) = await open('# L\n- [ ] Milk\n');
    c.startPolling();
    storage.externalWrite(uri, '# L\n- [x] Milk\n');
    await tester.pump(const Duration(seconds: 4));
    expect(md(c.doc), '# L\n- [ ] Milk\n');
    await tester.pump(const Duration(seconds: 1));
    expect(md(c.doc), '# L\n- [x] Milk\n');
    c.stopPolling();
  });

  testWidgets('an empty new file gets the default list on first save', (
    tester,
  ) async {
    final (storage, c) = await open('');
    expect(md(c.doc), '# TODO\n- [ ] \n');
    c.setItemText(c.doc.lists.single.items.single.id, 'Milk');
    await c.save();
    expect(storage.files[uri], '# TODO\n- [ ] Milk\n');
  });

  group('reuseIds', () {
    test('matches lists by name and items by text, each id once', () {
      final old = parseDocument('# A\n- [ ] x\n- [ ] x\n# B\n- [ ] y\n');
      final fresh = parseDocument('# B\n- [ ] y\n- [ ] x\n# A\n- [x] x\n');
      final r = reuseIds(old, fresh);
      expect(r.lists[0].id, old.lists[1].id);
      expect(r.lists[1].id, old.lists[0].id);
      expect(r.lists[0].items[0].id, idAt(old, 1, 0));
      // `x` in B: not in old B, so it takes an `x` left over from A.
      expect(r.lists[1].items[0].id, idAt(old, 0, 0));
      expect(r.lists[0].items[1].id, idAt(old, 0, 1));
      expect(md(r), '# B\n- [ ] y\n- [ ] x\n\n# A\n- [x] x\n');
    });

    test('new lists and items get new ids', () {
      final old = parseDocument('# A\n- [ ] x\n');
      final r = reuseIds(old, parseDocument('# C\n- [ ] z\n'));
      expect(r.lists[0].id, isNot(old.lists[0].id));
      expect(r.lists[0].items[0].id, isNot(idAt(old, 0, 0)));
    });
  });
}
