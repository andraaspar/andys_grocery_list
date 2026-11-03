import 'dart:ui';

import 'package:andys_grocery_list/app_name.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('app name follows the system language', () {
    expect(appNameFor(const Locale('hu', 'HU')), 'Andris Bevlistája');
    expect(appNameFor(const Locale('en', 'US')), "Andy's Grocery List");
    expect(appNameFor(const Locale('de')), "Andy's Grocery List");
    expect(appNameFor(null), "Andy's Grocery List");
  });
}
