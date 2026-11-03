import 'package:flutter/material.dart';

/// The total line after a list's last item (plan §4).
///
/// Always one line high, with tabular figures, so a changing value never
/// moves the layout.
class ListFooter extends StatelessWidget {
  const ListFooter({super.key, required this.total});

  /// The formatted total.
  final String total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyLarge!.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Text(
        'Total: $total',
        style: style,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        textAlign: TextAlign.end,
        // Fixes the line height so the footer's height never changes.
        strutStyle: StrutStyle.fromTextStyle(style, forceStrutHeight: true),
      ),
    );
  }
}
