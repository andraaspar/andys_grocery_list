import 'package:flutter/material.dart';

import 'display_options.dart';
import 'item_row.dart';
import 'sentinel_controller.dart';
import 'theme.dart';

/// Entries of the `⋯` menu (plan §4).
enum ListAction { reset, copy, deleteDone, delete }

/// The list name, edited inline, and the `⋯` menu (plan §4).
class ListHeader extends StatelessWidget {
  const ListHeader({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onAction,
    this.dragHandle,
    this.viewMode = false,
  });

  /// Its callbacks rename the list, and handle Backspace in an empty name.
  final SentinelController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmitted;
  final ValueChanged<ListAction> onAction;

  /// In reorder mode, shown in place of the `⋯` menu; the name can't be
  /// edited.
  final Widget? dragHandle;

  /// View mode: the name can't be edited, and the menu is hidden.
  final bool viewMode;

  bool get _locked => dragHandle != null || viewMode;

  /// Shown in an unnamed list.
  static const placeholder = 'Your brand new list';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final metrics = RowMetrics.of(context);
    final style = theme.textTheme.bodyLarge?.copyWith(
      fontWeight: FontWeight.bold,
    );
    // A Material, not a plain colour, so the menu button's ripple shows.
    return Material(
      color: ListColors.of(context).header,
      child: Padding(
        // The ⋯ menu lines up with the items' + buttons. The grey band is as
        // high above the name as below it.
        padding: EdgeInsets.fromLTRB(
          16,
          metrics.headerPadding,
          ItemRow.edgePadding,
          metrics.headerPadding,
        ),
        child: Row(
          children: [
            Expanded(
              child: IgnorePointer(
                ignoring: _locked,
                child: Stack(
                  children: [
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      readOnly: _locked,
                      maxLines: 1,
                      textInputAction: TextInputAction.next,
                      // Same size as the items, bold.
                      style: style,
                      decoration: const InputDecoration.collapsed(hintText: ''),
                      // Overrides the default "next" behaviour: focus goes to
                      // the start of this list's first item instead.
                      onEditingComplete: onSubmitted,
                    ),
                    // The field's own hint never shows: its text always holds
                    // the invisible sentinel. Greyed like the items'
                    // placeholder, so it doesn't read as a real name.
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) => controller.modelText.isEmpty
                          ? IgnorePointer(
                              child: Text(
                                placeholder,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: style?.copyWith(color: theme.hintColor),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
            if (dragHandle case final handle?)
              handle
            else if (viewMode)
              // Hidden, keeping its room, so the row keeps its height.
              Visibility.maintain(
                visible: false,
                child: IconButton(
                  icon: const Icon(Icons.more_horiz),
                  iconSize: metrics.iconSize,
                  padding: EdgeInsets.zero,
                  style: metrics.buttonStyle,
                  onPressed: null,
                ),
              )
            else
              PopupMenuButton<ListAction>(
                icon: const Icon(Icons.more_horiz),
                // Same size as the items' buttons.
                iconSize: metrics.iconSize,
                padding: EdgeInsets.zero,
                style: metrics.buttonStyle,
                tooltip: 'List actions',
                onSelected: onAction,
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: ListAction.reset,
                    child: Text('Reset'),
                  ),
                  const PopupMenuItem(
                    value: ListAction.copy,
                    child: Text('Copy list'),
                  ),
                  const PopupMenuItem(
                    value: ListAction.deleteDone,
                    child: Text('Delete done'),
                  ),
                  const PopupMenuItem(
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
