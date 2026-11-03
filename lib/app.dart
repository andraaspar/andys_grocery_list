import 'package:flutter/material.dart';

import 'app_name.dart';
import 'model/markdown_codec.dart';
import 'state/document_controller.dart';
import 'ui/home_page.dart';

/// Shown until file storage lands (milestone 7). Nothing is saved yet.
const _sampleDocument = '''
# Groceries
- [ ] 3x Milk 1.29
- [x] Bread 2,49
- [x] 1.5x Cheese 8.00
- [x] FAILED 2x Fresh basil 0.99

# Work
- [ ] Write report
''';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  late final DocumentController _document;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _document = DocumentController(
      parseDocument(_sampleDocument),
      locale: WidgetsBinding.instance.platformDispatcher.locale.toString(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _document.dispose();
    super.dispose();
  }

  /// The app name follows the system language, so rebuild when it changes.
  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (_) => appName(),
      theme: ThemeData(colorSchemeSeed: Colors.green),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.green,
        brightness: Brightness.dark,
      ),
      home: HomePage(document: _document),
    );
  }
}
