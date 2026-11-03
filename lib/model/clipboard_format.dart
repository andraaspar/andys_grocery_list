/// Copy formatting, shared by selection copy (§6) and Copy list (§4).
library;

import 'amounts.dart';
import 'markdown_codec.dart';
import 'number_parser.dart';
import 'todo_document.dart';

/// One line per item, with a trailing newline. If every item is NEW, each
/// line is `- text`; otherwise the backing format is used.
String formatItems(List<TodoItem> items, NumberContext ctx) {
  final allNew = items.every((i) => i.state == ItemState.newItem);
  final buf = StringBuffer();
  for (final item in items) {
    final text = stripQuantityOne(item.text, ctx);
    buf.write(allNew ? '- $text\n' : '${statePrefix(item.state)}$text\n');
  }
  return buf.toString();
}

/// `# name`, then the list's non-empty items.
String formatList(TodoList list, NumberContext ctx) =>
    '# ${list.name}\n'
    '${formatItems(list.items.where((i) => i.text.isNotEmpty).toList(), ctx)}';
