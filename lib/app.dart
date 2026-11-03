import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_name.dart';
import 'state/document_controller.dart';
import 'state/settings_controller.dart';
import 'storage/saf_storage.dart';
import 'storage/settings.dart';
import 'ui/file_switcher.dart';
import 'ui/home_page.dart';
import 'ui/scroll_memory.dart';
import 'ui/settings_page.dart';
import 'ui/snackbars.dart';
import 'ui/theme.dart';
import 'ui/welcome_page.dart';

class App extends StatefulWidget {
  const App({super.key, this.storage = const SafStorage()});

  final DocumentStorage storage;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _navigator = GlobalKey<NavigatorState>();

  Settings? _settings;
  SettingsController? _settingsController;
  DocumentController? _document;

  /// The open file's name, shown as the home page's title.
  String? _fileName;
  bool _loading = true;
  String? _error;

  DocumentStorage get _storage => widget.storage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Edits were already saved when the app was paused.
    _document?.dispose();
    _settingsController?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final settings = await Settings.load();
    _settings = settings;
    _settingsController = SettingsController(settings)
      ..addListener(_onLocaleChanged);
    final uri = settings.fileUri;
    if (uri != null) {
      final error = await _openUri(uri);
      if (error != null && mounted) setState(() => _error = error);
    }
    if (mounted) setState(() => _loading = false);
  }

  /// The locale used for numbers (plan §7).
  String get _locale =>
      _settingsController?.effectiveLocale ??
      WidgetsBinding.instance.platformDispatcher.locale.toString();

  void _onLocaleChanged() => _document?.setLocale(_locale);

  /// Opens the file at [uri] and makes it the current one. Returns why it
  /// could not be opened, or null on success. On failure the current file
  /// stays open.
  Future<String?> _openUri(String uri) async {
    // Write pending edits first, in case [uri] is the current file.
    await _document?.save();
    final DocumentController doc;
    try {
      if (!await _storage.hasPermission(uri)) {
        throw const _AccessLost();
      }
      doc = await DocumentController.open(_storage, uri, locale: _locale);
    } catch (e) {
      return e is _AccessLost || _isPermissionError(e)
          ? 'Access to the file was lost. Please open it again.'
          : 'Could not open the file.';
    }
    if (!mounted) {
      doc.dispose();
      return null;
    }
    String? name;
    try {
      name = await _storage.displayName(uri);
    } on PlatformException {
      name = null;
    }
    if (!mounted) {
      doc.dispose();
      return null;
    }
    doc.onStorageError = _onStorageError;
    final old = _document;
    setState(() {
      _document = doc;
      _fileName = name ?? fileDisplayName(uri);
      _error = null;
    });
    await _settings?.setFileUri(uri);
    for (final dropped in await _settings?.addRecentFile(uri) ?? const []) {
      await _release(dropped);
    }
    if (old != null) {
      await old.save();
      // The old home page is unmounted after the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    }
    doc.startPolling();
    return null;
  }

  /// Runs a file picker and opens the picked file.
  Future<FileChange> _pick(Future<String?> Function() picker) async {
    final String? uri;
    try {
      uri = await picker();
    } on PlatformException catch (e) {
      return (changed: false, error: e.message ?? 'Could not pick a file.');
    }
    if (uri == null) return (changed: false, error: null);
    final error = await _openUri(uri);
    return (changed: error == null, error: error);
  }

  /// The recent files other than the current one, by name. Files that no
  /// longer exist are forgotten.
  Future<List<RecentFile>> _recentFiles() async {
    final settings = _settings;
    if (settings == null) return const [];
    final current = _document?.uri;
    final kept = <String>[];
    final out = <RecentFile>[];
    for (final uri in settings.recentFiles) {
      String? name;
      try {
        name = await _storage.displayName(uri);
      } on PlatformException {
        name = null;
      }
      if (name == null && uri != current) {
        await _release(uri);
        continue;
      }
      kept.add(uri);
      if (uri != current) out.add((uri: uri, name: name!));
    }
    if (kept.length != settings.recentFiles.length) {
      await settings.setRecentFiles(kept);
    }
    return out;
  }

  Future<void> _removeRecentFile(String uri) async {
    final settings = _settings;
    if (settings == null) return;
    await settings.setRecentFiles(
      settings.recentFiles.where((u) => u != uri).toList(),
    );
    await _release(uri);
  }

  /// Gives up access to [uri], unless it is the current file.
  Future<void> _release(String uri) async {
    if (uri == _document?.uri) return;
    try {
      await _storage.releasePermission(uri);
    } on PlatformException {
      // Nothing to do.
    }
  }

  Future<FileChange> _openRecentFile(String uri) async {
    final error = await _openUri(uri);
    if (error != null) await _removeRecentFile(uri);
    return (changed: error == null, error: error);
  }

  /// From the welcome page: errors are shown on the page.
  Future<void> _pickFromWelcome(Future<String?> Function() picker) async {
    final result = await _pick(picker);
    if (result.error != null && mounted) {
      setState(() => _error = result.error);
    }
  }

  FileActions get _fileActions => FileActions(
    openFile: () => _pick(_storage.openDocument),
    createFile: () => _pick(() => _storage.createDocument('todo.md')),
    recentFiles: _recentFiles,
    openRecentFile: _openRecentFile,
    removeRecentFile: _removeRecentFile,
  );

  /// From the home page's title.
  void _switchFile() {
    final context = _navigator.currentContext;
    if (context != null) showFileSwitcher(context, _fileActions);
  }

  void _openSettings() {
    final settings = _settingsController;
    if (settings == null) return;
    _navigator.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          settings: settings,
          fileUri: _document?.uri,
          files: _fileActions,
        ),
      ),
    );
  }

  bool _isPermissionError(Object e) =>
      e is PlatformException && e.code == 'permission';

  void _onStorageError(Object e) {
    if (_isPermissionError(e)) {
      final doc = _document;
      _navigator.currentState?.popUntil((r) => r.isFirst);
      setState(() {
        _document = null;
        _error = 'Access to the file was lost. Please open it again.';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => doc?.dispose());
      return;
    }
    showMessage(
      _messenger.currentState,
      'Could not access the file: ${_message(e)}',
    );
  }

  String _message(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : '$e';

  /// The app name follows the system language, so rebuild when it changes.
  /// Numbers follow it too, unless a locale is chosen in Settings.
  @override
  void didChangeLocales(List<Locale>? locales) {
    setState(() {});
    _settingsController?.systemLocaleChanged();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final doc = _document;
    if (doc == null) return;
    switch (state) {
      case AppLifecycleState.resumed:
        doc.checkExternalChange();
        doc.startPolling();
      case AppLifecycleState.inactive ||
          AppLifecycleState.hidden ||
          AppLifecycleState.paused:
        doc.stopPolling();
        doc.save();
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: _messenger,
      navigatorKey: _navigator,
      onGenerateTitle: (_) => appName(),
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: navigationBarStyle(Theme.of(context).brightness),
        child: child!,
      ),
      home: _buildHome(),
    );
  }

  Widget _buildHome() {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final doc = _document;
    if (doc == null) {
      return WelcomePage(
        error: _error,
        onOpen: () => _pickFromWelcome(_storage.openDocument),
        onCreate: () =>
            _pickFromWelcome(() => _storage.createDocument('todo.md')),
      );
    }
    return HomePage(
      key: ValueKey(doc),
      document: doc,
      scrollMemory: ScrollMemory(_settings!, doc.uri!),
      helpExpanded: _settings!.helpExpanded,
      onHelpExpandedChanged: _settings!.setHelpExpanded,
      onOpenSettings: _openSettings,
      title: _fileName,
      onTapTitle: _switchFile,
    );
  }
}

class _AccessLost implements Exception {
  const _AccessLost();
}
