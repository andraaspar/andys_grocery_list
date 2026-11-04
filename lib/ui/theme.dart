import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'display_options.dart';

/// The brand colours, taken from the launcher icon
/// (`tool/generate_launcher_icon.py`): its sunflower-yellow background, and the tiles
/// for the item states.
abstract final class BrandColors {
  static const sunflower = Color(0xFFFFC21A);
  static const doneFace = Color(0xFF3DD35F);
  static const doneSide = Color(0xFF21924A);
  static const failedFace = Color(0xFFFF5E62);
  static const failedSide = Color(0xFFC2343F);
  static const newFace = Color(0xFFFFFFFF);
  static const newSide = Color(0xFFE3B04B);
}

/// The colours of the DONE and FAILED state icons: the icon's tiles, toned
/// for readable contrast on the theme's surface.
@immutable
class StateColors extends ThemeExtension<StateColors> {
  const StateColors({required this.done, required this.failed});

  static const light = StateColors(
    done: Color(0xFF1E8C3E),
    failed: Color(0xFFD7373F),
  );
  static const dark = StateColors(
    done: Color(0xFF5FDC7C),
    failed: Color(0xFFFF8285),
  );

  final Color done;
  final Color failed;

  static StateColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<StateColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  StateColors copyWith({Color? done, Color? failed}) =>
      StateColors(done: done ?? this.done, failed: failed ?? this.failed);

  @override
  StateColors lerp(StateColors? other, double t) => other == null
      ? this
      : StateColors(
          done: Color.lerp(done, other.done, t)!,
          failed: Color.lerp(failed, other.failed, t)!,
        );
}

/// Colours of the list rows that the colour scheme doesn't name.
@immutable
class ListColors extends ThemeExtension<ListColors> {
  const ListColors({required this.header});

  /// The background of the list name rows: a light, untinted grey (dark
  /// grey in dark mode).
  final Color header;

  static ListColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ListColors>() ??
        ListColors(header: theme.colorScheme.surfaceContainerHigh);
  }

  @override
  ListColors copyWith({Color? header}) =>
      ListColors(header: header ?? this.header);

  @override
  ListColors lerp(ListColors? other, double t) => other == null
      ? this
      : ListColors(header: Color.lerp(header, other.header, t)!);
}

/// The light and dark themes. The app follows the system setting.
///
/// Yellow can't be used for text on a light background, so in light mode
/// the sunflower shows as the app bar, and text and accents are black. In
/// dark mode the primary itself is sunflower, and the bar stays dark so it
/// doesn't glare.
///
/// No brown and no gray text: the seed's brownish tones are replaced with
/// black (light) or neutral (dark) ones, and secondary text uses the same
/// colour as the main text.
ThemeData buildTheme(Brightness brightness, {Spacing spacing = Spacing.dense}) {
  final dark = brightness == Brightness.dark;
  final seeded = ColorScheme.fromSeed(
    seedColor: BrandColors.sunflower,
    brightness: brightness,
    // Light: primaryContainer is exactly the sunflower. Dark: primary is a
    // vivid sunflower. The default variant would tone both down.
    dynamicSchemeVariant: dark
        ? DynamicSchemeVariant.vibrant
        : DynamicSchemeVariant.fidelity,
  );
  // Untinted greys, for the surfaces and outlines.
  final neutral = ColorScheme.fromSeed(
    seedColor: BrandColors.sunflower,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.monochrome,
  );
  final text = dark ? Colors.white : Colors.black;
  final scheme = seeded.copyWith(
    onSurface: text,
    onSurfaceVariant: text,
    outline: neutral.outline,
    outlineVariant: neutral.outlineVariant,
    onPrimaryContainer: dark ? null : Colors.black,
    onSecondaryContainer: dark ? null : Colors.black,
    // Light: the gold-brown accents become black.
    primary: dark ? null : Colors.black,
    onPrimary: dark ? null : Colors.white,
    secondary: dark ? null : Colors.black,
    onSecondary: dark ? null : Colors.white,
    tertiary: dark ? null : Colors.black,
    onTertiary: dark ? null : Colors.white,
    // Dark: the brownish surfaces become black and neutral greys.
    surface: dark ? Colors.black : null,
    surfaceDim: dark ? Colors.black : null,
    surfaceBright: dark ? neutral.surfaceBright : null,
    surfaceContainerLowest: dark ? Colors.black : null,
    surfaceContainerLow: dark ? neutral.surfaceContainerLow : null,
    surfaceContainer: dark ? neutral.surfaceContainer : null,
    surfaceContainerHigh: dark ? neutral.surfaceContainerHigh : null,
    surfaceContainerHighest: dark ? neutral.surfaceContainerHighest : null,
    surfaceTint: dark ? Colors.transparent : null,
  );
  return ThemeData(
    colorScheme: scheme,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? null : scheme.primaryContainer,
      foregroundColor: dark ? null : Colors.black,
      // Keep the bar's colour when the list scrolls under it.
      scrolledUnderElevation: 0,
      // Action buttons are 12 px wider than their icons on each side; this
      // puts the last icon 16 px from the edge, like the rows' icons.
      // [scaleAppBar] adjusts it to the text size.
      actionsPadding: const EdgeInsets.only(right: 4),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    extensions: [
      dark ? StateColors.dark : StateColors.light,
      ListColors(header: neutral.surfaceContainerHigh),
      SpacingTheme(spacing),
    ],
  );
}

/// The system navigation bar over the bottom of the app: see-through, with
/// icons that contrast with the theme's background.
///
/// Without this, Android uses light icons, meant for a black bar. With the
/// app drawn edge to edge they would sit on the app's light background,
/// over a white contrast backing, and be almost invisible.
SystemUiOverlayStyle navigationBarStyle(Brightness brightness) =>
    SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: brightness == Brightness.dark
          ? Brightness.light
          : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    );

/// An opaque backing for the system navigation bar, for a [Scaffold]'s
/// `bottomNavigationBar`.
///
/// Since Android 15 the app is always drawn behind the navigation bar, and
/// the bar's own colour can't be set, so with three-button navigation the
/// content would scroll behind the buttons. With this, the [Scaffold] keeps
/// its body above the bar.
class NavigationBarBacking extends StatelessWidget {
  const NavigationBarBacking({super.key});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: SizedBox(
      width: double.infinity,
      height: MediaQuery.viewPaddingOf(context).bottom,
    ),
  );
}
