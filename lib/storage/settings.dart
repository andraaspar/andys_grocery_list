import 'package:shared_preferences/shared_preferences.dart';

/// Per-device settings in `shared_preferences` (plan §7, §8).
class Settings {
  Settings(this._prefs);

  static Future<Settings> load() async =>
      Settings(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _fileUriKey = 'fileUri';
  static const _scrollKeyPrefix = 'scroll:';

  String? get fileUri => _prefs.getString(_fileUriKey);

  Future<void> setFileUri(String? uri) => uri == null
      ? _prefs.remove(_fileUriKey)
      : _prefs.setString(_fileUriKey, uri);

  /// The encoded scroll anchor for the file at [uri] (plan §3, Scrolling).
  String? scrollAnchor(String uri) => _prefs.getString('$_scrollKeyPrefix$uri');

  Future<void> setScrollAnchor(String uri, String encoded) =>
      _prefs.setString('$_scrollKeyPrefix$uri', encoded);
}
