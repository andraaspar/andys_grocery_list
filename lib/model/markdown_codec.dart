/// Parsing and serialization of the Markdown file format (plan §1).
library;

import 'amounts.dart';
import 'number_parser.dart';
import 'operations.dart' show normalize;
import 'todo_document.dart';

/// The result of parsing pasted text: items before any header, then lists.
class Fragment {
  const Fragment(this.looseItems, this.lists);

  final List<TodoItem> looseItems;
  final List<TodoList> lists;

  bool get isEmpty => looseItems.isEmpty && lists.isEmpty;
}

const _failedPrefixes = ['- [x] FAILED ', '- [X] FAILED '];
const _donePrefixes = ['- [x] ', '- [X] '];
const _newPrefix = '- [ ] ';

/// Parses one line as an item, or returns null if it is a header or blank.
TodoItem? parseItemLine(String line) {
  for (final p in _failedPrefixes) {
    if (line.startsWith(p)) {
      return TodoItem(state: ItemState.failed, text: line.substring(p.length));
    }
  }
  if (line == '- [x] FAILED' || line == '- [X] FAILED') {
    return TodoItem(state: ItemState.failed);
  }
  for (final p in _donePrefixes) {
    if (line.startsWith(p)) {
      return TodoItem(state: ItemState.done, text: line.substring(p.length));
    }
  }
  if (line == '- [x]' || line == '- [X]') {
    return TodoItem(state: ItemState.done);
  }
  if (line.startsWith(_newPrefix)) {
    return TodoItem(text: line.substring(_newPrefix.length));
  }
  if (line == '- [ ]') return TodoItem();
  if (line.startsWith('- ') || line.startsWith('* ')) {
    return TodoItem(text: line.substring(2));
  }
  if (line == '-' || line == '*') return TodoItem();
  return TodoItem(text: line);
}

/// The list name if [line] is a header, otherwise null.
String? _headerName(String line) {
  if (line.startsWith('# ')) return line.substring(2);
  if (line == '#') return '';
  return null;
}

/// Whether [line] starts with any recognized prefix (header or item).
bool hasRecognizedPrefix(String line) =>
    _headerName(line) != null ||
    line.startsWith('- ') ||
    line.startsWith('* ') ||
    line == '-' ||
    line == '*';

List<String> splitLines(String content) =>
    content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

Fragment parseFragment(String content) {
  final loose = <TodoItem>[];
  final lists = <TodoList>[];
  String? name;
  var items = <TodoItem>[];
  void flush() {
    if (name != null) lists.add(TodoList(name: name, items: items));
  }

  for (final line in splitLines(content)) {
    if (line.trim().isEmpty) continue;
    final header = _headerName(line);
    if (header != null) {
      flush();
      name = header;
      items = [];
      continue;
    }
    final item = parseItemLine(line)!;
    (name == null ? loose : items).add(item);
  }
  flush();
  return Fragment(loose, lists);
}

/// Parses a whole file. Items before the first header go into a list with an
/// empty name. An empty file gives one unnamed list with one empty item.
TodoDocument parseDocument(String content) {
  final fragment = parseFragment(content);
  final lists = [
    if (fragment.looseItems.isNotEmpty)
      TodoList(name: '', items: fragment.looseItems),
    ...fragment.lists,
  ];
  if (lists.isEmpty) lists.add(TodoList(name: ''));
  return normalize(TodoDocument(lists));
}

String statePrefix(ItemState state) => switch (state) {
  ItemState.newItem => _newPrefix,
  ItemState.done => _donePrefixes.first,
  ItemState.failed => _failedPrefixes.first,
};

/// The canonical line for [item]. A quantity of exactly 1 is removed.
String serializeItem(TodoItem item, NumberContext ctx) =>
    statePrefix(item.state) + stripQuantityOne(item.text, ctx);

String serializeDocument(TodoDocument doc, NumberContext ctx) {
  final buf = StringBuffer();
  for (var i = 0; i < doc.lists.length; i++) {
    if (i > 0) buf.write('\n');
    final list = doc.lists[i];
    buf.write('# ${list.name}\n');
    for (final item in list.items) {
      buf.write('${serializeItem(item, ctx)}\n');
    }
  }
  return buf.toString();
}
