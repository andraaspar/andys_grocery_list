# Andy's Grocery List

An Android grocery and TODO list app that keeps your lists in a plain
Markdown file. Hungarian-language devices show it as *Andris Bevlistája*.

Because the data is an ordinary `.md` file that you pick, you can keep it
in a synced folder (Nextcloud, Syncthing, Google Drive, …), edit it on a
computer, and the app picks up the changes when it returns to the
foreground and every few seconds while it is open.

## Features

- **Markdown storage** – one file holds any number of lists. Each list is a
  `#` header followed by task-list items:

  ```markdown
  # Groceries
  - [ ] 2x Milk 1.29
  - [x] Bread 0.99
  - [x] FAILED Avocado

  # Hardware store
  - [ ] Light bulbs
  ```

- **Three item states** – tap a box to cycle *new → done → failed*.
- **Quick entry** – Enter adds an item, Enter on an empty item starts a new
  list, Backspace at the start of an item joins it to the one above.
  Pasting several lines adds many items at once.
- **Counts and prices** – the + button counts items up (`Milk` →
  `2x Milk`). End an item with a price and the done items add up to a total
  under each list, using the number format of your chosen locale.
- **Selection and reordering** – long-press to select items; reorder mode
  lets you drag items and whole lists around.
- **List actions** – reset, copy or delete a list; deletes can be undone.
- **Files** – open an existing file or create a new one through the system
  file picker, and switch between recently used files from the title bar.
- **Settings** – number format locale, spacing and text size. Light and dark
  themes follow the system.

## Building

The app is written in [Flutter](https://flutter.dev) and currently targets
Android only.

### Requirements

- Flutter SDK with Dart `^3.13.7` (see `pubspec.yaml`)
- Android SDK, with `flutter doctor` reporting the Android toolchain as OK
- An Android device or emulator for running it

### Get the dependencies

```sh
flutter pub get
```

### Run in debug mode

```sh
flutter devices        # find your device or emulator
flutter run            # or: flutter run -d <device-id>
```

### Build an APK

```sh
flutter build apk --release
# → build/app/outputs/flutter-apk/app-release.apk
```

Smaller, per-architecture APKs:

```sh
flutter build apk --release --split-per-abi
```

Install the result on a connected device with:

```sh
flutter install
# or: adb install build/app/outputs/flutter-apk/app-release.apk
```

### Build an App Bundle (for Google Play)

```sh
flutter build appbundle --release
# → build/app/outputs/bundle/release/app-release.aab
```

> **Signing:** release builds are currently signed with the debug key (see
> `android/app/build.gradle.kts`). To publish, set up your own keystore as
> described in Flutter's
> [Android deployment guide](https://docs.flutter.dev/deployment/android#sign-the-app).

### Tests and analysis

```sh
flutter test
flutter analyze
```

### Launcher icon

The launcher icon is generated from a description in code. After changing
it, regenerate the Android resources with:

```sh
python3 tool/generate_launcher_icon.py
```

Its colours and tile geometry are mirrored in `lib/ui/theme.dart` and
`lib/ui/tiles_logo.dart`; keep them in sync.

## Project layout

| Path           | Contents                                                  |
| -------------- | --------------------------------------------------------- |
| `lib/model`    | Document model, Markdown codec, amount and price parsing  |
| `lib/state`    | Controllers for the document, selection and settings      |
| `lib/storage`  | Storage Access Framework bridge and saved settings        |
| `lib/ui`       | Pages and widgets                                         |
| `android`      | Android host project, including the SAF channel in `MainActivity.kt` |
| `test`         | Unit and widget tests                                     |
| `tool`         | Helper scripts                                            |

## License

[MIT](LICENSE) © 2026 András Parditka
