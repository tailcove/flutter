import 'storage_stub.dart' if (dart.library.io) 'storage_io.dart' as platform;

/// Keeps the queue of unsent lines between launches, as one JSON string.
abstract class TailcoveStorage {
  /// The stored queue, or null when there is none.
  Future<String?> read();

  /// Stores the queue; null removes it.
  Future<void> write(String? value);

  /// A file in the app's support directory (path_provider). Nothing is kept where there is no file system (web).
  static TailcoveStorage applicationSupport() => platform.applicationSupportStorage();
}

/// Keeps the queue in memory: for tests, or where nothing should touch the disk.
class MemoryTailcoveStorage implements TailcoveStorage {
  MemoryTailcoveStorage([this.value]);

  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? value) async => this.value = value;
}
