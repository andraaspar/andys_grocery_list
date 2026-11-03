import 'package:flutter/material.dart';

import '../model/todo_document.dart';

/// Asks before deleting [list] (plan §4). Returns true to delete.
Future<bool> confirmDeleteList(BuildContext context, TodoList list) async {
  final n = list.items.where((i) => i.text.isNotEmpty).length;
  final name = list.name.isEmpty ? 'this list' : 'list "${list.name}"';
  final question = n == 0
      ? 'Delete $name?'
      : 'Delete $name and its $n ${n == 1 ? 'item' : 'items'}?';
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      content: Text(question),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
