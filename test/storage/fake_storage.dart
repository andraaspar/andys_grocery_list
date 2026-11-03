import 'package:andys_grocery_list/storage/saf_storage.dart';

/// An in-memory [DocumentStorage]. Its clock only moves when a file is
/// written, through the app or through [externalWrite].
class FakeStorage implements DocumentStorage {
  FakeStorage([Map<String, String>? files]) {
    files?.forEach(externalWrite);
  }

  final files = <String, String>{};
  final modified = <String, int>{};
  final permitted = <String>{};
  final writes = <String>[];
  int _clock = 1000;

  /// Whether [lastModified] reports times (some providers do not).
  bool reportsModified = true;

  /// What the pickers return next.
  String? nextOpen;
  String? nextCreate;

  /// Simulates Syncthing (or anyone else) changing the file.
  void externalWrite(String uri, String content) {
    files[uri] = content;
    modified[uri] = _clock += 1000;
    permitted.add(uri);
  }

  @override
  Future<String?> openDocument() async => nextOpen;

  @override
  Future<String?> createDocument(String name) async {
    final uri = nextCreate;
    if (uri != null) externalWrite(uri, '');
    return uri;
  }

  @override
  Future<bool> hasPermission(String uri) async => permitted.contains(uri);

  @override
  Future<String> read(String uri) async => files[uri]!;

  @override
  Future<void> write(String uri, String content) async {
    writes.add(content);
    files[uri] = content;
    modified[uri] = _clock += 1000;
  }

  @override
  Future<int?> lastModified(String uri) async =>
      reportsModified ? modified[uri] : null;

  @override
  Future<String?> displayName(String uri) async =>
      files.containsKey(uri) && permitted.contains(uri)
      ? uri.substring(uri.lastIndexOf('/') + 1)
      : null;

  final released = <String>[];

  @override
  Future<void> releasePermission(String uri) async {
    released.add(uri);
    permitted.remove(uri);
  }
}
