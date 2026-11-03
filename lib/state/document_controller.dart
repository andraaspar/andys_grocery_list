import 'package:flutter/foundation.dart';

import '../model/number_parser.dart';
import '../model/operations.dart' as ops;
import '../model/todo_document.dart';

/// Holds the document and applies edit operations to it (plan §9).
///
/// Storage (autosave, reload) arrives in milestone 7; for now the document
/// lives in memory only.
class DocumentController extends ChangeNotifier {
  DocumentController(
    TodoDocument doc, {
    this.locale,
    NumberContext? numberContext,
  }) : _doc = ops.normalize(doc),
       numberContext =
           numberContext ??
           (locale == null
               ? NumberContext.en
               : NumberContext.forLocale(locale));

  TodoDocument _doc;
  TodoDocument get doc => _doc;

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
    _doc = r.doc;
    if (r.cursor != null) _pendingCursor = r.cursor;
    notifyListeners();
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

  void deleteList(String listId) {
    if (_doc.listIndexOf(listId) < 0) return;
    _apply(ops.deleteList(_doc, listId));
  }
}
