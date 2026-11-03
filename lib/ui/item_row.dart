import 'package:flutter/material.dart';

import '../model/todo_document.dart';
import 'sentinel_controller.dart';
import 'theme.dart';

/// One item: state icon + wrapping text field + quantity button (plan §3).
class ItemRow extends StatelessWidget {
  const ItemRow({
    super.key,
    required this.item,
    required this.controller,
    required this.focusNode,
    required this.onCycleState,
    required this.onIncrement,
    this.onLongPressIcon,
    this.selectionMode = false,
    this.selected = false,
    this.onToggleSelection,
  });

  final TodoItem item;
  final SentinelController controller;
  final FocusNode focusNode;
  final VoidCallback onCycleState;

  /// The + button. Hidden when null (selection mode, §6).
  final VoidCallback? onIncrement;

  /// Long-pressing the state icon enters selection mode (§6).
  final VoidCallback? onLongPressIcon;

  /// In selection mode the text can't be edited, and tapping the icon or the
  /// row calls [onToggleSelection] instead of changing the state.
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelection;

  static IconData iconFor(ItemState state) => switch (state) {
    ItemState.newItem => Icons.check_box_outline_blank,
    ItemState.done => Icons.check_box,
    ItemState.failed => Icons.disabled_by_default_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final states = StateColors.of(context);
    final base = theme.textTheme.bodyLarge!;
    final muted = item.state != ItemState.newItem;
    final style = muted
        ? base.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            decoration: item.state == ItemState.done
                ? TextDecoration.lineThrough
                : null,
            decorationColor: theme.colorScheme.onSurfaceVariant,
          )
        : base;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          icon: Icon(iconFor(item.state)),
          // Coloured like the launcher icon's tiles; NEW stays neutral.
          color: switch (item.state) {
            ItemState.newItem => null,
            ItemState.done => states.done,
            ItemState.failed => states.failed,
          },
          tooltip: switch (item.state) {
            ItemState.newItem => 'New',
            ItemState.done => 'Done',
            ItemState.failed => 'Failed',
          },
          onPressed: selectionMode ? onToggleSelection : onCycleState,
          onLongPress: selectionMode ? null : onLongPressIcon,
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top: 12,
              bottom: 12,
              right: onIncrement == null ? 16 : 0,
            ),
            // Always wrapped, so toggling selection mode keeps the field's
            // state.
            child: IgnorePointer(
              ignoring: selectionMode,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                readOnly: selectionMode,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                maxLines: null,
                style: style,
                decoration: const InputDecoration.collapsed(hintText: ''),
              ),
            ),
          ),
        ),
        if (onIncrement != null)
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add one',
            onPressed: onIncrement,
          ),
      ],
    );

    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: selectionMode ? onToggleSelection : null,
        child: row,
      ),
    );
  }
}
