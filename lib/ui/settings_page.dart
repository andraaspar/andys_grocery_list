import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../model/amounts.dart';
import '../model/locale_names.dart';
import '../state/settings_controller.dart';
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

/// Settings (plan §7): change file, and the locale used for numbers.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.fileUri,
    required this.onOpenFile,
    required this.onCreateFile,
    this.recentFiles,
    this.onOpenRecentFile,
    this.onRemoveRecentFile,
  });

  final SettingsController settings;

  /// The current file's URI.
  final String? fileUri;

  /// Pick an existing file / create a new one, and switch to it.
  final Future<FileChange> Function() onOpenFile;
  final Future<FileChange> Function() onCreateFile;

  /// The files opened before, other than the current one, that still exist.
  final Future<List<RecentFile>> Function()? recentFiles;
  final Future<FileChange> Function(String uri)? onOpenRecentFile;
  final Future<void> Function(String uri)? onRemoveRecentFile;

  Future<void> _changeFile(BuildContext context) async {
    final recent = await recentFiles?.call() ?? const <RecentFile>[];
    if (!context.mounted) return;
    final choice = await showModalBottomSheet<_FileChoice>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _ChangeFileSheet(
        recent: recent,
        onRemove: (uri) => onRemoveRecentFile?.call(uri),
      ),
    );
    if (choice == null || !context.mounted) return;
    final result = await switch (choice) {
      _OpenFile() => onOpenFile(),
      _CreateFile() => onCreateFile(),
      _RecentChoice(:final uri) => onOpenRecentFile!(uri),
    };
    if (!context.mounted) return;
    if (result.error != null) {
      showMessage(ScaffoldMessenger.maybeOf(context), result.error!);
    } else if (result.changed) {
      Navigator.pop(context);
    }
  }

  Future<void> _pickLocale(BuildContext context) async {
    final picked = await Navigator.push<_LocaleChoice>(
      context,
      MaterialPageRoute(
        builder: (_) => LocalePickerPage(
          current: settings.localeOverride,
          systemLocale: settings.systemLocale,
        ),
      ),
    );
    if (picked != null) await settings.setLocaleOverride(picked.locale);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final override = settings.localeOverride;
          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('File'),
                subtitle: Text(
                  fileUri == null ? 'No file' : fileDisplayName(fileUri!),
                ),
                trailing: TextButton(
                  onPressed: () => _changeFile(context),
                  child: const Text('Change file'),
                ),
                onTap: () => _changeFile(context),
              ),
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('Number format'),
                subtitle: Text(
                  '${override == null ? systemDefaultLabel(settings.systemLocale) : localeDisplayName(override)}'
                  ' · ${sampleNumber(settings.effectiveLocale)}',
                ),
                onTap: () => _pickLocale(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

String systemDefaultLabel(String systemLocale) =>
    'Same as phone (${localeDisplayName(systemLocale)})';

/// A sample total in [locale], showing its separators.
String sampleNumber(String locale) =>
    formatTotal(ListTotal(Decimal.parse('1234.56'), 2), locale);

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

/// The result of the locale picker. A null [locale] means the system default.
class _LocaleChoice {
  const _LocaleChoice(this.locale);
  final String? locale;
}

/// A searchable list of locales, with the system default first.
class LocalePickerPage extends StatefulWidget {
  const LocalePickerPage({
    super.key,
    required this.current,
    required this.systemLocale,
  });

  /// The chosen locale, or null for the system default.
  final String? current;
  final String systemLocale;

  @override
  State<LocalePickerPage> createState() => _LocalePickerPageState();
}

class _LocalePickerPageState extends State<LocalePickerPage> {
  static final _all = selectableLocales();
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Matches the readable name, or the code (`de_CH`, `de-CH`).
  bool _matches(String name, [String? code]) {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty || name.toLowerCase().contains(q)) return true;
    return code != null && code.toLowerCase().contains(q.replaceAll('-', '_'));
  }

  @override
  Widget build(BuildContext context) {
    final systemLabel = systemDefaultLabel(widget.systemLocale);
    final locales = _all
        .where((l) => _matches(localeDisplayName(l), l))
        .toList();
    final showSystem = _matches(systemLabel);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _search,
          autofocus: false,
          decoration: const InputDecoration(
            hintText: 'Search languages and countries',
            border: InputBorder.none,
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          if (_search.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Clear',
              onPressed: () => setState(_search.clear),
            ),
        ],
      ),
      body: ListView.builder(
        itemCount: locales.length + (showSystem ? 1 : 0),
        itemBuilder: (context, index) {
          if (showSystem && index == 0) {
            return _tile(
              title: systemLabel,
              sample: sampleNumber(widget.systemLocale),
              selected: widget.current == null,
              choice: const _LocaleChoice(null),
            );
          }
          final locale = locales[index - (showSystem ? 1 : 0)];
          return _tile(
            title: localeDisplayName(locale),
            sample: sampleNumber(locale),
            selected: widget.current == locale,
            choice: _LocaleChoice(locale),
          );
        },
      ),
    );
  }

  Widget _tile({
    required String title,
    required String sample,
    required bool selected,
    required _LocaleChoice choice,
  }) => ListTile(
    title: Text(title),
    subtitle: Text(sample),
    trailing: selected ? const Icon(Icons.check) : null,
    selected: selected,
    onTap: () => Navigator.pop(context, choice),
  );
}
