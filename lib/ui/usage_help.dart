import 'package:flutter/material.dart';

import '../model/todo_document.dart';
import 'item_row.dart';
import 'theme.dart';

/// Short instructions shown below the last list, behind a centred
/// "How to use" button that expands and collapses them.
class UsageHelp extends StatefulWidget {
  const UsageHelp({
    super.key,
    this.initiallyExpanded = true,
    this.onExpandedChanged,
    this.viewMode = false,
  });

  /// View mode gets fewer tips: only what can be done in it, and how to
  /// leave it.
  final bool viewMode;

  final bool initiallyExpanded;
  final ValueChanged<bool>? onExpandedChanged;

  @override
  State<UsageHelp> createState() => _UsageHelpState();
}

class _UsageHelpState extends State<UsageHelp> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onExpandedChanged?.call(_expanded);
  }

  static const _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.bodyMedium!.copyWith(color: color);
    final states = StateColors.of(context);

    // A state icon inside a line of text.
    InlineSpan stateIcon(ItemState state, Color? color) => WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: IconTheme.merge(
        data: IconThemeData(size: 18, color: color ?? style.color),
        child: ItemRow.iconFor(state),
      ),
    );

    Widget tip(IconData icon, InlineSpan text) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text.rich(text, style: style)),
        ],
      ),
    );

    // The states in order, after [lead] and before [tail].
    InlineSpan cycle(String lead, String tail) => TextSpan(
      children: [
        TextSpan(text: lead),
        stateIcon(ItemState.newItem, null),
        const TextSpan(text: ' new → '),
        stateIcon(ItemState.done, states.done),
        const TextSpan(text: ' done → '),
        stateIcon(ItemState.failed, states.failed),
        TextSpan(text: tail),
      ],
    );

    final viewTips = [
      tip(Icons.touch_app_outlined, cycle('Tap an item: ', ' failed.')),
      tip(
        Icons.lock_open,
        const TextSpan(
          text:
              'View mode keeps the lists safe from changes. Tap the lock at '
              'the bottom right to edit them again.',
        ),
      ),
    ];

    final tips = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: widget.viewMode
            ? viewTips
            : [
                tip(
                  Icons.touch_app_outlined,
                  cycle(
                    'Tap a box: ',
                    ' failed. Long-press an item to select it.',
                  ),
                ),
                tip(
                  Icons.keyboard_return,
                  const TextSpan(
                    text:
                        'Enter adds an item. Enter on an empty item starts a new '
                        'list.',
                  ),
                ),
                tip(
                  Icons.backspace_outlined,
                  const TextSpan(
                    text:
                        'Backspace at the start of an item joins it to the one '
                        'above, or the list to the list above. In an empty '
                        'list name, it joins the list up, or removes it if it '
                        'has no items.',
                  ),
                ),
                tip(
                  Icons.add,
                  const TextSpan(text: 'Counts up: Milk → 2x Milk.'),
                ),
                tip(
                  Icons.sell_outlined,
                  const TextSpan(
                    text:
                        'End an item with a price, like Milk 1.29. Done items add '
                        'up to the total.',
                  ),
                ),
                tip(
                  Icons.content_paste,
                  const TextSpan(
                    text: 'Paste several lines to add many items at once.',
                  ),
                ),
                tip(
                  Icons.swap_vert,
                  const TextSpan(
                    text:
                        'Tap ⇅ at the top to move items and lists: drag the ≡ '
                        'handle, or long-press a row.',
                  ),
                ),
                tip(
                  Icons.lock_outline,
                  const TextSpan(
                    text:
                        'The lock at the bottom right switches to view mode: '
                        'tap anywhere on an item to change its state, and nothing '
                        'gets edited or deleted by accident.',
                  ),
                ),
                tip(
                  Icons.more_horiz,
                  const TextSpan(
                    text:
                        'Next to a list name: reset, copy or delete the list.',
                  ),
                ),
              ],
      ),
    );

    // A grey band like the list names, set apart from the last list. A
    // Material, so the button's ripple shows on it.
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Material(
        color: ListColors.of(context).header,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            children: [
              TextButton.icon(
                onPressed: _toggle,
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                label: const Text('How to use'),
              ),
              AnimatedSize(
                duration: _duration,
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? tips
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
