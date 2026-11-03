import 'package:flutter/material.dart';

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
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final ValueChanged<ListAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              maxLines: 1,
              textInputAction: TextInputAction.next,
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
              decoration: const InputDecoration.collapsed(
                hintText: 'List name',
              ),
              onChanged: onChanged,
              // Overrides the default "next" behaviour: focus goes to the
              // start of this list's first item instead.
              onEditingComplete: onSubmitted,
            ),
          ),
          PopupMenuButton<ListAction>(
            icon: const Icon(Icons.more_horiz),
            tooltip: 'List actions',
            onSelected: onAction,
            itemBuilder: (context) => const [
              PopupMenuItem(value: ListAction.reset, child: Text('Reset')),
              PopupMenuItem(value: ListAction.copy, child: Text('Copy list')),
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
    );
  }
}
