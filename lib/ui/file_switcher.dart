import 'package:flutter/material.dart';

import 'snackbars.dart';

/// What happened when the user tried to change the file.
typedef FileChange = ({bool changed, String? error});

/// A file opened before, and its name.
typedef RecentFile = ({String uri, String name});

/// What was picked in the Change file sheet.
sealed class _FileChoice {
  const _FileChoice();
}

class _OpenFile extends _FileChoice {
  const _OpenFile();
}

class _CreateFile extends _FileChoice {
  const _CreateFile();
}

class _RecentChoice extends _FileChoice {
  const _RecentChoice(this.uri);
  final String uri;
}

/// What the file switcher can do. The callbacks open the chosen file and
/// make it the current one.
class FileActions {
  const FileActions({
    required this.openFile,
    required this.createFile,
    this.recentFiles,
    this.openRecentFile,
    this.removeRecentFile,
  });

  /// Pick an existing file / create a new one, and switch to it.
  final Future<FileChange> Function() openFile;
  final Future<FileChange> Function() createFile;

  /// The files opened before, other than the current one, that still exist.
  final Future<List<RecentFile>> Function()? recentFiles;
  final Future<FileChange> Function(String uri)? openRecentFile;
  final Future<void> Function(String uri)? removeRecentFile;
}

/// Shows the file switcher: open, create, or one of the recent files.
/// Errors are shown in a snackbar. Returns whether another file was opened.
Future<bool> showFileSwitcher(BuildContext context, FileActions files) async {
  final recent = await files.recentFiles?.call() ?? const <RecentFile>[];
  if (!context.mounted) return false;
  final choice = await showModalBottomSheet<_FileChoice>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => _ChangeFileSheet(
      recent: recent,
      onRemove: (uri) => files.removeRecentFile?.call(uri),
    ),
  );
  if (choice == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final result = await switch (choice) {
    _OpenFile() => files.openFile(),
    _CreateFile() => files.createFile(),
    _RecentChoice(:final uri) => files.openRecentFile!(uri),
  };
  if (result.error != null) showMessage(messenger, result.error!);
  return result.changed;
}

/// A readable name for a SAF URI: its decoded last path segment, without
/// the storage volume prefix (`primary:Sync/todo.md` → `todo.md`).
String fileDisplayName(String uri) {
  final parsed = Uri.tryParse(uri);
  var name = parsed != null && parsed.pathSegments.isNotEmpty
      ? parsed.pathSegments.last
      : uri;
  try {
    name = Uri.decodeComponent(name);
  } on ArgumentError {
    // Keep it as is.
  }
  final cut = name.lastIndexOf(RegExp('[/:]'));
  return cut < 0 || cut == name.length - 1 ? name : name.substring(cut + 1);
}

/// Open, create, or one of the recent files, which can be removed.
class _ChangeFileSheet extends StatefulWidget {
  const _ChangeFileSheet({required this.recent, required this.onRemove});

  final List<RecentFile> recent;
  final void Function(String uri) onRemove;

  @override
  State<_ChangeFileSheet> createState() => _ChangeFileSheetState();
}

class _ChangeFileSheetState extends State<_ChangeFileSheet> {
  late final _recent = [...widget.recent];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        // Long recent lists scroll instead of covering the whole screen.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('Open existing file'),
              onTap: () => Navigator.pop(context, const _OpenFile()),
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Create new file'),
              onTap: () => Navigator.pop(context, const _CreateFile()),
            ),
            if (_recent.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Recent files', style: theme.textTheme.titleSmall),
              ),
              for (final file in _recent)
                ListTile(
                  key: ValueKey(file.uri),
                  leading: const Icon(Icons.history),
                  title: Text(file.name),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove from recent files',
                    onPressed: () {
                      setState(() => _recent.remove(file));
                      widget.onRemove(file.uri);
                    },
                  ),
                  onTap: () => Navigator.pop(context, _RecentChoice(file.uri)),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
