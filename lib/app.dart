import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_name.dart';
import 'state/document_controller.dart';
import 'storage/saf_storage.dart';
import 'storage/settings.dart';
import 'ui/home_page.dart';
import 'ui/scroll_memory.dart';
import 'ui/welcome_page.dart';

class App extends StatefulWidget {
  const App({super.key, this.storage = const SafStorage()});

  final DocumentStorage storage;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  Settings? _settings;
  DocumentController? _document;
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
    super.dispose();
  }

  Future<void> _start() async {
    final settings = await Settings.load();
    _settings = settings;
    final uri = settings.fileUri;
    if (uri != null) await _openUri(uri);
    if (mounted) setState(() => _loading = false);
  }

  String get _locale =>
      WidgetsBinding.instance.platformDispatcher.locale.toString();

  /// Opens the file at [uri] and makes it the current one.
  Future<void> _openUri(String uri) async {
    final DocumentController doc;
    try {
      if (!await _storage.hasPermission(uri)) {
        throw const _AccessLost();
      }
      doc = await DocumentController.open(_storage, uri, locale: _locale);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is _AccessLost || _isPermissionError(e)
            ? 'Access to the file was lost. Please open it again.'
            : 'Could not open the file.';
      });
      return;
    }
    if (!mounted) {
      doc.dispose();
      return;
    }
    doc.onStorageError = _onStorageError;
    final old = _document;
    setState(() {
      _document = doc;
      _error = null;
    });
    await _settings?.setFileUri(uri);
    if (old != null) {
      await old.save();
      old.dispose();
    }
    doc.startPolling();
  }

  Future<void> _pick(Future<String?> Function() picker) async {
    final String? uri;
    try {
      uri = await picker();
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? 'Could not pick a file.');
      }
      return;
    }
    if (uri != null) await _openUri(uri);
  }

  bool _isPermissionError(Object e) =>
      e is PlatformException && e.code == 'permission';

  void _onStorageError(Object e) {
    if (_isPermissionError(e)) {
      final doc = _document;
      setState(() {
        _document = null;
        _error = 'Access to the file was lost. Please open it again.';
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => doc?.dispose());
      return;
    }
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('Could not access the file: ${_message(e)}')),
      );
  }

  String _message(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : '$e';

  /// The app name follows the system language, so rebuild when it changes.
  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

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
      onGenerateTitle: (_) => appName(),
      theme: ThemeData(colorSchemeSeed: Colors.green),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.green,
        brightness: Brightness.dark,
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
        onOpen: () => _pick(_storage.openDocument),
        onCreate: () => _pick(() => _storage.createDocument('todo.md')),
      );
    }
    return HomePage(
      key: ValueKey(doc),
      document: doc,
      scrollMemory: ScrollMemory(_settings!, doc.uri!),
    );
  }
}

class _AccessLost implements Exception {
  const _AccessLost();
}
