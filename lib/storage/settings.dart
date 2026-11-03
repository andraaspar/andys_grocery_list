import 'package:shared_preferences/shared_preferences.dart';

/// Per-device settings in `shared_preferences` (plan §7, §8).
class Settings {
  Settings(this._prefs);

  static Future<Settings> load() async =>
      Settings(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _fileUriKey = 'fileUri';
  static const _localeKey = 'locale';
  static const _scrollKeyPrefix = 'scroll:';
  static const _recentFilesKey = 'recentFiles';
  static const _helpExpandedKey = 'helpExpanded';

  /// How many recent files are remembered.
  static const maxRecentFiles = 10;

  String? get fileUri => _prefs.getString(_fileUriKey);

  Future<void> setFileUri(String? uri) => uri == null
      ? _prefs.remove(_fileUriKey)
      : _prefs.setString(_fileUriKey, uri);

  /// The files opened lately, most recent first, the current one included.
  List<String> get recentFiles =>
      _prefs.getStringList(_recentFilesKey) ?? const [];

  Future<void> setRecentFiles(List<String> uris) =>
      _prefs.setStringList(_recentFilesKey, uris);

  /// Puts [uri] first in [recentFiles]. Returns the files that fell off the
  /// end.
  Future<List<String>> addRecentFile(String uri) async {
    final all = [uri, ...recentFiles.where((u) => u != uri)];
    final kept = all.take(maxRecentFiles).toList();
    await setRecentFiles(kept);
    return all.skip(maxRecentFiles).toList();
  }

  /// Whether the usage help below the lists is expanded.
  bool get helpExpanded => _prefs.getBool(_helpExpandedKey) ?? true;

  Future<void> setHelpExpanded(bool expanded) =>
      _prefs.setBool(_helpExpandedKey, expanded);

  /// The locale chosen in Settings, such as `de_DE`. Null: follow the
  /// system (plan §7).
  String? get locale => _prefs.getString(_localeKey);

  Future<void> setLocale(String? locale) => locale == null
      ? _prefs.remove(_localeKey)
      : _prefs.setString(_localeKey, locale);

  /// The encoded scroll anchor for the file at [uri] (plan §3, Scrolling).
  String? scrollAnchor(String uri) => _prefs.getString('$_scrollKeyPrefix$uri');

  Future<void> setScrollAnchor(String uri, String encoded) =>
      _prefs.setString('$_scrollKeyPrefix$uri', encoded);
}
