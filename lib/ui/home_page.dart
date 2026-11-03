import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import '../app_name.dart';
import '../model/amounts.dart';
import '../model/clipboard_format.dart';
import '../model/operations.dart' show CursorTarget, itemsInOrder;
import '../model/todo_document.dart';
import '../state/document_controller.dart';
import '../state/selection_controller.dart';
import 'dialogs.dart';
import 'item_row.dart';
import 'list_footer.dart';
import 'list_header.dart';
import 'scroll_memory.dart';
import 'sentinel_controller.dart';

/// Approximate height of one item row, used to size the space below the last
/// item so it can be scrolled to the top of the viewport (plan §3, Scrolling).
const itemRowHeight = 48.0;

/// The main screen: one scrolling list of list headers, item rows and total
/// lines, followed by blank space.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.document, this.scrollMemory});

  final DocumentController document;

  /// Where the scroll position is remembered. Null: it is not.
  final ScrollMemory? scrollMemory;

  @override
  State<HomePage> createState() => _HomePageState();
}

sealed class _Row {
  const _Row(this.key, this.pos);
  final String key;
  final RowPosition pos;
}

class _HeaderRow extends _Row {
  _HeaderRow(this.list, int l) : super(_listKey(list.id), (list: l, item: -1));
  final TodoList list;
}

class _ItemRow extends _Row {
  _ItemRow(this.list, this.item, int l, int i)
    : super(item.id, (list: l, item: i));
  final TodoList list;
  final TodoItem item;
}

class _FooterRow extends _Row {
  _FooterRow(this.list, this.total, int l)
    : super('total:${list.id}', (list: l, item: list.items.length));
  final TodoList list;
  final String total;
}

class _SpaceRow extends _Row {
  const _SpaceRow(int lists) : super('space', (list: lists, item: -1));
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

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _items = <String, _ItemField>{};
  final _names = <String, _NameField>{};
  final _listController = ListController();
  final _scrollController = ScrollController();
  final _selection = SelectionController();

  List<_Row> _rows = const [];
  Map<String, int> _rowIndex = const {};

  /// The mounted row widgets, by row key, for measuring the scroll anchor.
  final _rowContexts = <String, BuildContext>{};
  Timer? _anchorSaveTimer;

  DocumentController get _document => widget.document;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _document.addListener(_onDocumentChanged);
    _document.onReloadedBeforeSave = _onReloadedBeforeSave;
    _selection.addListener(_onSelectionChanged);
    _syncFields();
    _buildRows();
    final anchor = widget.scrollMemory?.load();
    if (anchor != null) _restoreAnchor(anchor);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _anchorSaveTimer?.cancel();
    _saveAnchor();
    if (_document.onReloadedBeforeSave == _onReloadedBeforeSave) {
      _document.onReloadedBeforeSave = null;
    }
    _document.removeListener(_onDocumentChanged);
    _selection.removeListener(_onSelectionChanged);
    _selection.dispose();
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
    // A reload from the file keeps the view on the same row (plan §3).
    // Reloads keep the ids of unchanged rows, so the row is found by key
    // first, and by position if it is gone.
    final anchor = _document.reloading ? _currentAnchor() : null;
    final anchorKey = anchor == null ? null : _rows[_rowIndexAt(anchor)].key;
    _syncFields();
    _selection.retainOnly(_items.keys.toSet());
    setState(_buildRows);
    final cursor = _document.takeCursor();
    if (cursor != null) _moveCursor(cursor);
    if (anchor != null) {
      final index = _rowIndex[anchorKey];
      if (index != null) {
        _jumpToRow(index, anchor.offset);
      } else {
        _restoreAnchor(anchor);
      }
    }
  }

  void _onReloadedBeforeSave() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('File changed externally — reloaded')),
      );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _saveAnchor();
  }

  void _onSelectionChanged() => setState(() {});

  void _buildRows() {
    final rows = <_Row>[];
    final lists = _document.doc.lists;
    for (var l = 0; l < lists.length; l++) {
      final list = lists[l];
      rows.add(_HeaderRow(list, l));
      for (var i = 0; i < list.items.length; i++) {
        rows.add(_ItemRow(list, list.items[i], l, i));
      }
      // After the last item, so it never moves the items above (plan §4).
      final total = listTotal(list, _document.numberContext);
      if (total != null) {
        rows.add(_FooterRow(list, formatTotal(total, _document.locale), l));
      }
    }
    rows.add(_SpaceRow(lists.length));
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
  // Scroll memory (plan §3, Scrolling)

  /// The scroll offset at which the row's top is at the top of the viewport,
  /// or null if the row is not laid out.
  double? _rowTop(String rowKey) {
    final ro = _rowContexts[rowKey]?.findRenderObject();
    if (ro == null || !ro.attached) return null;
    return RenderAbstractViewport.of(ro).getOffsetToReveal(ro, 0).offset;
  }

  ScrollAnchor? _currentAnchor() {
    if (!_listController.isAttached || !_scrollController.hasClients) {
      return null;
    }
    final range = _listController.visibleRange;
    if (range == null || range.$1 >= _rows.length) return null;
    final row = _rows[range.$1];
    final top = _rowTop(row.key);
    final offset = top == null ? 0.0 : _scrollController.offset - top;
    return ScrollAnchor(row.pos, offset < 0 ? 0 : offset);
  }

  void _saveAnchor() {
    final memory = widget.scrollMemory;
    final anchor = _currentAnchor();
    if (memory != null && anchor != null) memory.save(anchor);
  }

  void _scheduleAnchorSave() {
    if (widget.scrollMemory == null) return;
    _anchorSaveTimer?.cancel();
    _anchorSaveTimer = Timer(const Duration(milliseconds: 300), _saveAnchor);
  }

  int _rowIndexAt(ScrollAnchor anchor) =>
      anchor.resolve([for (final r in _rows) r.pos]).index;

  /// Jumps to [anchor] after the next layout, without animation. If its row
  /// is gone, the closest earlier row is used.
  void _restoreAnchor(ScrollAnchor anchor) {
    final target = anchor.resolve([for (final r in _rows) r.pos]);
    _jumpToRow(target.index, target.offset);
  }

  /// After the next layout, jumps to the row at [index] and scrolls [offset]
  /// pixels past its top: first to the row, then, once it is laid out, by
  /// the exact pixel offset.
  void _jumpToRow(int index, double offset) {
    final rowKey = _rows[index].key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_listController.isAttached) return;
      if (!_scrollController.hasClients) return;
      _listController.jumpToItem(
        index: index,
        scrollController: _scrollController,
        alignment: 0,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final top = _rowTop(rowKey);
        if (top == null) return;
        final p = _scrollController.position;
        _scrollController.jumpTo(
          (top + offset).clamp(p.minScrollExtent, p.maxScrollExtent),
        );
      });
      WidgetsBinding.instance.scheduleFrame();
    });
  }

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
  // Selection mode (plan §6)

  void _enterSelection(String itemId) {
    FocusManager.instance.primaryFocus?.unfocus();
    _selection.select(itemId);
  }

  Future<void> _copySelected() async {
    final messenger = ScaffoldMessenger.of(context);
    final items = itemsInOrder(_document.doc, _selection.ids);
    await Clipboard.setData(
      ClipboardData(text: formatItems(items, _document.numberContext)),
    );
    final n = items.length;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Copied $n ${n == 1 ? 'item' : 'items'}')),
      );
  }

  Future<void> _deleteSelected() async {
    final ids = _selection.ids;
    if (ids.length > 1 && !await confirmDeleteItems(context, ids.length)) {
      return;
    }
    _selection.clear();
    _document.deleteItems(ids);
  }

  AppBar _buildAppBar() {
    if (!_selection.active) return AppBar(title: Text(appName()));
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Close',
        onPressed: _selection.clear,
      ),
      title: Text('${_selection.count} selected'),
      actions: [
        IconButton(
          icon: const Icon(Icons.copy),
          tooltip: 'Copy',
          onPressed: _copySelected,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete',
          onPressed: _deleteSelected,
        ),
      ],
    );
  }

  // -------------------------------------------------------------------------
  // Build

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back leaves selection mode instead of the app.
      canPop: !_selection.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _selection.clear();
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        body: NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            _scheduleAnchorSave();
            return false;
          },
          child: LayoutBuilder(
            builder: (context, constraints) => SuperListView.builder(
              listController: _listController,
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              itemCount: _rows.length,
              findChildIndexCallback: (key) =>
                  key is ValueKey<String> ? _rowIndex[key.value] : null,
              itemBuilder: (context, index) {
                final row = _rows[index];
                return _TrackedRow(
                  key: ValueKey(row.key),
                  rowKey: row.key,
                  contexts: _rowContexts,
                  child: _buildRow(row, constraints.maxHeight),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(_Row row, double viewportHeight) {
    switch (row) {
      case _HeaderRow(:final list):
        final f = _names[list.id]!;
        return ListHeader(
          controller: f.controller,
          focusNode: f.focusNode,
          onChanged: (name) => _document.renameList(list.id, name),
          onSubmitted: () => _focusFirstItem(list),
          onAction: (action) => _onListAction(list, action),
        );
      case _ItemRow(:final item):
        final f = _items[item.id]!;
        final selecting = _selection.active;
        return ItemRow(
          item: item,
          controller: f.controller,
          focusNode: f.focusNode,
          onCycleState: () => _document.cycleState(item.id),
          onIncrement: selecting
              ? null
              : () => _document.incrementQuantity(item.id),
          onLongPressIcon: () => _enterSelection(item.id),
          selectionMode: selecting,
          selected: _selection.contains(item.id),
          onToggleSelection: () => _selection.toggle(item.id),
        );
      case _FooterRow(:final total):
        return ListFooter(total: total);
      case _SpaceRow():
        return GestureDetector(
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

/// Registers its context under [rowKey] while mounted, so the page can
/// measure where the row is.
class _TrackedRow extends StatefulWidget {
  const _TrackedRow({
    super.key,
    required this.rowKey,
    required this.contexts,
    required this.child,
  });

  final String rowKey;
  final Map<String, BuildContext> contexts;
  final Widget child;

  @override
  State<_TrackedRow> createState() => _TrackedRowState();
}

class _TrackedRowState extends State<_TrackedRow> {
  @override
  void initState() {
    super.initState();
    widget.contexts[widget.rowKey] = context;
  }

  @override
  void didUpdateWidget(_TrackedRow old) {
    super.didUpdateWidget(old);
    if (old.rowKey != widget.rowKey) {
      if (old.contexts[old.rowKey] == context) old.contexts.remove(old.rowKey);
      widget.contexts[widget.rowKey] = context;
    }
  }

  @override
  void dispose() {
    if (widget.contexts[widget.rowKey] == context) {
      widget.contexts.remove(widget.rowKey);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
