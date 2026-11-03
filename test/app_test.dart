import 'package:andys_grocery_list/app.dart';
import 'package:andys_grocery_list/ui/home_page.dart';
import 'package:andys_grocery_list/ui/item_row.dart';
import 'package:andys_grocery_list/ui/list_header.dart';
import 'package:andys_grocery_list/ui/sentinel_controller.dart';
import 'package:andys_grocery_list/ui/settings_page.dart';
import 'package:andys_grocery_list/ui/welcome_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

import 'storage/fake_storage.dart';

/// An icon in the list rows, not in the usage help below them.
Finder rowIcon(IconData icon) => find.descendant(
  of: find.byWidgetPredicate((w) => w is ItemRow || w is ListHeader),
  matching: find.byIcon(icon),
);

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
    expect(find.text('Your brand new list'), findsOneWidget);
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
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text(uri.substring(uri.lastIndexOf('/') + 1)),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tapping the title switches files', (tester) async {
    SharedPreferences.setMockInitialValues({'fileUri': uri});
    const other = 'content://other.md';
    final storage = FakeStorage({
      uri: '# L\n- [ ] Milk\n',
      other: '# Work\n- [ ] Report\n',
    })..nextOpen = other;
    await pumpApp(tester, storage);

    await tester.tap(find.byTooltip('Switch file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open existing file'));
    await tester.pumpAndSettle();
    expect(itemField('Report'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('other.md')),
      findsOneWidget,
    );

    // The file before is now a recent file.
    await tester.tap(find.byTooltip('Switch file'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('todo.md'));
    await tester.pumpAndSettle();
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
    await tester.tap(rowIcon(Icons.check_box_outline_blank));
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

  testWidgets('the help remembers being collapsed', (tester) async {
    SharedPreferences.setMockInitialValues({'fileUri': uri});
    await pumpApp(tester, FakeStorage({uri: '# L\n- [ ] Milk\n'}));
    await tester.tap(find.text('How to use'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('helpExpanded'), isFalse);
  });

  group('settings', () {
    Future<void> openSettings(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
    }

    Future<void> pickLocale(
      WidgetTester tester,
      String search,
      String tap,
    ) async {
      await tester.tap(find.text('Number format'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), search);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(ListTile), matching: find.text(tap)),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('opens from the overflow menu and shows the file', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'fileUri': 'content://x/document/primary%3ASync%2Fgroceries.md',
      });
      await pumpApp(
        tester,
        FakeStorage({
          'content://x/document/primary%3ASync%2Fgroceries.md': '# L\n',
        }),
      );
      await openSettings(tester);
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('groceries.md'), findsOneWidget);
      expect(
        find.textContaining('Same as phone (English (United States))'),
        findsOneWidget,
      );
    });

    testWidgets('spacing and text size change the rows and persist', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'fileUri': uri});
      final storage = FakeStorage({uri: '# L\n- [ ] Milk\n'});
      await pumpApp(tester, storage);
      double rowHeight() => tester.getSize(find.byType(ItemRow)).height;
      double textHeight() => tester.getSize(itemField('Milk')).height;
      Future<void> pick(String setting, String option) async {
        await openSettings(tester);
        await tester.tap(find.text(setting));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(SimpleDialog),
            matching: find.text(option),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(option), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }

      // The default is the dense layout at the normal size: a line 15%
      // larger than the standard 24 px (text layout rounds it to 28), 4 px
      // above and below.
      expect(textHeight(), closeTo(24 * 1.15, 0.5));
      expect(rowHeight(), textHeight() + 8);

      await pick('Text size', 'Small');
      expect(textHeight(), 24);
      expect(rowHeight(), 32);

      await pick('Spacing', 'Roomy');
      expect(rowHeight(), 48);
      expect(textHeight(), 24);

      await pick('Text size', 'Larger');
      expect(textHeight(), 36);
      expect(rowHeight(), 60);
      // The state icon grows with the text and stays on its first line.
      final icon = tester.getRect(rowIcon(Icons.check_box_outline_blank));
      expect(icon.height, 36);
      expect(icon.center.dy, tester.getRect(itemField('Milk')).center.dy);

      // So do the app bar's icons, and the bar with them.
      expect(tester.getSize(find.byIcon(Icons.settings_outlined)).height, 36);
      expect(tester.getSize(find.byType(AppBar)).height, 68);
      // The last one is 16 px from the edge at 24 px, so 24 px at 36 px.
      expect(
        tester.getSize(find.byType(AppBar)).width -
            tester.getRect(find.byIcon(Icons.settings_outlined)).right,
        24,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('spacing'), 'roomy');
      expect(prefs.getString('textSize'), 'larger');
      await restart(tester, storage);
      expect(rowHeight(), 60);
    });

    testWidgets('changing the locale re-formats totals, not the file', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'fileUri': uri});
      const content = '# L\n- [x] Machine 1234.50\n';
      final storage = FakeStorage({uri: content});
      await pumpApp(tester, storage);
      expect(find.text('Total: 1,234.50'), findsOneWidget);

      await openSettings(tester);
      await pickLocale(tester, 'german', 'German');
      expect(find.textContaining('German · '), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('locale'), 'de');

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Total: 1.234,50'), findsOneWidget);
      pause(tester);
      await tester.pump();
      expect(storage.files[uri], content);
      expect(storage.writes, isEmpty);

      // Back to the system default.
      resume(tester);
      await tester.pumpAndSettle();
      await openSettings(tester);
      await pickLocale(
        tester,
        'phone',
        'Same as phone (English (United States))',
      );
      expect(prefs.getString('locale'), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Total: 1,234.50'), findsOneWidget);
    });

    testWidgets('the chosen locale is used after a restart', (tester) async {
      SharedPreferences.setMockInitialValues({'fileUri': uri, 'locale': 'de'});
      await pumpApp(tester, FakeStorage({uri: '# L\n- [x] A 1234.50\n'}));
      expect(find.text('Total: 1.234,50'), findsOneWidget);
    });

    testWidgets('Change file opens another file and returns home', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'fileUri': uri});
      const other = 'content://other.md';
      final storage = FakeStorage({
        uri: '# L\n- [ ] Milk\n',
        other: '# Work\n- [ ] Report\n',
      })..nextOpen = other;
      await pumpApp(tester, storage);

      // An unsaved edit to the old file is written before switching.
      await tester.tap(rowIcon(Icons.check_box_outline_blank));
      await tester.pump();
      await openSettings(tester);
      await tester.tap(find.text('Change file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open existing file'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsNothing);
      expect(itemField('Report'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('other.md'),
        ),
        findsOneWidget,
      );
      expect(storage.files[uri], '# L\n- [x] Milk\n');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fileUri'), other);
    });

    group('recent files', () {
      const other = 'content://other.md';

      Future<void> openChangeFile(WidgetTester tester) async {
        await openSettings(tester);
        await tester.tap(find.text('Change file'));
        await tester.pumpAndSettle();
      }

      testWidgets('lists the previous file and reopens it', (tester) async {
        SharedPreferences.setMockInitialValues({'fileUri': uri});
        final storage = FakeStorage({
          uri: '# L\n- [ ] Milk\n',
          other: '# Work\n- [ ] Report\n',
        })..nextOpen = other;
        await pumpApp(tester, storage);
        await openChangeFile(tester);
        // Only the current file so far, which isn't listed.
        expect(find.text('Recent files'), findsNothing);
        await tester.tap(find.text('Open existing file'));
        await tester.pumpAndSettle();

        await openChangeFile(tester);
        expect(find.text('Recent files'), findsOneWidget);
        expect(find.text(uri.substring(uri.lastIndexOf('/') + 1)), findsOne);
        await tester.tap(find.text(uri.substring(uri.lastIndexOf('/') + 1)));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsPage), findsNothing);
        expect(itemField('Milk'), findsOneWidget);
      });

      testWidgets('can be removed, which releases the file', (tester) async {
        SharedPreferences.setMockInitialValues({
          'fileUri': uri,
          'recentFiles': [uri, other],
        });
        final storage = FakeStorage({
          uri: '# L\n- [ ] Milk\n',
          other: '# Work\n- [ ] Report\n',
        });
        await pumpApp(tester, storage);
        await openChangeFile(tester);
        await tester.tap(find.byTooltip('Remove from recent files'));
        await tester.pumpAndSettle();
        expect(find.text('other.md'), findsNothing);
        expect(storage.released, [other]);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('recentFiles'), [uri]);
      });

      testWidgets('files that no longer exist are forgotten', (tester) async {
        SharedPreferences.setMockInitialValues({
          'fileUri': uri,
          'recentFiles': [uri, 'content://gone.md', other],
        });
        final storage = FakeStorage({
          uri: '# L\n- [ ] Milk\n',
          other: '# Work\n- [ ] Report\n',
        });
        await pumpApp(tester, storage);
        await openChangeFile(tester);
        expect(find.text('gone.md'), findsNothing);
        expect(find.text('other.md'), findsOneWidget);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getStringList('recentFiles'), [uri, other]);
      });
    });

    testWidgets('a cancelled Change file stays in Settings', (tester) async {
      SharedPreferences.setMockInitialValues({'fileUri': uri});
      await pumpApp(tester, FakeStorage({uri: '# L\n- [ ] Milk\n'}));
      await openSettings(tester);
      await tester.tap(find.text('Change file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create new file'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
    });

    testWidgets('a file that cannot be opened keeps the current one', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'fileUri': uri});
      final storage = FakeStorage({uri: '# L\n- [ ] Milk\n'})
        ..nextOpen = 'content://gone.md';
      await pumpApp(tester, storage);
      await openSettings(tester);
      await tester.tap(find.text('Change file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open existing file'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(
        find.textContaining('Access to the file was lost'),
        findsOneWidget,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(itemField('Milk'), findsOneWidget);
    });
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
