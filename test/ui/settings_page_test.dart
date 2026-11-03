import 'package:andys_grocery_list/state/settings_controller.dart';
import 'package:andys_grocery_list/ui/settings_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fileDisplayName shows the decoded file name', () {
    expect(
      fileDisplayName(
        'content://com.android.externalstorage.documents/document/'
        'primary%3ASync%2Fgroceries.md',
      ),
      'groceries.md',
    );
    expect(fileDisplayName('content://todo.md'), 'todo.md');
    expect(fileDisplayName('content://p/document/1234'), '1234');
  });

  test('sampleNumber uses the locale separators', () {
    expect(sampleNumber('en_US'), '-1,234.56');
    expect(sampleNumber('de'), '-1.234,56');
  });

  test('selectableLocales are sorted and use ASCII digits', () {
    final locales = selectableLocales();
    expect(locales, containsAll(['en_US', 'de', 'de_CH', 'hu', 'fr']));
    expect(locales, isNot(contains('ar_EG')));
    expect(locales, orderedEquals([...locales]..sort()));
  });
}
