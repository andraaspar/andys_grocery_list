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
import 'display_options.dart';
import 'item_row.dart';
import 'list_footer.dart';
import 'list_header.dart';
import 'scroll_memory.dart';
import 'sentinel_controller.dart';
import 'snackbars.dart';
import 'theme.dart';
import 'usage_help.dart';

/// How much room is kept between the focused row and the edges of the
/// viewport when it is scrolled into view.
const revealMargin = 16.0;

/// The main screen: one scrolling list of list headers, item rows and total
/// lines, followed by short usage instructions.
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.document,
    this.scrollMemory,
    this.onOpenSettings,
    this.helpExpanded = true,
    this.onHelpExpandedChanged,
    this.title,
    this.onTapTitle,
    this.viewMode = false,
    this.onViewModeChanged,
  });

  /// Whether the page starts in view mode, and where its changes go.
  final bool viewMode;
  final ValueChanged<bool>? onViewModeChanged;

  /// Tapping the title opens the file switcher. Null: it can't be tapped.
  final VoidCallback? onTapTitle;

  /// The open file's name. Null: the app name is shown.
  final String? title;

  /// Whether the usage help starts expanded, and where its changes go.
  final bool helpExpanded;
  final ValueChanged<bool>? onHelpExpandedChanged;

  final DocumentController document;

  /// Opens Settings from the overflow menu. Null: there is no menu.
  final VoidCallback? onOpenSettings;

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

class _HelpRow extends _Row {
  const _HelpRow(int lists) : super('help', (list: lists, item: -1));
}

String _listKey(String listId) => 'list:$listId';

class _ItemField {
  _ItemField(this.controller, this.focusNode);
  final SentinelController controller;
  final FocusNode focusNode;
}

/// What is being dragged in reorder mode: an item or a whole list.
typedef _Drag = ({String id, bool isList});

/// Where a drag would drop, and where its indicator line is drawn: on the
/// top or bottom edge of row [rowKey].
///
/// For an item, in front of item [index] of list [listId]. For a list, in
/// front of list [index].
typedef _Drop = ({String? listId, int index, String rowKey, bool below});

class _NameField {
  _NameField(this.controller, this.focusNode);
  final SentinelController controller;
  final FocusNode focusNode;
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver {
  final _items = <String, _ItemField>{};
  final _names = <String, _NameField>{};
  final _listController = ListController();
  final _scrollController = ScrollController();
  final _selection = SelectionController();
  final _viewportKey = GlobalKey();

  // Reorder mode (plan §6a).
  bool _reordering = false;

  /// Editing mode: an item or a list name has the focus. The app bar shows
  /// Done, which, like the back button, ends it.
  bool _editing = false;

  /// View mode: nothing can be edited, deleted or moved; tapping an item
  /// changes its state. The button at the bottom right switches it.
  late bool _viewing = widget.viewMode;
  _Drag? _drag;
  _Drop? _drop;
  Offset? _pointer;
  Timer? _autoScrollTimer;

  List<_Row> _rows = const [];
  Map<String, int> _rowIndex = const {};

  /// The mounted row widgets, by row key, for measuring the scroll anchor.
  final _rowContexts = <String, BuildContext>{};
  Timer? _anchorSaveTimer;
  Timer? _revealTimer;

  /// The operation the shown Undo snackbar reverts. Cleared when the
  /// snackbar closes, or when the document changes in another way.
  UndoToken? _pendingUndo;

  DocumentController get _document => widget.document;

  /// Kept here as well, as the help row is rebuilt when it scrolls back in.
  late bool _helpExpanded = widget.helpExpanded;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _document.addListener(_onDocumentChanged);
    _document.onReloadedBeforeSave = _onReloadedBeforeSave;
    _selection.addListener(_onSelectionChanged);
    FocusManager.instance.addListener(_onFocusChanged);
    _syncFields();
    _buildRows();
    final anchor = widget.scrollMemory?.load();
    if (anchor != null) _restoreAnchor(anchor);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _anchorSaveTimer?.cancel();
    _revealTimer?.cancel();
    _autoScrollTimer?.cancel();
    _saveAnchor();
    if (_document.onReloadedBeforeSave == _onReloadedBeforeSave) {
      _document.onReloadedBeforeSave = null;
    }
    _document.removeListener(_onDocumentChanged);
    _selection.removeListener(_onSelectionChanged);
    FocusManager.instance.removeListener(_onFocusChanged);
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
    final undo = _pendingUndo;
    if (undo != null && !identical(_document.doc, undo.after)) {
      // Undo would no longer put back what the user expects.
      _pendingUndo = null;
      ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    }
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
    _showMessage('File changed externally — reloaded');
  }

  void _showMessage(String message, {UndoToken? undo}) {
    final snack = showMessage(
      ScaffoldMessenger.maybeOf(context),
      message,
      onUndo: undo == null ? null : () => _document.undo(undo),
    );
    _pendingUndo = undo;
    if (undo != null) {
      snack?.closed.then((_) {
        if (identical(_pendingUndo, undo)) _pendingUndo = null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _saveAnchor();
  }

  /// The keyboard opening or the phone rotating shrinks the viewport, which
  /// can hide the focused row. Once the size settles, it is brought back.
  @override
  void didChangeMetrics() {
    _revealTimer?.cancel();
    _revealTimer = Timer(const Duration(milliseconds: 150), _revealFocusedRow);
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
    rows.add(_HelpRow(lists.length));
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
      if (name.controller.modelText != list.name) {
        name.controller.setModel(
          list.name,
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

  /// A sentinel controller like the items', so Backspace in an empty name
  /// is seen too.
  _NameField _createNameField(TodoList list) {
    final id = list.id;
    final controller = SentinelController(text: list.name);
    controller.onTextChanged = (name) => _document.renameList(id, name);
    controller.onBackspaceAtStart = () {
      if (controller.modelText.isEmpty) _document.backspaceListName(id);
    };
    // Text that would be items elsewhere is plain text in a name. The
    // single-line field has already removed any line breaks.
    controller.onPaste = (start, end, text) {
      final pasted = text.replaceAll(RegExp(r'[\r\n]+'), ' ');
      final name = controller.modelText.replaceRange(start, end, pasted);
      _document.renameList(id, name);
      _document.focus(CursorTarget.listName(id, start + pasted.length));
    };
    return _NameField(controller, FocusNode(debugLabel: 'list $id'));
  }

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
      // Nothing is edited in view mode.
      if (!mounted || _viewing) return;
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
        _names[target.id]!.controller.setModelSelection(
          target.start,
          target.end,
        );
      } else {
        _items[target.id]!.controller.setModelSelection(
          target.start,
          target.end,
        );
      }
      node.requestFocus();
      _revealFocusedRow();
    });
  }

  /// The item's or list name's focus node that this page's focus scope
  /// last focused, if any. It keeps it while a menu or dialog is open over
  /// the page, so editing mode doesn't flicker off and on around them.
  FocusNode? _editedNode() {
    final child = FocusScope.of(context).focusedChild;
    if (child == null) return null;
    for (final f in _items.values) {
      if (f.focusNode == child) return child;
    }
    for (final f in _names.values) {
      if (f.focusNode == child) return child;
    }
    return null;
  }

  void _onFocusChanged() {
    if (!mounted) return;
    final editing = _editedNode() != null;
    if (editing != _editing) setState(() => _editing = editing);
  }

  /// Leaves editing mode: the field loses the focus, and with it the
  /// keyboard, the cursor and its handle.
  void _endEditing() => _editedNode()?.unfocus();

  /// The row key of the focused item or list name, if any.
  String? _focusedRowKey() {
    for (final MapEntry(:key, :value) in _items.entries) {
      if (value.focusNode.hasFocus) return key;
    }
    for (final MapEntry(:key, :value) in _names.entries) {
      if (value.focusNode.hasFocus) return _listKey(key);
    }
    return null;
  }

  /// After the next layout, scrolls the focused row fully into view, with
  /// [revealMargin] around it (plan §3). The text field itself only keeps
  /// the caret visible, which can leave the rest of the row, or the row's
  /// other lines, cut off.
  void _revealFocusedRow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final key = _focusedRowKey();
      final ro = key == null ? null : _rowContexts[key]?.findRenderObject();
      if (ro is! RenderBox || !ro.attached) return;
      final viewport = RenderAbstractViewport.of(ro);
      final p = _scrollController.position;
      // The offsets at which the row's top is at the top of the viewport and
      // its bottom at the bottom.
      final top = viewport.getOffsetToReveal(ro, 0).offset - revealMargin;
      final bottom = viewport.getOffsetToReveal(ro, 1).offset + revealMargin;
      // A row taller than the viewport: the caret is kept visible instead.
      if (bottom > top) return;
      final target = p.pixels > top
          ? top
          : p.pixels < bottom
          ? bottom
          : p.pixels;
      final clamped = target.clamp(p.minScrollExtent, p.maxScrollExtent);
      if ((clamped - p.pixels).abs() < 1) return;
      _scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  void _focusFirstItem(TodoList list) {
    final current = _document.doc.lists.firstWhere(
      (l) => l.id == list.id,
      orElse: () => list,
    );
    _document.focus(CursorTarget.item(current.items.first.id, 0));
  }

  // -------------------------------------------------------------------------
  // The ⋯ menu (plan §4)

  Future<void> _onListAction(TodoList list, ListAction action) async {
    final current = _document.doc.lists.firstWhere(
      (l) => l.id == list.id,
      orElse: () => list,
    );
    switch (action) {
      case ListAction.reset:
        final previous = _document.resetList(list.id);
        // Reset's Undo puts back states, so later edits don't invalidate it,
        // and it is not tracked in [_pendingUndo].
        _pendingUndo = null;
        showMessage(
          ScaffoldMessenger.maybeOf(context),
          'List reset',
          onUndo: () => _document.restoreStates(previous),
        );
      case ListAction.copy:
        await Clipboard.setData(
          ClipboardData(text: formatList(current, _document.numberContext)),
        );
        if (!mounted) return;
        _showMessage('List copied');
      case ListAction.deleteDone:
        final n = current.items.where((i) => i.state == ItemState.done).length;
        if (n == 0) {
          _showMessage('No done items');
          return;
        }
        final undo = _document.deleteDone(list.id);
        _showMessage('Deleted ${_countItems(n)}', undo: undo);
      case ListAction.delete:
        if (!await confirmDeleteList(context, current)) return;
        final undo = _document.deleteList(list.id);
        if (!mounted) return;
        _showMessage(
          current.name.isEmpty ? 'List deleted' : 'Deleted "${current.name}"',
          undo: undo,
        );
    }
  }

  // -------------------------------------------------------------------------
  // Selection mode (plan §6)

  void _enterSelection(String itemId) {
    FocusManager.instance.primaryFocus?.unfocus();
    _selection.select(itemId);
  }

  Future<void> _copySelected() async {
    final items = itemsInOrder(_document.doc, _selection.ids);
    await Clipboard.setData(
      ClipboardData(text: formatItems(items, _document.numberContext)),
    );
    if (!mounted) return;
    _showMessage('Copied ${_countItems(items.length)}');
  }

  Future<void> _deleteSelected() async {
    final ids = _selection.ids;
    if (ids.length > 1 && !await confirmDeleteItems(context, ids.length)) {
      return;
    }
    _selection.clear();
    final undo = _document.deleteItems(ids);
    if (!mounted) return;
    _showMessage('Deleted ${_countItems(ids.length)}', undo: undo);
  }

  /// Reorder and Settings, on the normal and the editing bar.
  List<Widget> _pageActions() {
    final openSettings = widget.onOpenSettings;
    return [
      IconButton(
        icon: const Icon(Icons.swap_vert),
        tooltip: 'Reorder',
        onPressed: _enterReorder,
      ),
      if (openSettings != null)
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: () {
            // Coming back would otherwise put the focus, and the keyboard,
            // back on the field.
            _endEditing();
            openSettings();
          },
        ),
    ];
  }

  AppBar _buildAppBar() {
    final editing = _editing && !_selection.active && !_reordering && !_viewing;
    if (!_selection.active && !_reordering && !editing) {
      return AppBar(
        title: _buildTitle(),
        actions: _viewing ? null : _pageActions(),
      );
    }
    // Contextual bars, coloured so the modes are easy to tell apart.
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // The theme's icon themes carry their own colour, which would win over
    // the bar's foreground colour.
    final icons = (theme.appBarTheme.iconTheme ?? const IconThemeData())
        .copyWith(color: scheme.onInverseSurface);
    if (_reordering || editing) {
      return AppBar(
        backgroundColor: scheme.inverseSurface,
        foregroundColor: scheme.onInverseSurface,
        iconTheme: icons,
        actionsIconTheme: icons,
        leading: IconButton(
          icon: const Icon(Icons.check),
          tooltip: 'Done',
          onPressed: _reordering ? _leaveReorder : _endEditing,
        ),
        title: Text(_reordering ? 'Drag to reorder' : 'Editing'),
        actions: editing ? _pageActions() : null,
      );
    }
    return AppBar(
      backgroundColor: scheme.inverseSurface,
      foregroundColor: scheme.onInverseSurface,
      iconTheme: icons,
      actionsIconTheme: icons,
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

  /// The file name, with a ▾ when it opens the file switcher.
  Widget _buildTitle() {
    final text = Text(
      widget.title ?? appName(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    // The file can't be switched in view mode.
    final onTap = _viewing ? null : widget.onTapTitle;
    if (onTap == null) return text;
    return Tooltip(
      message: 'Switch file',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: text),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Reorder mode (plan §6a)
  //
  // The rows are dragged with [Draggable]s, which only start the drag and
  // show the floating row. The pointer is followed by a [Listener] around
  // the whole list instead, as a [Draggable] stops reporting once its row
  // is scrolled away and unmounted.

  // -------------------------------------------------------------------------
  // View mode

  void _toggleViewMode() {
    final viewing = !_viewing;
    if (viewing) {
      FocusManager.instance.primaryFocus?.unfocus();
      _selection.clear();
    }
    setState(() => _viewing = viewing);
    widget.onViewModeChanged?.call(viewing);
  }

  /// Red and locked in view mode, green and open in edit mode.
  Widget _buildModeButton() {
    final states = StateColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return FloatingActionButton(
      onPressed: _toggleViewMode,
      tooltip: _viewing ? 'Switch to edit mode' : 'Switch to view mode',
      backgroundColor: _viewing ? states.failed : states.done,
      // The dark theme's state colours are light.
      foregroundColor: dark ? Colors.black : Colors.white,
      child: Icon(_viewing ? Icons.lock : Icons.lock_open),
    );
  }

  /// How much room is left below the list, so the button doesn't cover its
  /// end: the button's height and its margins.
  static const _modeButtonRoom = 56.0 + 2 * 16;

  // -------------------------------------------------------------------------

  void _enterReorder() {
    FocusManager.instance.primaryFocus?.unfocus();
    _selection.clear();
    setState(() => _reordering = true);
  }

  void _leaveReorder() {
    _cancelDrag();
    setState(() => _reordering = false);
  }

  /// How close to the top or bottom edge the pointer must be to scroll, and
  /// the fastest speed, in pixels per tick.
  static const _autoScrollEdge = 56.0;
  static const _autoScrollSpeed = 16.0;
  static const _autoScrollTick = Duration(milliseconds: 16);

  void _startDrag(_Drag drag) {
    if (_drag != null) return;
    setState(() {
      _drag = drag;
      _drop = null;
    });
    _autoScrollTimer?.cancel();
    _autoScrollTimer = Timer.periodic(_autoScrollTick, (_) => _autoScroll());
  }

  void _onPointer(PointerEvent event) {
    _pointer = event.position;
    if (_drag != null) _updateDrop();
  }

  void _onPointerUp(PointerEvent event) {
    final drag = _drag;
    if (drag == null) return;
    _pointer = event.position;
    _updateDrop();
    final drop = _drop;
    _cancelDrag();
    if (drop == null) return;
    if (drag.isList) {
      _document.moveList(drag.id, drop.index);
    } else if (drop.listId case final listId?) {
      _document.moveItem(drag.id, listId, drop.index);
    }
  }

  void _cancelDrag() {
    _autoScrollTimer?.cancel();
    _autoScrollTimer = null;
    if (_drag == null) return;
    setState(() {
      _drag = null;
      _drop = null;
    });
  }

  RenderBox? get _viewportBox {
    final ro = _viewportKey.currentContext?.findRenderObject();
    return ro is RenderBox && ro.attached && ro.hasSize ? ro : null;
  }

  void _autoScroll() {
    final pointer = _pointer;
    final box = _viewportBox;
    if (pointer == null || box == null || !_scrollController.hasClients) {
      return;
    }
    final y = box.globalToLocal(pointer).dy;
    final height = box.size.height;
    final double delta;
    if (y < _autoScrollEdge) {
      delta = -_autoScrollSpeed * ((_autoScrollEdge - y) / _autoScrollEdge);
    } else if (y > height - _autoScrollEdge) {
      delta =
          _autoScrollSpeed *
          ((y - (height - _autoScrollEdge)) / _autoScrollEdge);
    } else {
      return;
    }
    final p = _scrollController.position;
    final target = (p.pixels + delta.clamp(-_autoScrollSpeed, _autoScrollSpeed))
        .clamp(p.minScrollExtent, p.maxScrollExtent);
    if (target == p.pixels) return;
    _scrollController.jumpTo(target);
    // The rows moved under the pointer once they are laid out again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _drag != null) _updateDrop();
    });
  }

  void _updateDrop() {
    final drop = _dropAtPointer();
    if (drop != _drop) setState(() => _drop = drop);
  }

  /// The drop under the pointer, or null if dropping there changes nothing.
  /// Above or below the list, the closest row is used.
  _Drop? _dropAtPointer() {
    final drag = _drag;
    final pointer = _pointer;
    final viewport = _viewportBox;
    if (drag == null || pointer == null || viewport == null) return null;
    final local = viewport.globalToLocal(pointer);
    final y = local.dy.clamp(0.0, viewport.size.height - 1);
    final at = viewport.localToGlobal(Offset(local.dx, y));
    for (final MapEntry(:key, :value) in _rowContexts.entries) {
      final ro = value.findRenderObject();
      if (ro is! RenderBox || !ro.attached || !ro.hasSize) continue;
      final rowY = ro.globalToLocal(at).dy;
      if (rowY < 0 || rowY >= ro.size.height) continue;
      final index = _rowIndex[key];
      if (index == null) return null;
      final drop = _dropOnRow(drag, _rows[index], rowY >= ro.size.height / 2);
      return drop != null && _changes(drag, drop) ? drop : null;
    }
    return _drop;
  }

  /// An item drops between items, at the top of a list (on its name) or at
  /// its end (on its total or the help). A list drops before a list (on its
  /// name) or after it (on its items or total).
  _Drop? _dropOnRow(_Drag drag, _Row row, bool lowerHalf) {
    final lists = _document.doc.lists;
    switch (row) {
      case _HeaderRow(:final list, :final pos):
        return drag.isList
            ? (listId: null, index: pos.list, rowKey: row.key, below: false)
            : (listId: list.id, index: 0, rowKey: row.key, below: true);
      case _ItemRow(:final list, :final pos):
        if (drag.isList) return _afterList(pos.list);
        return (
          listId: list.id,
          index: pos.item + (lowerHalf ? 1 : 0),
          rowKey: row.key,
          below: lowerHalf,
        );
      case _FooterRow(:final list, :final pos):
        if (drag.isList) return _afterList(pos.list);
        return (
          listId: list.id,
          index: list.items.length,
          rowKey: row.key,
          below: false,
        );
      case _HelpRow():
        if (lists.isEmpty) return null;
        return drag.isList
            ? (listId: null, index: lists.length, rowKey: row.key, below: false)
            : (
                listId: lists.last.id,
                index: lists.last.items.length,
                rowKey: row.key,
                below: false,
              );
    }
  }

  /// After list [l]: the indicator is under its last row.
  _Drop? _afterList(int l) {
    final lists = _document.doc.lists;
    if (l >= lists.length) return null;
    final next = l + 1 < lists.length ? _listKey(lists[l + 1].id) : 'help';
    final nextIndex = _rowIndex[next];
    if (nextIndex == null || nextIndex == 0) return null;
    return (
      listId: null,
      index: l + 1,
      rowKey: _rows[nextIndex - 1].key,
      below: true,
    );
  }

  /// Whether dropping [drag] at [drop] moves anything.
  bool _changes(_Drag drag, _Drop drop) {
    final doc = _document.doc;
    if (drag.isList) {
      final from = doc.listIndexOf(drag.id);
      return from >= 0 && drop.index != from && drop.index != from + 1;
    }
    final from = doc.locate(drag.id);
    if (from == null) return false;
    if (doc.lists[from.listIndex].id != drop.listId) return true;
    return drop.index != from.itemIndex && drop.index != from.itemIndex + 1;
  }

  /// Whether [row] is, or belongs to, what is being dragged.
  bool _isDragged(_Row row) {
    final drag = _drag;
    if (drag == null) return false;
    if (!drag.isList) return row.key == drag.id;
    return switch (row) {
      _HeaderRow(:final list) ||
      _ItemRow(:final list) ||
      _FooterRow(:final list) => list.id == drag.id,
      _HelpRow() => false,
    };
  }

  /// The handle shown in place of + and ⋯, and the long press on the whole
  /// row, both of which start dragging [drag].
  ({Widget handle, Widget Function(Widget row) wrap}) _dragControls(
    _Row row,
    _Drag drag,
  ) {
    final feedback = Builder(
      builder: (context) => _DragFeedback(
        width: MediaQuery.sizeOf(context).width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: ItemRow.edgePadding),
          child: _feedbackContent(row),
        ),
      ),
    );
    // Keeps the floating row where the row was, under the finger.
    Offset anchor(Draggable<Object> d, BuildContext context, Offset position) {
      final ro = _rowContexts[row.key]?.findRenderObject();
      return ro is RenderBox ? ro.globalToLocal(position) : Offset.zero;
    }

    final handle = Draggable<_Drag>(
      data: drag,
      feedback: feedback,
      dragAnchorStrategy: anchor,
      onDragStarted: () => _startDrag(drag),
      // The size of the + button and the ⋯ menu.
      child: RowMetrics.of(context).iconBox(
        Icon(
          Icons.drag_handle,
          semanticLabel: drag.isList ? 'Move list' : 'Move item',
        ),
      ),
    );
    Widget wrap(Widget child) => LongPressDraggable<_Drag>(
      data: drag,
      feedback: feedback,
      dragAnchorStrategy: anchor,
      onDragStarted: () => _startDrag(drag),
      child: child,
    );
    return (handle: handle, wrap: wrap);
  }

  Widget _feedbackContent(_Row row) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge!;
    final metrics = RowMetrics.of(context);
    switch (row) {
      case _ItemRow(:final item):
        final states = StateColors.of(context);
        return Row(
          children: [
            metrics.iconBox(
              IconTheme.merge(
                data: IconThemeData(
                  color: switch (item.state) {
                    ItemState.newItem => null,
                    ItemState.done => states.done,
                    ItemState.failed => states.failed,
                  },
                ),
                child: ItemRow.iconFor(item.state),
              ),
            ),
            Expanded(
              child: Text(
                item.text.isEmpty ? ItemRow.placeholder : item.text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: item.text.isEmpty
                    ? base.copyWith(color: theme.hintColor)
                    : base,
              ),
            ),
            metrics.iconBox(const Icon(Icons.drag_handle)),
          ],
        );
      case _HeaderRow(:final list):
        return Padding(
          padding: const EdgeInsets.only(left: 16 - ItemRow.edgePadding),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  list.name.isEmpty ? ListHeader.placeholder : list.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: base.copyWith(
                    fontWeight: FontWeight.bold,
                    color: list.name.isEmpty ? theme.hintColor : null,
                  ),
                ),
              ),
              Text(
                _countItems(list.items.length),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              metrics.iconBox(const Icon(Icons.drag_handle)),
            ],
          ),
        );
      case _FooterRow() || _HelpRow():
        return const SizedBox.shrink();
    }
  }

  // -------------------------------------------------------------------------
  // Build

  @override
  Widget build(BuildContext context) {
    // Read here, above the Scaffold, which takes the keyboard's height out
    // of its body's MediaQuery.
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return PopScope(
      // Back leaves selection, reorder or editing mode instead of the app.
      canPop: !_selection.active && !_reordering && !_editing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_reordering) {
          _leaveReorder();
        } else if (_editing) {
          _endEditing();
        } else {
          _selection.clear();
        }
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        bottomNavigationBar: const NavigationBarBacking(),
        // Hidden in the other modes, and above the keyboard, where it
        // would cover the rows being edited.
        floatingActionButton: _selection.active || _reordering || keyboardOpen
            ? null
            : _buildModeButton(),
        body: NotificationListener<ScrollEndNotification>(
          onNotification: (_) {
            _scheduleAnchorSave();
            return false;
          },
          child: Listener(
            onPointerDown: _onPointer,
            onPointerMove: _onPointer,
            onPointerUp: _onPointerUp,
            onPointerCancel: (_) => _cancelDrag(),
            child: SuperListView.builder(
              key: _viewportKey,
              listController: _listController,
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              padding: const EdgeInsets.only(bottom: _modeButtonRoom),
              itemCount: _rows.length,
              findChildIndexCallback: (key) =>
                  key is ValueKey<String> ? _rowIndex[key.value] : null,
              itemBuilder: (context, index) {
                final row = _rows[index];
                final drop = _drop;
                final scheme = Theme.of(context).colorScheme;
                final line = BorderSide(color: scheme.primary, width: 3);
                return _TrackedRow(
                  key: ValueKey(row.key),
                  rowKey: row.key,
                  contexts: _rowContexts,
                  // Always wrapped, so a drag never rebuilds the row's fields.
                  child: DecoratedBox(
                    position: DecorationPosition.foreground,
                    decoration: drop == null || drop.rowKey != row.key
                        ? const BoxDecoration()
                        : BoxDecoration(
                            border: drop.below
                                ? Border(bottom: line)
                                : Border(top: line),
                          ),
                    child: Opacity(
                      opacity: _isDragged(row) ? 0.4 : 1,
                      child: _buildRow(row),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(_Row row) {
    switch (row) {
      case _HeaderRow(:final list):
        final f = _names[list.id]!;
        final drag = _reordering
            ? _dragControls(row, (id: list.id, isList: true))
            : null;
        final header = ListHeader(
          controller: f.controller,
          focusNode: f.focusNode,
          onSubmitted: () => _focusFirstItem(list),
          viewMode: _viewing,
          onAction: (action) {
            _endEditing();
            _onListAction(list, action);
          },
          dragHandle: drag?.handle,
        );
        return drag?.wrap(header) ?? header;
      case _ItemRow(:final item):
        final f = _items[item.id]!;
        final selecting = _selection.active;
        final drag = _reordering
            ? _dragControls(row, (id: item.id, isList: false))
            : null;
        final itemRow = ItemRow(
          item: item,
          controller: f.controller,
          focusNode: f.focusNode,
          onCycleState: () {
            _endEditing();
            _document.cycleState(item.id);
          },
          onIncrement: selecting || _reordering
              ? null
              : () => _document.incrementQuantity(item.id),
          onLongPressIcon: _reordering || _viewing
              ? null
              : () => _enterSelection(item.id),
          viewMode: _viewing,
          selectionMode: selecting,
          selected: _selection.contains(item.id),
          onToggleSelection: () => _selection.toggle(item.id),
          dragHandle: drag?.handle,
        );
        return drag?.wrap(itemRow) ?? itemRow;
      case _FooterRow(:final total):
        return ListFooter(total: total);
      case _HelpRow():
        return UsageHelp(
          initiallyExpanded: _helpExpanded,
          viewMode: _viewing,
          onExpandedChanged: (expanded) {
            _helpExpanded = expanded;
            widget.onHelpExpandedChanged?.call(expanded);
          },
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

/// The row floating under the finger while it is dragged.
class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 6,
      color: scheme.surfaceContainerHigh,
      child: SizedBox(width: width, child: child),
    );
  }
}

String _countItems(int n) => '$n ${n == 1 ? 'item' : 'items'}';
