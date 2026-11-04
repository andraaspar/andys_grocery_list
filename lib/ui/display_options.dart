import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How much room the list rows get, chosen in Settings.
enum Spacing {
  dense('Dense', 4),
  comfortable('Comfortable', 8),
  roomy('Roomy', 12);

  const Spacing(this.label, this.textPadding);

  final String label;

  /// The space above and below an item's text.
  final double textPadding;

  static Spacing fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => dense);
}

/// The text size, chosen in Settings. It multiplies the phone's own text
/// size. [small] is the size of Flutter's standard text styles.
enum FontSize {
  small('Small', 1.0),
  normal('Normal', 1.15),
  large('Large', 1.3),
  larger('Larger', 1.5);

  const FontSize(this.label, this.factor);

  final String label;
  final double factor;

  static FontSize fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => normal);
}

/// Light or dark colours, chosen in Settings.
enum ColorMode {
  system('Same as phone', ThemeMode.system),
  light('Light', ThemeMode.light),
  dark('Dark', ThemeMode.dark);

  const ColorMode(this.label, this.themeMode);

  final String label;
  final ThemeMode themeMode;

  static ColorMode fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => system);
}

/// The phone's text scaling, multiplied by [factor].
class ScaledTextScaler extends TextScaler {
  const ScaledTextScaler(this.base, this.factor);

  final TextScaler base;
  final double factor;

  @override
  double scale(double fontSize) => base.scale(fontSize) * factor;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => base.textScaleFactor * factor;

  @override
  bool operator ==(Object other) =>
      other is ScaledTextScaler && other.base == base && other.factor == factor;

  @override
  int get hashCode => Object.hash(base, factor);
}

/// The chosen [Spacing], carried by the theme.
@immutable
class SpacingTheme extends ThemeExtension<SpacingTheme> {
  const SpacingTheme(this.spacing);

  final Spacing spacing;

  @override
  SpacingTheme copyWith({Spacing? spacing}) =>
      SpacingTheme(spacing ?? this.spacing);

  @override
  SpacingTheme lerp(SpacingTheme? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

/// Sizes of the list rows, from the text size and the [Spacing].
///
/// An item row's first line is [lineHeight] high with [textPadding] above
/// and below, so the row is [rowHeight] high. Its icon buttons are as high
/// as that, with icons as big as a line of text, so the icons stay centred
/// on the first line at any text size.
class RowMetrics {
  RowMetrics._({required this.lineHeight, required this.textPadding});

  factory RowMetrics.of(BuildContext context) {
    final theme = Theme.of(context);
    final spacing = theme.extension<SpacingTheme>()?.spacing ?? Spacing.dense;
    return RowMetrics._(
      lineHeight: lineHeightOf(theme, MediaQuery.textScalerOf(context)),
      textPadding: spacing.textPadding,
    );
  }

  /// The height of one line of item text, with [textScaler] applied.
  static double lineHeightOf(ThemeData theme, TextScaler textScaler) {
    final base = theme.textTheme.bodyLarge!;
    return textScaler.scale(base.fontSize ?? 16) * (base.height ?? 1.5);
  }

  /// The height of one line of item text.
  final double lineHeight;

  /// The space above and below an item's text.
  final double textPadding;

  double get rowHeight => lineHeight + 2 * textPadding;

  /// At the normal text size, 24: the standard icon size.
  double get iconSize => lineHeight;

  /// 8 px either side of the icon.
  double get buttonWidth => iconSize + 16;

  Size get buttonSize => Size(buttonWidth, rowHeight);

  /// The space above and below a list name's row.
  double get headerPadding => textPadding / 2;

  /// The icon buttons in the rows: [buttonSize], with no larger tap target.
  ButtonStyle get buttonStyle => IconButton.styleFrom(
    minimumSize: buttonSize,
    maximumSize: buttonSize,
    fixedSize: buttonSize,
    padding: EdgeInsets.zero,
    iconSize: iconSize,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.standard,
  );

  /// A box the size of a row button, for icons that aren't buttons.
  Widget iconBox(Widget icon) => SizedBox(
    width: buttonWidth,
    height: rowHeight,
    child: IconTheme.merge(
      data: IconThemeData(size: iconSize),
      child: Center(child: icon),
    ),
  );
}

/// [theme] with the app bar's icons as big as the rows' icons, and the bar
/// as much taller as they are bigger (56 px at the standard 24 px icon
/// size). The last action's icon is 16 px from the edge at the standard
/// size, and further in proportion to the icon size.
ThemeData scaleAppBar(ThemeData theme, TextScaler textScaler) {
  final iconSize = RowMetrics.lineHeightOf(theme, textScaler);
  final height = iconSize + 32;
  // An action button lays out at least 48 px wide (its tap target), with
  // 8 px either side of the icon.
  final buttonWidth = math.max(kMinInteractiveDimension, iconSize + 16);
  final iconInset = (buttonWidth - iconSize) / 2;
  final edgeGap = 16 * iconSize / 24;
  // A colour must be given: an icon theme without one would replace the
  // bar's foreground colour.
  final icons = IconThemeData(
    size: iconSize,
    color: theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface,
  );
  return theme.copyWith(
    appBarTheme: theme.appBarTheme.copyWith(
      iconTheme: icons,
      actionsIconTheme: icons,
      toolbarHeight: height,
      leadingWidth: height,
      actionsPadding: EdgeInsets.only(right: edgeGap - iconInset),
    ),
  );
}
