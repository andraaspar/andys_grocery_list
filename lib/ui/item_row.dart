import 'package:flutter/material.dart';

import '../model/todo_document.dart';
import 'sentinel_controller.dart';

/// One item: state icon + wrapping text field (plan §3).
///
/// The + button and quantity/price highlighting arrive in milestone 4.
class ItemRow extends StatelessWidget {
  const ItemRow({
    super.key,
    required this.item,
    required this.controller,
    required this.focusNode,
    required this.onCycleState,
  });

  final TodoItem item;
  final SentinelController controller;
  final FocusNode focusNode;
  final VoidCallback onCycleState;

  static IconData iconFor(ItemState state) => switch (state) {
    ItemState.newItem => Icons.check_box_outline_blank,
    ItemState.done => Icons.check_box,
    ItemState.failed => Icons.disabled_by_default_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IconButton(
          icon: Icon(iconFor(item.state)),
          color: item.state == ItemState.failed
              ? theme.colorScheme.error
              : null,
          tooltip: switch (item.state) {
            ItemState.newItem => 'New',
            ItemState.done => 'Done',
            ItemState.failed => 'Failed',
          },
          onPressed: onCycleState,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 12, right: 16),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              maxLines: null,
              style: style,
              decoration: const InputDecoration.collapsed(hintText: ''),
            ),
          ),
        ),
      ],
    );
  }
}
