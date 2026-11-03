/// The text controller behind every item field (plan §3, Android notes).
///
/// Android soft keyboards usually send no event for Backspace at the start of
/// a field or in an empty field. To see it anyway, the field's text always
/// starts with an invisible sentinel character (a zero-width space). The
/// controller hides it from the model: [modelText] and all model offsets
/// exclude it. When the sentinel gets deleted, that is Backspace at the start.
///
/// Every edit, whether from the IME, a hardware keyboard or the context menu,
/// arrives through the [value] setter, where it is classified:
/// - an inserted line break alone → [onEnter];
/// - inserted text that is not a plain paste (§5 rule 1) → [onPaste];
/// - the sentinel deleted → [onBackspaceAtStart];
/// - anything else → [onTextChanged].
///
/// For Enter, paste and Backspace the edit itself is not applied. The callback
/// runs the operation, and the caller then pushes the result back in with
/// [setModel].
library;

import 'package:flutter/widgets.dart';

import '../model/operations.dart' show isPlainPaste;

const sentinel = '​';

class SentinelController extends TextEditingController {
  SentinelController({String text = ''})
    : super.fromValue(
        TextEditingValue(
          text: sentinel + _clean(text),
          selection: TextSelection.collapsed(offset: _clean(text).length + 1),
        ),
      );

  /// Plain typing changed the text.
  void Function(String modelText)? onTextChanged;

  /// Enter was pressed. [modelText] is the field's text without the line
  /// break (it may include other edits that arrived in the same update), and
  /// [offset] is where the line break was.
  void Function(String modelText, int offset)? onEnter;

  /// Backspace at the start of the field.
  VoidCallback? onBackspaceAtStart;

  /// Structured text was pasted, replacing model range [start]..[end] of the
  /// current text.
  void Function(int start, int end, String pasted)? onPaste;

  bool _internal = false;

  /// The text without the sentinel.
  String get modelText => text.substring(_sentinelLength(text));

  /// The selection in model offsets.
  TextSelection get modelSelection {
    final s = selection;
    if (!s.isValid) return s;
    return s.copyWith(
      baseOffset: (s.baseOffset - 1).clamp(0, modelText.length),
      extentOffset: (s.extentOffset - 1).clamp(0, modelText.length),
    );
  }

  /// Replaces the text from the model, without running any callback.
  /// If [selection] (model offsets) is omitted, the current one is kept as far
  /// as it fits.
  void setModel(String modelText, {TextSelection? selection}) {
    final clean = _clean(modelText);
    final sel = selection ?? modelSelection;
    _setInternal(
      TextEditingValue(
        text: sentinel + clean,
        selection: sel.isValid
            ? _shift(sel, 1, clean.length + 1)
            : TextSelection.collapsed(offset: clean.length + 1),
      ),
    );
  }

  /// Sets the selection in model offsets.
  void setModelSelection(int start, [int? end]) {
    final len = modelText.length;
    _setInternal(
      value.copyWith(
        selection: TextSelection(
          baseOffset: start.clamp(0, len) + 1,
          extentOffset: (end ?? start).clamp(0, len) + 1,
        ),
        composing: TextRange.empty,
      ),
    );
  }

  void _setInternal(TextEditingValue v) {
    _internal = true;
    try {
      super.value = v;
    } finally {
      _internal = false;
    }
  }

  @override
  set value(TextEditingValue newValue) {
    if (_internal) {
      super.value = newValue;
      return;
    }
    final old = value;
    if (newValue.text == old.text) {
      super.value = _clampToSentinel(newValue);
      return;
    }

    final oldModel = modelText;
    final newModel = newValue.text.replaceAll(sentinel, '');
    final sentinelDeleted = !newValue.text.startsWith(sentinel);

    if (sentinelDeleted && newModel == oldModel) {
      _reject(old);
      onBackspaceAtStart?.call();
      return;
    }

    final edit = _diff(old, oldModel, newValue, newModel);
    final inserted = edit.inserted;
    final hasLineBreak = inserted.contains('\n') || inserted.contains('\r');

    if (hasLineBreak && _isSingleLineBreak(inserted)) {
      _reject(old);
      onEnter?.call(
        newModel.replaceRange(edit.start, edit.start + inserted.length, ''),
        edit.start,
      );
      return;
    }
    if (hasLineBreak || (inserted.length > 1 && !isPlainPaste(inserted))) {
      _reject(old);
      onPaste?.call(edit.start, edit.oldEnd, inserted);
      return;
    }

    super.value = _clampToSentinel(_withSentinel(newValue, newModel));
    onTextChanged?.call(newModel);
  }

  /// Keeps the old value but tells listeners anyway, so the field pushes the
  /// unchanged value back to the IME (which already applied the edit).
  void _reject(TextEditingValue old) {
    _setInternal(old.copyWith(composing: TextRange.empty));
    notifyListeners();
  }

  static bool _isSingleLineBreak(String s) =>
      s == '\n' || s == '\r\n' || s == '\r';

  /// Rebuilds [v] as sentinel + [model], mapping its offsets.
  TextEditingValue _withSentinel(TextEditingValue v, String model) {
    if (v.text == sentinel + model) return v;
    int map(int o) {
      if (o < 0) return o;
      final before = v.text.substring(0, o.clamp(0, v.text.length));
      return before.replaceAll(sentinel, '').length + 1;
    }

    return TextEditingValue(
      text: sentinel + model,
      selection: v.selection.isValid
          ? v.selection.copyWith(
              baseOffset: map(v.selection.baseOffset),
              extentOffset: map(v.selection.extentOffset),
            )
          : TextSelection.collapsed(offset: model.length + 1),
      composing: v.composing.isValid && !v.composing.isCollapsed
          ? TextRange(start: map(v.composing.start), end: map(v.composing.end))
          : TextRange.empty,
    );
  }

  /// Keeps the selection and the composing region from moving before the
  /// sentinel.
  TextEditingValue _clampToSentinel(TextEditingValue v) {
    final len = v.text.length;
    final sel = v.selection.isValid ? _shift(v.selection, 0, len) : v.selection;
    var composing = v.composing;
    if (composing.isValid && composing.start < 1) {
      composing = composing.end <= 1
          ? TextRange.empty
          : TextRange(start: 1, end: composing.end);
    }
    return v.copyWith(selection: sel, composing: composing);
  }

  /// Shifts [s] by [by] and clamps both ends to 1..[max].
  static TextSelection _shift(TextSelection s, int by, int max) => s.copyWith(
    baseOffset: (s.baseOffset + by).clamp(1, max),
    extentOffset: (s.extentOffset + by).clamp(1, max),
  );

  static int _sentinelLength(String s) => s.startsWith(sentinel) ? 1 : 0;

  static String _clean(String s) => s.replaceAll(sentinel, '');
}

/// A single replacement: model range [start]..[oldEnd] became [inserted].
typedef _Edit = ({int start, int oldEnd, String inserted});

/// Finds what changed between [oldModel] and [newModel]. The common prefix is
/// bounded by the old selection start, and the common suffix by the text
/// after the new cursor, so a repeated character at the edge of an insertion
/// is attributed correctly.
_Edit _diff(
  TextEditingValue oldValue,
  String oldModel,
  TextEditingValue newValue,
  String newModel,
) {
  var maxPrefix = oldModel.length < newModel.length
      ? oldModel.length
      : newModel.length;
  if (oldValue.selection.isValid) {
    final s = (oldValue.selection.start - 1).clamp(0, oldModel.length);
    if (s < maxPrefix) maxPrefix = s;
  }
  var p = 0;
  while (p < maxPrefix && oldModel.codeUnitAt(p) == newModel.codeUnitAt(p)) {
    p++;
  }

  var maxSuffix = (oldModel.length - p) < (newModel.length - p)
      ? oldModel.length - p
      : newModel.length - p;
  if (newValue.selection.isValid) {
    final cursor = newValue.text
        .substring(0, newValue.selection.end.clamp(0, newValue.text.length))
        .replaceAll(sentinel, '')
        .length;
    final after = newModel.length - cursor;
    if (after >= 0 && after < maxSuffix) maxSuffix = after;
  }
  var s = 0;
  while (s < maxSuffix &&
      oldModel.codeUnitAt(oldModel.length - 1 - s) ==
          newModel.codeUnitAt(newModel.length - 1 - s)) {
    s++;
  }

  return (
    start: p,
    oldEnd: oldModel.length - s,
    inserted: newModel.substring(p, newModel.length - s),
  );
}
