import 'package:flutter/material.dart';

import '../model/todo_document.dart';

/// Asks before deleting [n] selected items (plan §6). Returns true to delete.
Future<bool> confirmDeleteItems(BuildContext context, int n) =>
    _confirm(context, 'Delete $n selected items?');

/// Asks before deleting [list] (plan §4). Returns true to delete.
Future<bool> confirmDeleteList(BuildContext context, TodoList list) async {
  final n = list.items.where((i) => i.text.isNotEmpty).length;
  final name = list.name.isEmpty ? 'this list' : 'list "${list.name}"';
  final question = n == 0
      ? 'Delete $name?'
      : 'Delete $name and its $n ${n == 1 ? 'item' : 'items'}?';
  return _confirm(context, question);
}

Future<bool> _confirm(BuildContext context, String question) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      return AlertDialog(
        // Even room around the question, and buttons close to the edges.
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        content: Text(question, style: theme.textTheme.bodyLarge),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );
  return ok ?? false;
}
