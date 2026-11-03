import 'dart:ui';

const appNameEn = "Andy's Grocery List";
const appNameHu = 'Andris Bevlistája';

/// The app name for the system language (plan §0). Hungarian gets the
/// Hungarian name; every other language gets the English one.
String appNameFor(Locale? systemLocale) =>
    systemLocale?.languageCode == 'hu' ? appNameHu : appNameEn;

/// The app name for the current system language.
String appName() => appNameFor(PlatformDispatcher.instance.locale);
