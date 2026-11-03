import 'package:flutter/material.dart';

/// The list name, edited inline (plan §4).
///
/// The `⋯` menu arrives in milestone 5.
class ListHeader extends StatelessWidget {
  const ListHeader({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        maxLines: 1,
        textInputAction: TextInputAction.next,
        style: theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
        decoration: const InputDecoration.collapsed(hintText: 'List name'),
        onChanged: onChanged,
        // Overrides the default "next" behaviour: focus goes to the start of
        // this list's first item instead.
        onEditingComplete: onSubmitted,
      ),
    );
  }
}
