import 'package:flutter/foundation.dart';

/// Which items are selected in selection mode (plan §6).
///
/// Selection mode is active while at least one item is selected: deselecting
/// the last one leaves it.
class SelectionController extends ChangeNotifier {
  final _ids = <String>{};

  bool get active => _ids.isNotEmpty;
  int get count => _ids.length;
  Set<String> get ids => Set.unmodifiable(_ids);
  bool contains(String itemId) => _ids.contains(itemId);

  /// Enters selection mode with [itemId] selected, or adds it.
  void select(String itemId) {
    if (_ids.add(itemId)) notifyListeners();
  }

  void toggle(String itemId) {
    if (!_ids.remove(itemId)) _ids.add(itemId);
    notifyListeners();
  }

  /// Leaves selection mode.
  void clear() {
    if (_ids.isEmpty) return;
    _ids.clear();
    notifyListeners();
  }

  /// Drops ids of items that no longer exist (deleted elsewhere, reloaded).
  void retainOnly(Set<String> existing) {
    final before = _ids.length;
    _ids.retainWhere(existing.contains);
    if (_ids.length != before) notifyListeners();
  }
}
