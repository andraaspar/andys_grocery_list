import 'package:andys_grocery_list/app.dart';
import 'package:andys_grocery_list/ui/home_page.dart';
import 'package:andys_grocery_list/ui/sentinel_controller.dart';
import 'package:andys_grocery_list/ui/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'storage/fake_storage.dart';

const uri = 'content://todo.md';

final list = find.byType(SuperListView);

Finder itemField(String text) => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      w.controller is SentinelController &&
      (w.controller! as SentinelController).modelText == text,
);

Future<void> pumpApp(WidgetTester tester, FakeStorage storage) async {
  await tester.pumpWidget(App(storage: storage));
  await tester.pumpAndSettle();
}

/// Restarts the app: tears the widget tree down and builds a fresh one.
Future<void> restart(WidgetTester tester, FakeStorage storage) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  await pumpApp(tester, storage);
}

void pause(WidgetTester tester) {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

void resume(WidgetTester tester) {
  for (final s in [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}

String manyItems(int n, {String prefix = ''}) =>
    '# L\n${[for (var i = 0; i < n; i++) '- [ ] ${prefix}Item $i'].join('\n')}\n';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('first launch shows the welcome page; creating a file opens it', (
    tester,
  ) async {
    final storage = FakeStorage()..nextCreate = uri;
    await pumpApp(tester, storage);
    expect(find.byType(WelcomePage), findsOneWidget);

    await tester.tap(find.text('Create new file'));
    await tester.pumpAndSettle();
    expect(find.byType(HomePage), findsOneWidget);
    expect(find.text('TODO'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('fileUri'), uri);
  });

  testWidgets('opening an existing file shows it', (tester) async {
    final storage = FakeStorage({uri: '# Groceries\n- [ ] Milk\n'})
      ..nextOpen = uri;
    await pumpApp(tester, storage);
    await tester.tap(find.text('Open existing file'));
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsOneWidget);
    expect(itemField('Milk'), findsOneWidget);
  });

  testWidgets('a cancelled picker stays on the welcome page', (tester) async {
    await pumpApp(tester, FakeStorage());
    await tester.tap(find.text('Open existing file'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomePage), findsOneWidget);
  });

  testWidgets('the remembered file opens directly', (tester) async {
    SharedPreferences.setMockInitialValues({'fileUri': uri});
    await pumpApp(tester, FakeStorage({uri: '# Work\n- [ ] Report\n'}));
    expect(find.byType(HomePage), findsOneWidget);
    expect(itemField('Report'), findsOneWidget);
  });

  testWidgets('a lost permission shows the welcome page', (tester) async {
    SharedPreferences.setMockInitialValues({'fileUri': uri});
    final storage = FakeStorage({uri: '# Work\n'})..permitted.clear();
    await pumpApp(tester, storage);
    expect(find.byType(WelcomePage), findsOneWidget);
    expect(find.textContaining('Access to the file was lost'), findsOneWidget);
  });

  testWidgets('edits are saved when the app is paused', (tester) async {
    SharedPreferences.setMockInitialValues({'fileUri': uri});
    final storage = FakeStorage({uri: '# L\n- [ ] Milk\n'});
    await pumpApp(tester, storage);
    await tester.tap(find.byIcon(Icons.check_box_outline_blank));
    await tester.pump();
    pause(tester);
    await tester.pump();
    expect(storage.files[uri], '# L\n- [x] Milk\n');
  });

  testWidgets('an external change is picked up on resume', (tester) async {
    SharedPreferences.setMockInitialValues({'fileUri': uri});
    final storage = FakeStorage({uri: '# L\n- [ ] Milk\n'});
    await pumpApp(tester, storage);
    pause(tester);
    storage.externalWrite(uri, '# L\n- [ ] Eggs\n');
    resume(tester);
    await tester.pumpAndSettle();
    expect(itemField('Eggs'), findsOneWidget);
  });

  testWidgets('the scroll position is restored after a restart', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'fileUri': uri});
    final storage = FakeStorage({uri: manyItems(60)});
    await pumpApp(tester, storage);

    await tester.drag(list, const Offset(0, -1000));
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(list).dy;
    final anchored = _firstVisibleItem(tester, top);
    final before = tester.getTopLeft(itemField(anchored)).dy;
    pause(tester);
    await tester.pump();

    await restart(tester, storage);
    expect(itemField(anchored), findsOneWidget);
    expect(tester.getTopLeft(itemField(anchored)).dy, closeTo(before, 1));
  });

  testWidgets('an external reload keeps the same row in view', (tester) async {
    SharedPreferences.setMockInitialValues({'fileUri': uri});
    final storage = FakeStorage({uri: manyItems(60)});
    await pumpApp(tester, storage);

    await tester.drag(list, const Offset(0, -1000));
    await tester.pumpAndSettle();
    final top = tester.getTopLeft(list).dy;
    final anchored = _firstVisibleItem(tester, top);
    final before = tester.getTopLeft(itemField(anchored)).dy;

    // Ten new items at the top push everything down by ten rows.
    final extra = [for (var i = 0; i < 10; i++) '- [ ] New $i'].join('\n');
    storage.externalWrite(
      uri,
      manyItems(60).replaceFirst('# L\n', '# L\n$extra\n'),
    );
    pause(tester);
    resume(tester);
    await tester.pumpAndSettle();
    expect(itemField(anchored), findsOneWidget);
    expect(tester.getTopLeft(itemField(anchored)).dy, closeTo(before, 1));
  });
}

/// The text of the first item row whose top is at or below [top].
String _firstVisibleItem(WidgetTester tester, double top) {
  final fields = tester
      .widgetList<TextField>(find.byType(TextField))
      .where((f) => f.controller is SentinelController)
      .toList();
  String? best;
  var bestY = double.infinity;
  for (final f in fields) {
    final text = (f.controller! as SentinelController).modelText;
    final y = tester.getTopLeft(itemField(text)).dy;
    if (y >= top && y < bestY) {
      best = text;
      bestY = y;
    }
  }
  return best!;
}
