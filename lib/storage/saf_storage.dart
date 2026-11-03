import 'package:flutter/services.dart';

/// Access to the Markdown file (plan §8). [SafStorage] is the real one; tests
/// use a fake.
abstract class DocumentStorage {
  /// Lets the user pick an existing file. Returns its URI, or null if the
  /// picker was cancelled.
  Future<String?> openDocument();

  /// Lets the user create a new file. Returns its URI, or null if cancelled.
  Future<String?> createDocument(String name);

  /// Whether the app still holds read and write permission for [uri].
  Future<bool> hasPermission(String uri);

  Future<String> read(String uri);

  Future<void> write(String uri, String content);

  /// Milliseconds since the epoch, or null if the provider does not say.
  Future<int?> lastModified(String uri);
}

/// The Storage Access Framework, through the Kotlin channel in
/// `MainActivity.kt`.
class SafStorage implements DocumentStorage {
  const SafStorage();

  static const _channel = MethodChannel('hu.parditka.andys_grocery_list/saf');

  @override
  Future<String?> openDocument() =>
      _channel.invokeMethod<String>('openDocument');

  @override
  Future<String?> createDocument(String name) =>
      _channel.invokeMethod<String>('createDocument', {'name': name});

  @override
  Future<bool> hasPermission(String uri) async =>
      await _channel.invokeMethod<bool>('hasPermission', {'uri': uri}) ?? false;

  @override
  Future<String> read(String uri) async =>
      await _channel.invokeMethod<String>('read', {'uri': uri}) ?? '';

  @override
  Future<void> write(String uri, String content) =>
      _channel.invokeMethod<void>('write', {'uri': uri, 'content': content});

  @override
  Future<int?> lastModified(String uri) =>
      _channel.invokeMethod<int>('lastModified', {'uri': uri});
}
