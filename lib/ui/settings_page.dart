import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';

import '../model/amounts.dart';
import '../model/locale_names.dart';
import '../state/settings_controller.dart';
import 'display_options.dart';
import 'file_switcher.dart';
import 'theme.dart';

export 'file_switcher.dart' show fileDisplayName;

/// Settings (plan §7): change file, the locale used for numbers, and the
/// row spacing and text size.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.fileUri,
    required this.files,
  });

  final SettingsController settings;

  /// The current file's URI.
  final String? fileUri;

  /// What the file switcher offers.
  final FileActions files;

  Future<void> _changeFile(BuildContext context) async {
    final changed = await showFileSwitcher(context, files);
    if (changed && context.mounted) Navigator.pop(context);
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

  Future<void> _pickSpacing(BuildContext context) async {
    final picked = await _pickOption(
      context,
      title: 'Spacing',
      options: Spacing.values,
      current: settings.spacing,
      label: (s) => Text(s.label),
    );
    if (picked != null) await settings.setSpacing(picked);
  }

  Future<void> _pickFontSize(BuildContext context) async {
    final style = Theme.of(context).textTheme.bodyLarge!;
    final picked = await _pickOption(
      context,
      title: 'Text size',
      options: FontSize.values,
      current: settings.fontSize,
      // Each shown at its own size, relative to the current one.
      label: (f) => Text(
        f.label,
        style: style.copyWith(
          fontSize: style.fontSize! * f.factor / settings.fontSize.factor,
        ),
      ),
    );
    if (picked != null) await settings.setFontSize(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      bottomNavigationBar: const NavigationBarBacking(),
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
              ListTile(
                leading: const Icon(Icons.format_line_spacing),
                title: const Text('Spacing'),
                subtitle: Text(settings.spacing.label),
                onTap: () => _pickSpacing(context),
              ),
              ListTile(
                leading: const Icon(Icons.format_size),
                title: const Text('Text size'),
                subtitle: Text(settings.fontSize.label),
                onTap: () => _pickFontSize(context),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// A dialog listing [options], with [current] checked. Null if dismissed.
Future<T?> _pickOption<T>(
  BuildContext context, {
  required String title,
  required List<T> options,
  required T current,
  required Widget Function(T) label,
}) => showDialog<T>(
  context: context,
  builder: (context) => SimpleDialog(
    title: Text(title),
    children: [
      for (final option in options)
        ListTile(
          title: label(option),
          trailing: option == current ? const Icon(Icons.check) : null,
          selected: option == current,
          contentPadding: const EdgeInsets.symmetric(horizontal: 24),
          onTap: () => Navigator.pop(context, option),
        ),
    ],
  ),
);

String systemDefaultLabel(String systemLocale) =>
    'Same as phone (${localeDisplayName(systemLocale)})';

/// A sample total in [locale], showing its separators.
String sampleNumber(String locale) =>
    formatTotal(ListTotal(Decimal.parse('1234.56'), 2), locale);

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
      bottomNavigationBar: const NavigationBarBacking(),
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
