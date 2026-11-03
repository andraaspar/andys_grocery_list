/// Edit operations as pure functions on the model (plan §2–§6).
///
/// Every operation returns the new document plus where the cursor should go.
/// Invariants are applied by [normalize] at the end of every operation.
library;

import 'amounts.dart' as amounts;
import 'markdown_codec.dart';
import 'number_parser.dart';
import 'todo_document.dart';

/// New lists start unnamed; the name field shows a placeholder.
const defaultNewListName = '';
const emptyDocumentListName = '';

/// Where focus goes after an operation. Offsets are model offsets (no
/// sentinel). If [isListName], [id] is a list id, otherwise an item id.
class CursorTarget {
  const CursorTarget.item(this.id, this.start, [int? end])
    : end = end ?? start,
      isListName = false;

  const CursorTarget.listName(this.id, this.start, [int? end])
    : end = end ?? start,
      isListName = true;

  final String id;
  final int start;
  final int end;
  final bool isListName;

  @override
  bool operator ==(Object other) =>
      other is CursorTarget &&
      other.id == id &&
      other.start == start &&
      other.end == end &&
      other.isListName == isListName;

  @override
  int get hashCode => Object.hash(id, start, end, isListName);

  @override
  String toString() =>
      'CursorTarget(${isListName ? 'list' : 'item'} $id, $start..$end)';
}

class OpResult {
  const OpResult(this.doc, [this.cursor]);

  final TodoDocument doc;
  final CursorTarget? cursor;
}

String _singleLine(String s) => s.replaceAll(RegExp(r'\r\n|\r|\n'), ' ');

/// Applies the invariants: at least one list, every list has at least one
/// item, and no line breaks in names or item text.
TodoDocument normalize(TodoDocument doc) {
  final lists = <TodoList>[];
  for (final list in doc.lists) {
    final items = [
      for (final item in list.items)
        item.text.contains(RegExp(r'[\r\n]'))
            ? item.copyWith(text: _singleLine(item.text))
            : item,
    ];
    if (items.isEmpty) items.add(TodoItem());
    final name = _singleLine(list.name);
    lists.add(
      name == list.name && _sameItems(items, list.items)
          ? list
          : list.copyWith(name: name, items: items),
    );
  }
  if (lists.isEmpty) {
    lists.add(TodoList(name: emptyDocumentListName, items: [TodoItem()]));
  }
  return TodoDocument(lists);
}

bool _sameItems(List<TodoItem> a, List<TodoItem> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (!identical(a[i], b[i])) return false;
  }
  return true;
}

TodoDocument _replaceList(TodoDocument doc, int index, TodoList list) =>
    TodoDocument([...doc.lists]..[index] = list);

TodoDocument _replaceItem(TodoDocument doc, String itemId, TodoItem item) {
  final loc = doc.locate(itemId)!;
  final list = doc.lists[loc.listIndex];
  return _replaceList(
    doc,
    loc.listIndex,
    list.copyWith(items: [...list.items]..[loc.itemIndex] = item),
  );
}

// ---------------------------------------------------------------------------
// Typing

/// Sets the text of an item (plain typing, no line breaks expected).
OpResult setItemText(TodoDocument doc, String itemId, String text) {
  final item = doc.itemById(itemId)!;
  return OpResult(
    normalize(_replaceItem(doc, itemId, item.copyWith(text: text))),
  );
}

/// Removes a quantity prefix of exactly 1, when an item loses focus.
OpResult normalizeQuantityOnBlur(
  TodoDocument doc,
  String itemId,
  NumberContext ctx,
) {
  final item = doc.itemById(itemId);
  if (item == null) return OpResult(doc);
  final text = amounts.stripQuantityOne(item.text, ctx);
  if (text == item.text) return OpResult(doc);
  return setItemText(doc, itemId, text);
}

// ---------------------------------------------------------------------------
// Enter

/// Enter pressed in item [itemId] with the cursor at [offset].
OpResult enter(TodoDocument doc, String itemId, int offset) {
  final loc = doc.locate(itemId)!;
  final list = doc.lists[loc.listIndex];
  final item = list.items[loc.itemIndex];
  final text = item.text;

  if (text.isEmpty) {
    return _newListFromEmptyItem(doc, loc.listIndex, loc.itemIndex);
  }

  final items = [...list.items];
  if (offset <= 0) {
    // At the start: insert an empty NEW item above; keep focus here.
    items.insert(loc.itemIndex, TodoItem());
    return OpResult(
      normalize(_replaceList(doc, loc.listIndex, list.copyWith(items: items))),
      CursorTarget.item(item.id, 0),
    );
  }

  // In the middle or at the end: split; the second part becomes NEW.
  final at = offset.clamp(0, text.length);
  final after = TodoItem(text: text.substring(at));
  items[loc.itemIndex] = item.copyWith(text: text.substring(0, at));
  items.insert(loc.itemIndex + 1, after);
  return OpResult(
    normalize(_replaceList(doc, loc.listIndex, list.copyWith(items: items))),
    CursorTarget.item(after.id, 0),
  );
}

/// Enter on an empty item: the items below move into a new list.
OpResult _newListFromEmptyItem(TodoDocument doc, int listIndex, int itemIndex) {
  final list = doc.lists[listIndex];
  final above = list.items.sublist(0, itemIndex);
  final below = list.items.sublist(itemIndex + 1);
  final newList = TodoList(name: defaultNewListName, items: below);
  final lists = [...doc.lists]
    ..[listIndex] = list.copyWith(items: above)
    ..insert(listIndex + 1, newList);
  return OpResult(
    normalize(TodoDocument(lists)),
    CursorTarget.listName(newList.id, 0, defaultNewListName.length),
  );
}

// ---------------------------------------------------------------------------
// Backspace

/// Backspace at the start of item [itemId]. Returns null if nothing happens.
OpResult? backspaceAtStart(TodoDocument doc, String itemId) {
  final loc = doc.locate(itemId)!;
  final list = doc.lists[loc.listIndex];
  final item = list.items[loc.itemIndex];

  if (loc.itemIndex > 0) {
    // Merge with the previous item; it keeps its state.
    final prev = list.items[loc.itemIndex - 1];
    final items = [...list.items]
      ..[loc.itemIndex - 1] = prev.copyWith(text: prev.text + item.text)
      ..removeAt(loc.itemIndex);
    return OpResult(
      normalize(_replaceList(doc, loc.listIndex, list.copyWith(items: items))),
      CursorTarget.item(prev.id, prev.text.length),
    );
  }

  if (loc.listIndex == 0) return null;

  // First item of a list: merge this list into the previous one.
  final prevList = doc.lists[loc.listIndex - 1];
  final prevItems = _isOnlyEmptyItem(prevList) ? <TodoItem>[] : prevList.items;
  final lists = [...doc.lists]
    ..[loc.listIndex - 1] = prevList.copyWith(
      items: [...prevItems, ...list.items],
    )
    ..removeAt(loc.listIndex);
  return OpResult(
    normalize(TodoDocument(lists)),
    CursorTarget.item(item.id, 0),
  );
}

bool _isOnlyEmptyItem(TodoList list) =>
    list.items.length == 1 && list.items.single.text.isEmpty;

// ---------------------------------------------------------------------------
// Paste

/// Whether [text] should be inserted as plain text (rule 1 of §5): a single
/// line with no recognized prefix.
bool isPlainPaste(String text) {
  final lines = splitLines(_trimTrailingLineBreaks(text));
  return lines.length == 1 && !hasRecognizedPrefix(lines.single);
}

String _trimTrailingLineBreaks(String s) =>
    s.replaceFirst(RegExp(r'[\r\n]+$'), '');

/// Pastes structured [text] into item [itemId], replacing the selection
/// [selStart]..[selEnd]. Returns null if the text contains nothing.
OpResult? paste(
  TodoDocument doc,
  String itemId,
  int selStart,
  int selEnd,
  String text,
) {
  final fragment = parseFragment(text);
  if (fragment.isEmpty) return null;

  final loc = doc.locate(itemId)!;
  final list = doc.lists[loc.listIndex];
  final item = list.items[loc.itemIndex];
  final s = selStart.clamp(0, item.text.length);
  final e = selEnd.clamp(s, item.text.length);

  final before = item.copyWith(text: item.text.substring(0, s));
  final afterText = item.text.substring(e);
  final rest = [
    if (afterText.isNotEmpty) TodoItem(text: afterText),
    ...list.items.sublist(loc.itemIndex + 1),
  ];
  final head = [
    ...list.items.sublist(0, loc.itemIndex),
    if (before.text.isNotEmpty) before,
    ...fragment.looseItems,
  ];

  final lists = [...doc.lists];
  CursorTarget cursor;
  if (fragment.lists.isEmpty) {
    lists[loc.listIndex] = list.copyWith(items: [...head, ...rest]);
    final last = fragment.looseItems.last;
    cursor = CursorTarget.item(last.id, last.text.length);
  } else {
    lists[loc.listIndex] = list.copyWith(items: head);
    final pasted = [...fragment.lists];
    final lastList = pasted.last;
    final lastItems = [...lastList.items, ...rest];
    if (lastItems.isEmpty) lastItems.add(TodoItem());
    pasted[pasted.length - 1] = lastList.copyWith(items: lastItems);
    lists.insertAll(loc.listIndex + 1, pasted);
    final allPasted = [
      ...fragment.looseItems,
      for (final l in fragment.lists) ...l.items,
    ];
    // Normally the end of the last pasted item. If only empty headers were
    // pasted, the start of the first item of the last pasted list.
    cursor = allPasted.isNotEmpty
        ? CursorTarget.item(allPasted.last.id, allPasted.last.text.length)
        : CursorTarget.item(lastItems.first.id, 0);
  }
  return OpResult(normalize(TodoDocument(lists)), cursor);
}

// ---------------------------------------------------------------------------
// Item state and quantity

const _nextState = {
  ItemState.newItem: ItemState.done,
  ItemState.done: ItemState.failed,
  ItemState.failed: ItemState.newItem,
};

OpResult cycleState(TodoDocument doc, String itemId) {
  final item = doc.itemById(itemId)!;
  return OpResult(
    normalize(
      _replaceItem(doc, itemId, item.copyWith(state: _nextState[item.state])),
    ),
  );
}

/// The + button: adds 1 to the quantity and selects the number.
OpResult incrementQuantity(TodoDocument doc, String itemId, NumberContext ctx) {
  final item = doc.itemById(itemId)!;
  final r = amounts.incrementQuantity(item.text, ctx);
  return OpResult(
    normalize(_replaceItem(doc, itemId, item.copyWith(text: r.text))),
    CursorTarget.item(itemId, r.start, r.end),
  );
}

// ---------------------------------------------------------------------------
// List operations

OpResult renameList(TodoDocument doc, String listId, String name) {
  final i = doc.listIndexOf(listId);
  return OpResult(
    normalize(
      _replaceList(doc, i, doc.lists[i].copyWith(name: _singleLine(name))),
    ),
  );
}

/// Sets every item in the list to NEW. Quantities are kept.
OpResult resetList(TodoDocument doc, String listId) {
  final i = doc.listIndexOf(listId);
  final list = doc.lists[i];
  return OpResult(
    normalize(
      _replaceList(
        doc,
        i,
        list.copyWith(
          items: [
            for (final it in list.items) it.copyWith(state: ItemState.newItem),
          ],
        ),
      ),
    ),
  );
}

/// Removes every DONE item from the list. FAILED items are kept.
OpResult deleteDone(TodoDocument doc, String listId) {
  final i = doc.listIndexOf(listId);
  final list = doc.lists[i];
  return OpResult(
    normalize(
      _replaceList(
        doc,
        i,
        list.copyWith(
          items: list.items.where((it) => it.state != ItemState.done).toList(),
        ),
      ),
    ),
  );
}

OpResult deleteList(TodoDocument doc, String listId) => OpResult(
  normalize(TodoDocument(doc.lists.where((l) => l.id != listId).toList())),
);

/// Removes the items with the given ids, in any list.
OpResult deleteItems(TodoDocument doc, Set<String> itemIds) => OpResult(
  normalize(
    TodoDocument([
      for (final list in doc.lists)
        list.items.any((it) => itemIds.contains(it.id))
            ? list.copyWith(
                items: list.items
                    .where((it) => !itemIds.contains(it.id))
                    .toList(),
              )
            : list,
    ]),
  ),
);

/// The items with the given ids, in document order.
List<TodoItem> itemsInOrder(TodoDocument doc, Set<String> itemIds) => [
  for (final list in doc.lists)
    for (final item in list.items)
      if (itemIds.contains(item.id)) item,
];

/// Sets the state of each item in [states] that still exists. Used to undo
/// a reset without discarding edits made since.
OpResult restoreStates(TodoDocument doc, Map<String, ItemState> states) =>
    OpResult(
      TodoDocument([
        for (final list in doc.lists)
          list.copyWith(
            items: [
              for (final it in list.items)
                states.containsKey(it.id)
                    ? it.copyWith(state: states[it.id])
                    : it,
            ],
          ),
      ]),
    );
