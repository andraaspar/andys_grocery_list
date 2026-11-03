import 'package:flutter/material.dart';

import '../model/todo_document.dart';
import 'display_options.dart';
import 'failed_box_icon.dart';
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
    this.dragHandle,
  });

  final TodoItem item;
  final SentinelController controller;
  final FocusNode focusNode;
  final VoidCallback onCycleState;

  /// The + button. Hidden when null (reorder mode).
  final VoidCallback? onIncrement;

  /// Long-pressing the state icon or the + button enters selection mode
  /// (§6).
  final VoidCallback? onLongPressIcon;

  /// In selection mode the text can't be edited, and tapping the icon or the
  /// row calls [onToggleSelection] instead of changing the state.
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onToggleSelection;

  /// In reorder mode, shown in place of the + button; the text can't be
  /// edited.
  final Widget? dragHandle;

  bool get _locked => selectionMode || dragHandle != null;

  /// Space at both ends of a row. The icon buttons are 8 px wider than their
  /// icons on each side, so with this the icons are 16 px from the screen
  /// edges, in line with the list names and the app title.
  static const edgePadding = 8.0;

  /// Shown in an empty item.
  static const placeholder = 'Something';

  static Widget iconFor(ItemState state) => switch (state) {
    ItemState.newItem => const Icon(Icons.check_box_outline_blank),
    ItemState.done => const Icon(Icons.check_box),
    ItemState.failed => const FailedBoxIcon(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final states = StateColors.of(context);
    final metrics = RowMetrics.of(context);
    final base = theme.textTheme.bodyLarge!;
    // DONE is struck through; the text keeps its colour (no gray text).
    final style = item.state == ItemState.done
        ? base.copyWith(decoration: TextDecoration.lineThrough)
        : base;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          style: metrics.buttonStyle,
          icon: iconFor(item.state),
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
              top: metrics.textPadding,
              bottom: metrics.textPadding,
              // Selection mode puts a check mark in the place of +, so the
              // text keeps its width and doesn't rewrap.
              right: onIncrement == null && dragHandle == null && !selectionMode
                  ? 8
                  : 0,
            ),
            // Always wrapped, so toggling selection or reorder mode keeps the
            // field's state.
            child: IgnorePointer(
              ignoring: _locked,
              child: Stack(
                children: [
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    readOnly: _locked,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    maxLines: null,
                    style: style,
                    decoration: const InputDecoration.collapsed(hintText: ''),
                  ),
                  // The field's own hint never shows: its text always holds
                  // the invisible sentinel.
                  ListenableBuilder(
                    listenable: controller,
                    builder: (context, _) => controller.modelText.isEmpty
                        ? IgnorePointer(
                            child: Text(
                              placeholder,
                              style: base.copyWith(color: theme.hintColor),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (dragHandle case final handle?)
          handle
        else if (selectionMode)
          IconButton(
            style: metrics.buttonStyle,
            icon: Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
            ),
            color: selected ? theme.colorScheme.primary : null,
            tooltip: selected ? 'Deselect' : 'Select',
            onPressed: onToggleSelection,
          )
        else if (onIncrement != null)
          IconButton(
            style: metrics.buttonStyle,
            icon: const Icon(Icons.add),
            tooltip: 'Add one',
            onPressed: onIncrement,
            onLongPress: onLongPressIcon,
          ),
      ],
    );

    return Material(
      color: selected
          ? theme.colorScheme.secondaryContainer
          : Colors.transparent,
      child: InkWell(
        onTap: selectionMode ? onToggleSelection : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: edgePadding),
          child: row,
        ),
      ),
    );
  }
}
