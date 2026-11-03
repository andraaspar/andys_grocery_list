import 'dart:async';

import 'package:flutter/foundation.dart';

import '../model/markdown_codec.dart';
import '../model/number_parser.dart';
import '../model/operations.dart' as ops;
import '../model/todo_document.dart';
import '../storage/saf_storage.dart';

/// Holds the document, applies edit operations to it, and keeps it in sync
/// with its file (plan §8, §9).
///
/// Without a storage the document lives in memory only (used by tests).
class DocumentController extends ChangeNotifier {
  DocumentController(
    TodoDocument doc, {
    this.locale,
    NumberContext? numberContext,
    this._storage,
    this.uri,
    this._lastKnownContent,
    this._lastModified,
  }) : _doc = ops.normalize(doc),
       numberContext =
           numberContext ??
           (locale == null
               ? NumberContext.en
               : NumberContext.forLocale(locale));

  /// Reads the file at [uri] and returns a controller that autosaves to it.
  static Future<DocumentController> open(
    DocumentStorage storage,
    String uri, {
    String? locale,
  }) async {
    final content = await storage.read(uri);
    final modified = await storage.lastModified(uri);
    return DocumentController(
      parseDocument(content),
      locale: locale,
      storage: storage,
      uri: uri,
      lastKnownContent: content,
      lastModified: modified,
    );
  }

  static const saveDelay = Duration(milliseconds: 500);
  static const pollInterval = Duration(seconds: 5);

  TodoDocument _doc;
  TodoDocument get doc => _doc;

  final DocumentStorage? _storage;

  /// The file's URI, or null when there is no storage.
  final String? uri;

  /// The content last read from or written to the file, and its
  /// modification time.
  String? _lastKnownContent;
  int? _lastModified;

  /// Bumped on every local edit, so a save can tell whether more edits came
  /// in while it was writing.
  int _edits = 0;
  int _savedEdits = 0;
  bool get hasUnsavedChanges => _edits != _savedEdits;

  Timer? _saveTimer;
  Timer? _pollTimer;

  /// File operations run one at a time, in order.
  Future<void> _queue = Future.value();

  bool _disposed = false;

  /// True while listeners are notified of a reload from the file. The UI uses
  /// it to keep the scroll position anchored to the same row.
  bool get reloading => _reloading;
  bool _reloading = false;

  /// Called when a save found that the file had changed outside the app and
  /// reloaded it instead, discarding the unsaved local edits.
  VoidCallback? onReloadedBeforeSave;

  /// Called when reading or writing the file fails.
  void Function(Object error)? onStorageError;

  /// The locale used to format totals (plan §4). Null means English.
  String? locale;

  NumberContext numberContext;

  /// Where focus should go after the last operation. The UI consumes it with
  /// [takeCursor].
  ops.CursorTarget? _pendingCursor;

  ops.CursorTarget? takeCursor() {
    final c = _pendingCursor;
    _pendingCursor = null;
    return c;
  }

  void _apply(ops.OpResult? r) {
    if (r == null) return;
    final changed = !identical(r.doc, _doc);
    _doc = r.doc;
    if (r.cursor != null) _pendingCursor = r.cursor;
    if (changed) _edited();
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // Saving and reloading (plan §8)

  void _edited() {
    _edits++;
    if (_storage == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(saveDelay, save);
  }

  Future<T> _enqueue<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Writes the document now if it has unsaved edits. Before writing, checks
  /// whether the file changed outside the app; if so, reloads it instead.
  Future<void> save() {
    _saveTimer?.cancel();
    _saveTimer = null;
    final storage = _storage;
    if (storage == null) return Future.value();
    return _enqueue(() async {
      if (_disposed || !hasUnsavedChanges) return;
      final edits = _edits;
      final content = serializeDocument(_doc, numberContext);
      try {
        if (content == _lastKnownContent) {
          _savedEdits = edits;
          return;
        }
        final external = await _readIfChanged(storage);
        if (_disposed) return;
        if (external != null) {
          _reload(external.content, external.modified);
          onReloadedBeforeSave?.call();
          return;
        }
        await storage.write(uri!, content);
        _lastKnownContent = content;
        _lastModified = await storage.lastModified(uri!);
        _savedEdits = edits;
      } catch (e) {
        onStorageError?.call(e);
      }
    });
  }

  /// Reloads the file if it changed outside the app and there are no unsaved
  /// local edits. With unsaved edits, the next [save] deals with it.
  Future<void> checkExternalChange() {
    final storage = _storage;
    if (storage == null) return Future.value();
    return _enqueue(() async {
      if (_disposed || hasUnsavedChanges) return;
      try {
        final external = await _readIfChanged(storage);
        if (_disposed || external == null || hasUnsavedChanges) return;
        _reload(external.content, external.modified);
      } catch (e) {
        onStorageError?.call(e);
      }
    });
  }

  /// Returns the file's content if it differs from the last known content.
  /// Skips the read when the modification time is unchanged.
  Future<({String content, int? modified})?> _readIfChanged(
    DocumentStorage storage,
  ) async {
    final modified = await storage.lastModified(uri!);
    if (modified != null && modified == _lastModified) return null;
    final content = await storage.read(uri!);
    _lastModified = modified;
    if (content == _lastKnownContent) return null;
    return (content: content, modified: modified);
  }

  void _reload(String content, int? modified) {
    _saveTimer?.cancel();
    _saveTimer = null;
    _lastKnownContent = content;
    _lastModified = modified;
    _savedEdits = _edits;
    _doc = ops.normalize(reuseIds(_doc, parseDocument(content)));
    _pendingCursor = null;
    _reloading = true;
    try {
      notifyListeners();
    } finally {
      _reloading = false;
    }
  }

  /// Checks for external changes every [pollInterval] while the app is in
  /// the foreground.
  void startPolling() {
    if (_storage == null) return;
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(pollInterval, (_) => checkExternalChange());
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Requests focus somewhere without changing the document.
  void focus(ops.CursorTarget target) {
    _pendingCursor = target;
    notifyListeners();
  }

  void setItemText(String itemId, String text) {
    final item = _doc.itemById(itemId);
    if (item == null || item.text == text) return;
    _apply(ops.setItemText(_doc, itemId, text));
  }

  /// Enter in an item whose current text is [text], at [offset].
  void enter(String itemId, String text, int offset) {
    if (_doc.itemById(itemId) == null) return;
    final synced = ops.setItemText(_doc, itemId, text).doc;
    _apply(ops.enter(synced, itemId, offset));
  }

  void backspaceAtStart(String itemId) {
    if (_doc.itemById(itemId) == null) return;
    _apply(ops.backspaceAtStart(_doc, itemId));
  }

  void paste(String itemId, int start, int end, String text) {
    if (_doc.itemById(itemId) == null) return;
    _apply(ops.paste(_doc, itemId, start, end, text));
  }

  void cycleState(String itemId) => _apply(ops.cycleState(_doc, itemId));

  /// The + button: adds 1 to the quantity and selects the number.
  void incrementQuantity(String itemId) {
    if (_doc.itemById(itemId) == null) return;
    _apply(ops.incrementQuantity(_doc, itemId, numberContext));
  }

  void renameList(String listId, String name) {
    final i = _doc.listIndexOf(listId);
    if (i < 0 || _doc.lists[i].name == name) return;
    _apply(ops.renameList(_doc, listId, name));
  }

  void itemBlurred(String itemId) {
    final r = ops.normalizeQuantityOnBlur(_doc, itemId, numberContext);
    if (!identical(r.doc, _doc)) _apply(r);
  }

  /// Sets every item in the list to NEW. Returns the previous states, for
  /// [restoreStates] (Undo).
  Map<String, ItemState> resetList(String listId) {
    final i = _doc.listIndexOf(listId);
    if (i < 0) return const {};
    final previous = {for (final it in _doc.lists[i].items) it.id: it.state};
    _apply(ops.resetList(_doc, listId));
    return previous;
  }

  void restoreStates(Map<String, ItemState> states) =>
      _apply(ops.restoreStates(_doc, states));

  void deleteDone(String listId) {
    if (_doc.listIndexOf(listId) < 0) return;
    _apply(ops.deleteDone(_doc, listId));
  }

  /// Deletes the selected items (plan §6).
  void deleteItems(Set<String> itemIds) {
    if (itemIds.isEmpty) return;
    _apply(ops.deleteItems(_doc, itemIds));
  }

  void deleteList(String listId) {
    if (_doc.listIndexOf(listId) < 0) return;
    _apply(ops.deleteList(_doc, listId));
  }
}

/// Gives the lists and items of [fresh] the ids of matching ones in [old], so
/// a reload keeps text fields, focus and selection on the same rows (plan §8).
///
/// Lists match by name, items by text: first within the matching list, then
/// anywhere. Each old id is used at most once.
TodoDocument reuseIds(TodoDocument old, TodoDocument fresh) {
  final unusedLists = [...old.lists];
  final unusedItems = <String, List<TodoItem>>{};
  for (final list in old.lists) {
    for (final item in list.items) {
      (unusedItems[item.text] ??= []).add(item);
    }
  }

  TodoItem? take(String text, {TodoList? inList}) {
    final candidates = unusedItems[text];
    if (candidates == null || candidates.isEmpty) return null;
    final i = inList == null
        ? 0
        : candidates.indexWhere((c) => inList.items.contains(c));
    if (i < 0) return null;
    return candidates.removeAt(i);
  }

  // First pass: lists by name, items within their list.
  final matchedLists = <TodoList?>[];
  final itemIds = <List<String?>>[];
  for (final list in fresh.lists) {
    final li = unusedLists.indexWhere((l) => l.name == list.name);
    final match = li < 0 ? null : unusedLists.removeAt(li);
    matchedLists.add(match);
    itemIds.add([
      for (final item in list.items)
        match == null ? null : take(item.text, inList: match)?.id,
    ]);
  }

  // Second pass: remaining items anywhere.
  return TodoDocument([
    for (var l = 0; l < fresh.lists.length; l++)
      TodoList(
        id: matchedLists[l]?.id,
        name: fresh.lists[l].name,
        items: [
          for (var i = 0; i < fresh.lists[l].items.length; i++)
            TodoItem(
              id: itemIds[l][i] ?? take(fresh.lists[l].items[i].text)?.id,
              state: fresh.lists[l].items[i].state,
              text: fresh.lists[l].items[i].text,
            ),
        ],
      ),
  ]);
}
