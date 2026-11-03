import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../app_name.dart';
import '../model/amounts.dart';
import '../model/clipboard_format.dart';
import '../model/operations.dart' show CursorTarget;
import '../model/todo_document.dart';
import '../state/document_controller.dart';
import 'dialogs.dart';
import 'item_row.dart';
import 'list_footer.dart';
import 'list_header.dart';
import 'sentinel_controller.dart';

/// Approximate height of one item row, used to size the space below the last
/// item so it can be scrolled to the top of the viewport (plan §3, Scrolling).
const itemRowHeight = 48.0;

/// The main screen: one scrolling list of list headers, item rows and total
/// lines, followed by blank space.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.document});

  final DocumentController document;

  @override
  State<HomePage> createState() => _HomePageState();
}

sealed class _Row {
  const _Row(this.key);
  final String key;
}

class _HeaderRow extends _Row {
  _HeaderRow(this.list) : super(_listKey(list.id));
  final TodoList list;
}

class _ItemRow extends _Row {
  _ItemRow(this.list, this.item) : super(item.id);
  final TodoList list;
  final TodoItem item;
}

class _FooterRow extends _Row {
  _FooterRow(this.list, this.total) : super('total:${list.id}');
  final TodoList list;
  final String total;
}

class _SpaceRow extends _Row {
  const _SpaceRow() : super('space');
}

String _listKey(String listId) => 'list:$listId';

class _ItemField {
  _ItemField(this.controller, this.focusNode);
  final SentinelController controller;
  final FocusNode focusNode;
}

class _NameField {
  _NameField(this.controller, this.focusNode);
  final TextEditingController controller;
  final FocusNode focusNode;
}

class _HomePageState extends State<HomePage> {
  final _items = <String, _ItemField>{};
  final _names = <String, _NameField>{};
  final _listController = ListController();
  final _scrollController = ScrollController();

  List<_Row> _rows = const [];
  Map<String, int> _rowIndex = const {};

  DocumentController get _document => widget.document;

  @override
  void initState() {
    super.initState();
    _document.addListener(_onDocumentChanged);
    _syncFields();
    _buildRows();
  }

  @override
  void dispose() {
    _document.removeListener(_onDocumentChanged);
    for (final f in _items.values) {
      f.controller.dispose();
      f.focusNode.dispose();
    }
    for (final f in _names.values) {
      f.controller.dispose();
      f.focusNode.dispose();
    }
    _listController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onDocumentChanged() {
    _syncFields();
    setState(_buildRows);
    final cursor = _document.takeCursor();
    if (cursor != null) _moveCursor(cursor);
  }

  void _buildRows() {
    final rows = <_Row>[];
    for (final list in _document.doc.lists) {
      rows.add(_HeaderRow(list));
      for (final item in list.items) {
        rows.add(_ItemRow(list, item));
      }
      // After the last item, so it never moves the items above (plan §4).
      final total = listTotal(list, _document.numberContext);
      if (total != null) {
        rows.add(_FooterRow(list, formatTotal(total, _document.locale)));
      }
    }
    rows.add(const _SpaceRow());
    _rows = rows;
    _rowIndex = {for (var i = 0; i < rows.length; i++) rows[i].key: i};
  }

  // -------------------------------------------------------------------------
  // Controllers and focus nodes, one per item and per list, keyed by id.

  void _syncFields() {
    final doc = _document.doc;
    final itemIds = <String>{};
    final listIds = <String>{};
    for (final list in doc.lists) {
      listIds.add(list.id);
      final name = _names.putIfAbsent(list.id, () => _createNameField(list));
      if (name.controller.text != list.name) {
        name.controller.value = TextEditingValue(
          text: list.name,
          selection: TextSelection.collapsed(offset: list.name.length),
        );
      }
      for (final item in list.items) {
        itemIds.add(item.id);
        final field = _items.putIfAbsent(item.id, () => _createItemField(item));
        field.controller.muted = item.state != ItemState.newItem;
        if (field.controller.modelText != item.text) {
          field.controller.setModel(item.text);
        }
      }
    }
    _removeStale(_items, itemIds, (f) {
      f.controller.dispose();
      f.focusNode.dispose();
    });
    _removeStale(_names, listIds, (f) {
      f.controller.dispose();
      f.focusNode.dispose();
    });
  }

  /// Removes fields whose item or list is gone. They are disposed after the
  /// next frame, once their widgets have been unmounted.
  void _removeStale<T>(
    Map<String, T> fields,
    Set<String> keep,
    void Function(T) dispose,
  ) {
    final stale = fields.keys.where((id) => !keep.contains(id)).toList();
    if (stale.isEmpty) return;
    final removed = [for (final id in stale) fields.remove(id) as T];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      removed.forEach(dispose);
    });
  }

  _ItemField _createItemField(TodoItem item) {
    final id = item.id;
    final controller = SentinelController(
      text: item.text,
      numberContext: () => _document.numberContext,
    )..muted = item.state != ItemState.newItem;
    controller.onTextChanged = (text) => _document.setItemText(id, text);
    controller.onEnter = (text, offset) => _document.enter(id, text, offset);
    controller.onBackspaceAtStart = () => _document.backspaceAtStart(id);
    controller.onPaste = (start, end, text) =>
        _document.paste(id, start, end, text);
    final focusNode = FocusNode(debugLabel: 'item $id');
    focusNode.addListener(() {
      if (!focusNode.hasFocus) _document.itemBlurred(id);
    });
    return _ItemField(controller, focusNode);
  }

  _NameField _createNameField(TodoList list) => _NameField(
    TextEditingController(text: list.name),
    FocusNode(debugLabel: 'list ${list.id}'),
  );

  // -------------------------------------------------------------------------
  // Focus

  /// Focuses [target] after the next frame. If its row is not built (it is
  /// scrolled far away), jumps to it first and tries again.
  void _moveCursor(CursorTarget target, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final FocusNode? node = target.isListName
          ? _names[target.id]?.focusNode
          : _items[target.id]?.focusNode;
      if (node == null) return;

      if (node.context == null) {
        final index =
            _rowIndex[target.isListName ? _listKey(target.id) : target.id];
        if (index == null || attempt >= 3 || !_listController.isAttached) {
          return;
        }
        _listController.jumpToItem(
          index: index,
          scrollController: _scrollController,
          alignment: 0.3,
        );
        _moveCursor(target, attempt: attempt + 1);
        WidgetsBinding.instance.scheduleFrame();
        return;
      }

      if (target.isListName) {
        final c = _names[target.id]!.controller;
        c.selection = TextSelection(
          baseOffset: target.start.clamp(0, c.text.length),
          extentOffset: target.end.clamp(0, c.text.length),
        );
      } else {
        _items[target.id]!.controller.setModelSelection(
          target.start,
          target.end,
        );
      }
      node.requestFocus();
    });
  }

  void _focusFirstItem(TodoList list) {
    final current = _document.doc.lists.firstWhere(
      (l) => l.id == list.id,
      orElse: () => list,
    );
    _document.focus(CursorTarget.item(current.items.first.id, 0));
  }

  void _focusLastItem() {
    final last = _document.doc.lists.last.items.last;
    _document.focus(CursorTarget.item(last.id, last.text.length));
  }

  // -------------------------------------------------------------------------
  // The ⋯ menu (plan §4)

  Future<void> _onListAction(TodoList list, ListAction action) async {
    final messenger = ScaffoldMessenger.of(context);
    final current = _document.doc.lists.firstWhere(
      (l) => l.id == list.id,
      orElse: () => list,
    );
    switch (action) {
      case ListAction.reset:
        final previous = _document.resetList(list.id);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: const Text('List reset'),
              action: SnackBarAction(
                label: 'Undo',
                onPressed: () => _document.restoreStates(previous),
              ),
            ),
          );
      case ListAction.copy:
        await Clipboard.setData(
          ClipboardData(text: formatList(current, _document.numberContext)),
        );
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('List copied')));
      case ListAction.deleteDone:
        _document.deleteDone(list.id);
      case ListAction.delete:
        if (await confirmDeleteList(context, current)) {
          _document.deleteList(list.id);
        }
    }
  }

  // -------------------------------------------------------------------------
  // Build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appName())),
      body: LayoutBuilder(
        builder: (context, constraints) => SuperListView.builder(
          listController: _listController,
          controller: _scrollController,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
          itemCount: _rows.length,
          findChildIndexCallback: (key) =>
              key is ValueKey<String> ? _rowIndex[key.value] : null,
          itemBuilder: (context, index) =>
              _buildRow(_rows[index], constraints.maxHeight),
        ),
      ),
    );
  }

  Widget _buildRow(_Row row, double viewportHeight) {
    final key = ValueKey(row.key);
    switch (row) {
      case _HeaderRow(:final list):
        final f = _names[list.id]!;
        return ListHeader(
          key: key,
          controller: f.controller,
          focusNode: f.focusNode,
          onChanged: (name) => _document.renameList(list.id, name),
          onSubmitted: () => _focusFirstItem(list),
          onAction: (action) => _onListAction(list, action),
        );
      case _ItemRow(:final item):
        final f = _items[item.id]!;
        return ItemRow(
          key: key,
          item: item,
          controller: f.controller,
          focusNode: f.focusNode,
          onCycleState: () => _document.cycleState(item.id),
          onIncrement: () => _document.incrementQuantity(item.id),
        );
      case _FooterRow(:final total):
        return ListFooter(key: key, total: total);
      case _SpaceRow():
        return GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: _focusLastItem,
          child: SizedBox(
            height: (viewportHeight - itemRowHeight).clamp(
              0.0,
              double.infinity,
            ),
          ),
        );
    }
  }
}
