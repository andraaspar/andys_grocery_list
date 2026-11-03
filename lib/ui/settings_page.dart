import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../model/amounts.dart';
import '../state/settings_controller.dart';

/// What happened when the user tried to change the file.
typedef FileChange = ({bool changed, String? error});

/// Settings (plan §7): change file, and the locale used for numbers.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.fileUri,
    required this.onOpenFile,
    required this.onCreateFile,
  });

  final SettingsController settings;

  /// The current file's URI.
  final String? fileUri;

  /// Pick an existing file / create a new one, and switch to it.
  final Future<FileChange> Function() onOpenFile;
  final Future<FileChange> Function() onCreateFile;

  Future<void> _changeFile(BuildContext context) async {
    final create = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('Open existing file'),
              onTap: () => Navigator.pop(context, false),
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Create new file'),
              onTap: () => Navigator.pop(context, true),
            ),
          ],
        ),
      ),
    );
    if (create == null || !context.mounted) return;
    final result = await (create ? onCreateFile() : onOpenFile());
    if (!context.mounted) return;
    if (result.error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(result.error!)));
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
                title: const Text('Locale'),
                subtitle: Text(
                  '${override ?? systemDefaultLabel(settings.systemLocale)}'
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
    'System default ($systemLocale)';

/// A sample total in [locale], showing its separators.
String sampleNumber(String locale) =>
    formatTotal(ListTotal(Decimal.parse('-1234.56'), 2), locale);

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

  bool _matches(String text) {
    final q = _search.text.trim().toLowerCase().replaceAll('-', '_');
    return q.isEmpty || text.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final systemLabel = systemDefaultLabel(widget.systemLocale);
    final locales = _all.where(_matches).toList();
    final showSystem = _matches(systemLabel);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _search,
          autofocus: false,
          decoration: const InputDecoration(
            hintText: 'Search locales',
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
            title: locale,
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
