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
  });

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
    if (_expanded) {
      // The tips open below the button, at the end of the page: bring them
      // into view once they have grown.
      Future.delayed(_duration, () {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      });
    }
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

    final tips = Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          tip(
            Icons.touch_app_outlined,
            TextSpan(
              children: [
                const TextSpan(text: 'Tap a box: '),
                stateIcon(ItemState.newItem, null),
                const TextSpan(text: ' new → '),
                stateIcon(ItemState.done, states.done),
                const TextSpan(text: ' done → '),
                stateIcon(ItemState.failed, states.failed),
                const TextSpan(text: ' failed. Long-press it to select items.'),
              ],
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
                  'above, or the list to the list above.',
            ),
          ),
          tip(Icons.add, const TextSpan(text: '+ counts up: Milk → 2x Milk.')),
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
            Icons.more_horiz,
            const TextSpan(
              text: 'Next to a list name: reset, copy or delete the list.',
            ),
          ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
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
            child: _expanded ? tips : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
