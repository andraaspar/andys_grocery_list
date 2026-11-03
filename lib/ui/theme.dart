import 'package:flutter/material.dart';

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
ThemeData buildTheme(Brightness brightness) {
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
    appBarTheme: dark
        ? null
        : AppBarTheme(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: Colors.black,
          ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    extensions: [dark ? StateColors.dark : StateColors.light],
  );
}
