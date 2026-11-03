import 'package:flutter/widgets.dart';
import 'package:intl/number_symbols_data.dart';

import '../model/locale_names.dart';
import '../storage/settings.dart';
import '../ui/display_options.dart';

/// The settings that change how the app looks or reads numbers.
///
/// The effective number locale is the one chosen in Settings, or the system
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

  Spacing get spacing => Spacing.fromName(_settings.spacing);

  Future<void> setSpacing(Spacing spacing) async {
    if (spacing == this.spacing) return;
    await _settings.setSpacing(spacing.name);
    notifyListeners();
  }

  FontSize get fontSize => FontSize.fromName(_settings.fontSize);

  Future<void> setFontSize(FontSize fontSize) async {
    if (fontSize == this.fontSize) return;
    await _settings.setFontSize(fontSize.name);
    notifyListeners();
  }

  /// Only matters while following the system.
  void systemLocaleChanged() {
    if (localeOverride == null) notifyListeners();
  }
}

/// The locales `intl` has number symbols for, sorted by their readable
/// name. Locales that write digits other than 0–9 are left out, because the
/// number parser only reads ASCII digits (plan §2), and so are old codes
/// that duplicate a current one.
List<String> selectableLocales() {
  final locales = [
    for (final e in numberFormatSymbols.entries)
      if (e.value.ZERO_DIGIT == '0' && !deprecatedLocaleAliases.contains(e.key))
        e.key,
  ];
  final names = {for (final l in locales) l: localeDisplayName(l)};
  return locales..sort((a, b) => names[a]!.compareTo(names[b]!));
}
