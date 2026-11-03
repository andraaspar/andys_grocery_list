import 'package:flutter/material.dart';

import 'item_row.dart';
import 'theme.dart';

/// Entries of the `⋯` menu (plan §4).
enum ListAction { reset, copy, deleteDone, delete }

/// The list name, edited inline, and the `⋯` menu (plan §4).
class ListHeader extends StatelessWidget {
  const ListHeader({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    required this.onAction,
    this.dragHandle,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final ValueChanged<ListAction> onAction;

  /// In reorder mode, shown in place of the `⋯` menu; the name can't be
  /// edited.
  final Widget? dragHandle;

  /// Shown in an unnamed list.
  static const placeholder = 'Your brand new list';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A Material, not a plain colour, so the menu button's ripple shows.
    return Material(
      color: ListColors.of(context).header,
      child: Padding(
        // The ⋯ menu lines up with the items' + buttons. The grey band is as
        // high above the name as below it.
        padding: const EdgeInsets.fromLTRB(16, 2, ItemRow.edgePadding, 2),
        child: Row(
          children: [
            Expanded(
              child: IgnorePointer(
                ignoring: dragHandle != null,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  readOnly: dragHandle != null,
                  maxLines: 1,
                  textInputAction: TextInputAction.next,
                  // Same size as the items, bold.
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  // Greyed like the items' placeholder, so it doesn't read as
                  // a real name.
                  decoration: InputDecoration.collapsed(
                    hintText: placeholder,
                    hintStyle: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.hintColor,
                    ),
                  ),
                  onChanged: onChanged,
                  // Overrides the default "next" behaviour: focus goes to the
                  // start of this list's first item instead.
                  onEditingComplete: onSubmitted,
                ),
              ),
            ),
            if (dragHandle case final handle?)
              handle
            else
              PopupMenuButton<ListAction>(
                icon: const Icon(Icons.more_horiz),
                // Same height as an item row.
                style: IconButton.styleFrom(
                  visualDensity: const VisualDensity(
                    horizontal: -2,
                    vertical: -4,
                  ),
                ),
                tooltip: 'List actions',
                onSelected: onAction,
                itemBuilder: (context) => const [
                  PopupMenuItem(value: ListAction.reset, child: Text('Reset')),
                  PopupMenuItem(
                    value: ListAction.copy,
                    child: Text('Copy list'),
                  ),
                  PopupMenuItem(
                    value: ListAction.deleteDone,
                    child: Text('Delete done'),
                  ),
                  PopupMenuItem(
                    value: ListAction.delete,
                    child: Text('Delete list'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
