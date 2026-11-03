/// Quantity, unit price and totals (plan §2).
library;

import 'package:decimal/decimal.dart';

import 'number_parser.dart';
import 'todo_document.dart';

/// A number found inside item text. [start]..[end] covers the number only.
class AmountMatch {
  const AmountMatch(this.number, this.start, this.end);

  final ParsedNumber number;
  final int start;
  final int end;

  Decimal get value => number.value;
}

/// The quantity prefix `<n>x ` at the start of [text], or null if there is
/// none (meaning the quantity is an implied 1).
AmountMatch? parseQuantity(String text, NumberContext ctx) {
  var end = 0;
  while (end < text.length && isNumberChar(text[end])) {
    end++;
  }
  if (end == 0 || end >= text.length || text[end] != 'x') return null;
  if (end + 1 < text.length && text[end + 1] != ' ') return null;
  final number = parseNumberToken(text.substring(0, end), ctx, signed: false);
  if (number == null) return null;
  return AmountMatch(number, 0, end);
}

/// The quantity of [text]: the prefix value, or 1 if there is none.
Decimal quantityOf(String text, NumberContext ctx) =>
    parseQuantity(text, ctx)?.value ?? Decimal.one;

/// Adds 1 to the quantity of [text]. Returns the new text and the range of
/// the number in it.
({String text, int start, int end}) incrementQuantity(
  String text,
  NumberContext ctx,
) {
  final q = parseQuantity(text, ctx);
  if (q == null) {
    return (text: '2x $text', start: 0, end: 1);
  }
  final formatted = _formatLike(q.value + Decimal.one, q.number);
  return (
    text: formatted + text.substring(q.end),
    start: 0,
    end: formatted.length,
  );
}

/// Formats [value] with the decimal character and number of decimal places
/// of [like], without grouping.
String _formatLike(Decimal value, ParsedNumber like) {
  final s = value.toStringAsFixed(like.fractionDigits);
  if (like.fractionDigits == 0) return s;
  return s.replaceFirst('.', like.decimalChar ?? '.');
}

/// Removes a quantity prefix whose value is exactly 1 (`1x `, `1.0x `...).
String stripQuantityOne(String text, NumberContext ctx) {
  final q = parseQuantity(text, ctx);
  if (q == null || q.value != Decimal.one) return text;
  // Remove the number, the `x` and the following space, if any.
  var cut = q.end + 1;
  if (cut < text.length && text[cut] == ' ') cut++;
  return text.substring(cut);
}

bool _isWordSpace(String c) => c == ' ' || c == '\t';

/// The unit price at the end of [text], or null if there is none.
///
/// Trailing whitespace is ignored; any other character after the number
/// means there is no price. [AmountMatch.end] is the end of the number.
AmountMatch? parsePrice(String text, NumberContext ctx) {
  final end = text.trimRight().length;
  if (end == 0) return null;
  var start = end;
  while (start > 0 && !_isWordSpace(text[start - 1])) {
    start--;
  }
  final number = parseNumberToken(text.substring(start, end), ctx);
  if (number == null) return null;
  return AmountMatch(number, start, end);
}

/// Quantity × price, or null if the item has no price.
Decimal? lineTotal(TodoItem item, NumberContext ctx) {
  final price = parsePrice(item.text, ctx);
  if (price == null) return null;
  return quantityOf(item.text, ctx) * price.value;
}

class ListTotal {
  const ListTotal(this.sum, this.fractionDigits);

  /// The exact sum.
  final Decimal sum;

  /// The largest number of decimal places used by the list's prices.
  final int fractionDigits;
}

/// The sum of quantity × price over DONE items, or null when no item in the
/// list (in any state) has a price.
ListTotal? listTotal(TodoList list, NumberContext ctx) {
  var any = false;
  var sum = Decimal.zero;
  var digits = 0;
  for (final item in list.items) {
    final price = parsePrice(item.text, ctx);
    if (price == null) continue;
    any = true;
    if (price.number.fractionDigits > digits) {
      digits = price.number.fractionDigits;
    }
    if (item.state == ItemState.done) {
      sum += quantityOf(item.text, ctx) * price.value;
    }
  }
  return any ? ListTotal(sum, digits) : null;
}

/// Formats [total] with the locale's separators and minus sign. Rounding is
/// half-up and affects the display only.
String formatTotal(ListTotal total, String? locale) {
  final format = decimalFormatFor(locale);
  final symbols = format.symbols;
  final rounded = total.sum.round(scale: total.fractionDigits);
  final negative = rounded < Decimal.zero;
  final fixed = rounded.abs().toStringAsFixed(total.fractionDigits);
  final dot = fixed.indexOf('.');
  final intDigits = dot < 0 ? fixed : fixed.substring(0, dot);
  final frac = dot < 0 ? '' : fixed.substring(dot + 1);
  final intFormatted = format.format(BigInt.parse(intDigits).toInt());
  return '${negative ? symbols.MINUS_SIGN : ''}$intFormatted'
      '${frac.isEmpty ? '' : '${symbols.DECIMAL_SEP}$frac'}';
}
