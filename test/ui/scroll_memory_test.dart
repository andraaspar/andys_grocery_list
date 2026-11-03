import 'package:andys_grocery_list/ui/scroll_memory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encode and decode round-trip', () {
    const a = ScrollAnchor((list: 2, item: -1), 13.5);
    expect(ScrollAnchor.decode(a.encode()), a);
    expect(ScrollAnchor.decode(null), isNull);
    expect(ScrollAnchor.decode('1,x,3'), isNull);
  });

  const rows = <RowPosition>[
    (list: 0, item: -1),
    (list: 0, item: 0),
    (list: 0, item: 1),
    (list: 0, item: 2), // Total line.
    (list: 1, item: -1),
    (list: 1, item: 0),
    (list: 2, item: -1), // Blank space.
  ];

  test('resolves an existing row with its offset', () {
    expect(const ScrollAnchor((list: 1, item: 0), 7).resolve(rows), (
      index: 5,
      offset: 7.0,
    ));
  });

  test('a deleted row falls back to the closest earlier row', () {
    expect(const ScrollAnchor((list: 1, item: 3), 7).resolve(rows), (
      index: 5,
      offset: 0.0,
    ));
    expect(const ScrollAnchor((list: 0, item: 5), 7).resolve(rows), (
      index: 3,
      offset: 0.0,
    ));
    expect(const ScrollAnchor((list: 9, item: 0), 7).resolve(rows), (
      index: 6,
      offset: 0.0,
    ));
  });
}
