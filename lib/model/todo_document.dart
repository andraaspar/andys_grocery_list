/// Immutable data model (plan §2).
///
/// The `id`s exist only in memory. They keep text controllers and focus nodes
/// stable across rebuilds and are never written to the file.
library;

enum ItemState { newItem, done, failed }

int _idCounter = 0;

/// Returns a new id, unique within this process.
String newId() => 'n${_idCounter++}';

class TodoItem {
  TodoItem({String? id, this.state = ItemState.newItem, this.text = ''})
    : id = id ?? newId();

  final String id;
  final ItemState state;
  final String text;

  TodoItem copyWith({ItemState? state, String? text}) =>
      TodoItem(id: id, state: state ?? this.state, text: text ?? this.text);

  @override
  String toString() => 'TodoItem($state, "$text")';
}

class TodoList {
  TodoList({String? id, this.name = '', this.items = const []})
    : id = id ?? newId();

  final String id;
  final String name;
  final List<TodoItem> items;

  TodoList copyWith({String? name, List<TodoItem>? items}) =>
      TodoList(id: id, name: name ?? this.name, items: items ?? this.items);

  @override
  String toString() => 'TodoList("$name", $items)';
}

class TodoDocument {
  const TodoDocument(this.lists);

  final List<TodoList> lists;

  /// Finds the item with [itemId], with the indices of its list and itself.
  ({int listIndex, int itemIndex})? locate(String itemId) {
    for (var l = 0; l < lists.length; l++) {
      final items = lists[l].items;
      for (var i = 0; i < items.length; i++) {
        if (items[i].id == itemId) return (listIndex: l, itemIndex: i);
      }
    }
    return null;
  }

  int listIndexOf(String listId) => lists.indexWhere((l) => l.id == listId);

  TodoItem? itemById(String itemId) {
    final loc = locate(itemId);
    return loc == null ? null : lists[loc.listIndex].items[loc.itemIndex];
  }

  @override
  String toString() => 'TodoDocument($lists)';
}
