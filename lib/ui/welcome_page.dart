import 'package:flutter/material.dart';

import '../app_name.dart';
import 'tiles_logo.dart';

/// Shown on first launch, or when the file can no longer be opened (plan §8).
class WelcomePage extends StatefulWidget {
  const WelcomePage({
    super.key,
    required this.onOpen,
    required this.onCreate,
    this.error,
  });

  /// Pick an existing file / create a new one. They complete once the
  /// picker closes.
  final Future<void> Function() onOpen;
  final Future<void> Function() onCreate;

  /// Why the previous file could not be opened, if it could not.
  final String? error;

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: TilesLogo()),
                  const SizedBox(height: 16),
                  Text(
                    appName(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your lists are kept in one Markdown file. Put it in a '
                    'synced folder to share it between devices.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (widget.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      widget.error!,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _run(widget.onOpen),
                    icon: const Icon(Icons.file_open_outlined),
                    label: const Text('Open existing file'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _run(widget.onCreate),
                    icon: const Icon(Icons.note_add_outlined),
                    label: const Text('Create new file'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
