import 'package:flutter/material.dart';

import '../model/todo_document.dart';
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

  /// The tightest vertical density makes the row 32 px high: one 24 px text
  /// line with [textPadding] above and below.
  static const rowDensity = VisualDensity(horizontal: -2, vertical: -4);
  static const textPadding = 4.0;

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
    final base = theme.textTheme.bodyLarge!;
    // DONE is struck through; the text keeps its colour (no gray text).
    final style = item.state == ItemState.done
        ? base.copyWith(decoration: TextDecoration.lineThrough)
        : base;

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          visualDensity: rowDensity,
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
              top: textPadding,
              bottom: textPadding,
              right: onIncrement == null ? 16 : 0,
            ),
            // Always wrapped, so toggling selection mode keeps the field's
            // state.
            child: IgnorePointer(
              ignoring: selectionMode,
              child: Stack(
                children: [
                  TextField(
                    controller: controller,
                    focusNode: focusNode,
                    readOnly: selectionMode,
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
        if (onIncrement != null)
          IconButton(
            visualDensity: rowDensity,
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
