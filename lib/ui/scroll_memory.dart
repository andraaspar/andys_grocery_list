import '../storage/settings.dart';

/// A row's place in the document: its list index and, within the list, -1
/// for the header, 0…n-1 for the items and n for the total line. The blank
/// space at the end is `(lists.length, -1)`.
typedef RowPosition = ({int list, int item});

int compareRowPositions(RowPosition a, RowPosition b) =>
    a.list != b.list ? a.list.compareTo(b.list) : a.item.compareTo(b.item);

/// The remembered scroll position (plan §3, Scrolling): the first visible row
/// and how many pixels of it are scrolled past. Unlike a raw pixel offset, it
/// survives text wrapping differently.
class ScrollAnchor {
  const ScrollAnchor(this.row, this.offset);

  final RowPosition row;
  final double offset;

  String encode() => '${row.list},${row.item},${offset.toStringAsFixed(1)}';

  static ScrollAnchor? decode(String? s) {
    final parts = s?.split(',');
    if (parts == null || parts.length != 3) return null;
    final list = int.tryParse(parts[0]);
    final item = int.tryParse(parts[1]);
    final offset = double.tryParse(parts[2]);
    if (list == null || item == null || offset == null) return null;
    return ScrollAnchor((list: list, item: item), offset);
  }

  /// Finds the row to jump to among [rows] (in display order). If the
  /// anchor's row is gone, uses the closest earlier row, without the pixel
  /// offset.
  ({int index, double offset}) resolve(List<RowPosition> rows) {
    var best = 0;
    for (var i = 0; i < rows.length; i++) {
      final c = compareRowPositions(rows[i], row);
      if (c == 0) return (index: i, offset: offset);
      if (c > 0) break;
      best = i;
    }
    return (index: best, offset: 0);
  }

  @override
  bool operator ==(Object other) =>
      other is ScrollAnchor && other.row == row && other.offset == offset;

  @override
  int get hashCode => Object.hash(row, offset);

  @override
  String toString() => 'ScrollAnchor($row, $offset)';
}

/// Saves and loads the scroll anchor of one file.
class ScrollMemory {
  ScrollMemory(this._settings, this._uri);

  final Settings _settings;
  final String _uri;

  ScrollAnchor? load() => ScrollAnchor.decode(_settings.scrollAnchor(_uri));

  Future<void> save(ScrollAnchor anchor) =>
      _settings.setScrollAnchor(_uri, anchor.encode());
}
