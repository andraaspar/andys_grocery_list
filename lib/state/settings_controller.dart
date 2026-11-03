import 'package:flutter/widgets.dart';
import 'package:intl/number_symbols_data.dart';

import '../storage/settings.dart';

/// The effective number locale: the one chosen in Settings, or the system
/// locale (plan §7). The owner calls [systemLocaleChanged] from
/// `didChangeLocales`.
class SettingsController extends ChangeNotifier {
  SettingsController(this._settings, {String Function()? systemLocale})
    : _systemLocale = systemLocale ?? _platformLocale;

  static String _platformLocale() =>
      WidgetsBinding.instance.platformDispatcher.locale.toString();

  final Settings _settings;
  final String Function() _systemLocale;

  Settings get settings => _settings;

  /// The locale chosen in Settings, or null for the system default.
  String? get localeOverride => _settings.locale;

  String get systemLocale => _systemLocale();

  /// The locale used to parse numbers and format totals.
  String get effectiveLocale => localeOverride ?? systemLocale;

  Future<void> setLocaleOverride(String? locale) async {
    if (locale == localeOverride) return;
    await _settings.setLocale(locale);
    notifyListeners();
  }

  /// Only matters while following the system.
  void systemLocaleChanged() {
    if (localeOverride == null) notifyListeners();
  }
}

/// The locales `intl` has number symbols for, sorted. Locales that write
/// digits other than 0–9 are left out, because the number parser only reads
/// ASCII digits (plan §2).
List<String> selectableLocales() {
  final locales = [
    for (final e in numberFormatSymbols.entries)
      if (e.value.ZERO_DIGIT == '0') e.key,
  ]..sort();
  return locales;
}
