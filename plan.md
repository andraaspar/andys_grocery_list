# Andy's Grocery List — Plan

**Andy's Grocery List** is a Flutter app for Android for managing TODO lists. Each item is in one of three states: **NEW**, **DONE** or **FAILED**. Everything is stored in one Markdown file chosen by the user, which can be synced between devices with Syncthing.

## 0. Identity

| What | Value |
|---|---|
| Display name, English (default) | `Andy's Grocery List` |
| Display name, Hungarian | `Andris Bevlistája` |
| Organization (reverse domain of `parditka.hu`) | `hu.parditka` |
| Dart package name (`pubspec.yaml` `name:`) | `andys_grocery_list` |
| Android `applicationId` / `namespace` | `hu.parditka.andys_grocery_list` |
| Kotlin package | `hu.parditka.andys_grocery_list` |
| Platform channel prefix | `hu.parditka.andys_grocery_list/…` |

- The project is created in this folder with:
  `flutter create --org hu.parditka --project-name andys_grocery_list --platforms=android .`
- **Launcher label (localized by Android):**
  - `AndroidManifest.xml` uses `android:label="@string/app_name"`.
  - `android/app/src/main/res/values/strings.xml`: `<string name="app_name">Andy\'s Grocery List</string>`. The apostrophe must be escaped in Android string resources.
  - `android/app/src/main/res/values-hu/strings.xml`: `<string name="app_name">Andris Bevlistája</string>`. Save the file as UTF-8.
  - Android picks the right one from the phone's system language. Any language other than Hungarian gets the English name.
- **Name inside the app** (app bar, welcome screen, task switcher):
  - `lib/app_name.dart` returns `Andris Bevlistája` when the system language code is `hu`, and `Andy's Grocery List` otherwise.
  - It is used through `MaterialApp.onGenerateTitle` and in the app bar, and is recalculated on `didChangeLocales`.
  - It follows the **system** language, like the launcher, not the number locale from Settings (§7). That way the name inside the app always matches the launcher icon.
  - The rest of the interface stays English for now. If it is localized later, this moves into the normal `flutter gen-l10n` ARB files.
- Dart imports use `package:andys_grocery_list/…`.

---

## 1. File format

One file holds any number of lists.

```markdown
# Groceries
- [ ] 3x Milk 1.29
- [x] Bread 2,49
- [x] 1.5x Cheese 8.00
- [x] Coffee machine 1.299,00
- [x] Coupon -1
- [x] FAILED 2x Fresh basil 0.99

# Work
- [ ] Write report
```

| Element      | Prefix          |
|--------------|-----------------|
| List name    | `# `            |
| NEW item     | `- [ ] `        |
| DONE item    | `- [x] `        |
| FAILED item  | `- [x] FAILED ` |
| Quantity     | `<n>x ` right after the state prefix (optional, see §2) |
| Unit price   | ` <number>` at the end of the line (optional, see §2) |

### Parsing rules (one parser for both files and pasted text)
- Read line by line. Both `\n` and `\r\n` line endings work.
- A line starting with `# ` starts a new list. The rest of the line is the list name.
- Item prefixes are checked in this order: `- [x] FAILED `, then `- [x] ` / `- [X] `, then `- [ ] `.
- The text after the state prefix becomes the item's text, unchanged. The quantity and the price are part of that text (§2).
- Lenient fallback, so no data is ever lost:
  - `- text` or `* text` → a NEW item.
  - Any other non-blank line → a NEW item whose text is the line.
  - Blank lines are ignored.
- Items before the first `# ` header:
  - **In a file:** they go into a list with an empty name.
  - **In a paste:** they become "loose items" (§5).
- An empty file → one list named `TODO` with one empty item.
- After parsing, the invariants from §2 are applied, so a list with no items gets one empty item.

### Serialization rules
- Each list is written as `# name`, then one line per item in the canonical format.
- Lists are separated by a blank line. The file ends with a newline.
- Empty items are written as `- [ ] `, with the trailing space, so they survive a save and reload.
- A quantity prefix whose value is exactly 1 (`1x `, `1.0x `, `1,00x `) is removed when writing, because 1 is implied.
- Apart from that, item text is never reformatted: numbers stay exactly as the user typed them. Locale formatting is only used for displaying the total.
- The list total (§4) is calculated in memory and never written to the file.
- The output is always canonical. Variants written by hand get normalized on the next save.
- Known edge case: a DONE item whose text starts with `FAILED ` can't be told apart from a FAILED item. We accept this.

---

## 2. Data model and invariants

```
TodoDocument { List<TodoList> lists }
TodoList     { String id; String name; List<TodoItem> items }
TodoItem     { String id; ItemState state; String text }
enum ItemState { newItem, done, failed }
```

- The `id`s exist only in memory. They keep text controllers and focus nodes stable across rebuilds and are never written to the file.
- **Invariant A:** there is always at least one list.
- **Invariant B:** every list has at least one item. If an operation would leave a list with no items, or creates one with none, one empty NEW item is added. That item behaves like any other: it can be edited, have its state changed and be selected, and it is saved to the file.
- Item text and list names never contain line breaks. Incoming `\n` / `\r` characters are handled by the split or paste logic. In list names they are replaced with spaces.

### Numbers (locale-aware, "natural" parsing)
- Parsing and display both use the configured **locale** (§7). By default this is the system locale.
- The parser receives a `NumberContext { decimalSep, groupSep }`, taken from the locale's `intl` number symbols.
- **Number token:**
  - An optional sign: `-`, or the Unicode minus `−`.
  - Digits, with optional thousands separators and an optional decimal part.
  - Digits are required on both sides of a decimal point, so `.5` and `5.` are not numbers.
- **Separator characters:**
  - `.` and `,` can be either the decimal point or the thousands separator. The rules below decide which.
  - `'`, `’`, the no-break space (U+00A0) and the narrow no-break space (U+202F) are only ever thousands separators.
  - A **regular space is never a thousands separator**, because spaces separate words. Write `1299` or `1.299`, not `1 299`.
- **Rules for `.` and `,`** (the first one that applies wins):
  1. **Both `.` and `,` appear:** the one that comes **last** is the decimal point. `1.234,50` → 1234.5. `1,234.50` → 1234.5.
  2. **One of them appears more than once:** it is the thousands separator. `1.234.567` → 1234567.
  3. **One of them appears exactly once:**
     - If it is the locale's decimal separator, it is the decimal point.
     - If it is the locale's thousands separator **and** is followed by exactly 3 digits, it is the thousands separator. With an English locale, `1,234` → 1234. With a German locale, `1.234` → 1234.
     - Otherwise it is the decimal point. This keeps the earlier behaviour that both `.` and `,` work: `2,49` → 2.49 in English, and `1.5` → 1.5 in German.
- **Grouping must be well formed:** the first group has 1–3 digits, every later group has exactly 3, and there is no grouping after the decimal point. Otherwise the token is not a number (`12.34.5`, `1,23,456`).
- All arithmetic is done in **exact decimal** with the `decimal` package, never `double`, so `0.1 + 0.2` and `1.5 × 1.99` come out exactly right.
- Accepted consequence: devices set to different locales can read the one truly ambiguous form differently: a single separator followed by exactly 3 digits (`1,234` / `1.234`). Every other form gives the same value everywhere.

### Quantity
- The quantity is **part of the item text**. It is an unsigned number token (§2 Numbers) at the start of the text, immediately followed by `x` and then a space or the end of the text.
  - Examples: `3x Milk` → 3. `1,5x Cheese` → 1.5. `0.25x Butter` → 0.25. `Milk` → 1 (implied).
  - It stays in the text rather than in a separate field. That way it can be seen and edited directly in the text field, and split, merge, copy and paste all handle it automatically.
- Helpers in `lib/model/amounts.dart`:
  - `parseQuantity(text) -> (value, start, end)`
  - `incrementQuantity(text) -> (text, numberStart, numberEnd)`
- Normalizing a quantity of 1: if the value is exactly 1 (`1x`, `1.0x`, `1,00x`), the prefix is removed when the item **loses focus** and when the file is written.
  - It is **not** removed while the user is typing, otherwise typing `1` on the way to `10` or `1.5` would break.
- Accepted consequences:
  - Text that happens to start with a number followed by `x`, such as `2x faster`, is read as a quantity.
  - `0x` is a valid quantity of zero, and contributes 0 to the total.

### Unit price
- The price is also **part of the item text**. It is a signed number token (§2 Numbers) at the **end** of the text, preceded by whitespace or by the start of the text.
  - Trailing whitespace after the number is ignored (`Milk 1.29 ` still has a price). Any other visible character after it means there is no price.
  - Examples (English locale): `Milk 1.29` → 1.29. `Bread 2,49` → 2.49. `Machine 1.299,00` → 1299. `TV 1,299.00` → 1299. `Coupon -1` → −1. `3x Milk 1.29` → quantity 3, price 1.29. `Milk` → no price.
  - Prices **can be negative** (a leading `-` or `−`), for things like discounts and coupons.
  - A trailing token that is not exactly a number is not a price: `Room 12b`, `v2`, `12.34.5`, `5€`.
  - A trailing `3x` is the quantity, not a price. In `2x` alone, the `2` is the quantity.
- Helper: `parsePrice(text) -> (value, start, end)?`.
- Accepted consequence: any item that ends in a number gets a price, for example `Bus 42`. If that turns out to be annoying, we can add an escape later (see §13).

### Line total
- `lineTotal(item) = quantity × price` if the item has a price, otherwise none.
- `listTotal(list) = Σ lineTotal` over the list's **DONE** items that have a price. NEW and FAILED items are not counted.

Every edit operation is a **pure function** on the model, in `lib/model/operations.dart`. Each one returns the new document plus the cursor target `(itemId, selectionStart, selectionEnd)`. Invariants are applied in a single `normalize()` step at the end of every operation.

---

## 3. Editing behaviour

Each item is a row:

```
[state icon]  [text field that wraps, any length]  [+]
```

The text field uses `maxLines: null`, so all of the text is shown no matter how long it is. The text is still one logical line.

### Keyboard operations

| Action | Where | Result |
|---|---|---|
| Enter | at the end of a non-empty line | Insert an empty NEW item below and focus it. |
| Enter | in the middle of a line | Split the item. The text before the cursor stays, along with the item's state. The text after the cursor becomes a new **NEW** item below. Focus goes to the start of the new item. |
| Enter | at the start of a non-empty line | Insert an empty NEW item above. The current text keeps its state and the focus. |
| Enter | on an **empty** item | **Create a new list.** The empty item is removed, and every item below it moves into a new list, inserted right after the current one. Focus goes to the new list's **name field** with the default name `New list` selected (§4). If nothing was below, the new list gets one empty item. If the current list is left with no items, it gets one empty item. |
| Backspace | at the start of a line that isn't the first item of its list | Merge with the previous item. The previous item keeps its state, the text becomes `prev + current`, and the cursor is placed at the join. If the current item is empty, this simply deletes it ("delete by keyboard"). |
| Backspace | at the start of the **first item** of a list (not the first list) | **Merge this list into the previous list.** The items are appended to the previous list, which keeps its name. If the previous list's only item was empty, that item is dropped. The cursor stays at the start of the same item. |
| Backspace | at the start of the first item of the first list | Does nothing. |
| Paste | anywhere in an item's text field | See §5. |

### The + (quantity) button
- There is a small **+** icon button at the right end of every item row.
- Pressing it:
  1. Adds 1 to the quantity: `Milk` → `2x Milk`, `2x Milk` → `3x Milk`, `1,5x Cheese` → `2,5x Cheese`. An empty item becomes `2x `.
     - Decimal quantities keep their separator (`,` or `.`) and their number of decimal places.
  2. Focuses that item's text field, opening the keyboard if needed.
  3. **Selects the whole number** (for example `3` in `3x Milk`, or `2,5` in `2,5x Cheese`), so typing replaces it right away. The selection is set in a post-frame callback, after the controller text has been updated.
- Pressing + several times in a row keeps the number selected each time, so a quick `+ + +` followed by typing works smoothly.
- The quantity prefix and the trailing price are drawn with a subtle emphasis (for example semibold or the accent colour for the quantity, and a tabular-figure style for the price), using the controller's `buildTextSpan`. They are still plain text that can be edited.
- In selection mode (§6), the + buttons are hidden.
- Out of scope for now: decrementing. The user can type a smaller number instead, or delete the prefix to get back to 1.

### Android implementation notes (the hard part)
- **Enter:** use `keyboardType: TextInputType.multiline` with `maxLines: null`, so the keyboard shows an Enter key. In the controller listener, detect an inserted `\n`, remove it, and run the split operation at that offset.
- **Backspace at the start or in an empty field:** Android soft keyboards usually send *no* event in these cases. Workaround: every field's text starts with an invisible **sentinel character**, a zero-width space (U+200B).
  - The controller hides the sentinel from the model and keeps the selection from moving before it.
  - All model offsets, including the quantity selection, are converted by +1 for the sentinel.
  - When the sentinel gets deleted, that means Backspace at the start: restore the sentinel and run the merge operation.
  - Hardware keyboards are handled through `Focus.onKeyEvent` (`backspace`, `enter`).
- Each item has one `TextEditingController` and one `FocusNode`, keyed by item id. They are disposed when the item disappears.
- After an operation, the target field is focused and its selection set in a post-frame callback.
- One scrolling list of rows: list headers, items and list footers. The focused item is kept visible (see Scrolling below).

### Scrolling
- **Room below the last item.** The scroll view ends with blank space as tall as the viewport minus one row. That means even the last item of the last list can be scrolled all the way to the top of the screen.
  - A `LayoutBuilder` recalculates this space whenever the viewport changes size, for example when the keyboard opens or the phone rotates.
  - Tapping the blank space focuses the last item of the last list, with the cursor at the end of its text.
- **The scroll position is always remembered**, including across app restarts.
  - The position is saved as an **anchor**: the first visible row (its list index and item index) plus how many pixels of that row are scrolled past. A raw pixel offset would drift when text wraps differently, for example after rotating the phone or switching to another device's file.
  - It is stored in `shared_preferences`, keyed by the file's URI. It is written when a scroll ends (debounced) and when the app goes to `paused`.
  - It is restored by jumping to the anchor once the document has loaded and the first frame has been laid out, without animation. If the anchor no longer exists (the list or items were deleted), the closest earlier row is used instead.
  - When the file is reloaded because it changed outside the app (§8), the current position is kept by anchoring to the same row. The view never jumps to the top.
  - Leaving for Settings and coming back keeps the position, because the home page stays alive in the navigation stack.
- **Implementation:** rows have different heights (text wraps), and a plain `ListView` cannot jump to a row by index. The plan is to use `super_sliver_list` (`SuperListView` + `ListController`). It can jump to an item by index and alignment, it reports which rows are visible (that is how the anchor is saved), and it estimates row heights well, so jumps are accurate.
  - Keeping the focused item visible also goes through it: after an operation moves focus, `ListController.animateToItem` / `jumpToItem` brings the row into view.

### State changes
- **Tap** the state icon to cycle NEW → DONE → FAILED → NEW.
- Icons: an empty checkbox for NEW, a checkmark for DONE, a cross for FAILED.
- DONE and FAILED items have muted or strike-through text. It stays fully readable and editable.

---

## 4. List header and footer

Each list is laid out like this:

```
[list name — inline editable text field]  [⋯]     ← header
[icon] item …                             [+]
[icon] item …                             [+]
                           Total: 1,317.83         ← footer (only if the list has prices)
```

- **Total line (footer):** shown **after the list's last item**, right-aligned. It displays `listTotal` (§2), the sum of quantity × price over the DONE items.
  - **It must never move the content the user is looking at or editing.** For that reason it sits below the items, not between the name and the items:
    - When it appears or disappears (the first price is typed, or the last price is removed), only content *below* the list moves. The focused item and everything above it stay in place.
    - The footer always has the same height: one line, `maxLines: 1`, numbers in tabular figures. When the value changes, the layout does not move at all.
  - It is shown only when at least one item in the list (in any state) has a price. Lists without prices stay uncluttered, and a shopping list shows `Total: 0` before anything is checked off.
  - It updates live as items are checked off or edited.
  - Formatting follows the configured locale (§7) through `intl`'s `NumberFormat.decimalPattern(locale)`:
    - The **thousands separator** and the decimal separator come from the locale: `1,317.83` in English, `1.317,83` in German, `1 317,83` in French or Hungarian.
    - The number of decimal places is the largest used by the list's prices, so usually 2. Rounding is half-up and only affects the display; the sum itself is kept exact.
    - Negative totals use the locale's minus sign.
    - No currency symbol is shown.

- **Renaming:** the name is a single-line text field styled as a heading. **Tap it to edit it directly.** There is no Rename button or dialog.
  - Pressing Enter (`textInputAction: next`) commits the name and moves focus to the start of the list's first item.
  - Line breaks in pasted text are replaced with spaces.
  - An empty name is allowed and is written as `# `.
  - The new name is saved through the normal autosave.
- The **`⋯` menu** contains:

| Entry | Action |
|---|---|
| **Reset** | Set every item in the list to NEW. Quantities are kept. Shows a snackbar with Undo. |
| **Copy list** | Copy the list to the clipboard: `# name`, then the items (empty items are skipped), using the format rule from §6. If all items are NEW, each line is `- text`; otherwise the backing format is used. Quantities are part of the text, so they are kept. The copied text can be pasted back in as-is. |
| **Delete done** | Remove every **DONE** item from the list. FAILED items are kept. |
| **Delete list** | Confirmation dialog ("Delete list "X" and its N items?"). If it was the only list, it is replaced by an empty `TODO` list. |

---

## 5. Pasting from the clipboard

Pasting only happens **inside an item's text field**. There is no separate Paste button. Two paths are covered:
- The field's context-menu **Paste**, through a custom `contextMenuBuilder`.
- IME clipboard inserts, such as the Gboard clipboard strip. The controller listener sees these as an insert of more than one character.

Pasting into a **list name** field just inserts the text on one line (line breaks become spaces).

### Rules
1. **One line with no recognized prefix** (`# `, an item prefix, `- `, `* `): inserted at the cursor as normal text. A quantity like `3x eggs` is just text, so it is inserted as-is.
2. **Anything else** (several lines, or a line with a prefix): parsed with the parser from §1 in *fragment mode*. That gives:
   - *loose items*: items before any `# ` header, each with its parsed state. Plain lines become NEW. Quantities stay in the text.
   - *lists*: zero or more `# name` blocks, each with its items.
3. Inserting at the cursor in item `I` of list `L` works like a text editor:
   - Split `I` at the cursor into `before` (keeps `I`'s state) and `after` (NEW).
   - If `before` is empty, drop it. In practice, pasting into an empty item replaces it.
   - Insert the loose items after `before`, in order.
   - **If no lists were pasted:** `after` (if non-empty) comes right after the loose items, followed by the rest of `L`.
   - **If one or more lists were pasted:** `L` ends after the loose items. The pasted lists are inserted after `L`. The rest of `L` (`after` plus every item below the cursor) is appended to the **last pasted list**. This matches what Enter on an empty line does.
   - Run `normalize()`. The cursor goes to the end of the last pasted item.
4. A paste counts as one operation, so a single Undo reverts it (if undo gets implemented, see §11).

---

## 6. Selection mode

- **Long-press a state icon** to enter selection mode with that item selected.
- In selection mode:
  - Tapping a state icon or a row toggles selection. It does not change the item's state.
  - The app bar becomes a contextual bar: `N selected`, **Copy**, **Delete**, **Close**.
  - The + buttons are hidden.
  - The Android back button leaves selection mode.
  - Items from several lists can be selected at once.
- **Delete selected:** removes all selected items (with a confirmation if N > 1), normalizes, and leaves selection mode.
- **Copy selected:** copies the items in document order, one per line, with a trailing newline.
  - If **every** selected item is NEW: each line is `- text`.
  - Otherwise: each line uses the backing format (`- [ ] `, `- [x] `, `- [x] FAILED `).
  - Quantities are part of the text and are copied with it. A `1x ` prefix is never written out.
  - A snackbar shows "Copied N items". Selection mode stays active.

This formatting rule lives in `lib/model/clipboard_format.dart` and is shared with **Copy list** (§4).

---

## 7. Settings

Settings opens from the overflow menu in the app bar (⋮ → **Settings**). All settings are stored per device in `shared_preferences`, not in the Markdown file.

| Setting | Options | Default |
|---|---|---|
| **File** | **Change file**: open an existing file or create a new one (§8) | — |
| **Locale** | **System default (`<current>`)**, or a searchable list of the locales `intl` supports (for example `en_US`, `de_DE`, `hu_HU`) | System default |

- The locale controls how numbers are read (decimal and thousands separators, §2) and how the total is formatted (§4). The app's interface stays in English for now.
- **System default** keeps following the system. The app listens to `WidgetsBindingObserver.didChangeLocales`, so changing the phone's language or region updates parsing and totals immediately.
- Changing the locale recalculates every total right away. The file is not touched, because item text is never reformatted.

---

## 8. Storage and Syncthing

### Picking the file
The Android **Storage Access Framework (SAF)** is used through a small Kotlin platform channel, `MethodChannel('hu.parditka.andys_grocery_list/saf')`:
- `openDocument()`: `ACTION_OPEN_DOCUMENT` (mime `text/markdown` / `text/*`). Picks an existing `.md` file.
- `createDocument(name)`: `ACTION_CREATE_DOCUMENT`. Creates a new `todo.md`.
- `takePersistableUriPermission` (read and write), so access survives restarts.
- `read(uri) -> String` and `write(uri, String)`. Writing opens the file with mode **`"wt"`**, because plain `"w"` doesn't truncate the file on some providers.
- `lastModified(uri)`, read from a `DocumentsContract` query.

The URI is stored in `shared_preferences`. On first launch, or if the permission is lost, a welcome screen offers **Open existing file** and **Create new file**. Settings has **Change file** (§7).

*(Considered and rejected: `MANAGE_EXTERNAL_STORAGE` + `dart:io`. It is a sensitive permission that Play restricts, and SAF can reach Syncthing folders without it.)*

### Saving
- Autosave about 500 ms after the last change.
- Save immediately when the app goes to `paused` / `inactive`.
- Skip the write if the serialized content is the same as the last content read or written.

### External changes (Syncthing)
- Keep `lastKnownContent` and `lastModified` after every read and write.
- On `AppLifecycleState.resumed`, and every ~5 s while the app is in the foreground, check `lastModified`. If it changed:
  - **No unsaved local edits:** reload. Keep focus on the same item if a matching one still exists; otherwise drop focus.
  - **Unsaved local edits:** the last write wins. Syncthing makes its own `.sync-conflict` copies when both sides changed. A 3-way merge per line could come later.
- Before every write, check `lastModified` again. If the file changed since the last read, reload it and show a "File changed externally — reloaded" snackbar.

---

## 9. Architecture

```
lib/
  main.dart
  app.dart                     # MaterialApp (onGenerateTitle → app_name.dart), theme, routes
  app_name.dart                # "Andy's Grocery List" / "Andris Bevlistája" by system language
  model/
    todo_document.dart         # immutable model classes
    markdown_codec.dart        # parse (file + fragment mode) / serialize
    number_parser.dart         # NumberContext from locale; locale-aware "natural"
                               # number token parsing (§2)
    amounts.dart               # parseQuantity, incrementQuantity, parsePrice,
                               # lineTotal, listTotal, formatTotal
    operations.dart            # split, merge, newList, mergeLists, paste, reset,
                               # deleteDone, deleteItems, deleteList, rename,
                               # incrementQuantity, normalize
    clipboard_format.dart      # copy formatting (selection + list)
  state/
    document_controller.dart   # ChangeNotifier: document, apply ops, autosave, reload
    selection_controller.dart
    settings_controller.dart   # effective locale; follows system locale changes
  storage/
    saf_storage.dart           # Dart side of the platform channel
    settings.dart              # shared_preferences (file URI, locale, scroll anchor per file)
  ui/
    home_page.dart             # app bar, SuperListView, bottom space, selection bar
    scroll_memory.dart         # save/restore the scroll anchor
    list_header.dart           # inline-editable name + ⋯ menu
    list_footer.dart           # total line (fixed height)
    item_row.dart              # icon + sentinel-backed TextField + [+] button
    sentinel_controller.dart   # TextEditingController: sentinel trick, paste
                               # detection, quantity/price highlighting
    dialogs.dart               # confirm delete
    welcome_page.dart          # pick/create file
    settings_page.dart         # change file, locale picker
android/app/src/main/kotlin/hu/parditka/andys_grocery_list/MainActivity.kt   # SAF channel
```

- State management: a plain `ChangeNotifier` + `ListenableBuilder` (or `provider`). Keep dependencies few.
- Packages: `shared_preferences`, `super_sliver_list` (jump to a row by index, visible range), `decimal` (exact arithmetic), `intl` (locale number symbols and formatting), `uuid` (or a counter), `flutter_lints`.

---

## 10. Testing

- **Codec unit tests:**
  - Every state round-trips.
  - FAILED takes precedence over DONE; `[X]` is accepted; CRLF works.
  - Items before the first header, in file mode and in fragment mode.
  - Lenient lines; an empty file.
  - Empty items round-trip, and a header with no items gets one empty item.
  - `1x `, `1.0x ` and `1,00x ` are removed when writing; `3x ` and `1.5x ` are kept.
- **Number parser unit tests**, run with `en_US`, `de_DE`, `fr_FR`, `hu_HU` and `de_CH`:
  - Both separators: `1.234,50` and `1,234.50` → 1234.5 in every locale.
  - Repeated separator: `1.234.567` and `1,234,567` → 1234567.
  - Single separator: `2,49` and `1.5` are decimals in every locale. `1,234` → 1234 in `en_US` but 1.234 in `de_DE`, and the other way round for `1.234`.
  - Other grouping: `1'234.50`, and `1 234,50` with U+00A0 or U+202F. `1 234` with a regular space is not one number.
  - Malformed: `12.34.5`, `1,23,456`, `.5`, `5.` are rejected.
  - Signs: `-5`, `−5`.
- **Amount unit tests:**
  - Quantity parsing: `3x Milk`, `1,5x`, `0.25x`, `Milk`, `2x`, `0x`, `.5x` (not a quantity), `12x  spaced`.
  - Increment: `Milk` → `2x Milk`, `9x` → `10x`, `1,5x` → `2,5x`, `0.25x` → `1.25x`, an empty item → `2x `. The returned selection covers exactly the number.
  - Price parsing: `Milk 1.29`, `Bread 2,49`, `Machine 1.299,00`, `Coupon -1`, `5`, `3x 2`, `2x` (no price), `Room 12b`, `5€` (no price), `Milk  -0.5`, `Milk 1.29 ` (trailing whitespace), `Milk 1.29 .` (no price).
  - Totals: only DONE items count; quantity × price; negatives; exact decimals (`3 × 0.1 = 0.3`); a list with no prices → no total line.
  - Total formatting per locale: thousands separator, decimal separator and minus sign; the number of decimal places follows the list's prices; rounding half-up.
- **Operation unit tests:**
  - Every row in §3.
  - The non-empty-list invariant after every operation.
  - Merging lists when the previous list has only one empty item.
  - Enter on the only (empty) item of a list; deleting the last item; deleting the last list.
  - Reset keeps quantities.
- **Paste unit tests:**
  - A plain single line; multi-line plain text; lines with state prefixes and quantities.
  - A fragment containing lists, pasted into the middle of a list: the remainder moves to the last pasted list.
  - Pasting into an empty item.
- **Clipboard format unit tests:**
  - All NEW → `- ` prefix; mixed → backing format.
  - Copy list includes `# name` and skips empty items.
- **Widget tests:**
  - Enter and Backspace through the sentinel controller.
  - The + button increments, focuses the field and selects the number, and repeated + presses still work.
  - The total line updates when an item with a price is checked off.
  - Typing the first price into a list doesn't move the focused item (the footer appears below it).
  - Tapping the list name to edit it, and Enter moving focus to the first item.
  - Long-press entering selection mode.
  - The `⋯` menu actions and the confirm dialogs.
  - Changing the locale in Settings re-formats the totals without changing the file.
  - The last item can be scrolled to the top of the viewport, with the keyboard open and closed.
  - The scroll position is restored after a restart and kept across an external reload. A deleted anchor row falls back to the closest earlier row.
- **Manual tests on a real device** with Gboard and SwiftKey. They differ in how they handle Backspace, Enter, the clipboard and replacing a selection.

---

## 11. Milestones

1. `flutter create --org hu.parditka --project-name andys_grocery_list --platforms=android .` project (§0), localized app label (en + hu), lints, model + codec + locale-aware number parser + amount helpers (quantity, price, totals), with tests.
2. Operations (including paste, increment and normalize), with tests.
3. Item row with the sentinel controller. Enter, Backspace and paste working on a device. `SuperListView` with bottom space, and the focused item kept in view.
4. The + button: increment, focus, select the number. Highlight the quantity and price.
5. List header (inline name editing) and footer (total line), and the `⋯` menu (reset, copy list, delete done, delete list).
6. Selection mode: copy and delete.
7. SAF platform channel, welcome screen, autosave, reload on resume or external change. Saving and restoring the scroll position.
8. Settings page: change file, locale (system default + picker).
9. Polish: light and dark themes, keeping the focused item visible, snackbars, app icon.
10. Optional: undo/redo stack (cheap, since operations are pure), decrementing the quantity, drag to reorder, 3-way merge on conflicts, localizing the app's interface.

---

## 12. Decisions log

- Splitting an item in the middle: the second part becomes **NEW**.
- Delete done removes only **DONE** items. FAILED items stay.
- Enter on an empty item: the items below **move into the new list**.
- A list is never empty. When it would have no items, **one regular empty item** is added, saved to the file like any other.
- List names are edited **inline by tapping them**. There is no Rename button.
- Paste happens only **inside an item's text field**. There is no Paste button.
- A pasted fragment that contains lists works like a text editor: the rest of the current list follows the last pasted list.
- The `⋯` menu holds Reset, Copy list, Delete done and Delete list.
- The quantity `<n>x ` is part of the item text. It can be a decimal. A quantity of exactly 1 is implied and gets removed. The **+** button adds 1 and selects the number.
- The unit price is a number at the end of the item text, preceded by whitespace (or the whole text). It can be a decimal and can be negative.
- Numbers are parsed "naturally" according to the configurable **locale** (default: the system locale). `.` and `,` both work as the decimal point, and thousands separators are understood. Totals are displayed with the locale's thousands and decimal separators.
- **No currency**: prices and totals are plain numbers.
- The scroll position is always remembered (per file, across restarts and external reloads) as a row anchor. Below the last item there is about one viewport of blank space, so the last item can be scrolled to the top.
- The list total is Σ quantity × price over the **DONE** items. It is shown **after the list's last item**, so it never moves the items being edited. It is shown whenever the list contains any price, and is never written to the file.

---

## 13. Open questions

1. **Numbers at the end that aren't prices** (`Bus 42`, `Gate 7`): should they count as prices, or should there be an escape? One option is to count a price only when it has decimals; another is a marker character.
