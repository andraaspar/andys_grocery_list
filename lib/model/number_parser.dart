/// Locale-aware "natural" number parsing (plan §2, Numbers).
library;

import 'package:decimal/decimal.dart';
import 'package:intl/intl.dart';
import 'package:intl/number_symbols.dart';

/// The separators of a locale, used to resolve ambiguous `.` / `,`.
class NumberContext {
  const NumberContext({required this.decimalSep, required this.groupSep});

  /// Builds the context from `intl`'s number symbols for [locale].
  /// Unsupported locales fall back to English.
  factory NumberContext.forLocale(String? locale) {
    final symbols = numberSymbolsFor(locale);
    return NumberContext(
      decimalSep: symbols.DECIMAL_SEP,
      groupSep: symbols.GROUP_SEP,
    );
  }

  static const en = NumberContext(decimalSep: '.', groupSep: ',');

  final String decimalSep;
  final String groupSep;
}

/// Returns `intl`'s number format for [locale], falling back to English.
NumberFormat decimalFormatFor(String? locale) {
  try {
    return NumberFormat.decimalPattern(locale);
  } on ArgumentError {
    return NumberFormat.decimalPattern('en');
  }
}

NumberSymbols numberSymbolsFor(String? locale) =>
    decimalFormatFor(locale).symbols;

/// A successfully parsed number token.
class ParsedNumber {
  const ParsedNumber({
    required this.value,
    required this.decimalChar,
    required this.fractionDigits,
  });

  final Decimal value;

  /// The character used as the decimal point, or null if there is none.
  final String? decimalChar;

  /// How many digits were written after the decimal point.
  final int fractionDigits;
}

const _minusChars = {'-', '−'};
const _ambiguousSeps = {'.', ','};
const _groupOnlySeps = {"'", '’', ' ', ' '};

/// Characters that can appear inside a number token (after the sign).
bool isNumberChar(String c) =>
    _isDigit(c) || _ambiguousSeps.contains(c) || _groupOnlySeps.contains(c);

bool _isDigit(String c) {
  final u = c.codeUnitAt(0);
  return u >= 0x30 && u <= 0x39;
}

/// Parses [token] as a whole. Returns null if it is not exactly a number.
///
/// If [signed] is false, a leading sign makes the token invalid.
ParsedNumber? parseNumberToken(
  String token,
  NumberContext ctx, {
  bool signed = true,
}) {
  if (token.isEmpty) return null;
  var negative = false;
  var body = token;
  if (_minusChars.contains(token[0])) {
    if (!signed) return null;
    negative = true;
    body = token.substring(1);
  }
  if (body.isEmpty) return null;
  if (!_isDigit(body[0]) || !_isDigit(body[body.length - 1])) return null;

  var dots = 0, commas = 0, lastDot = -1, lastComma = -1;
  for (var i = 0; i < body.length; i++) {
    final c = body[i];
    if (_isDigit(c)) continue;
    if (!isNumberChar(c)) return null;
    // No two separators in a row.
    if (!_isDigit(body[i - 1])) return null;
    if (c == '.') {
      dots++;
      lastDot = i;
    } else if (c == ',') {
      commas++;
      lastComma = i;
    }
  }

  // Decide which position (if any) is the decimal point.
  int decimalPos = -1;
  if (dots > 0 && commas > 0) {
    // Rule 1: the one that comes last is the decimal point.
    final isDot = lastDot > lastComma;
    if ((isDot ? dots : commas) != 1) return null;
    decimalPos = isDot ? lastDot : lastComma;
  } else if (dots > 1 || commas > 1) {
    // Rule 2: repeated → thousands separator.
    decimalPos = -1;
  } else if (dots == 1 || commas == 1) {
    // Rule 3: exactly one occurrence.
    final sep = dots == 1 ? '.' : ',';
    final pos = dots == 1 ? lastDot : lastComma;
    if (sep == ctx.decimalSep) {
      decimalPos = pos;
    } else if (sep == ctx.groupSep && _digitRunAfter(body, pos) == 3) {
      decimalPos = -1;
    } else {
      decimalPos = pos;
    }
  }

  final intPart = decimalPos < 0 ? body : body.substring(0, decimalPos);
  final fracPart = decimalPos < 0 ? '' : body.substring(decimalPos + 1);

  // No grouping after the decimal point.
  for (var i = 0; i < fracPart.length; i++) {
    if (!_isDigit(fracPart[i])) return null;
  }

  // Grouping must be well formed: first group 1–3 digits, the rest exactly 3.
  final groups = <String>[];
  var current = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    final c = intPart[i];
    if (_isDigit(c)) {
      current.write(c);
    } else {
      groups.add(current.toString());
      current = StringBuffer();
    }
  }
  groups.add(current.toString());
  if (groups.length > 1) {
    if (groups.first.isEmpty || groups.first.length > 3) return null;
    for (final g in groups.skip(1)) {
      if (g.length != 3) return null;
    }
  }

  final digits = groups.join();
  final source =
      '${negative ? '-' : ''}$digits${fracPart.isEmpty ? '' : '.$fracPart'}';
  return ParsedNumber(
    value: Decimal.parse(source),
    decimalChar: decimalPos < 0 ? null : body[decimalPos],
    fractionDigits: fracPart.length,
  );
}

int _digitRunAfter(String s, int pos) {
  var n = 0;
  for (var i = pos + 1; i < s.length && _isDigit(s[i]); i++) {
    n++;
  }
  return n;
}
