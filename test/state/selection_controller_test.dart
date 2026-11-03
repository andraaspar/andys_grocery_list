import 'package:andys_grocery_list/state/selection_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('selecting enters selection mode, deselecting the last leaves it', () {
    final s = SelectionController();
    expect(s.active, isFalse);
    s.select('a');
    expect(s.active, isTrue);
    s.toggle('b');
    expect(s.ids, {'a', 'b'});
    s.toggle('a');
    s.toggle('b');
    expect(s.active, isFalse);
  });

  test('retainOnly drops items that no longer exist', () {
    final s = SelectionController()
      ..select('a')
      ..select('b');
    var notified = 0;
    s.addListener(() => notified++);
    s.retainOnly({'b', 'c'});
    expect(s.ids, {'b'});
    s.retainOnly({'b'});
    expect(notified, 1);
  });

  test('clear leaves selection mode', () {
    final s = SelectionController()..select('a');
    s.clear();
    expect(s.active, isFalse);
    expect(s.count, 0);
  });
}
